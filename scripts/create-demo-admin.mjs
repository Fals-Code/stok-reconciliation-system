import { readFile } from "node:fs/promises";
import path from "node:path";

function parseArgs(argv) {
  const result = {};

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (!token.startsWith("--")) continue;

    const key = token.slice(2);
    const value = argv[index + 1];

    if (!value || value.startsWith("--")) {
      throw new Error(`Argumen --${key} membutuhkan nilai.`);
    }

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

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    env[key] = value;
  }

  return env;
}

async function parseResponse(response) {
  const raw = await response.text();

  if (!raw) return null;

  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
}

function errorMessage(payload, response) {
  if (typeof payload === "string") return payload;

  return (
    payload?.msg ??
    payload?.message ??
    payload?.error_description ??
    payload?.error ??
    `${response.status} ${response.statusText}`
  );
}

const args = parseArgs(process.argv.slice(2));
const email = String(args.email ?? "").trim().toLowerCase();
const password = String(args.password ?? "");
const displayName = String(args.name ?? "Demo Admin").trim();

if (!email || !password) {
  throw new Error(
    'Gunakan: node scripts/create-demo-admin.mjs --email "..." --password "..." [--name "..."]',
  );
}

if (password.length < 8) {
  throw new Error("Password demo minimal 8 karakter.");
}

const envPath = path.resolve(process.cwd(), ".env.local");
const env = await loadEnvFile(envPath);
const supabaseUrl = String(
  env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321",
).replace(/\/$/, "");
const serviceKey = env.SUPABASE_SECRET_KEY;

if (!serviceKey || serviceKey.includes("REPLACE_ME")) {
  throw new Error("SUPABASE_SECRET_KEY belum dikonfigurasi di .env.local.");
}

const adminHeaders = {
  apikey: serviceKey,
  Authorization: `Bearer ${serviceKey}`,
  "Content-Type": "application/json",
};

const listResponse = await fetch(
  `${supabaseUrl}/auth/v1/admin/users?page=1&per_page=1000`,
  { headers: adminHeaders },
);
const listPayload = await parseResponse(listResponse);

if (!listResponse.ok) {
  throw new Error(errorMessage(listPayload, listResponse));
}

let user = listPayload?.users?.find(
  (candidate) => candidate.email?.toLowerCase() === email,
);

if (!user) {
  const createResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users`, {
    method: "POST",
    headers: adminHeaders,
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: displayName },
    }),
  });
  const createPayload = await parseResponse(createResponse);

  if (!createResponse.ok) {
    throw new Error(errorMessage(createPayload, createResponse));
  }

  user = createPayload;
} else {
  const updateResponse = await fetch(
    `${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(user.id)}`,
    {
      method: "PUT",
      headers: adminHeaders,
      body: JSON.stringify({
        password,
        email_confirm: true,
        user_metadata: {
          ...(user.user_metadata ?? {}),
          display_name: displayName,
        },
      }),
    },
  );
  const updatePayload = await parseResponse(updateResponse);

  if (!updateResponse.ok) {
    throw new Error(errorMessage(updatePayload, updateResponse));
  }

  user = updatePayload?.user ?? updatePayload;
}

if (!user?.id) {
  throw new Error("Demo Admin tidak menghasilkan user Auth yang valid.");
}

const bootstrapResponse = await fetch(
  `${supabaseUrl}/rest/v1/rpc/bootstrap_demo_admin`,
  {
    method: "POST",
    headers: {
      ...adminHeaders,
      "Accept-Profile": "api",
      "Content-Profile": "api",
    },
    body: JSON.stringify({
      p_user_id: user.id,
      p_email: email,
      p_display_name: displayName,
    }),
  },
);
const bootstrapPayload = await parseResponse(bootstrapResponse);

if (!bootstrapResponse.ok) {
  throw new Error(errorMessage(bootstrapPayload, bootstrapResponse));
}

console.log(`Demo Admin siap: ${email}`);
console.log(`User ID: ${user.id}`);
console.log(`Organization ID: ${bootstrapPayload.organizationId}`);
console.log("Password tidak dicetak. Simpan hanya untuk pengujian lokal.");
