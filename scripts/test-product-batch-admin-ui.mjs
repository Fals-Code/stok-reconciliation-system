import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const baseUrl = process.env.PRODUCT_ADMIN_SMOKE_BASE_URL ?? "http://127.0.0.1:3000";
const email = process.env.PRODUCT_ADMIN_SMOKE_EMAIL ?? "demo.admin@glowlab.invalid";
const password = process.env.PRODUCT_ADMIN_SMOKE_PASSWORD ?? "LocalSmoke123!";
const results = [];
let server;
let serverOutput = "";
let failure;

function pass(name, ok, detail = "", scope = "Product") {
  results.push({ name, ok, detail, scope });
  console.log(`${ok ? "[PASS]" : "[FAIL]"} ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) throw new Error(name);
}

function command(file, args) {
  const result = spawnSync(file, args, { cwd: process.cwd(), encoding: "utf8", shell: false, windowsHide: true });
  if (result.status !== 0) throw new Error(`${file} gagal: ${result.stderr || result.stdout}`);
  return result.stdout;
}

async function env() {
  const raw = await readFile(".env.local", "utf8");
  const values = {};
  for (const line of raw.split(/\r?\n/)) {
    const index = line.indexOf("=");
    if (index > 0 && !line.trimStart().startsWith("#")) values[line.slice(0, index).trim()] = line.slice(index + 1).trim().replace(/^['"]|['"]$/g, "");
  }
  return values;
}

async function ready() {
  try {
    return (await fetch(baseUrl, { redirect: "manual", signal: AbortSignal.timeout(1000) })).status < 500;
  } catch {
    return false;
  }
}

async function start() {
  if (await ready()) return;
  const uri = new URL(baseUrl);
  server = spawn(process.execPath, [path.resolve(process.cwd(), "node_modules", "next", "dist", "bin", "next"), "dev", "--hostname", uri.hostname, "--port", String(uri.port || 3000)], { cwd: process.cwd(), stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
  server.stdout.on("data", (chunk) => { serverOutput += chunk; });
  server.stderr.on("data", (chunk) => { serverOutput += chunk; });
  for (let i = 0; i < 90; i += 1) {
    if (server.exitCode != null) throw new Error(`Next.js berhenti: ${serverOutput}`);
    await new Promise((resolve) => setTimeout(resolve, 1000));
    if (await ready()) return;
  }
  throw new Error(`Next.js tidak siap: ${serverOutput}`);
}

function addDays(date, days) {
  const value = new Date(`${date}T00:00:00.000Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

function pageText(html) {
  return html
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

async function main() {
  const config = await env();
  const supabaseUrl = (config.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321").replace(/\/$/, "");
  const key = config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  pass("Konfigurasi publishable key tersedia", Boolean(key && !key.includes("REPLACE_ME")));
  command(process.execPath, ["scripts/create-demo-admin.mjs", "--email", email, "--password", password, "--name", "Product Admin Smoke"]);
  const auth = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: key, "Content-Type": "application/json" }, body: JSON.stringify({ email, password }) });
  const token = await auth.json();
  pass("Admin smoke dapat login", auth.ok && Boolean(token.access_token));
  const headers = { apikey: key, Authorization: `Bearer ${token.access_token}`, "Content-Type": "application/json", "Accept-Profile": "api", "Content-Profile": "api" };
  async function rpc(name, body, expected = true, scope = "Product") {
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, { method: "POST", headers, body: JSON.stringify(body) });
    const raw = await response.text();
    if (expected) pass(`RPC ${name} berhasil`, response.ok, raw, scope);
    return { response, raw, json: raw ? JSON.parse(raw) : null };
  }
  async function view(pathname) {
    const response = await fetch(`${supabaseUrl}/rest/v1/${pathname}`, { headers: { apikey: key, Authorization: `Bearer ${token.access_token}`, "Accept-Profile": "api" } });
    return response.json();
  }
  async function restoreSmokeExpiryFixtures(organizationId) {
    const corrections = await view(`product_batch_master_audit?organization_id=eq.${encodeURIComponent(organizationId)}&reason=eq.${encodeURIComponent("Smoke expiry correction")}&select=batch_id,before_snapshot,after_snapshot&order=occurred_at.desc&limit=3000`);
    for (const correction of corrections) {
      const [master] = await view(`product_batch_master?batch_id=eq.${encodeURIComponent(correction.batch_id)}&select=batch_id,product_id,batch_code,batch_kind_code,manufactured_date,expiry_date,received_first_at,row_version&limit=1`);
      const originalExpiry = correction.before_snapshot?.expiryDate;
      const correctedExpiry = correction.after_snapshot?.expiryDate;
      if (!master || !originalExpiry || master.expiry_date !== correctedExpiry) continue;
      const restored = await rpc("update_product_batch", { p_organization_id: organizationId, p_idempotency_key: `product-batch-admin-smoke:fixture-restore:${randomUUID()}`, p_batch_id: master.batch_id, p_expected_row_version: master.row_version, p_product_id: master.product_id, p_batch_kind_code: master.batch_kind_code, p_batch_code: master.batch_code, p_manufactured_date: master.manufactured_date, p_expiry_date: originalExpiry, p_received_first_at: master.received_first_at, p_reason: "Smoke fixture cleanup" }, false);
      if (!restored.response.ok) throw new Error(`Fixture Batch cleanup gagal: ${restored.raw}`);
    }
  }

  await start();
  const anonymous = await fetch(`${baseUrl}/products`, { redirect: "manual" });
  pass("Anonim ditolak dari /products", [302, 303, 307, 308].includes(anonymous.status) && (anonymous.headers.get("location") ?? "").includes("/login"));
  const sessionCookie = `glowlab_access_token=${token.access_token}`;
  async function page(pathname) {
    const response = await fetch(`${baseUrl}${pathname}`, { headers: { Cookie: sessionCookie }, redirect: "manual" });
    const html = await response.text();
    return { response, html };
  }

  const initial = await page("/products");
  pass("Admin dapat membuka /products", initial.response.ok && initial.html.includes("Kelola Produk tanpa mengubah stok"));
  const suffix = Date.now().toString(36).toUpperCase();
  const sku = `SMOKE PRODUCT ${suffix}`;
  const idempotency = randomUUID();
  const org = (await view("current_admin_profile?select=organization_id"))[0].organization_id;
  await restoreSmokeExpiryFixtures(org);
  const created = await rpc("create_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:create:${idempotency}`, p_sku: `  ${sku}  `, p_name: "Produk Smoke", p_unit_code: "UNIT", p_description: "Deskripsi awal", p_note: "Focused smoke." });
  const product = created.json;
  pass("Create Produk stock-neutral", product.status === "CREATED" && product.stockEffect === "NONE");
  const refreshed = await page("/products");
  pass("Produk bertahan setelah refresh", refreshed.html.includes(sku));
  const duplicate = await rpc("create_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:duplicate:${randomUUID()}`, p_sku: sku.toLowerCase(), p_name: "Duplikat", p_unit_code: "UNIT" }, false);
  pass("SKU normalisasi duplikat ditolak", !duplicate.response.ok && duplicate.raw.includes("DUPLICATE_SKU"));
  const missing = await rpc("create_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:missing:${randomUUID()}`, p_sku: "", p_name: "", p_unit_code: "UNIT" }, false);
  pass("Field wajib ditolak", !missing.response.ok && missing.raw.includes("PRODUCT_REQUIRED_FIELDS_MISSING"));
  const updated = await rpc("update_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:update:${randomUUID()}`, p_product_id: product.productId, p_expected_row_version: product.rowVersion, p_sku: sku, p_name: "Produk Smoke Revisi", p_unit_code: "UNIT", p_description: "Deskripsi revisi" });
  pass("Edit nama dan deskripsi sukses", updated.json.status === "UPDATED");
  const stale = await rpc("update_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:stale:${randomUUID()}`, p_product_id: product.productId, p_expected_row_version: product.rowVersion, p_sku: sku, p_name: "Stale", p_unit_code: "UNIT" }, false);
  pass("Stale row version ditolak", !stale.response.ok && stale.raw.includes("PRODUCT_STALE_VERSION"));
  const historyRows = await view(`product_master?organization_id=eq.${encodeURIComponent(org)}&has_authoritative_history=eq.true&is_active=eq.true&select=product_id,sku,name,row_version&limit=1`);
  pass("Fixture Produk berhistori tersedia tanpa membuat ledger baru", historyRows.length > 0);
  const history = historyRows[0];
  const skuAfterHistory = await rpc("update_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:sku-history:${randomUUID()}`, p_product_id: history.product_id, p_expected_row_version: history.row_version, p_sku: `${history.sku} SMOKE`, p_name: history.name, p_unit_code: "UNIT" }, false);
  pass("SKU dengan history ditolak", !skuAfterHistory.response.ok && skuAfterHistory.raw.includes("TRANSACTED_SKU_CHANGE_FORBIDDEN"));

  const batchCode = `SMOKE BATCH ${suffix}`;
  const batchExpiry = "2099-12-31";
  const activeDetail = await page(`/products/${product.productId}`);
  pass("Admin membuka detail Produk dan melihat form Tambah Batch", activeDetail.response.ok && activeDetail.html.includes("Tambah Batch STANDARD") && activeDetail.html.includes("Kode Batch"), "", "Batch");
  const batchCreated = await rpc("create_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:create:${randomUUID()}`, p_product_id: product.productId, p_batch_code: `  ${batchCode}  `, p_expiry_date: batchExpiry, p_manufactured_date: "2099-01-01", p_received_first_at: "2099-01-02T00:00:00+07:00", p_batch_kind_code: "STANDARD", p_note: "Focused batch smoke." }, false);
  const batch = batchCreated.json;
  pass("Create Batch STANDARD sukses dan stock-neutral", batchCreated.response.ok && batch.status === "CREATED" && batch.batchKindCode === "STANDARD" && batch.stockEffect === "NONE", batchCreated.raw, "Batch");
  const batchRefreshed = await page(`/products/${product.productId}`);
  pass("Batch bertahan setelah refresh/read ulang", batchRefreshed.html.includes(batchCode), "", "Batch");
  const duplicateBatch = await rpc("create_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:duplicate:${randomUUID()}`, p_product_id: product.productId, p_batch_code: batchCode.toLowerCase(), p_expiry_date: batchExpiry, p_batch_kind_code: "STANDARD" }, false);
  pass("Normalized duplicate batch code ditolak", !duplicateBatch.response.ok && duplicateBatch.raw.includes("DUPLICATE_PRODUCT_BATCH"), "", "Batch");
  const missingExpiry = await rpc("create_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:missing-expiry:${randomUUID()}`, p_product_id: product.productId, p_batch_code: `MISSING EXPIRY ${suffix}`, p_expiry_date: null, p_batch_kind_code: "STANDARD" }, false);
  pass("Expiry wajib ditolak ketika kosong", !missingExpiry.response.ok && missingExpiry.raw.includes("EXPIRY_DATE_REQUIRED"), "", "Batch");
  const invalidRange = await rpc("create_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:invalid-range:${randomUUID()}`, p_product_id: product.productId, p_batch_code: `INVALID RANGE ${suffix}`, p_expiry_date: "2099-01-01", p_manufactured_date: "2099-01-02", p_batch_kind_code: "STANDARD" }, false);
  pass("Manufactured date setelah expiry ditolak", !invalidRange.response.ok && invalidRange.raw.includes("INVALID_BATCH_DATE_RANGE"), "", "Batch");
  const manualReturn = await rpc("create_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:return:${randomUUID()}`, p_product_id: product.productId, p_batch_code: `RETURN ${suffix}`, p_expiry_date: batchExpiry, p_batch_kind_code: "RETURN" }, false);
  pass("Create manual RETURN ditolak pada trusted RPC boundary", !manualReturn.response.ok && manualReturn.raw.includes("MANUAL_BATCH_KIND_FORBIDDEN"), "", "Batch");
  const manualUnidentifiedReturn = await rpc("create_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:unidentified-return:${randomUUID()}`, p_product_id: product.productId, p_batch_code: `UNIDENTIFIED RETURN ${suffix}`, p_expiry_date: batchExpiry, p_batch_kind_code: "UNIDENTIFIED_RETURN" }, false);
  pass("Create manual UNIDENTIFIED_RETURN ditolak", !manualUnidentifiedReturn.response.ok && manualUnidentifiedReturn.raw.includes("MANUAL_BATCH_KIND_FORBIDDEN"), "", "Batch");

  const archived = await rpc("archive_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:archive:${randomUUID()}`, p_product_id: product.productId, p_expected_row_version: updated.json.rowVersion, p_reason: "Smoke archive" });
  pass("Archive Produk sukses", archived.json.status === "ARCHIVED");
  const detail = await page(`/products/${product.productId}`);
  pass("Produk archived tetap membuka audit", detail.html.includes("DIARSIPKAN") && detail.html.includes("Jejak perubahan"));
  const archivedProductBatch = await rpc("create_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:archived-product:${randomUUID()}`, p_product_id: product.productId, p_batch_code: `ARCHIVED PRODUCT ${suffix}`, p_expiry_date: batchExpiry, p_batch_kind_code: "STANDARD" }, false);
  pass("Produk archived tidak dapat menerima Batch baru", !archivedProductBatch.response.ok && archivedProductBatch.raw.includes("INACTIVE_PRODUCT_FOR_TRANSACTION") && detail.html.includes("Produk archived tidak dapat menerima Batch baru."), "", "Batch");
  const manual = await page("/manual-outbounds");
  pass("Produk archived tidak ada di selector transaksi baru", !manual.html.includes(sku));
  const reactivated = await rpc("reactivate_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:reactivate:${randomUUID()}`, p_product_id: product.productId, p_expected_row_version: archived.json.rowVersion, p_reason: "Smoke reactivate" });
  pass("Reactivate Produk sukses", reactivated.json.status === "REACTIVATED");

  const batchUpdated = await rpc("update_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:update:${randomUUID()}`, p_batch_id: batch.batchId, p_expected_row_version: batch.rowVersion, p_product_id: product.productId, p_batch_kind_code: "STANDARD", p_batch_code: batchCode, p_manufactured_date: "2099-01-01", p_expiry_date: batchExpiry, p_received_first_at: "2099-01-03T00:00:00+07:00", p_reason: null, p_note: "Update allowed attribute." }, false);
  pass("Update atribut Batch yang diizinkan berhasil", batchUpdated.response.ok && batchUpdated.json.status === "UPDATED" && batchUpdated.json.receivedFirstAt?.startsWith("2099-01-02T17:00:00"), batchUpdated.raw, "Batch");
  const immutableProduct = await rpc("update_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:immutable-product:${randomUUID()}`, p_batch_id: batch.batchId, p_expected_row_version: batchUpdated.json.rowVersion, p_product_id: history.product_id, p_batch_kind_code: "STANDARD", p_batch_code: batchCode, p_manufactured_date: "2099-01-01", p_expiry_date: batchExpiry, p_received_first_at: "2099-01-03T00:00:00+07:00" }, false);
  pass("Product linkage immutable", !immutableProduct.response.ok && immutableProduct.raw.includes("BATCH_PRODUCT_CHANGE_FORBIDDEN"), "", "Batch");
  const immutableKind = await rpc("update_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:immutable-kind:${randomUUID()}`, p_batch_id: batch.batchId, p_expected_row_version: batchUpdated.json.rowVersion, p_product_id: product.productId, p_batch_kind_code: "RETURN", p_batch_code: batchCode, p_manufactured_date: "2099-01-01", p_expiry_date: batchExpiry, p_received_first_at: "2099-01-03T00:00:00+07:00" }, false);
  pass("Batch kind immutable", !immutableKind.response.ok && immutableKind.raw.includes("BATCH_KIND_CHANGE_FORBIDDEN"), "", "Batch");
  const staleBatch = await rpc("update_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:stale:${randomUUID()}`, p_batch_id: batch.batchId, p_expected_row_version: batch.rowVersion, p_product_id: product.productId, p_batch_kind_code: "STANDARD", p_batch_code: batchCode, p_manufactured_date: "2099-01-01", p_expiry_date: batchExpiry, p_received_first_at: "2099-01-03T00:00:00+07:00" }, false);
  pass("Stale row_version Batch ditolak", !staleBatch.response.ok && staleBatch.raw.includes("BATCH_STALE_VERSION"), "", "Batch");

  const historyBatches = await view(`product_batch_master?organization_id=eq.${encodeURIComponent(org)}&has_authoritative_history=eq.true&batch_kind_code=eq.STANDARD&select=batch_id,product_id,batch_code,batch_kind_code,manufactured_date,expiry_date,received_first_at,row_version&limit=1`);
  pass("Fixture Batch berhistori tersedia tanpa membuat ledger baru", historyBatches.length > 0, "", "Batch");
  const historyBatch = historyBatches[0];
  const correctedExpiry = addDays(historyBatch.expiry_date, 1);
  const historyWithoutReason = await rpc("update_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:history-no-reason:${randomUUID()}`, p_batch_id: historyBatch.batch_id, p_expected_row_version: historyBatch.row_version, p_product_id: historyBatch.product_id, p_batch_kind_code: historyBatch.batch_kind_code, p_batch_code: historyBatch.batch_code, p_manufactured_date: historyBatch.manufactured_date, p_expiry_date: correctedExpiry, p_received_first_at: historyBatch.received_first_at, p_reason: null }, false);
  pass("Expiry Batch berhistori tanpa correction reason ditolak", !historyWithoutReason.response.ok && historyWithoutReason.raw.includes("EXPIRY_CHANGE_REASON_REQUIRED"), "", "Batch");
  const historyCorrected = await rpc("update_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:history-correction:${randomUUID()}`, p_batch_id: historyBatch.batch_id, p_expected_row_version: historyBatch.row_version, p_product_id: historyBatch.product_id, p_batch_kind_code: historyBatch.batch_kind_code, p_batch_code: historyBatch.batch_code, p_manufactured_date: historyBatch.manufactured_date, p_expiry_date: correctedExpiry, p_received_first_at: historyBatch.received_first_at, p_reason: "Smoke expiry correction" }, false);
  pass("Expiry correction dengan reason berhasil", historyCorrected.response.ok && historyCorrected.json.status === "UPDATED" && historyCorrected.json.expiryDate === correctedExpiry, historyCorrected.raw, "Batch");
  const historyAuditRows = await view(`product_batch_master_audit?audit_id=eq.${encodeURIComponent(historyCorrected.json.auditId)}&select=before_snapshot,after_snapshot,reason&limit=1`);
  const historyAudit = historyAuditRows[0];
  pass("Audit menyimpan expiry before dan after", historyAudit?.reason === "Smoke expiry correction" && historyAudit?.before_snapshot?.expiryDate === historyBatch.expiry_date && historyAudit?.after_snapshot?.expiryDate === correctedExpiry, JSON.stringify(historyAudit), "Batch");
  const historyRestored = await rpc("update_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:history-restore:${randomUUID()}`, p_batch_id: historyBatch.batch_id, p_expected_row_version: historyCorrected.json.rowVersion, p_product_id: historyBatch.product_id, p_batch_kind_code: historyBatch.batch_kind_code, p_batch_code: historyBatch.batch_code, p_manufactured_date: historyBatch.manufactured_date, p_expiry_date: historyBatch.expiry_date, p_received_first_at: historyBatch.received_first_at, p_reason: "Smoke fixture cleanup" }, false);
  if (!historyRestored.response.ok) throw new Error(`Fixture Batch cleanup gagal: ${historyRestored.raw}`);

  const blockWithoutReason = await rpc("block_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:block-no-reason:${randomUUID()}`, p_batch_id: batch.batchId, p_expected_row_version: batchUpdated.json.rowVersion, p_reason: "" }, false);
  pass("Block tanpa alasan ditolak", !blockWithoutReason.response.ok && blockWithoutReason.raw.includes("BATCH_STATUS_REASON_REQUIRED"), "", "Batch");
  const blocked = await rpc("block_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:block:${randomUUID()}`, p_batch_id: batch.batchId, p_expected_row_version: batchUpdated.json.rowVersion, p_reason: "Smoke block" }, false);
  pass("Block sukses", blocked.response.ok && blocked.json.status === "BLOCK" && blocked.json.lifecycleStatusCode === "BLOCKED", blocked.raw, "Batch");
  const blockedMaster = (await view(`product_batch_master?batch_id=eq.${encodeURIComponent(batch.batchId)}&select=*&limit=1`))[0];
  pass("BLOCKED Batch tidak FEFO eligible", blockedMaster.lifecycle_status_code === "BLOCKED" && blockedMaster.is_fefo_eligible === false, JSON.stringify(blockedMaster), "Batch");
  const unblocked = await rpc("unblock_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:unblock:${randomUUID()}`, p_batch_id: batch.batchId, p_expected_row_version: blocked.json.rowVersion, p_reason: "Smoke unblock" }, false);
  pass("Unblock valid berhasil", unblocked.response.ok && unblocked.json.status === "UNBLOCK" && unblocked.json.lifecycleStatusCode === "ACTIVE", unblocked.raw, "Batch");
  const batchArchived = await rpc("archive_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:archive:${randomUUID()}`, p_batch_id: batch.batchId, p_expected_row_version: unblocked.json.rowVersion, p_reason: "Smoke archive batch" }, false);
  pass("Archive Batch berhasil", batchArchived.response.ok && batchArchived.json.status === "ARCHIVE" && batchArchived.json.lifecycleStatusCode === "ARCHIVED", batchArchived.raw, "Batch");
  const archivedBatchDetail = await page(`/products/${product.productId}/batches/${batch.batchId}`);
  const archivedBatchAudits = await view(`product_batch_master_audit?batch_id=eq.${encodeURIComponent(batch.batchId)}&select=action_code,before_snapshot,after_snapshot&order=occurred_at.desc&limit=20`);
  pass("Archived Batch tetap terbaca beserta audit", archivedBatchDetail.response.ok && archivedBatchDetail.html.includes("ARCHIVED") && archivedBatchDetail.html.includes("Audit Batch") && archivedBatchAudits.some((audit) => audit.action_code === "BATCH_ARCHIVE"), "", "Batch");
  const disposal = await page("/stock-disposals");
  pass("Archived Batch tidak muncul pada selector transaksi baru yang relevan", !disposal.html.includes(batchCode), "", "Batch");
  const batchReactivated = await rpc("reactivate_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:reactivate:${randomUUID()}`, p_batch_id: batch.batchId, p_expected_row_version: batchArchived.json.rowVersion, p_reason: "Smoke reactivate batch" }, false);
  pass("Reactivate valid berhasil", batchReactivated.response.ok && batchReactivated.json.status === "REACTIVATE" && batchReactivated.json.lifecycleStatusCode === "ACTIVE", batchReactivated.raw, "Batch");

  const expiredCode = `SMOKE EXPIRED ${suffix}`;
  const expiredCreated = await rpc("create_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:expired-create:${randomUUID()}`, p_product_id: product.productId, p_batch_code: expiredCode, p_expiry_date: "2000-01-01", p_batch_kind_code: "STANDARD" }, false);
  if (!expiredCreated.response.ok) throw new Error(`Fixture Batch expired gagal dibuat: ${expiredCreated.raw}`);
  const expiredBlocked = await rpc("block_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:expired-block:${randomUUID()}`, p_batch_id: expiredCreated.json.batchId, p_expected_row_version: expiredCreated.json.rowVersion, p_reason: "Smoke expired block" }, false);
  if (!expiredBlocked.response.ok) throw new Error(`Fixture Batch expired gagal diblokir: ${expiredBlocked.raw}`);
  const expiredUnblock = await rpc("unblock_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:expired-unblock:${randomUUID()}`, p_batch_id: expiredCreated.json.batchId, p_expected_row_version: expiredBlocked.json.rowVersion, p_reason: "Attempt expired unblock" }, false);
  const expiredArchived = await rpc("archive_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:expired-archive:${randomUUID()}`, p_batch_id: expiredCreated.json.batchId, p_expected_row_version: expiredBlocked.json.rowVersion, p_reason: "Archive expired batch" }, false);
  if (!expiredArchived.response.ok) throw new Error(`Fixture Batch expired gagal diarsipkan: ${expiredArchived.raw}`);
  const expiredReactivate = await rpc("reactivate_product_batch", { p_organization_id: org, p_idempotency_key: `product-batch-admin-smoke:expired-reactivate:${randomUUID()}`, p_batch_id: expiredCreated.json.batchId, p_expected_row_version: expiredArchived.json.rowVersion, p_reason: "Attempt expired reactivate" }, false);
  pass("Effectively expired Batch tidak dapat di-unblock atau direactivate", !expiredUnblock.response.ok && expiredUnblock.raw.includes("BATCH_EFFECTIVELY_EXPIRED") && !expiredReactivate.response.ok && expiredReactivate.raw.includes("BATCH_EFFECTIVELY_EXPIRED"), "", "Batch");

  const bySku = await page(`/products?q=${encodeURIComponent(sku)}`);
  const byName = await page("/products?q=Revisi");
  const filtered = await page("/products?status=ACTIVE");
  pass("Search SKU, nama, dan filter status bekerja", bySku.html.includes(sku) && byName.html.includes("Produk Smoke Revisi") && filtered.html.includes(sku));
  const batchSearch = await page(`/products/${product.productId}?batchQ=${encodeURIComponent(batchCode)}&batchStatus=ACTIVE`);
  pass("Search/filter Batch bekerja", batchSearch.html.includes(batchCode) && batchSearch.html.includes("ACTIVE"), "", "Batch");
  const masterBatch = (await view(`product_batch_master?batch_id=eq.${encodeURIComponent(batch.batchId)}&select=*&limit=1`))[0];
  const currentBatchDetail = await page(`/products/${product.productId}/batches/${batch.batchId}`);
  const currentBatchText = pageText(currentBatchDetail.html);
  pass("Nilai bucket, reserved, available, status, dan FEFO sama dengan api.product_batch_master", currentBatchText.includes(`Status: ${masterBatch.lifecycle_status_code}`) && currentBatchText.includes(`SELLABLE: ${masterBatch.sellable_qty}`) && currentBatchText.includes(`QUARANTINE: ${masterBatch.quarantine_qty}`) && currentBatchText.includes(`DAMAGED: ${masterBatch.damaged_qty}`) && currentBatchText.includes(`Reserved: ${masterBatch.reserved_qty} (product-scoped)`) && currentBatchText.includes(`Available: ${masterBatch.available_qty}`) && currentBatchText.includes(`FEFO: ${masterBatch.is_fefo_eligible ? "Eligible" : "Tidak eligible"}`), JSON.stringify({ lifecycleStatusCode: masterBatch.lifecycle_status_code, sellableQty: masterBatch.sellable_qty, quarantineQty: masterBatch.quarantine_qty, damagedQty: masterBatch.damaged_qty, reservedQty: masterBatch.reserved_qty, availableQty: masterBatch.available_qty, isFefoEligible: masterBatch.is_fefo_eligible }), "Batch");
  const feedback = await page("/products?success=Produk+tersimpan");
  pass("Feedback success persisten", feedback.html.includes("Produk tersimpan"));
  const batchSuccessFeedback = await page(`/products/${product.productId}/batches/${batch.batchId}?success=Batch+tersimpan`);
  const batchErrorFeedback = await page(`/products/${product.productId}/batches/${batch.batchId}?error=Batch+gagal`);
  pass("Feedback sukses/error Batch bertahan setelah refresh", batchSuccessFeedback.html.includes("Batch tersimpan") && batchErrorFeedback.html.includes("Batch gagal"), "", "Batch");
  pass("Tidak ada error runtime relevan", !refreshed.html.includes("Unhandled Runtime Error") && !detail.html.includes("Internal Server Error"));
  pass("Tidak ada console, server, hydration, atau runtime error Batch relevan", !/(console error|hydration failed|unhandled runtime error|internal server error|\berror:\b)/i.test(`${serverOutput}\n${activeDetail.html}\n${currentBatchDetail.html}\n${archivedBatchDetail.html}`), "", "Batch");
}

try {
  await main();
} catch (error) {
  failure = error;
  console.error(error);
  process.exitCode = 1;
} finally {
  if (server) {
    if (process.platform === "win32") spawnSync("taskkill", ["/PID", String(server.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
    else server.kill();
  }
  console.table(results.map((result) => ({ scope: result.scope, status: result.ok ? "PASS" : "FAIL", test: result.name })));
  const productCount = results.filter((result) => result.scope === "Product" && result.ok).length;
  const batchCount = results.filter((result) => result.scope === "Batch" && result.ok).length;
  console.log(`Product checks: ${productCount}`);
  console.log(`Batch checks: ${batchCount}`);
  console.log(`Total checks: ${results.filter((result) => result.ok).length}`);
  const succeeded = !failure && results.length > 0 && results.every((result) => result.ok);
  console.log(`Result: ${succeeded ? "PASS" : "FAIL"} (${results.filter((result) => result.ok).length} passed)`);
}
