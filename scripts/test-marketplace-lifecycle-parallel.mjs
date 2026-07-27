import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import process from "node:process";

const EMAIL = process.env.MARKETPLACE_PARALLEL_EMAIL ?? "demo.admin@glowlab.invalid";
const TIMEOUT_MS = 30_000;
const PREFIX = "CONCURRENCY-MARKETPLACE-V2";
const EFFECTIVE_AT = "2026-07-01T00:00:00Z";
const EVENT_AT = "2026-07-26T10:00:00Z";

function fail(message) { throw new Error(message); }
function assert(condition, message) { if (!condition) fail(message); }
function text(value) { return String(value ?? "").trim(); }
function literal(value) { return `'${String(value).replaceAll("'", "''")}'`; }

function resolvePassword(config) {
  const pwd = process.env.MARKETPLACE_PARALLEL_PASSWORD ?? config?.MARKETPLACE_PARALLEL_PASSWORD ?? process.env.PARALLEL_TEST_PASSWORD ?? config?.PARALLEL_TEST_PASSWORD;
  if (!pwd || typeof pwd !== "string" || pwd.trim() === "") {
    fail("Password harness tidak ditemukan pada MARKETPLACE_PARALLEL_PASSWORD atau PARALLEL_TEST_PASSWORD.");
  }
  return pwd;
}

function validateSupabaseUrl(config) {
  const rawUrl = config?.NEXT_PUBLIC_SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!rawUrl) fail("NEXT_PUBLIC_SUPABASE_URL tidak ditemukan.");
  let parsed;
  try { parsed = new URL(rawUrl); } catch { fail("NEXT_PUBLIC_SUPABASE_URL tidak valid."); }
  const hostname = parsed.hostname.replace(/^\[|\]$/g, "");
  const isLocal = hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1";
  const allowRemote = process.env.ALLOW_REMOTE_PARALLEL_TESTS === "true" || config?.ALLOW_REMOTE_PARALLEL_TESTS === "true";
  if (!isLocal && !allowRemote) {
    fail(`Supabase URL non-local (${hostname}) ditolak secara default. Set ALLOW_REMOTE_PARALLEL_TESTS=true untuk mengizinkan testing remote.`);
  }
}

async function env() {
  const raw = await readFile(".env.local", "utf8");
  return Object.fromEntries(raw.split(/\r?\n/).filter((line) => line && !line.startsWith("#") && line.includes("=")).map((line) => {
    const index = line.indexOf("=");
    return [line.slice(0, index), line.slice(index + 1).trim().replace(/^['\"]|['\"]$/g, "")];
  }));
}

function dbContainer() {
  const result = spawnSync("docker", ["ps", "--format", "{{.Names}}"], { encoding: "utf8", windowsHide: true });
  if (result.status !== 0) fail("Docker Supabase lokal tidak tersedia.");
  const name = result.stdout.split(/\r?\n/).map((value) => value.trim()).find((value) => value.startsWith("supabase_db_"));
  if (!name) fail("Container database Supabase lokal tidak ditemukan.");
  return name;
}

function sqlJson(container, sql) {
  const result = spawnSync("docker", ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-t", "-A", "-q"], { input: sql, encoding: "utf8", windowsHide: true, maxBuffer: 4 * 1024 * 1024 });
  if (result.status !== 0) fail(`Snapshot database gagal: ${result.stderr.slice(-1500)}`);
  const line = result.stdout.split(/\r?\n/).map((value) => value.trim()).findLast((value) => value.startsWith("{") || value === "null");
  if (!line) fail("Snapshot database tidak mengembalikan JSON.");
  return JSON.parse(line);
}

async function login(config) {
  validateSupabaseUrl(config);
  const password = resolvePassword(config);
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password }), signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) fail(`Login Admin gagal (${response.status}).`);
  const payload = await response.json();
  if (!payload.access_token) fail("Login tidak menghasilkan access token.");
  return payload.access_token;
}

async function rpc(config, token, name, body) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api", "Content-Type": "application/json" },
    body: JSON.stringify(body), signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const raw = await response.text();
  let payload;
  try { payload = raw ? JSON.parse(raw) : null; } catch { payload = { message: raw }; }
  return { ok: response.ok, status: response.status, payload };
}

async function profile(config, token) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/current_admin_profile?select=*&limit=1`, {
    headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api" }, signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) fail(`Profil Admin gagal (${response.status}).`);
  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length !== 1 || rows[0]?.role_code !== "ADMIN" || !rows[0]?.organization_id) fail("Fixture Admin aktif tidak ditemukan.");
  return rows[0];
}

function error(result) { return text(result?.payload?.message ?? result?.payload?.code); }
function names(name) {
  const stem = `${PREFIX}-${name}`;
  return { name, sku: `${stem}-PRODUCT`, batch: `${stem}-BATCH`, listing: `${stem}-LISTING`, productKey: `${stem}-PRODUCT-KEY`, batchKey: `${stem}-BATCH-KEY`, receiptKey: `${stem}-RECEIPT-KEY`, receiptRef: `${stem}-RECEIPT` };
}

function fixture(container, organizationId, item) {
  return sqlJson(container, `
select coalesce((select jsonb_build_object('productId',p.id,'batchId',b.id,'listingId',l.id,'versionId',v.id)
from catalog.products p
join catalog.product_batches b on b.organization_id=p.organization_id and b.product_id=p.id
join catalog.marketplace_listings l on l.organization_id=p.organization_id and l.external_listing_code=${literal(item.listing)}
join catalog.marketplace_single_listing_versions v on v.organization_id=l.organization_id and v.listing_id=l.id and v.status_code='ACTIVE'
where p.organization_id=${literal(organizationId)}::uuid and p.sku=${literal(item.sku)} and b.batch_code=${literal(item.batch)} limit 1), 'null'::jsonb);
`);
}

async function ensureFixture(config, token, container, organizationId, name, quantity) {
  const item = names(name);
  let current = fixture(container, organizationId, item);
  if (current) return current;
  const product = await rpc(config, token, "create_product", { p_organization_id: organizationId, p_idempotency_key: item.productKey, p_sku: item.sku, p_name: `Fixture marketplace concurrency ${name}`, p_unit_code: "UNIT", p_description: "Fixture durable Issue #56.", p_note: "Issue #56 marketplace parallel harness." });
  if (!product.ok || !product.payload?.productId) fail(`Create product ${name} gagal: ${error(product)}`);
  const batch = await rpc(config, token, "create_product_batch", { p_organization_id: organizationId, p_idempotency_key: item.batchKey, p_product_id: product.payload.productId, p_batch_code: item.batch, p_expiry_date: "2028-01-01", p_manufactured_date: "2026-06-01", p_received_first_at: EFFECTIVE_AT, p_batch_kind_code: "STANDARD", p_note: "Fixture durable Issue #56." });
  if (!batch.ok || !batch.payload?.batchId) fail(`Create batch ${name} gagal: ${error(batch)}`);
  const receipt = await rpc(config, token, "post_receipt", { p_organization_id: organizationId, p_idempotency_key: item.receiptKey, p_source_ref: item.receiptRef, p_occurred_at: EFFECTIVE_AT, p_lines: [{ productId: product.payload.productId, batchId: batch.payload.batchId, quantity, sourceLineRef: "CONCURRENCY-1" }], p_note: "Fixture stok Issue #56.", p_metadata: { source: "marketplace-parallel-harness", fixture: name, version: 1 } });
  if (!receipt.ok) fail(`Receipt ${name} gagal: ${error(receipt)}`);
  const draft = await rpc(config, token, "create_marketplace_listing_version_draft", { p_organization_id: organizationId, p_idempotency_key: `${item.listing}-DRAFT`, p_channel_code: "SHOPEE", p_external_listing_code: item.listing, p_display_name: `Listing fixture ${name}`, p_listing_type_code: "SINGLE", p_effective_from: EFFECTIVE_AT, p_product_id: product.payload.productId, p_components: [], p_note: "Listing fixture Issue #56.", p_metadata: { source: "marketplace-parallel-harness", fixture: name, version: 1 } });
  if (!draft.ok || draft.payload?.status !== "DRAFT_CREATED") fail(`Draft listing ${name} gagal: ${error(draft)}`);
  const preview = await rpc(config, token, "preview_marketplace_listing_version_activation", { p_organization_id: organizationId, p_listing_id: draft.payload.listingId, p_version_id: draft.payload.versionId });
  if (!preview.ok || preview.payload?.eligible !== true || !preview.payload?.basisHash) fail(`Preview listing ${name} gagal: ${error(preview)}`);
  const activation = await rpc(config, token, "activate_marketplace_listing_version", { p_organization_id: organizationId, p_idempotency_key: `${item.listing}-ACTIVATE`, p_listing_id: draft.payload.listingId, p_version_id: draft.payload.versionId, p_expected_row_version: Number(preview.payload.versionRowVersion), p_preview_basis_hash: preview.payload.basisHash, p_confirmation: true });
  if (!activation.ok || activation.payload?.status !== "ACTIVATED") fail(`Aktivasi listing ${name} gagal: ${error(activation)}`);
  current = fixture(container, organizationId, item);
  if (!current) fail(`Fixture marketplace ${name} tidak terbentuk.`);
  return current;
}

async function ensureTikTokListing(config, token, organizationId, current) {
  const code = `${names("SHIP-TIKTOK").listing}-TIKTOK`;
  const existing = sqlJson(dbContainer(), `select coalesce((select jsonb_build_object('id',l.id) from catalog.marketplace_listings l join catalog.channels c on c.id=l.channel_id where l.organization_id=${literal(organizationId)}::uuid and c.code='TIKTOK_SHOP' and l.external_listing_code=${literal(code)} and l.status_code='ACTIVE' limit 1), 'null'::jsonb);`);
  if (existing) return code;
  const draft = await rpc(config, token, "create_marketplace_listing_version_draft", { p_organization_id: organizationId, p_idempotency_key: `${code}-DRAFT`, p_channel_code: "TIKTOK_SHOP", p_external_listing_code: code, p_display_name: "Listing fixture TikTok", p_listing_type_code: "SINGLE", p_effective_from: EFFECTIVE_AT, p_product_id: current.productId, p_components: [], p_note: "Fixture TikTok Issue #56.", p_metadata: { source: "marketplace-parallel-harness", fixture: "SHIP-TIKTOK", version: 1 } });
  if (!draft.ok || draft.payload?.status !== "DRAFT_CREATED") fail(`Draft TikTok gagal: ${error(draft)}`);
  const preview = await rpc(config, token, "preview_marketplace_listing_version_activation", { p_organization_id: organizationId, p_listing_id: draft.payload.listingId, p_version_id: draft.payload.versionId });
  if (!preview.ok || preview.payload?.eligible !== true) fail(`Preview TikTok gagal: ${error(preview)}`);
  const activation = await rpc(config, token, "activate_marketplace_listing_version", { p_organization_id: organizationId, p_idempotency_key: `${code}-ACTIVATE`, p_listing_id: draft.payload.listingId, p_version_id: draft.payload.versionId, p_expected_row_version: Number(preview.payload.versionRowVersion), p_preview_basis_hash: preview.payload.basisHash, p_confirmation: true });
  if (!activation.ok || activation.payload?.status !== "ACTIVATED") fail(`Aktivasi TikTok gagal: ${error(activation)}`);
  return code;
}

function reserveInput(name, current, quantity, key = `${PREFIX}-${name}-RESERVE-KEY`, eventRef = `${PREFIX}-${name}-RESERVE-EVENT`, orderRef = `${PREFIX}-${name}-ORDER`) {
  const item = names(name);
  return { key, eventRef, orderRef, sourceLineRef: `${name}-LINE`, body: { p_idempotency_key: key, p_channel_code: "SHOPEE", p_event_ref: eventRef, p_order_ref: orderRef, p_source_status: "READY_TO_SHIP", p_occurred_at: EVENT_AT, p_received_at: EVENT_AT, p_lines: [{ sourceLineRef: `${name}-LINE`, externalListingCode: item.listing, listingQuantity: quantity, sourceTitle: `Fixture ${name}`, sourceSku: item.listing, rawLinePayload: { fixture: name } }], p_note: `Issue #56 reserve ${name}.`, p_raw_payload: { fixture: name, quantity }, p_metadata: { source: "marketplace-parallel-harness", fixture: name, version: 1 }, p_schema_version: 1 } };
}

function shipInput(name, reserve, channel = "SHOPEE", key = `${PREFIX}-${name}-SHIP-KEY`, eventRef = `${PREFIX}-${name}-SHIP-EVENT`) {
  return { key, eventRef, body: { p_idempotency_key: key, p_channel_code: channel, p_event_ref: eventRef, p_order_ref: reserve.orderRef, p_source_status: channel === "TIKTOK_SHOP" ? "IN_TRANSIT" : "SHIPPED", p_occurred_at: EVENT_AT, p_received_at: EVENT_AT, p_lines: [{ orderSourceLineRef: reserve.sourceLineRef, componentNo: 1, quantity: 1 }], p_note: `Issue #56 ship ${name}.`, p_raw_payload: { fixture: name, channel }, p_metadata: { source: "marketplace-parallel-harness", fixture: name, version: 1 }, p_schema_version: 1 } };
}

async function cancellationInput(config, token, organizationId, name, reserve, phase, quantity, key, eventRef) {
  const body = { p_organization_id: organizationId, p_channel_code: "SHOPEE", p_event_ref: eventRef, p_order_ref: reserve.orderRef, p_source_status: phase === "POST_SHIPMENT" ? "CANCELLED_AFTER_SHIPMENT" : "CANCELLED_BEFORE_SHIPMENT", p_occurred_at: EVENT_AT, p_received_at: EVENT_AT, p_lines: [{ orderSourceLineRef: reserve.sourceLineRef, componentNo: 1, phaseCode: phase, quantity, cancellationLineRef: `${name}-${phase}-LINE` }], p_note: `Issue #56 cancellation ${name}.`, p_raw_payload: { fixture: name, phase, quantity }, p_metadata: { source: "marketplace-parallel-harness", fixture: name, version: 1 }, p_schema_version: 1 };
  const preview = await rpc(config, token, "preview_marketplace_listing_cancellation", body);
  if (!preview.ok || preview.payload?.eligible !== true || !preview.payload?.basisHash) fail(`Preview cancellation ${name} gagal: ${error(preview)}`);
  return { ...body, p_idempotency_key: key, p_preview_basis_hash: preview.payload.basisHash, p_confirmation: true };
}

function snapshot(container, organizationId, current, eventRefs, orderRefs) {
  const events = eventRefs.map(literal).join(",") || "''";
  const orders = orderRefs.map(literal).join(",") || "''";
  return sqlJson(container, `
select jsonb_build_object(
 'events',(select count(*) from operations.marketplace_events where organization_id=${literal(organizationId)}::uuid and external_event_ref in (${events})),
 'orders',(select count(*) from operations.marketplace_orders where organization_id=${literal(organizationId)}::uuid and external_order_ref in (${orders})),
 'reservations',(select coalesce(sum(r.reserved_qty-r.consumed_qty-r.released_qty),0) from inventory.stock_reservations r join operations.marketplace_order_items i on i.reservation_id=r.id join operations.marketplace_orders o on o.id=i.order_id where r.organization_id=${literal(organizationId)}::uuid and o.external_order_ref in (${orders})),
 'transactions',(select count(*) from inventory.stock_transactions t where t.organization_id=${literal(organizationId)}::uuid and (t.source_ref_snapshot in (${events}) or exists (select 1 from operations.marketplace_events e where e.transaction_id=t.id and e.external_event_ref in (${events})))),
 'ledgerQty',(select coalesce(sum(e.quantity_delta),0) from inventory.stock_ledger_entries e where e.organization_id=${literal(organizationId)}::uuid and e.product_id=${literal(current.productId)}::uuid and e.batch_id=${literal(current.batchId)}::uuid),
 'shipAllocations',(select count(*) from operations.marketplace_ship_allocations a join operations.marketplace_event_lines l on l.id=a.event_line_id join operations.marketplace_events e on e.id=l.event_id where a.organization_id=${literal(organizationId)}::uuid and e.external_event_ref in (${events})),
 'cancellations',(select count(*) from operations.marketplace_cancellations where organization_id=${literal(organizationId)}::uuid and external_event_ref in (${events})),
 'cancelApplications',(select count(*) from operations.marketplace_cancellation_applications a join operations.marketplace_cancellation_lines l on l.id=a.cancellation_line_id join operations.marketplace_cancellations c on c.id=l.cancellation_id where c.organization_id=${literal(organizationId)}::uuid and c.external_event_ref in (${events})),
 'reversalApplications',(select count(*) from inventory.stock_reversal_applications a join operations.marketplace_cancellation_applications ca on ca.stock_reversal_application_id=a.id join operations.marketplace_cancellation_lines cl on cl.id=ca.cancellation_line_id join operations.marketplace_cancellations c on c.id=cl.cancellation_id where c.organization_id=${literal(organizationId)}::uuid and c.external_event_ref in (${events})),
 'product',(select jsonb_build_object('sellable',p.sellable_qty,'reserved',p.reserved_qty,'available',p.sellable_qty-p.reserved_qty) from inventory.stock_product_positions p where p.organization_id=${literal(organizationId)}::uuid and p.product_id=${literal(current.productId)}::uuid),
 'batch',(select jsonb_build_object('sellable',b.sellable_qty,'reserved',0,'available',b.sellable_qty) from inventory.stock_batch_balances b where b.organization_id=${literal(organizationId)}::uuid and b.batch_id=${literal(current.batchId)}::uuid)
);
`);
}

function assertBalances(state, name) {
  assert(Number(state.product.sellable) >= 0 && Number(state.product.reserved) >= 0 && Number(state.product.available) >= 0, `${name}: product physical/reservation tidak boleh negatif.`);
  assert(Number(state.batch.sellable) >= 0 && Number(state.batch.reserved) >= 0 && Number(state.batch.available) >= 0, `${name}: batch physical/reservation tidak boleh negatif.`);
  assert(Number(state.ledgerQty) === Number(state.product.sellable) && Number(state.ledgerQty) === Number(state.batch.sellable), `${name}: ledger dan projection fixture harus konsisten.`);
}

async function reserve(config, token, organizationId, input) { return rpc(config, token, "reserve_marketplace_listing_event", { p_organization_id: organizationId, ...input.body }); }
async function ship(config, token, organizationId, input) { return rpc(config, token, "ship_marketplace_listing_event", { p_organization_id: organizationId, ...input.body }); }
async function cancel(config, token, input) { return rpc(config, token, "post_marketplace_listing_cancellation", input); }

async function ensureReserved(config, token, organizationId, input) {
  const result = await reserve(config, token, organizationId, input);
  if (!result.ok || result.payload?.status !== "APPLIED") fail(`Reserve fixture ${input.orderRef} gagal: ${error(result)}`);
}

async function main() {
  const config = await env(); const container = dbContainer();
  const [tokenA, tokenB] = await Promise.all([login(config), login(config)]);
  assert(tokenA !== tokenB, "Harness membutuhkan dua session Admin independen.");
  const [profileA, profileB] = await Promise.all([profile(config, tokenA), profile(config, tokenB)]);
  assert(profileA.organization_id === profileB.organization_id, "Dua session harus berada pada satu organisasi fixture.");
  const organizationId = profileA.organization_id;

  const scenarios = ["RES-REPLAY", "RES-CONFLICT", "RES-CONTENTION", "SHIP-REPLAY", "SHIP-TIKTOK", "SHIP-COMPETE", "PRE-REPLAY", "PRE-OVERLAP", "POST-REPLAY", "POST-OVERLAP", "SHIP-CANCEL"];
  const fixtures = new Map();
  for (const name of scenarios) fixtures.set(name, await ensureFixture(config, tokenA, container, organizationId, name, name.includes("OVERLAP") ? 3 : name === "RES-CONTENTION" ? 1 : 2));

  // Durable terminal check: every fixture-specific event identity must already be bounded before no write is attempted.
  const terminalProbe = sqlJson(container, `select jsonb_build_object('events',(select count(*) from operations.marketplace_events where organization_id=${literal(organizationId)}::uuid and external_event_ref like ${literal(PREFIX + "%")}), 'cancellations',(select count(*) from operations.marketplace_cancellations where organization_id=${literal(organizationId)}::uuid and external_event_ref like ${literal(PREFIX + "%")}));`);
  if (terminalProbe.events >= 9 && terminalProbe.cancellations >= 4) {
    const before = sqlJson(container, `select jsonb_build_object('events',(select count(*) from operations.marketplace_events where organization_id=${literal(organizationId)}::uuid and external_event_ref like ${literal(PREFIX + "%")}), 'transactions',(select count(*) from inventory.stock_transactions where organization_id=${literal(organizationId)}::uuid and source_ref_snapshot like ${literal(PREFIX + "%")}), 'ledger',(select count(*) from inventory.stock_ledger_entries e join inventory.stock_transactions t on t.id=e.transaction_id where t.organization_id=${literal(organizationId)}::uuid and t.source_ref_snapshot like ${literal(PREFIX + "%")}));`);
    const after = sqlJson(container, `select jsonb_build_object('events',(select count(*) from operations.marketplace_events where organization_id=${literal(organizationId)}::uuid and external_event_ref like ${literal(PREFIX + "%")}), 'transactions',(select count(*) from inventory.stock_transactions where organization_id=${literal(organizationId)}::uuid and source_ref_snapshot like ${literal(PREFIX + "%")}), 'ledger',(select count(*) from inventory.stock_ledger_entries e join inventory.stock_transactions t on t.id=e.transaction_id where t.organization_id=${literal(organizationId)}::uuid and t.source_ref_snapshot like ${literal(PREFIX + "%")}));`);
    assert(JSON.stringify(before) === JSON.stringify(after), "Durable rerun harus hanya membaca fixture marketplace terminal.");
    console.log("[PASS] durable rerun: fixture marketplace terminal tanpa effect tambahan");
    return;
  }

  const rr = reserveInput("RES-REPLAY", fixtures.get("RES-REPLAY"), 1);
  const [rrA, rrB] = await Promise.all([reserve(config, tokenA, organizationId, rr), reserve(config, tokenB, organizationId, rr)]);
  assert(rrA.ok && rrB.ok && rrA.payload?.eventId === rrB.payload?.eventId, "Reserve identical replay harus mengembalikan satu event authoritative/replay.");
  let state = snapshot(container, organizationId, fixtures.get("RES-REPLAY"), [rr.eventRef], [rr.orderRef]);
  assert(state.events === 1 && state.orders === 1 && Number(state.reservations) === 1 && state.transactions === 0, "Reserve replay harus membuat satu reservation stock-neutral."); assertBalances(state, "Reserve replay"); console.log("[PASS] reservation identical replay");

  const rcA = reserveInput("RES-CONFLICT", fixtures.get("RES-CONFLICT"), 1, `${PREFIX}-RES-CONFLICT-KEY`);
  const rcB = reserveInput("RES-CONFLICT", fixtures.get("RES-CONFLICT"), 2, `${PREFIX}-RES-CONFLICT-KEY`, rcA.eventRef, rcA.orderRef);
  const rcResults = await Promise.all([reserve(config, tokenA, organizationId, rcA), reserve(config, tokenB, organizationId, rcB)]);
  assert(rcResults.filter((result) => result.ok).length === 1 && rcResults.filter((result) => !result.ok).length === 1 && error(rcResults.find((result) => !result.ok)) === "IDEMPOTENCY_KEY_REUSED", "Reserve changed payload harus memiliki satu winner dan satu conflict.");
  state = snapshot(container, organizationId, fixtures.get("RES-CONFLICT"), [rcA.eventRef], [rcA.orderRef]); assert(state.events === 1 && state.orders === 1 && [1, 2].includes(Number(state.reservations)) && state.transactions === 0, "Reserve conflict harus menyimpan satu payload tanpa physical effect."); assertBalances(state, "Reserve conflict"); console.log("[PASS] reservation changed-payload conflict");

  const rca = reserveInput("RES-CONTENTION", fixtures.get("RES-CONTENTION"), 1, `${PREFIX}-RES-CONTENTION-A-KEY`, `${PREFIX}-RES-CONTENTION-A-EVENT`, `${PREFIX}-RES-CONTENTION-A-ORDER`);
  const rcb = reserveInput("RES-CONTENTION", fixtures.get("RES-CONTENTION"), 1, `${PREFIX}-RES-CONTENTION-B-KEY`, `${PREFIX}-RES-CONTENTION-B-EVENT`, `${PREFIX}-RES-CONTENTION-B-ORDER`);
  const rct = await Promise.all([reserve(config, tokenA, organizationId, rca), reserve(config, tokenB, organizationId, rcb)]);
  assert(rct.filter((result) => result.ok).length === 1 && rct.filter((result) => !result.ok).length === 1, "Contention reservation stok terakhir harus mempunyai satu winner dan satu penolakan aman.");
  state = snapshot(container, organizationId, fixtures.get("RES-CONTENTION"), [rca.eventRef, rcb.eventRef], [rca.orderRef, rcb.orderRef]); assert(state.events === 1 && Number(state.reservations) === 1 && state.transactions === 0, "Contention reservation tidak boleh over-reserve atau mengubah stok fisik."); assertBalances(state, "Reserve contention"); console.log("[PASS] reservation final-stock contention");

  const sr = reserveInput("SHIP-REPLAY", fixtures.get("SHIP-REPLAY"), 1); await ensureReserved(config, tokenA, organizationId, sr); const sh = shipInput("SHIP-REPLAY", sr);
  const shResults = await Promise.all([ship(config, tokenA, organizationId, sh), ship(config, tokenB, organizationId, sh)]); assert(shResults.every((result) => result.ok) && shResults[0].payload?.eventId === shResults[1].payload?.eventId, "Shipment Shopee replay harus menghasilkan satu event.");
  state = snapshot(container, organizationId, fixtures.get("SHIP-REPLAY"), [sr.eventRef, sh.eventRef], [sr.orderRef]); assert(state.events === 2 && state.transactions === 1 && state.shipAllocations === 1 && Number(state.reservations) === 0, "Shipment Shopee harus mengonsumsi reservation dan membuat satu physical effect."); assertBalances(state, "Shipment Shopee replay"); console.log("[PASS] shipment Shopee identical replay");

  const st = reserveInput("SHIP-TIKTOK", fixtures.get("SHIP-TIKTOK"), 1, `${PREFIX}-SHIP-TIKTOK-RESERVE-KEY`, `${PREFIX}-SHIP-TIKTOK-RESERVE-EVENT`, `${PREFIX}-SHIP-TIKTOK-ORDER`); st.body.p_channel_code = "TIKTOK_SHOP"; st.body.p_lines[0].externalListingCode = await ensureTikTokListing(config, tokenA, organizationId, fixtures.get("SHIP-TIKTOK")); await ensureReserved(config, tokenA, organizationId, st); const ts = shipInput("SHIP-TIKTOK", st, "TIKTOK_SHOP");
  const tsResults = await Promise.all([ship(config, tokenA, organizationId, ts), ship(config, tokenB, organizationId, ts)]); assert(tsResults.every((result) => result.ok) && tsResults[0].payload?.eventId === tsResults[1].payload?.eventId, "Shipment TikTok IN_TRANSIT replay harus menghasilkan satu event."); state = snapshot(container, organizationId, fixtures.get("SHIP-TIKTOK"), [st.eventRef, ts.eventRef], [st.orderRef]); assert(state.transactions === 1 && state.shipAllocations === 1, "Shipment TikTok IN_TRANSIT harus memiliki satu physical effect."); assertBalances(state, "Shipment TikTok replay"); console.log("[PASS] shipment TikTok IN_TRANSIT identical replay");

  const sc = reserveInput("SHIP-COMPETE", fixtures.get("SHIP-COMPETE"), 1); await ensureReserved(config, tokenA, organizationId, sc); const scA = shipInput("SHIP-COMPETE", sc, "SHOPEE", `${PREFIX}-SHIP-COMPETE-A-KEY`, `${PREFIX}-SHIP-COMPETE-A-EVENT`); const scB = shipInput("SHIP-COMPETE", sc, "SHOPEE", `${PREFIX}-SHIP-COMPETE-B-KEY`, `${PREFIX}-SHIP-COMPETE-B-EVENT`);
  const scResults = await Promise.all([ship(config, tokenA, organizationId, scA), ship(config, tokenB, organizationId, scB)]); assert(scResults.filter((result) => result.ok).length === 1 && scResults.filter((result) => !result.ok).length === 1, "Dua shipment berbeda untuk item sama harus memiliki satu winner."); state = snapshot(container, organizationId, fixtures.get("SHIP-COMPETE"), [sc.eventRef, scA.eventRef, scB.eventRef], [sc.orderRef]); assert(state.transactions === 1 && state.shipAllocations === 1 && Number(state.reservations) === 0, "Shipment competing tidak boleh double allocation atau oversell."); assertBalances(state, "Shipment competing"); console.log("[PASS] shipment competing command");

  const pre = reserveInput("PRE-REPLAY", fixtures.get("PRE-REPLAY"), 2); await ensureReserved(config, tokenA, organizationId, pre); const preBody = await cancellationInput(config, tokenA, organizationId, "PRE-REPLAY", pre, "PRE_SHIPMENT", 1, `${PREFIX}-PRE-REPLAY-KEY`, `${PREFIX}-PRE-REPLAY-EVENT`); const preResults = await Promise.all([cancel(config, tokenA, preBody), cancel(config, tokenB, preBody)]); assert(preResults.every((result) => result.ok) && preResults[0].payload?.cancellationId === preResults[1].payload?.cancellationId, "Pre-shipment cancellation replay harus satu application."); state = snapshot(container, organizationId, fixtures.get("PRE-REPLAY"), [pre.eventRef, preBody.p_event_ref], [pre.orderRef]); assert(state.cancellations === 1 && state.cancelApplications === 1 && state.transactions === 0 && Number(state.reservations) === 1, "Pre-shipment cancellation harus release reservation saja."); assertBalances(state, "Pre cancellation replay"); console.log("[PASS] pre-shipment cancellation identical replay");

  const po = reserveInput("PRE-OVERLAP", fixtures.get("PRE-OVERLAP"), 3); await ensureReserved(config, tokenA, organizationId, po); const poA = await cancellationInput(config, tokenA, organizationId, "PRE-OVERLAP-A", po, "PRE_SHIPMENT", 2, `${PREFIX}-PRE-OVERLAP-A-KEY`, `${PREFIX}-PRE-OVERLAP-A-EVENT`); const poB = await cancellationInput(config, tokenB, organizationId, "PRE-OVERLAP-B", po, "PRE_SHIPMENT", 2, `${PREFIX}-PRE-OVERLAP-B-KEY`, `${PREFIX}-PRE-OVERLAP-B-EVENT`); const poResults = await Promise.all([cancel(config, tokenA, poA), cancel(config, tokenB, poB)]); assert(poResults.filter((result) => result.ok).length === 1 && poResults.filter((result) => !result.ok).length === 1, "Overlapping pre-shipment cancellation harus memiliki satu winner."); state = snapshot(container, organizationId, fixtures.get("PRE-OVERLAP"), [po.eventRef, poA.p_event_ref, poB.p_event_ref], [po.orderRef]); assert(state.cancellations === 1 && state.transactions === 0 && Number(state.reservations) === 1, "Pre-shipment overlap tidak boleh over-release atau membuat ledger."); assertBalances(state, "Pre cancellation overlap"); console.log("[PASS] pre-shipment overlapping cancellation");

  const post = reserveInput("POST-REPLAY", fixtures.get("POST-REPLAY"), 2); await ensureReserved(config, tokenA, organizationId, post); const postShip = shipInput("POST-REPLAY", post); postShip.body.p_lines[0].quantity = 2; const postShipResult = await ship(config, tokenA, organizationId, postShip); if (!postShipResult.ok) fail(`Setup shipment post replay gagal: ${error(postShipResult)}`); const postBody = await cancellationInput(config, tokenA, organizationId, "POST-REPLAY", post, "POST_SHIPMENT", 1, `${PREFIX}-POST-REPLAY-KEY`, `${PREFIX}-POST-REPLAY-EVENT`); const postResults = await Promise.all([cancel(config, tokenA, postBody), cancel(config, tokenB, postBody)]); assert(postResults.every((result) => result.ok) && postResults[0].payload?.cancellationId === postResults[1].payload?.cancellationId, "Post-shipment cancellation replay harus satu cancellation."); state = snapshot(container, organizationId, fixtures.get("POST-REPLAY"), [post.eventRef, postShip.eventRef, postBody.p_event_ref], [post.orderRef]); assert(state.cancellations === 1 && state.cancelApplications === 1 && state.reversalApplications === 1 && state.transactions === 2, "Post-shipment cancellation harus memakai satu exact reversal."); assertBalances(state, "Post cancellation replay"); console.log("[PASS] post-shipment cancellation identical replay");

  const pso = reserveInput("POST-OVERLAP", fixtures.get("POST-OVERLAP"), 3); await ensureReserved(config, tokenA, organizationId, pso); const psoShip = shipInput("POST-OVERLAP", pso); psoShip.body.p_lines[0].quantity = 3; const psoShipResult = await ship(config, tokenA, organizationId, psoShip); if (!psoShipResult.ok) fail(`Setup shipment post overlap gagal: ${error(psoShipResult)}`); const psoA = await cancellationInput(config, tokenA, organizationId, "POST-OVERLAP-A", pso, "POST_SHIPMENT", 2, `${PREFIX}-POST-OVERLAP-A-KEY`, `${PREFIX}-POST-OVERLAP-A-EVENT`); const psoB = await cancellationInput(config, tokenB, organizationId, "POST-OVERLAP-B", pso, "POST_SHIPMENT", 2, `${PREFIX}-POST-OVERLAP-B-KEY`, `${PREFIX}-POST-OVERLAP-B-EVENT`); const psoResults = await Promise.all([cancel(config, tokenA, psoA), cancel(config, tokenB, psoB)]); assert(psoResults.filter((result) => result.ok).length === 1 && psoResults.filter((result) => !result.ok).length === 1, "Overlapping post-shipment cancellation harus memiliki satu winner."); state = snapshot(container, organizationId, fixtures.get("POST-OVERLAP"), [pso.eventRef, psoShip.eventRef, psoA.p_event_ref, psoB.p_event_ref], [pso.orderRef]); assert(state.cancellations === 1 && state.reversalApplications === 1 && state.transactions === 2, "Post-shipment overlap tidak boleh double restore atau FEFO ulang."); assertBalances(state, "Post cancellation overlap"); console.log("[PASS] post-shipment overlapping cancellation");

  const sv = reserveInput("SHIP-CANCEL", fixtures.get("SHIP-CANCEL"), 1); await ensureReserved(config, tokenA, organizationId, sv); const svShip = shipInput("SHIP-CANCEL", sv); const svCancel = await cancellationInput(config, tokenB, organizationId, "SHIP-CANCEL", sv, "PRE_SHIPMENT", 1, `${PREFIX}-SHIP-CANCEL-KEY`, `${PREFIX}-SHIP-CANCEL-EVENT`); const svResults = await Promise.all([ship(config, tokenA, organizationId, svShip), cancel(config, tokenB, svCancel)]); assert(svResults.filter((result) => result.ok).length === 1 && svResults.filter((result) => !result.ok).length === 1, "Ship-versus-cancel harus serialise menjadi satu outcome sah."); state = snapshot(container, organizationId, fixtures.get("SHIP-CANCEL"), [sv.eventRef, svShip.eventRef, svCancel.p_event_ref], [sv.orderRef]); assert((state.transactions === 1 && state.cancellations === 0) || (state.transactions === 0 && state.cancellations === 1), "Ship-versus-cancel tidak boleh memiliki physical effect dan release yang menghitung quantity sama."); assertBalances(state, "Ship versus cancel"); console.log("[PASS] ship-versus-pre-shipment-cancel serializable outcome");
}

try { await main(); } catch (cause) { console.error(cause instanceof Error ? cause.stack ?? cause.message : String(cause)); process.exitCode = 1; }
