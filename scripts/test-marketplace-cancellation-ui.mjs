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
const FIXTURE_PREFIX = "marketplace-cancellation-ui-smoke:";

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
let eventSequence = 0;
const eventClockBase = Date.now();

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

function formHasInput(formHtml, name) {
  const tags = formHtml.match(/<input\b[^>]*>/gi) ?? [];

  return tags.some((tag) => parseAttributes(tag).name === name);
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

function nextEventDate() {
  eventSequence += 1;
  return new Date(eventClockBase + eventSequence * 120_000);
}

function jakartaDateTimeLocal(date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );

  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

function occurredAtFromDraft(draft) {
  return `${draft.occurredAt}:00+07:00`;
}

function cancellationMetadata(runId, fixture) {
  return {
    source: "marketplace-cancellation-ui-smoke",
    version: 1,
    runId,
    fixture,
    temporary: true,
  };
}

async function applyMarketplaceEvent({
  eventType,
  eventRef,
  orderRef,
  productId,
  quantity,
  sourceLineRef,
  occurredAt,
  runId,
  fixture,
}) {
  return rpc("apply_marketplace_event", {
    p_organization_id: organizationId,
    p_idempotency_key:
      `${FIXTURE_PREFIX}${eventType.toLowerCase()}:${eventRef}`,
    p_channel_code: "SHOPEE",
    p_event_type: eventType,
    p_event_ref: eventRef,
    p_order_ref: orderRef,
    p_occurred_at: occurredAt,
    p_lines: [
      {
        productId,
        quantity,
        sourceLineRef,
      },
    ],
    p_note: `${fixture} ${eventType} for marketplace cancellation smoke.`,
    p_metadata: cancellationMetadata(runId, fixture),
  });
}

async function previewCancellationDirect(draft) {
  return rpc("preview_marketplace_cancellation", {
    p_organization_id: organizationId,
    p_channel_code: draft.channelCode,
    p_event_ref: draft.eventRef,
    p_order_ref: draft.orderRef,
    p_occurred_at: occurredAtFromDraft(draft),
    p_source_status: draft.sourceStatus,
    p_lines: draft.lines,
    p_note: draft.note,
    p_metadata: {
      source: "marketplace-cancellation-admin-ui",
      version: 1,
    },
  });
}

async function postCancellationDirect({
  draft,
  previewBasisHash,
  idempotencyKey,
  confirmation,
}) {
  return rpc("post_marketplace_cancellation", {
    p_organization_id: organizationId,
    p_idempotency_key: idempotencyKey,
    p_channel_code: draft.channelCode,
    p_event_ref: draft.eventRef,
    p_order_ref: draft.orderRef,
    p_occurred_at: occurredAtFromDraft(draft),
    p_source_status: draft.sourceStatus,
    p_lines: draft.lines,
    p_preview_basis_hash: previewBasisHash,
    p_confirmation: confirmation,
    p_note: draft.note,
    p_metadata: {
      source: "marketplace-cancellation-admin-ui",
      version: 1,
    },
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

function readCancellationEffect(eventRef) {
  return runSqlJson(`
select jsonb_build_object(
  'eventCount',
    (
      select count(*)
      from operations.marketplace_events event
      where event.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and event.external_event_ref = ${sqlLiteral(eventRef)}
        and event.event_type_code = 'CANCEL'
    ),
  'cancellationCount',
    (
      select count(distinct application.cancellation_id)
      from api.marketplace_cancellation_applications application
      where application.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and application.external_event_ref =
            ${sqlLiteral(eventRef)}
    ),
  'lineCount',
    (
      select count(distinct application.cancellation_line_id)
      from api.marketplace_cancellation_applications application
      where application.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and application.external_event_ref =
            ${sqlLiteral(eventRef)}
    ),
  'applicationCount',
    (
      select count(*)
      from api.marketplace_cancellation_applications application
      where application.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and application.external_event_ref =
            ${sqlLiteral(eventRef)}
    ),
  'reversalTransactionCount',
    (
      select count(distinct application.reversal_transaction_id)
      from api.marketplace_cancellation_applications application
      where application.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and application.external_event_ref =
            ${sqlLiteral(eventRef)}
        and application.reversal_transaction_id is not null
    ),
  'reversalLedgerEntryCount',
    (
      select count(distinct application.reversal_entry_id)
      from api.marketplace_cancellation_applications application
      where application.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and application.external_event_ref =
            ${sqlLiteral(eventRef)}
        and application.reversal_entry_id is not null
    )
);
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

async function readCandidate(orderRef, itemRef) {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  const rows = await restRows(
    "marketplace_cancellation_candidates" +
      `?organization_id=eq.${encodedOrganizationId}` +
      `&external_order_ref=eq.${encodeURIComponent(orderRef)}` +
      `&external_item_ref=eq.${encodeURIComponent(itemRef)}` +
      "&select=*",
  );

  return rows[0] ?? null;
}

async function readMarketplaceEvent(eventRef) {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  const rows = await restRows(
    "marketplace_events" +
      `?organization_id=eq.${encodedOrganizationId}` +
      `&external_event_ref=eq.${encodeURIComponent(eventRef)}` +
      "&select=*&limit=1",
  );

  return rows[0] ?? null;
}

async function readShipAllocations(eventId) {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  return restRows(
    "marketplace_ship_allocations" +
      `?organization_id=eq.${encodedOrganizationId}` +
      `&event_id=eq.${encodeURIComponent(eventId)}` +
      "&select=*&order=allocation_no.asc",
  );
}

async function readCancellationByEventRef(eventRef) {
  const encodedOrganizationId = encodeURIComponent(organizationId);
  const headers = await restRows(
    "marketplace_cancellations" +
      `?organization_id=eq.${encodedOrganizationId}` +
      `&external_event_ref=eq.${encodeURIComponent(eventRef)}` +
      "&select=*&limit=1",
  );
  const header = headers[0] ?? null;

  if (!header) {
    return { header: null, lines: [], applications: [] };
  }

  const encodedCancellationId = encodeURIComponent(
    header.cancellation_id,
  );
  const [lines, applications] = await Promise.all([
    restRows(
      "marketplace_cancellation_lines" +
        `?organization_id=eq.${encodedOrganizationId}` +
        `&cancellation_id=eq.${encodedCancellationId}` +
        "&select=*&order=line_no.asc",
    ),
    restRows(
      "marketplace_cancellation_applications" +
        `?organization_id=eq.${encodedOrganizationId}` +
        `&cancellation_id=eq.${encodedCancellationId}` +
        "&select=*&order=application_no.asc",
    ),
  ]);

  return { header, lines, applications };
}

async function selectSplitFixture() {
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
    const second = batches[1];
    const firstQuantity = Number(first.sellable_qty);
    const secondQuantity = Number(second.sellable_qty);

    if (firstQuantity < 2 || secondQuantity < 1) continue;

    const productRows = await restRows(
      "product_inventory" +
        `?organization_id=eq.${encodedOrganizationId}` +
        `&product_id=eq.${encodeURIComponent(first.product_id)}` +
        "&select=product_id,available_qty,sellable_qty,reserved_qty",
    );
    const product = productRows[0];

    if (!product) continue;

    const shipQuantity = firstQuantity + 1;

    if (Number(product.available_qty) < shipQuantity + 4) continue;

    return {
      productId: first.product_id,
      sku: first.sku,
      productName: first.product_name,
      batches: [first, second],
      shipQuantity,
    };
  }

  throw new Error(
    "Fixture membutuhkan produk dengan dua batch aktif, batch pertama minimal 2 unit, dan available stock mencukupi.",
  );
}

function normalizePreviewApplications(preview) {
  return preview.lines
    .flatMap((line) => line.applications)
    .filter(
      (application) =>
        application.effectCode === "POST_SHIPMENT_REVERSAL",
    )
    .map((application) => ({
      originalLedgerEntryId: application.originalLedgerEntryId,
      originalTransactionId: application.originalTransactionId,
      batchId: application.batchId,
      batchCode: application.batchCode,
      quantity: Number(application.quantity),
    }))
    .sort((left, right) =>
      `${left.originalLedgerEntryId}:${left.quantity}`.localeCompare(
        `${right.originalLedgerEntryId}:${right.quantity}`,
      ),
    );
}

function normalizePersistedApplications(applications) {
  return applications
    .filter(
      (application) =>
        application.effect_code === "POST_SHIPMENT_REVERSAL",
    )
    .map((application) => ({
      originalLedgerEntryId: application.original_ledger_entry_id,
      originalTransactionId: application.original_transaction_id,
      batchId: application.batch_id,
      batchCode: application.batch_code_snapshot,
      quantity: Number(application.quantity_applied),
    }))
    .sort((left, right) =>
      `${left.originalLedgerEntryId}:${left.quantity}`.localeCompare(
        `${right.originalLedgerEntryId}:${right.quantity}`,
      ),
    );
}

function relevantServerErrorText() {
  const combined = `${serverStdout}\n${serverStderr}`;
  const lines = combined
    .split(/\r?\n/)
    .filter((line) =>
      /Unhandled|TypeError|ReferenceError|Hydration failed|statusCode:\s*500|Internal Server Error/i.test(
        line,
      ),
    );

  return lines.join("\n");
}

async function cleanupOpenReservation({
  orderRef,
  itemRef,
  productId,
  runId,
  fixture,
}) {
  const candidate = await readCandidate(orderRef, itemRef);

  if (!candidate || Number(candidate.open_reserved_qty) <= 0) {
    return;
  }

  const eventRef = `${FIXTURE_PREFIX}cleanup-release:${randomUUID()}`;

  await applyMarketplaceEvent({
    eventType: "RELEASE",
    eventRef,
    orderRef,
    productId,
    quantity: Number(candidate.open_reserved_qty),
    sourceLineRef: itemRef,
    occurredAt: nextEventDate().toISOString(),
    runId,
    fixture,
  });
}

async function cleanupPostShipment({
  orderRef,
  itemRef,
  productId,
  fixture,
}) {
  const candidate = await readCandidate(orderRef, itemRef);

  if (
    !candidate ||
    Number(candidate.remaining_post_cancellable_qty) <= 0
  ) {
    return;
  }

  const eventRef = `${FIXTURE_PREFIX}cleanup-cancel:${randomUUID()}`;
  const draft = {
    channelCode: "SHOPEE",
    eventRef,
    orderRef,
    occurredAt: jakartaDateTimeLocal(nextEventDate()),
    sourceStatus: "CANCELLED_CLEANUP",
    lines: [
      {
        productId,
        orderItemRef: itemRef,
        phaseCode: "POST_SHIPMENT",
        quantity: Number(candidate.remaining_post_cancellable_qty),
        sourceLineRef: "CLEANUP-1",
      },
    ],
    note: `Cleanup seluruh sisa shipment untuk ${fixture}.`,
  };
  const preview = await previewCancellationDirect(draft);

  if (!preview?.eligible || !HASH_PATTERN.test(preview?.basisHash ?? "")) {
    throw new Error(
      `Cleanup post-shipment diblokir: ${JSON.stringify(preview)}`,
    );
  }

  await postCancellationDirect({
    draft,
    previewBasisHash: preview.basisHash,
    idempotencyKey: `${FIXTURE_PREFIX}cleanup:${randomUUID()}`,
    confirmation: true,
  });
}

async function main(args) {
  const runId = randomUUID();
  const preOrderRef = `${FIXTURE_PREFIX}pre-order:${runId}`;
  const preItemRef = `PRE-ITEM-${runId}`;
  const postOrderRef = `${FIXTURE_PREFIX}post-order:${runId}`;
  const postItemRef = `POST-ITEM-${runId}`;
  let fixture = null;
  let baselineSnapshot = null;

  console.log("== Preflight ==");

  const requiredPaths = [
    ".env.local",
    "package.json",
    "scripts/create-demo-admin.mjs",
    "scripts/test-marketplace-cancellation-ui.mjs",
    "src/app/marketplace/cancellations/actions.ts",
    "src/app/marketplace/cancellations/components/draft-form.tsx",
    "src/app/marketplace/cancellations/draft.ts",
    "src/app/marketplace/cancellations/page.tsx",
    "src/app/marketplace/page.tsx",
    "src/lib/supabase-rest.ts",
    "supabase/migrations/202607200008_marketplace_partial_cancellation.sql",
    "supabase/tests/045_marketplace_partial_cancellation.test.sql",
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
    "Setelah db reset, jalankan npm run demo:admin terlebih dahulu.",
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

  const cancellationUrl =
    `${args.baseUrl}/marketplace/cancellations`;
  const unauthenticated =
    await getUnauthenticated(cancellationUrl);

  assertTest(
    [302, 303, 307, 308].includes(
      unauthenticated.statusCode,
    ) &&
      String(unauthenticated.location ?? "").includes("/login"),
    "Halaman cancellation menolak sesi anonim",
    `Status=${unauthenticated.statusCode} ` +
      `Location=${unauthenticated.location ?? ""}`,
  );

  let page = await getPage(cancellationUrl);

  const cancellationReadyOrEmpty =
    containsText(page.html, "Tinjau dampak pembatalan") ||
    containsText(
      page.html,
      "Tidak ada item marketplace yang masih dapat dibatalkan",
    );

  assertTest(
    containsText(page.html, "Marketplace cancellation") &&
      cancellationReadyOrEmpty &&
      containsText(
        page.html,
        "Tanpa pemilihan batch manual",
      ),
    "Halaman authenticated cancellation dan empty state dirender",
  );

  const marketplacePage = await getPage(
    `${args.baseUrl}/marketplace`,
  );

  assertTest(
    containsText(
      marketplacePage.html,
      "Kelola pembatalan parsial",
    ),
    "Halaman Marketplace memiliki shortcut cancellation",
  );

  fixture = await selectSplitFixture();
  baselineSnapshot = await readInventorySnapshot(
    fixture.productId,
    fixture.batches.map((batch) => batch.batch_id),
  );

  console.log("\n== Pre-shipment partial cancellation ==");

  await applyMarketplaceEvent({
    eventType: "RESERVE",
    eventRef: `${FIXTURE_PREFIX}pre-reserve:${runId}`,
    orderRef: preOrderRef,
    productId: fixture.productId,
    quantity: 4,
    sourceLineRef: preItemRef,
    occurredAt: nextEventDate().toISOString(),
    runId,
    fixture: "pre-shipment",
  });

  const preDraft = {
    channelCode: "SHOPEE",
    eventRef: `${FIXTURE_PREFIX}pre-cancel:${runId}`,
    orderRef: preOrderRef,
    occurredAt: jakartaDateTimeLocal(nextEventDate()),
    sourceStatus: "CANCELLED_BEFORE_SHIPMENT",
    lines: [
      {
        productId: fixture.productId,
        orderItemRef: preItemRef,
        phaseCode: "PRE_SHIPMENT",
        quantity: 2,
        sourceLineRef: "UI-1",
      },
    ],
    note: null,
  };
  const preDirect = await previewCancellationDirect(preDraft);

  assertTest(
    preDirect?.eligible === true &&
      preDirect?.preShipmentQuantity === 2 &&
      preDirect?.postShipmentQuantity === 0 &&
      HASH_PATTERN.test(preDirect?.basisHash ?? "") &&
      preDirect?.lines?.[0]?.applications?.every(
        (application) =>
          application.effectCode ===
          "PRE_SHIPMENT_RELEASE",
      ),
    "RPC preview pre-shipment eligible dan stock-neutral",
    JSON.stringify(preDirect),
  );

  const preInventoryBefore = await readInventorySnapshot(
    fixture.productId,
    fixture.batches.map((batch) => batch.batch_id),
  );
  const preLedgerBefore = readLedgerWatermark();

  page = await invokeServerActionForm({
    pageUri: cancellationUrl,
    pageHtml: (await getPage(cancellationUrl)).html,
    marker: "Tinjau dampak pembatalan",
    fields: {
      draft: JSON.stringify(preDraft),
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(page.html, "Preview authoritative") &&
      containsText(page.html, "Sebelum shipment") &&
      containsText(page.html, "Release reservation") &&
      hasForm(page.html, "Lepaskan reservasi"),
    "UI merender preview pre-shipment dan commit form",
  );

  const preForm = findForm(page.html, "Lepaskan reservasi");
  const preHash = findInputValue(
    preForm,
    "previewBasisHash",
  );
  const preIntentId = findInputValue(preForm, "intentId");
  const preHiddenDraft = findInputValue(preForm, "draft");

  assertTest(
    preHash === preDirect.basisHash &&
      UUID_PATTERN.test(preIntentId) &&
      !formHasInput(preForm, "confirmation"),
    "Pre-shipment memakai exact basis hash tanpa konfirmasi reversal",
  );

  const preInventoryAfterPreview = await readInventorySnapshot(
    fixture.productId,
    fixture.batches.map((batch) => batch.batch_id),
  );
  const preLedgerAfterPreview = readLedgerWatermark();

  assertTest(
    JSON.stringify(preInventoryAfterPreview) ===
      JSON.stringify(preInventoryBefore) &&
      JSON.stringify(preLedgerAfterPreview) ===
        JSON.stringify(preLedgerBefore) &&
      readCancellationEffect(preDraft.eventRef).cancellationCount === 0,
    "Preview UI pre-shipment tidak menulis stok, ledger, atau dokumen",
  );

  const preSuccessPage = await invokeServerActionForm({
    pageUri: page.uri,
    pageHtml: page.html,
    marker: "Lepaskan reservasi",
    fields: {
      draft: preHiddenDraft,
      previewBasisHash: preHash,
      intentId: preIntentId,
    },
    baseUrl: args.baseUrl,
  });
  const preSuccessUrl = new URL(preSuccessPage.uri);
  const preCancellationId =
    preSuccessUrl.searchParams.get("cancellationId");
  const preEffect = readCancellationEffect(preDraft.eventRef);
  const preCandidate = await readCandidate(
    preOrderRef,
    preItemRef,
  );

  assertTest(
    UUID_PATTERN.test(preCancellationId ?? "") &&
      containsText(
        preSuccessPage.html,
        "dilepas dari reservasi tanpa pergerakan stok fisik",
      ) &&
      preEffect.eventCount === 1 &&
      preEffect.cancellationCount === 1 &&
      preEffect.lineCount === 1 &&
      preEffect.applicationCount === 1 &&
      preEffect.reversalTransactionCount === 0 &&
      preEffect.reversalLedgerEntryCount === 0 &&
      Number(preCandidate?.open_reserved_qty) === 2 &&
      Number(preCandidate?.pre_shipment_cancelled_qty) === 2,
    "Commit pre-shipment melepas quantity parsial tanpa ledger effect",
    JSON.stringify({ preEffect, preCandidate }),
  );

  const preRefreshPage = await getPage(preSuccessPage.uri);

  assertTest(
    containsText(
      preRefreshPage.html,
      "dilepas dari reservasi tanpa pergerakan stok fisik",
    ) &&
      containsText(preRefreshPage.html, preDraft.eventRef),
    "Feedback pre-shipment dan drill-down bertahan setelah refresh",
  );

  await invokeServerActionForm({
    pageUri: page.uri,
    pageHtml: page.html,
    marker: "Lepaskan reservasi",
    fields: {
      draft: preHiddenDraft,
      previewBasisHash: preHash,
      intentId: preIntentId,
    },
    baseUrl: args.baseUrl,
  });
  const preReplayEffect =
    readCancellationEffect(preDraft.eventRef);

  assertTest(
    JSON.stringify(preReplayEffect) === JSON.stringify(preEffect),
    "Replay pre-shipment idempotent tanpa domain effect kedua",
    JSON.stringify(preReplayEffect),
  );

  console.log("\n== Split shipment fixture ==");

  await applyMarketplaceEvent({
    eventType: "RESERVE",
    eventRef: `${FIXTURE_PREFIX}post-reserve:${runId}`,
    orderRef: postOrderRef,
    productId: fixture.productId,
    quantity: fixture.shipQuantity,
    sourceLineRef: postItemRef,
    occurredAt: nextEventDate().toISOString(),
    runId,
    fixture: "post-shipment",
  });

  const shipEventRef =
    `${FIXTURE_PREFIX}post-ship:${runId}`;

  await applyMarketplaceEvent({
    eventType: "SHIP",
    eventRef: shipEventRef,
    orderRef: postOrderRef,
    productId: fixture.productId,
    quantity: fixture.shipQuantity,
    sourceLineRef: postItemRef,
    occurredAt: nextEventDate().toISOString(),
    runId,
    fixture: "post-shipment",
  });

  const shipEvent = await readMarketplaceEvent(shipEventRef);
  const shipAllocations = await readShipAllocations(
    shipEvent?.event_id,
  );

  assertTest(
    UUID_PATTERN.test(shipEvent?.transaction_id ?? "") &&
      shipAllocations.length >= 2,
    "Shipment fixture memakai minimal dua alokasi FEFO",
    JSON.stringify({ shipEvent, shipAllocations }),
  );

  const lastAllocation =
    shipAllocations[shipAllocations.length - 1];
  const postCancelQuantity =
    Number(lastAllocation.quantity_allocated) + 1;

  assertTest(
    postCancelQuantity < fixture.shipQuantity,
    "Quantity cancellation post-shipment bersifat parsial",
    JSON.stringify({
      postCancelQuantity,
      shipped: fixture.shipQuantity,
    }),
  );

  console.log("\n== Post-shipment preview, confirmation, dan commit ==");

  const postDraft = {
    channelCode: "SHOPEE",
    eventRef: `${FIXTURE_PREFIX}post-cancel:${runId}`,
    orderRef: postOrderRef,
    occurredAt: jakartaDateTimeLocal(nextEventDate()),
    sourceStatus: "CANCELLED_AFTER_SHIPMENT",
    lines: [
      {
        productId: fixture.productId,
        orderItemRef: postItemRef,
        phaseCode: "POST_SHIPMENT",
        quantity: postCancelQuantity,
        sourceLineRef: "UI-1",
      },
    ],
    note: `Partial post-shipment cancellation ${runId}.`,
  };
  const postDirect = await previewCancellationDirect(postDraft);
  const postPreviewApplications =
    normalizePreviewApplications(postDirect);

  assertTest(
    postDirect?.eligible === true &&
      postDirect?.postShipmentQuantity ===
        postCancelQuantity &&
      postDirect?.preShipmentQuantity === 0 &&
      HASH_PATTERN.test(postDirect?.basisHash ?? "") &&
      postPreviewApplications.length >= 2,
    "RPC preview post-shipment eligible dan melintasi split batch",
    JSON.stringify(postDirect),
  );

  const postInventoryBeforePreview =
    await readInventorySnapshot(
      fixture.productId,
      fixture.batches.map((batch) => batch.batch_id),
    );
  const postLedgerBeforePreview = readLedgerWatermark();

  const postPreviewPage = await invokeServerActionForm({
    pageUri: cancellationUrl,
    pageHtml: (await getPage(cancellationUrl)).html,
    marker: "Tinjau dampak pembatalan",
    fields: {
      draft: JSON.stringify(postDraft),
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      postPreviewPage.html,
      "Batch dan ledger shipment yang akan dibalik",
    ) &&
      postPreviewApplications.every(
        (application) =>
          containsText(
            postPreviewPage.html,
            application.batchCode,
          ) &&
          containsText(
            postPreviewPage.html,
            application.originalLedgerEntryId,
          ),
      ) &&
      hasForm(
        postPreviewPage.html,
        "Posting reversal pembatalan",
      ),
    "UI menampilkan exact original batch dan ledger restoration",
  );

  const postForm = findForm(
    postPreviewPage.html,
    "Posting reversal pembatalan",
  );
  const postHash = findInputValue(
    postForm,
    "previewBasisHash",
  );
  const postIntentId = findInputValue(postForm, "intentId");
  const postHiddenDraft = findInputValue(postForm, "draft");

  assertTest(
    postHash === postDirect.basisHash &&
      UUID_PATTERN.test(postIntentId) &&
      formHasInput(postForm, "confirmation"),
    "Post-shipment memakai exact basis hash dan explicit confirmation",
  );

  const postInventoryAfterPreview =
    await readInventorySnapshot(
      fixture.productId,
      fixture.batches.map((batch) => batch.batch_id),
    );
  const postLedgerAfterPreview = readLedgerWatermark();

  assertTest(
    JSON.stringify(postInventoryAfterPreview) ===
      JSON.stringify(postInventoryBeforePreview) &&
      JSON.stringify(postLedgerAfterPreview) ===
        JSON.stringify(postLedgerBeforePreview) &&
      readCancellationEffect(postDraft.eventRef).cancellationCount ===
        0,
    "Preview UI post-shipment tetap stock-neutral",
  );

  const missingConfirmationPage =
    await invokeServerActionForm({
      pageUri: postPreviewPage.uri,
      pageHtml: postPreviewPage.html,
      marker: "Posting reversal pembatalan",
      fields: {
        draft: postHiddenDraft,
        previewBasisHash: postHash,
        intentId: postIntentId,
      },
      baseUrl: args.baseUrl,
    });
  const missingConfirmationEffect =
    readCancellationEffect(postDraft.eventRef);

  assertTest(
    containsText(
      missingConfirmationPage.html,
      "Konfirmasi final wajib dicentang",
    ) &&
      missingConfirmationEffect.cancellationCount === 0 &&
      missingConfirmationEffect.reversalLedgerEntryCount === 0,
    "Server Action menolak post-shipment tanpa konfirmasi",
    JSON.stringify(missingConfirmationEffect),
  );

  const postSuccessPage = await invokeServerActionForm({
    pageUri: postPreviewPage.uri,
    pageHtml: postPreviewPage.html,
    marker: "Posting reversal pembatalan",
    fields: {
      draft: postHiddenDraft,
      previewBasisHash: postHash,
      intentId: postIntentId,
      confirmation: "on",
    },
    baseUrl: args.baseUrl,
  });
  const postSuccessUrl = new URL(postSuccessPage.uri);
  const postCancellationId =
    postSuccessUrl.searchParams.get("cancellationId");
  const postTransactionId =
    postSuccessUrl.searchParams.get("transactionId");
  const postPersisted = await readCancellationByEventRef(
    postDraft.eventRef,
  );
  const postEffect =
    readCancellationEffect(postDraft.eventRef);
  const postPersistedApplications =
    normalizePersistedApplications(
      postPersisted.applications,
    );

  assertTest(
    UUID_PATTERN.test(postCancellationId ?? "") &&
      UUID_PATTERN.test(postTransactionId ?? "") &&
      containsText(
        postSuccessPage.html,
        "dipulihkan ke batch shipment asal",
      ) &&
      postEffect.eventCount === 1 &&
      postEffect.cancellationCount === 1 &&
      postEffect.lineCount === 1 &&
      postEffect.applicationCount >= 2 &&
      postEffect.reversalTransactionCount === 1 &&
      postEffect.reversalLedgerEntryCount >= 2,
    "Commit post-shipment membuat exact linked reversal",
    JSON.stringify({
      postEffect,
      uri: postSuccessPage.uri,
    }),
  );

  assertTest(
    JSON.stringify(postPersistedApplications) ===
      JSON.stringify(postPreviewApplications),
    "Persisted cancellation applications tepat sama dengan preview",
    JSON.stringify({
      preview: postPreviewApplications,
      persisted: postPersistedApplications,
    }),
  );

  const postRefreshPage = await getPage(postSuccessPage.uri);

  assertTest(
    containsText(
      postRefreshPage.html,
      postPersisted.header.cancellation_no,
    ) &&
      postPersisted.applications.every(
        (application) =>
          containsText(
            postRefreshPage.html,
            application.original_transaction_no ?? "non-physical",
          ) &&
          containsText(
            postRefreshPage.html,
            application.batch_code_snapshot ?? "—",
          ),
      ),
    "Refresh-safe drill-down menampilkan shipment, reversal, dan batch",
  );

  await invokeServerActionForm({
    pageUri: postPreviewPage.uri,
    pageHtml: postPreviewPage.html,
    marker: "Posting reversal pembatalan",
    fields: {
      draft: postHiddenDraft,
      previewBasisHash: postHash,
      intentId: postIntentId,
      confirmation: "on",
    },
    baseUrl: args.baseUrl,
  });
  const postReplayEffect =
    readCancellationEffect(postDraft.eventRef);

  assertTest(
    JSON.stringify(postReplayEffect) === JSON.stringify(postEffect),
    "Replay post-shipment idempotent tanpa double reversal",
    JSON.stringify(postReplayEffect),
  );

  console.log("\n== Blocker over-cancellation ==");

  const blockedDraft = {
    channelCode: "SHOPEE",
    eventRef: `${FIXTURE_PREFIX}blocked:${runId}`,
    orderRef: postOrderRef,
    occurredAt: jakartaDateTimeLocal(nextEventDate()),
    sourceStatus: "CANCELLED_AFTER_SHIPMENT",
    lines: [
      {
        productId: fixture.productId,
        orderItemRef: postItemRef,
        phaseCode: "POST_SHIPMENT",
        quantity: fixture.shipQuantity + 1,
        sourceLineRef: "UI-1",
      },
    ],
    note: `Intentional blocker ${runId}.`,
  };
  const blockedBefore =
    readCancellationEffect(blockedDraft.eventRef);
  const blockedPage = await invokeServerActionForm({
    pageUri: cancellationUrl,
    pageHtml: (await getPage(cancellationUrl)).html,
    marker: "Tinjau dampak pembatalan",
    fields: {
      draft: JSON.stringify(blockedDraft),
    },
    baseUrl: args.baseUrl,
  });
  const blockedAfter =
    readCancellationEffect(blockedDraft.eventRef);

  assertTest(
    containsText(blockedPage.html, "Diblokir") &&
      !hasForm(
        blockedPage.html,
        "Posting reversal pembatalan",
      ) &&
      JSON.stringify(blockedAfter) === JSON.stringify(blockedBefore),
    "Over-cancellation diblokir tanpa final action atau domain effect",
    JSON.stringify(blockedAfter),
  );

  const serverErrors = relevantServerErrorText();

  assertTest(
    serverErrors === "",
    "Tidak ada error relevan pada Next.js server",
    serverErrors,
  );

  await cleanupOpenReservation({
    orderRef: preOrderRef,
    itemRef: preItemRef,
    productId: fixture.productId,
    runId,
    fixture: "pre-shipment",
  });
  await cleanupPostShipment({
    orderRef: postOrderRef,
    itemRef: postItemRef,
    productId: fixture.productId,
    fixture: "post-shipment",
  });

  const finalSnapshot = await readInventorySnapshot(
    fixture.productId,
    fixture.batches.map((batch) => batch.batch_id),
  );

  const baselineQuantityState = {
    product: {
      productId: baselineSnapshot.product.product_id,
      sellableQty: Number(
        baselineSnapshot.product.sellable_qty,
      ),
      reservedQty: Number(
        baselineSnapshot.product.reserved_qty,
      ),
      availableQty: Number(
        baselineSnapshot.product.available_qty,
      ),
    },
    batches: baselineSnapshot.batches
      .map((batch) => ({
        batchId: batch.batch_id,
        batchCode: batch.batch_code,
        sellableQty: Number(batch.sellable_qty),
      }))
      .sort((left, right) =>
        left.batchId.localeCompare(right.batchId),
      ),
  };
  const finalQuantityState = {
    product: {
      productId: finalSnapshot.product.product_id,
      sellableQty: Number(
        finalSnapshot.product.sellable_qty,
      ),
      reservedQty: Number(
        finalSnapshot.product.reserved_qty,
      ),
      availableQty: Number(
        finalSnapshot.product.available_qty,
      ),
    },
    batches: finalSnapshot.batches
      .map((batch) => ({
        batchId: batch.batch_id,
        batchCode: batch.batch_code,
        sellableQty: Number(batch.sellable_qty),
      }))
      .sort((left, right) =>
        left.batchId.localeCompare(right.batchId),
      ),
  };
  const baselineBatchWatermarks = new Map(
    baselineSnapshot.batches.map((batch) => [
      batch.batch_id,
      Number(batch.last_ledger_seq),
    ]),
  );
  const ledgerWatermarksAdvanced =
    Number(finalSnapshot.product.last_ledger_seq) >
      Number(baselineSnapshot.product.last_ledger_seq) &&
    finalSnapshot.batches.every(
      (batch) =>
        Number(batch.last_ledger_seq) >
        Number(
          baselineBatchWatermarks.get(batch.batch_id) ?? 0,
        ),
    );

  assertTest(
    JSON.stringify(finalQuantityState) ===
      JSON.stringify(baselineQuantityState) &&
      ledgerWatermarksAdvanced,
    "Cleanup memulihkan quantity stok dan mempertahankan ledger append-only",
    JSON.stringify({
      baseline: baselineSnapshot,
      final: finalSnapshot,
      baselineQuantityState,
      finalQuantityState,
      ledgerWatermarksAdvanced,
    }),
  );
}

const args = parseArgs(process.argv.slice(2));

try {
  await main(args);
} catch (error) {
  exitCode = 1;
  addResult(
    "Smoke test marketplace cancellation selesai tanpa exception",
    false,
    error instanceof Error ? error.stack ?? error.message : String(error),
  );

  if (ownedServer) {
    showServerLogs();
  }
} finally {
  try {
    if (organizationId && accessToken) {
      const runId = randomUUID();
      const productRows = await restRows(
        "marketplace_cancellation_candidates" +
          `?organization_id=eq.${encodeURIComponent(organizationId)}` +
          `&external_order_ref=like.${encodeURIComponent(FIXTURE_PREFIX)}*` +
          "&select=external_order_ref,external_item_ref,product_id," +
          "open_reserved_qty,remaining_post_cancellable_qty",
      );

      for (const row of productRows) {
        try {
          if (Number(row.open_reserved_qty) > 0) {
            await cleanupOpenReservation({
              orderRef: row.external_order_ref,
              itemRef: row.external_item_ref,
              productId: row.product_id,
              runId,
              fixture: "best-effort-finally",
            });
          }

          if (Number(row.remaining_post_cancellable_qty) > 0) {
            await cleanupPostShipment({
              orderRef: row.external_order_ref,
              itemRef: row.external_item_ref,
              productId: row.product_id,
              fixture: "best-effort-finally",
  });
          }
        } catch (cleanupError) {
          addResult(
            `Best-effort cleanup ${row.external_order_ref}`,
            false,
            cleanupError instanceof Error
              ? cleanupError.message
              : String(cleanupError),
          );
        }
      }
    }
  } catch (cleanupError) {
    addResult(
      "Best-effort fixture cleanup",
      false,
      cleanupError instanceof Error
        ? cleanupError.message
        : String(cleanupError),
    );
  }

  stopOwnedServer(args.keepServerRunning);

  console.log("\n== Ringkasan ==");
  console.table(results);

  if (exitCode !== 0) {
    process.exitCode = exitCode;
  }
}
