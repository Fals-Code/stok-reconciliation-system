import { spawn, spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import process from "node:process";

const BASE_URL = process.env.CROSS_ADAPTER_SMOKE_URL ?? "http://127.0.0.1:3000";
const PORT = new URL(BASE_URL).port || "3000";
const EMAIL = process.env.MARKETPLACE_EXTERNAL_PARALLEL_EMAIL ?? process.env.CSV_IMPORT_SMOKE_EMAIL ?? "demo.admin@glowlab.invalid";
const TIMEOUT_MS = 30_000;
const PREFIX = "CONCURRENCY-CROSS-ADAPTER-V6";
const EFFECTIVE_AT = "2026-07-01T00:00:00Z";
let server;

function fail(message) { throw new Error(message); }
function assert(condition, message) { if (!condition) fail(message); }
function errorText(result) { return String(result?.payload?.message ?? result?.payload?.code ?? "").trim(); }
function literal(value) { return `'${String(value).replaceAll("'", "''")}'`; }

function resolvePassword(config) {
  const pwd = process.env.MARKETPLACE_EXTERNAL_PARALLEL_PASSWORD ?? config?.MARKETPLACE_EXTERNAL_PARALLEL_PASSWORD ?? process.env.CSV_IMPORT_SMOKE_PASSWORD ?? config?.CSV_IMPORT_SMOKE_PASSWORD ?? process.env.PARALLEL_TEST_PASSWORD ?? config?.PARALLEL_TEST_PASSWORD;
  if (!pwd || typeof pwd !== "string" || pwd.trim() === "") {
    fail("Password harness tidak ditemukan pada MARKETPLACE_EXTERNAL_PARALLEL_PASSWORD, CSV_IMPORT_SMOKE_PASSWORD, atau PARALLEL_TEST_PASSWORD.");
  }
  return pwd;
}

function validateUrl(rawUrl, name, config) {
  if (!rawUrl) fail(`${name} tidak ditemukan.`);
  let parsed;
  try { parsed = new URL(rawUrl); } catch { fail(`${name} tidak valid.`); }
  const hostname = parsed.hostname.replace(/^\[|\]$/g, "");
  const isLocal = hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1";
  const allowRemote = process.env.ALLOW_REMOTE_PARALLEL_TESTS === "true" || config?.ALLOW_REMOTE_PARALLEL_TESTS === "true";
  if (!isLocal && !allowRemote) {
    fail(`${name} non-local (${hostname}) ditolak secara default. Set ALLOW_REMOTE_PARALLEL_TESTS=true untuk mengizinkan testing remote.`);
  }
}

function dbContainer() {
  const result = spawnSync("docker", ["ps", "--format", "{{.Names}}"], { encoding: "utf8", windowsHide: true });
  if (result.status !== 0) fail("Docker Supabase lokal tidak tersedia.");
  const container = result.stdout.split(/\r?\n/).map((value) => value.trim()).find((value) => value.startsWith("supabase_db_"));
  if (!container) fail("Container database Supabase lokal tidak ditemukan.");
  return container;
}
function sqlJson(container, sql) {
  const result = spawnSync("docker", ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-t", "-A", "-q"], { input: sql, encoding: "utf8", windowsHide: true });
  if (result.status !== 0) fail(`Snapshot fixture gagal: ${result.stderr.slice(-300)}`);
  const line = result.stdout.split(/\r?\n/).map((value) => value.trim()).findLast((value) => value.startsWith("{") || value === "null");
  return line ? JSON.parse(line) : null;
}
function fixtureNames() {
  return { sku: `${PREFIX}-PRODUCT`, batch: `${PREFIX}-BATCH`, listing: `${PREFIX}-LISTING`, productKey: `${PREFIX}-PRODUCT-KEY`, batchKey: `${PREFIX}-BATCH-KEY`, receiptKey: `${PREFIX}-RECEIPT-KEY` };
}

async function env() {
  const raw = await readFile(".env.local", "utf8");
  return Object.fromEntries(raw.split(/\r?\n/).filter((line) => line && !line.startsWith("#") && line.includes("=")).map((line) => {
    const index = line.indexOf("=");
    return [line.slice(0, index), line.slice(index + 1).trim().replace(/^['\"]|['\"]$/g, "")];
  }));
}
async function waitReady() {
  for (let attempt = 0; attempt < 90; attempt += 1) {
    try { if ((await fetch(`${BASE_URL}/login`, { signal: AbortSignal.timeout(1_000) })).status === 200) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  fail("Next server tidak siap untuk harness cross-adapter.");
}
async function login(config) {
  validateUrl(config.NEXT_PUBLIC_SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL, "NEXT_PUBLIC_SUPABASE_URL", config);
  validateUrl(BASE_URL, "CROSS_ADAPTER_SMOKE_URL", config);
  const password = resolvePassword(config);
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password }), signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) fail(`Login Admin gagal (${response.status}).`);
  const body = await response.json();
  if (!body.access_token) fail("Login tidak menghasilkan sesi independen.");
  return body.access_token;
}
async function rest(config, token, path) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api" }, signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) fail(`Read snapshot gagal (${response.status}).`);
  return response.json();
}
async function rpc(config, token, name, body) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST", headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api", "Content-Type": "application/json" },
    body: JSON.stringify(body), signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const raw = await response.text(); let payload;
  try { payload = raw ? JSON.parse(raw) : null; } catch { payload = { message: raw }; }
  return { ok: response.ok, status: response.status, payload };
}
function fixture(container, organizationId, names) {
  return sqlJson(container, `select coalesce((select jsonb_build_object('productId', p.id, 'batchId', b.id, 'listing', l.external_listing_code)
    from catalog.products p join catalog.product_batches b on b.organization_id = p.organization_id and b.product_id = p.id
    join catalog.marketplace_listings l on l.organization_id = p.organization_id and l.external_listing_code = ${literal(names.listing)}
    join catalog.marketplace_single_listing_versions v on v.organization_id = l.organization_id and v.listing_id = l.id and v.status_code = 'ACTIVE'
    where p.organization_id = ${literal(organizationId)}::uuid and p.sku = ${literal(names.sku)} and b.batch_code = ${literal(names.batch)} limit 1), 'null'::jsonb);`);
}
async function ensureFixture(config, token, container, organizationId) {
  const names = fixtureNames(); let current = fixture(container, organizationId, names);
  if (current) return current;
  const product = await rpc(config, token, "create_product", { p_organization_id: organizationId, p_idempotency_key: names.productKey, p_sku: names.sku, p_name: "Fixture external identity concurrency", p_unit_code: "UNIT", p_description: "Fixture durable Issue #56.", p_note: "External identity concurrency fixture." });
  if (!product.ok || !product.payload?.productId) fail(`Create product fixture gagal: ${errorText(product)}`);
  const batch = await rpc(config, token, "create_product_batch", { p_organization_id: organizationId, p_idempotency_key: names.batchKey, p_product_id: product.payload.productId, p_batch_code: names.batch, p_expiry_date: "2028-01-01", p_manufactured_date: "2026-06-01", p_received_first_at: EFFECTIVE_AT, p_batch_kind_code: "STANDARD", p_note: "Fixture durable Issue #56." });
  if (!batch.ok || !batch.payload?.batchId) fail(`Create batch fixture gagal: ${errorText(batch)}`);
  const receipt = await rpc(config, token, "post_receipt", { p_organization_id: organizationId, p_idempotency_key: names.receiptKey, p_source_ref: `${PREFIX}-RECEIPT`, p_occurred_at: EFFECTIVE_AT, p_lines: [{ productId: product.payload.productId, batchId: batch.payload.batchId, quantity: 30, sourceLineRef: "FIXTURE-1" }], p_note: "Fixture stock Issue #56.", p_metadata: { source: "cross-adapter-parallel", version: 1 } });
  if (!receipt.ok) fail(`Receipt fixture gagal: ${errorText(receipt)}`);
  const draft = await rpc(config, token, "create_marketplace_listing_version_draft", { p_organization_id: organizationId, p_idempotency_key: `${PREFIX}-LISTING-DRAFT`, p_channel_code: "SHOPEE", p_external_listing_code: names.listing, p_display_name: "Listing external identity concurrency", p_listing_type_code: "SINGLE", p_effective_from: EFFECTIVE_AT, p_product_id: product.payload.productId, p_components: [], p_note: "Fixture Issue #56.", p_metadata: { source: "cross-adapter-parallel", version: 1 } });
  if (!draft.ok || draft.payload?.status !== "DRAFT_CREATED") fail(`Draft listing fixture gagal: ${errorText(draft)}`);
  const preview = await rpc(config, token, "preview_marketplace_listing_version_activation", { p_organization_id: organizationId, p_listing_id: draft.payload.listingId, p_version_id: draft.payload.versionId });
  if (!preview.ok || preview.payload?.eligible !== true || !preview.payload?.basisHash) fail(`Preview listing fixture gagal: ${errorText(preview)}`);
  const activation = await rpc(config, token, "activate_marketplace_listing_version", { p_organization_id: organizationId, p_idempotency_key: `${PREFIX}-LISTING-ACTIVATE`, p_listing_id: draft.payload.listingId, p_version_id: draft.payload.versionId, p_expected_row_version: Number(preview.payload.versionRowVersion), p_preview_basis_hash: preview.payload.basisHash, p_confirmation: true });
  if (!activation.ok || activation.payload?.status !== "ACTIVATED") fail(`Aktivasi listing fixture gagal: ${errorText(activation)}`);
  current = fixture(container, organizationId, names);
  if (!current) fail("Fixture external identity tidak terbentuk melalui RPC resmi.");
  return current;
}
function formAction(markup, marker) {
  const form = (markup.match(/<form\b[^>]*>[\s\S]*?<\/form>/gi) ?? []).find((candidate) => candidate.toLowerCase().includes(marker.toLowerCase()));
  if (!form) fail(`Form ${marker} tidak ditemukan.`);
  const action = form.match(/name="(\$ACTION_ID_[^"]+)"/)?.[1];
  if (!action) fail(`Action ${marker} tidak memiliki action id.`);
  return action;
}
function input(markup, name) { return markup.match(new RegExp(`<input[^>]+name="${name}"[^>]+value="([^"]*)"`, "i"))?.[1] ?? ""; }
async function html(token, path) {
  const response = await fetch(`${BASE_URL}${path}`, { headers: { Cookie: `glowlab_access_token=${token}` }, redirect: "manual", signal: AbortSignal.timeout(TIMEOUT_MS) });
  return { response, html: await response.text() };
}
async function action(token, path, markup, marker, fields) {
  const body = new FormData(); body.append(formAction(markup, marker), "");
  for (const [name, value] of Object.entries(fields)) body.append(name, value);
  const response = await fetch(`${BASE_URL}${path}`, {
    method: "POST", headers: { Cookie: `glowlab_access_token=${token}`, Origin: BASE_URL, Referer: `${BASE_URL}${path}` }, body, redirect: "manual", signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (![302, 303, 307, 308].includes(response.status)) fail(`Server action ${marker} gagal (${response.status}).`);
  return response.headers.get("location");
}
async function upload(token, csv, filename) {
  const landing = await html(token, "/marketplace/import");
  const location = await action(token, "/marketplace/import", landing.html, "Unggah untuk preview", { file: new File([csv], filename, { type: "text/csv" }) });
  if (!location) fail("Upload tidak mengarahkan ke job detail.");
  return new URL(location, BASE_URL).pathname;
}
async function commit(token, jobPath) {
  const detail = await html(token, jobPath);
  if (!detail.html.includes("Konfirmasi dan proses")) fail(`Job ${jobPath} tidak READY untuk commit.`);
  return action(token, jobPath, detail.html, "Konfirmasi dan proses", { jobId: jobPath.split("/").at(-1), commitKey: input(detail.html, "commitKey"), confirmation: "on" });
}
function csv(channel, listing, ref, quantity) {
  const header = "schema_version,channel_code,external_event_ref,external_order_ref,source_status,occurred_at,received_at,source_line_ref,external_listing_code,listing_quantity,event_type,source_title,source_sku,note";
  const line = `MARKETPLACE_RESERVATION_V1,${channel},${ref},${ref},READY_TO_SHIP,2026-07-26T09:00:00Z,2026-07-26T09:01:00Z,LINE-1,${listing},${quantity},ORDER,,,Cross adapter durable fixture`;
  return `${header}\r\n${line}\r\n`;
}
function reserveBody(org, channel, listing, ref, quantity, key) {
  return {
    p_organization_id: org, p_idempotency_key: key, p_channel_code: channel, p_event_ref: ref, p_order_ref: ref,
    p_source_status: "READY_TO_SHIP", p_occurred_at: "2026-07-26T09:00:00Z", p_received_at: "2026-07-26T09:01:00Z",
    p_lines: [{ sourceLineRef: "LINE-1", externalListingCode: listing, listingQuantity: quantity, sourceStatus: "READY_TO_SHIP" }],
    p_note: "Cross adapter durable fixture", p_raw_payload: { adapter: "SIMULATOR", volatile: key }, p_metadata: { adapter: "SIMULATOR" }, p_schema_version: 1,
  };
}
async function events(config, token, org, ref) {
  return rest(config, token, `marketplace_events?organization_id=eq.${org}&external_event_ref=eq.${encodeURIComponent(ref)}&select=event_id,order_id,event_type_code,transaction_id&limit=3`);
}
async function results(config, token, org, ref) {
  return rest(config, token, `import_event_result_read_model?organization_id=eq.${org}&external_event_ref=eq.${encodeURIComponent(ref)}&select=status_code,canonical_event_id,marketplace_order_id&order=created_at.asc`);
}

async function main() {
  const config = await env();
  const health = await fetch(`${BASE_URL}/login`, { signal: AbortSignal.timeout(1_000) }).catch(() => null);
  if (!health || health.status !== 200) { server = spawn(process.execPath, ["node_modules/next/dist/bin/next", "dev", "--hostname", "127.0.0.1", "--port", PORT], { stdio: "ignore", windowsHide: true }); await waitReady(); }
  const [csvToken, canonicalToken] = await Promise.all([login(config), login(config)]);
  const profile = (await rest(config, csvToken, "current_admin_profile?select=organization_id,role_code&limit=1"))[0];
  assert(profile?.organization_id && profile.role_code === "ADMIN", "Admin fixture resmi tidak tersedia.");
  const stableFixture = await ensureFixture(config, csvToken, dbContainer(), profile.organization_id);
  const listing = { channel_code: "SHOPEE", external_listing_code: stableFixture.listing };

  const identicalRef = `${PREFIX}-IDENTICAL`;
  const conflictRef = `${PREFIX}-CONFLICT`;
  const twoJobRef = `${PREFIX}-TWO-JOBS`;
  const existing = await Promise.all([events(config, csvToken, profile.organization_id, identicalRef), events(config, csvToken, profile.organization_id, conflictRef), events(config, csvToken, profile.organization_id, twoJobRef)]);
  if (existing.every((rows) => Array.isArray(rows) && rows.length === 1)) {
    const [identicalResults, twoJobResults] = await Promise.all([results(config, csvToken, profile.organization_id, identicalRef), results(config, csvToken, profile.organization_id, twoJobRef)]);
    assert(identicalResults.length >= 1 && twoJobResults.length >= 2, "Fixture durable tidak memiliki audit replay yang lengkap.");
    console.log("[PASS] run kedua menemukan tiga event immutable tunggal tanpa membuat job/event baru");
    console.log("Marketplace external-event parallel harness PASS (durable replay)");
    return;
  }
  assert(existing.every((rows) => Array.isArray(rows) && rows.length === 0), "Fixture cross-adapter berada pada state parsial; tidak aman untuk dilanjutkan.");

  const identicalJob = await upload(csvToken, csv(listing.channel_code, listing.external_listing_code, identicalRef, 1), "cross-adapter-identical.csv");
  const [csvIdentical, canonicalIdentical] = await Promise.all([
    commit(csvToken, identicalJob),
    rpc(config, canonicalToken, "reserve_marketplace_listing_event", reserveBody(profile.organization_id, listing.channel_code, listing.external_listing_code, identicalRef, 1, `${PREFIX}-DIRECT-IDENTICAL`)),
  ]);
  assert(csvIdentical && (canonicalIdentical.ok || errorText(canonicalIdentical) === "MARKETPLACE_EXTERNAL_EVENT_CONFLICT"), `Race identical tidak mengembalikan outcome canonical yang aman (${canonicalIdentical.ok ? "created" : errorText(canonicalIdentical)}).`);
  const identicalEvents = await events(config, csvToken, profile.organization_id, identicalRef); const identicalResults = await results(config, csvToken, profile.organization_id, identicalRef);
  assert(identicalEvents.length === 1 && identicalEvents[0].event_type_code === "RESERVE" && identicalEvents[0].transaction_id === null, "CSV versus canonical identical harus menghasilkan satu reserve stock-neutral.");
  assert(identicalResults.length === 1 && identicalResults[0].canonical_event_id === identicalEvents[0].event_id, "CSV identical race harus memiliki exact canonical audit linkage.");
  console.log("[PASS] CSV versus canonical identical menghasilkan satu event/reservation dan audit linkage exact");

  const conflictJob = await upload(csvToken, csv(listing.channel_code, listing.external_listing_code, conflictRef, 1), "cross-adapter-conflict.csv");
  const [, canonicalConflict] = await Promise.all([
    commit(csvToken, conflictJob),
    rpc(config, canonicalToken, "reserve_marketplace_listing_event", reserveBody(profile.organization_id, listing.channel_code, listing.external_listing_code, conflictRef, 2, `${PREFIX}-DIRECT-CONFLICT`)),
  ]);
  const conflictEvents = await events(config, csvToken, profile.organization_id, conflictRef);
  assert(conflictEvents.length === 1 && (canonicalConflict.ok || errorText(canonicalConflict) === "MARKETPLACE_EXTERNAL_EVENT_CONFLICT"), `Changed payload race tidak mengembalikan outcome canonical yang aman (${canonicalConflict.ok ? "created" : errorText(canonicalConflict)}).`);
  console.log("[PASS] changed payload lintas adapter menolak effect gabungan");

  const [jobA, jobB] = await Promise.all([
    upload(csvToken, csv(listing.channel_code, listing.external_listing_code, twoJobRef, 1), "cross-adapter-job-a.csv"),
    upload(canonicalToken, `${csv(listing.channel_code, listing.external_listing_code, twoJobRef, 1)}\r\n`, "cross-adapter-job-b.csv"),
  ]);
  await Promise.all([commit(csvToken, jobA), commit(canonicalToken, jobB)]);
  const twoJobEvents = await events(config, csvToken, profile.organization_id, twoJobRef); const twoJobResults = await results(config, csvToken, profile.organization_id, twoJobRef);
  assert(twoJobEvents.length === 1 && twoJobResults.length === 2, "dua CSV job harus memiliki satu effect canonical dan dua audit linkage.");
  console.log("[PASS] dua CSV job parallel memakai satu effect canonical dengan dua audit linkage");
  console.log("Marketplace external-event parallel harness PASS");
}

main().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => { if (server?.pid) spawnSync("taskkill", ["/PID", String(server.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" }); });
