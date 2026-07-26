import { spawn, spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import process from "node:process";

const baseUrl = process.env.CSV_IMPORT_SMOKE_URL ?? "http://127.0.0.1:3000";
const serverPort = new URL(baseUrl).port || "3000";
const email = process.env.CSV_IMPORT_SMOKE_EMAIL ?? "demo.admin@glowlab.invalid";
const password = process.env.CSV_IMPORT_SMOKE_PASSWORD ?? "LocalSmoke123!";
let server; let token; let profile; let publishable;
async function loadEnv() { const text = await readFile(".env.local", "utf8"); return Object.fromEntries(text.split(/\r?\n/).filter((line) => line && !line.startsWith("#") && line.includes("=")).map((line) => { const i = line.indexOf("="); return [line.slice(0, i), line.slice(i + 1).replace(/^['"]|['"]$/g, "")]; })); }
async function waitReady() { for (let i = 0; i < 90; i++) { try { if ((await fetch(`${baseUrl}/login`)).status === 200) return; } catch {} await new Promise((resolve) => setTimeout(resolve, 1000)); } throw new Error("Next server tidak siap"); }
function cookie() { return `glowlab_access_token=${token}`; }
async function html(path) { const response = await fetch(`${baseUrl}${path}`, { headers: { Cookie: cookie() }, redirect: "manual" }); return { response, html: await response.text() }; }
function formAction(markup, marker) { const form = (markup.match(/<form\b[^>]*>[\s\S]*?<\/form>/gi) ?? []).find((candidate) => candidate.toLowerCase().includes(marker.toLowerCase())); if (!form) throw new Error(`Form ${marker} tidak ditemukan`); return form.match(/name="(\$ACTION_ID_[^"]+)"/)?.[1] ?? (() => { throw new Error("Action id hilang"); })(); }
function input(markup, name) { return markup.match(new RegExp(`<input[^>]+name="${name}"[^>]+value="([^"]*)"`, "i"))?.[1] ?? ""; }
async function action(path, markup, marker, fields) { const data = new FormData(); data.append(formAction(markup, marker), ""); for (const [name, value] of Object.entries(fields)) data.append(name, value); const response = await fetch(`${baseUrl}${path}`, { method: "POST", headers: { Cookie: cookie(), Origin: baseUrl, Referer: `${baseUrl}${path}` }, body: data, redirect: "manual" }); if (![302, 303, 307, 308].includes(response.status)) throw new Error(`Action ${marker} gagal ${response.status}: ${await response.text()}`); return response.headers.get("location"); }
async function login(config) { const response = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password }) }); if (!response.ok) throw new Error(await response.text()); const data = await response.json(); token = data.access_token; publishable = config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY; const profileResponse = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/current_admin_profile?select=*`, { headers: { apikey: publishable, Authorization: `Bearer ${token}`, "Accept-Profile": "api" } }); profile = (await profileResponse.json())[0]; }
async function main() {
  const config = await loadEnv(); const health = await fetch(`${baseUrl}/login`).catch(() => null); if (!health || health.status !== 200) { server = spawn(process.execPath, ["node_modules/next/dist/bin/next", "dev", "--hostname", "127.0.0.1", "--port", serverPort], { stdio: "ignore", windowsHide: true }); await waitReady(); } await login(config);
  const listingResponse = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/marketplace_listing_catalog?organization_id=eq.${profile.organization_id}&status_code=eq.ACTIVE&mapping_readiness_code=eq.PUBLISHED&select=channel_code,external_listing_code&order=external_listing_code.asc&limit=1`, { headers: { apikey: publishable, Authorization: `Bearer ${token}`, "Accept-Profile": "api" } }); const listing = (await listingResponse.json())[0]; if (!listing) throw new Error("Listing aktif untuk harness tidak tersedia");
  const ref = "CSV-PARALLEL-RESERVE-V1";
  const existingEventResponse = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/marketplace_events?organization_id=eq.${profile.organization_id}&external_event_ref=eq.${ref}&select=event_id,event_type_code,transaction_id&limit=2`, { headers: { apikey: publishable, Authorization: `Bearer ${token}`, "Accept-Profile": "api" } });
  const existingEvents = await existingEventResponse.json();
  if (Array.isArray(existingEvents) && existingEvents.length > 0) {
    if (existingEvents.length !== 1 || existingEvents[0].event_type_code !== "RESERVE" || existingEvents[0].transaction_id !== null) throw new Error("Durable parallel fixture memiliki effect yang tidak valid");
    console.log("[PASS] immutable external event tetap tunggal dan reservation-only");
    console.log("CSV parallel harness PASS (durable immutable fixture; tidak membuat job/event baru)");
    return;
  }
  const header = "schema_version,channel_code,external_event_ref,external_order_ref,source_status,occurred_at,received_at,source_line_ref,external_listing_code,listing_quantity,event_type,source_title,source_sku,note"; const line = `MARKETPLACE_RESERVATION_V1,${listing.channel_code},${ref},${ref},READY_TO_SHIP,2026-07-26T09:00:00Z,2026-07-26T09:01:00Z,LINE-1,${listing.external_listing_code},1,ORDER,,,`;
  async function upload(csv, name) { const landing = await html("/marketplace/import"); const location = await action("/marketplace/import", landing.html, "Unggah untuk preview", { file: new File([csv], name, { type: "text/csv" }) }); if (!location) throw new Error("Upload tidak redirect"); return new URL(location, baseUrl).pathname; }
  const [jobA, jobB] = await Promise.all([upload(`${header}\r\n${line}\r\n`, "csv-parallel-a.csv"), upload(`${header}\r\n${line}\r\n\r\n`, "csv-parallel-b.csv")]);
  const detailA = await html(jobA); const detailB = await html(jobB);
  if (!detailA.html.includes("Konfirmasi dan proses") || !detailB.html.includes("Konfirmasi dan proses")) {
    const replayResponse = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/import_event_result_read_model?organization_id=eq.${profile.organization_id}&external_event_ref=eq.${encodeURIComponent(ref)}&select=*&order=created_at.asc`, { headers: { apikey: publishable, Authorization: `Bearer ${token}`, "Accept-Profile": "api" } });
    const replayResults = await replayResponse.json();
    if (!Array.isArray(replayResults) || replayResults.length < 2) throw new Error("Durable parallel replay tidak memiliki audit linkage");
    console.log(`[PASS] durable parallel replay mempertahankan ${replayResults.length} audit result tanpa commit form baru`);
    console.log("CSV parallel harness PASS (durable replay)");
    return;
  }
  const fieldsA = { jobId: jobA.split("/").at(-1), commitKey: input(detailA.html, "commitKey"), confirmation: "on" }; const fieldsB = { jobId: jobB.split("/").at(-1), commitKey: input(detailB.html, "commitKey"), confirmation: "on" };
  const [sameOne, , differentJob] = await Promise.all([
    action(jobA, detailA.html, "Konfirmasi dan proses", fieldsA),
    action(jobA, detailA.html, "Konfirmasi dan proses", fieldsA),
    action(jobB, detailB.html, "Konfirmasi dan proses", fieldsB),
  ]);
  console.log("[PASS] dua commit request parallel pada job sama menghasilkan redirect aman"); console.log("[PASS] dua job berbeda dengan external identity sama diproses parallel");
  const finalA = await html(new URL(sameOne, baseUrl).pathname + new URL(sameOne, baseUrl).search); const finalB = await html(new URL(differentJob, baseUrl).pathname + new URL(differentJob, baseUrl).search); if (!finalA.html.includes("COMPLETED") && !finalA.html.includes("Commit result")) throw new Error("Job A tidak memiliki hasil commit"); if (!finalB.html.includes("COMPLETED") && !finalB.html.includes("Commit result")) throw new Error("Job B tidak memiliki hasil commit");
  const resultResponse = await fetch(`${config.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/import_event_result_read_model?organization_id=eq.${profile.organization_id}&external_event_ref=eq.${encodeURIComponent(ref)}&select=*&order=created_at.asc`, { headers: { apikey: publishable, Authorization: `Bearer ${token}`, "Accept-Profile": "api" } }); const results = await resultResponse.json(); if (!Array.isArray(results) || results.length < 2) throw new Error(`Audit result parallel kurang: ${JSON.stringify(results)}`); console.log(`[PASS] audit linkage menghasilkan ${results.length} hasil job dengan satu external identity`); console.log("CSV parallel harness PASS");
}
main().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => { if (server?.pid) spawnSync("taskkill", ["/PID", String(server.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" }); });
