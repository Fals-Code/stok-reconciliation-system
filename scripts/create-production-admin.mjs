import { readFile } from "node:fs/promises";
import path from "node:path";

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`Argumen --${key} membutuhkan nilai.`);
    result[key] = value;
    index += 1;
  }
  return result;
}

async function loadEnvFile(filePath) {
  const raw = await readFile(filePath, "utf8");
  const env = {};
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const separator = trimmed.indexOf("=");
    if (separator < 1) continue;
    const key = trimmed.slice(0, separator).trim();
    let value = trimmed.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
    env[key] = value;
  }
  return env;
}

async function parseResponse(response) {
  const raw = await response.text();
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return raw; }
}

function errorMessage(payload, response) {
  if (typeof payload === "string") return payload;
  return payload?.msg ?? payload?.message ?? payload?.error_description ?? payload?.error ?? `${response.status} ${response.statusText}`;
}

function requireProductionTarget(supabaseUrl) {
  let url;
  try { url = new URL(supabaseUrl); } catch { throw new Error("NEXT_PUBLIC_SUPABASE_URL produksi tidak valid."); }
  const hostname = url.hostname.toLowerCase();
  if (url.protocol !== "https:" || !hostname.endsWith(".supabase.co") || hostname.includes("localhost") || hostname === "127.0.0.1" || hostname.includes("replace_me") || hostname.includes("placeholder") || hostname.startsWith("your-project")) {
    throw new Error("Bootstrap produksi hanya menerima URL HTTPS project Supabase Cloud, bukan localhost.");
  }
  return url.toString().replace(/\/$/, "");
}

const args = parseArgs(process.argv.slice(2));
const email = String(args.email ?? "").trim().toLowerCase();
const displayName = String(args.name ?? "Admin").trim();
const password = String(process.env.PRODUCTION_ADMIN_PASSWORD ?? "");
if (!email || !displayName) throw new Error('Gunakan: node scripts/create-production-admin.mjs --email "..." [--name "..."]');
if (password.length < 8) throw new Error("PRODUCTION_ADMIN_PASSWORD harus disediakan melalui environment proses dan minimal 8 karakter.");

const env = await loadEnvFile(path.resolve(process.cwd(), ".env.local"));
if (env.APP_ENV !== "production") throw new Error(".env.local harus menetapkan APP_ENV=production untuk bootstrap produksi.");
const supabaseUrl = requireProductionTarget(String(env.NEXT_PUBLIC_SUPABASE_URL ?? ""));
const secretKey = String(env.SUPABASE_SECRET_KEY ?? "");
if (!secretKey || secretKey.includes("REPLACE_ME")) throw new Error("SUPABASE_SECRET_KEY server-side belum dikonfigurasi.");

const headers = { apikey: secretKey, Authorization: `Bearer ${secretKey}`, "Content-Type": "application/json" };
const listResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users?page=1&per_page=1000`, { headers });
const listPayload = await parseResponse(listResponse);
if (!listResponse.ok) throw new Error(errorMessage(listPayload, listResponse));
let user = listPayload?.users?.find((candidate) => candidate.email?.toLowerCase() === email);
if (!user) {
  const createResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users`, { method: "POST", headers, body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { display_name: displayName } }) });
  const createPayload = await parseResponse(createResponse);
  if (!createResponse.ok) throw new Error(errorMessage(createPayload, createResponse));
  user = createPayload;
} else {
  const updateResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(user.id)}`, { method: "PUT", headers, body: JSON.stringify({ password, email_confirm: true, user_metadata: { ...(user.user_metadata ?? {}), display_name: displayName } }) });
  const updatePayload = await parseResponse(updateResponse);
  if (!updateResponse.ok) throw new Error(errorMessage(updatePayload, updateResponse));
  user = updatePayload?.user ?? updatePayload;
}
if (!user?.id) throw new Error("Bootstrap produksi tidak menghasilkan user Auth yang valid.");
const bootstrapResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/bootstrap_admin`, { method: "POST", headers: { ...headers, "Accept-Profile": "api", "Content-Profile": "api" }, body: JSON.stringify({ p_user_id: user.id, p_email: email, p_display_name: displayName }) });
const bootstrapPayload = await parseResponse(bootstrapResponse);
if (!bootstrapResponse.ok) throw new Error(errorMessage(bootstrapPayload, bootstrapResponse));
console.log(`Admin produksi siap: ${email}`);
console.log(`Organisasi: ${bootstrapPayload.organizationCode}`);
console.log("Password tidak dicetak. Hapus PRODUCTION_ADMIN_PASSWORD dari environment setelah selesai.");