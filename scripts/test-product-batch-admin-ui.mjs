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
function pass(name, ok, detail = "") { results.push({ name, ok, detail }); console.log(`${ok ? "[PASS]" : "[FAIL]"} ${name}${detail ? ` — ${detail}` : ""}`); if (!ok) throw new Error(name); }
function command(file, args) { const result = spawnSync(file, args, { cwd: process.cwd(), encoding: "utf8", shell: false, windowsHide: true }); if (result.status !== 0) throw new Error(`${file} gagal: ${result.stderr || result.stdout}`); return result.stdout; }
async function env() { const raw = await readFile(".env.local", "utf8"); const values = {}; for (const line of raw.split(/\r?\n/)) { const index = line.indexOf("="); if (index > 0 && !line.trimStart().startsWith("#")) values[line.slice(0,index).trim()] = line.slice(index + 1).trim().replace(/^['"]|['"]$/g, ""); } return values; }
async function ready() { try { return (await fetch(baseUrl, { redirect: "manual", signal: AbortSignal.timeout(1000) })).status < 500; } catch { return false; } }
async function start() { if (await ready()) return; const uri = new URL(baseUrl); server = spawn(process.execPath, [path.resolve(process.cwd(), "node_modules", "next", "dist", "bin", "next"), "dev", "--hostname", uri.hostname, "--port", String(uri.port || 3000)], { cwd: process.cwd(), stdio: ["ignore", "pipe", "pipe"], windowsHide: true }); server.stdout.on("data", (chunk) => { serverOutput += chunk; }); server.stderr.on("data", (chunk) => { serverOutput += chunk; }); for (let i = 0; i < 90; i += 1) { if (server.exitCode != null) throw new Error(`Next.js berhenti: ${serverOutput}`); await new Promise((resolve) => setTimeout(resolve, 1000)); if (await ready()) return; } throw new Error(`Next.js tidak siap: ${serverOutput}`); }
async function main() {
  const config = await env();
  const supabaseUrl = (config.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321").replace(/\/$/, "");
  const key = config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  pass("Konfigurasi publishable key tersedia", Boolean(key && !key.includes("REPLACE_ME")));
  command(process.execPath, ["scripts/create-demo-admin.mjs", "--email", email, "--password", password, "--name", "Product Admin Smoke"]);
  const auth = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: key, "Content-Type": "application/json" }, body: JSON.stringify({ email, password }) });
  const token = await auth.json(); pass("Admin smoke dapat login", auth.ok && Boolean(token.access_token));
  const headers = { apikey: key, Authorization: `Bearer ${token.access_token}`, "Content-Type": "application/json", "Accept-Profile": "api", "Content-Profile": "api" };
  async function rpc(name, body, expected = true) { const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, { method: "POST", headers, body: JSON.stringify(body) }); const raw = await response.text(); if (expected) pass(`RPC ${name} berhasil`, response.ok, raw); return { response, raw, json: raw ? JSON.parse(raw) : null }; }
  async function view(path) { const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, { headers: { apikey: key, Authorization: `Bearer ${token.access_token}`, "Accept-Profile": "api" } }); return response.json(); }
  await start();
  const anonymous = await fetch(`${baseUrl}/products`, { redirect: "manual" }); pass("Anonim ditolak dari /products", [302,303,307,308].includes(anonymous.status) && (anonymous.headers.get("location") ?? "").includes("/login"));
  const sessionCookie = `glowlab_access_token=${token.access_token}`;
  async function page(path) { const response = await fetch(`${baseUrl}${path}`, { headers: { Cookie: sessionCookie }, redirect: "manual" }); const html = await response.text(); return { response, html }; }
  const initial = await page("/products"); pass("Admin dapat membuka /products", initial.response.ok && initial.html.includes("Kelola Produk tanpa mengubah stok"));
  const suffix = Date.now().toString(36).toUpperCase(); const sku = `SMOKE PRODUCT ${suffix}`; const idempotency = randomUUID();
  const created = await rpc("create_product", { p_organization_id: (await view("current_admin_profile?select=organization_id"))[0].organization_id, p_idempotency_key: `product-admin-smoke:create:${idempotency}`, p_sku: `  ${sku}  `, p_name: "Produk Smoke", p_unit_code: "UNIT", p_description: "Deskripsi awal", p_note: "Focused smoke." });
  const product = created.json; pass("Create Produk stock-neutral", product.status === "CREATED" && product.stockEffect === "NONE");
  const refreshed = await page("/products"); pass("Produk bertahan setelah refresh", refreshed.html.includes(sku));
  const duplicate = await rpc("create_product", { p_organization_id: (await view("current_admin_profile?select=organization_id"))[0].organization_id, p_idempotency_key: `product-admin-smoke:duplicate:${randomUUID()}`, p_sku: sku.toLowerCase(), p_name: "Duplikat", p_unit_code: "UNIT" }, false); pass("SKU normalisasi duplikat ditolak", !duplicate.response.ok && duplicate.raw.includes("DUPLICATE_SKU"));
  const missing = await rpc("create_product", { p_organization_id: (await view("current_admin_profile?select=organization_id"))[0].organization_id, p_idempotency_key: `product-admin-smoke:missing:${randomUUID()}`, p_sku: "", p_name: "", p_unit_code: "UNIT" }, false); pass("Field wajib ditolak", !missing.response.ok && missing.raw.includes("PRODUCT_REQUIRED_FIELDS_MISSING"));
  const updated = await rpc("update_product", { p_organization_id: (await view("current_admin_profile?select=organization_id"))[0].organization_id, p_idempotency_key: `product-admin-smoke:update:${randomUUID()}`, p_product_id: product.productId, p_expected_row_version: product.rowVersion, p_sku: sku, p_name: "Produk Smoke Revisi", p_unit_code: "UNIT", p_description: "Deskripsi revisi" });
  pass("Edit nama dan deskripsi sukses", updated.json.status === "UPDATED");
  const stale = await rpc("update_product", { p_organization_id: (await view("current_admin_profile?select=organization_id"))[0].organization_id, p_idempotency_key: `product-admin-smoke:stale:${randomUUID()}`, p_product_id: product.productId, p_expected_row_version: product.rowVersion, p_sku: sku, p_name: "Stale", p_unit_code: "UNIT" }, false); pass("Stale row version ditolak", !stale.response.ok && stale.raw.includes("PRODUCT_STALE_VERSION"));
  const org = (await view("current_admin_profile?select=organization_id"))[0].organization_id;
  const historyRows = await view(`product_master?organization_id=eq.${encodeURIComponent(org)}&has_authoritative_history=eq.true&is_active=eq.true&select=product_id,sku,name,row_version&limit=1`);
  pass("Fixture Produk berhistori tersedia tanpa membuat ledger baru", historyRows.length > 0);
  const history = historyRows[0];
  const skuAfterHistory = await rpc("update_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:sku-history:${randomUUID()}`, p_product_id: history.product_id, p_expected_row_version: history.row_version, p_sku: `${history.sku} SMOKE`, p_name: history.name, p_unit_code: "UNIT" }, false); pass("SKU dengan history ditolak", !skuAfterHistory.response.ok && skuAfterHistory.raw.includes("TRANSACTED_SKU_CHANGE_FORBIDDEN"));  const archived = await rpc("archive_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:archive:${randomUUID()}`, p_product_id: product.productId, p_expected_row_version: updated.json.rowVersion, p_reason: "Smoke archive" }); pass("Archive Produk sukses", archived.json.status === "ARCHIVED");
  const detail = await page(`/products/${product.productId}`); pass("Produk archived tetap membuka audit", detail.html.includes("DIARSIPKAN") && detail.html.includes("Jejak perubahan"));
  const manual = await page("/manual-outbounds"); pass("Produk archived tidak ada di selector transaksi baru", !manual.html.includes(sku));
  const reactivated = await rpc("reactivate_product", { p_organization_id: org, p_idempotency_key: `product-admin-smoke:reactivate:${randomUUID()}`, p_product_id: product.productId, p_expected_row_version: archived.json.rowVersion, p_reason: "Smoke reactivate" }); pass("Reactivate Produk sukses", reactivated.json.status === "REACTIVATED");
  const bySku = await page(`/products?q=${encodeURIComponent(sku)}`); const byName = await page("/products?q=Revisi"); const filtered = await page("/products?status=ACTIVE"); pass("Search SKU, nama, dan filter status bekerja", bySku.html.includes(sku) && byName.html.includes("Produk Smoke Revisi") && filtered.html.includes(sku));
  const feedback = await page("/products?success=Produk+tersimpan"); pass("Feedback success persisten", feedback.html.includes("Produk tersimpan"));
  pass("Tidak ada error runtime relevan", !refreshed.html.includes("Unhandled Runtime Error") && !detail.html.includes("Internal Server Error"));
}
try { await main(); } catch (error) { console.error(error); process.exitCode = 1; } finally { if (server) { if (process.platform === "win32") spawnSync("taskkill", ["/PID", String(server.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" }); else server.kill(); } console.table(results.map((result) => ({ status: result.ok ? "PASS" : "FAIL", test: result.name }))); console.log(`Result: ${results.every((result) => result.ok) ? "PASS" : "FAIL"} (${results.filter((result) => result.ok).length} passed)`); }