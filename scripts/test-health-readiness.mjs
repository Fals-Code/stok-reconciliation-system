import { spawn, spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const healthyBaseUrl = "http://127.0.0.1:31291";
const unavailableBaseUrl = "http://127.0.0.1:31292";
const checks = [];
const servers = [];

function check(name, condition) {
  if (!condition) throw new Error(name);
  checks.push(name);
  console.log(`[PASS] ${name}`);
}

function run(file, args, input) {
  const result = spawnSync(file, args, { cwd: process.cwd(), input, encoding: "utf8", windowsHide: true });
  if (result.error || result.status !== 0) throw new Error(`${file} gagal: ${result.stderr || result.stdout || result.error?.message}`);
  return result.stdout ?? "";
}

function snapshot() {
  const container = run("docker", ["ps", "--format", "{{.Names}}"])
    .split(/\r?\n/).map((value) => value.trim()).find((name) => name.startsWith("supabase_db_"));
  if (!container) throw new Error("Container Supabase lokal tidak ditemukan.");
  const output = run("docker", ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-q", "-v", "ON_ERROR_STOP=1"], `select jsonb_build_object('transactions',(select count(*) from inventory.stock_transactions),'ledger',(select count(*) from inventory.stock_ledger_entries),'positions',(select count(*) from inventory.stock_product_positions),'reservations',(select count(*) from inventory.stock_reservations),'idempotency',(select count(*) from inventory.idempotency_commands),'reconciliationRuns',(select count(*) from reconciliation.runs),'reconciliationIssues',(select count(*) from reconciliation.issues));`);
  const row = output.split(/\r?\n/).map((value) => value.trim()).findLast((value) => value.startsWith("{"));
  if (!row) throw new Error("Snapshot database tidak mengembalikan JSON.");
  return JSON.parse(row);
}

async function config() {
  const raw = await readFile(".env.local", "utf8");
  return Object.fromEntries(raw.split(/\r?\n/).flatMap((line) => {
    const index = line.indexOf("=");
    return index <= 0 || line.trimStart().startsWith("#") ? [] : [[line.slice(0, index).trim(), line.slice(index + 1).trim().replace(/^['"]|['"]$/g, "")]];
  }));
}

async function alive(baseUrl) {
  try { return (await fetch(baseUrl, { signal: AbortSignal.timeout(1_000) })).status < 500; } catch { return false; }
}

async function start(baseUrl, environment = {}) {
  if (await alive(baseUrl)) throw new Error(`Port health smoke sudah digunakan: ${baseUrl}`);
  const url = new URL(baseUrl);
  let output = "";
  const server = spawn(process.execPath, [path.join(process.cwd(), "node_modules", "next", "dist", "bin", "next"), "dev", "--hostname", url.hostname, "--port", url.port], { cwd: process.cwd(), env: { ...process.env, ...environment }, stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
  servers.push(server);
  server.stdout.on("data", (chunk) => { output += chunk; });
  server.stderr.on("data", (chunk) => { output += chunk; });
  for (let attempt = 0; attempt < 90; attempt += 1) {
    if (server.exitCode != null) throw new Error(`Next.js berhenti: ${output}`);
    await new Promise((resolve) => setTimeout(resolve, 1_000));
    if (await alive(baseUrl)) return server;
  }
  throw new Error(`Next.js tidak siap: ${output}`);
}

async function stop(server) {
  if (server.exitCode != null) return;
  await new Promise((resolve) => {
    server.once("exit", resolve);
    server.kill("SIGTERM");
  });
}

async function request(baseUrl, pathname) {
  const response = await fetch(`${baseUrl}${pathname}`, { signal: AbortSignal.timeout(3_000) });
  return { response, body: await response.json() };
}

async function main() {
  const local = await config();
  const secret = local.SUPABASE_SECRET_KEY ?? "";
  check("Konfigurasi server-only readiness tersedia", Boolean(secret && !secret.includes("REPLACE_ME")));
  const before = snapshot();
  const healthyServer = await start(healthyBaseUrl);
  const live = await request(healthyBaseUrl, "/api/health/live");
  check("Liveness menjawab sehat", live.response.status === 200 && live.body?.status === "ok");
  const ready = await request(healthyBaseUrl, "/api/health/ready");
  check("Readiness memverifikasi dependency sehat", ready.response.status === 200 && ready.body?.status === "ready");
  check("Respons sehat tidak memaparkan konfigurasi atau secret", !JSON.stringify({ live: live.body, ready: ready.body }).includes(secret));
  await request(healthyBaseUrl, "/api/health/live");
  await request(healthyBaseUrl, "/api/health/ready");
  check("Liveness dan readiness berulang tetap stock-neutral", JSON.stringify(snapshot()) === JSON.stringify(before));
  await stop(healthyServer);
  await start(unavailableBaseUrl, { NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:1" });
  const unavailableLive = await request(unavailableBaseUrl, "/api/health/live");
  check("Liveness tidak bergantung pada database", unavailableLive.response.status === 200 && unavailableLive.body?.status === "ok");
  const unavailableReady = await request(unavailableBaseUrl, "/api/health/ready");
  check("Kegagalan dependency readiness terkontrol", unavailableReady.response.status === 503 && unavailableReady.body?.status === "unavailable" && !("error" in unavailableReady.body));
  check("Kegagalan readiness tidak memaparkan secret", !JSON.stringify(unavailableReady.body).includes(secret));
  console.log(`Health/readiness runtime smoke PASS (${checks.length} checks)`);
}

try { await main(); } finally { for (const server of servers) if (server.exitCode == null) server.kill("SIGTERM"); }
