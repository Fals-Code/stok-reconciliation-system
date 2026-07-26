import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";

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
let ownedServer = null;
let serverOutput = "";

function check(name, condition, detail = "") {
  if (!condition) throw new Error(`${name}${detail ? `: ${detail}` : ""}`);
  results.push(name);
  console.log(`[PASS] ${name}${detail ? ` — ${detail}` : ""}`);
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
  if (rows.length >= 21 && rows.some((row) => row.reversal_state === "REVERSAL" || row.reversal_state === "FULLY_REVERSED")) return rows;

  const batches = await restRows(`product_batch_master?organization_id=eq.${encodeURIComponent(organizationId)}&batch_kind_code=eq.STANDARD&lifecycle_status_code=eq.ACTIVE&is_effectively_expired=eq.false&select=product_id,batch_id&order=expiry_date.asc,batch_code.asc&limit=2`);
  check("Temporary read fixture has active batches", batches.length > 0);
  const fixtureCount = Math.max(1, Math.ceil((21 - rows.length) / Math.max(batches.length * 2, 1)));
  for (let fixtureIndex = 0; fixtureIndex < fixtureCount; fixtureIndex += 1) {
    const runId = randomUUID();
    const posted = await rpc("post_receipt", {
      p_organization_id: organizationId,
      p_idempotency_key: `ledger-explorer-ui-smoke:receipt:${runId}`,
      p_source_ref: `ledger-explorer-ui-smoke:${runId}`,
      p_occurred_at: new Date(Date.now() + fixtureIndex * 1000).toISOString(),
      p_lines: batches.map((batch, index) => ({ productId: batch.product_id, batchId: batch.batch_id, quantity: 1, sourceLineRef: `LEDGER-EXPLORER-SMOKE-${fixtureIndex + 1}-${index + 1}` })),
      p_note: "Temporary Ledger Explorer UI smoke receipt.",
      p_metadata: { source: "ledger-explorer-ui-smoke", runId, temporary: true },
    });
    const transactionId = String(posted?.transactionId ?? "");
    fixtureTransactionIds.push(transactionId);
    check("Temporary read fixture receipt created", UUID.test(transactionId));

    const preview = await rpc("preview_stock_transaction_reversal", { p_organization_id: organizationId, p_original_transaction_id: transactionId });
    check("Temporary read fixture reversal preview is eligible", preview?.eligible === true && typeof preview?.basisHash === "string");
    await rpc("reverse_stock_transaction", {
      p_organization_id: organizationId,
      p_idempotency_key: `ledger-explorer-ui-smoke:reversal:${runId}`,
      p_original_transaction_id: transactionId,
      p_preview_basis_hash: preview.basisHash,
      p_confirmation: true,
      p_note: "Temporary Ledger Explorer UI smoke reversal.",
      p_metadata: { source: "ledger-explorer-ui-smoke", runId, temporary: true },
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
  check("Ledger route renders", first.status === 200 && contains(first.html, "Ledger Explorer"));
  check("Ledger table renders movement", first.html.includes('data-testid="ledger-table"') && contains(first.html, "Occurred") && contains(first.html, "Recorded"));
  check("Ledger UI is read-only", !/<form[^>]*data-testid="ledger-filter-form"[^>]*action=/.test(first.html) && contains(first.html, "Read-only"));
  const nextHref = first.html.match(/href="([^"]*direction=next[^"]*)"/)?.[1]?.replaceAll("&amp;", "&");
  check("Ledger next pagination link is rendered", Boolean(nextHref));
  const nextPage = await page(new URL(nextHref, baseUrl).toString());
  check("Ledger next pagination keeps the result contract", contains(nextPage.html, "Lebih baru") && contains(nextPage.html, "Ledger Explorer"));
  const previousHref = nextPage.html.match(/href="([^"]*direction=previous[^"]*)"/)?.[1]?.replaceAll("&amp;", "&");
  check("Ledger previous pagination link is rendered", Boolean(previousHref));
  const previousPage = await page(new URL(previousHref, baseUrl).toString());
  check("Ledger previous pagination returns to a readable page", contains(previousPage.html, "Ledger Explorer") && previousPage.html.includes('data-testid="ledger-table"'));

  const sku = String(multi.product_sku_snapshot);
  const filterUrl = `${ledgerUrl}?productSku=${encodeURIComponent(sku)}`;
  const filtered = await page(filterUrl);
  check("Product/SKU filter returns matching movement", filtered.uri.includes("productSku=") && contains(filtered.html, sku));
  const refreshed = await page(filtered.uri);
  check("Filter survives refresh", refreshed.uri.includes("productSku=") && contains(refreshed.html, sku));

  const detail = await page(`${baseUrl}/ledger/${multi.transaction_id}?productSku=${encodeURIComponent(sku)}`);
  check("Exact transaction detail opens", contains(detail.html, "Exact transaction detail") && contains(detail.html, "Ledger entries"));
  check("Multi-entry detail renders all rows", (detail.html.match(/data-testid=\"ledger-detail-entries\"/g) ?? []).length === 1 && contains(detail.html, String(multi.transaction_no)));
  check("Detail shows occurred and recorded timestamps", contains(detail.html, "Occurred at") && contains(detail.html, "Recorded at"));

  if (reversal) {
    const reversalPage = await page(`${baseUrl}/ledger/${reversal.transaction_id}`);
    check("Reversal detail exposes linkage section", contains(reversalPage.html, "Original") && contains(reversalPage.html, "reversal"));
  } else {
    check("Reversal detail fixture is available", false, "Durable ledger has no reversal row");
  }

  const invalid = await page(`${baseUrl}/ledger/not-a-uuid`, true);
  check("Invalid transaction renders safe not-found", contains(invalid.html, "Transaction tidak ditemukan") && !contains(invalid.html, "Ledger entries"));

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
