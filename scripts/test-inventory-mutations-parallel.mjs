import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import process from "node:process";

const EMAIL = process.env.INVENTORY_PARALLEL_EMAIL ?? "demo.admin@glowlab.invalid";
const TIMEOUT_MS = 30_000;
const PREFIX = "CONCURRENCY-INVENTORY-V1";
const RECEIPT_AT = "2026-06-20T09:00:00Z";
const DISPOSAL_AT = "2026-07-20T09:00:00Z";

function fail(message) { throw new Error(message); }
function assert(condition, message) { if (!condition) fail(message); }
function text(value) { return String(value ?? "").trim(); }
function sqlLiteral(value) { return `'${String(value).replaceAll("'", "''")}'`; }

function resolvePassword(config) {
  const pwd = process.env.INVENTORY_PARALLEL_PASSWORD ?? config?.INVENTORY_PARALLEL_PASSWORD ?? process.env.PARALLEL_TEST_PASSWORD ?? config?.PARALLEL_TEST_PASSWORD;
  if (!pwd || typeof pwd !== "string" || pwd.trim() === "") {
    fail("Password harness tidak ditemukan pada INVENTORY_PARALLEL_PASSWORD atau PARALLEL_TEST_PASSWORD.");
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
  const contents = await readFile(".env.local", "utf8");
  return Object.fromEntries(contents.split(/\r?\n/).filter((line) => line && !line.startsWith("#") && line.includes("=")).map((line) => {
    const index = line.indexOf("=");
    return [line.slice(0, index), line.slice(index + 1).replace(/^['\"]|['\"]$/g, "")];
  }));
}

function databaseContainer() {
  const result = spawnSync("docker", ["ps", "--format", "{{.Names}}"], { encoding: "utf8", windowsHide: true });
  if (result.status !== 0) fail("Docker Supabase lokal tidak dapat diperiksa.");
  const name = result.stdout.split(/\r?\n/).map((entry) => entry.trim()).find((entry) => entry.startsWith("supabase_db_"));
  if (!name) fail("Container database Supabase lokal tidak ditemukan.");
  return name;
}

function sqlJson(container, sql) {
  const result = spawnSync("docker", ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-t", "-A", "-q"], { input: sql, encoding: "utf8", windowsHide: true, maxBuffer: 2 * 1024 * 1024 });
  if (result.status !== 0) fail(`Snapshot database gagal: ${result.stderr.slice(-800)}`);
  const line = result.stdout.split(/\r?\n/).map((entry) => entry.trim()).findLast((entry) => entry.startsWith("{") || entry === "null");
  if (!line) fail("Snapshot database tidak mengembalikan JSON.");
  return JSON.parse(line);
}

async function login(config) {
  validateSupabaseUrl(config);
  const password = resolvePassword(config);
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email: EMAIL, password }), signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!response.ok) fail(`Login harness gagal (${response.status}).`);
  const payload = await response.json();
  if (!payload.access_token) fail("Login harness tidak menghasilkan access token.");
  return payload.access_token;
}

async function profile(config, token) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/current_admin_profile?select=*&limit=1`, { headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api" }, signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!response.ok) fail(`Profile harness gagal (${response.status}).`);
  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length !== 1 || rows[0]?.role_code !== "ADMIN" || !rows[0]?.organization_id) fail("Admin fixture aktif tidak ditemukan.");
  return rows[0];
}

async function rpc(config, token, name, body) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/${name}`, { method: "POST", headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api", "Content-Type": "application/json" }, body: JSON.stringify(body), signal: AbortSignal.timeout(TIMEOUT_MS) });
  const raw = await response.text();
  let payload;
  try { payload = raw ? JSON.parse(raw) : null; } catch { payload = { message: raw }; }
  return { ok: response.ok, status: response.status, payload };
}

function errorCode(result) { return text(result?.payload?.message ?? result?.payload?.code); }
function names(name) { const stem = `${PREFIX}-${name}`; return { sku: `${stem}-PRODUCT`, batch: `${stem}-BATCH`, receiptRef: `${stem}-RECEIPT`, productKey: `${stem}-PRODUCT-KEY`, batchKey: `${stem}-BATCH-KEY`, receiptKey: `${stem}-RECEIPT-KEY` }; }

function fixture(container, organizationId, name) {
  const item = names(name);
  return sqlJson(container, `
select coalesce((select jsonb_build_object('productId', p.id, 'batchId', b.id, 'transactionId', r.transaction_id)
from catalog.products p join catalog.product_batches b on b.organization_id=p.organization_id and b.product_id=p.id
join operations.receipts r on r.organization_id=p.organization_id and r.source_ref=${sqlLiteral(item.receiptRef)}
where p.organization_id=${sqlLiteral(organizationId)}::uuid and p.sku=${sqlLiteral(item.sku)} and b.batch_code=${sqlLiteral(item.batch)} limit 1), 'null'::jsonb);`);
}

function entityFixture(container, organizationId, name) {
  const item = names(name);
  return sqlJson(container, `
select coalesce((select jsonb_build_object('productId', p.id, 'batchId', b.id, 'transactionId', null)
from catalog.products p join catalog.product_batches b on b.organization_id=p.organization_id and b.product_id=p.id
where p.organization_id=${sqlLiteral(organizationId)}::uuid and p.sku=${sqlLiteral(item.sku)} and b.batch_code=${sqlLiteral(item.batch)} limit 1), 'null'::jsonb);`);
}

async function ensureFixture(config, token, container, organizationId, name, quantity, { expired = false, seedReceipt = true } = {}) {
  let current = seedReceipt ? fixture(container, organizationId, name) : entityFixture(container, organizationId, name);
  if (current) return current;
  const item = names(name);
  const product = await rpc(config, token, "create_product", { p_organization_id: organizationId, p_idempotency_key: item.productKey, p_sku: item.sku, p_name: `Fixture concurrency ${name}`, p_unit_code: "UNIT", p_description: "Fixture durable Issue #56.", p_note: "Issue #56 inventory parallel harness." });
  if (!product.ok || !product.payload?.productId) fail(`Create product ${name} gagal: ${errorCode(product)}`);
  const batch = await rpc(config, token, "create_product_batch", { p_organization_id: organizationId, p_idempotency_key: item.batchKey, p_product_id: product.payload.productId, p_batch_code: item.batch, p_expiry_date: expired ? "2026-07-01" : "2028-01-01", p_manufactured_date: "2026-06-01", p_received_first_at: RECEIPT_AT, p_batch_kind_code: "STANDARD", p_note: "Fixture durable Issue #56." });
  if (!batch.ok || !batch.payload?.batchId) fail(`Create batch ${name} gagal: ${errorCode(batch)}`);
  if (seedReceipt) {
    const receipt = await receiptPost(config, token, organizationId, { key: item.receiptKey, sourceRef: item.receiptRef, productId: product.payload.productId, batchId: batch.payload.batchId, quantity, name });
    if (!receipt.ok || !receipt.payload?.transactionId) fail(`Post receipt ${name} gagal: ${errorCode(receipt)}`);
  }
  current = seedReceipt ? fixture(container, organizationId, name) : entityFixture(container, organizationId, name);
  if (!current) fail(`Fixture ${name} tidak terbentuk.`);
  return current;
}

function receiptBody(organizationId, { key, sourceRef, productId, batchId, quantity, name }) { return { p_organization_id: organizationId, p_idempotency_key: key, p_source_ref: sourceRef, p_occurred_at: RECEIPT_AT, p_lines: [{ productId, batchId, quantity, sourceLineRef: "CONCURRENCY-1" }], p_note: `Issue #56 ${name}.`, p_metadata: { source: "inventory-parallel-harness", version: 1, name } }; }
function receiptPost(config, token, organizationId, input) { return rpc(config, token, "post_receipt", receiptBody(organizationId, input)); }

function snapshot(container, organizationId, current, refs) {
  const sourceRefPredicate = refs.length > 0
    ? `source_ref in (${refs.map(sqlLiteral).join(",")})`
    : "false";
  const transactionSourceRefPredicate = refs.length > 0
    ? `source_ref_snapshot in (${refs.map(sqlLiteral).join(",")})`
    : "false";
  const originalTransactionPredicate = current.transactionId
    ? `reversal_of_transaction_id=${sqlLiteral(current.transactionId)}::uuid`
    : "false";
  const originalApplicationPredicate = current.transactionId
    ? `original_transaction_id=${sqlLiteral(current.transactionId)}::uuid`
    : "false";
  return sqlJson(container, `
select jsonb_build_object(
 'receipts',(select count(*) from operations.receipts where organization_id=${sqlLiteral(organizationId)}::uuid and ${sourceRefPredicate}),
 'disposals',(select count(*) from operations.stock_disposals where organization_id=${sqlLiteral(organizationId)}::uuid and ${sourceRefPredicate}),
 'transactions',(select count(*) from inventory.stock_transactions where organization_id=${sqlLiteral(organizationId)}::uuid and ${transactionSourceRefPredicate}),
 'ledgerQty',(select coalesce(sum(quantity_delta),0) from inventory.stock_ledger_entries where organization_id=${sqlLiteral(organizationId)}::uuid and product_id=${sqlLiteral(current.productId)}::uuid and batch_id=${sqlLiteral(current.batchId)}::uuid),
 'ledgerCount',(select count(*) from inventory.stock_ledger_entries where organization_id=${sqlLiteral(organizationId)}::uuid and product_id=${sqlLiteral(current.productId)}::uuid and batch_id=${sqlLiteral(current.batchId)}::uuid),
 'batch',(select jsonb_build_object('sellable',sellable_qty,'quarantine',quarantine_qty,'damaged',damaged_qty) from inventory.stock_batch_balances where organization_id=${sqlLiteral(organizationId)}::uuid and batch_id=${sqlLiteral(current.batchId)}::uuid),
 'product',(select jsonb_build_object('sellable',sellable_qty,'quarantine',quarantine_qty,'damaged',damaged_qty,'reserved',reserved_qty) from inventory.stock_product_positions where organization_id=${sqlLiteral(organizationId)}::uuid and product_id=${sqlLiteral(current.productId)}::uuid),
 'reversalTransactions',(select count(*) from inventory.stock_transactions where organization_id=${sqlLiteral(organizationId)}::uuid and ${originalTransactionPredicate}),
 'reversalApplications',(select count(*) from inventory.stock_reversal_applications where organization_id=${sqlLiteral(organizationId)}::uuid and ${originalApplicationPredicate}),
 'reservations',(select count(*) from inventory.stock_reservations where organization_id=${sqlLiteral(organizationId)}::uuid and product_id=${sqlLiteral(current.productId)}::uuid)
);`);
}

function assertProjection(state, message) {
  assert(Number(state.batch.sellable) + Number(state.batch.quarantine) + Number(state.batch.damaged) === Number(state.ledgerQty), `${message}: batch projection tidak sama dengan scoped ledger.`);
  assert(Number(state.product.sellable) + Number(state.product.quarantine) + Number(state.product.damaged) === Number(state.ledgerQty), `${message}: product projection tidak sama dengan scoped ledger.`);
  assert(Number(state.batch.sellable) >= 0 && Number(state.batch.quarantine) >= 0 && Number(state.batch.damaged) >= 0 && Number(state.product.reserved) >= 0, `${message}: quantity fisik/reservasi negatif.`);
}

async function disposalPreview(config, token, organizationId, sourceRef, current, quantity) {
  const lines = [{ productId: current.productId, batchId: current.batchId, sourceBucketCode: "SELLABLE", quantity, sourceLineRef: "CONCURRENCY-1" }];
  const body = { p_organization_id: organizationId, p_source_ref: sourceRef, p_occurred_at: DISPOSAL_AT, p_reason_code: "EXPIRED_DISPOSAL", p_lines: lines, p_reference_text: "BA-Concurrency-56", p_note: "Issue #56 disposal parallel harness.", p_metadata: { source: "inventory-parallel-harness", version: 1 } };
  const preview = await rpc(config, token, "preview_stock_disposal", body);
  if (!preview.ok || preview.payload?.eligible !== true || !/^[0-9a-f]{64}$/.test(text(preview.payload?.basisHash))) fail(`Preview disposal ${sourceRef} gagal: ${errorCode(preview)}`);
  return { ...body, p_idempotency_key: `${sourceRef}-KEY`, p_preview_basis_hash: preview.payload.basisHash, p_confirmation: true };
}

function disposalPost(config, token, body) { return rpc(config, token, "post_stock_disposal", body); }
async function reversalPreview(config, token, organizationId, transactionId) {
  const result = await rpc(config, token, "preview_stock_transaction_reversal", { p_organization_id: organizationId, p_original_transaction_id: transactionId });
  if (!result.ok || result.payload?.eligible !== true || !/^[0-9a-f]{64}$/.test(text(result.payload?.basisHash))) fail(`Preview reversal gagal: ${errorCode(result)}`);
  return result.payload.basisHash;
}
function reversalPost(config, token, organizationId, transactionId, key, basisHash, note) { return rpc(config, token, "reverse_stock_transaction", { p_organization_id: organizationId, p_idempotency_key: key, p_original_transaction_id: transactionId, p_preview_basis_hash: basisHash, p_confirmation: true, p_note: note, p_metadata: { source: "inventory-parallel-harness", version: 1 } }); }

async function main() {
  const config = await readEnv(); const container = databaseContainer();
  const [tokenA, tokenB] = await Promise.all([login(config), login(config)]);
  assert(tokenA !== tokenB, "Harness membutuhkan dua session independen.");
  const [profileA, profileB] = await Promise.all([profile(config, tokenA), profile(config, tokenB)]);
  assert(profileA.organization_id === profileB.organization_id, "Dua session harus satu organisasi fixture.");
  const organizationId = profileA.organization_id;

  const receiptReplay = await ensureFixture(config, tokenA, container, organizationId, "RECEIPT-REPLAY-SEED", 0, { seedReceipt: false });
  const receiptConflict = await ensureFixture(config, tokenA, container, organizationId, "RECEIPT-CONFLICT-SEED", 0, { seedReceipt: false });
  const disposalReplay = await ensureFixture(config, tokenA, container, organizationId, "DISPOSAL-REPLAY", 1, { expired: true });
  const disposalContention = await ensureFixture(config, tokenA, container, organizationId, "DISPOSAL-CONTENTION", 1, { expired: true });
  const reversalReplay = await ensureFixture(config, tokenA, container, organizationId, "REVERSAL-REPLAY", 1);
  const reversalContention = await ensureFixture(config, tokenA, container, organizationId, "REVERSAL-CONTENTION", 1);
  const reversalConflict = await ensureFixture(config, tokenA, container, organizationId, "REVERSAL-CONFLICT", 1);

  const terminal = snapshot(container, organizationId, receiptReplay, [`${PREFIX}-RECEIPT-REPLAY`]).receipts === 1 && snapshot(container, organizationId, receiptConflict, [`${PREFIX}-RECEIPT-CONFLICT`]).receipts === 1 && snapshot(container, organizationId, disposalReplay, [`${PREFIX}-DISPOSAL-REPLAY`]).disposals === 1 && snapshot(container, organizationId, disposalContention, [`${PREFIX}-DISPOSAL-CONTENTION-A`, `${PREFIX}-DISPOSAL-CONTENTION-B`]).disposals === 1 && snapshot(container, organizationId, reversalReplay, []).reversalTransactions === 1 && snapshot(container, organizationId, reversalContention, []).reversalTransactions === 1 && snapshot(container, organizationId, reversalConflict, []).reversalTransactions === 1;
  if (terminal) {
    const terminalFixtures = [
      { current: receiptReplay, refs: [`${PREFIX}-RECEIPT-REPLAY`], expected: { receipts: 1, disposals: 0, ledgerQty: 1 } },
      { current: receiptConflict, refs: [`${PREFIX}-RECEIPT-CONFLICT`], expected: { receipts: 1, disposals: 0, ledgerQty: [1, 2] } },
      { current: disposalReplay, refs: [names("DISPOSAL-REPLAY").receiptRef, `${PREFIX}-DISPOSAL-REPLAY`], expected: { receipts: 1, disposals: 1, ledgerQty: 0 } },
      { current: disposalContention, refs: [names("DISPOSAL-CONTENTION").receiptRef, `${PREFIX}-DISPOSAL-CONTENTION-A`, `${PREFIX}-DISPOSAL-CONTENTION-B`], expected: { receipts: 1, disposals: 1, ledgerQty: 0 } },
      { current: reversalReplay, refs: [names("REVERSAL-REPLAY").receiptRef], expected: { receipts: 1, disposals: 0, ledgerQty: 0, reversals: 1 } },
      { current: reversalContention, refs: [names("REVERSAL-CONTENTION").receiptRef], expected: { receipts: 1, disposals: 0, ledgerQty: 0, reversals: 1 } },
      { current: reversalConflict, refs: [names("REVERSAL-CONFLICT").receiptRef], expected: { receipts: 1, disposals: 0, ledgerQty: 0, reversals: 1 } },
    ];
    const beforeTerminal = terminalFixtures.map(({ current, refs }) => snapshot(container, organizationId, current, refs));
    beforeTerminal.forEach((state, index) => {
      const expected = terminalFixtures[index].expected;
      assert(state.receipts === expected.receipts && state.disposals === expected.disposals, `Durable rerun fixture ${index + 1} memiliki document count yang tidak tepat.`);
      assert(Array.isArray(expected.ledgerQty) ? expected.ledgerQty.includes(Number(state.ledgerQty)) : Number(state.ledgerQty) === expected.ledgerQty, `Durable rerun fixture ${index + 1} memiliki ledger quantity yang tidak tepat.`);
      if (expected.reversals) assert(state.reversalTransactions === 1 && state.reversalApplications === 1, `Durable rerun fixture ${index + 1} harus memiliki satu reversal application.`);
      assertProjection(state, `Durable rerun fixture ${index + 1}`);
    });
    const afterTerminal = terminalFixtures.map(({ current, refs }) => snapshot(container, organizationId, current, refs));
    assert(JSON.stringify(afterTerminal) === JSON.stringify(beforeTerminal), "Durable rerun harus hanya membaca fixture terminal tanpa domain effect baru.");
    console.log("[PASS] durable rerun: receipt/disposal/reversal terminal tanpa effect tambahan");
    return;
  }

  const receiptReplayRef = `${PREFIX}-RECEIPT-REPLAY`;
  const replayInput = { key: `${receiptReplayRef}-KEY`, sourceRef: receiptReplayRef, productId: receiptReplay.productId, batchId: receiptReplay.batchId, quantity: 1, name: "receipt replay" };
  const [receiptReplayA, receiptReplayB] = await Promise.all([receiptPost(config, tokenA, organizationId, replayInput), receiptPost(config, tokenB, organizationId, replayInput)]);
  assert(receiptReplayA.ok && receiptReplayB.ok && receiptReplayA.payload?.transactionId === receiptReplayB.payload?.transactionId, "Receipt identical replay harus mengembalikan satu transaction authoritative/replay.");
  const receiptReplayState = snapshot(container, organizationId, receiptReplay, [receiptReplayRef]);
  assert(receiptReplayState.receipts === 1 && receiptReplayState.transactions === 1 && receiptReplayState.ledgerQty === 1, "Receipt replay hanya membuat satu receipt/transaction/ledger effect."); assertProjection(receiptReplayState, "Receipt replay");
  console.log("[PASS] receipt identical replay: satu effect dan projection konsisten");

  const receiptConflictRef = `${PREFIX}-RECEIPT-CONFLICT`;
  const [receiptConflictA, receiptConflictB] = await Promise.all([receiptPost(config, tokenA, organizationId, { key: `${receiptConflictRef}-KEY`, sourceRef: receiptConflictRef, productId: receiptConflict.productId, batchId: receiptConflict.batchId, quantity: 1, name: "receipt conflict A" }), receiptPost(config, tokenB, organizationId, { key: `${receiptConflictRef}-KEY`, sourceRef: receiptConflictRef, productId: receiptConflict.productId, batchId: receiptConflict.batchId, quantity: 2, name: "receipt conflict B" })]);
  const receiptConflictResults = [receiptConflictA, receiptConflictB]; assert(receiptConflictResults.filter((result) => result.ok).length === 1 && receiptConflictResults.filter((result) => !result.ok).length === 1 && errorCode(receiptConflictResults.find((result) => !result.ok)) === "IDEMPOTENCY_KEY_REUSED", "Receipt changed payload harus memiliki satu winner dan satu conflict.");
  const receiptConflictState = snapshot(container, organizationId, receiptConflict, [receiptConflictRef]); assert(receiptConflictState.receipts === 1 && [1, 2].includes(Number(receiptConflictState.ledgerQty)), "Receipt conflict harus menyimpan satu payload utuh."); assertProjection(receiptConflictState, "Receipt conflict");
  console.log("[PASS] receipt changed payload: satu payload authoritative tanpa gabungan quantity");

  const disposalReplayRef = `${PREFIX}-DISPOSAL-REPLAY`; const disposalReplayBody = await disposalPreview(config, tokenA, organizationId, disposalReplayRef, disposalReplay, 1);
  const [disposalReplayA, disposalReplayB] = await Promise.all([disposalPost(config, tokenA, disposalReplayBody), disposalPost(config, tokenB, disposalReplayBody)]);
  assert(disposalReplayA.ok && disposalReplayB.ok && disposalReplayA.payload?.transactionId === disposalReplayB.payload?.transactionId, "Disposal identical replay harus menghasilkan satu transaction.");
  const disposalReplayState = snapshot(container, organizationId, disposalReplay, [names("DISPOSAL-REPLAY").receiptRef, disposalReplayRef]); assert(disposalReplayState.disposals === 1 && disposalReplayState.ledgerQty === 0, "Disposal replay harus mengurangi stok tepat satu kali."); assertProjection(disposalReplayState, "Disposal replay");
  console.log("[PASS] disposal identical replay: satu disposal/transaction/ledger effect");

  const disposalA = await disposalPreview(config, tokenA, organizationId, `${PREFIX}-DISPOSAL-CONTENTION-A`, disposalContention, 1); const disposalB = await disposalPreview(config, tokenB, organizationId, `${PREFIX}-DISPOSAL-CONTENTION-B`, disposalContention, 1);
  const [disposalResultA, disposalResultB] = await Promise.all([disposalPost(config, tokenA, disposalA), disposalPost(config, tokenB, disposalB)]);
  const disposalResults = [disposalResultA, disposalResultB]; assert(disposalResults.filter((result) => result.ok).length === 1 && disposalResults.filter((result) => !result.ok).length === 1 && ["STALE_STOCK_DISPOSAL_PREVIEW", "STOCK_DISPOSAL_PREVIEW_BLOCKED"].includes(errorCode(disposalResults.find((result) => !result.ok))), "Contention disposal stok terakhir harus memiliki satu winner dan penolakan stale/blocked.");
  const disposalContentionState = snapshot(container, organizationId, disposalContention, [names("DISPOSAL-CONTENTION").receiptRef, `${PREFIX}-DISPOSAL-CONTENTION-A`, `${PREFIX}-DISPOSAL-CONTENTION-B`]); assert(disposalContentionState.disposals === 1 && disposalContentionState.ledgerQty === 0, "Contention disposal tidak boleh oversell."); assertProjection(disposalContentionState, "Disposal contention");
  console.log("[PASS] disposal contention: stok fisik tidak negatif dan bucket tepat");

  const replayBasis = await reversalPreview(config, tokenA, organizationId, reversalReplay.transactionId); const replayKey = `${PREFIX}-REVERSAL-REPLAY-KEY`;
  const [reversalReplayA, reversalReplayB] = await Promise.all([reversalPost(config, tokenA, organizationId, reversalReplay.transactionId, replayKey, replayBasis, "Issue #56 reversal replay."), reversalPost(config, tokenB, organizationId, reversalReplay.transactionId, replayKey, replayBasis, "Issue #56 reversal replay.")]);
  assert(reversalReplayA.ok && reversalReplayB.ok && reversalReplayA.payload?.transactionId === reversalReplayB.payload?.transactionId, "Reversal identical replay harus menghasilkan satu reversal transaction.");
  const reversalReplayState = snapshot(container, organizationId, reversalReplay, [names("REVERSAL-REPLAY").receiptRef]); assert(reversalReplayState.reversalTransactions === 1 && reversalReplayState.reversalApplications === 1 && reversalReplayState.ledgerQty === 0, "Reversal replay harus memulihkan projection tepat satu kali dengan satu application."); assertProjection(reversalReplayState, "Reversal replay");
  console.log("[PASS] reversal identical replay: satu application dan restore tepat satu kali");

  const contentionBasisA = await reversalPreview(config, tokenA, organizationId, reversalContention.transactionId); const contentionBasisB = await reversalPreview(config, tokenB, organizationId, reversalContention.transactionId);
  const [reversalContentionA, reversalContentionB] = await Promise.all([reversalPost(config, tokenA, organizationId, reversalContention.transactionId, `${PREFIX}-REVERSAL-CONTENTION-A`, contentionBasisA, "Issue #56 reversal contention A."), reversalPost(config, tokenB, organizationId, reversalContention.transactionId, `${PREFIX}-REVERSAL-CONTENTION-B`, contentionBasisB, "Issue #56 reversal contention B.")]);
  const reversalContentionResults = [reversalContentionA, reversalContentionB]; assert(reversalContentionResults.filter((result) => result.ok).length === 1 && reversalContentionResults.filter((result) => !result.ok).length === 1 && ["STALE_REVERSAL_PREVIEW", "ORIGINAL_TRANSACTION_ALREADY_REVERSED"].includes(errorCode(reversalContentionResults.find((result) => !result.ok))), "Dua reversal command untuk original sama harus memiliki satu winner dan satu penolakan aman.");
  const reversalContentionState = snapshot(container, organizationId, reversalContention, [names("REVERSAL-CONTENTION").receiptRef]); assert(reversalContentionState.reversalTransactions === 1 && reversalContentionState.reversalApplications === 1 && reversalContentionState.ledgerQty === 0, "Reversal contention tidak boleh double restore."); assertProjection(reversalContentionState, "Reversal contention");
  console.log("[PASS] reversal original contention: original hanya direverse sekali");

  const conflictBasisA = await reversalPreview(config, tokenA, organizationId, reversalConflict.transactionId); const conflictBasisB = await reversalPreview(config, tokenB, organizationId, reversalConflict.transactionId); const reversalConflictKey = `${PREFIX}-REVERSAL-CONFLICT-KEY`;
  const [reversalConflictA, reversalConflictB] = await Promise.all([reversalPost(config, tokenA, organizationId, reversalConflict.transactionId, reversalConflictKey, conflictBasisA, "Issue #56 reversal conflict A."), reversalPost(config, tokenB, organizationId, reversalConflict.transactionId, reversalConflictKey, conflictBasisB, "Issue #56 reversal conflict B.")]);
  const reversalConflictResults = [reversalConflictA, reversalConflictB]; assert(reversalConflictResults.filter((result) => result.ok).length === 1 && reversalConflictResults.filter((result) => !result.ok).length === 1 && errorCode(reversalConflictResults.find((result) => !result.ok)) === "IDEMPOTENCY_KEY_REUSED", "Reversal changed payload harus conflict tanpa effect kedua.");
  const reversalConflictState = snapshot(container, organizationId, reversalConflict, [names("REVERSAL-CONFLICT").receiptRef]); assert(reversalConflictState.reversalTransactions === 1 && reversalConflictState.reversalApplications === 1 && reversalConflictState.ledgerQty === 0, "Reversal changed payload tidak boleh double restore."); assertProjection(reversalConflictState, "Reversal conflict");
  console.log("[PASS] reversal changed payload: conflict aman tanpa application kedua");
}

main().then(() => console.log("Inventory mutations parallel harness PASS")).catch((error) => { console.error(error instanceof Error ? error.stack : error); process.exitCode = 1; });
