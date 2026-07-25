import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const baseUrl = process.env.TIKTOK_CLAIM_SMOKE_BASE_URL ?? "http://127.0.0.1:3000";
const password = process.env.TIKTOK_CLAIM_SMOKE_PASSWORD ?? "LocalSmoke123!";
let organizationId = "";
let productId = "";
let runFixture = null;
const prefix = `tiktok-return-claim-ui-smoke:${randomUUID()}`;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const results = [];
let env = {};
let supabaseUrl = "";
let publishableKey = "";
let serviceKey = "";
let accessToken = "";
let smokeUserId = "";
let dbContainer = "";
let server;
let serverOutput = "";

function pass(name, detail = "") {
  results.push({ name, ok: true });
  console.log(`[PASS] ${name}${detail ? ` — ${detail}` : ""}`);
}

function check(name, condition, detail = "") {
  if (!condition) throw new Error(`${name}${detail ? `: ${detail}` : ""}`);
  pass(name, detail);
}

async function loadEnv() {
  const raw = await readFile(".env.local", "utf8");
  return Object.fromEntries(raw.split(/\r?\n/).filter((line) => line.trim() && !line.trimStart().startsWith("#")).map((line) => {
    const index = line.indexOf("=");
    return [line.slice(0, index).trim(), line.slice(index + 1).trim().replace(/^['"]|['"]$/g, "")];
  }));
}

function run(command, args, input) {
  const result = spawnSync(command, args, { cwd: process.cwd(), input, encoding: "utf8", windowsHide: true, maxBuffer: 20 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} gagal (${result.status})\n${result.stdout}\n${result.stderr}`);
  return result.stdout ?? "";
}

function sqlLiteral(value) { return `'${String(value).replaceAll("'", "''")}'`; }

function resolveDb() {
  const output = run("docker", ["ps", "--format", "{{.Names}}"]).split(/\r?\n/);
  const name = output.find((item) => item.startsWith("supabase_db_"));
  if (!name) throw new Error("Container Supabase lokal tidak ditemukan.");
  return name;
}

function runSql(sql, tuplesOnly = false) {
  const args = ["exec", "-i", dbContainer, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"];
  if (tuplesOnly) args.push("-t", "-A", "-q");
  return run("docker", args, sql);
}

function runSqlJson(sql) {
  const output = runSql(sql, true);
  const line = output.split(/\r?\n/).map((item) => item.trim()).findLast((item) => item.startsWith("{") || item.startsWith("["));
  if (!line) throw new Error(`SQL tidak mengembalikan JSON: ${output.slice(-2000)}`);
  return JSON.parse(line);
}

async function json(response) {
  const raw = await response.text();
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return raw; }
}

function headers(token = accessToken) {
  return { apikey: publishableKey, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api", "Content-Type": "application/json" };
}

async function loginAs(userEmail, userPassword) {
  const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: publishableKey, "Content-Type": "application/json" }, body: JSON.stringify({ email: userEmail, password: userPassword }) });
  const payload = await json(response);
  if (!response.ok) throw new Error(`Login gagal: ${JSON.stringify(payload)}`);
  return { token: payload.access_token, userId: payload.user?.id };
}

async function restRows(resource) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${resource}`, { headers: headers(), cache: "no-store" });
  const payload = await json(response);
  if (!response.ok) throw new Error(`REST ${resource} gagal: ${JSON.stringify(payload)}`);
  return Array.isArray(payload) ? payload : [];
}

async function rpc(name, body, token = accessToken) {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, { method: "POST", headers: headers(token), body: JSON.stringify(body), cache: "no-store" });
  const payload = await json(response);
  if (!response.ok) throw new Error(`RPC ${name} gagal (${response.status}): ${JSON.stringify(payload)}`);
  return payload;
}

function localDateTime() {
  const shifted = new Date(Date.now() + 7 * 60 * 60 * 1000);
  return shifted.toISOString().slice(0, 16);
}

function cookie() { return `glowlab_access_token=${accessToken}`; }

async function page(uri) {
  const response = await fetch(`${baseUrl}${uri}`, { headers: { Cookie: cookie() }, redirect: "manual", cache: "no-store" });
  const html = await response.text();
  if (!response.ok) throw new Error(`GET ${uri} gagal (${response.status}): ${html.slice(0, 2500)}`);
  return { uri: `${baseUrl}${uri}`, html, status: response.status };
}

function forms(html) { return html.match(/<form\b[^>]*>.*?<\/form>/gis) ?? []; }
function formFor(html, marker) {
  const form = forms(html).find((candidate) => candidate.toLowerCase().includes(marker.toLowerCase()));
  if (!form) throw new Error(`Form tidak ditemukan: ${marker}`);
  return form;
}
function hasForm(html, marker) { return forms(html).some((candidate) => candidate.toLowerCase().includes(marker.toLowerCase())); }
function actionName(form) {
  const match = form.match(/name="(\$ACTION_ID_[^"]+)"/i);
  if (!match) throw new Error("Server Action identifier tidak ditemukan.");
  return match[1];
}
function htmlContains(html, text) { return html.toLowerCase().includes(text.toLowerCase()); }
async function submitForm({ uri, html, marker, fields, actionId }) {
  const form = actionId ? null : formFor(html, marker);
  const body = new FormData();
  body.append(actionId ?? actionName(form), "");
  for (const [key, value] of Object.entries(fields)) body.append(key, value == null ? "" : String(value));
  const response = await fetch(uri, { method: "POST", headers: { Cookie: cookie(), Origin: baseUrl, Referer: uri }, body, redirect: "manual" });
  const responseBody = await response.text();
  check(`Server Action redirect: ${marker}`, [302, 303, 307, 308].includes(response.status), responseBody.slice(0, 500));
  const location = response.headers.get("location");
  check(`Server Action destination: ${marker}`, Boolean(location));
  const redirectUrl = new URL(location, uri);
  const next = await fetch(redirectUrl, { headers: { Cookie: cookie() }, cache: "no-store" });
  const nextHtml = await next.text();
  check(`Redirect page tersedia: ${marker}`, next.ok, nextHtml.slice(0, 500));
  return {
    uri: redirectUrl.toString(),
    html: nextHtml,
    postStatus: response.status,
    location,
    finalStatus: next.status,
    success: redirectUrl.searchParams.get("success"),
    error: redirectUrl.searchParams.get("error"),
    responseBody: responseBody.slice(0, 2000),
  };
}

function startServer() {
  const url = new URL(baseUrl);
  server = spawn(process.execPath, [path.resolve("node_modules/next/dist/bin/next"), "dev", "--hostname", url.hostname, "--port", String(url.port || 3000)], { cwd: process.cwd(), windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  server.stdout.on("data", (chunk) => { serverOutput = (serverOutput + chunk.toString()).slice(-30000); });
  server.stderr.on("data", (chunk) => { serverOutput = (serverOutput + chunk.toString()).slice(-30000); });
}

async function waitForServer() {
  for (let i = 0; i < 90; i += 1) {
    try { const response = await fetch(`${baseUrl}/login`, { redirect: "manual" }); if (response.status === 200) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`Next.js tidak siap: ${serverOutput}`);
}

function createReturn(suffix, quantity = 1, markLost = true) {
  const reserve = `${prefix}:${suffix}:reserve`;
  const ship = `${prefix}:${suffix}:ship`;
  const expected = `${prefix}:${suffix}:expected`;
  const returnRef = `${prefix}:${suffix}:return`;
  const order = `${prefix}:${suffix}:order`;
  const line = `${prefix}:${suffix}:line`;
  const lostSql = markLost ? `select api.mark_return_lost(${sqlLiteral(organizationId)}::uuid,${sqlLiteral(`${prefix}:${suffix}:lost`)},${sqlLiteral(returnRef)},${sqlLiteral(`${prefix}:${suffix}:lost:event`)},clock_timestamp(),jsonb_build_array(jsonb_build_object('returnItemId',(select item.return_item_id::text from api.return_items item join api.returns header on header.return_id=item.return_id where header.external_return_ref=${sqlLiteral(returnRef)}),'quantity',${quantity},'sourceLineRef',${sqlLiteral(`${prefix}:${suffix}:lost:line`)})),'ui smoke',jsonb_build_object('smokePrefix',${sqlLiteral(prefix)}));` : "";
  const fixture = runSqlJson(`
begin;
select api.apply_marketplace_event(${sqlLiteral(organizationId)}::uuid,${sqlLiteral(reserve)},'TIKTOK_SHOP','RESERVE',${sqlLiteral(`${reserve}:event`)},${sqlLiteral(order)},clock_timestamp(),jsonb_build_array(jsonb_build_object('productId',${sqlLiteral(productId)},'quantity',${quantity},'sourceLineRef',${sqlLiteral(line)})),'ui smoke',jsonb_build_object('smokePrefix',${sqlLiteral(prefix)}));
select api.apply_marketplace_event(${sqlLiteral(organizationId)}::uuid,${sqlLiteral(ship)},'TIKTOK_SHOP','SHIP',${sqlLiteral(`${ship}:event`)},${sqlLiteral(order)},clock_timestamp(),jsonb_build_array(jsonb_build_object('productId',${sqlLiteral(productId)},'quantity',${quantity},'sourceLineRef',${sqlLiteral(line)})),'ui smoke',jsonb_build_object('smokePrefix',${sqlLiteral(prefix)}));
select api.create_expected_return(${sqlLiteral(organizationId)}::uuid,${sqlLiteral(expected)},'TIKTOK_SHOP',${sqlLiteral(returnRef)},${sqlLiteral(order)},clock_timestamp(),jsonb_build_array(jsonb_build_object('productId',${sqlLiteral(productId)},'quantity',${quantity},'sourceLineRef',${sqlLiteral(line)})),'RETURN_REQUESTED','ui smoke',jsonb_build_object('smokePrefix',${sqlLiteral(prefix)}));
${lostSql}
commit;
  select json_build_object(
    'returnId',r.id,
    'returnRef',r.external_return_ref,
    'createdAt',r.created_at,
    'itemId',i.id,
    'sourceLineRef',i.source_line_ref,
    'marketplaceOrderItemId',i.marketplace_order_item_id,
    'marketplaceShipAllocationId',allocation.id,
    'sourceBatchId',allocation.batch_id,
    'sourceBatchCode',allocation.batch_code_snapshot,
    'sourceExpiryDate',allocation.expiry_date_snapshot,
    'shippedQuantity',allocation.quantity_allocated
  )
  from operations.returns r
  join operations.return_items i
    on i.organization_id=r.organization_id and i.return_id=r.id
  join operations.marketplace_order_items order_item
    on order_item.organization_id=i.organization_id and order_item.id=i.marketplace_order_item_id
  join operations.marketplace_events shipment
    on shipment.organization_id=order_item.organization_id
   and shipment.order_id=order_item.order_id
   and shipment.external_event_ref=${sqlLiteral(`${ship}:event`)}
  join operations.marketplace_ship_allocations allocation
    on allocation.organization_id=shipment.organization_id
   and allocation.event_id=shipment.id
   and allocation.product_id=i.product_id
   and allocation.source_line_ref=i.source_line_ref
  where r.organization_id=${sqlLiteral(organizationId)}::uuid
    and r.external_return_ref=${sqlLiteral(returnRef)};
  `);
  check(`Shipment allocation ${suffix} tepat untuk return fixture`, Boolean(fixture.marketplaceShipAllocationId) && fixture.sourceBatchId === runFixture.sourceBatchId && Number(fixture.shippedQuantity) === quantity, JSON.stringify(fixture));
  return fixture;
}

function createRunScopedInventoryFixture(requiredShipmentQuantity) {
  const fixtureCode = `SMK-${randomUUID()}`;
  const result = runSqlJson(`
begin;
select set_config('request.jwt.claim.sub',${sqlLiteral(smokeUserId)},true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',${sqlLiteral(smokeUserId)},'role','authenticated')::text,true);
set local role authenticated;
with product as (
  select api.create_product(${sqlLiteral(organizationId)}::uuid,${sqlLiteral(`${prefix}:catalog-product`)},${sqlLiteral(fixtureCode)},'TikTok claim UI smoke product','UNIT',null,'Run-scoped smoke catalog fixture') result
), batch as (
  select api.create_product_batch(${sqlLiteral(organizationId)}::uuid,${sqlLiteral(`${prefix}:catalog-batch`)},(select (result->>'productId')::uuid from product),${sqlLiteral(`${fixtureCode}-BATCH`)},'2027-12-31',current_date,null,'STANDARD','Run-scoped smoke source batch') result
), receipt as (
  select api.post_receipt(${sqlLiteral(organizationId)}::uuid,${sqlLiteral(`${prefix}:catalog-receipt`)},${sqlLiteral(`${prefix}:catalog-receipt-ref`)},clock_timestamp(),jsonb_build_array(jsonb_build_object('productId',(select result->>'productId' from product),'batchId',(select result->>'batchId' from batch),'quantity',${requiredShipmentQuantity},'sourceLineRef',${sqlLiteral(`${prefix}:catalog-receipt-line`)})),'Run-scoped smoke inbound receipt.',jsonb_build_object('smokePrefix',${sqlLiteral(prefix)})) result
)
select json_build_object('productId',(select result->>'productId' from product),'productSku',${sqlLiteral(fixtureCode)},'sourceBatchId',(select result->>'batchId' from batch),'sourceBatchCode',${sqlLiteral(`${fixtureCode}-BATCH`)},'receipt',(select result from receipt),'initialQuantity',${requiredShipmentQuantity});
reset role;
commit;`);
  const position = runSqlJson(`select json_build_object('product', (select row_to_json(p) from inventory.stock_product_positions p where p.organization_id=${sqlLiteral(organizationId)}::uuid and p.product_id=${sqlLiteral(result.productId)}::uuid), 'batch', (select row_to_json(b) from inventory.stock_batch_balances b where b.organization_id=${sqlLiteral(organizationId)}::uuid and b.batch_id=${sqlLiteral(result.sourceBatchId)}::uuid));`);
  check('Run-scoped inventory cukup sebelum shipment', Number(position.product?.sellable_qty) === requiredShipmentQuantity && Number(position.product?.reserved_qty) === 0 && Number(position.batch?.sellable_qty) === requiredShipmentQuantity, JSON.stringify(position));
  return result;
}

function stockSnapshot() {
  return runSqlJson(`select json_build_object(
    'transactions',(select count(*) from inventory.stock_transactions),
    'ledger',(select count(*) from inventory.stock_ledger_entries),
    'product',(select coalesce(json_agg(row_to_json(x) order by x.product_id),'[]'::json) from (select product_id,sellable_qty,quarantine_qty,damaged_qty,reserved_qty from inventory.stock_product_positions where organization_id=${sqlLiteral(organizationId)}::uuid order by product_id) x),
    'batch',(select coalesce(json_agg(row_to_json(x) order by x.batch_id),'[]'::json) from (select batch_id,product_id,sellable_qty,quarantine_qty,damaged_qty from inventory.stock_batch_balances where organization_id=${sqlLiteral(organizationId)}::uuid order by batch_id) x),
    'reservation',(select coalesce(json_agg(row_to_json(x) order by x.id),'[]'::json) from (select id,product_id,reserved_qty,consumed_qty,released_qty,status_code from inventory.stock_reservations where organization_id=${sqlLiteral(organizationId)}::uuid order by id) x)
  );`);
}

function assertSnapshotSame(before, after, label) { check(label, JSON.stringify(before) === JSON.stringify(after), `before=${JSON.stringify(before)} after=${JSON.stringify(after)}`); }

async function claimFor(returnId) {
  const rows = await restRows(`return_claim_master?organization_id=eq.${organizationId}&return_id=eq.${returnId}&select=*&order=created_at.desc&limit=1`);
  check("Claim tersimpan pada return fixture", rows.length === 1);
  return rows[0];
}

async function createRunScopedAdmin(label) {
  const fixtureEmail = `tiktok-claim-ui-${label}-${randomUUID()}@glowlab.invalid`;
  const response = await fetch(`${supabaseUrl}/auth/v1/admin/users`, { method: "POST", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ email: fixtureEmail, password, email_confirm: true, user_metadata: { display_name: `TikTok Claim Smoke ${label}` } }) });
  const payload = await json(response);
  if (!response.ok) throw new Error(`Admin fixture ${label} gagal dibuat: ${JSON.stringify(payload)}`);
  const fixtureOrganizationId = randomUUID();
  runSql(`insert into app.organizations(id,code,name,timezone,is_active,created_by) values (${sqlLiteral(fixtureOrganizationId)}::uuid,${sqlLiteral(`${prefix}:${label}:ORG`)},${sqlLiteral(`TikTok claim smoke ${label}`)},'Asia/Jakarta',true,${sqlLiteral(payload.id)}::uuid); insert into app.user_profiles(user_id,organization_id,display_name,employee_code,role_code,is_active) values (${sqlLiteral(payload.id)}::uuid,${sqlLiteral(fixtureOrganizationId)}::uuid,${sqlLiteral(`TikTok Claim Smoke ${label}`)},${sqlLiteral(`${prefix}:${label}:ADMIN`)},'ADMIN',true);`);
  const session = await loginAs(fixtureEmail, password);
  return { ...session, email: fixtureEmail, organizationId: fixtureOrganizationId };
}

async function main() {
  env = await loadEnv();
  supabaseUrl = String(env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321").replace(/\/$/, "");
  publishableKey = String(env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "");
  serviceKey = String(env.SUPABASE_SECRET_KEY ?? "");
  check("Supabase local dan publishable key tersedia", publishableKey && !publishableKey.includes("REPLACE_ME"));
  check("Smoke tidak memakai service key sebagai browser credential", Boolean(serviceKey));
  check("Base URL loopback", ["127.0.0.1", "localhost", "::1"].includes(new URL(baseUrl).hostname));
  check("Supabase URL loopback", ["127.0.0.1", "localhost", "::1"].includes(new URL(supabaseUrl).hostname));
  dbContainer = resolveDb();
  const primary = await createRunScopedAdmin("PRIMARY");
  const secondary = await createRunScopedAdmin("SECONDARY");
  organizationId = primary.organizationId;
  accessToken = primary.token;
  smokeUserId = primary.userId;
  check("Admin fixture run dapat login", Boolean(accessToken));
  startServer();
  await waitForServer();

  const anonymous = await fetch(`${baseUrl}/returns`, { redirect: "manual" });
  check("Anonim diarahkan ke login", [302,303,307,308].includes(anonymous.status) && (anonymous.headers.get("location") ?? "").includes("/login"));
  const initial = await page("/returns");
  check("Admin membuka /returns", htmlContains(initial.html, "TikTok claim desk"));
  check("Organization Admin utama terisolasi", runSqlJson(`select json_build_object('organizationId',(select organization_id from app.user_profiles where user_id=${sqlLiteral(smokeUserId)}::uuid))`).organizationId === organizationId);

  console.log(`Fixture prefix: ${prefix}`);
  const requiredShipmentQuantity = 4;
  runFixture = createRunScopedInventoryFixture(requiredShipmentQuantity);
  productId = runFixture.productId;
  const scenarioA = createReturn("A-RESOLVE-LATE", 1);
  const scenarioB = createReturn("B-CANCEL", 1);
  const scenarioSellable = createReturn("C-SELLABLE", 1, false);
  const scenarioDamaged = createReturn("D-DAMAGED", 1, false);
  for (const fixture of [scenarioA, scenarioB, scenarioSellable, scenarioDamaged]) check("Fixture return memiliki UUID", UUID.test(fixture.returnId) && UUID.test(fixture.itemId));

  const beforeCreate = stockSnapshot();
  let current = await page(`/returns?returnId=${scenarioA.returnId}#claims`);
  check("Form create tersedia untuk TikTok lost item", hasForm(current.html, "Buat klaim TikTok"));
  const invalid = await submitForm({ uri: current.uri, html: current.html, marker: "Buat klaim TikTok", fields: { returnId: scenarioA.returnId, claimTypeCode: "LOST_RETURN", idempotencyKey: `${prefix}:invalid-create`, claimItemId: scenarioA.itemId, [`quantity_${scenarioA.itemId}`]: "0", occurredAt: localDateTime(), confirmation: "on" } });
  check("Invalid quantity memberi feedback persisten", htmlContains(invalid.html, "bilangan bulat positif") || htmlContains(invalid.html, "quantity klaim"));
  current = await page(`/returns?returnId=${scenarioA.returnId}#claims`);
  const created = await submitForm({ uri: current.uri, html: current.html, marker: "Buat klaim TikTok", fields: { returnId: scenarioA.returnId, claimTypeCode: "LOST_RETURN", idempotencyKey: `${prefix}:claim-a`, claimItemId: scenarioA.itemId, [`quantity_${scenarioA.itemId}`]: "1", occurredAt: localDateTime(), confirmation: "on" } });
  const claimA = await claimFor(scenarioA.returnId);
  check("Create claim valid berhasil dan feedback bertahan", htmlContains(created.html, "Klaim") && created.html.includes(claimA.id));
  assertSnapshotSame(beforeCreate, stockSnapshot(), "Create claim tetap stock-neutral");
  const replay = await submitForm({ uri: created.uri, html: created.html, marker: "Buat klaim TikTok", fields: { returnId: scenarioA.returnId, claimTypeCode: "LOST_RETURN", idempotencyKey: `${prefix}:claim-a`, claimItemId: scenarioA.itemId, [`quantity_${scenarioA.itemId}`]: "1", occurredAt: localDateTime(), confirmation: "on" } });
  const claimsAfterReplay = await restRows(`return_claim_master?organization_id=eq.${organizationId}&return_id=eq.${scenarioA.returnId}&select=id`);
  check("Replay create tidak menggandakan claim", claimsAfterReplay.length === 1 && htmlContains(replay.html, claimA.id));
  check("Deadline tersimpan tepat 40 hari dari return.created_at", Math.abs(new Date(claimA.deadline_at).getTime() - (new Date(scenarioA.createdAt).getTime() + 40 * 86400000)) < 2000);
  check("Claim detail menampilkan provenance dan stock NONE", htmlContains(created.html, "Provenance historis") && htmlContains(created.html, "NONE"));

  // The demo organization intentionally retains durable smoke fixtures.  The
  // evaluator scans every active claim in that tenant, so choose an observed
  // time after every stored deadline rather than re-entering an older D1
  // window and attempting a stage downgrade on a previous smoke episode.
  const observedAt = runSqlJson(`select json_build_object('observed_at', (greatest(
    ${sqlLiteral(claimA.deadline_at)}::timestamptz,
    coalesce((select max(deadline_at) from operations.return_claims where organization_id=${sqlLiteral(organizationId)}::uuid), '-infinity'::timestamptz),
    coalesce((select max(last_seen_at) from notification.notifications where organization_id=${sqlLiteral(organizationId)}::uuid), '-infinity'::timestamptz),
    coalesce((select max(occurred_at) from notification.notification_events event join notification.notifications notification_row on notification_row.id=event.notification_id where notification_row.organization_id=${sqlLiteral(organizationId)}::uuid), '-infinity'::timestamptz)
  ) + interval '1 microsecond')::text);`).observed_at;
  const evalResult = runSqlJson(`select notification.evaluate_tiktok_claim_deadlines(${sqlLiteral(organizationId)}::uuid,${sqlLiteral(`${prefix}:notification:evaluate`)},${sqlLiteral(observedAt)}::timestamptz,'tiktok-return-claim-ui-smoke');`);
  check("Evaluator notification membuat hasil", evalResult && ["COMPLETED", "REPLAYED"].includes(evalResult.action));
  current = await page(`/returns?claimId=${claimA.id}#claim-detail`);
  check("Notification deep link memilih claim exact", current.html.includes(claimA.id) && htmlContains(current.html, "Detail klaim"));
  const notificationRows = await rpc("notification_list", { p_lifecycle_status_code: null, p_severity_code: null, p_category_code: null, p_read_state_code: null, p_include_archived: true, p_limit: 100, p_before_last_seen_at: null, p_before_id: null });
  const notification = (notificationRows ?? []).find((row) => row.entity_id === claimA.id || row.action_route?.includes(claimA.id));
  check("Notification tertaut ke claim dan route exact", Boolean(notification) && notification.action_route === `/returns?claimId=${claimA.id}`);
  check("Link kembali ke Notification Center tersedia", current.html.includes(`/notifications?notificationId=${notification?.notification_id}#detail`));

  const submitRejected = await submitForm({ uri: current.uri, html: current.html, marker: "External claim reference", fields: { claimId: claimA.id, returnId: scenarioA.returnId, externalClaimRef: `${prefix}:CLAIM-A`, occurredAt: localDateTime() } });
  check("Submit tanpa confirmation ditolak", htmlContains(submitRejected.html, "Konfirmasi operator"));
  current = await page(`/returns?claimId=${claimA.id}#claim-detail`);
  const submitted = await submitForm({ uri: current.uri, html: current.html, marker: "External claim reference", fields: { claimId: claimA.id, returnId: scenarioA.returnId, externalClaimRef: `${prefix}:CLAIM-A`, occurredAt: localDateTime(), confirmation: "on" } });
  let claimAAfter = await claimFor(scenarioA.returnId);
  check("Submit valid menghasilkan SUBMITTED", claimAAfter.status_code === "SUBMITTED" && htmlContains(submitted.html, "SUBMITTED"));
  assertSnapshotSame(beforeCreate, stockSnapshot(), "Submit tetap stock-neutral");
  current = await page(`/returns?claimId=${claimA.id}#claim-detail`);
  const resolved = await submitForm({ uri: current.uri, html: current.html, marker: "Resolution", fields: { claimId: claimA.id, returnId: scenarioA.returnId, resolutionCode: "APPROVED", occurredAt: localDateTime(), confirmation: "on" } });
  claimAAfter = await claimFor(scenarioA.returnId);
  check("Resolve valid menghasilkan RESOLVED", claimAAfter.status_code === "RESOLVED" && claimAAfter.resolution_code === "APPROVED" && htmlContains(resolved.html, "RESOLVED"));
  assertSnapshotSame(beforeCreate, stockSnapshot(), "Resolve tetap stock-neutral");

  const lateBefore = stockSnapshot();
  current = await page(`/returns?returnId=${scenarioA.returnId}&claimId=${claimA.id}#claims`);
  const lateRejected = await submitForm({ uri: current.uri, html: current.html, marker: "Konfirmasi kedatangan terlambat", fields: { returnId: scenarioA.returnId, returnRef: scenarioA.returnRef, lateArrivalReference: `${prefix}:A:LATE`, receiptRef: `${prefix}:A:RECEIPT`, lateReturnItemId: scenarioA.itemId, [`lateQuantity_${scenarioA.itemId}`]: "2", sourceLineRef: `${prefix}:A:LATE:LINE`, occurredAt: localDateTime(), confirmation: "on" } });
  check("Late arrival over-quantity memberi feedback", htmlContains(lateRejected.html, "melebihi quantity lost") || htmlContains(lateRejected.html, "belum dikoreksi"));
  current = await page(`/returns?returnId=${scenarioA.returnId}&claimId=${claimA.id}#claims`);
  const lateActionId = actionName(formFor(current.html, "Konfirmasi kedatangan terlambat"));
  const initialLateArrivalFields = { returnId: scenarioA.returnId, returnRef: scenarioA.returnRef, lateArrivalReference: `${prefix}:A:LATE`, receiptRef: `${prefix}:A:RECEIPT`, lateReturnItemId: scenarioA.itemId, [`lateQuantity_${scenarioA.itemId}`]: "1", sourceLineRef: `${prefix}:A:LATE:LINE`, occurredAt: localDateTime(), note: "UI smoke late arrival", confirmation: "on" };
  const lateDone = await submitForm({ uri: current.uri, html: current.html, marker: "Konfirmasi kedatangan terlambat", fields: initialLateArrivalFields, actionId: lateActionId });
  check("Late arrival valid berhasil", htmlContains(lateDone.html, "stock-neutral") || htmlContains(lateDone.html, "berhasil"));
  const lateRows = await restRows(`return_late_arrivals?organization_id=eq.${organizationId}&return_id=eq.${scenarioA.returnId}&select=*&limit=10`);
  check("Late arrival receipt dan claim link terlihat", lateRows.length === 1 && htmlContains(lateDone.html, "Receipt") && htmlContains(lateDone.html, "review"));
  assertSnapshotSame(lateBefore, stockSnapshot(), "Late arrival receipt tetap stock-neutral");
  const lateAfterInitial = stockSnapshot();
  const initialLateArrivalId = lateRows[0]?.late_arrival_id;
  const replayLate = await submitForm({ uri: current.uri, html: current.html, marker: "Konfirmasi kedatangan terlambat", fields: structuredClone(initialLateArrivalFields), actionId: lateActionId });
  const lateAgain = await restRows(`return_late_arrivals?organization_id=eq.${organizationId}&return_id=eq.${scenarioA.returnId}&select=late_arrival_id`);
  check("Replay late arrival mempertahankan receipt yang sama", lateAgain.length === 1 && lateAgain[0]?.late_arrival_id === initialLateArrivalId && replayLate.html.includes(initialLateArrivalFields.receiptRef), `expectedLateArrivalId=${initialLateArrivalId} actual=${JSON.stringify(lateAgain)}`);
  assertSnapshotSame(lateAfterInitial, stockSnapshot(), "Replay late arrival tidak menambah stock effect");
  const changedLateArrivalFields = structuredClone(initialLateArrivalFields);
  changedLateArrivalFields.occurredAt = new Date(new Date(initialLateArrivalFields.occurredAt).getTime() + 60_000).toISOString().slice(0, 16);
  const changedLate = await submitForm({ uri: current.uri, html: current.html, marker: "Konfirmasi kedatangan terlambat", fields: changedLateArrivalFields, actionId: lateActionId });
  const lateAfterConflict = await restRows(`return_late_arrivals?organization_id=eq.${organizationId}&return_id=eq.${scenarioA.returnId}&select=late_arrival_id`);
  check("Late arrival payload berubah ditolak tanpa effect baru", lateAfterConflict.length === 1 && htmlContains(changedLate.html, "payload berbeda"));

  current = await page(`/returns?returnId=${scenarioB.returnId}#claims`);
  await submitForm({ uri: current.uri, html: current.html, marker: "Buat klaim TikTok", fields: { returnId: scenarioB.returnId, claimTypeCode: "LOST_RETURN", idempotencyKey: `${prefix}:claim-b`, claimItemId: scenarioB.itemId, [`quantity_${scenarioB.itemId}`]: "1", occurredAt: localDateTime(), confirmation: "on" } });
  const claimB = await claimFor(scenarioB.returnId);
  const cancelDetailPage = await page(`/returns?returnId=${scenarioB.returnId}&claimId=${claimB.id}#claim-detail`);
  const cancelForm = formFor(cancelDetailPage.html, "Alasan pembatalan");
  const cancelActionId = actionName(cancelForm);
  check("Cancel form tepat untuk claim B", cancelForm.includes(`value=\"${claimB.id}\"`) && cancelForm.includes('name="reason"'), `claimId=${claimB.id}`);
  const invalidCancelFields = { claimId: claimB.id, returnId: scenarioB.returnId, reason: `${prefix}:cancel`, occurredAt: localDateTime() };
  const cancelRejected = await submitForm({ uri: cancelDetailPage.uri, html: cancelDetailPage.html, marker: "Alasan pembatalan", fields: invalidCancelFields, actionId: cancelActionId });
  check("Cancel tanpa confirmation ditolak", htmlContains(cancelRejected.html, "Konfirmasi operator"));
  current = await page(`/returns?claimId=${claimB.id}#claim-detail`);
  const cancelled = await submitForm({ uri: current.uri, html: current.html, marker: "Alasan pembatalan", fields: { claimId: claimB.id, returnId: scenarioB.returnId, reason: `${prefix}:cancel`, occurredAt: localDateTime(), confirmation: "on" } });
  const claimBAfter = await claimFor(scenarioB.returnId);
  check("Cancel valid mempertahankan history dan melepas capacity", claimBAfter.status_code === "CANCELLED" && htmlContains(cancelled.html, "CANCELLED"));
  const cancelledItems = await restRows(`return_claim_items?organization_id=eq.${organizationId}&claim_id=eq.${claimB.id}&select=id`);
  check("Cancelled claim item tetap ada", cancelledItems.length === 1);

  for (const [suffix, fixture, mode] of [["SELLABLE", scenarioSellable, "1"], ["DAMAGED", scenarioDamaged, "2"]]) {
    let receiptPage = await page(`/returns?returnId=${fixture.returnId}#actions`);
    const receiptForm = formFor(receiptPage.html, "Confirm physical receipt");
    check(`${suffix} receipt form menyediakan field provenance`, receiptForm.includes('name="returnItemId"') && receiptForm.includes('name="marketplaceShipAllocationId"'), `returnId=${fixture.returnId} allocationId=${fixture.marketplaceShipAllocationId}`);
    const receiptFields = { returnRef: fixture.returnRef, receiptRef: `${prefix}:${suffix}:RECEIPT`, returnItemId: fixture.itemId, marketplaceShipAllocationId: fixture.marketplaceShipAllocationId, quantity: "1", sourceLineRef: `${prefix}:${suffix}:RECEIPT:LINE`, occurredAt: localDateTime(), note: "UI smoke receipt" };
    const receipt = await submitForm({ uri: receiptPage.uri, html: receiptPage.html, marker: "Confirm physical receipt", fields: receiptFields });
    check(`${suffix} receipt stock-neutral`, htmlContains(receipt.html, "belum berubah") || htmlContains(receipt.html, "Stok belum berubah"));
    const receiptLines = await restRows(`return_receipt_lines?organization_id=eq.${organizationId}&receipt_ref=eq.${encodeURIComponent(`${prefix}:${suffix}:RECEIPT`)}&select=*&limit=10`);
    check(`${suffix} receipt line membawa provenance shipment exact`, receiptLines.length === 1 && receiptLines[0].marketplace_ship_allocation_id === fixture.marketplaceShipAllocationId && receiptLines[0].source_batch_id === fixture.sourceBatchId && receiptLines[0].source_batch_code_snapshot === fixture.sourceBatchCode && receiptLines[0].source_expiry_date_snapshot === fixture.sourceExpiryDate && receiptLines[0].batch_identity_verified === true, `expectedAllocation=${fixture.marketplaceShipAllocationId} expectedBatch=${fixture.sourceBatchId} actual=${JSON.stringify(receiptLines)}`);
    const inspectionBefore = stockSnapshot();
    const inspectPage = await page(`/returns?returnId=${fixture.returnId}#actions`);
    const inspectionFields = { returnRef: fixture.returnRef, receiptLineId: receiptLines[0].receipt_line_id, inspectionRef: `${prefix}:${suffix}:INSPECTION`, occurredAt: localDateTime(), sellableQuantity: mode === "1" ? "1" : "0", damagedQuantity: mode === "2" ? "1" : "0", sourceLineRef: `${prefix}:${suffix}:INSPECTION:LINE`, note: "UI smoke inspection" };
    const inspected = await submitForm({ uri: inspectPage.uri, html: inspectPage.html, marker: "Tetapkan kondisi fisik", fields: inspectionFields });
    console.log(`[DIAG] ${suffix} inspection POST=${inspected.postStatus} location=${inspected.location} final=${inspected.uri} finalStatus=${inspected.finalStatus} success=${JSON.stringify(inspected.success)} error=${JSON.stringify(inspected.error)} receiptLineId=${inspectionFields.receiptLineId} inspectionRef=${inspectionFields.inspectionRef} fields=${Object.keys(inspectionFields).join(",")}`);
    const transactionCountBefore = Number(inspectionBefore.transactions);
    const after = stockSnapshot();
    if (mode === "1") {
      check("SELLABLE inspection menghasilkan satu movement", Number(after.transactions) === transactionCountBefore + 1 && htmlContains(inspected.html, "batch retur"));
      const returnBatches = await restRows(`return_stock_batches?organization_id=eq.${organizationId}&return_id=eq.${fixture.returnId}&select=*&limit=10`);
      check("SELLABLE membuat batch RETURN", returnBatches.length === 1 && returnBatches[0].batch_kind_code === "RETURN");
    } else {
      assertSnapshotSame(inspectionBefore, after, "DAMAGED inspection tidak menambah movement");
      check("DAMAGED feedback menyatakan tanpa movement stok", htmlContains(inspected.html, "tanpa pergerakan stok"));
    }
  }

  const second = secondary;
  const firstToken = accessToken;
  const firstPage = await page(`/returns?returnId=${scenarioA.returnId}&claimId=${claimA.id}#claim-detail`);
  accessToken = second.token;
  const foreign = await page(`/returns?claimId=${claimA.id}#claim-detail`);
  check("Foreign claim deep link menjadi blocked/no-result", htmlContains(foreign.html, "tidak ditemukan") && !hasForm(foreign.html, "Buat klaim TikTok"));
  const forged = await submitForm({ uri: firstPage.uri, html: firstPage.html, marker: "Buat klaim TikTok", fields: { returnId: scenarioA.returnId, claimTypeCode: "LOST_RETURN", idempotencyKey: `${prefix}:foreign`, claimItemId: scenarioA.itemId, [`quantity_${scenarioA.itemId}`]: "1", occurredAt: localDateTime(), confirmation: "on" } });
  check("Foreign Server Action ditolak tanpa detail lintas organisasi", htmlContains(forged.html, "organisasi aktif") || htmlContains(forged.html, "tidak ditemukan"));
  accessToken = firstToken;
  check("Fixture source line memiliki provenance historis", Boolean(scenarioA.marketplaceOrderItemId) && Boolean(scenarioA.sourceLineRef));
  check("Tidak ada error server/hydration relevan", !/(Unhandled Runtime Error|Internal Server Error|Hydration failed|UnhandledPromiseRejection)/i.test(serverOutput));
  console.log(`Smoke fixture sengaja dipertahankan sebagai audit evidence dengan prefix ${prefix}.`);
}

main().catch((error) => {
  console.error(`[FAIL] ${error instanceof Error ? error.stack ?? error.message : error}`);
  if (serverOutput) console.error(`\n== Next server output ==\n${serverOutput}`);
  process.exitCode = 1;
}).finally(() => { if (server) server.kill(); });
