import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const baseUrl = process.env.PRODUCT_STOCK_EXPLANATION_SMOKE_URL ?? "http://127.0.0.1:31289";
const orgId = "00000000-0000-4000-8000-000000000001";
const successProductId = "30000000-0000-4000-8000-000000000001";
const zeroProductId = "00000000-0000-4072-8000-000000000021";
const mismatchProductId = "00000000-0000-4072-8000-000000000022";
const results = [];
let server;
let serverOutput = "";

function check(name, ok, detail = "") {
  if (!ok) throw new Error(`${name}${detail ? `: ${detail}` : ""}`);
  results.push(name);
  console.log(`[PASS] ${name}${detail ? ` — ${detail}` : ""}`);
}

function run(file, args, input) {
  const result = spawnSync(file, args, { cwd: process.cwd(), input, encoding: "utf8", windowsHide: true });
  if (result.error || result.status !== 0) throw new Error(`${file} gagal: ${result.stderr || result.stdout || result.error?.message}`);
  return result.stdout ?? "";
}

function db() {
  return run("docker", ["ps", "--format", "{{.Names}}"])
    .split(/\r?\n/)
    .find((name) => name.startsWith("supabase_db_"));
}

function sql(statement) {
  const container = db();
  if (!container) throw new Error("Container Supabase lokal tidak ditemukan.");
  return run("docker", ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-q", "-v", "ON_ERROR_STOP=1"], statement);
}

function jsonLine(output) {
  const line = output.split(/\r?\n/).map((value) => value.trim()).findLast((value) => value.startsWith("{"));
  if (!line) throw new Error("SQL tidak mengembalikan JSON.");
  return JSON.parse(line);
}

async function config() {
  const raw = await readFile(".env.local", "utf8");
  return Object.fromEntries(raw.split(/\r?\n/).flatMap((line) => {
    const index = line.indexOf("=");
    return index > 0 && !line.trimStart().startsWith("#") ? [[line.slice(0, index).trim(), line.slice(index + 1).trim().replace(/^['"]|['"]$/g, "")]] : [];
  }));
}

async function ready() {
  try { return (await fetch(baseUrl, { redirect: "manual", signal: AbortSignal.timeout(1_000) })).status < 500; } catch { return false; }
}

async function start() {
  if (await ready()) return;
  const url = new URL(baseUrl);
  server = spawn(process.execPath, [path.join(process.cwd(), "node_modules", "next", "dist", "bin", "next"), "dev", "--hostname", url.hostname, "--port", url.port], { cwd: process.cwd(), stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
  server.stdout.on("data", (chunk) => { serverOutput += chunk; });
  server.stderr.on("data", (chunk) => { serverOutput += chunk; });
  for (let attempt = 0; attempt < 90; attempt += 1) {
    if (server.exitCode != null) throw new Error(`Next.js berhenti: ${serverOutput}`);
    await new Promise((resolve) => setTimeout(resolve, 1_000));
    if (await ready()) return;
  }
  throw new Error(`Next.js tidak siap: ${serverOutput}`);
}

function stop() { if (server && server.exitCode == null) server.kill("SIGTERM"); }

async function main() {
  const env = await config();
  const supabaseUrl = (env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321").replace(/\/$/, "");
  const key = env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  check("Konfigurasi publishable key tersedia", Boolean(key && !key.includes("REPLACE_ME")));

  const email = "demo.admin@glowlab.invalid";
  const password = `${randomUUID().replaceAll("-", "")}Aa1!`;
  run(process.execPath, ["scripts/create-demo-admin.mjs", "--email", email, "--password", password, "--name", "Issue 89 Runtime Smoke"]);
  const auth = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: key, "Content-Type": "application/json" }, body: JSON.stringify({ email, password }) });
  const token = await auth.json();
  check("Admin lokal dapat login", auth.ok && Boolean(token.access_token));

  sql(`
    insert into catalog.products(id, organization_id, sku, name) values
      ('${zeroProductId}', '${orgId}', 'EXPLAIN-ZERO-RUNTIME', 'Explain zero runtime'),
      ('${mismatchProductId}', '${orgId}', 'EXPLAIN-MISMATCH-RUNTIME', 'Explain mismatch runtime')
    on conflict (id) do nothing;
    insert into inventory.stock_product_positions(organization_id, product_id, sellable_qty, quarantine_qty, damaged_qty, reserved_qty, last_ledger_seq, version) values
      ('${orgId}', '${zeroProductId}', 0, 0, 0, 0, 0, 0),
      ('${orgId}', '${mismatchProductId}', 3, 0, 0, 1, 0, 0)
    on conflict (organization_id, product_id) do update set sellable_qty = excluded.sellable_qty, quarantine_qty = excluded.quarantine_qty, damaged_qty = excluded.damaged_qty, reserved_qty = excluded.reserved_qty;
  `);

  const baseline = jsonLine(sql(`select jsonb_build_object('transactions',(select count(*) from inventory.stock_transactions where organization_id='${orgId}'),'ledger',(select count(*) from inventory.stock_ledger_entries where organization_id='${orgId}'),'positions',(select count(*) from inventory.stock_product_positions where organization_id='${orgId}'),'reservations',(select count(*) from inventory.stock_reservations where organization_id='${orgId}'),'runs',(select count(*) from reconciliation.runs where organization_id='${orgId}'),'issues',(select count(*) from reconciliation.issues where organization_id='${orgId}'),'idempotency',(select count(*) from inventory.idempotency_commands where organization_id='${orgId}'));`));

  await start();
  const cookie = `glowlab_access_token=${token.access_token}`;
  async function page(route) {
    const response = await fetch(`${baseUrl}${route}`, { headers: { Cookie: cookie }, redirect: "manual" });
    return { response, html: await response.text() };
  }

  const success = await page(`/products/${successProductId}?explainStock=1`);
  check("SUCCESS merender Ringkasan Jelaskan Stok", success.response.ok && success.html.includes("Jelaskan Stok") && success.html.includes("Layak Dijual") && success.html.includes("Batas ledger: urutan #"));
  check("SUCCESS menampilkan grouped movement dan status match", success.html.includes("Buka bukti ledger") && success.html.includes("Sama"));
  const drillDownHref = success.html.match(/href="(\/ledger\?[^\"]*productId=[^\"]*)"[^>]*>Buka bukti ledger/)?.[1]?.replaceAll("&amp;", "&") ?? "";
  const drillDown = drillDownHref ? await page(drillDownHref) : { response: new Response(), html: "" };
  check("Drill-down membuka Ledger terfilter tanpa UUID input", Boolean(drillDownHref) && drillDown.response.ok && drillDown.html.includes("Riwayat Stok") && drillDown.html.includes(successProductId));
  const refreshed = await page(`/products/${successProductId}?explainStock=1`);
  check("Refresh mempertahankan explanation dari state database", refreshed.response.ok && refreshed.html.includes("Batas ledger: urutan #"));

  const zero = await page(`/products/${zeroProductId}?explainStock=1`);
  check("ZERO HISTORY dengan projection nol adalah empty normal", zero.response.ok && zero.html.includes("Belum ada bukti pergerakan") && zero.html.includes("Sama"));
  const mismatch = await page(`/products/${mismatchProductId}?explainStock=1`);
  check("ZERO HISTORY plus projection nonzero tampil mismatch eksplisit", mismatch.response.ok && mismatch.html.includes("Selisih — perlu ditelusuri"));
  check("Mismatch tidak dilabel aman atau verified", !/aman|verified|terverifikasi/i.test(mismatch.html));

  const after = jsonLine(sql(`select jsonb_build_object('transactions',(select count(*) from inventory.stock_transactions where organization_id='${orgId}'),'ledger',(select count(*) from inventory.stock_ledger_entries where organization_id='${orgId}'),'positions',(select count(*) from inventory.stock_product_positions where organization_id='${orgId}'),'reservations',(select count(*) from inventory.stock_reservations where organization_id='${orgId}'),'runs',(select count(*) from reconciliation.runs where organization_id='${orgId}'),'issues',(select count(*) from reconciliation.issues where organization_id='${orgId}'),'idempotency',(select count(*) from inventory.idempotency_commands where organization_id='${orgId}'));`));
  check("Render dan reload explanation stock-neutral", JSON.stringify(after) === JSON.stringify(baseline));
  console.log(`Product stock explanation runtime smoke PASS (${results.length} checks)`);
}

try { await main(); } finally { stop(); }
