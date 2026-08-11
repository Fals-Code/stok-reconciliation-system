import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { spawn, spawnSync } from "node:child_process";

const baseUrl = process.env.LEDGER_EXPLORER_SMOKE_BASE_URL ?? "http://127.0.0.1:3000";
const password = process.env.LEDGER_EXPLORER_SMOKE_PASSWORD ?? "LocalSmoke123!";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const results = [];
let env = {};
let accessToken = "";
let email = "";
let supabaseUrl = "";
let publishableKey = "";
let serviceKey = "";
let organizationId = "";
const fixtureTransactionIds = [];
const fixtureReversedIds = new Set();
const FIXTURE_SOURCE_PREFIX = "ledger-explorer-ui-smoke:pagination:v1:";
let ownedServer = null;
let serverOutput = "";

function check(name, condition, detail = "") {
  if (!condition) throw new Error(`${name}${detail ? `: ${detail}` : ""}`);
  results.push(name);
  console.log(`[PASS] ${name}${detail ? ` Ã¢â‚¬â€ ${detail}` : ""}`);
}

function run(command, args, input) {
  const result = spawnSync(command, args, { cwd: process.cwd(), input, encoding: "utf8", windowsHide: true, maxBuffer: 10 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} gagal (${result.status})\n${result.stdout}\n${result.stderr}`);
  return result.stdout ?? "";
}

async function loadEnv() {
  const raw = await readFile(".env.local", "utf8");
  env = Object.fromEntries(raw.split(/\r?\n/).filter((line) => line.trim() && !line.trimStart().startsWith("#")).map((line) => {
    const separator = line.indexOf("=");
    return [line.slice(0, separator).trim(), line.slice(separator + 1).trim().replace(/^['"]|['"]$/g, "")];
  }));
  supabaseUrl = String(env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321").replace(/\/$/, "");
  publishableKey = String(env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "");
  serviceKey = String(env.SUPABASE_SECRET_KEY ?? "");
  check("Local Supabase configuration exists", Boolean(publishableKey && serviceKey));
}

function resolveDbContainer() {
  return run("docker", ["ps", "--format", "{{.Names}}"]).split(/\r?\n/).find((name) => name.startsWith("supabase_db_"));
}

function runSql(sql, tuplesOnly = false) {
  const db = resolveDbContainer();
  if (!db) throw new Error("Container Supabase lokal tidak ditemukan.");
  const args = ["exec", "-i", db, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"];
  if (tuplesOnly) args.push("-t", "-A", "-q");
  return run("docker", args, sql);
}

function parseJsonLine(output) {
  const line = output.split(/\r?\n/).map((item) => item.trim()).findLast((item) => item.startsWith("{") || item.startsWith("["));
  if (!line) throw new Error(`SQL tidak mengembalikan JSON: ${output.slice(-2000)}`);
  return JSON.parse(line);
}

async function json(response) {
  const raw = await response.text();
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return raw; }
}

function apiHeaders(token = accessToken) {
  return { apikey: publishableKey, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api", "Content-Type": "application/json" };
}

async function login() {
  const admin = parseJsonLine(runSql(`select jsonb_build_object('email', lower(auth_user.email), 'userId', profile.user_id) from app.user_profiles profile join auth.users auth_user on auth_user.id = profile.user_id where profile.employee_code = 'DEMO-ADMIN' and profile.role_code = 'ADMIN' order by profile.is_active desc, profile.created_at asc limit 1;`));
  email = String(admin.email ?? "");
  check("Demo Admin fixture exists", email.includes("@") && UUID.test(String(admin.userId ?? "")));
  runSql(`update app.user_profiles set is_active = true where user_id = '${admin.userId}'::uuid;`);

  const passwordResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users/${admin.userId}`, { method: "PUT", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ password, email_confirm: true }) });
  check("Demo Admin password prepared", passwordResponse.ok);

  const tokenResponse = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: publishableKey, "Content-Type": "application/json" }, body: JSON.stringify({ email, password }) });
  const token = await json(tokenResponse);
  check("Admin login succeeds", tokenResponse.ok && Boolean(token?.access_token));
  accessToken = String(token.access_token);
}

async function restRows(resource, token = accessToken) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${resource}`, { headers: apiHeaders(token), cache: "no-store" });
  const payload = await json(response);
  if (!response.ok) throw new Error(`REST ${resource} gagal (${response.status}): ${JSON.stringify(payload)}`);
  return Array.isArray(payload) ? payload : [];
}

async function rpc(name, body) {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, { method: "POST", headers: apiHeaders(), body: JSON.stringify(body), cache: "no-store" });
  const payload = await json(response);
  if (!response.ok) throw new Error(`RPC ${name} gagal (${response.status}): ${JSON.stringify(payload)}`);
  return payload;
}

async function provisionReadFixture() {
  const profileRows = await restRows("current_admin_profile?select=*");
  organizationId = String(profileRows[0]?.organization_id ?? "");
  check("Admin profile has organization authority", UUID.test(organizationId));

  let rows = await restRows("ledger_explorer?select=*&order=ledger_seq.desc&limit=1000");
  const stableFixtureRows = rows.filter((row) => String(row.source_ref_snapshot ?? "").startsWith(FIXTURE_SOURCE_PREFIX));
  if (stableFixtureRows.length >= 12 && stableFixtureRows.some((row) => row.reversal_state === "FULLY_REVERSED")) return rows;

  const batches = await restRows(`product_batch_master?organization_id=eq.${encodeURIComponent(organizationId)}&batch_kind_code=eq.STANDARD&lifecycle_status_code=eq.ACTIVE&is_effectively_expired=eq.false&select=product_id,batch_id&order=expiry_date.asc,batch_code.asc&limit=2`);
  check("Temporary read fixture has active batches", batches.length > 0);
  for (let fixtureIndex = 1; fixtureIndex <= 6; fixtureIndex += 1) {
    const sourceRef = `${FIXTURE_SOURCE_PREFIX}${fixtureIndex}`;
    const existing = rows.find((row) => row.source_ref_snapshot === sourceRef);
    let transactionId = String(existing?.transaction_id ?? "");
    if (!transactionId) {
      const posted = await rpc("post_receipt", {
        p_organization_id: organizationId,
        p_idempotency_key: `ledger-explorer-ui-smoke:receipt:v1:${fixtureIndex}`,
        p_source_ref: sourceRef,
        p_occurred_at: "2026-01-01T00:00:00.000Z",
        p_lines: batches.map((batch, index) => ({ productId: batch.product_id, batchId: batch.batch_id, quantity: 1, sourceLineRef: `LEDGER-EXPLORER-SMOKE-V1-${fixtureIndex}-${index + 1}` })),
        p_note: "Durable Ledger Explorer UI smoke read fixture.",
        p_metadata: { source: "ledger-explorer-ui-smoke", fixtureVersion: 1, fixtureIndex, readOnly: true },
      });
      transactionId = String(posted?.transactionId ?? "");
      check("Stable read fixture receipt created", UUID.test(transactionId));
    }
    if (!fixtureTransactionIds.includes(transactionId)) fixtureTransactionIds.push(transactionId);
    const alreadyReversed = rows.some((row) => row.transaction_id === transactionId && (row.reversal_state === "FULLY_REVERSED" || row.reversal_state === "PARTIALLY_REVERSED"));
    if (alreadyReversed) {
      fixtureReversedIds.add(transactionId);
      continue;
    }
    const preview = await rpc("preview_stock_transaction_reversal", { p_organization_id: organizationId, p_original_transaction_id: transactionId });
    check("Stable read fixture reversal preview is eligible", preview?.eligible === true && typeof preview?.basisHash === "string");
    await rpc("reverse_stock_transaction", {
      p_organization_id: organizationId,
      p_idempotency_key: `ledger-explorer-ui-smoke:reversal:v1:${fixtureIndex}`,
      p_original_transaction_id: transactionId,
      p_preview_basis_hash: preview.basisHash,
      p_confirmation: true,
      p_note: "Durable Ledger Explorer UI smoke reversal.",
      p_metadata: { source: "ledger-explorer-ui-smoke", fixtureVersion: 1, fixtureIndex, readOnly: true },
    });
    fixtureReversedIds.add(transactionId);
  }
  rows = await restRows("ledger_explorer?select=*&order=ledger_seq.desc&limit=1000");
  check("Temporary read fixture is visible after exact reversal", rows.length >= 21);
  return rows;
}

function cookieHeader() {
  return `glowlab_access_token=${accessToken}`;
}

async function page(uri, allowNotFound = false) {
  const response = await fetch(uri, { headers: { Cookie: cookieHeader() }, redirect: "manual", cache: "no-store" });
  const html = await response.text();
  if (!response.ok && !(allowNotFound && response.status === 404)) throw new Error(`GET ${uri} gagal (${response.status}): ${html.slice(0, 1000)}`);
  return { html, status: response.status, uri: response.url || uri };
}

function contains(html, text) {
  return html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").toLowerCase().includes(text.toLowerCase());
}

function pagination(html) {
  return html.match(/<nav[^>]*data-testid="ledger-pagination"[^>]*>[\s\S]*?<\/nav>/)?.[0] ?? "";
}

function hrefForAriaLabel(html, label) {
  const tag = html.match(new RegExp(`<a\\b[^>]*aria-label="${label}"[^>]*>`, "g"))?.[0] ?? "";
  return tag.match(/href="([^"]*)"/)?.[1]?.replaceAll("&amp;", "&") ?? "";
}

function hrefForText(html, text) {
  const escaped = text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return html.match(new RegExp(`<a\\b[^>]*href="([^"]*)"[^>]*>\\s*${escaped}\\s*<\\/a>`))?.[1]?.replaceAll("&amp;", "&") ?? "";
}

function activePage(html, pageNumber) {
  return new RegExp(`<span[^>]*aria-current="page"[^>]*>\\s*${pageNumber}\\s*<\\/span>`).test(html);
}

function numericPageLabels(html) {
  return [...html.matchAll(/<a\b[^>]*aria-label="Halaman (\d+)"[^>]*>/g)].map((match) => Number(match[1]));
}

function disabledControl(html, label) {
  return [...html.matchAll(/<span\b[^>]*>/g)].some((tag) => tag[0].includes(`aria-label="${label}"`) && tag[0].includes('aria-disabled="true"'));
}

async function serverReady() {
  try { return (await fetch(`${baseUrl}/login`, { redirect: "manual" })).status === 200; } catch { return false; }
}

async function startServerIfNeeded() {
  if (await serverReady()) return;
  const uri = new URL(baseUrl);
  const nextCli = path.resolve(process.cwd(), "node_modules", "next", "dist", "bin", "next");
  ownedServer = spawn(process.execPath, [nextCli, "dev", "--hostname", uri.hostname, "--port", String(uri.port || 3000)], { cwd: process.cwd(), windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  ownedServer.stdout.on("data", (chunk) => { serverOutput = (serverOutput + chunk.toString()).slice(-20000); });
  ownedServer.stderr.on("data", (chunk) => { serverOutput = (serverOutput + chunk.toString()).slice(-20000); });
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    if (await serverReady()) return;
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`Next.js server tidak siap.\n${serverOutput}`);
}

function stopServer() {
  if (!ownedServer) return;
  if (process.platform === "win32") spawnSync("taskkill", ["/PID", String(ownedServer.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
  else ownedServer.kill("SIGTERM");
}

async function main() {
  const liveFilterSource = await readFile(
    path.resolve(
      process.cwd(),
      "src",
      "app",
      "ledger",
      "ledger-filter-controls.tsx",
    ),
    "utf8",
  );

  const sharedLiveFilterSource = await readFile(
    path.resolve(
      process.cwd(),
      "src",
      "components",
      "ui",
      "live-query-controls.tsx",
    ),
    "utf8",
  );

  check(
    "Ledger live search uses debounced URL replacement",
    liveFilterSource.includes('"use client"') &&
      sharedLiveFilterSource.includes("useSearchParams") &&
      sharedLiveFilterSource.includes("window.setTimeout") &&
      sharedLiveFilterSource.includes("debounceMs = 300") &&
      sharedLiveFilterSource.includes("router.replace") &&
      !sharedLiveFilterSource.includes("router.push"),
  );

  check(
    "Live search resets keyset pagination before filtering",
    sharedLiveFilterSource.includes('resetKeys = ["cursor", "direction", "page"]') &&
      sharedLiveFilterSource.includes('"cursor"') &&
      sharedLiveFilterSource.includes('"direction"') &&
      sharedLiveFilterSource.includes('"page"') &&
      sharedLiveFilterSource.includes("params.delete(name)"),
  );

  check(
    "Live search preserves exact product and batch context",
    liveFilterSource.includes('contextKeys={["productId", "batchId"]}') &&
      liveFilterSource.includes('"productId"') &&
      liveFilterSource.includes('"batchId"') &&
      sharedLiveFilterSource.includes('type="hidden"'),
  );

  check(
    "Ledger live filters contain no domain or network logic",
    !liveFilterSource.includes("@/lib/") &&
      !liveFilterSource.includes("fetch("),
  );
  await loadEnv();
  await login();
  await startServerIfNeeded();

  const baseline = parseJsonLine(runSql(`select jsonb_build_object('batch',(select coalesce(jsonb_agg(jsonb_build_object('organization_id',balance.organization_id,'batch_id',balance.batch_id,'product_id',balance.product_id,'sellable_qty',balance.sellable_qty,'quarantine_qty',balance.quarantine_qty,'damaged_qty',balance.damaged_qty) order by balance.organization_id,balance.batch_id), '[]'::jsonb) from inventory.stock_batch_balances balance), 'product',(select coalesce(jsonb_agg(jsonb_build_object('organization_id',position.organization_id,'product_id',position.product_id,'sellable_qty',position.sellable_qty,'quarantine_qty',position.quarantine_qty,'damaged_qty',position.damaged_qty,'reserved_qty',position.reserved_qty) order by position.organization_id,position.product_id), '[]'::jsonb) from inventory.stock_product_positions position), 'reservations',(select coalesce(jsonb_agg(jsonb_build_object('organization_id',reservation.organization_id,'id',reservation.id,'reserved_qty',reservation.reserved_qty,'consumed_qty',reservation.consumed_qty,'released_qty',reservation.released_qty,'status_code',reservation.status_code) order by reservation.organization_id,reservation.id), '[]'::jsonb) from inventory.stock_reservations reservation));`));
  const rows = await provisionReadFixture();
  check("Ledger page has durable movement data", rows.length > 0, `rows=${rows.length}`);
  const multi = rows.find((row, index) => rows.slice(index + 1).some((other) => other.transaction_id === row.transaction_id));
  check("Durable data includes a multi-entry transaction", Boolean(multi));
  const reversal = rows.find((row) => row.reversal_state === "REVERSAL" || row.reversal_state === "FULLY_REVERSED");

  const anonymous = await fetch(`${baseUrl}/ledger`, { redirect: "manual" });
  check("Anonymous ledger access redirects to login", [302, 303, 307, 308].includes(anonymous.status) && String(anonymous.headers.get("location") ?? "").includes("/login"));

  const ledgerUrl = `${baseUrl}/ledger`;
  const first = await page(ledgerUrl);
  check("Riwayat Stok renders", first.status === 200 && contains(first.html, "Riwayat Stok"));
  check("Desktop list renders operational movement fields", first.html.includes('data-testid="ledger-table"') && contains(first.html, "Waktu kejadian") && contains(first.html, "Waktu dicatat"));
  check("Riwayat Stok is read-only", !/<form[^>]*data-testid="ledger-filter-form"[^>]*action=/.test(first.html) && contains(first.html, "tidak dapat diubah atau dihapus"));
  check(
    "Ledger filters render as automatic URL controls",
    first.html.includes(
      'data-ui-live-query-controls',
    ) &&
      contains(
        first.html,
        "Hasil diperbarui otomatis",
      ) &&
      !contains(
        first.html,
        "Terapkan Filter",
      ),
  );
  const firstPagination = pagination(first.html);
  check("First page renders compact numeric pagination", activePage(firstPagination, 1) && contains(first.html, "20 perubahan per halaman") && !contains(firstPagination, "Lebih baru") && !contains(firstPagination, "Lebih lama"));
  check("First page disables previous pagination control", disabledControl(firstPagination, "Halaman sebelumnya"));
  const nextHref = hrefForAriaLabel(firstPagination, "Halaman 2");
  const nextUrl = new URL(nextHref, baseUrl);
  check("First page next target has keyset cursor and numeric page state", Boolean(nextHref) && nextUrl.searchParams.get("page") === "2" && nextUrl.searchParams.get("direction") === "next" && Boolean(nextUrl.searchParams.get("cursor")) && !nextUrl.searchParams.has("offset"));
  check("First page pagination exposes no total or fake numeric targets", !/\btotal\b/i.test(firstPagination) && numericPageLabels(firstPagination).join(",") === "2");
  const nextPage = await page(new URL(nextHref, baseUrl).toString());
  const nextPagination = pagination(nextPage.html);
  check("Second page keeps numeric active state", activePage(nextPagination, 2) && contains(nextPage.html, "Riwayat Stok"));
  const numberedDetailHref = nextPage.html.match(/href="(\/ledger\/[0-9a-f-]+\?[^\"]*page=2[^\"]*)"/)?.[1]?.replaceAll("&amp;", "&") ?? "";
  const numberedDetail = await page(new URL(numberedDetailHref, baseUrl).toString());
  check("Numbered page detail keeps page and keyset context", Boolean(numberedDetailHref) && new URL(numberedDetail.uri).searchParams.get("page") === "2" && contains(numberedDetail.html, "Detail Transaksi"));
  const numberedDetailReturn = new URL(hrefForText(numberedDetail.html, "Kembali ke Riwayat Stok"), baseUrl);
  check("Numbered detail back link keeps page and keyset context", numberedDetailReturn.searchParams.get("page") === "2" && numberedDetailReturn.searchParams.get("direction") === "next" && Boolean(numberedDetailReturn.searchParams.get("cursor")));
  const previousHref = hrefForAriaLabel(nextPagination, "Halaman 1");
  const previousUrl = new URL(previousHref, baseUrl);
  check("Second page prior target returns to cursor-free page one", Boolean(previousHref) && previousUrl.searchParams.get("page") === "1" && !previousUrl.searchParams.has("direction") && !previousUrl.searchParams.has("cursor") && !previousUrl.searchParams.has("offset"));
  const subsequentHref = hrefForAriaLabel(nextPagination, "Halaman 3");
  check("Second page only exposes adjacent numeric targets", numericPageLabels(nextPagination).every((pageNumber) => pageNumber === 1 || pageNumber === 3) && (!subsequentHref || (new URL(subsequentHref, baseUrl).searchParams.get("direction") === "next" && Boolean(new URL(subsequentHref, baseUrl).searchParams.get("cursor")))));
  const previousPage = await page(new URL(previousHref, baseUrl).toString());
  check("Previous keyset target returns to active page one", activePage(pagination(previousPage.html), 1) && previousPage.html.includes('data-testid="ledger-table"'));
  const refreshedNextPage = await page(nextPage.uri);
  check("Refreshing a numbered page preserves active page state", activePage(pagination(refreshedNextPage.html), 2));

  const filteredPage = await page(`${ledgerUrl}?occurredFrom=1970-01-01T00%3A00`);
  const filteredNextHref = hrefForAriaLabel(pagination(filteredPage.html), "Halaman 2");
  const filteredNextUrl = new URL(filteredNextHref, baseUrl);
  check("Filtered page target preserves filter and numeric keyset state", Boolean(filteredNextHref) && filteredNextUrl.searchParams.get("occurredFrom") === "1970-01-01T00:00" && filteredNextUrl.searchParams.get("page") === "2" && filteredNextUrl.searchParams.get("direction") === "next" && Boolean(filteredNextUrl.searchParams.get("cursor")));

  const invalidPage = await page(`${ledgerUrl}?page=invalid`);
  check("Invalid page safely renders active page one", activePage(pagination(invalidPage.html), 1) && new URL(hrefForAriaLabel(pagination(invalidPage.html), "Halaman 2"), baseUrl).searchParams.get("page") === "2");

  const cursorFreePage = await page(`${ledgerUrl}?page=2`);
  check("Cursor-free non-first page falls back to page one", activePage(pagination(cursorFreePage.html), 1) && new URL(hrefForAriaLabel(pagination(cursorFreePage.html), "Halaman 2"), baseUrl).searchParams.get("page") === "2");

  const cursorFreePreviousPage = await page(`${ledgerUrl}?page=2&direction=previous`);
  const cursorFreePreviousDetailHref = cursorFreePreviousPage.html.match(/href="(\/ledger\/[0-9a-f-]+\?[^\"]*)"/)?.[1]?.replaceAll("&amp;", "&") ?? "";
  const cursorFreePreviousDetailUrl = new URL(cursorFreePreviousDetailHref, baseUrl);
  check("Cursor-free backward state falls back without forwarding invalid context", activePage(pagination(cursorFreePreviousPage.html), 1) && cursorFreePreviousDetailUrl.searchParams.get("page") === "1" && !cursorFreePreviousDetailUrl.searchParams.has("cursor") && !cursorFreePreviousDetailUrl.searchParams.has("direction"));
  const cursorFreePreviousDetail = await page(cursorFreePreviousDetailUrl.toString());
  const cursorFreePreviousReturnUrl = new URL(hrefForText(cursorFreePreviousDetail.html, "Kembali ke Riwayat Stok"), baseUrl);
  check("Normalized detail return does not restore invalid keyset context", cursorFreePreviousReturnUrl.searchParams.get("page") === "1" && !cursorFreePreviousReturnUrl.searchParams.has("cursor") && !cursorFreePreviousReturnUrl.searchParams.has("direction"));

  const malformedCursorPage = await page(`${ledgerUrl}?page=2&cursor=abc&direction=previous`);
  check("Malformed keyset cursor falls back to page one", activePage(pagination(malformedCursorPage.html), 1));

  const sku = String(multi.product_sku_snapshot);
  const filterUrl = `${ledgerUrl}?productSku=${encodeURIComponent(sku)}`;
  const filtered = await page(filterUrl);
  check("Product/SKU filter returns matching movement", filtered.uri.includes("productSku=") && contains(filtered.html, sku));
  const refreshed = await page(filtered.uri);
  check("Filter survives refresh", refreshed.uri.includes("productSku=") && contains(refreshed.html, sku));

  const malformedDetail = await page(`${baseUrl}/ledger/${multi.transaction_id}?page=2&cursor=abc&direction=previous`);
  const malformedReturnUrl = new URL(hrefForText(malformedDetail.html, "Kembali ke Riwayat Stok"), baseUrl);
  check("Malformed detail context returns to canonical page one", malformedReturnUrl.searchParams.get("page") === "1" && !malformedReturnUrl.searchParams.has("cursor") && !malformedReturnUrl.searchParams.has("direction"));

  const contextualUrl = `${ledgerUrl}?productId=${encodeURIComponent(multi.product_id)}&batchId=${encodeURIComponent(multi.batch_id)}&sourceType=RECEIPT`;
  const contextual = await page(contextualUrl);
  check("Filter form preserves exact product and batch context", contextual.html.includes(`name="productId"`) && contextual.html.includes(`value="${multi.product_id}"`) && contextual.html.includes(`name="batchId"`) && contextual.html.includes(`value="${multi.batch_id}"`));
  check(
    "Ledger filters use operational transaction and source codes",
    contains(contextual.html, "Jenis Perubahan") &&
      contextual.html.includes('value="DISPOSAL"') &&
      contains(contextual.html, "Barang Rusak / Kedaluwarsa") &&
      !contextual.html.includes('value="DISPOSAL_DAMAGED"') &&
      !contextual.html.includes('value="DISPOSAL_EXPIRED"') &&
      contains(contextual.html, "Sumber transaksi") &&
      contextual.html.includes('name="sourceType"') &&
      contextual.html.includes('value="OPENING_BALANCE_CUTOVER"') &&
      contains(contextual.html, "Saldo Awal") &&
      !contextual.html.includes('value="OPENING_BALANCE"') &&
      contextual.html.includes('value="MANUAL_OUTBOUND"') &&
      contains(contextual.html, "Barang Keluar Manual") &&
      contextual.html.includes('value="RETURN_RECEIPT"') &&
      contains(contextual.html, "Penerimaan Retur"),
  );

  const detail = await page(`${baseUrl}/ledger/${multi.transaction_id}?productSku=${encodeURIComponent(sku)}`);
  check("Exact transaction detail opens", contains(detail.html, "Detail Transaksi") && contains(detail.html, "Dampak stok"));
  check("Multi-entry detail renders all rows", (detail.html.match(/data-testid=\"ledger-detail-entries\"/g) ?? []).length === 1 && contains(detail.html, String(multi.transaction_no)));
  check("Detail renders expected transaction evidence", contains(detail.html, "Waktu kejadian") && contains(detail.html, "Waktu dicatat") && contains(detail.html, "Alasan") && contains(detail.html, "Kanal / Sumber") && contains(detail.html, "Referensi sumber") && contains(detail.html, "Dilakukan oleh") && contains(detail.html, String(multi.product_sku_snapshot)) && contains(detail.html, String(multi.batch_code_snapshot)));

  const contextualDetail = await page(`${baseUrl}/ledger/${multi.transaction_id}?productId=${encodeURIComponent(multi.product_id)}&batchId=${encodeURIComponent(multi.batch_id)}&sourceType=RECEIPT`);
  check("Detail and back link retain exact filter context", contextualDetail.html.includes(`productId=${multi.product_id}`) && contextualDetail.html.includes(`batchId=${multi.batch_id}`) && contextualDetail.html.includes("sourceType=RECEIPT"));

  if (reversal) {
    const reversalPage = await page(`${baseUrl}/ledger/${reversal.transaction_id}`);
    check("Reversal detail exposes human linkage", contains(reversalPage.html, "Pembatalan untuk transaksi") || contains(reversalPage.html, "Transaksi ini telah dibatalkan."));
  } else {
    check("Reversal detail fixture is available", false, "Durable ledger has no reversal row");
  }

  const reversedMulti = rows.find((row, index) => row.reversal_state === "FULLY_REVERSED" && rows.slice(index + 1).some((other) => other.transaction_id === row.transaction_id));
  const relatedReversal = reversedMulti ? rows.find((row) => row.transaction_type_code === "REVERSAL" && row.source_ref_snapshot === reversedMulti.transaction_no) : null;
  check("Multi-entry reversal fixture has an exact related transaction", Boolean(reversedMulti && relatedReversal));
  if (reversedMulti && relatedReversal) {
    const reversedDetail = await page(`${baseUrl}/ledger/${reversedMulti.transaction_id}`);
    const relatedHref = new RegExp(`href="/ledger/${relatedReversal.transaction_id}"`, "g");
    check("Multi-entry reversal renders one human relationship", (reversedDetail.html.match(relatedHref) ?? []).length === 1);
  }

  const invalid = await page(`${baseUrl}/ledger/not-a-uuid`, true);
  check("Invalid transaction renders safe not-found", contains(invalid.html, "Transaksi tidak ditemukan atau tidak dapat diakses") && !contains(invalid.html, "Dampak stok"));

  const after = parseJsonLine(runSql(`select jsonb_build_object('batch',(select coalesce(jsonb_agg(jsonb_build_object('organization_id',balance.organization_id,'batch_id',balance.batch_id,'product_id',balance.product_id,'sellable_qty',balance.sellable_qty,'quarantine_qty',balance.quarantine_qty,'damaged_qty',balance.damaged_qty) order by balance.organization_id,balance.batch_id), '[]'::jsonb) from inventory.stock_batch_balances balance), 'product',(select coalesce(jsonb_agg(jsonb_build_object('organization_id',position.organization_id,'product_id',position.product_id,'sellable_qty',position.sellable_qty,'quarantine_qty',position.quarantine_qty,'damaged_qty',position.damaged_qty,'reserved_qty',position.reserved_qty) order by position.organization_id,position.product_id), '[]'::jsonb) from inventory.stock_product_positions position), 'reservations',(select coalesce(jsonb_agg(jsonb_build_object('organization_id',reservation.organization_id,'id',reservation.id,'reserved_qty',reservation.reserved_qty,'consumed_qty',reservation.consumed_qty,'released_qty',reservation.released_qty,'status_code',reservation.status_code) order by reservation.organization_id,reservation.id), '[]'::jsonb) from inventory.stock_reservations reservation));`));
  check("Read, filter, detail, and refresh preserve stock state", JSON.stringify(after) === JSON.stringify(baseline));
  console.log(`Ledger Explorer UI smoke PASS (${results.length} checks)`);
}

try {
  await main();
} catch (error) {
  console.error("Ledger Explorer UI smoke FAIL", error instanceof Error ? error.stack ?? error.message : String(error));
  if (serverOutput) console.error(serverOutput);
  process.exitCode = 1;
} finally {
  for (const fixtureTransactionId of fixtureTransactionIds) {
    if (!fixtureReversedIds.has(fixtureTransactionId)) {
      try {
        const preview = await rpc("preview_stock_transaction_reversal", { p_organization_id: organizationId, p_original_transaction_id: fixtureTransactionId });
        if (preview?.eligible === true) {
          await rpc("reverse_stock_transaction", {
            p_organization_id: organizationId,
            p_idempotency_key: `ledger-explorer-ui-smoke:recovery:${fixtureTransactionId}`,
            p_original_transaction_id: fixtureTransactionId,
            p_preview_basis_hash: preview.basisHash,
            p_confirmation: true,
            p_note: "Recovery reversal for Ledger Explorer UI smoke.",
            p_metadata: { source: "ledger-explorer-ui-smoke", temporary: true },
          });
          console.log("Fixture recovery reversal completed: " + fixtureTransactionId);
        }
      } catch (cleanupError) {
        console.error("Fixture recovery failed", cleanupError);
        process.exitCode = 1;
      }
    }
  }
  stopServer();
}
