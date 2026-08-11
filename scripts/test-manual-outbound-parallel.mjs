import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import process from "node:process";

const EMAIL = process.env.MANUAL_OUTBOUND_PARALLEL_EMAIL ?? "demo.admin@glowlab.invalid";
const TIMEOUT_MS = 30_000;
const PREFIX = "CONCURRENCY-FEFO-V1";
const OCCURRED_AT = "2026-07-26T10:00:00Z";
const RECEIPT_AT = "2026-07-26T09:00:00Z";

const scenarios = [
  { name: "REPLAY", receiptQuantity: 2, outboundQuantity: 1, expiryDate: "2028-01-11" },
  { name: "CONFLICT", receiptQuantity: 3, outboundQuantity: 1, expiryDate: "2028-01-12" },
  { name: "CONTENTION", receiptQuantity: 1, outboundQuantity: 1, expiryDate: "2028-01-13" },
];

function fail(message) { throw new Error(message); }
function assert(condition, message) { if (!condition) fail(message); }
function value(valueToCheck) { return String(valueToCheck ?? "").trim(); }
function sqlLiteral(input) { return `'${String(input).replaceAll("'", "''")}'`; }

function resolvePassword(config) {
  const pwd = process.env.MANUAL_OUTBOUND_PARALLEL_PASSWORD ?? config?.MANUAL_OUTBOUND_PARALLEL_PASSWORD ?? process.env.PARALLEL_TEST_PASSWORD ?? config?.PARALLEL_TEST_PASSWORD;
  if (!pwd || typeof pwd !== "string" || pwd.trim() === "") {
    fail("Password harness tidak ditemukan pada MANUAL_OUTBOUND_PARALLEL_PASSWORD atau PARALLEL_TEST_PASSWORD.");
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

async function readEnv() {
  const text = await readFile(".env.local", "utf8");
  return Object.fromEntries(text.split(/\r?\n/).filter((line) => line && !line.startsWith("#") && line.includes("=")).map((line) => {
    const index = line.indexOf("=");
    return [line.slice(0, index), line.slice(index + 1).replace(/^['\"]|['\"]$/g, "")];
  }));
}

function databaseContainer() {
  const result = spawnSync("docker", ["ps", "--format", "{{.Names}}"], { encoding: "utf8", windowsHide: true });
  if (result.status !== 0) fail("Docker Supabase lokal tidak dapat diperiksa.");
  const container = result.stdout.split(/\r?\n/).map((name) => name.trim()).find((name) => name.startsWith("supabase_db_"));
  if (!container) fail("Container database Supabase lokal tidak ditemukan.");
  return container;
}

function sqlJson(container, sql) {
  const result = spawnSync("docker", ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-t", "-A", "-q"], { input: sql, encoding: "utf8", windowsHide: true, maxBuffer: 2 * 1024 * 1024 });
  if (result.status !== 0) fail(`Snapshot database gagal: ${result.stderr.slice(-1000)}`);
  const line = result.stdout.split(/\r?\n/).map((entry) => entry.trim()).findLast((entry) => entry.startsWith("{") || entry === "null");
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
  if (!response.ok) fail(`Login harness gagal (${response.status}).`);
  const payload = await response.json();
  if (!payload.access_token) fail("Login harness tidak menghasilkan access token.");
  return payload.access_token;
}

async function profile(config, token) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/current_admin_profile?select=*&limit=1`, {
    headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api", "Content-Type": "application/json" },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) fail(`Profile harness gagal (${response.status}).`);
  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length !== 1 || !rows[0]?.organization_id || rows[0]?.role_code !== "ADMIN") fail("Admin fixture aktif tidak ditemukan.");
  return rows[0];
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
  const text = await response.text();
  let payload;
  try { payload = text ? JSON.parse(text) : null; } catch { payload = { message: text }; }
  return { ok: response.ok, status: response.status, payload };
}

function errorCode(result) {
  return value(result?.payload?.message ?? result?.payload?.code);
}

function fixtureSizeMl(value) { let hash = 2166136261; for (const char of String(value)) { hash ^= char.charCodeAt(0); hash = Math.imul(hash, 16777619); } return 1000 + ((hash >>> 0) % 1000000000); }

function scenarioNames(scenario) {
  const stem = `${PREFIX}-${scenario.name}`;
  return {
    productName: `Fixture FEFO concurrency ${scenario.name}`,
    batchCode: `${stem}-BATCH`,
    receiptSource: `${stem}-RECEIPT`,
    receiptKey: `${stem}-RECEIPT-KEY`,
    productKey: `${stem}-PRODUCT-KEY`,
    batchKey: `${stem}-BATCH-KEY`,
  };
}

function lookupFixture(container, organizationId, scenario) {
  const names = scenarioNames(scenario);
  return sqlJson(container, `
select coalesce((
  select jsonb_build_object(
    'productId', product.id,
    'batchId', batch.id,
    'receiptTransactionId', receipt.transaction_id,
    'receiptCount', (select count(*) from operations.receipts r where r.organization_id = product.organization_id and r.source_ref = ${sqlLiteral(names.receiptSource)})
  )
  from catalog.products product
  join catalog.product_batches batch on batch.organization_id = product.organization_id and batch.product_id = product.id
  join operations.receipts receipt on receipt.organization_id = product.organization_id and receipt.source_ref = ${sqlLiteral(names.receiptSource)}
  where product.organization_id = ${sqlLiteral(organizationId)}::uuid
    and product.name = ${sqlLiteral(names.productName)}
    and batch.batch_code = ${sqlLiteral(names.batchCode)}
  limit 1
), 'null'::jsonb);
`);
}

async function ensureFixture(config, token, container, organizationId, scenario) {
  let fixture = lookupFixture(container, organizationId, scenario);
  if (fixture) return fixture;
  const names = scenarioNames(scenario);
  const product = await rpc(config, token, "create_product", {
    p_organization_id: organizationId, p_idempotency_key: names.productKey,
    p_name: names.productName, p_size_ml: fixtureSizeMl(names.productKey), p_unit_code: "UNIT",
    p_description: "Fixture durable untuk harness concurrency manual outbound.", p_note: "Issue #56 harness fixture.",
  });
  if (!product.ok || !product.payload?.productId) fail(`Create product ${scenario.name} gagal: ${errorCode(product)}`);
  const batch = await rpc(config, token, "create_product_batch", {
    p_organization_id: organizationId, p_idempotency_key: names.batchKey, p_product_id: product.payload.productId,
    p_batch_code: names.batchCode, p_expiry_date: scenario.expiryDate, p_manufactured_date: "2026-07-01",
    p_received_first_at: RECEIPT_AT, p_batch_kind_code: "STANDARD", p_note: "Fixture durable Issue #56.",
  });
  if (!batch.ok || !batch.payload?.batchId) fail(`Create batch ${scenario.name} gagal: ${errorCode(batch)}`);
  const receipt = await rpc(config, token, "post_receipt", {
    p_organization_id: organizationId, p_idempotency_key: names.receiptKey, p_source_ref: names.receiptSource,
    p_occurred_at: RECEIPT_AT,
    p_lines: [{ productId: product.payload.productId, batchId: batch.payload.batchId, quantity: scenario.receiptQuantity, sourceLineRef: "CONCURRENCY-1" }],
    p_note: "Fixture stok terbatas untuk Issue #56.", p_metadata: { source: "manual-outbound-parallel-harness", version: 1, fixture: scenario.name },
  });
  if (!receipt.ok || !receipt.payload?.transactionId) fail(`Post receipt ${scenario.name} gagal: ${errorCode(receipt)}`);
  fixture = lookupFixture(container, organizationId, scenario);
  if (!fixture || fixture.receiptCount !== 1) fail(`Fixture ${scenario.name} tidak terbentuk secara tunggal.`);
  return fixture;
}

function command(sourceRef, productId, quantity, key) {
  return { key, sourceRef, quantity, body: {
    p_idempotency_key: key, p_source_ref: sourceRef, p_occurred_at: OCCURRED_AT,
    p_reason_code: "OFFLINE_SALE", p_lines: [{ productId, quantity, sourceLineRef: "CONCURRENCY-1" }],
    p_confirmation: true, p_note: `Issue #56 ${sourceRef}.`, p_metadata: { source: "manual-outbound-parallel-harness", version: 1, sourceRef },
  } };
}

async function previewCommand(config, token, organizationId, commandInput) {
  const preview = await rpc(config, token, "preview_manual_outbound", {
    p_organization_id: organizationId, p_source_ref: commandInput.sourceRef, p_occurred_at: OCCURRED_AT,
    p_reason_code: "OFFLINE_SALE", p_lines: commandInput.body.p_lines, p_note: commandInput.body.p_note, p_metadata: commandInput.body.p_metadata,
  });
  if (!preview.ok || preview.payload?.eligible !== true || !/^[0-9a-f]{64}$/.test(value(preview.payload?.basisHash))) fail(`Preview ${commandInput.sourceRef} tidak eligible: ${errorCode(preview)}`);
  commandInput.body.p_preview_basis_hash = preview.payload.basisHash;
  return preview.payload;
}

function snapshot(container, organizationId, fixture, sourceRefs) {
  const refs = sourceRefs.map(sqlLiteral).join(",");
  return sqlJson(container, `
select jsonb_build_object(
  'outboundCount', (select count(*) from operations.manual_outbounds o where o.organization_id=${sqlLiteral(organizationId)}::uuid and o.source_ref in (${refs})),
  'transactionCount', (select count(*) from inventory.stock_transactions t where t.organization_id=${sqlLiteral(organizationId)}::uuid and t.transaction_type_code='MANUAL_OUTBOUND' and t.source_ref_snapshot in (${refs})),
  'ledgerCount', (select count(*) from inventory.stock_ledger_entries e join inventory.stock_transactions t on t.id=e.transaction_id where t.organization_id=${sqlLiteral(organizationId)}::uuid and t.transaction_type_code='MANUAL_OUTBOUND' and t.source_ref_snapshot in (${refs})),
  'allocationQty', (select coalesce(sum(a.quantity_allocated),0) from operations.manual_outbound_allocations a join operations.manual_outbounds o on o.id=a.outbound_id where o.organization_id=${sqlLiteral(organizationId)}::uuid and o.source_ref in (${refs})),
  'outboundQty', (select coalesce(sum(l.quantity_requested),0) from operations.manual_outbound_lines l join operations.manual_outbounds o on o.id=l.outbound_id where o.organization_id=${sqlLiteral(organizationId)}::uuid and o.source_ref in (${refs})),
  'product', (select jsonb_build_object('sellableQty',p.sellable_qty,'reservedQty',p.reserved_qty,'availableQty',p.sellable_qty-p.reserved_qty) from inventory.stock_product_positions p where p.organization_id=${sqlLiteral(organizationId)}::uuid and p.product_id=${sqlLiteral(fixture.productId)}::uuid),
  'batch', (select jsonb_build_object('sellableQty',b.sellable_qty,'version',b.version) from inventory.stock_batch_balances b where b.organization_id=${sqlLiteral(organizationId)}::uuid and b.batch_id=${sqlLiteral(fixture.batchId)}::uuid),
  'reservationCount', (select count(*) from inventory.stock_reservations r where r.organization_id=${sqlLiteral(organizationId)}::uuid and r.product_id=${sqlLiteral(fixture.productId)}::uuid)
);
`);
}

async function parallelPosts(config, leftToken, rightToken, organizationId, inputA, inputB) {
  const bodyA = { p_organization_id: organizationId, ...inputA.body };
  const bodyB = { p_organization_id: organizationId, ...inputB.body };
  return Promise.all([
    rpc(config, leftToken, "post_manual_outbound", bodyA),
    rpc(config, rightToken, "post_manual_outbound", bodyB),
  ]);
}

function terminalSnapshot(container, organizationId, fixtures) {
  return fixtures.map(({ fixture, sourceRefs }) => snapshot(container, organizationId, fixture, sourceRefs));
}

async function main() {
  const config = await readEnv();
  const container = databaseContainer();
  const tokenA = await login(config);
  const tokenB = await login(config);
  assert(tokenA !== tokenB, "Harness membutuhkan dua session login independen.");
  const [profileA, profileB] = await Promise.all([profile(config, tokenA), profile(config, tokenB)]);
  assert(profileA.organization_id === profileB.organization_id, "Dua session harus berada pada organisasi fixture yang sama.");
  const organizationId = profileA.organization_id;
  const fixtureByName = new Map();
  for (const scenario of scenarios) fixtureByName.set(scenario.name, await ensureFixture(config, tokenA, container, organizationId, scenario));

  const replay = { scenario: scenarios[0], fixture: fixtureByName.get("REPLAY"), sourceRefs: [`${PREFIX}-REPLAY-OUTBOUND`] };
  const conflict = { scenario: scenarios[1], fixture: fixtureByName.get("CONFLICT"), sourceRefs: [`${PREFIX}-CONFLICT-OUTBOUND`] };
  const contention = { scenario: scenarios[2], fixture: fixtureByName.get("CONTENTION"), sourceRefs: [`${PREFIX}-CONTENTION-A`, `${PREFIX}-CONTENTION-B`] };
  const all = [replay, conflict, contention];
  const beforeTerminal = terminalSnapshot(container, organizationId, all);
  const terminal = beforeTerminal.every((state, index) => state.outboundCount === (index < 2 ? 1 : 1));
  if (terminal) {
    for (const [index, state] of beforeTerminal.entries()) {
      assert(state.transactionCount === 1 && state.outboundQty === state.allocationQty, `Run kedua: fixture ${all[index].scenario.name} harus memiliki satu effect ledger/allocation yang konsisten.`);
      assert(Number(state.product.availableQty) >= 0 && Number(state.batch.sellableQty) >= 0 && state.reservationCount === 0, `Run kedua: fixture ${all[index].scenario.name} tidak boleh oversell atau mengubah reservation.`);
    }
    const afterTerminal = terminalSnapshot(container, organizationId, all);
    assert(JSON.stringify(afterTerminal) === JSON.stringify(beforeTerminal), "Run kedua hanya membaca fixture terminal dan tidak menambah domain effect.");
    console.log("[PASS] durable rerun mempertahankan seluruh fixture terminal tanpa outbound/ledger/allocation baru");
    return;
  }

  const replayCommand = command(replay.sourceRefs[0], replay.fixture.productId, 1, `${PREFIX}-REPLAY-KEY`);
  const replayPreview = await previewCommand(config, tokenA, organizationId, replayCommand);
  assert(replayPreview.allocations.length === 1 && replayPreview.allocations[0].batchId === replay.fixture.batchId, "Preview replay harus memilih batch fixture FEFO yang tepat.");
  const replayBefore = snapshot(container, organizationId, replay.fixture, replay.sourceRefs);
  const [replayA, replayB] = await parallelPosts(config, tokenA, tokenB, organizationId, replayCommand, replayCommand);
  assert(replayA.ok && replayB.ok && replayA.payload?.transactionId === replayB.payload?.transactionId, "Replay paralel harus menghasilkan satu response authoritative/replay yang sama.");
  const replayAfter = snapshot(container, organizationId, replay.fixture, replay.sourceRefs);
  assert(replayAfter.outboundCount === 1 && replayAfter.transactionCount === 1 && replayAfter.outboundQty === 1 && replayAfter.allocationQty === 1 && replayAfter.ledgerCount === 1, "Replay paralel hanya membuat satu outbound, transaction, ledger entry, dan allocation.");
  assert(Number(replayAfter.product.sellableQty) === Number(replayBefore.product.sellableQty) - 1 && Number(replayAfter.batch.sellableQty) === Number(replayBefore.batch.sellableQty) - 1 && replayAfter.reservationCount === replayBefore.reservationCount, "Replay paralel mengubah projection satu kali dan tidak mengubah reservation.");
  console.log("[PASS] identical replay paralel: satu effect FEFO");

  const conflictA = command(conflict.sourceRefs[0], conflict.fixture.productId, 1, `${PREFIX}-CONFLICT-KEY`);
  const conflictB = command(conflict.sourceRefs[0], conflict.fixture.productId, 2, `${PREFIX}-CONFLICT-KEY`);
  await Promise.all([previewCommand(config, tokenA, organizationId, conflictA), previewCommand(config, tokenB, organizationId, conflictB)]);
  const conflictBefore = snapshot(container, organizationId, conflict.fixture, conflict.sourceRefs);
  const [conflictResultA, conflictResultB] = await parallelPosts(config, tokenA, tokenB, organizationId, conflictA, conflictB);
  const conflictSuccesses = [conflictResultA, conflictResultB].filter((result) => result.ok);
  const conflictFailures = [conflictResultA, conflictResultB].filter((result) => !result.ok);
  assert(conflictSuccesses.length === 1 && conflictFailures.length === 1 && errorCode(conflictFailures[0]) === "IDEMPOTENCY_KEY_REUSED", "Changed payload paralel harus memiliki satu winner dan satu IDEMPOTENCY_KEY_REUSED.");
  const conflictAfter = snapshot(container, organizationId, conflict.fixture, conflict.sourceRefs);
  assert(conflictAfter.outboundCount === 1 && conflictAfter.transactionCount === 1 && [1, 2].includes(Number(conflictAfter.outboundQty)) && conflictAfter.outboundQty === conflictAfter.allocationQty, "Conflict paralel hanya mempersist satu payload utuh tanpa gabungan allocation.");
  assert(Number(conflictAfter.product.sellableQty) === Number(conflictBefore.product.sellableQty) - Number(conflictAfter.outboundQty) && Number(conflictAfter.batch.sellableQty) === Number(conflictBefore.batch.sellableQty) - Number(conflictAfter.outboundQty), "Projection conflict mengikuti satu payload authoritative.");
  console.log("[PASS] changed-payload paralel: conflict aman tanpa effect gabungan");

  const contentionA = command(contention.sourceRefs[0], contention.fixture.productId, 1, `${PREFIX}-CONTENTION-A-KEY`);
  const contentionB = command(contention.sourceRefs[1], contention.fixture.productId, 1, `${PREFIX}-CONTENTION-B-KEY`);
  const [contentionPreviewA, contentionPreviewB] = await Promise.all([previewCommand(config, tokenA, organizationId, contentionA), previewCommand(config, tokenB, organizationId, contentionB)]);
  assert(contentionPreviewA.allocations[0].batchId === contention.fixture.batchId && contentionPreviewB.allocations[0].batchId === contention.fixture.batchId, "Dua preview contention harus memakai batch FEFO terakhir yang sama.");
  const contentionBefore = snapshot(container, organizationId, contention.fixture, contention.sourceRefs);
  const [contentionResultA, contentionResultB] = await parallelPosts(config, tokenA, tokenB, organizationId, contentionA, contentionB);
  const contentionSuccesses = [contentionResultA, contentionResultB].filter((result) => result.ok);
  const contentionFailures = [contentionResultA, contentionResultB].filter((result) => !result.ok);
  assert(contentionSuccesses.length === 1 && contentionFailures.length === 1 && ["STALE_MANUAL_OUTBOUND_PREVIEW", "MANUAL_OUTBOUND_PREVIEW_BLOCKED"].includes(errorCode(contentionFailures[0])), "Contention stok terakhir harus memiliki satu winner dan satu penolakan stale/blocked yang aman.");
  const contentionAfter = snapshot(container, organizationId, contention.fixture, contention.sourceRefs);
  assert(contentionAfter.outboundCount === 1 && contentionAfter.transactionCount === 1 && contentionAfter.outboundQty === 1 && contentionAfter.allocationQty === 1 && contentionAfter.ledgerCount === 1, "Contention stok terakhir hanya membuat satu effect outbound/ledger/allocation.");
  assert(Number(contentionAfter.product.sellableQty) === Number(contentionBefore.product.sellableQty) - 1 && Number(contentionAfter.batch.sellableQty) === Number(contentionBefore.batch.sellableQty) - 1 && Number(contentionAfter.product.availableQty) === 0 && contentionAfter.reservationCount === 0, "Contention stok terakhir mengubah projection tepat satu unit, tidak oversell, dan reservation tetap nol.");
  console.log("[PASS] contention stok terakhir: FEFO tidak over-allocate dan projection konsisten");
}

main().then(() => console.log("Manual outbound parallel harness PASS")).catch((error) => {
  console.error(error instanceof Error ? error.stack : error);
  process.exitCode = 1;
});
