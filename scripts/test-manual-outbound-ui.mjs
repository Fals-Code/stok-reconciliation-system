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
const FIXTURE_PREFIX = "manual-outbound-ui-smoke:";

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

function hasForm(html, marker) {
  const forms = html.match(/<form\b[^>]*>.*?<\/form>/gis) ?? [];
  const normalizedMarker = normalizeRenderedText(marker);

  return forms.some((candidate) =>
    normalizeRenderedText(candidate).includes(normalizedMarker),
  );
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
    serverStdout = (serverStdout + chunk.toString()).slice(-50000);
  });

  ownedServer.stderr.on("data", (chunk) => {
    serverStderr = (serverStderr + chunk.toString()).slice(-50000);
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

function metadataForDraft(draft) {
  return {
    source: "manual-outbound-admin-ui",
    version: 1,
    ...(draft.reference ? { reference: draft.reference } : {}),
  };
}

async function previewDraftDirect(draft) {
  return rpc("preview_manual_outbound", {
    p_organization_id: organizationId,
    p_source_ref: draft.sourceRef,
    p_occurred_at: occurredAtFromDraft(draft),
    p_reason_code: draft.reasonCode,
    p_lines: draft.lines,
    p_note: draft.note,
    p_metadata: metadataForDraft(draft),
  });
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

async function readInventorySnapshot(productId, batchIds) {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  const encodedProductId = encodeURIComponent(productId);
  const products = await restRows(
    "product_inventory" +
      `?organization_id=eq.${encodedOrganizationId}` +
      `&product_id=eq.${encodedProductId}` +
      "&select=product_id,sellable_qty,reserved_qty,available_qty,last_ledger_seq",
  );

  if (!products[0]) {
    throw new Error("Projection produk fixture tidak ditemukan.");
  }

  const batches = [];

  for (const batchId of batchIds) {
    const encodedBatchId = encodeURIComponent(batchId);
    const rows = await restRows(
      "batch_inventory" +
        `?organization_id=eq.${encodedOrganizationId}` +
        `&batch_id=eq.${encodedBatchId}` +
        "&select=batch_id,batch_code,sellable_qty,last_ledger_seq",
    );

    if (!rows[0]) {
      throw new Error(`Projection batch tidak ditemukan: ${batchId}`);
    }

    batches.push(rows[0]);
  }

  return {
    product: products[0],
    batches: batches.sort((left, right) =>
      left.batch_id.localeCompare(right.batch_id),
    ),
  };
}

function readManualEffect(sourceRef) {
  return runSqlJson(`
select jsonb_build_object(
  'outboundCount',
    (
      select count(*)
      from operations.manual_outbounds outbound
      where outbound.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and outbound.source_ref = ${sqlLiteral(sourceRef)}
    ),
  'transactionCount',
    (
      select count(*)
      from inventory.stock_transactions transaction
      where transaction.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and transaction.transaction_type_code = 'MANUAL_OUTBOUND'
        and transaction.source_ref_snapshot = ${sqlLiteral(sourceRef)}
    ),
  'ledgerEntryCount',
    (
      select count(*)
      from inventory.stock_ledger_entries entry
      join inventory.stock_transactions transaction
        on transaction.id = entry.transaction_id
      where transaction.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and transaction.transaction_type_code = 'MANUAL_OUTBOUND'
        and transaction.source_ref_snapshot = ${sqlLiteral(sourceRef)}
    ),
  'allocationCount',
    (
      select count(*)
      from operations.manual_outbound_allocations allocation
      join operations.manual_outbounds outbound
        on outbound.id = allocation.outbound_id
      where outbound.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and outbound.source_ref = ${sqlLiteral(sourceRef)}
    )
);
`);
}

async function readOutboundById(outboundId) {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  const encodedOutboundId = encodeURIComponent(outboundId);
  const outbounds = await restRows(
    "manual_outbounds" +
      `?organization_id=eq.${encodedOrganizationId}` +
      `&outbound_id=eq.${encodedOutboundId}` +
      "&select=*",
  );
  const lines = await restRows(
    "manual_outbound_lines" +
      `?organization_id=eq.${encodedOrganizationId}` +
      `&outbound_id=eq.${encodedOutboundId}` +
      "&select=*&order=line_no.asc",
  );
  const allocations = await restRows(
    "manual_outbound_allocations" +
      `?organization_id=eq.${encodedOrganizationId}` +
      `&outbound_id=eq.${encodedOutboundId}` +
      "&select=*&order=outbound_line_id.asc,allocation_no.asc",
  );

  return {
    outbound: outbounds[0] ?? null,
    lines,
    allocations,
  };
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
        sourceLineRef: "SMOKE-RECEIPT-1",
      },
    ],
    p_note: `Temporary ${fixture} receipt for manual outbound smoke.`,
    p_metadata: {
      source: "manual-outbound-ui-smoke",
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
      source: "manual-outbound-ui-smoke-cleanup",
      version: 1,
      runId,
      fixture,
      temporary: true,
    },
  });
}

async function selectFefoFixture(runId) {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  const rows = await restRows(
    "batch_inventory" +
      `?organization_id=eq.${encodedOrganizationId}` +
      "&status_code=eq.ACTIVE" +
      "&sellable_qty=gt.0" +
      "&select=batch_id,product_id,sku,product_name,batch_code," +
      "expiry_date,received_first_at,status_code,sellable_qty" +
      "&order=product_id.asc,expiry_date.asc,received_first_at.asc.nullslast,batch_code.asc",
  );
  const byProduct = new Map();

  for (const row of rows) {
    const current = byProduct.get(row.product_id) ?? [];
    current.push(row);
    byProduct.set(row.product_id, current);
  }

  for (const batches of byProduct.values()) {
    if (batches.length < 2) continue;

    const first = batches[0];
    const quantity = Number(first.sellable_qty) + 1;
    const candidate = {
      sourceRef: `${FIXTURE_PREFIX}fixture-check:${randomUUID()}`,
      occurredAt: jakartaDateTimeLocal(),
      reasonCode: "OFFLINE_SALE",
      lines: [
        {
          productId: first.product_id,
          quantity,
          sourceLineRef: "UI-1",
        },
      ],
      note: "Fixture selection preview.",
      reference: null,
    };
    const preview = await previewDraftDirect(
      candidate,
      runId,
      "fixture-selection",
    );

    if (
      preview?.eligible === true &&
      preview?.status === "PREVIEW_READY" &&
      Array.isArray(preview.allocations) &&
      preview.allocations.length >= 2
    ) {
      const allocatedBatchIds = new Set(
        preview.allocations.map((allocation) => allocation.batchId),
      );
      const selectedBatches = batches.filter((batch) =>
        allocatedBatchIds.has(batch.batch_id),
      );

      return {
        productId: first.product_id,
        sku: first.sku,
        productName: first.product_name,
        batches: selectedBatches,
        oneBatchQuantity: Math.max(
          1,
          Math.min(
            Number(preview.allocations[0].quantity),
            Number(first.sellable_qty),
          ),
        ),
        splitQuantity: quantity,
        splitPreview: preview,
      };
    }
  }

  throw new Error(
    "Fixture FEFO membutuhkan satu produk dengan minimal dua batch eligible.",
  );
}

function normalizePreviewAllocations(allocations) {
  return [...allocations]
    .map((allocation) => ({
      batchId: allocation.batchId,
      batchCode: allocation.batchCode,
      quantity: Number(allocation.quantity),
    }))
    .sort((left, right) =>
      `${left.batchId}:${left.quantity}`.localeCompare(
        `${right.batchId}:${right.quantity}`,
      ),
    );
}

function normalizePersistedAllocations(allocations) {
  return [...allocations]
    .map((allocation) => ({
      batchId: allocation.batch_id,
      batchCode: allocation.batch_code_snapshot,
      quantity: Number(allocation.quantity_allocated),
    }))
    .sort((left, right) =>
      `${left.batchId}:${left.quantity}`.localeCompare(
        `${right.batchId}:${right.quantity}`,
      ),
    );
}

async function main(args) {
  const runId = randomUUID();
  const cleanupTransactions = [];
  let baselineSnapshot = null;
  let fixture = null;

  console.log("== Preflight ==");

  const requiredPaths = [
    ".env.local",
    "package.json",
    "scripts/create-demo-admin.mjs",
    "scripts/test-manual-outbound-ui.mjs",
    "src/app/app-shell/navigation.ts",
    "src/app/manual-outbounds/actions.ts",
    "src/app/manual-outbounds/components/draft-form.tsx",
    "src/app/manual-outbounds/draft.ts",
    "src/app/manual-outbounds/page.tsx",
    "src/lib/supabase-rest.ts",
    "supabase/migrations/202607180006_manual_outbound_preview.sql",
    "supabase/tests/043_manual_outbound_preview.test.sql",
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
      where profile.organization_id =
            '00000000-0000-4000-8000-000000000001'::uuid
        and profile.employee_code = 'DEMO-ADMIN'
        and profile.role_code = 'ADMIN'
    ),
  'userId',
    (
      select profile.user_id::text
      from app.user_profiles profile
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
      "Smoke test lokal harus memakai Admin demo existing: " +
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

  const organizationOutput = runSql(
    `
update app.user_profiles
set is_active = true
where user_id = ${sqlLiteral(smokeUserId)}::uuid
returning organization_id::text;
`,
    { tuplesOnly: true },
  );
  organizationId = organizationOutput
    .split(/\r?\n/)
    .map((value) => value.trim())
    .find((value) => UUID_PATTERN.test(value));

  assertTest(
    UUID_PATTERN.test(organizationId ?? ""),
    "Profil smoke aktif pada satu organisasi",
    organizationId ?? "",
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

  const manualUrl = `${args.baseUrl}/manual-outbounds`;
  const unauthenticated = await getUnauthenticated(manualUrl);

  assertTest(
    [302, 303, 307, 308].includes(
      unauthenticated.statusCode,
    ) &&
      String(unauthenticated.location ?? "").includes("/login"),
    "Halaman Barang Keluar menolak sesi anonim",
    `Status=${unauthenticated.statusCode} ` +
      `Location=${unauthenticated.location ?? ""}`,
  );

  let page = await getPage(manualUrl);

  assertTest(
    containsText(page.html, "Barang Keluar") &&
      containsText(page.html, "Preview FEFO") &&
      containsText(page.html, "Tinjau alokasi FEFO"),
    "Halaman authenticated dan navigasi Barang Keluar dirender",
  );

  const dashboard = await getPage(`${args.baseUrl}/`);

  assertTest(
    containsText(
      dashboard.html,
      "Buka workflow Barang Keluar",
    ) &&
      !containsText(
        dashboard.html,
        "Allocate & post outbound",
      ),
    "Dashboard hanya menyediakan shortcut tanpa direct-post bypass",
  );

  fixture = await selectFefoFixture(runId);
  baselineSnapshot = await readInventorySnapshot(
    fixture.productId,
    fixture.batches.map((batch) => batch.batch_id),
  );

  assertTest(
    fixture.batches.length >= 2 &&
      fixture.splitPreview.allocations.length >= 2,
    "Fixture memiliki split FEFO authoritative",
    JSON.stringify(fixture),
  );

  try {
    console.log("\n== Preview satu batch dan stock-neutral ==");

    const oneBatchDraft = {
      sourceRef: `${FIXTURE_PREFIX}one-batch:${runId}`,
      occurredAt: jakartaDateTimeLocal(),
      reasonCode: "OFFLINE_SALE",
      lines: [
        {
          productId: fixture.productId,
          quantity: fixture.oneBatchQuantity,
          sourceLineRef: "UI-1",
        },
      ],
      note: `Preview satu batch ${runId}.`,
      reference: null,
    };
    const oneBatchDirect = await previewDraftDirect(
      oneBatchDraft,
      runId,
      "one-batch",
    );

    assertTest(
      oneBatchDirect?.eligible === true &&
        oneBatchDirect?.status === "PREVIEW_READY" &&
        oneBatchDirect?.allocations?.length === 1 &&
        HASH_PATTERN.test(oneBatchDirect?.basisHash ?? ""),
      "RPC preview satu batch eligible",
      JSON.stringify(oneBatchDirect),
    );

    const ledgerBeforeOneBatch = readLedgerWatermark();
    const inventoryBeforeOneBatch = await readInventorySnapshot(
      fixture.productId,
      fixture.batches.map((batch) => batch.batch_id),
    );

    page = await invokeServerActionForm({
      pageUri: page.uri,
      pageHtml: page.html,
      marker: "Tinjau alokasi FEFO",
      fields: {
        draft: JSON.stringify(oneBatchDraft),
      },
      baseUrl: args.baseUrl,
    });

    assertTest(
      containsText(page.html, "Preview authoritative") &&
        containsText(page.html, "Siap diposting") &&
        containsText(
          page.html,
          oneBatchDirect.allocations[0].batchCode,
        ) &&
        hasForm(page.html, "Posting Barang Keluar"),
      "UI merender preview satu batch dan commit form",
    );

    const oneBatchForm = findForm(
      page.html,
      "Posting Barang Keluar",
    );
    const oneBatchHash = findInputValue(
      oneBatchForm,
      "previewBasisHash",
    );

    assertTest(
      oneBatchHash === oneBatchDirect.basisHash,
      "UI memakai basis hash preview satu batch dari database",
    );

    const inventoryAfterOneBatch = await readInventorySnapshot(
      fixture.productId,
      fixture.batches.map((batch) => batch.batch_id),
    );
    const ledgerAfterOneBatch = readLedgerWatermark();

    assertTest(
      JSON.stringify(inventoryAfterOneBatch) ===
        JSON.stringify(inventoryBeforeOneBatch) &&
        JSON.stringify(ledgerAfterOneBatch) ===
          JSON.stringify(ledgerBeforeOneBatch) &&
        readManualEffect(oneBatchDraft.sourceRef).outboundCount === 0,
      "Preview UI satu batch tidak mengubah stok, ledger, atau dokumen",
    );

    console.log("\n== Reason/reference blocker ==");

    const promoDraft = {
      sourceRef: `${FIXTURE_PREFIX}promo-blocked:${runId}`,
      occurredAt: jakartaDateTimeLocal(),
      reasonCode: "PROMO",
      lines: [
        {
          productId: fixture.productId,
          quantity: 1,
          sourceLineRef: "UI-1",
        },
      ],
      note: `Promo tanpa referensi ${runId}.`,
      reference: null,
    };
    const promoPage = await invokeServerActionForm({
      pageUri: manualUrl,
      pageHtml: (await getPage(manualUrl)).html,
      marker: "Tinjau alokasi FEFO",
      fields: {
        draft: JSON.stringify(promoDraft),
      },
      baseUrl: args.baseUrl,
    });

    assertTest(
      containsText(
        promoPage.html,
        "Referensi kegiatan, persetujuan, penerima, atau pesanan wajib diisi.",
      ) &&
        containsText(
          promoPage.html,
          "OUTBOUND_REASON_REFERENCE_REQUIRED",
        ) &&
        containsText(promoPage.html, "Diblokir") &&
        !hasForm(promoPage.html, "Posting Barang Keluar"),
      "Promo tanpa referensi diblokir tanpa commit action",
    );

    console.log("\n== Multi-line atomic blocked preview ==");

    const atomicDraft = {
      sourceRef: `${FIXTURE_PREFIX}atomic-blocked:${runId}`,
      occurredAt: jakartaDateTimeLocal(),
      reasonCode: "OFFLINE_SALE",
      lines: [
        {
          productId: fixture.productId,
          quantity: 1,
          sourceLineRef: "UI-1",
        },
        {
          productId: randomUUID(),
          quantity: 1,
          sourceLineRef: "UI-2",
        },
      ],
      note: `Atomic blocked ${runId}.`,
      reference: null,
    };
    const atomicBefore = await readInventorySnapshot(
      fixture.productId,
      fixture.batches.map((batch) => batch.batch_id),
    );
    const atomicLedgerBefore = readLedgerWatermark();
    const atomicPage = await invokeServerActionForm({
      pageUri: manualUrl,
      pageHtml: (await getPage(manualUrl)).html,
      marker: "Tinjau alokasi FEFO",
      fields: {
        draft: JSON.stringify(atomicDraft),
      },
      baseUrl: args.baseUrl,
    });
    const atomicAfter = await readInventorySnapshot(
      fixture.productId,
      fixture.batches.map((batch) => batch.batch_id),
    );
    const atomicLedgerAfter = readLedgerWatermark();
    const atomicEffect = readManualEffect(atomicDraft.sourceRef);

    assertTest(
      containsText(atomicPage.html, "Diblokir") &&
        !hasForm(atomicPage.html, "Posting Barang Keluar") &&
        JSON.stringify(atomicAfter) === JSON.stringify(atomicBefore) &&
        JSON.stringify(atomicLedgerAfter) ===
          JSON.stringify(atomicLedgerBefore) &&
        atomicEffect.outboundCount === 0 &&
        atomicEffect.transactionCount === 0 &&
        atomicEffect.ledgerEntryCount === 0 &&
        atomicEffect.allocationCount === 0,
      "Multi-line invalid diblokir atomik tanpa partial effect",
      JSON.stringify(atomicEffect),
    );

    console.log("\n== Split FEFO dan commit melalui Server Action ==");

    const splitDraft = {
      sourceRef: `${FIXTURE_PREFIX}split-success:${runId}`,
      occurredAt: jakartaDateTimeLocal(),
      reasonCode: "OFFLINE_SALE",
      lines: [
        {
          productId: fixture.productId,
          quantity: fixture.splitQuantity,
          sourceLineRef: "UI-1",
        },
      ],
      note: `Split FEFO UI smoke ${runId}.`,
      reference: null,
    };
    const splitDirect = await previewDraftDirect(
      splitDraft,
      runId,
      "split-success",
    );

    assertTest(
      splitDirect?.eligible === true &&
        splitDirect?.allocations?.length >= 2 &&
        HASH_PATTERN.test(splitDirect?.basisHash ?? ""),
      "RPC preview split FEFO eligible",
      JSON.stringify(splitDirect),
    );

    const splitPage = await invokeServerActionForm({
      pageUri: manualUrl,
      pageHtml: (await getPage(manualUrl)).html,
      marker: "Tinjau alokasi FEFO",
      fields: {
        draft: JSON.stringify(splitDraft),
      },
      baseUrl: args.baseUrl,
    });

    assertTest(
      splitDirect.allocations.every((allocation) =>
        containsText(splitPage.html, allocation.batchCode),
      ) &&
        containsText(splitPage.html, "Posting Barang Keluar") &&
        containsText(splitPage.html, "Reserved"),
      "UI menampilkan split batch, stock before/after, dan reserved",
    );

    const splitForm = findForm(
      splitPage.html,
      "Posting Barang Keluar",
    );
    const splitHash = findInputValue(
      splitForm,
      "previewBasisHash",
    );
    const splitIntentId = findInputValue(
      splitForm,
      "intentId",
    );
    const splitHiddenDraft = findInputValue(
      splitForm,
      "draft",
    );

    assertTest(
      splitHash === splitDirect.basisHash &&
        HASH_PATTERN.test(splitHash) &&
        UUID_PATTERN.test(splitIntentId) &&
        JSON.parse(splitHiddenDraft).sourceRef ===
          splitDraft.sourceRef,
      "Commit form membawa exact draft, basis hash, dan intent ID",
    );

    const missingConfirmationPage =
      await invokeServerActionForm({
        pageUri: splitPage.uri,
        pageHtml: splitPage.html,
        marker: "Posting Barang Keluar",
        fields: {
          draft: splitHiddenDraft,
          previewBasisHash: splitHash,
          intentId: splitIntentId,
        },
        baseUrl: args.baseUrl,
      });
    const missingConfirmationEffect = readManualEffect(
      splitDraft.sourceRef,
    );

    assertTest(
      containsText(
        missingConfirmationPage.html,
        "Konfirmasi final wajib dicentang",
      ) &&
        missingConfirmationEffect.outboundCount === 0 &&
        missingConfirmationEffect.ledgerEntryCount === 0,
      "Server Action menolak commit tanpa konfirmasi final",
      JSON.stringify(missingConfirmationEffect),
    );

    let successPage = await invokeServerActionForm({
      pageUri: splitPage.uri,
      pageHtml: splitPage.html,
      marker: "Posting Barang Keluar",
      fields: {
        draft: splitHiddenDraft,
        previewBasisHash: splitHash,
        intentId: splitIntentId,
        confirmation: "on",
      },
      baseUrl: args.baseUrl,
    });

    const successUrl = new URL(successPage.uri);
    const outboundId = successUrl.searchParams.get("outboundId");
    const transactionId =
      successUrl.searchParams.get("transactionId");

    assertTest(
      UUID_PATTERN.test(outboundId ?? "") &&
        UUID_PATTERN.test(transactionId ?? "") &&
        containsText(successPage.html, "berhasil memposting") &&
        containsText(
          successPage.html,
          "Buka transaksi dan jalur Koreksi Entri",
        ),
      "Commit Server Action redirect dengan feedback dan linkage",
      successPage.uri,
    );

    cleanupTransactions.push({
      transactionId,
      fixture: "split-success",
    });

    const persisted = await readOutboundById(outboundId);
    const persistedLedger = await readLedgerByTransaction(
      transactionId,
    );
    const effectAfterCommit = readManualEffect(
      splitDraft.sourceRef,
    );

    assertTest(
      persisted.outbound?.transaction_id === transactionId &&
        persisted.lines.length === 1 &&
        persisted.allocations.length ===
          splitDirect.allocations.length &&
        persistedLedger.length ===
          splitDirect.allocations.length,
      "Dokumen, line, allocation, transaction, dan ledger terhubung",
      JSON.stringify({
        persisted,
        ledger: persistedLedger,
      }),
    );

    assertTest(
      JSON.stringify(
        normalizePersistedAllocations(
          persisted.allocations,
        ),
      ) ===
        JSON.stringify(
          normalizePreviewAllocations(
            splitDirect.allocations,
          ),
        ),
      "Allocation commit tepat sama dengan preview authoritative",
      JSON.stringify({
        preview: normalizePreviewAllocations(
          splitDirect.allocations,
        ),
        persisted: normalizePersistedAllocations(
          persisted.allocations,
        ),
      }),
    );

    assertTest(
      effectAfterCommit.outboundCount === 1 &&
        effectAfterCommit.transactionCount === 1 &&
        effectAfterCommit.ledgerEntryCount ===
          splitDirect.allocations.length &&
        effectAfterCommit.allocationCount ===
          splitDirect.allocations.length,
      "Commit menghasilkan tepat satu domain effect",
      JSON.stringify(effectAfterCommit),
    );

    const refreshedSuccessPage = await getPage(successPage.uri);

    assertTest(
      containsText(refreshedSuccessPage.html, "berhasil memposting") &&
        containsText(
          refreshedSuccessPage.html,
          persisted.outbound.outbound_no,
        ) &&
        containsText(
          refreshedSuccessPage.html,
          "Buka Ledger dan Koreksi Entri",
        ),
      "Feedback sukses dan drill-down bertahan setelah refresh",
    );

    const correctionPage = await getPage(
      `${args.baseUrl}/entry-corrections` +
        `?transactionId=${transactionId}#detail`,
    );

    assertTest(
      containsText(correctionPage.html, persisted.outbound.outbound_no) &&
        containsText(
          correctionPage.html,
          "Preview dampak authoritative",
        ),
      "Link Koreksi Entri membuka transaksi immutable yang diposting",
    );

    const replayPage = await invokeServerActionForm({
      pageUri: splitPage.uri,
      pageHtml: splitPage.html,
      marker: "Posting Barang Keluar",
      fields: {
        draft: splitHiddenDraft,
        previewBasisHash: splitHash,
        intentId: splitIntentId,
        confirmation: "on",
      },
      baseUrl: args.baseUrl,
    });
    const effectAfterReplay = readManualEffect(
      splitDraft.sourceRef,
    );

    assertTest(
      containsText(replayPage.html, "berhasil memposting") &&
        effectAfterReplay.outboundCount === 1 &&
        effectAfterReplay.transactionCount === 1 &&
        effectAfterReplay.ledgerEntryCount ===
          splitDirect.allocations.length &&
        effectAfterReplay.allocationCount ===
          splitDirect.allocations.length,
      "Duplicate submit replay sukses tanpa menggandakan effect",
      JSON.stringify(effectAfterReplay),
    );

    console.log("\n== Stale preview setelah perubahan basis ==");

    const staleDraft = {
      sourceRef: `${FIXTURE_PREFIX}stale:${runId}`,
      occurredAt: jakartaDateTimeLocal(),
      reasonCode: "OFFLINE_SALE",
      lines: [
        {
          productId: fixture.productId,
          quantity: 1,
          sourceLineRef: "UI-1",
        },
      ],
      note: `Stale preview UI smoke ${runId}.`,
      reference: null,
    };
    const stalePage = await invokeServerActionForm({
      pageUri: manualUrl,
      pageHtml: (await getPage(manualUrl)).html,
      marker: "Tinjau alokasi FEFO",
      fields: {
        draft: JSON.stringify(staleDraft),
      },
      baseUrl: args.baseUrl,
    });
    const staleForm = findForm(
      stalePage.html,
      "Posting Barang Keluar",
    );
    const staleHash = findInputValue(
      staleForm,
      "previewBasisHash",
    );
    const staleIntentId = findInputValue(
      staleForm,
      "intentId",
    );
    const staleHiddenDraft = findInputValue(
      staleForm,
      "draft",
    );
    const interferenceSourceRef =
      `${FIXTURE_PREFIX}interference:${runId}`;
    const interference = await postReceipt({
      sourceRef: interferenceSourceRef,
      idempotencyKey:
        `${FIXTURE_PREFIX}post:interference:${runId}`,
      productId: fixture.productId,
      batchId: fixture.batches[0].batch_id,
      quantity: 1,
      runId,
      fixture: "stale-interference",
    });

    assertTest(
      UUID_PATTERN.test(interference?.transactionId ?? ""),
      "Interference mengubah basis setelah preview",
      JSON.stringify(interference),
    );

    cleanupTransactions.push({
      transactionId: interference.transactionId,
      fixture: "stale-interference",
    });

    const staleCommitPage = await invokeServerActionForm({
      pageUri: stalePage.uri,
      pageHtml: stalePage.html,
      marker: "Posting Barang Keluar",
      fields: {
        draft: staleHiddenDraft,
        previewBasisHash: staleHash,
        intentId: staleIntentId,
        confirmation: "on",
      },
      baseUrl: args.baseUrl,
    });
    const staleEffect = readManualEffect(staleDraft.sourceRef);

    assertTest(
      containsText(
        staleCommitPage.html,
        "Posisi stok berubah setelah preview dibuat",
      ) &&
        staleEffect.outboundCount === 0 &&
        staleEffect.transactionCount === 0 &&
        staleEffect.ledgerEntryCount === 0 &&
        staleEffect.allocationCount === 0,
      "Stale preview ditolak tanpa mengganti alokasi diam-diam",
      JSON.stringify(staleEffect),
    );

    const serverLog = `${serverStdout}\n${serverStderr}`;
    const unsafeLogPattern =
      /Unhandled Runtime Error|Internal Server Error|ReferenceError:|TypeError:|⨯/i;

    assertTest(
      !unsafeLogPattern.test(serverLog),
      "Tidak ada unhandled browser/server runtime error",
      unsafeLogPattern.test(serverLog)
        ? serverLog.slice(-5000)
        : "",
    );
  } finally {
    console.log("\n== Pemulihan stok fixture ==");

    for (const item of [...cleanupTransactions].reverse()) {
      try {
        await reverseDirect({
          transactionId: item.transactionId,
          idempotencyKey:
            `${FIXTURE_PREFIX}cleanup:${item.fixture}:${runId}`,
          note:
            `Cleanup ${item.fixture} setelah smoke test Barang Keluar.`,
          runId,
          fixture: item.fixture,
        });
        addResult(
          `Projection fixture dipulihkan: ${item.fixture}`,
          true,
        );
      } catch (error) {
        addResult(
          `Projection fixture dipulihkan: ${item.fixture}`,
          false,
          error instanceof Error ? error.message : String(error),
        );
      }
    }

    if (baselineSnapshot && fixture) {
      try {
        const finalSnapshot = await readInventorySnapshot(
          fixture.productId,
          fixture.batches.map((batch) => batch.batch_id),
        );

        const baselineBatches = new Map(
          baselineSnapshot.batches.map((batch) => [
            batch.batch_id,
            batch,
          ]),
        );
        const quantitiesRestored =
          Number(finalSnapshot.product.sellable_qty) ===
            Number(baselineSnapshot.product.sellable_qty) &&
          Number(finalSnapshot.product.reserved_qty) ===
            Number(baselineSnapshot.product.reserved_qty) &&
          Number(finalSnapshot.product.available_qty) ===
            Number(baselineSnapshot.product.available_qty) &&
          finalSnapshot.batches.length ===
            baselineSnapshot.batches.length &&
          finalSnapshot.batches.every((batch) => {
            const baselineBatch = baselineBatches.get(batch.batch_id);

            return (
              baselineBatch &&
              Number(batch.sellable_qty) ===
                Number(baselineBatch.sellable_qty)
            );
          });
        const ledgerWatermarksAdvanced =
          Number(finalSnapshot.product.last_ledger_seq) >=
            Number(baselineSnapshot.product.last_ledger_seq) &&
          finalSnapshot.batches.every((batch) => {
            const baselineBatch = baselineBatches.get(batch.batch_id);

            return (
              baselineBatch &&
              Number(batch.last_ledger_seq) >=
                Number(baselineBatch.last_ledger_seq)
            );
          });

        addResult(
          "Projection quantity akhir kembali ke baseline",
          quantitiesRestored,
          JSON.stringify({
            baseline: baselineSnapshot,
            final: finalSnapshot,
          }),
        );
        addResult(
          "Ledger watermark maju setelah posting dan reversal",
          ledgerWatermarksAdvanced,
          JSON.stringify({
            baseline: baselineSnapshot,
            final: finalSnapshot,
          }),
        );
      } catch (error) {
        addResult(
          "Projection akhir kembali ke baseline",
          false,
          error instanceof Error ? error.message : String(error),
        );
      }
    }
  }
}

const args = parseArgs(process.argv.slice(2));

try {
  await main(args);
} catch (error) {
  exitCode = 1;
  console.error(
    "\nSmoke test berhenti:",
    error instanceof Error ? error.stack : error,
  );
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

  process.exitCode = exitCode || (failed > 0 ? 1 : 0);
}
