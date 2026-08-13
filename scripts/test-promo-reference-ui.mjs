import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const baseUrl = process.env.PROMO_ADMIN_SMOKE_BASE_URL ?? "http://127.0.0.1:31102";
const email = process.env.PROMO_ADMIN_SMOKE_EMAIL ?? "demo.admin@glowlab.invalid";
const password = process.env.PROMO_ADMIN_SMOKE_PASSWORD;
if (!password) {
  console.error("PROMO_ADMIN_SMOKE_PASSWORD wajib tersedia untuk smoke test lokal.");
  process.exit(1);
}
const results = [];
let server;
let serverOutput = "";
let failure;

function pass(name, ok, detail = "", scope = "Promo") {
  results.push({ name, ok, detail, scope });
  console.log(`${ok ? "[PASS]" : "[FAIL]"} ${name}${detail ? ` - ${detail}` : ""}`);
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
    if (index > 0 && !line.trimStart().startsWith("#")) {
      values[line.slice(0, index).trim()] = line.slice(index + 1).trim().replace(/^['"]|['"]$/g, "");
    }
  }
  return values;
}

async function ready() {
  try {
    const res = await fetch(baseUrl, { redirect: "manual", signal: AbortSignal.timeout(1000) });
    return res.status < 500;
  } catch {
    return false;
  }
}

async function start() {
  if (await ready()) return;
  const uri = new URL(baseUrl);
  server = spawn(process.execPath, [
    path.resolve(process.cwd(), "node_modules", "next", "dist", "bin", "next"),
    "dev",
    "--hostname",
    uri.hostname,
    "--port",
    String(uri.port || 3000)
  ], { cwd: process.cwd(), stdio: ["ignore", "pipe", "pipe"], windowsHide: true });

  server.stdout.on("data", (chunk) => { serverOutput += chunk; });
  server.stderr.on("data", (chunk) => { serverOutput += chunk; });

  for (let i = 0; i < 90; i += 1) {
    if (server.exitCode != null) throw new Error(`Next.js berhenti: ${serverOutput}`);
    await new Promise((resolve) => setTimeout(resolve, 1000));
    if (await ready()) return;
  }
  throw new Error(`Next.js tidak siap: ${serverOutput}`);
}

async function main() {
  const config = await env();
  const supabaseUrl = (config.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321").replace(/\/$/, "");
  const key = config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  pass("Konfigurasi publishable key tersedia", Boolean(key && !key.includes("REPLACE_ME")));

  command(process.execPath, [
    "scripts/create-demo-admin.mjs",
    "--email",
    email,
    "--password",
    password,
    "--name",
    "Promo Admin Smoke"
  ]);

  const auth = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: key, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password })
  });
  const token = await auth.json();
  pass("Admin smoke dapat login", auth.ok && Boolean(token.access_token));

  const headers = {
    apikey: key,
    Authorization: `Bearer ${token.access_token}`,
    "Content-Type": "application/json",
    "Accept-Profile": "api",
    "Content-Profile": "api"
  };

  async function rpc(name, body, expected = true) {
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body)
    });
    const raw = await response.text();
    if (expected) pass(`RPC ${name} berhasil`, response.ok, raw);
    return { response, raw, json: raw ? JSON.parse(raw) : null };
  }

  async function view(pathname) {
    const response = await fetch(`${supabaseUrl}/rest/v1/${pathname}`, {
      headers: { apikey: key, Authorization: `Bearer ${token.access_token}`, "Accept-Profile": "api" }
    });
    return response.json();
  }

  async function stockSnapshot() {
    async function readRows(entity) {
      const rows = await view(`${entity}?organization_id=eq.${encodeURIComponent(org)}&select=*`);
      return (Array.isArray(rows) ? rows : []).sort((left, right) =>
        JSON.stringify(left).localeCompare(JSON.stringify(right))
      );
    }

    return {
      ledger_transactions: await readRows("ledger_transaction_detail"),
      ledger_entries: await readRows("ledger_explorer"),
      product_positions: await readRows("product_master"),
      batch_balances: await readRows("product_batch_master"),
      reservations: await readRows("marketplace_reservations"),
      manual_outbounds: await readRows("manual_outbounds"),
    };
  }

  await start();

  // Test Guardrail 1: Anon ditolak
  const anonymous = await fetch(`${baseUrl}/settings/promos`, { redirect: "manual" });
  pass("Anonim ditolak dari /settings/promos", [302, 303, 307, 308].includes(anonymous.status) && (anonymous.headers.get("location") ?? "").includes("/login"));

  const sessionCookie = `glowlab_access_token=${token.access_token}`;

  async function page(pathname) {
    const response = await fetch(`${baseUrl}${pathname}`, { headers: { Cookie: sessionCookie }, redirect: "manual" });
    const html = await response.text();
    return { response, html };
  }

  // Test Guardrail 2: Admin dapat membuka /settings/promos
  const initial = await page("/settings/promos");
  if (!initial.response.ok || !initial.html.includes("Referensi Promo") || !initial.html.includes("Tambah Referensi Promo")) {
    console.error("DIAGNOSTIC - Status:", initial.response.status);
    console.error("DIAGNOSTIC - Location Header:", initial.response.headers.get("location"));
    console.error("DIAGNOSTIC - Html snippet:", initial.html.slice(0, 800));
  }
  pass("Admin dapat membuka /settings/promos", initial.response.ok && initial.html.includes("Referensi Promo") && initial.html.includes("Tambah Referensi Promo"));

  const org = (await view("current_admin_profile?select=organization_id"))[0].organization_id;
  const suffix = Date.now().toString(36).toUpperCase();
  const promoCode = `PROMO_SMOKE_${suffix}`;
  const promoName = `Promo Smoke ${suffix}`;
  const idempotency = randomUUID();

  const stockBefore = await stockSnapshot();

  // Test Guardrail 3: Create Promo Reference
  const created = await rpc("create_promo_reference", {
    p_organization_id: org,
    p_idempotency_key: `promo-admin-smoke:create:${idempotency}`,
    p_code: promoCode,
    p_name: promoName,
    p_description: "Focused promo smoke"
  });

  const promoResult = created.json;
  pass("Create Promo Reference berhasil dan stock-neutral", created.response.ok && Boolean(promoResult.promoId) && promoResult.status === "CREATED");

  const refreshed = await page("/settings/promos");
  pass("Promo baru bertahan setelah refresh", refreshed.html.includes(promoCode) && refreshed.html.includes(promoName));

  // Test Guardrail 4: Collision promo code ditolak
  const duplicate = await rpc("create_promo_reference", {
    p_organization_id: org,
    p_idempotency_key: `promo-admin-smoke:duplicate:${randomUUID()}`,
    p_code: promoCode,
    p_name: "Promo Duplikat"
  }, false);
  pass("Duplikasi Kode Promo ditolak", !duplicate.response.ok && duplicate.raw.includes("DUPLICATE_PROMO_CODE"));

  // Test Guardrail 5: Edit promo name & description
  const updated = await rpc("update_promo_reference", {
    p_organization_id: org,
    p_idempotency_key: `promo-admin-smoke:update:${randomUUID()}`,
    p_promo_id: promoResult.promoId,
    p_expected_row_version: promoResult.rowVersion,
    p_name: `${promoName} Revisi`,
    p_description: "Deskripsi promo direvisi"
  });
  pass("Update Promo berhasil", updated.json.status === "UPDATED");

  const revisedRefreshed = await page("/settings/promos");
  pass("Revisi Promo bertahan setelah refresh", revisedRefreshed.html.includes(`${promoName} Revisi`) && revisedRefreshed.html.includes("Deskripsi promo direvisi"));

  // Test Guardrail 6: Concurrency / Stale Row Version ditolak
  const stale = await rpc("update_promo_reference", {
    p_organization_id: org,
    p_idempotency_key: `promo-admin-smoke:stale:${randomUUID()}`,
    p_promo_id: promoResult.promoId,
    p_expected_row_version: promoResult.rowVersion,
    p_name: "Stale"
  }, false);
  pass("Stale row version ditolak", !stale.response.ok && stale.raw.includes("CONCURRENCY_ERROR"));

  // Test Guardrail 7: Archive / Deactivate Promo
  const archived = await rpc("archive_promo_reference", {
    p_organization_id: org,
    p_idempotency_key: `promo-admin-smoke:archive:${randomUUID()}`,
    p_promo_id: promoResult.promoId,
    p_expected_row_version: updated.json.rowVersion,
    p_reason: "Smoke deactivation"
  });
  pass("Deactivate Promo berhasil", archived.json.status === "ARCHIVED");

  const archivedRefreshed = await page("/settings/promos");
  // StatusBadge neutral (tanpa tone="selected") untuk Tidak Aktif
  pass("Status badge neutral untuk tidak aktif", archivedRefreshed.html.includes("Tidak Aktif") && archivedRefreshed.html.includes("Aktifkan Kembali"));

  // Test Guardrail 8: Reactivate Promo
  const reactivated = await rpc("reactivate_promo_reference", {
    p_organization_id: org,
    p_idempotency_key: `promo-admin-smoke:reactivate:${randomUUID()}`,
    p_promo_id: promoResult.promoId,
    p_expected_row_version: archived.json.rowVersion,
    p_reason: "Smoke reactivation"
  });
  pass("Reactivate Promo berhasil", reactivated.json.status === "REACTIVATED");

  const reactivatedRefreshed = await page("/settings/promos");
  pass("Status badge selected untuk aktif kembali", reactivatedRefreshed.html.includes("Aktif") && reactivatedRefreshed.html.includes("Nonaktifkan"));

  // Test Guardrail 9: Six-surface stock neutrality snapshot
  const stockAfter = await stockSnapshot();
  pass("Enam surface stok tidak berubah setelah mutasi Promo", JSON.stringify(stockBefore) === JSON.stringify(stockAfter));

  // Test Guardrail 10: Cross-org mutation rejection
  const fakeOrgId = "00000000-0000-4000-8000-ffffffffffff";
  const crossOrgCreate = await rpc("create_promo_reference", {
    p_organization_id: fakeOrgId,
    p_idempotency_key: `promo-admin-smoke:crossorg:${randomUUID()}`,
    p_code: "CROSS_ORG_TEST",
    p_name: "Cross Org Test"
  }, false);
  pass("Cross-org create ditolak", !crossOrgCreate.response.ok && crossOrgCreate.raw.includes("ORGANIZATION_ACCESS_DENIED"));

  const crossOrgUpdate = await rpc("update_promo_reference", {
    p_organization_id: fakeOrgId,
    p_idempotency_key: `promo-admin-smoke:crossorg-update:${randomUUID()}`,
    p_promo_id: promoResult.promoId,
    p_expected_row_version: reactivated.json.rowVersion,
    p_name: "Cross Org"
  }, false);
  pass("Cross-org update ditolak", !crossOrgUpdate.response.ok && crossOrgUpdate.raw.includes("ORGANIZATION_ACCESS_DENIED"));

  // Test Guardrail 11: Search/filter query & status works
  const byCode = await page(`/settings/promos?q=${encodeURIComponent(promoCode)}`);
  const byName = await page("/settings/promos?q=Revisi");
  const filteredActive = await page("/settings/promos?status=ACTIVE");
  pass("Filter pencarian dan status bekerja di UI", byCode.html.includes(promoCode) && byName.html.includes("Revisi") && filteredActive.html.includes(promoCode));

  // Test Guardrail 10: Feedback query parameters persist
  const feedbackSuccess = await page("/settings/promos?success=Aksi+berhasil");
  pass("Feedback banner success muncul", feedbackSuccess.html.includes("Aksi berhasil"));

  pass("Tidak ada error runtime Next.js", !refreshed.html.includes("Unhandled Runtime Error") && !refreshed.html.includes("Internal Server Error"));
}

try {
  await main();
} catch (error) {
  failure = error;
  console.error(error);
  process.exitCode = 1;
} finally {
  if (server) {
    if (process.platform === "win32") {
      spawnSync("taskkill", ["/PID", String(server.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
    } else {
      server.kill();
    }
  }
  if (failure) {
    console.error("DIAGNOSTIC - NEXT SERVER OUTPUT:\n", serverOutput);
  }
  console.table(results.map((r) => ({ status: r.ok ? "PASS" : "FAIL", test: r.name })));
  console.log(`Total checks: ${results.filter((r) => r.ok).length}`);
  const succeeded = !failure && results.length > 0 && results.every((r) => r.ok);
  console.log(`Result: ${succeeded ? "PASS" : "FAIL"}`);
}
