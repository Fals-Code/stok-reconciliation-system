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
const FIXTURE_PREFIX = "stock-disposal-ui-smoke:";

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
    process.platform === "win32" && /\.(cmd|bat)$/i.test(command);
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
      (value) => value.startsWith("{") || value.startsWith("["),
    );

  if (!jsonLine) {
    throw new Error(
      `Query tidak mengembalikan JSON.\n${output.slice(-2000)}`,
    );
  }

  return JSON.parse(jsonLine);
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

  return getPage(new URL(location, pageUri).toString());
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
    serverStdout = (serverStdout + chunk.toString()).slice(-50000);
  });

  ownedServer.stderr.on("data", (chunk) => {
    serverStderr = (serverStderr + chunk.toString()).slice(-50000);
  });
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

function jakartaDateTimeLocal() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date());
  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );

  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

function occurredAtFromDraft(draft) {
  return `${draft.occurredAt}:00+07:00`;
}

function historicalReceiptOccurredAt(expiryDate) {
  const expiryAtNoonJakarta = Date.parse(
    `${expiryDate}T12:00:00+07:00`,
  );

  if (Number.isNaN(expiryAtNoonJakarta)) {
    throw new Error(`Tanggal kedaluwarsa fixture tidak valid: ${expiryDate}`);
  }

  return new Date(
    expiryAtNoonJakarta - 24 * 60 * 60 * 1000,
  ).toISOString();
}

function readLedgerWatermark() {
  return runSqlJson(`
select jsonb_build_object(
  'entryCount',
  count(*),
  'maxLedgerSeq',
  coalesce(max(ledger_seq), 0)
)
from inventory.stock_ledger_entries
where organization_id = ${sqlLiteral(organizationId)}::uuid;
`);
}

async function readInventory(productId, batchId) {
  const org = encodeURIComponent(organizationId);
  const product = encodeURIComponent(productId);
  const batch = encodeURIComponent(batchId);
  const products = await restRows(
    `product_inventory?organization_id=eq.${org}` +
      `&product_id=eq.${product}` +
      "&select=product_id,sellable_qty,quarantine_qty,damaged_qty,reserved_qty,available_qty,last_ledger_seq",
  );
  const batches = await restRows(
    `batch_inventory?organization_id=eq.${org}` +
      `&batch_id=eq.${batch}` +
      "&select=batch_id,batch_code,expiry_date,status_code,sellable_qty,quarantine_qty,damaged_qty,last_ledger_seq",
  );

  if (!products[0] || !batches[0]) {
    throw new Error("Projection fixture tidak ditemukan.");
  }

  return {
    product: products[0],
    batch: batches[0],
  };
}

async function createExpiredBatch(runId) {
  return runSqlJson(`
with selected_product as (
  select product.id, product.sku, product.name
  from catalog.products product
  where product.organization_id = ${sqlLiteral(organizationId)}::uuid
    and product.is_active
  order by product.id
  limit 1
),
inserted as (
  insert into catalog.product_batches (
    id,
    organization_id,
    product_id,
    batch_code,
    manufactured_date,
    expiry_date,
    received_first_at,
    status_code,
    block_reason,
    created_by,
    batch_kind_code
  )
  select
    gen_random_uuid(),
    ${sqlLiteral(organizationId)}::uuid,
    selected_product.id,
    'DSP-SMOKE-' || upper(substr(replace(${sqlLiteral(runId)}, '-', ''), 1, 10)),
    (
      (clock_timestamp() at time zone 'Asia/Jakarta')::date
      - interval '60 days'
    )::date,
    (
      (clock_timestamp() at time zone 'Asia/Jakarta')::date
      - interval '2 days'
    )::date,
    clock_timestamp(),
    'ACTIVE',
    null,
    ${sqlLiteral(smokeUserId)}::uuid,
    'STANDARD'
  from selected_product
  returning id, product_id, batch_code, expiry_date
)
select jsonb_build_object(
  'batchId', inserted.id,
  'productId', inserted.product_id,
  'batchCode', inserted.batch_code,
  'expiryDate', inserted.expiry_date,
  'productSku', selected_product.sku,
  'productName', selected_product.name
)
from inserted
join selected_product
  on selected_product.id = inserted.product_id;
`);
}

async function postReceipt({
  sourceRef,
  idempotencyKey,
  productId,
  batchId,
  quantity,
  runId,
  occurredAt,
}) {
  return rpc("post_receipt", {
    p_organization_id: organizationId,
    p_idempotency_key: idempotencyKey,
    p_source_ref: sourceRef,
    p_occurred_at: occurredAt,
    p_lines: [
      {
        productId,
        batchId,
        quantity,
        sourceLineRef: "SMOKE-RECEIPT-1",
      },
    ],
    p_note: "Temporary expired-batch receipt for disposal UI smoke.",
    p_metadata: {
      source: "stock-disposal-ui-smoke",
      version: 1,
      runId,
      temporary: true,
    },
  });
}

async function previewDisposal(draft) {
  return rpc("preview_stock_disposal", {
    p_organization_id: organizationId,
    p_source_ref: draft.sourceRef,
    p_occurred_at: occurredAtFromDraft(draft),
    p_reason_code: draft.reasonCode,
    p_lines: draft.lines,
    p_reference_text: draft.referenceText,
    p_note: draft.note,
    p_metadata: {
      source: "stock-disposal-admin-ui",
      version: 1,
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
  idempotencyKey,
  note,
  runId,
  fixture,
}) {
  const preview = await previewReversal(transactionId);

  if (!preview?.eligible || !HASH_PATTERN.test(preview?.basisHash ?? "")) {
    throw new Error(
      `Cleanup ${fixture} diblokir: ${JSON.stringify(preview)}`,
    );
  }

  return rpc("reverse_stock_transaction", {
    p_organization_id: organizationId,
    p_idempotency_key: idempotencyKey,
    p_original_transaction_id: transactionId,
    p_preview_basis_hash: preview.basisHash,
    p_confirmation: true,
    p_note: note,
    p_metadata: {
      source: "stock-disposal-ui-smoke-cleanup",
      version: 1,
      runId,
      fixture,
      temporary: true,
    },
  });
}

function readDisposalEffect(sourceRef) {
  return runSqlJson(`
select jsonb_build_object(
  'disposalCount',
    (
      select count(*)
      from operations.stock_disposals disposal
      where disposal.organization_id = ${sqlLiteral(organizationId)}::uuid
        and disposal.source_ref = ${sqlLiteral(sourceRef)}
    ),
  'transactionCount',
    (
      select count(*)
      from inventory.stock_transactions transaction
      where transaction.organization_id = ${sqlLiteral(organizationId)}::uuid
        and transaction.transaction_type_code = 'DISPOSAL'
        and transaction.source_ref_snapshot = ${sqlLiteral(sourceRef)}
    ),
  'ledgerEntryCount',
    (
      select count(*)
      from inventory.stock_ledger_entries entry
      join inventory.stock_transactions transaction
        on transaction.id = entry.transaction_id
      where transaction.organization_id = ${sqlLiteral(organizationId)}::uuid
        and transaction.transaction_type_code = 'DISPOSAL'
        and transaction.source_ref_snapshot = ${sqlLiteral(sourceRef)}
    )
);
`);
}

async function main(args) {
  const runId = randomUUID();
  let receiptTransactionId = null;
  let disposalTransactionId = null;
  let fixture = null;

  console.log("== Preflight ==");

  const requiredPaths = [
    ".env.local",
    "package.json",
    "scripts/create-demo-admin.mjs",
    "scripts/test-stock-disposal-ui.mjs",
    "src/app/app-shell/navigation.ts",
    "src/app/stock-disposals/actions.ts",
    "src/app/stock-disposals/components/draft-form.tsx",
    "src/app/stock-disposals/draft.ts",
    "src/app/stock-disposals/page.tsx",
    "src/app/entry-corrections/page.tsx",
    "src/lib/supabase-rest.ts",
    "supabase/migrations/202607200007_stock_disposal_workflow.sql",
    "supabase/tests/044_stock_disposal_workflow.test.sql",
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

  const env = await loadEnvFile(path.resolve(process.cwd(), ".env.local"));
  supabaseUrl = String(
    env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321",
  ).replace(/\/$/, "");
  publishableKey = env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  serviceKey = env.SUPABASE_SECRET_KEY;

  assertTest(
    Boolean(publishableKey && !publishableKey.includes("REPLACE_ME")),
    "Publishable key lokal tersedia",
  );
  assertTest(
    Boolean(serviceKey && !serviceKey.includes("REPLACE_ME")),
    "Service key lokal tersedia",
  );

  const baseUri = new URL(args.baseUrl);

  if (!args.allowRemote && !isLoopback(baseUri.hostname)) {
    throw new Error(
      "Smoke test hanya boleh memakai loopback kecuali --allow-remote diberikan.",
    );
  }

  dbContainer = resolveDbContainer();
  assertTest(
    Boolean(dbContainer),
    "Database Supabase lokal ditemukan",
    dbContainer,
  );

  console.log("\n== Provision dan aktivasi Admin smoke ==");

  runCommand(
    process.platform === "win32" ? "npm.cmd" : "npm",
    [
      "run",
      "demo:admin",
      "--",
      "--email",
      args.email,
      "--password",
      args.password,
      "--name",
      args.displayName,
    ],
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
        email: args.email,
        password: args.password,
      }),
    },
  );
  const tokenPayload = await parseResponse(tokenResponse);

  assertTest(
    tokenResponse.ok && Boolean(tokenPayload?.access_token),
    "Password grant menghasilkan access token",
    JSON.stringify(tokenPayload),
  );

  accessToken = tokenPayload.access_token;
  smokeUserId = tokenPayload.user?.id;

  assertTest(
    UUID_PATTERN.test(smokeUserId ?? ""),
    "Auth user smoke memiliki UUID",
  );

  const profile = runSqlJson(`
select jsonb_build_object(
  'organizationId', profile.organization_id,
  'isActive', profile.is_active,
  'roleCode', profile.role_code
)
from app.user_profiles profile
where profile.user_id = ${sqlLiteral(smokeUserId)}::uuid;
`);

  organizationId = profile.organizationId;

  assertTest(
    UUID_PATTERN.test(organizationId ?? "") &&
      profile.isActive === true &&
      profile.roleCode === "ADMIN",
    "Token memiliki profil Admin aktif",
    JSON.stringify(profile),
  );

  console.log("\n== Start / reuse Next.js server ==");

  if (!(await isServerReady(args.baseUrl))) {
    startServer(args.baseUrl);
  }

  assertTest(
    await waitForServer(args.baseUrl, args.startupTimeoutSeconds),
    "Next.js server siap",
  );

  const anonymous = await getUnauthenticated(
    `${args.baseUrl}/stock-disposals`,
  );

  assertTest(
    [302, 303, 307, 308].includes(anonymous.statusCode) &&
      String(anonymous.location ?? "").includes("/login"),
    "Halaman pemusnahan menolak sesi anonim",
    `Status=${anonymous.statusCode} Location=${anonymous.location}`,
  );

  console.log("\n== Fixture batch kedaluwarsa ==");

  fixture = await createExpiredBatch(runId);
  assertTest(
    UUID_PATTERN.test(fixture.batchId) &&
      UUID_PATTERN.test(fixture.productId),
    "Batch kedaluwarsa sementara dibuat",
    JSON.stringify(fixture),
  );

  const receipt = await postReceipt({
    sourceRef: `${FIXTURE_PREFIX}receipt:${runId}`,
    idempotencyKey: `${FIXTURE_PREFIX}receipt:${runId}`,
    productId: fixture.productId,
    batchId: fixture.batchId,
    quantity: 5,
    runId,
    occurredAt: historicalReceiptOccurredAt(fixture.expiryDate),
  });

  receiptTransactionId = receipt.transactionId;

  assertTest(
    UUID_PATTERN.test(receiptTransactionId ?? ""),
    "Receipt fixture memiliki transaction ID",
    JSON.stringify(receipt),
  );

  const baseline = await readInventory(
    fixture.productId,
    fixture.batchId,
  );

  assertTest(
    Number(baseline.batch.sellable_qty) === 5,
    "Receipt fixture menambah SELLABLE tepat lima unit",
    JSON.stringify(baseline),
  );

  console.log("\n== Preview dan posting melalui UI ==");

  const draft = {
    sourceRef: `${FIXTURE_PREFIX}disposal:${runId}`,
    occurredAt: jakartaDateTimeLocal(),
    reasonCode: "EXPIRED_DISPOSAL",
    lines: [
      {
        productId: fixture.productId,
        batchId: fixture.batchId,
        sourceBucketCode: "SELLABLE",
        quantity: 2,
        sourceLineRef: "UI-1",
      },
    ],
    referenceText: `BA-SMOKE-${runId}`,
    note: `Pemusnahan batch kedaluwarsa untuk smoke ${runId}.`,
  };

  const ledgerBeforePreview = readLedgerWatermark();
  const preview = await previewDisposal(draft);
  const ledgerAfterPreview = readLedgerWatermark();
  const afterPreview = await readInventory(
    fixture.productId,
    fixture.batchId,
  );

  assertTest(
    preview?.eligible === true &&
      preview?.status === "PREVIEW_READY" &&
      HASH_PATTERN.test(preview?.basisHash ?? "") &&
      preview?.lines?.[0]?.batchId === fixture.batchId &&
      preview?.lines?.[0]?.sourceBucketCode === "SELLABLE",
    "Preview exact batch dan bucket eligible",
    JSON.stringify(preview),
  );

  assertTest(
    Number(afterPreview.batch.sellable_qty) ===
      Number(baseline.batch.sellable_qty),
    "Preview tidak mengubah projection stok",
  );

  assertTest(
    ledgerBeforePreview.entryCount === ledgerAfterPreview.entryCount &&
      ledgerBeforePreview.maxLedgerSeq === ledgerAfterPreview.maxLedgerSeq,
    "Preview tidak menulis ledger",
    JSON.stringify({
      before: ledgerBeforePreview,
      after: ledgerAfterPreview,
    }),
  );

  const draftQuery = encodeURIComponent(JSON.stringify(draft));
  const previewPage = await getPage(
    `${args.baseUrl}/stock-disposals?draft=${draftQuery}#preview`,
  );

  assertTest(
    containsText(previewPage.html, "Dampak stok exact batch dan bucket") &&
      containsText(previewPage.html, fixture.batchCode) &&
      containsText(previewPage.html, "Posting Pemusnahan Stok"),
    "Queue, drill-down preview, dan commit form dirender",
  );

  const commitForm = findForm(
    previewPage.html,
    "Posting Pemusnahan Stok",
  );
  const uiBasisHash = findInputValue(
    commitForm,
    "previewBasisHash",
  );
  const intentId = findInputValue(commitForm, "intentId");

  assertTest(
    uiBasisHash === preview.basisHash,
    "UI memakai basis hash preview database",
  );

  assertTest(
    UUID_PATTERN.test(intentId),
    "UI menghasilkan intent UUID untuk idempotency",
    intentId,
  );

  const beforeMissingConfirmation = readDisposalEffect(draft.sourceRef);
  const missingConfirmationPage = await invokeServerActionForm({
    pageUri: previewPage.uri,
    pageHtml: previewPage.html,
    marker: "Posting Pemusnahan Stok",
    fields: {
      draft: JSON.stringify(draft),
      previewBasisHash: uiBasisHash,
      intentId,
    },
    baseUrl: args.baseUrl,
  });
  const afterMissingConfirmation = readDisposalEffect(draft.sourceRef);

  assertTest(
    containsText(
      missingConfirmationPage.html,
      "Konfirmasi final wajib dicentang",
    ),
    "Server Action menolak commit tanpa konfirmasi",
  );

  assertTest(
    beforeMissingConfirmation.disposalCount ===
      afterMissingConfirmation.disposalCount &&
      afterMissingConfirmation.disposalCount === 0,
    "Failure konfirmasi tidak menulis domain effect",
  );

  const successPage = await invokeServerActionForm({
    pageUri: previewPage.uri,
    pageHtml: previewPage.html,
    marker: "Posting Pemusnahan Stok",
    fields: {
      draft: JSON.stringify(draft),
      previewBasisHash: uiBasisHash,
      intentId,
      confirmation: "on",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(successPage.html, "berhasil memusnahkan") &&
      containsText(successPage.html, "Buka transaksi dan jalur Koreksi Entri"),
    "Server Action memberi feedback sukses dan tautan koreksi",
  );

  const effect = readDisposalEffect(draft.sourceRef);

  assertTest(
    Number(effect.disposalCount) === 1 &&
      Number(effect.transactionCount) === 1 &&
      Number(effect.ledgerEntryCount) === 1,
    "Commit membuat satu dokumen, transaksi, dan ledger entry",
    JSON.stringify(effect),
  );

  const disposals = await restRows(
    `stock_disposals?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&source_ref=eq.${encodeURIComponent(draft.sourceRef)}&select=*`,
  );
  const disposal = disposals[0];

  disposalTransactionId = disposal?.transaction_id;

  assertTest(
    UUID_PATTERN.test(disposal?.disposal_id ?? "") &&
      UUID_PATTERN.test(disposalTransactionId ?? ""),
    "Riwayat disposal menyimpan identitas immutable",
    JSON.stringify(disposal),
  );

  const afterDisposal = await readInventory(
    fixture.productId,
    fixture.batchId,
  );

  assertTest(
    Number(afterDisposal.batch.sellable_qty) === 3 &&
      Number(afterDisposal.product.sellable_qty) ===
        Number(baseline.product.sellable_qty) - 2,
    "Posting mengurangi exact batch dan projection produk sekali",
    JSON.stringify({ baseline, afterDisposal }),
  );

  const detailPage = await getPage(
    `${args.baseUrl}/stock-disposals?disposalId=${encodeURIComponent(
      disposal.disposal_id,
    )}#history`,
  );

  assertTest(
    containsText(detailPage.html, disposal.disposal_no) &&
      containsText(detailPage.html, fixture.batchCode) &&
      containsText(detailPage.html, draft.referenceText) &&
      containsText(detailPage.html, "Tinjau melalui Koreksi Entri"),
    "Feedback, history, dan detail bertahan setelah refresh",
  );

  console.log("\n== Replay idempotent dan Koreksi Entri ==");

  const replay = await rpc("post_stock_disposal", {
    p_organization_id: organizationId,
    p_idempotency_key: `stock-disposal:${intentId}`,
    p_source_ref: draft.sourceRef,
    p_occurred_at: occurredAtFromDraft(draft),
    p_reason_code: draft.reasonCode,
    p_lines: draft.lines,
    p_preview_basis_hash: uiBasisHash,
    p_confirmation: true,
    p_reference_text: draft.referenceText,
    p_note: draft.note,
    p_metadata: {
      source: "stock-disposal-admin-ui",
      version: 1,
    },
  });

  const replayEffect = readDisposalEffect(draft.sourceRef);

  assertTest(
    replay?.transactionId === disposalTransactionId,
    "Replay command identik mengembalikan transaksi yang sama",
  );

  assertTest(
    Number(replayEffect.disposalCount) === 1 &&
      Number(replayEffect.transactionCount) === 1 &&
      Number(replayEffect.ledgerEntryCount) === 1,
    "Replay idempotent tidak menggandakan domain effect",
    JSON.stringify(replayEffect),
  );

  const correctionPage = await getPage(
    `${args.baseUrl}/entry-corrections?type=DISPOSAL&transactionId=${encodeURIComponent(
      disposalTransactionId,
    )}#detail`,
  );

  assertTest(
    containsText(correctionPage.html, "Posting Koreksi Entri") &&
      containsText(correctionPage.html, disposal.disposal_no) &&
      containsText(correctionPage.html, fixture.batchCode),
    "Koreksi Entri merender disposal dan preview exact batch",
  );

  const correctionForm = findForm(
    correctionPage.html,
    "Posting Koreksi Entri",
  );
  const reversalHash = findInputValue(
    correctionForm,
    "previewBasisHash",
  );
  const reversalKey = findInputValue(
    correctionForm,
    "idempotencyKey",
  );
  const returnTo = findInputValue(correctionForm, "returnTo");

  const reversedPage = await invokeServerActionForm({
    pageUri: correctionPage.uri,
    pageHtml: correctionPage.html,
    marker: "Posting Koreksi Entri",
    fields: {
      originalTransactionId: disposalTransactionId,
      previewBasisHash: reversalHash,
      idempotencyKey: reversalKey,
      returnTo,
      note: `Koreksi disposal smoke ${runId}.`,
      confirmation: "on",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(reversedPage.html, "berhasil membalik") &&
      containsText(reversedPage.html, disposal.disposal_no),
    "Disposal berhasil dibalik melalui UI Koreksi Entri",
  );

  const afterReversal = await readInventory(
    fixture.productId,
    fixture.batchId,
  );

  assertTest(
    Number(afterReversal.batch.sellable_qty) === 5 &&
      Number(afterReversal.product.sellable_qty) ===
        Number(baseline.product.sellable_qty),
    "Reversal memulihkan exact batch tanpa FEFO atau realokasi",
    JSON.stringify({ baseline, afterReversal }),
  );

  const serverOutput = `${serverStdout}\n${serverStderr}`;
  assertTest(
    !/unhandled runtime error|uncaught exception|fatal error/i.test(
      serverOutput,
    ),
    "Tidak ada unhandled runtime error selama smoke test",
    serverOutput.slice(-4000),
  );

  console.log("\n== Pemulihan fixture ==");

  if (receiptTransactionId) {
    await reverseDirect({
      transactionId: receiptTransactionId,
      idempotencyKey: `${FIXTURE_PREFIX}cleanup-receipt:${runId}`,
      note: `Cleanup receipt disposal UI smoke ${runId}.`,
      runId,
      fixture: "receipt",
    });
  }

  const finalSnapshot = await readInventory(
    fixture.productId,
    fixture.batchId,
  );

  assertTest(
    Number(finalSnapshot.batch.sellable_qty) === 0 &&
      Number(finalSnapshot.batch.quarantine_qty) === 0 &&
      Number(finalSnapshot.batch.damaged_qty) === 0,
    "Saldo batch fixture kembali nol",
    JSON.stringify(finalSnapshot),
  );

  runSql(`
update catalog.product_batches
set
  status_code = 'ARCHIVED',
  block_reason = null,
  updated_by = ${sqlLiteral(smokeUserId)}::uuid
where organization_id = ${sqlLiteral(organizationId)}::uuid
  and id = ${sqlLiteral(fixture.batchId)}::uuid;
`);

  const archived = runSqlJson(`
select jsonb_build_object(
  'statusCode', batch.status_code,
  'batchId', batch.id
)
from catalog.product_batches batch
where batch.organization_id = ${sqlLiteral(organizationId)}::uuid
  and batch.id = ${sqlLiteral(fixture.batchId)}::uuid;
`);

  assertTest(
    archived.statusCode === "ARCHIVED",
    "Batch fixture nol diarsipkan",
    JSON.stringify(archived),
  );
}

async function run() {
  const args = parseArgs(process.argv.slice(2));

  try {
    await main(args);
  } catch (error) {
    exitCode = 1;
    console.error(
      `\nSmoke test gagal: ${
        error instanceof Error ? error.stack ?? error.message : error
      }`,
    );
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
      `Result: ${failed === 0 && exitCode === 0 ? "PASS" : "FAIL"} ` +
        `(${passed} passed, ${failed} failed)`,
    );

    process.exitCode = exitCode;
  }
}

await run();