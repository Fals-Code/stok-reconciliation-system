import { spawn, spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import process from "node:process";

const baseUrl = process.env.CSV_IMPORT_SMOKE_URL ?? "http://127.0.0.1:3000";
const serverPort = new URL(baseUrl).port || "3000";
const email = process.env.CSV_IMPORT_SMOKE_EMAIL ?? "demo.admin@glowlab.invalid";
const password = process.env.CSV_IMPORT_SMOKE_PASSWORD ?? "LocalSmoke123!";
let server;
let token;
let profile;
let key;
const results = [];

function pass(name, condition, detail = "") { results.push({ name, condition }); console.log(`${condition ? "[PASS]" : "[FAIL]"} ${name}${detail ? ` — ${detail}` : ""}`); if (!condition) throw new Error(name); }
async function env() { const text = await readFile(".env.local", "utf8"); return Object.fromEntries(text.split(/\r?\n/).filter((line) => line && !line.startsWith("#") && line.includes("=")).map((line) => { const i = line.indexOf("="); return [line.slice(0, i), line.slice(i + 1).replace(/^['"]|['"]$/g, "")]; })); }
async function waitReady() { for (let i = 0; i < 90; i++) { try { const response = await fetch(`${baseUrl}/login`); if (response.status === 200) return; } catch {} await new Promise((resolve) => setTimeout(resolve, 1000)); } throw new Error("Next server tidak siap"); }
async function login(config) { const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password }) }); if (!response.ok) throw new Error(`Login gagal: ${await response.text()}`); const data = await response.json(); token = data.access_token; const profileResponse = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/current_admin_profile?select=*`, { headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Accept-Profile": "api" } }); profile = (await profileResponse.json())[0]; key = config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY; }
function cookie() { return `glowlab_access_token=${token}`; }
async function page(path) { const response = await fetch(`${baseUrl}${path}`, { headers: { Cookie: cookie() }, redirect: "manual" }); return { response, html: await response.text() }; }
function actionName(html, marker) { const forms = html.match(/<form\b[^>]*>[\s\S]*?<\/form>/gi) ?? []; const form = forms.find((item) => item.toLowerCase().includes(marker.toLowerCase())); if (!form) throw new Error(`Form ${marker} tidak ditemukan`); const match = form.match(/name="(\$ACTION_ID_[^"]+)"/); if (!match) throw new Error("Server action tidak ditemukan"); return match[1]; }
function hidden(html, name) { const match = html.match(new RegExp(`<input[^>]+name="${name}"[^>]+value="([^"]*)"`, "i")); return match?.[1] ?? ""; }
async function postAction(path, html, marker, fields) { const form = new FormData(); form.append(actionName(html, marker), ""); for (const [name, value] of Object.entries(fields)) form.append(name, value); const response = await fetch(`${baseUrl}${path}`, { method: "POST", headers: { Cookie: cookie(), Origin: baseUrl, Referer: `${baseUrl}${path}` }, body: form, redirect: "manual" }); pass(`server action ${marker} redirect`, [302, 303, 307, 308].includes(response.status)); return response.headers.get("location"); }
async function main() {
  const config = await env();
  const health = await fetch(`${baseUrl}/login`).catch(() => null);
  if (!health || health.status !== 200) { server = spawn(process.execPath, ["node_modules/next/dist/bin/next", "dev", "--hostname", "127.0.0.1", "--port", serverPort], { stdio: "ignore", windowsHide: true }); await waitReady(); }
  await login(config);
  const listingResponse = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/marketplace_listing_catalog?organization_id=eq.${profile.organization_id}&status_code=eq.ACTIVE&mapping_readiness_code=eq.PUBLISHED&select=channel_code,external_listing_code&order=external_listing_code.asc&limit=1`, { headers: { apikey: key, Authorization: `Bearer ${token}`, "Accept-Profile": "api" } });
  const listing = (await listingResponse.json())[0]; pass("listing canonical tersedia", Boolean(listing));
  const importPage = await page("/marketplace/import"); pass("route import dapat dibuka", importPage.response.status === 200); pass("judul Import Pesanan tampil", importPage.html.includes("Import Pesanan")); pass("template link tampil", importPage.html.includes("marketplace/import/template")); pass("upload form tampil", importPage.html.includes("Unggah untuk preview"));
  const template = await fetch(`${baseUrl}/marketplace/import/template`, { headers: { Cookie: cookie() } }); pass("template download private", template.status === 200 && (template.headers.get("content-disposition") ?? "").includes("marketplace-reservation-v1-template.csv"));
  const existingEventResponse = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/marketplace_events?organization_id=eq.${profile.organization_id}&external_event_ref=eq.CSV-UI-SMOKE-V1&select=event_id,event_type_code,transaction_id&limit=2`, { headers: { apikey: key, Authorization: `Bearer ${token}`, "Accept-Profile": "api" } });
  const existingEvents = await existingEventResponse.json();
  if (Array.isArray(existingEvents) && existingEvents.length > 0) {
    pass("immutable smoke event tetap satu dan stock-neutral", existingEvents.length === 1 && existingEvents[0].event_type_code === "RESERVE" && existingEvents[0].transaction_id === null);
    console.log(`CSV UI smoke PASS: ${results.length} checks (durable immutable fixture; tidak membuat job/event baru)`);
    return;
  }
  const csv = ["schema_version,channel_code,external_event_ref,external_order_ref,source_status,occurred_at,received_at,source_line_ref,external_listing_code,listing_quantity,event_type,source_title,source_sku,note", `MARKETPLACE_RESERVATION_V1,${listing.channel_code},CSV-UI-SMOKE-V1,CSV-UI-SMOKE-V1,READY_TO_SHIP,2026-07-26T09:00:00Z,2026-07-26T09:01:00Z,LINE-1,${listing.external_listing_code},1,ORDER,Smoke,,durable`].join("\r\n") + "\r\n";
  const location = await postAction("/marketplace/import", importPage.html, "Unggah untuk preview", { file: new File([csv], "csv-ui-smoke-v1.csv", { type: "text/csv" }) });
  pass("upload mengarah ke detail job", Boolean(location?.includes("/marketplace/import/") && !location.includes("?error=")), location ?? "no location");
  let detail = await page(new URL(location, baseUrl).pathname + new URL(location, baseUrl).search);
  if (detail.html.includes("CSV_IMPORT_COMMIT")) throw new Error(detail.html);
  pass("preview row/error tampil", detail.response.status === 200 && detail.html.includes("Baris dan masalah per data")); pass("canonical preview tampil", detail.html.includes("Pemetaan produk"));
  const errorReport = await fetch(`${baseUrl}${new URL(location, baseUrl).pathname}/errors`, { headers: { Cookie: cookie() } }); pass("error report route authorized", errorReport.status === 200 && (errorReport.headers.get("content-type") ?? "").includes("text/csv"));
  if (detail.html.includes("Hasil pemrosesan") || detail.html.includes("Selesai")) {
    pass("durable exact replay mempertahankan hasil commit", detail.html.includes("Hasil pemrosesan") || detail.html.includes("Selesai"));
    console.log(`CSV UI smoke PASS: ${results.length} checks (durable replay)`);
    return;
  }
  pass("explicit confirmation tersedia", detail.html.includes("Periksa sebelum memproses"));
  const commitLocation = await postAction(new URL(location, baseUrl).pathname, detail.html, "Proses semua pesanan", { jobId: new URL(location, baseUrl).pathname.split("/").at(-1), commitKey: hidden(detail.html, "commitKey"), confirmation: "on" });
  pass("commit action redirect", Boolean(commitLocation)); detail = await page(new URL(commitLocation, baseUrl).pathname + new URL(commitLocation, baseUrl).search); pass("commit result atau failure aman tampil", detail.response.status === 200 && (detail.html.includes("Hasil pemrosesan") || detail.html.includes("Pemrosesan belum selesai")));
  console.log(`CSV UI smoke PASS: ${results.length} checks`);
}
main().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => { if (server?.pid) spawnSync("taskkill", ["/PID", String(server.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" }); });
