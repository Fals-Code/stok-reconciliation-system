import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const DEFAULTS = {
  baseUrl: "http://127.0.0.1:3000",
  email: "demo.admin@glowlab.invalid",
  password: "LocalSmoke123!",
  displayName: "Demo Admin",
  startupTimeoutSeconds: 90,
  keepServerRunning: false,
  allowRemote: false,
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH_PATTERN = /^[0-9a-f]{64}$/i;
const FIXTURE_PREFIX = "entry-correction-ui-smoke:";

const results = [];

let exitCode = 0;
let ownedServer = null;
let serverStdout = "";
let serverStderr = "";
let dbContainer = null;
let supabaseUrl = null;
let publishableKey = null;
let serviceKey = null;
let accessToken = null;
let smokeUserId = null;
let organizationId = null;

function parseArgs(argv) {
  const args = { ...DEFAULTS };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (token === "--keep-server-running") {
      args.keepServerRunning = true;
      continue;
    }

    if (token === "--allow-remote") {
      args.allowRemote = true;
      continue;
    }

    if (!token.startsWith("--")) {
      throw new Error(`Argumen tidak dikenal: ${token}`);
    }

    const key = token.slice(2);
    const value = argv[index + 1];

    if (!value || value.startsWith("--")) {
      throw new Error(`Argumen --${key} membutuhkan nilai.`);
    }

    const mapping = {
      "base-url": "baseUrl",
      email: "email",
      password: "password",
      name: "displayName",
      "startup-timeout-seconds": "startupTimeoutSeconds",
    };

    const target = mapping[key];

    if (!target) {
      throw new Error(`Argumen tidak dikenal: --${key}`);
    }

    args[target] =
      target === "startupTimeoutSeconds" ? Number(value) : value;
    index += 1;
  }

  if (
    !Number.isInteger(args.startupTimeoutSeconds) ||
    args.startupTimeoutSeconds < 10 ||
    args.startupTimeoutSeconds > 300
  ) {
    throw new Error(
      "--startup-timeout-seconds harus bilangan bulat 10-300.",
    );
  }

  return args;
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

function addResult(name, passed, detail = "") {
  results.push({
    status: passed ? "PASS" : "FAIL",
    test: name,
    detail,
  });

  const prefix = passed
    ? "\x1b[32m[PASS]\x1b[0m"
    : "\x1b[31m[FAIL]\x1b[0m";

  console.log(`${prefix} ${name}`);

  if (!passed && detail) {
    console.log(`       ${detail}`);
  }

  if (!passed) {
    exitCode = 1;
  }
}

function assertTest(condition, name, detail = "") {
  addResult(name, Boolean(condition), detail);

  if (!condition) {
    throw new Error(`Assertion gagal: ${name}`);
  }
}

function isLoopback(hostname) {
  return ["127.0.0.1", "localhost", "::1"].includes(hostname);
}

function quoteWindowsCommandArgument(value) {
  const normalized = String(value);

  if (!/[ \t"&|<>^()%!]/.test(normalized)) {
    return normalized;
  }

  return `"${normalized.replace(/"/g, '""')}"`;
}

function runCommand(command, args, options = {}) {
  const isWindowsBatch =
    process.platform === "win32" &&
    /\.(cmd|bat)$/i.test(command);

  const executable = isWindowsBatch
    ? process.env.ComSpec || "cmd.exe"
    : command;
  const executableArgs = isWindowsBatch
    ? [
        "/d",
        "/s",
        "/c",
        [command, ...args]
          .map(quoteWindowsCommandArgument)
          .join(" "),
      ]
    : args;

  const result = spawnSync(executable, executableArgs, {
    cwd: process.cwd(),
    encoding: "utf8",
    input: options.input,
    shell: false,
    windowsHide: true,
    maxBuffer: 20 * 1024 * 1024,
  });

  if (options.printStdout && result.stdout) {
    process.stdout.write(result.stdout);
  }

  if (options.printStderr && result.stderr) {
    process.stderr.write(result.stderr);
  }

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    const output = [result.stdout, result.stderr]
      .filter(Boolean)
      .join("\n");

    throw new Error(
      `${command} gagal dengan exit code ${result.status}.\n${output}`,
    );
  }

  return result.stdout ?? "";
}

function resolveDbContainer() {
  const output = runCommand(
    "docker",
    ["ps", "--format", "{{.Names}}"],
  );

  const container = output
    .split(/\r?\n/)
    .map((value) => value.trim())
    .find((value) => value.startsWith("supabase_db_"));

  if (!container) {
    throw new Error(
      "Container database Supabase lokal tidak ditemukan.",
    );
  }

  return container;
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runSql(sql, { tuplesOnly = false } = {}) {
  if (!dbContainer) {
    throw new Error("Container database belum di-resolve.");
  }

  const args = [
    "exec",
    "-i",
    dbContainer,
    "psql",
    "-U",
    "postgres",
    "-d",
    "postgres",
    "-v",
    "ON_ERROR_STOP=1",
  ];

  if (tuplesOnly) {
    args.push("-t", "-A", "-q");
  }

  return runCommand("docker", args, { input: sql });
}

function runSqlJson(sql) {
  const output = runSql(sql, { tuplesOnly: true });
  const jsonLine = output
    .split(/\r?\n/)
    .map((value) => value.trim())
    .findLast(
      (value) =>
        value.startsWith("{") || value.startsWith("["),
    );

  if (!jsonLine) {
    throw new Error(
      `Query tidak mengembalikan JSON.\n${output.slice(-2000)}`,
    );
  }

  return JSON.parse(jsonLine);
}

function setSmokeProfileActive(userId) {
  const output = runSql(
    `
update app.user_profiles
set is_active = true
where user_id = ${sqlLiteral(userId)}::uuid
returning organization_id::text;
`,
    { tuplesOnly: true },
  );

  const resolvedOrganizationId = output
    .split(/\r?\n/)
    .map((value) => value.trim())
    .find((value) => UUID_PATTERN.test(value));

  if (!resolvedOrganizationId) {
    throw new Error("Profil Admin smoke gagal diaktifkan.");
  }

  organizationId = resolvedOrganizationId;
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

function apiHeaders() {
  return {
    apikey: publishableKey,
    Authorization: `Bearer ${accessToken}`,
    "Accept-Profile": "api",
    "Content-Profile": "api",
    "Content-Type": "application/json",
  };
}

async function rpc(name, body) {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/${name}`,
    {
      method: "POST",
      headers: apiHeaders(),
      body: JSON.stringify(body),
      cache: "no-store",
    },
  );
  const payload = await parseResponse(response);

  if (!response.ok) {
    throw new Error(
      `RPC ${name} gagal (${response.status}): ` +
        JSON.stringify(payload),
    );
  }

  return payload;
}

async function restRows(resourcePath) {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/${resourcePath}`,
    {
      method: "GET",
      headers: apiHeaders(),
      cache: "no-store",
    },
  );
  const payload = await parseResponse(response);

  if (!response.ok) {
    throw new Error(
      `REST ${resourcePath} gagal (${response.status}): ` +
        JSON.stringify(payload),
    );
  }

  return Array.isArray(payload) ? payload : [];
}

function cookieHeader() {
  return `glowlab_access_token=${accessToken}`;
}

async function getPage(uri) {
  const response = await fetch(uri, {
    method: "GET",
    headers: {
      Cookie: cookieHeader(),
    },
    redirect: "manual",
    cache: "no-store",
  });
  const html = await response.text();

  if (!response.ok) {
    throw new Error(
      `GET ${uri} gagal (${response.status}): ` +
        html.slice(0, 3000),
    );
  }

  return {
    uri: response.url || uri,
    html,
    statusCode: response.status,
  };
}

async function getUnauthenticated(uri) {
  const response = await fetch(uri, {
    method: "GET",
    redirect: "manual",
    cache: "no-store",
  });

  return {
    statusCode: response.status,
    location: response.headers.get("location"),
    body: await response.text(),
  };
}

function decodeHtml(value) {
  return String(value)
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#x27;|&#39;/gi, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) =>
      String.fromCodePoint(Number.parseInt(hex, 16)),
    )
    .replace(/&#([0-9]+);/g, (_, decimal) =>
      String.fromCodePoint(Number.parseInt(decimal, 10)),
    );
}

function normalizeRenderedText(value) {
  return decodeHtml(
    String(value)
      .replace(/<!--[\s\S]*?-->/g, "")
      .replace(/<[^>]+>/g, " "),
  )
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function containsText(html, text) {
  return normalizeRenderedText(html).includes(
    normalizeRenderedText(text),
  );
}

function findForm(html, marker) {
  const forms = html.match(/<form\b[^>]*>.*?<\/form>/gis) ?? [];
  const normalizedMarker = normalizeRenderedText(marker);

  const form = forms.find((candidate) =>
    normalizeRenderedText(candidate).includes(normalizedMarker),
  );

  if (!form) {
    throw new Error(
      `Form dengan marker "${marker}" tidak ditemukan.`,
    );
  }

  return form;
}

function findServerActionName(formHtml) {
  const match = formHtml.match(/name="(\$ACTION_ID_[^"]+)"/i);

  if (!match) {
    throw new Error("Nama Server Action tidak ditemukan.");
  }

  return match[1];
}

function parseAttributes(tag) {
  const attributes = {};
  const pattern = /([:$\w-]+)="([^"]*)"/g;

  for (const match of tag.matchAll(pattern)) {
    attributes[match[1]] = decodeHtml(match[2]);
  }

  return attributes;
}

function findInputValue(formHtml, name) {
  const tags = formHtml.match(/<input\b[^>]*>/gi) ?? [];

  for (const tag of tags) {
    const attributes = parseAttributes(tag);

    if (attributes.name === name) {
      return attributes.value ?? "";
    }
  }

  throw new Error(`Input "${name}" tidak ditemukan pada form.`);
}

async function invokeServerActionForm({
  pageUri,
  pageHtml,
  marker,
  fields,
  baseUrl,
}) {
  const formHtml = findForm(pageHtml, marker);
  const actionName = findServerActionName(formHtml);
  const form = new FormData();

  form.append(actionName, "");

  for (const [key, value] of Object.entries(fields)) {
    form.append(key, value == null ? "" : String(value));
  }

  const origin = new URL(baseUrl).origin;
  const response = await fetch(pageUri, {
    method: "POST",
    headers: {
      Cookie: cookieHeader(),
      Origin: origin,
      Referer: pageUri,
    },
    body: form,
    redirect: "manual",
  });
  const body = await response.text();

  if (![302, 303, 307, 308].includes(response.status)) {
    throw new Error(
      `Server Action "${marker}" tidak redirect. ` +
        `Status=${response.status} Body=${body.slice(0, 3000)}`,
    );
  }

  const location = response.headers.get("location");

  if (!location) {
    throw new Error(
      `Server Action "${marker}" tidak mengembalikan Location.`,
    );
  }

  const redirectUri = new URL(location, pageUri).toString();
  return getPage(redirectUri);
}

async function isServerReady(baseUrl) {
  try {
    const response = await fetch(`${baseUrl}/login`, {
      redirect: "manual",
      cache: "no-store",
    });

    return response.status === 200;
  } catch {
    return false;
  }
}

async function waitForServer(baseUrl, timeoutSeconds) {
  const deadline = Date.now() + timeoutSeconds * 1000;

  while (Date.now() < deadline) {
    if (ownedServer?.exitCode != null) {
      throw new Error(
        "Next.js dev server berhenti dengan exit code " +
          `${ownedServer.exitCode}.`,
      );
    }

    if (await isServerReady(baseUrl)) return true;

    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  return false;
}

function startServer(baseUrl) {
  const uri = new URL(baseUrl);
  const nextCliPath = path.resolve(
    process.cwd(),
    "node_modules",
    "next",
    "dist",
    "bin",
    "next",
  );

  ownedServer = spawn(
    process.execPath,
    [
      nextCliPath,
      "dev",
      "--hostname",
      uri.hostname,
      "--port",
      String(uri.port || 3000),
    ],
    {
      cwd: process.cwd(),
      shell: false,
      windowsHide: true,
      detached: process.platform !== "win32",
      stdio: ["ignore", "pipe", "pipe"],
    },
  );

  ownedServer.stdout.on("data", (chunk) => {
    serverStdout = (serverStdout + chunk.toString()).slice(-30000);
  });

  ownedServer.stderr.on("data", (chunk) => {
    serverStderr = (serverStderr + chunk.toString()).slice(-30000);
  });
}

function showServerLogs() {
  if (serverStdout) {
    console.log("\n--- Next.js stdout ---");
    console.log(serverStdout);
  }

  if (serverStderr) {
    console.log("\n--- Next.js stderr ---");
    console.log(serverStderr);
  }
}

function stopOwnedServer(keepServerRunning) {
  if (!ownedServer) return;

  if (keepServerRunning) {
    console.log(
      `Server dibiarkan aktif. PID induk: ${ownedServer.pid}`,
    );
    return;
  }

  if (process.platform === "win32") {
    spawnSync(
      "taskkill",
      ["/PID", String(ownedServer.pid), "/T", "/F"],
      {
        windowsHide: true,
        stdio: "ignore",
      },
    );
  } else {
    try {
      process.kill(-ownedServer.pid, "SIGTERM");
    } catch {
      ownedServer.kill("SIGTERM");
    }
  }
}

function inventorySnapshot(batchRow, productRow) {
  return {
    batchSellable: Number(batchRow.sellable_qty),
    productSellable: Number(productRow.sellable_qty),
    productReserved: Number(productRow.reserved_qty),
  };
}

async function readInventory(batchId, productId) {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  const encodedBatchId = encodeURIComponent(batchId);
  const encodedProductId = encodeURIComponent(productId);

  const [batches, products] = await Promise.all([
    restRows(
      "batch_inventory" +
        `?organization_id=eq.${encodedOrganizationId}` +
        `&batch_id=eq.${encodedBatchId}` +
        "&select=batch_id,product_id,batch_code,expiry_date," +
        "status_code,sellable_qty,quarantine_qty,damaged_qty,last_ledger_seq",
    ),
    restRows(
      "product_inventory" +
        `?organization_id=eq.${encodedOrganizationId}` +
        `&product_id=eq.${encodedProductId}` +
        "&select=product_id,sku,name,sellable_qty,quarantine_qty," +
        "damaged_qty,reserved_qty,available_qty,last_ledger_seq",
    ),
  ]);

  if (!batches[0] || !products[0]) {
    throw new Error("Snapshot inventory tidak ditemukan.");
  }

  return {
    batch: batches[0],
    product: products[0],
    snapshot: inventorySnapshot(batches[0], products[0]),
  };
}

async function selectReceiptBatch() {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  const tomorrow = new Date(Date.now() + 86_400_000)
    .toISOString()
    .slice(0, 10);

  const rows = await restRows(
    "batch_inventory" +
      `?organization_id=eq.${encodedOrganizationId}` +
      "&status_code=eq.ACTIVE" +
      `&expiry_date=gte.${tomorrow}` +
      "&select=batch_id,product_id,sku,product_name,batch_code," +
      "expiry_date,status_code,sellable_qty" +
      "&order=expiry_date.asc,batch_code.asc&limit=1",
  );

  if (!rows[0]) {
    throw new Error(
      "Batch aktif yang belum kedaluwarsa tidak tersedia. " +
        "Jalankan seed/reset lokal yang sesuai sebelum smoke test.",
    );
  }

  return rows[0];
}

async function postReceipt({
  sourceRef,
  idempotencyKey,
  productId,
  batchId,
  quantity,
  runId,
  fixture,
}) {
  return rpc("post_receipt", {
    p_organization_id: organizationId,
    p_idempotency_key: idempotencyKey,
    p_source_ref: sourceRef,
    p_occurred_at: new Date().toISOString(),
    p_lines: [
      {
        productId,
        batchId,
        quantity,
        sourceLineRef: "SMOKE-LINE-1",
      },
    ],
    p_note: `Temporary ${fixture} receipt for Entry Correction smoke.`,
    p_metadata: {
      source: "entry-correction-ui-smoke",
      version: 1,
      runId,
      fixture,
      temporary: true,
    },
  });
}

async function previewReversal(transactionId) {
  return rpc("preview_stock_transaction_reversal", {
    p_organization_id: organizationId,
    p_original_transaction_id: transactionId,
  });
}

async function reverseDirect({
  transactionId,
  previewBasisHash,
  idempotencyKey,
  note,
  runId,
  fixture,
}) {
  return rpc("reverse_stock_transaction", {
    p_organization_id: organizationId,
    p_idempotency_key: idempotencyKey,
    p_original_transaction_id: transactionId,
    p_preview_basis_hash: previewBasisHash,
    p_confirmation: true,
    p_note: note,
    p_metadata: {
      source: "entry-correction-ui-smoke-cleanup",
      version: 1,
      runId,
      fixture,
      temporary: true,
    },
  });
}

async function readApplications(transactionId) {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  const encodedTransactionId = encodeURIComponent(transactionId);

  return restRows(
    "stock_reversal_applications" +
      `?organization_id=eq.${encodedOrganizationId}` +
      `&original_transaction_id=eq.${encodedTransactionId}` +
      "&select=*&order=created_at.asc",
  );
}

async function readLedgerByTransaction(transactionId) {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  const encodedTransactionId = encodeURIComponent(transactionId);

  return restRows(
    "stock_ledger" +
      `?organization_id=eq.${encodedOrganizationId}` +
      `&transaction_id=eq.${encodedTransactionId}` +
      "&select=*&order=line_no.asc,ledger_seq.asc",
  );
}

async function cleanupReceipt({
  transactionId,
  runId,
  fixture,
}) {
  const applications = await readApplications(transactionId);

  if (applications.length > 0) {
    return;
  }

  const preview = await previewReversal(transactionId);

  if (!preview?.eligible) {
    throw new Error(
      `Cleanup ${fixture} diblokir: ${JSON.stringify(
        preview?.blockers ?? [],
      )}`,
    );
  }

  await reverseDirect({
    transactionId,
    previewBasisHash: preview.basisHash,
    idempotencyKey:
      `${FIXTURE_PREFIX}cleanup:${fixture}:${runId}`,
    note: `Cleanup ${fixture} setelah smoke test Koreksi Entri.`,
    runId,
    fixture,
  });
}

async function main(args) {
  const runId = randomUUID();
  const createdReceiptIds = [];

  console.log("== Preflight ==");

  const requiredPaths = [
    ".env.local",
    "package.json",
    "scripts/create-demo-admin.mjs",
    "scripts/test-entry-correction-ui.mjs",
    "src/app/app-shell/navigation.ts",
    "src/app/entry-corrections/actions.ts",
    "src/app/entry-corrections/page.tsx",
    "src/lib/supabase-rest.ts",
    "supabase/migrations/202607180005_general_reversal_foundation.sql",
    "supabase/tests/042_general_reversal_foundation.test.sql",
  ];

  for (const requiredPath of requiredPaths) {
    let exists = true;

    try {
      await readFile(path.resolve(process.cwd(), requiredPath));
    } catch {
      exists = false;
    }

    assertTest(
      exists,
      `File tersedia: ${requiredPath}`,
      "Jalankan script dari root repository.",
    );
  }

  const env = await loadEnvFile(
    path.resolve(process.cwd(), ".env.local"),
  );

  supabaseUrl = String(
    env.NEXT_PUBLIC_SUPABASE_URL ??
      "http://127.0.0.1:54321",
  ).replace(/\/$/, "");

  publishableKey = String(
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "",
  );
  serviceKey = String(env.SUPABASE_SECRET_KEY ?? "");

  const baseUri = new URL(args.baseUrl);
  const supabaseUri = new URL(supabaseUrl);

  if (!args.allowRemote) {
    if (!isLoopback(baseUri.hostname)) {
      throw new Error(
        `BaseUrl nonlokal ditolak: ${args.baseUrl}.`,
      );
    }

    if (!isLoopback(supabaseUri.hostname)) {
      throw new Error(
        `Supabase nonlokal ditolak: ${supabaseUrl}.`,
      );
    }
  }

  if (
    !publishableKey ||
    publishableKey.includes("REPLACE_ME")
  ) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY belum valid di .env.local.",
    );
  }

  if (!serviceKey || serviceKey.includes("REPLACE_ME")) {
    throw new Error(
      "SUPABASE_SECRET_KEY belum valid di .env.local.",
    );
  }

  dbContainer = resolveDbContainer();

  assertTest(
    Boolean(dbContainer),
    "Database Supabase lokal ditemukan",
    dbContainer,
  );

  console.log("\n== Provision dan aktivasi Admin smoke ==");

  const existingAdmin = runSqlJson(`
select jsonb_build_object(
  'found',
    exists (
      select 1
      from app.user_profiles profile
      join auth.users auth_user
        on auth_user.id = profile.user_id
      where profile.organization_id =
            '00000000-0000-4000-8000-000000000001'::uuid
        and profile.employee_code = 'DEMO-ADMIN'
        and profile.role_code = 'ADMIN'
    ),
  'userId',
    (
      select profile.user_id
      from app.user_profiles profile
      join auth.users auth_user
        on auth_user.id = profile.user_id
      where profile.organization_id =
            '00000000-0000-4000-8000-000000000001'::uuid
        and profile.employee_code = 'DEMO-ADMIN'
        and profile.role_code = 'ADMIN'
      order by profile.is_active desc, profile.created_at asc
      limit 1
    ),
  'email',
    (
      select lower(auth_user.email)
      from app.user_profiles profile
      join auth.users auth_user
        on auth_user.id = profile.user_id
      where profile.organization_id =
            '00000000-0000-4000-8000-000000000001'::uuid
        and profile.employee_code = 'DEMO-ADMIN'
        and profile.role_code = 'ADMIN'
      order by profile.is_active desc, profile.created_at asc
      limit 1
    )
);
`);

  assertTest(
    existingAdmin?.found === true &&
      UUID_PATTERN.test(existingAdmin?.userId ?? "") &&
      typeof existingAdmin?.email === "string",
    "Admin demo existing ditemukan",
    JSON.stringify(existingAdmin),
  );

  if (
    args.email.trim().toLowerCase() !==
    existingAdmin.email.trim().toLowerCase()
  ) {
    throw new Error(
      `Smoke test lokal harus memakai Admin demo existing: ` +
        `${existingAdmin.email}.`,
    );
  }

  const adminHeaders = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
  const passwordUpdateResponse = await fetch(
    `${supabaseUrl}/auth/v1/admin/users/${existingAdmin.userId}`,
    {
      method: "PUT",
      headers: adminHeaders,
      body: JSON.stringify({
        password: args.password,
        email_confirm: true,
        user_metadata: {
          display_name: args.displayName,
        },
      }),
    },
  );
  const passwordUpdatePayload = await parseResponse(
    passwordUpdateResponse,
  );

  assertTest(
    passwordUpdateResponse.ok,
    "Password Admin demo disiapkan untuk smoke lokal",
    JSON.stringify(passwordUpdatePayload),
  );

  const tokenResponse = await fetch(
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        apikey: publishableKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: args.email.trim().toLowerCase(),
        password: args.password,
      }),
    },
  );
  const tokenPayload = await parseResponse(tokenResponse);

  if (!tokenResponse.ok) {
    throw new Error(
      `Password grant gagal: ${JSON.stringify(tokenPayload)}`,
    );
  }

  accessToken = String(tokenPayload?.access_token ?? "");
  smokeUserId = String(tokenPayload?.user?.id ?? "");

  assertTest(
    Boolean(accessToken),
    "Password grant menghasilkan access token",
  );
  assertTest(
    UUID_PATTERN.test(smokeUserId),
    "Auth user smoke memiliki UUID",
  );

  setSmokeProfileActive(smokeUserId);

  assertTest(
    UUID_PATTERN.test(organizationId),
    "Profil smoke aktif pada satu organisasi",
    organizationId,
  );

  const profileRows = await restRows(
    "current_admin_profile?select=*",
  );
  const profile = profileRows[0];

  assertTest(
    profile?.role_code === "ADMIN" &&
      profile?.organization_id === organizationId,
    "Token memiliki profil Admin aktif",
  );

  console.log("\n== Start / reuse Next.js server ==");

  let serverReady = await isServerReady(args.baseUrl);

  if (!serverReady) {
    startServer(args.baseUrl);
    serverReady = await waitForServer(
      args.baseUrl,
      args.startupTimeoutSeconds,
    );
  }

  assertTest(serverReady, "Next.js server siap");

  const entryCorrectionUrl =
    `${args.baseUrl}/entry-corrections`;
  const unauthenticated = await getUnauthenticated(
    entryCorrectionUrl,
  );

  assertTest(
    [302, 303, 307, 308].includes(
      unauthenticated.statusCode,
    ) &&
      String(unauthenticated.location ?? "").includes("/login"),
    "Halaman Koreksi Entri menolak sesi anonim",
    `Status=${unauthenticated.statusCode} ` +
      `Location=${unauthenticated.location ?? ""}`,
  );

  const batch = await selectReceiptBatch();
  const baseline = await readInventory(
    batch.batch_id,
    batch.product_id,
  );

  assertTest(
    batch.status_code === "ACTIVE",
    "Fixture memakai batch aktif",
    `${batch.batch_code} exp ${batch.expiry_date}`,
  );

  try {
    console.log("\n== Preview dan reversal sukses melalui UI ==");

    const sourceRef =
      `${FIXTURE_PREFIX}success:${runId}`;
    const posted = await postReceipt({
      sourceRef,
      idempotencyKey:
        `${FIXTURE_PREFIX}post:success:${runId}`,
      productId: batch.product_id,
      batchId: batch.batch_id,
      quantity: 3,
      runId,
      fixture: "success",
    });

    assertTest(
      UUID_PATTERN.test(posted?.transactionId),
      "Fixture receipt sukses memiliki transaction ID",
      JSON.stringify(posted),
    );

    createdReceiptIds.push({
      transactionId: posted.transactionId,
      fixture: "success",
    });

    const afterPost = await readInventory(
      batch.batch_id,
      batch.product_id,
    );

    assertTest(
      afterPost.snapshot.batchSellable ===
        baseline.snapshot.batchSellable + 3 &&
        afterPost.snapshot.productSellable ===
          baseline.snapshot.productSellable + 3,
      "Fixture receipt menambah projection tepat satu kali",
      JSON.stringify({
        baseline: baseline.snapshot,
        afterPost: afterPost.snapshot,
      }),
    );

    const directPreview = await previewReversal(
      posted.transactionId,
    );

    assertTest(
      directPreview?.eligible === true &&
        directPreview?.status === "PREVIEW_READY" &&
        directPreview?.lineCount === 1 &&
        directPreview?.totalAbsoluteQuantity === 3 &&
        HASH_PATTERN.test(directPreview?.basisHash ?? ""),
      "RPC preview menghasilkan basis eligible yang lengkap",
      JSON.stringify(directPreview),
    );

    const afterDirectPreview = await readInventory(
      batch.batch_id,
      batch.product_id,
    );

    assertTest(
      JSON.stringify(afterDirectPreview.snapshot) ===
        JSON.stringify(afterPost.snapshot),
      "Preview RPC tidak mengubah projection stok",
    );

    let page = await getPage(
      `${entryCorrectionUrl}` +
        `?q=${encodeURIComponent(sourceRef)}` +
        "&type=RECEIPT" +
        `&transactionId=${posted.transactionId}` +
        "#detail",
    );

    assertTest(
      containsText(page.html, "Koreksi Entri") &&
        containsText(page.html, "Preview dampak authoritative") &&
        containsText(page.html, posted.receiptNo) &&
        containsText(page.html, sourceRef),
      "Worklist, filter, drill-down, dan preview dirender",
    );

    assertTest(
      containsText(page.html, "Posting Koreksi Entri") &&
        containsText(page.html, "Alasan koreksi") &&
        containsText(
          page.html,
          "Saya sudah meninjau dampak",
        ),
      "Form alasan dan konfirmasi final dirender",
    );

    const successForm = findForm(
      page.html,
      "Posting Koreksi Entri",
    );
    const previewBasisHash = findInputValue(
      successForm,
      "previewBasisHash",
    );
    const idempotencyKey = findInputValue(
      successForm,
      "idempotencyKey",
    );

    assertTest(
      previewBasisHash === directPreview.basisHash &&
        HASH_PATTERN.test(previewBasisHash),
      "UI memakai basis hash preview database",
    );
    assertTest(
      idempotencyKey.startsWith(
        `entry-correction:${posted.transactionId}:`,
      ),
      "UI menghasilkan idempotency key per konfirmasi",
      idempotencyKey,
    );

    const correctionNote =
      `Koreksi receipt smoke ${runId}.`;
    const formFields = {
      originalTransactionId: posted.transactionId,
      previewBasisHash,
      idempotencyKey,
      returnTo:
        `/entry-corrections?q=${encodeURIComponent(sourceRef)}` +
        `&type=RECEIPT&transactionId=${posted.transactionId}` +
        "#detail",
      note: correctionNote,
      confirmation: "on",
    };

    page = await invokeServerActionForm({
      pageUri: page.uri,
      pageHtml: page.html,
      marker: "Posting Koreksi Entri",
      fields: formFields,
      baseUrl: args.baseUrl,
    });

    assertTest(
      containsText(page.html, "berhasil membalik") &&
        containsText(page.html, "Buka transaksi asal") &&
        containsText(page.html, "Buka transaksi pembalik"),
      "Server Action memberi feedback sukses dan linkage",
    );

    const applications = await readApplications(
      posted.transactionId,
    );

    assertTest(
      applications.length === 1,
      "Commit membuat satu reversal application",
      JSON.stringify(applications),
    );

    const application = applications[0];
    const reversalLedger = await readLedgerByTransaction(
      application.reversal_transaction_id,
    );

    assertTest(
      reversalLedger.length === 1 &&
        Number(reversalLedger[0].quantity_delta) === -3 &&
        reversalLedger[0].batch_id === batch.batch_id &&
        reversalLedger[0].product_id === batch.product_id,
      "Ledger pembalik adalah delta tepat berlawanan pada batch asal",
      JSON.stringify(reversalLedger),
    );

    const afterReversal = await readInventory(
      batch.batch_id,
      batch.product_id,
    );

    assertTest(
      JSON.stringify(afterReversal.snapshot) ===
        JSON.stringify(baseline.snapshot),
      "Reversal UI mengembalikan projection ke baseline",
      JSON.stringify({
        baseline: baseline.snapshot,
        afterReversal: afterReversal.snapshot,
      }),
    );

    const originalLedger = await readLedgerByTransaction(
      posted.transactionId,
    );

    assertTest(
      originalLedger.length === 1 &&
        originalLedger[0].transaction_type_code === "RECEIPT" &&
        Number(originalLedger[0].quantity_delta) === 3,
      "Transaksi dan ledger asal tetap immutable",
    );

    const persistedPage = await getPage(page.uri);

    assertTest(
      containsText(persistedPage.html, "berhasil membalik") &&
        containsText(persistedPage.html, application.reversal_transaction_no),
      "Feedback dan linkage bertahan setelah refresh",
    );

    const originalDetail = await getPage(
      `${entryCorrectionUrl}` +
        `?transactionId=${posted.transactionId}#detail`,
    );
    const reversalDetail = await getPage(
      `${entryCorrectionUrl}` +
        `?transactionId=${application.reversal_transaction_id}` +
        "#detail",
    );

    assertTest(
      containsText(originalDetail.html, "Hubungan reversal") &&
        containsText(
          originalDetail.html,
          application.reversal_transaction_no,
        ),
      "Detail transaksi asal menampilkan transaksi pembalik",
    );
    assertTest(
      containsText(reversalDetail.html, "Transaksi pembalik") &&
        containsText(
          reversalDetail.html,
          application.original_transaction_no,
        ),
      "Detail reversal menampilkan transaksi asal",
    );

    const replayPage = await invokeServerActionForm({
      pageUri:
        `${entryCorrectionUrl}` +
        `?transactionId=${posted.transactionId}#detail`,
      pageHtml: originalDetail.html,
      marker: "Posting Koreksi Entri",
      fields: formFields,
      baseUrl: args.baseUrl,
    }).catch(async () => {
      return invokeServerActionForm({
        pageUri:
          `${entryCorrectionUrl}` +
          `?q=${encodeURIComponent(sourceRef)}` +
          `&type=RECEIPT&transactionId=${posted.transactionId}` +
          "#detail",
        pageHtml: successForm,
        marker: "Posting Koreksi Entri",
        fields: formFields,
        baseUrl: args.baseUrl,
      });
    });

    assertTest(
      containsText(replayPage.html, "berhasil membalik"),
      "Replay command identik mengembalikan hasil sukses",
    );

    const applicationsAfterReplay =
      await readApplications(posted.transactionId);
    const reversalCount = runSqlJson(`
select jsonb_build_object(
  'count',
  count(*)
)
from inventory.stock_transactions transaction
where transaction.organization_id =
      ${sqlLiteral(organizationId)}::uuid
  and transaction.reversal_of_transaction_id =
      ${sqlLiteral(posted.transactionId)}::uuid;
`);

    assertTest(
      applicationsAfterReplay.length === 1 &&
        Number(reversalCount.count) === 1,
      "Replay idempotent tidak menggandakan domain effect",
      JSON.stringify({
        applicationCount: applicationsAfterReplay.length,
        reversalTransactionCount: reversalCount.count,
      }),
    );

    console.log("\n== Failure path dan stale preview ==");

    const staleSourceRef =
      `${FIXTURE_PREFIX}stale:${runId}`;
    const staleReceipt = await postReceipt({
      sourceRef: staleSourceRef,
      idempotencyKey:
        `${FIXTURE_PREFIX}post:stale:${runId}`,
      productId: batch.product_id,
      batchId: batch.batch_id,
      quantity: 2,
      runId,
      fixture: "stale",
    });

    createdReceiptIds.push({
      transactionId: staleReceipt.transactionId,
      fixture: "stale",
    });

    let stalePage = await getPage(
      `${entryCorrectionUrl}` +
        `?q=${encodeURIComponent(staleSourceRef)}` +
        `&type=RECEIPT` +
        `&transactionId=${staleReceipt.transactionId}` +
        "#detail",
    );
    const staleForm = findForm(
      stalePage.html,
      "Posting Koreksi Entri",
    );
    const staleFields = {
      originalTransactionId: staleReceipt.transactionId,
      previewBasisHash: findInputValue(
        staleForm,
        "previewBasisHash",
      ),
      idempotencyKey: findInputValue(
        staleForm,
        "idempotencyKey",
      ),
      returnTo:
        `/entry-corrections?q=${encodeURIComponent(staleSourceRef)}` +
        `&type=RECEIPT&transactionId=${staleReceipt.transactionId}` +
        "#detail",
      note: `Stale preview smoke ${runId}.`,
    };

    const missingConfirmationPage =
      await invokeServerActionForm({
        pageUri: stalePage.uri,
        pageHtml: stalePage.html,
        marker: "Posting Koreksi Entri",
        fields: staleFields,
        baseUrl: args.baseUrl,
      });

    assertTest(
      containsText(
        missingConfirmationPage.html,
        "Konfirmasi final wajib dicentang",
      ),
      "Server Action menolak commit tanpa konfirmasi final",
    );
    assertTest(
      (await readApplications(staleReceipt.transactionId))
        .length === 0,
      "Failure konfirmasi tidak menulis reversal",
    );

    const interferenceReceipt = await postReceipt({
      sourceRef:
        `${FIXTURE_PREFIX}interference:${runId}`,
      idempotencyKey:
        `${FIXTURE_PREFIX}post:interference:${runId}`,
      productId: batch.product_id,
      batchId: batch.batch_id,
      quantity: 1,
      runId,
      fixture: "interference",
    });

    createdReceiptIds.push({
      transactionId: interferenceReceipt.transactionId,
      fixture: "interference",
    });

    stalePage = await invokeServerActionForm({
      pageUri:
        `${entryCorrectionUrl}` +
        `?transactionId=${staleReceipt.transactionId}` +
        "#detail",
      pageHtml: stalePage.html,
      marker: "Posting Koreksi Entri",
      fields: {
        ...staleFields,
        confirmation: "on",
      },
      baseUrl: args.baseUrl,
    });

    assertTest(
      containsText(
        stalePage.html,
        "Posisi stok berubah setelah preview dibuat",
      ),
      "Stale preview ditolak dengan feedback operasional",
    );
    assertTest(
      (await readApplications(staleReceipt.transactionId))
        .length === 0,
      "Stale preview tidak membuat ledger reversal",
    );

    const runtimeLog = `${serverStdout}\n${serverStderr}`;

    assertTest(
      !/Unhandled Runtime Error|ReferenceError:|TypeError: Cannot/i.test(
        runtimeLog,
      ),
      "Tidak ada unhandled runtime error selama smoke test",
      runtimeLog.slice(-3000),
    );
  } finally {
    console.log("\n== Pemulihan stok fixture ==");

    for (const fixture of createdReceiptIds) {
      try {
        await cleanupReceipt({
          transactionId: fixture.transactionId,
          runId,
          fixture: fixture.fixture,
        });
        addResult(
          `Projection fixture dipulihkan: ${fixture.fixture}`,
          true,
        );
      } catch (error) {
        addResult(
          `Projection fixture dipulihkan: ${fixture.fixture}`,
          false,
          error instanceof Error
            ? error.message
            : String(error),
        );
      }
    }

    const finalInventory = await readInventory(
      batch.batch_id,
      batch.product_id,
    );

    assertTest(
      JSON.stringify(finalInventory.snapshot) ===
        JSON.stringify(baseline.snapshot),
      "Projection akhir kembali ke baseline",
      JSON.stringify({
        baseline: baseline.snapshot,
        final: finalInventory.snapshot,
      }),
    );
  }
}

const args = parseArgs(process.argv.slice(2));

try {
  await main(args);
} catch (error) {
  exitCode = 1;
  const detail =
    error instanceof Error ? error.stack ?? error.message : String(error);

  if (!results.some((result) => result.status === "FAIL")) {
    addResult("Smoke test selesai tanpa exception", false, detail);
  }

  console.error("\nSmoke test gagal:", detail);
  showServerLogs();
} finally {
  stopOwnedServer(args.keepServerRunning);

  console.log("\n== Ringkasan ==");
  console.table(results);

  const passed = results.filter(
    (result) => result.status === "PASS",
  ).length;
  const failed = results.filter(
    (result) => result.status === "FAIL",
  ).length;

  console.log(
    `Result: ${failed === 0 ? "PASS" : "FAIL"} ` +
      `(${passed} passed, ${failed} failed)`,
  );

  process.exitCode = exitCode;
}
