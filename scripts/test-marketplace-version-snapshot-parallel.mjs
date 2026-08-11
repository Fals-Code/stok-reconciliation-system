import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";

const EMAIL = process.env.MARKETPLACE_VERSION_PARALLEL_EMAIL ?? "demo.admin@glowlab.invalid";
const TIMEOUT_MS = 30_000;
const PREFIX = "CONCURRENCY-MARKETPLACE-VERSION-V1";
const V1_AT = "2026-07-01T00:00:00Z";
const V2_AT = "2026-08-01T00:00:00Z";
const OLD_EVENT_AT = "2026-07-31T12:00:00Z";

function fail(message) { throw new Error(message); }
function assert(condition, message) { if (!condition) fail(message); }
function value(input) { return String(input ?? "").trim(); }
function errorCode(result) { return value(result?.payload?.message ?? result?.payload?.code); }
function literal(input) { return `'${String(input).replaceAll("'", "''")}'`; }

function resolvePassword(config) {
  const pwd = process.env.MARKETPLACE_VERSION_PARALLEL_PASSWORD ?? config?.MARKETPLACE_VERSION_PARALLEL_PASSWORD ?? process.env.PARALLEL_TEST_PASSWORD ?? config?.PARALLEL_TEST_PASSWORD;
  if (!pwd || typeof pwd !== "string" || pwd.trim() === "") {
    fail("Password harness tidak ditemukan pada MARKETPLACE_VERSION_PARALLEL_PASSWORD atau PARALLEL_TEST_PASSWORD.");
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
  const container = result.stdout.split(/\r?\n/).map((line) => line.trim()).find((line) => line.startsWith("supabase_db_"));
  if (!container) fail("Container database Supabase lokal tidak ditemukan.");
  return container;
}

function sqlJson(container, sql) {
  const result = spawnSync("docker", ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-t", "-A", "-q"], {
    input: sql, encoding: "utf8", windowsHide: true, maxBuffer: 4 * 1024 * 1024,
  });
  if (result.status !== 0) fail(`Snapshot database gagal: ${result.stderr.slice(-800)}`);
  const line = result.stdout.split(/\r?\n/).map((item) => item.trim()).findLast((item) => item.startsWith("{") || item === "null");
  if (!line) fail("Snapshot database tidak mengembalikan JSON.");
  return JSON.parse(line);
}

async function login(config) {
  validateSupabaseUrl(config);
  const password = resolvePassword(config);
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) fail(`Login Admin gagal (${response.status}).`);
  const payload = await response.json();
  if (!payload.access_token) fail("Login tidak menghasilkan session independen.");
  return payload.access_token;
}

async function rpc(config, token, name, body) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${token}`,
      "Accept-Profile": "api",
      "Content-Profile": "api",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const raw = await response.text();
  let payload;
  try { payload = raw ? JSON.parse(raw) : null; } catch { payload = { message: raw }; }
  return { ok: response.ok, status: response.status, payload };
}

async function profile(config, token) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/current_admin_profile?select=organization_id,role_code&limit=1`, {
    headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api" },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) fail(`Profil Admin gagal (${response.status}).`);
  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length !== 1 || rows[0]?.role_code !== "ADMIN" || !rows[0]?.organization_id) fail("Fixture Admin aktif tidak ditemukan.");
  return rows[0];
}

function fixtureSizeMl(value) { let hash = 2166136261; for (const char of String(value)) { hash ^= char.charCodeAt(0); hash = Math.imul(hash, 16777619); } return 1000 + ((hash >>> 0) % 1000000000); }

function names(kind) {
  const stem = `${PREFIX}-${kind}`;
  return {
    kind,
    listing: `${stem}-LISTING`,
    products: ["A", "B", "C"].map((suffix) => ({
      sku: `${stem}-PRODUCT-${suffix}`,
      batch: `${stem}-BATCH-${suffix}`,
      productKey: `${stem}-PRODUCT-${suffix}`,
      batchKey: `${stem}-BATCH-${suffix}`,
      receiptKey: `${stem}-RECEIPT-${suffix}`,
    })),
  };
}

async function ensureProduct(config, token, organizationId, item) {
  const product = await rpc(config, token, "create_product", {
    p_organization_id: organizationId, p_idempotency_key: item.productKey,
    p_name: `Fixture version concurrency ${item.sku}`, p_size_ml: fixtureSizeMl(item.productKey), p_unit_code: "UNIT", p_description: "Fixture durable Issue #56.", p_note: "Marketplace version fixture.",
  });
  if (!product.ok || !product.payload?.productId) fail(`Create product ${item.sku} gagal: ${errorCode(product)}`);
  const batch = await rpc(config, token, "create_product_batch", {
    p_organization_id: organizationId, p_idempotency_key: item.batchKey, p_product_id: product.payload.productId, p_batch_code: item.batch,
    p_expiry_date: "2028-01-01", p_manufactured_date: "2026-06-01", p_received_first_at: V1_AT, p_batch_kind_code: "STANDARD", p_note: "Fixture durable Issue #56.",
  });
  if (!batch.ok || !batch.payload?.batchId) fail(`Create batch ${item.sku} gagal: ${errorCode(batch)}`);
  const receipt = await rpc(config, token, "post_receipt", {
    p_organization_id: organizationId, p_idempotency_key: item.receiptKey, p_source_ref: `${item.receiptKey}-SOURCE`, p_occurred_at: V1_AT,
    p_lines: [{ productId: product.payload.productId, batchId: batch.payload.batchId, quantity: 30, sourceLineRef: "FIXTURE-1" }],
    p_note: "Fixture stock Issue #56.", p_metadata: { source: "marketplace-version-parallel", fixture: item.sku, version: 1 },
  });
  if (!receipt.ok) fail(`Receipt ${item.sku} gagal: ${errorCode(receipt)}`);
  return product.payload.productId;
}

async function activate(config, token, organizationId, listingId, versionId, key) {
  const preview = await rpc(config, token, "preview_marketplace_listing_version_activation", {
    p_organization_id: organizationId, p_listing_id: listingId, p_version_id: versionId,
  });
  if (!preview.ok || preview.payload?.eligible !== true || !preview.payload?.basisHash) fail(`Preview ${key} gagal: ${errorCode(preview)}`);
  return rpc(config, token, "activate_marketplace_listing_version", {
    p_organization_id: organizationId, p_idempotency_key: key, p_listing_id: listingId, p_version_id: versionId,
    p_expected_row_version: Number(preview.payload.versionRowVersion), p_preview_basis_hash: preview.payload.basisHash, p_confirmation: true,
  });
}

function fixture(container, organizationId, item) {
  return sqlJson(container, `
select coalesce((
  select jsonb_build_object(
    'listingId', listing.id,
    'listingType', listing.listing_type_code,
    'v1Id', (select version.id from catalog.marketplace_single_listing_versions version where version.organization_id=listing.organization_id and version.listing_id=listing.id and version.version=1),
    'v2Id', (select version.id from catalog.marketplace_single_listing_versions version where version.organization_id=listing.organization_id and version.listing_id=listing.id and version.version=2),
    'bundleV1Id', (select recipe.id from catalog.bundle_recipes recipe where recipe.organization_id=listing.organization_id and recipe.channel_id=listing.channel_id and recipe.external_listing_sku=listing.external_listing_code and recipe.version=1),
    'bundleV2Id', (select recipe.id from catalog.bundle_recipes recipe where recipe.organization_id=listing.organization_id and recipe.channel_id=listing.channel_id and recipe.external_listing_sku=listing.external_listing_code and recipe.version=2),
    'products', (select jsonb_agg(product.id order by product.name, product.id) from catalog.products product where product.organization_id=${literal(organizationId)}::uuid and product.name like ${literal(`Fixture version concurrency ${PREFIX}-${item.kind}-PRODUCT-%`)})
  )
  from catalog.marketplace_listings listing
  join catalog.channels channel on channel.id=listing.channel_id
  where listing.organization_id=${literal(organizationId)}::uuid and channel.code='SHOPEE' and listing.external_listing_code=${literal(item.listing)}
  limit 1
), 'null'::jsonb);
`);
}

async function ensureFixture(config, token, container, organizationId, kind, listingType) {
  const item = names(kind);
  let current = fixture(container, organizationId, item);
  if (current?.v2Id || current?.bundleV2Id) return { item, current };

  const [productA, productB, productC] = await Promise.all(item.products.map((product) => ensureProduct(config, token, organizationId, product)));
  const v1Components = listingType === "BUNDLE"
    ? [{ productId: productA, quantity: 1 }, { productId: productB, quantity: 2 }]
    : [];
  const draftV1 = await rpc(config, token, "create_marketplace_listing_version_draft", {
    p_organization_id: organizationId, p_idempotency_key: `${PREFIX}-${kind}-DRAFT-V1`, p_channel_code: "SHOPEE", p_external_listing_code: item.listing,
    p_display_name: `Version fixture ${kind}`, p_listing_type_code: listingType, p_effective_from: V1_AT,
    p_product_id: listingType === "SINGLE" ? productA : null, p_components: v1Components, p_note: "Fixture version satu.", p_metadata: { source: "marketplace-version-parallel", fixture: kind, version: 1 },
  });
  if (!draftV1.ok || draftV1.payload?.status !== "DRAFT_CREATED") fail(`Draft v1 ${kind} gagal: ${errorCode(draftV1)}`);
  const activationV1 = await activate(config, token, organizationId, draftV1.payload.listingId, draftV1.payload.versionId, `${PREFIX}-${kind}-ACTIVATE-V1`);
  if (!activationV1.ok || activationV1.payload?.status !== "ACTIVATED") fail(`Aktivasi v1 ${kind} gagal: ${errorCode(activationV1)}`);
  const v2Components = listingType === "BUNDLE" ? [{ productId: productC, quantity: 3 }] : [];
  const draftV2 = await rpc(config, token, "create_marketplace_listing_version_draft", {
    p_organization_id: organizationId, p_idempotency_key: `${PREFIX}-${kind}-DRAFT-V2`, p_channel_code: "SHOPEE", p_external_listing_code: item.listing,
    p_display_name: `Version fixture ${kind} v2`, p_listing_type_code: listingType, p_effective_from: V2_AT,
    p_product_id: listingType === "SINGLE" ? productC : null, p_components: v2Components, p_note: "Fixture version dua.", p_metadata: { source: "marketplace-version-parallel", fixture: kind, version: 2 },
  });
  if (!draftV2.ok || draftV2.payload?.status !== "DRAFT_CREATED") fail(`Draft v2 ${kind} gagal: ${errorCode(draftV2)}`);
  current = fixture(container, organizationId, item);
  if (!current?.listingId || !(current.v2Id || current.bundleV2Id)) fail(`Fixture ${kind} tidak terbentuk melalui lifecycle resmi.`);
  return { item, current };
}

function reserveBody(organizationId, item, eventRef) {
  return {
    p_organization_id: organizationId, p_idempotency_key: `${PREFIX}-${eventRef}-KEY`, p_channel_code: "SHOPEE", p_event_ref: eventRef, p_order_ref: `${eventRef}-ORDER`,
    p_source_status: "READY_TO_SHIP", p_occurred_at: OLD_EVENT_AT, p_received_at: "2026-08-02T00:00:00Z",
    p_lines: [{ sourceLineRef: "LINE-1", externalListingCode: item.listing, listingQuantity: 2, sourceStatus: "READY_TO_SHIP" }],
    p_note: `Version race ${item.kind}.`, p_raw_payload: { adapter: "SIMULATOR", fixture: item.kind }, p_metadata: { adapter: "SIMULATOR", fixture: item.kind }, p_schema_version: 1,
  };
}

function snapshot(container, organizationId, refs) {
  const quoted = refs.map(literal).join(",");
  const orderRefs = refs.map((ref) => literal(`${ref}-ORDER`)).join(",");
  return sqlJson(container, `
select jsonb_build_object(
  'events', (select count(*) from operations.marketplace_events event where event.organization_id=${literal(organizationId)}::uuid and event.external_event_ref in (${quoted})),
  'orders', (select count(*) from operations.marketplace_orders orders where orders.organization_id=${literal(organizationId)}::uuid and orders.external_order_ref in (${orderRefs})),
  'normalizations', (select count(*) from operations.marketplace_normalization_events normalization where normalization.organization_id=${literal(organizationId)}::uuid and normalization.external_event_ref_snapshot in (${quoted})),
  'components', (select count(*) from operations.marketplace_source_line_components component join operations.marketplace_source_lines line on line.id=component.source_line_id where component.organization_id=${literal(organizationId)}::uuid and line.normalization_event_id in (select normalization.id from operations.marketplace_normalization_events normalization where normalization.organization_id=${literal(organizationId)}::uuid and normalization.external_event_ref_snapshot in (${quoted}))),
  'transactions', (select count(*) from inventory.stock_transactions transaction where transaction.organization_id=${literal(organizationId)}::uuid and transaction.source_ref_snapshot in (${quoted})),
  'ledger', (select count(*) from inventory.stock_ledger_entries ledger join inventory.stock_transactions transaction on transaction.id=ledger.transaction_id where transaction.organization_id=${literal(organizationId)}::uuid and transaction.source_ref_snapshot in (${quoted}))
);
`);
}

function sourceSnapshot(container, organizationId, eventRef) {
  return sqlJson(container, `
select coalesce((select jsonb_build_object(
  'singleVersionId', line.single_listing_version_id,
  'bundleRecipeId', line.bundle_recipe_id,
  'mappingVersion', line.mapping_version,
  'components', (select jsonb_agg(jsonb_build_object('productId', component.product_id, 'quantity', component.expanded_quantity) order by component.component_no) from operations.marketplace_source_line_components component where component.source_line_id=line.id)
) from operations.marketplace_source_lines line join operations.marketplace_normalization_events normalization on normalization.id=line.normalization_event_id where line.organization_id=${literal(organizationId)}::uuid and normalization.external_event_ref_snapshot=${literal(eventRef)} limit 1), 'null'::jsonb);
`);
}

async function race(config, firstToken, secondToken, organizationId, fixtureValue, activationFirst) {
  const eventRef = `${PREFIX}-${fixtureValue.item.kind}-EVENT`;
  const versionId = fixtureValue.current.v2Id ?? fixtureValue.current.bundleV2Id;
  const preview = await rpc(config, firstToken, "preview_marketplace_listing_version_activation", {
    p_organization_id: organizationId, p_listing_id: fixtureValue.current.listingId, p_version_id: versionId,
  });
  if (!preview.ok || preview.payload?.eligible !== true || !preview.payload?.basisHash) fail(`Preview parallel ${fixtureValue.item.kind} gagal: ${errorCode(preview)}`);
  const activationBody = {
    p_organization_id: organizationId, p_idempotency_key: `${PREFIX}-${fixtureValue.item.kind}-ACTIVATE-V2`, p_listing_id: fixtureValue.current.listingId,
    p_version_id: versionId, p_expected_row_version: Number(preview.payload.versionRowVersion), p_preview_basis_hash: preview.payload.basisHash, p_confirmation: true,
  };
  const reserve = () => rpc(config, secondToken, "reserve_marketplace_listing_event", reserveBody(organizationId, fixtureValue.item, eventRef));
  const activateVersion = () => rpc(config, firstToken, "activate_marketplace_listing_version", activationBody);
  const results = activationFirst ? await Promise.all([activateVersion(), reserve()]) : await Promise.all([reserve(), activateVersion()]);
  assert(results.every((result) => result.ok), `${fixtureValue.item.kind}: lifecycle/reservation race harus selesai bounded tanpa deadlock (${results.map(errorCode).join(", ")}).`);
  const state = snapshot(dbContainer(), organizationId, [eventRef]);
  assert(state.events === 1 && state.orders === 1 && state.normalizations === 1, `${fixtureValue.item.kind}: race hanya boleh membuat satu canonical event/order/snapshot.`);
  assert(state.transactions === 0 && state.ledger === 0, `${fixtureValue.item.kind}: reservation race harus stock-neutral.`);
  return { eventRef, state };
}

async function assertParallelOrganizationIsolation(config, tokenA, tokenB, organizationId, item, eventRef) {
  const [sameOrganizationReplay, crossOrganization] = await Promise.all([
    rpc(config, tokenB, "reserve_marketplace_listing_event", reserveBody(organizationId, item, eventRef)),
    rpc(config, tokenA, "reserve_marketplace_listing_event", {
      ...reserveBody("00000000-0000-0000-0000-000000000001", item, `${PREFIX}-CROSS-ORG`),
      p_idempotency_key: `${PREFIX}-CROSS-ORG-KEY`,
    }),
  ]);
  assert(sameOrganizationReplay.ok && sameOrganizationReplay.payload?.externalEventOutcome === "REPLAYED", "Parallel same-organization replay harus memakai stored canonical result.");
  assert(!crossOrganization.ok && errorCode(crossOrganization) === "ORGANIZATION_ACCESS_DENIED", "Parallel organisasi lain harus ditolak sebelum resolver atau lock fixture dapat diakses.");
}

async function main() {
  const config = await env();
  const container = dbContainer();
  const [tokenA, tokenB] = await Promise.all([login(config), login(config)]);
  assert(tokenA !== tokenB, "Harness membutuhkan dua session Admin independen.");
  const [profileA, profileB] = await Promise.all([profile(config, tokenA), profile(config, tokenB)]);
  assert(profileA.organization_id === profileB.organization_id, "Dua session harus memakai organisasi fixture yang sama.");
  const organizationId = profileA.organization_id;
  const single = await ensureFixture(config, tokenA, container, organizationId, "SINGLE", "SINGLE");
  const bundle = await ensureFixture(config, tokenA, container, organizationId, "BUNDLE", "BUNDLE");
  const singleRef = `${PREFIX}-SINGLE-EVENT`;
  const bundleRef = `${PREFIX}-BUNDLE-EVENT`;
  const terminal = snapshot(container, organizationId, [singleRef, bundleRef]);

  if (terminal.events === 2 && terminal.orders === 2 && terminal.normalizations === 2 && terminal.transactions === 0 && terminal.ledger === 0) {
    const before = JSON.stringify(terminal);
    const singleStored = sourceSnapshot(container, organizationId, singleRef);
    const bundleStored = sourceSnapshot(container, organizationId, bundleRef);
    assert(singleStored?.singleVersionId === single.current.v1Id && Number(singleStored.mappingVersion) === 1, "Rerun durable: snapshot SINGLE harus tetap versi awal berdasarkan occurred_at.");
    assert(bundleStored?.bundleRecipeId === bundle.current.bundleV1Id && Number(bundleStored.mappingVersion) === 1 && Array.isArray(bundleStored.components) && bundleStored.components.length === 2, "Rerun durable: snapshot BUNDLE harus tetap satu recipe v1 lengkap.");
    await assertParallelOrganizationIsolation(config, tokenA, tokenB, organizationId, single.item, singleRef);
    assert(JSON.stringify(snapshot(container, organizationId, [singleRef, bundleRef])) === before, "Rerun durable tidak boleh menambah event, order, snapshot, ledger, atau transaction.");
    console.log("[PASS] run kedua memverifikasi snapshot immutable dan replay tanpa pertumbuhan fixture");
    console.log("Marketplace version snapshot parallel harness PASS (durable replay)");
    return;
  }

  assert(terminal.events === 0 && terminal.orders === 0 && terminal.normalizations === 0, "Fixture version concurrency berada pada state parsial; hentikan tanpa menambah effect.");
  const singleRace = await race(config, tokenA, tokenB, organizationId, single, true);
  const singleStored = sourceSnapshot(container, organizationId, singleRace.eventRef);
  assert(singleStored?.singleVersionId === single.current.v1Id && Number(singleStored.mappingVersion) === 1 && singleStored.components?.[0]?.productId === single.current.products[0], "SINGLE race harus menyimpan satu snapshot v1 lengkap untuk occurred_at sebelum boundary.");
  console.log("[PASS] listing SINGLE activation-versus-reservation menggunakan satu mapping historis lengkap");

  const bundleRace = await race(config, tokenA, tokenB, organizationId, bundle, false);
  const bundleStored = sourceSnapshot(container, organizationId, bundleRace.eventRef);
  assert(bundleStored?.bundleRecipeId === bundle.current.bundleV1Id && Number(bundleStored.mappingVersion) === 1, "BUNDLE race harus menyimpan recipe v1 untuk occurred_at sebelum boundary.");
  assert(Array.isArray(bundleStored.components) && bundleStored.components.length === 2 && bundleStored.components.every((component, index) => component.productId === bundle.current.products[index] && Number(component.quantity) === [2, 4][index]), "BUNDLE race tidak boleh mencampur komponen atau quantity lintas versi.");
  console.log("[PASS] bundle activation-versus-reservation menggunakan satu recipe dan component snapshot lengkap");

  await assertParallelOrganizationIsolation(config, tokenA, tokenB, organizationId, single.item, singleRace.eventRef);
  const conflict = await rpc(config, tokenB, "reserve_marketplace_listing_event", {
    ...reserveBody(organizationId, single.item, singleRace.eventRef), p_idempotency_key: `${PREFIX}-SINGLE-CONFLICT-KEY`, p_lines: [{ sourceLineRef: "LINE-1", externalListingCode: single.item.listing, listingQuantity: 3, sourceStatus: "READY_TO_SHIP" }],
  });
  assert(!conflict.ok && errorCode(conflict) === "MARKETPLACE_EXTERNAL_EVENT_CONFLICT", "Changed payload tidak boleh mengganti snapshot pertama.");
  const final = snapshot(container, organizationId, [singleRace.eventRef, bundleRace.eventRef]);
  assert(final.events === 2 && final.orders === 2 && final.normalizations === 2 && final.components === 3 && final.transactions === 0 && final.ledger === 0, "Race, replay, dan conflict harus mempertahankan exact canonical snapshot tanpa effect fisik.");
  console.log("[PASS] opposite request order selesai bounded; replay dan conflict mempertahankan snapshot pertama");
  console.log("Marketplace version snapshot parallel harness PASS");
}

main().catch((error) => { console.error(error instanceof Error ? error.stack ?? error.message : String(error)); process.exitCode = 1; });
