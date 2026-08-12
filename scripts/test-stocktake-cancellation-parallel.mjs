import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import process from "node:process";

const EMAIL = process.env.STOCKTAKE_CANCELLATION_PARALLEL_EMAIL ?? "demo.admin@glowlab.invalid";
const PREFIX = "CONCURRENCY-STOCKTAKE-CANCEL-V3";
const TIMEOUT_MS = 30_000;
const OCCURRED_AT = "2026-08-12T09:00:00Z";
const names = ["REPLAY", "CONFLICT", "CONTENTION", "TRANSITION", "POST-GUARD"];

function fail(message) { throw new Error(message); }
function assert(value, message) { if (!value) fail(message); }
function sql(value) { return `'${String(value).replaceAll("'", "''")}'`; }
function code(result) { return String(result?.payload?.message ?? result?.payload?.code ?? "").trim(); }
function same(left, right, message) { assert(JSON.stringify(left) === JSON.stringify(right), message); }

async function env() {
  const raw = await readFile(".env.local", "utf8");
  return Object.fromEntries(raw.split(/\r?\n/).filter((line) => line && !line.startsWith("#") && line.includes("=")).map((line) => {
    const index = line.indexOf("=");
    return [line.slice(0, index), line.slice(index + 1).replace(/^['\"]|['\"]$/g, "")];
  }));
}

function password(config) {
  const value = process.env.STOCKTAKE_CANCELLATION_PARALLEL_PASSWORD ?? config.STOCKTAKE_CANCELLATION_PARALLEL_PASSWORD ?? process.env.PARALLEL_TEST_PASSWORD ?? config.PARALLEL_TEST_PASSWORD;
  if (!value?.trim()) fail("Password harness tidak ditemukan pada STOCKTAKE_CANCELLATION_PARALLEL_PASSWORD atau PARALLEL_TEST_PASSWORD.");
  return value;
}

function verifyLocal(config) {
  const raw = config.NEXT_PUBLIC_SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!raw) fail("NEXT_PUBLIC_SUPABASE_URL tidak ditemukan.");
  const host = new URL(raw).hostname.replace(/^\[|\]$/g, "");
  const local = host === "localhost" || host === "127.0.0.1" || host === "::1";
  if (!local && process.env.ALLOW_REMOTE_PARALLEL_TESTS !== "true" && config.ALLOW_REMOTE_PARALLEL_TESTS !== "true") {
    fail(`Supabase URL non-local (${host}) ditolak. Set ALLOW_REMOTE_PARALLEL_TESTS=true hanya bila memang disengaja.`);
  }
}

function db() {
  const result = spawnSync("docker", ["ps", "--format", "{{.Names}}"], { encoding: "utf8", windowsHide: true });
  const container = result.stdout.split(/\r?\n/).map((value) => value.trim()).find((value) => value.startsWith("supabase_db_"));
  if (!container) fail("Container Supabase lokal tidak ditemukan.");
  return container;
}

function query(container, statement) {
  const result = spawnSync("docker", ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-t", "-A", "-q"], { input: statement, encoding: "utf8", windowsHide: true });
  if (result.status !== 0) fail(`Snapshot read-only gagal: ${result.stderr.slice(-500)}`);
  const row = result.stdout.split(/\r?\n/).map((value) => value.trim()).findLast((value) => value.startsWith("{") || value.startsWith("[") || value === "null");
  if (!row) fail("Snapshot read-only tidak mengembalikan JSON.");
  return JSON.parse(row);
}

async function login(config) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password: password(config) }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) fail(`Login harness gagal (${response.status}).`);
  const body = await response.json();
  if (!body.access_token) fail("Login harness tidak menghasilkan token.");
  return body.access_token;
}

async function rpc(config, token, name, body) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api", "Content-Type": "application/json" },
    body: JSON.stringify(body), signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const text = await response.text();
  let payload;
  try { payload = text ? JSON.parse(text) : null; } catch { payload = { message: text }; }
  return { ok: response.ok, payload };
}

async function rows(config, token, path) {
  const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api", "Content-Profile": "api" }, signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) fail(`Read model ${path} gagal (${response.status}).`);
  return response.json();
}

async function organization(config, token) {
  const profile = await rows(config, token, "current_admin_profile?select=*&limit=1");
  if (profile.length !== 1 || profile[0]?.role_code !== "ADMIN" || !profile[0]?.organization_id) fail("Admin fixture aktif tidak tersedia.");
  return profile[0].organization_id;
}

function size(value) {
  let hash = 2166136261;
  for (const character of value) { hash ^= character.charCodeAt(0); hash = Math.imul(hash, 16777619); }
  return 1000 + ((hash >>> 0) % 999000000);
}

function ids(name) {
  const base = `${PREFIX}-${name}`;
  return { title: `Cancellation parallel V3 ${name}`, productName: `Cancellation fixture V3 ${name}`, productKey: `${base}-PRODUCT`, batchKey: `${base}-BATCH`, batchCode: `${base}-BATCH` };
}

function batchFor(container, org, name) {
  const item = ids(name);
  return query(container, `select coalesce((select jsonb_build_object('productId', p.id, 'batchId', b.id) from catalog.products p join catalog.product_batches b on b.organization_id=p.organization_id and b.product_id=p.id where p.organization_id=${sql(org)}::uuid and p.name=${sql(item.productName)} and b.batch_code=${sql(item.batchCode)} limit 1), 'null'::jsonb);`);
}

async function ensureBatch(config, token, container, org, name) {
  let current = batchFor(container, org, name);
  if (current) { await ensureZeroBalance(config, token, container, org, current, name); return current; }
  const item = ids(name);
  const product = await rpc(config, token, "create_product", { p_organization_id: org, p_idempotency_key: item.productKey, p_name: item.productName, p_size_ml: size(item.productKey), p_unit_code: "UNIT", p_description: "Fixture durable cancellation parallel.", p_note: "Concurrency harness." });
  if (!product.ok) fail(`Create product ${name}: ${code(product)}`);
  const batch = await rpc(config, token, "create_product_batch", { p_organization_id: org, p_idempotency_key: item.batchKey, p_product_id: product.payload.productId, p_batch_code: item.batchCode, p_expiry_date: "2028-12-31", p_manufactured_date: "2026-08-01", p_received_first_at: OCCURRED_AT, p_batch_kind_code: "STANDARD", p_note: "Concurrency harness." });
  if (!batch.ok) fail(`Create batch ${name}: ${code(batch)}`);
  current = batchFor(container, org, name);
  if (!current) fail(`Batch ${name} tidak terbentuk.`);
  await ensureZeroBalance(config, token, container, org, current, name);
  return current;
}

async function ensureZeroBalance(config, token, container, org, current, name) { const balance = query(container, `select coalesce((select jsonb_build_object('exists',true) from inventory.stock_batch_balances where organization_id=${sql(org)}::uuid and batch_id=${sql(current.batchId)}::uuid),'null'::jsonb);`); if (balance?.exists === true) return; const key = `${PREFIX}:${name}:seed-receipt`; const receipt = await rpc(config, token, "post_receipt", { p_organization_id: org, p_idempotency_key: key, p_source_ref: `${PREFIX}-${name}-SEED-RECEIPT`, p_occurred_at: OCCURRED_AT, p_lines: [{ productId: current.productId, batchId: current.batchId, quantity: 1, sourceLineRef: "SEED-1" }], p_note: "Seed projection zero balance.", p_metadata: { source: "stocktake-cancellation-parallel" } }); if (!receipt.ok) fail(`Seed receipt ${name}: ${code(receipt)}`); const preview = await rpc(config, token, "preview_stock_transaction_reversal", { p_organization_id: org, p_original_transaction_id: receipt.payload.transactionId }); if (!preview.ok || preview.payload?.eligible !== true) fail(`Seed reversal preview ${name}: ${code(preview)}`); const reversed = await rpc(config, token, "reverse_stock_transaction", { p_organization_id: org, p_idempotency_key: `${PREFIX}:${name}:seed-reversal`, p_original_transaction_id: receipt.payload.transactionId, p_preview_basis_hash: preview.payload.basisHash, p_confirmation: true, p_note: "Restore seed projection to zero.", p_metadata: { source: "stocktake-cancellation-parallel" } }); if (!reversed.ok) fail(`Seed reversal ${name}: ${code(reversed)}`); }

function existing(container, org, name) {
  return query(container, `select coalesce((select jsonb_build_object('stocktakeId', id, 'status', status_code, 'approvalVersion', approval_version_no) from operations.stocktakes where organization_id=${sql(org)}::uuid and title=${sql(ids(name).title)} order by created_at desc limit 1), 'null'::jsonb);`);
}

async function createDraft(config, token, org, container, name) {
  const batch = await ensureBatch(config, token, container, org, name);
  const prior = existing(container, org, name);
  if (prior) return { ...batch, ...prior };
  const created = await rpc(config, token, "create_stocktake", {
    p_organization_id: org, p_idempotency_key: `${PREFIX}:${name}:create`, p_title: ids(name).title,
    p_stocktake_type_code: "CYCLE", p_mode_code: "CONTINUOUS", p_visibility_code: "NON_BLIND",
    p_scope: { mode: "BATCHES", batchIds: [batch.batchId], bucketCodes: ["SELLABLE"], includeZeroSystemBalance: true, includeInactiveWithBalance: false, includeBlockedBatches: false, includeExpiredBatches: false },
    p_planned_at: null, p_note: "Cancellation concurrency fixture.", p_metadata: { source: "stocktake-cancellation-parallel" },
  });
  if (!created.ok) fail(`Create stocktake ${name}: ${code(created)}`);
  return { ...batch, stocktakeId: created.payload.stocktakeId, status: "DRAFT", approvalVersion: null };
}

async function prepareCounting(config, token, org, container, name) {
  const current = await createDraft(config, token, org, container, name);
  if (current.status === "COUNTING") return current;
  if (current.status !== "DRAFT") fail(`Fixture ${name} partial/unexpected (${current.status}).`);
  const prepared = await rpc(config, token, "prepare_stocktake", { p_organization_id: org, p_idempotency_key: `${PREFIX}:${name}:prepare`, p_stocktake_id: current.stocktakeId, p_metadata: { source: "stocktake-cancellation-parallel" } });
  if (!prepared.ok) fail(`Prepare ${name}: ${code(prepared)}`);
  const started = await rpc(config, token, "start_stocktake", { p_organization_id: org, p_idempotency_key: `${PREFIX}:${name}:start`, p_stocktake_id: current.stocktakeId, p_metadata: { source: "stocktake-cancellation-parallel" } });
  if (!started.ok) fail(`Start ${name}: ${code(started)}`);
  return { ...current, status: "COUNTING" };
}

async function prepareApproved(config, token, org, container, name) {
  const current = await prepareCounting(config, token, org, container, name);
  if (current.status === "APPROVED") return current;
  const line = (await rows(config, token, `stocktake_non_blind_lines?organization_id=eq.${encodeURIComponent(org)}&stocktake_id=eq.${encodeURIComponent(current.stocktakeId)}&select=*&order=line_no.asc`))[0];
  if (!line) fail(`Line ${name} tidak tersedia.`);
  const count = await submitCount(config, token, org, current, line.stocktake_line_id, `${PREFIX}:${name}:count`);
  if (!count.ok) fail(`Count ${name}: ${code(count)}`);
  const complete = await rpc(config, token, "complete_stocktake_counting", { p_organization_id: org, p_idempotency_key: `${PREFIX}:${name}:complete`, p_stocktake_id: current.stocktakeId, p_metadata: { source: "stocktake-cancellation-parallel" } });
  if (!complete.ok) fail(`Complete ${name}: ${code(complete)}`);
  const review = (await rows(config, token, `stocktake_review_lines?organization_id=eq.${encodeURIComponent(org)}&stocktake_id=eq.${encodeURIComponent(current.stocktakeId)}&select=*&order=line_no.asc`))[0];
  if (!review) fail(`Review line ${name} tidak tersedia.`);
  const reviewed = await rpc(config, token, "review_stocktake_line", { p_organization_id: org, p_idempotency_key: `${PREFIX}:${name}:review:${review.version_no}`, p_stocktake_id: current.stocktakeId, p_stocktake_line_id: review.stocktake_line_id, p_expected_line_version: review.version_no, p_decision_code: "VARIANCE_ACCEPTED", p_reason_code: "PHYSICAL_SURPLUS", p_review_note: "Concurrency fixture.", p_exception_code: null, p_metadata: { source: "stocktake-cancellation-parallel" } });
  if (!reviewed.ok) fail(`Review ${name}: ${code(reviewed)}`);
  const detail = (await rows(config, token, `stocktake_details?organization_id=eq.${encodeURIComponent(org)}&stocktake_id=eq.${encodeURIComponent(current.stocktakeId)}&select=*&limit=1`))[0];
  const approved = await rpc(config, token, "approve_stocktake", { p_organization_id: org, p_idempotency_key: `${PREFIX}:${name}:approve:${detail.version_no}`, p_stocktake_id: current.stocktakeId, p_expected_stocktake_version: detail.version_no, p_confirmation: true, p_note: "Concurrency fixture.", p_metadata: { source: "stocktake-cancellation-parallel" } });
  if (!approved.ok || approved.payload?.status !== "APPROVED") fail(`Approve ${name}: ${code(approved)}`);
  return { ...current, status: "APPROVED", approvalVersion: approved.payload.approvalVersion };
}

async function prepareReview(config, token, org, container, name) {
  const current = await prepareCounting(config, token, org, container, name);
  if (current.status === "REVIEW") return current;
  if (current.status !== "COUNTING") fail(`Fixture ${name} partial/unexpected (${current.status}).`);
  const line = (await rows(config, token, `stocktake_non_blind_lines?organization_id=eq.${encodeURIComponent(org)}&stocktake_id=eq.${encodeURIComponent(current.stocktakeId)}&select=*&order=line_no.asc`))[0];
  if (!line) fail(`Line ${name} tidak tersedia.`);
  const counted = await submitCount(config, token, org, current, line.stocktake_line_id, `${PREFIX}:${name}:count`);
  if (!counted.ok) fail(`Count ${name}: ${code(counted)}`);
  const completed = await rpc(config, token, "complete_stocktake_counting", { p_organization_id: org, p_idempotency_key: `${PREFIX}:${name}:complete`, p_stocktake_id: current.stocktakeId, p_metadata: { source: "stocktake-cancellation-parallel" } });
  if (!completed.ok || completed.payload?.status !== "REVIEW") fail(`Complete ${name}: ${code(completed)}`);
  return { ...current, status: "REVIEW" };
}

function requestReviewRecount(config, token, org, current, line, key) {
  return rpc(config, token, "request_stocktake_review_recount", { p_organization_id: org, p_idempotency_key: key, p_stocktake_id: current.stocktakeId, p_stocktake_line_id: line.stocktake_line_id, p_expected_line_version: line.version_no, p_reason: "Race recount review.", p_metadata: { source: "stocktake-cancellation-parallel" } });
}

function reviewLine(config, token, org, current, line, key) {
  return rpc(config, token, "review_stocktake_line", { p_organization_id: org, p_idempotency_key: key, p_stocktake_id: current.stocktakeId, p_stocktake_line_id: line.stocktake_line_id, p_expected_line_version: line.version_no, p_decision_code: "VARIANCE_ACCEPTED", p_reason_code: "PHYSICAL_SURPLUS", p_review_note: "Race review.", p_exception_code: null, p_metadata: { source: "stocktake-cancellation-parallel" } });
}

function cancel(config, token, org, current, key, reason) {
  return rpc(config, token, "cancel_stocktake", { p_organization_id: org, p_idempotency_key: key, p_stocktake_id: current.stocktakeId, p_reason: reason, p_confirmation: true, p_metadata: { source: "stocktake-cancellation-parallel", version: 1 } });
}

function submitCount(config, token, org, current, lineId, key) {
  return rpc(config, token, "submit_stocktake_count", { p_organization_id: org, p_idempotency_key: key, p_stocktake_id: current.stocktakeId, p_stocktake_line_id: lineId, p_physical_qty: 1, p_zero_confirmed: false, p_count_method_code: "MANUAL_ENTRY", p_note: "Concurrency count.", p_metadata: { source: "stocktake-cancellation-parallel" } });
}

function snapshot(container, org, current) {
  return query(container, `select jsonb_build_object(
    'status', (select status_code from operations.stocktakes where organization_id=${sql(org)}::uuid and id=${sql(current.stocktakeId)}::uuid),
    'cancellations', (select count(*) from operations.stocktake_cancellations where organization_id=${sql(org)}::uuid and stocktake_id=${sql(current.stocktakeId)}::uuid),
    'commands', (select count(*) from inventory.idempotency_commands where organization_id=${sql(org)}::uuid and scope='CANCEL_STOCKTAKE' and key like ${sql(`${PREFIX}%`)}),
    'attempts', (select count(*) from operations.stocktake_count_attempts where organization_id=${sql(org)}::uuid and stocktake_id=${sql(current.stocktakeId)}::uuid),
    'postings', (select count(*) from operations.stocktake_postings where organization_id=${sql(org)}::uuid and stocktake_id=${sql(current.stocktakeId)}::uuid),
    'transactions', (select count(*) from inventory.stock_transactions where organization_id=${sql(org)}::uuid and source_type_code='STOCKTAKE' and source_id=${sql(current.stocktakeId)}::uuid),
    'ledger', (select count(*) from inventory.stock_ledger_entries entry join inventory.stock_transactions transaction on transaction.id=entry.transaction_id where transaction.organization_id=${sql(org)}::uuid and transaction.source_type_code='STOCKTAKE' and transaction.source_id=${sql(current.stocktakeId)}::uuid),
    'batch', (select jsonb_build_object('sellable', sellable_qty, 'quarantine', quarantine_qty, 'damaged', damaged_qty) from inventory.stock_batch_balances where organization_id=${sql(org)}::uuid and batch_id=${sql(current.batchId)}::uuid),
    'product', (select jsonb_build_object('sellable', sellable_qty, 'quarantine', quarantine_qty, 'damaged', damaged_qty) from inventory.stock_product_positions where organization_id=${sql(org)}::uuid and product_id=${sql(current.productId)}::uuid),
    'reservations', (select jsonb_build_object('count', count(*), 'reserved', coalesce(sum(reserved_qty), 0), 'consumed', coalesce(sum(consumed_qty), 0), 'released', coalesce(sum(released_qty), 0)) from inventory.stock_reservations where organization_id=${sql(org)}::uuid),
    'allocations', (select jsonb_build_object('count', count(*), 'qty', coalesce(sum(quantity_allocated), 0)) from operations.marketplace_ship_allocations where organization_id=${sql(org)}::uuid)
  );`);
}

function assertNeutral(before, after, message) {
  for (const key of ["postings", "transactions", "ledger", "batch", "product", "reservations", "allocations"]) same(before[key], after[key], `${message}: ${key} berubah.`);
}

function assertOneCancelled(state, message) {
  assert(state.status === "CANCELLED" && state.cancellations === 1 && state.transactions === 0 && state.ledger === 0 && state.postings === 0, message);
}

async function runTerminalReplay(container, org) {
  const states = names.map((name) => existing(container, org, name));
  if (states.every((state) => state === null)) return false;
  const safeBootstrap = states[0]?.status === "DRAFT" && states.slice(1).every((state) => state === null);
  if (safeBootstrap) return false;
  const resumablePostGuard =
    states.slice(0, 4).every((state) => state?.status === "CANCELLED") &&
    states[4]?.status === "APPROVED";
  if (resumablePostGuard) {
    const batches = names.map((name) => batchFor(container, org, name));
    if (batches.some((batch) => !batch)) fail("Fixture recovery POST-GUARD tidak memiliki batch yang utuh.");
    const partial = states.map((state, index) => snapshot(container, org, { ...batches[index], ...state }));
    partial.slice(0, 4).forEach((state, index) => assertOneCancelled(state, `Fixture recovery ${names[index]} tidak utuh.`));
    assert(
      partial[4].status === "APPROVED" &&
        partial[4].cancellations === 0 &&
        partial[4].postings === 0 &&
        partial[4].transactions === 0 &&
        partial[4].ledger === 0,
      "Fixture recovery POST-GUARD harus APPROVED tanpa stock effect.",
    );
    console.log("[PASS] durable recovery: empat cancellation terminal utuh, POST-GUARD siap dilanjutkan");
    return "POST_GUARD_APPROVED";
  }

  const expected = ["CANCELLED", "CANCELLED", "CANCELLED", "CANCELLED", "POSTED"];
  if (!states.every((state, index) => state?.status === expected[index])) fail(`Fixture durable partial/unexpected: ${JSON.stringify(states.map((state) => state?.status ?? null))}`);
  const batches = names.map((name) => batchFor(container, org, name));
  if (batches.some((batch) => !batch)) fail("Fixture durable tidak memiliki batch yang utuh.");
  const before = states.map((state, index) => snapshot(container, org, { ...batches[index], ...state }));
  before.slice(0, 4).forEach((state, index) => assertOneCancelled(state, `Fixture terminal ${names[index]} tidak utuh.`));
  assert(before[4].status === "POSTED" && before[4].cancellations === 0 && before[4].postings === 1 && before[4].transactions === 1 && before[4].ledger > 0, "Fixture POST-GUARD tidak utuh.");
  const after = states.map((state, index) => snapshot(container, org, { ...batches[index], ...state }));
  same(before, after, "Durable rerun tidak boleh menambah domain effect");
  console.log("[PASS] durable rerun: fixture terminal tetap exact tanpa effect tambahan");
  return true;
}

async function main() {
  const config = await env(); verifyLocal(config); const container = db();
  const [tokenA, tokenB] = await Promise.all([login(config), login(config)]);
  assert(tokenA !== tokenB, "Dua login harus menghasilkan token independen.");
  const org = await organization(config, tokenA);
  assert(org === await organization(config, tokenB), "Dua session harus berada pada organisasi yang sama.");
  const durableState = await runTerminalReplay(container, org);
  if (durableState === true) return;
  if (durableState === "POST_GUARD_APPROVED") {
    const state = existing(container, org, "POST-GUARD");
    const batch = batchFor(container, org, "POST-GUARD");
    if (!state || !batch) fail("Fixture recovery POST-GUARD tidak utuh.");
    const postGuard = { ...batch, ...state };
    const blocked = await cancel(config, tokenA, org, postGuard, `${PREFIX}:POST-GUARD:cancel-before-post`, "Tidak boleh cancel approved.");
    assert(!blocked.ok && code(blocked) === "STOCKTAKE_CANCEL_INVALID_STATE", `APPROVED harus menolak cancel: ${code(blocked)}`);
    const posted = await rpc(config, tokenA, "post_stocktake_adjustment", { p_organization_id: org, p_idempotency_key: `stocktake:${postGuard.stocktakeId}:post:${postGuard.approvalVersion}`, p_stocktake_id: postGuard.stocktakeId, p_approval_version: postGuard.approvalVersion, p_confirmation: true, p_note: "Post guard concurrency fixture.", p_metadata: { source: "stocktake-cancellation-parallel" } });
    assert(posted.ok, `Posting approved fixture gagal: ${code(posted)}`);
    const afterPostCancel = await cancel(config, tokenB, org, postGuard, `${PREFIX}:POST-GUARD:cancel-after-post`, "Tidak boleh cancel posted.");
    assert(!afterPostCancel.ok && code(afterPostCancel) === "STOCKTAKE_CANCEL_INVALID_STATE", `POSTED harus menolak cancel: ${code(afterPostCancel)}`);
    const postGuardAfter = snapshot(container, org, postGuard);
    assert(postGuardAfter.status === "POSTED" && postGuardAfter.cancellations === 0 && postGuardAfter.postings === 1 && postGuardAfter.transactions === 1 && postGuardAfter.ledger > 0, "CANCELLED tidak boleh muncul sebelum/selepas POSTED.");
    console.log("[PASS] post guard recovery: APPROVED/POSTED menolak cancel, CANCELLED tidak dapat kemudian POSTED");
    return;
  }

  const replay = await createDraft(config, tokenA, org, container, "REPLAY");
  const replayBefore = snapshot(container, org, replay); const replayKey = `${PREFIX}:REPLAY:cancel`;
  const [replayA, replayB] = await Promise.all([cancel(config, tokenA, org, replay, replayKey, "Replay identik."), cancel(config, tokenB, org, replay, replayKey, "Replay identik.")]);
  assert(replayA.ok && replayB.ok && replayA.payload?.cancellationId === replayB.payload?.cancellationId, `Replay identik tidak canonical: ${code(replayA)} / ${code(replayB)}`);
  const replayAfter = snapshot(container, org, replay); assertOneCancelled(replayAfter, "Replay identik harus satu cancellation."); assert(replayAfter.commands === replayBefore.commands + 1, "Replay identik harus satu idempotency command."); assertNeutral(replayBefore, replayAfter, "Replay identik"); console.log("[PASS] identical cancel replay: satu audit/domain effect");

  const conflict = await createDraft(config, tokenA, org, container, "CONFLICT");
  const conflictBefore = snapshot(container, org, conflict); const conflictKey = `${PREFIX}:CONFLICT:cancel`;
  const [conflictA, conflictB] = await Promise.all([cancel(config, tokenA, org, conflict, conflictKey, "Payload A."), cancel(config, tokenB, org, conflict, conflictKey, "Payload B berbeda.")]);
  const conflictResults = [conflictA, conflictB]; assert(conflictResults.filter((result) => result.ok).length === 1 && code(conflictResults.find((result) => !result.ok)) === "IDEMPOTENCY_KEY_REUSED", `Changed payload harus IDEMPOTENCY_KEY_REUSED: ${code(conflictA)} / ${code(conflictB)}`);
  const conflictAfter = snapshot(container, org, conflict); assertOneCancelled(conflictAfter, "Changed payload harus satu cancellation."); assert(conflictAfter.commands === conflictBefore.commands + 1, "Changed payload harus satu command."); assertNeutral(conflictBefore, conflictAfter, "Changed payload"); console.log("[PASS] same key changed payload: satu winner, satu IDEMPOTENCY_KEY_REUSED");

  const contention = await createDraft(config, tokenA, org, container, "CONTENTION");
  const contentionBefore = snapshot(container, org, contention);
  const [contentionA, contentionB] = await Promise.all([cancel(config, tokenA, org, contention, `${PREFIX}:CONTENTION:a`, "Command A."), cancel(config, tokenB, org, contention, `${PREFIX}:CONTENTION:b`, "Command B.")]);
  const contentionResults = [contentionA, contentionB]; assert(contentionResults.filter((result) => result.ok).length === 1 && code(contentionResults.find((result) => !result.ok)) === "STOCKTAKE_CANCEL_INVALID_STATE", `Contention harus satu winner: ${code(contentionA)} / ${code(contentionB)}`);
  const contentionAfter = snapshot(container, org, contention); assertOneCancelled(contentionAfter, "Contention harus satu cancellation."); assert(contentionAfter.commands === contentionBefore.commands + 1, "Contention loser tidak boleh membuat command effect."); assertNeutral(contentionBefore, contentionAfter, "Contention"); console.log("[PASS] different command identities: satu winner, satu invalid-state");

  const transition = await prepareCounting(config, tokenA, org, container, "TRANSITION");
  const line = (await rows(config, tokenA, `stocktake_non_blind_lines?organization_id=eq.${encodeURIComponent(org)}&stocktake_id=eq.${encodeURIComponent(transition.stocktakeId)}&select=*&order=line_no.asc`))[0];
  if (!line) fail("Line transition tidak tersedia.");
  const transitionBefore = snapshot(container, org, transition);
  const [transitionCancel, transitionCount] = await Promise.all([cancel(config, tokenA, org, transition, `${PREFIX}:TRANSITION:cancel`, "Race dengan count."), submitCount(config, tokenB, org, transition, line.stocktake_line_id, `${PREFIX}:TRANSITION:count`)]);
  assert(transitionCancel.ok, `Cancel harus menang atau mengikuti count yang tetap cancellable: ${code(transitionCancel)}`);
  assert(transitionCount.ok || code(transitionCount) === "STOCKTAKE_INVALID_STATE", `Count race harus commit atau invalid-state: ${code(transitionCount)}`);
  const transitionAfter = snapshot(container, org, transition); assertOneCancelled(transitionAfter, "Race transition final harus CANCELLED."); assert(transitionAfter.attempts === transitionBefore.attempts || transitionAfter.attempts === transitionBefore.attempts + 1, "Count attempt race tidak boleh partial."); assertNeutral(transitionBefore, transitionAfter, "Cancel versus count"); console.log("[PASS] cancel vs submit count: outcome serializable dan count evidence preserved bila commit");

  const recountRace = await prepareReview(config, tokenA, org, container, "RECOUNT-RACE");
  const recountLine = (await rows(config, tokenA, `stocktake_review_lines?organization_id=eq.${encodeURIComponent(org)}&stocktake_id=eq.${encodeURIComponent(recountRace.stocktakeId)}&select=*&order=line_no.asc`))[0];
  if (!recountLine) fail("Line recount race tidak tersedia.");
  const recountBefore = snapshot(container, org, recountRace);
  const [recountCancel, recountRequest] = await Promise.all([
    cancel(config, tokenA, org, recountRace, `${PREFIX}:RECOUNT-RACE:cancel`, "Race dengan recount."),
    requestReviewRecount(config, tokenB, org, recountRace, recountLine, `${PREFIX}:RECOUNT-RACE:recount`),
  ]);
  assert(recountCancel.ok, `Cancel versus recount harus menang atau mengikuti COUNTING yang cancellable: ${code(recountCancel)}`);
  assert(recountRequest.ok || code(recountRequest) === "STOCKTAKE_REVIEW_INVALID_STATE", `Recount race harus commit atau invalid-state: ${code(recountRequest)}`);
  const recountAfter = snapshot(container, org, recountRace);
  assertOneCancelled(recountAfter, "Cancel versus recount harus terminal CANCELLED.");
  assert(recountAfter.attempts === recountBefore.attempts, "Recount request tidak boleh membuat count attempt parsial.");
  assertNeutral(recountBefore, recountAfter, "Cancel versus recount");
  console.log("[PASS] cancel vs recount: outcome serializable, evidence count preserved");

  const reviewRace = await prepareReview(config, tokenA, org, container, "REVIEW-RACE");
  const reviewRaceLine = (await rows(config, tokenA, `stocktake_review_lines?organization_id=eq.${encodeURIComponent(org)}&stocktake_id=eq.${encodeURIComponent(reviewRace.stocktakeId)}&select=*&order=line_no.asc`))[0];
  if (!reviewRaceLine) fail("Line review race tidak tersedia.");
  const reviewBefore = snapshot(container, org, reviewRace);
  const [reviewCancel, reviewed] = await Promise.all([
    cancel(config, tokenA, org, reviewRace, `${PREFIX}:REVIEW-RACE:cancel`, "Race dengan review."),
    reviewLine(config, tokenB, org, reviewRace, reviewRaceLine, `${PREFIX}:REVIEW-RACE:review`),
  ]);
  assert(reviewCancel.ok, `Cancel versus review harus selesai canonical: ${code(reviewCancel)}`);
  assert(reviewed.ok || code(reviewed) === "STOCKTAKE_REVIEW_INVALID_STATE", `Review race harus commit atau invalid-state: ${code(reviewed)}`);
  const reviewAfter = snapshot(container, org, reviewRace);
  assertOneCancelled(reviewAfter, "Cancel versus review harus terminal CANCELLED.");
  assert(reviewAfter.attempts === reviewBefore.attempts, "Review tidak boleh menghapus count attempt.");
  assertNeutral(reviewBefore, reviewAfter, "Cancel versus review");
  console.log("[PASS] cancel vs review: outcome serializable dan evidence preserved");

  const approvalRace = await prepareReview(config, tokenA, org, container, "APPROVAL-RACE");
  const approvalLine = (await rows(config, tokenA, `stocktake_review_lines?organization_id=eq.${encodeURIComponent(org)}&stocktake_id=eq.${encodeURIComponent(approvalRace.stocktakeId)}&select=*&order=line_no.asc`))[0];
  if (!approvalLine) fail("Line approval race tidak tersedia.");
  const approvalReview = await reviewLine(config, tokenA, org, approvalRace, approvalLine, `${PREFIX}:APPROVAL-RACE:review`);
  if (!approvalReview.ok) fail(`Prepare approval race review: ${code(approvalReview)}`);
  const approvalDetail = (await rows(config, tokenA, `stocktake_details?organization_id=eq.${encodeURIComponent(org)}&stocktake_id=eq.${encodeURIComponent(approvalRace.stocktakeId)}&select=*&limit=1`))[0];
  const approvalBefore = snapshot(container, org, approvalRace);
  const [approvalCancel, approved] = await Promise.all([
    cancel(config, tokenA, org, approvalRace, `${PREFIX}:APPROVAL-RACE:cancel`, "Race dengan approval."),
    rpc(config, tokenB, "approve_stocktake", { p_organization_id: org, p_idempotency_key: `${PREFIX}:APPROVAL-RACE:approve:${approvalDetail.version_no}`, p_stocktake_id: approvalRace.stocktakeId, p_expected_stocktake_version: approvalDetail.version_no, p_confirmation: true, p_note: "Race approval.", p_metadata: { source: "stocktake-cancellation-parallel" } }),
  ]);
  const approvalAfter = snapshot(container, org, approvalRace);
  assert((approvalCancel.ok && !approved.ok && code(approved) === "STOCKTAKE_REVIEW_INVALID_STATE" && approvalAfter.status === "CANCELLED" && approvalAfter.cancellations === 1) || (!approvalCancel.ok && code(approvalCancel) === "STOCKTAKE_CANCEL_INVALID_STATE" && approved.ok && approvalAfter.status === "APPROVED" && approvalAfter.cancellations === 0), `Cancel versus approval harus satu outcome serializable: ${code(approvalCancel)} / ${code(approved)}`);
  assert(approvalAfter.attempts === approvalBefore.attempts, "Approval race tidak boleh menghapus count attempt.");
  assertNeutral(approvalBefore, approvalAfter, "Cancel versus approval");
  console.log("[PASS] cancel vs approval: satu winner state-machine dan tidak ada partial state");

  const postGuard = await prepareApproved(config, tokenA, org, container, "POST-GUARD");
  const [postCancel, posted] = await Promise.all([
    cancel(config, tokenA, org, postGuard, `${PREFIX}:POST-GUARD:cancel-parallel`, "Tidak boleh cancel approved."),
    rpc(config, tokenB, "post_stocktake_adjustment", { p_organization_id: org, p_idempotency_key: `stocktake:${postGuard.stocktakeId}:post:${postGuard.approvalVersion}`, p_stocktake_id: postGuard.stocktakeId, p_approval_version: postGuard.approvalVersion, p_confirmation: true, p_note: "Post guard concurrency fixture.", p_metadata: { source: "stocktake-cancellation-parallel" } }),
  ]);
  assert(!postCancel.ok && code(postCancel) === "STOCKTAKE_CANCEL_INVALID_STATE", `APPROVED cancel parallel harus ditolak: ${code(postCancel)}`);
  assert(posted.ok, `Posting approved fixture gagal: ${code(posted)}`);
  const afterPostCancel = await cancel(config, tokenA, org, postGuard, `${PREFIX}:POST-GUARD:cancel-after-post`, "Tidak boleh cancel posted.");
  assert(!afterPostCancel.ok && code(afterPostCancel) === "STOCKTAKE_CANCEL_INVALID_STATE", `POSTED harus menolak cancel: ${code(afterPostCancel)}`);
  const postGuardAfter = snapshot(container, org, postGuard); assert(postGuardAfter.status === "POSTED" && postGuardAfter.cancellations === 0 && postGuardAfter.postings === 1 && postGuardAfter.transactions === 1 && postGuardAfter.ledger > 0, "CANCELLED tidak boleh muncul sebelum/selepas POSTED."); console.log("[PASS] cancel vs post: two-session parallel post wins from APPROVED and CANCELLED cannot follow");
}

main().then(() => console.log("Stocktake cancellation parallel harness PASS")).catch((error) => { console.error(error instanceof Error ? error.stack : error); process.exitCode = 1; });
