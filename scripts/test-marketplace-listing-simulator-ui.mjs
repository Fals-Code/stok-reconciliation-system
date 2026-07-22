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
const FIXTURE_PREFIX = "marketplace-listing-simulator-ui-smoke:";

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
let eventClockBase = Date.now();
let listingId = null;
let orderRef = null;

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

function simulatorMetadata(runId, fixture) {
  return {
    source: "marketplace-listing-simulator-ui-smoke",
    version: 1,
    runId,
    fixture,
    temporary: true,
  };
}

async function readProductSnapshot(productId) {
  const rows = await restRows(
    "product_inventory" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&product_id=eq.${encodeURIComponent(productId)}` +
      "&select=product_id,sku,name,sellable_qty,reserved_qty,available_qty,last_ledger_seq" +
      "&limit=1",
  );

  if (!rows[0]) {
    throw new Error(`Projection produk tidak ditemukan: ${productId}`);
  }

  return rows[0];
}

async function readInventoryPair(products) {
  const entries = await Promise.all(
    products.map(async (product) => [
      product.product_id,
      await readProductSnapshot(product.product_id),
    ]),
  );

  return Object.fromEntries(entries);
}

function inventoryNumbers(snapshot) {
  return {
    sellable: Number(snapshot.sellable_qty),
    reserved: Number(snapshot.reserved_qty),
    available: Number(snapshot.available_qty),
    ledgerSeq: Number(snapshot.last_ledger_seq ?? 0),
  };
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

async function readNormalizations(targetOrderRef) {
  return restRows(
    "marketplace_listing_normalizations" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&external_order_ref_snapshot=eq.${encodeURIComponent(targetOrderRef)}` +
      "&select=*&order=source_line_no.asc,component_no.asc",
  );
}

async function readComponents(targetOrderRef) {
  return restRows(
    "marketplace_listing_component_lifecycle" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&external_order_ref=eq.${encodeURIComponent(targetOrderRef)}` +
      "&select=*&order=source_line_ref.asc,component_no.asc",
  );
}

async function readListing(targetListingId) {
  const rows = await restRows(
    "marketplace_listing_catalog" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&listing_id=eq.${encodeURIComponent(targetListingId)}` +
      "&select=*&limit=1",
  );

  return rows[0] ?? null;
}

async function readMarketplaceEvent(eventRef) {
  const rows = await restRows(
    "marketplace_events" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&external_event_ref=eq.${encodeURIComponent(eventRef)}` +
      "&select=*&limit=2",
  );

  return rows;
}

async function readShipAllocations(eventId) {
  return restRows(
    "marketplace_ship_allocations" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&event_id=eq.${encodeURIComponent(eventId)}` +
      "&select=*&order=allocation_no.asc",
  );
}

async function selectBundleProducts() {
  const rows = await restRows(
    "product_inventory" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      "&available_qty=gt.0" +
      "&select=product_id,sku,name,sellable_qty,reserved_qty,available_qty" +
      "&order=sku.asc",
  );
  const first = rows.find((row) => Number(row.available_qty) >= 6);
  const second = rows.find(
    (row) =>
      row.product_id !== first?.product_id &&
      Number(row.available_qty) >= 3,
  );

  if (!first || !second) {
    throw new Error(
      "Smoke test membutuhkan dua produk berbeda dengan available stock minimal 6 dan 3 unit.",
    );
  }

  return [first, second];
}

async function establishEventClock() {
  const [marketplaceRows, ledgerRows] = await Promise.all([
    restRows(
      "marketplace_events" +
        `?organization_id=eq.${encodeURIComponent(organizationId)}` +
        "&select=occurred_at&order=occurred_at.desc&limit=1",
    ),
    restRows(
      "stock_ledger" +
        `?organization_id=eq.${encodeURIComponent(organizationId)}` +
        "&select=occurred_at&order=occurred_at.desc&limit=1",
    ),
  ]);
  const latest = [
    Date.now(),
    marketplaceRows[0]?.occurred_at
      ? new Date(marketplaceRows[0].occurred_at).getTime()
      : 0,
    ledgerRows[0]?.occurred_at
      ? new Date(ledgerRows[0].occurred_at).getTime()
      : 0,
  ].filter(Number.isFinite);

  eventClockBase = Math.max(...latest) + 5 * 60_000;
}

async function createAndActivateBundle({
  runId,
  externalListingCode,
  displayName,
  products,
}) {
  const effectiveFrom = new Date(eventClockBase - 60 * 60_000).toISOString();
  const draft = await rpc("create_marketplace_listing_version_draft", {
    p_organization_id: organizationId,
    p_idempotency_key: `${FIXTURE_PREFIX}create:${runId}`,
    p_channel_code: "SHOPEE",
    p_external_listing_code: externalListingCode,
    p_display_name: displayName,
    p_listing_type_code: "BUNDLE",
    p_effective_from: effectiveFrom,
    p_product_id: null,
    p_components: [
      {
        productId: products[0].product_id,
        quantity: 2,
      },
      {
        productId: products[1].product_id,
        quantity: 1,
      },
    ],
    p_note: "Draft bundle untuk smoke normalized simulator.",
    p_metadata: simulatorMetadata(runId, "listing-draft"),
  });

  assertTest(
    draft?.status === "DRAFT_CREATED" &&
      UUID_PATTERN.test(draft?.listingId ?? "") &&
      UUID_PATTERN.test(draft?.versionId ?? ""),
    "Draft bundle fixture dibuat melalui Admin RPC",
    JSON.stringify(draft),
  );

  const preview = await rpc(
    "preview_marketplace_listing_version_activation",
    {
      p_organization_id: organizationId,
      p_listing_id: draft.listingId,
      p_version_id: draft.versionId,
    },
  );

  assertTest(
    preview?.eligible === true &&
      Number(preview?.componentCount) === 2 &&
      HASH_PATTERN.test(preview?.basisHash ?? "") &&
      Number(preview?.versionRowVersion) > 0,
    "Preview aktivasi bundle eligible dan memiliki basis hash",
    JSON.stringify(preview),
  );

  const activation = await rpc("activate_marketplace_listing_version", {
    p_organization_id: organizationId,
    p_idempotency_key: `${FIXTURE_PREFIX}activate:${runId}`,
    p_listing_id: draft.listingId,
    p_version_id: draft.versionId,
    p_expected_row_version: Number(preview.versionRowVersion),
    p_preview_basis_hash: preview.basisHash,
    p_confirmation: true,
  });

  assertTest(
    activation?.status === "ACTIVATED",
    "Bundle fixture diaktifkan dari preview exact",
    JSON.stringify(activation),
  );

  return {
    listingId: draft.listingId,
    versionId: draft.versionId,
  };
}

async function cancelRemainingOrder({
  runId,
  targetOrderRef,
  sourceLineRef,
}) {
  const components = await readComponents(targetOrderRef);
  const lines = [];

  for (const component of components) {
    const preQuantity = Number(component.open_reserved_quantity);
    const postQuantity = Math.max(
      0,
      Number(component.shipped_quantity) -
        Number(component.post_shipment_cancelled_quantity) -
        Number(component.return_expected_quantity),
    );

    if (preQuantity > 0) {
      lines.push({
        orderSourceLineRef: sourceLineRef,
        componentNo: Number(component.component_no),
        phaseCode: "PRE_SHIPMENT",
        quantity: preQuantity,
        cancellationLineRef:
          `CLEANUP-PRE-${component.component_no}-${runId}`,
      });
    }

    if (postQuantity > 0) {
      lines.push({
        orderSourceLineRef: sourceLineRef,
        componentNo: Number(component.component_no),
        phaseCode: "POST_SHIPMENT",
        quantity: postQuantity,
        cancellationLineRef:
          `CLEANUP-POST-${component.component_no}-${runId}`,
      });
    }
  }

  if (lines.length === 0) return null;

  const eventRef = `${FIXTURE_PREFIX}cleanup-cancel:${randomUUID()}`;
  const occurredAt = nextEventDate().toISOString();
  const body = {
    p_organization_id: organizationId,
    p_channel_code: "SHOPEE",
    p_event_ref: eventRef,
    p_order_ref: targetOrderRef,
    p_source_status: "CANCELLED_SMOKE_CLEANUP",
    p_occurred_at: occurredAt,
    p_received_at: occurredAt,
    p_lines: lines,
    p_note: "Cleanup normalized simulator smoke.",
    p_raw_payload: {
      eventRef,
      orderRef: targetOrderRef,
      lines,
    },
    p_metadata: simulatorMetadata(runId, "cleanup-cancellation"),
    p_schema_version: 1,
  };
  const preview = await rpc(
    "preview_marketplace_listing_cancellation",
    body,
  );

  if (
    preview?.eligible !== true ||
    !HASH_PATTERN.test(preview?.basisHash ?? "")
  ) {
    throw new Error(
      `Cleanup cancellation diblokir: ${JSON.stringify(preview)}`,
    );
  }

  const posted = await rpc("post_marketplace_listing_cancellation", {
    ...body,
    p_idempotency_key: `${FIXTURE_PREFIX}cleanup-post:${randomUUID()}`,
    p_preview_basis_hash: preview.basisHash,
    p_confirmation: true,
  });

  if (posted?.status !== "POSTED") {
    throw new Error(
      `Cleanup cancellation tidak POSTED: ${JSON.stringify(posted)}`,
    );
  }

  return posted;
}

async function archiveFixtureListing(runId, targetListingId) {
  if (!targetListingId) return;

  const listing = await readListing(targetListingId);

  if (!listing || listing.status_code === "ARCHIVED") return;

  await rpc("archive_marketplace_listing", {
    p_organization_id: organizationId,
    p_idempotency_key: `${FIXTURE_PREFIX}archive:${runId}`,
    p_listing_id: targetListingId,
    p_expected_row_version: Number(listing.row_version),
    p_confirmation: true,
  });

  const archived = await readListing(targetListingId);

  if (archived?.status_code !== "ARCHIVED") {
    throw new Error(
      `Listing cleanup tidak ARCHIVED: ${JSON.stringify(archived)}`,
    );
  }
}

async function main(args) {
  const runId = randomUUID();
  const shortRunId = runId.replaceAll("-", "").slice(0, 12).toUpperCase();
  const externalListingCode = `SHP-000-UI-BUNDLE-${shortRunId}`;
  const displayName = `Smoke Bundle ${shortRunId}`;
  orderRef = `${FIXTURE_PREFIX}order:${runId}`;
  const sourceLineRef = `SRC-${shortRunId}`;
  const reserveEventRef = `${FIXTURE_PREFIX}reserve:${runId}`;
  const shipEventRef = `${FIXTURE_PREFIX}ship:${runId}`;
  let products = [];
  let baselineInventory = null;

  console.log("== Preflight ==");

  const requiredPaths = [
    ".env.local",
    "package.json",
    "scripts/create-demo-admin.mjs",
    "scripts/test-marketplace-listing-simulator-ui.mjs",
    "src/app/actions.ts",
    "src/app/marketplace/page.tsx",
    "src/lib/supabase-rest.ts",
    "supabase/migrations/202607220013_marketplace_listing_recipe_foundation.sql",
    "supabase/migrations/202607220014_marketplace_listing_event_normalization.sql",
    "supabase/migrations/202607220015_marketplace_listing_downstream_lifecycle.sql",
    "supabase/migrations/202607220016_marketplace_listing_admin_lifecycle.sql",
    "supabase/tests/049_marketplace_listing_recipe_foundation.test.sql",
    "supabase/tests/050_marketplace_listing_event_normalization.test.sql",
    "supabase/tests/051_marketplace_listing_downstream_lifecycle.test.sql",
    "supabase/tests/052_marketplace_listing_admin_lifecycle.test.sql",
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

  console.log("\n== Provision dan autentikasi Admin smoke ==");

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

  await establishEventClock();

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

  const marketplaceUrl = `${args.baseUrl}/marketplace`;
  const unauthenticated = await getUnauthenticated(marketplaceUrl);

  assertTest(
    [302, 303, 307, 308].includes(
      unauthenticated.statusCode,
    ) &&
      String(unauthenticated.location ?? "").includes("/login"),
    "Halaman marketplace menolak sesi anonim",
    `Status=${unauthenticated.statusCode} ` +
      `Location=${unauthenticated.location ?? ""}`,
  );

  console.log("\n== Fixture listing bundle aktif ==");

  products = await selectBundleProducts();
  baselineInventory = await readInventoryPair(products);
  const baselineLedger = readLedgerWatermark();
  const fixture = await createAndActivateBundle({
    runId,
    externalListingCode,
    displayName,
    products,
  });
  listingId = fixture.listingId;

  const activeListing = await readListing(listingId);

  assertTest(
    activeListing?.status_code === "ACTIVE" &&
      activeListing?.mapping_readiness_code === "PUBLISHED" &&
      activeListing?.listing_type_code === "BUNDLE" &&
      Number(activeListing?.current_version) === 1,
    "Read model listing menampilkan bundle aktif versi 1",
    JSON.stringify(activeListing),
  );

  let page = await getPage(marketplaceUrl);

  assertTest(
    containsText(
      page.html,
      "Listing marketplace dinormalisasi sebelum reservasi dan shipment",
    ) &&
      containsText(page.html, "Reserve listing marketplace") &&
      containsText(page.html, "Ship komponen hasil ekspansi") &&
      containsText(page.html, externalListingCode),
    "Halaman normalized simulator merender listing aktif",
  );

  assertTest(
    page.html.includes('name="marketplaceListingSelection"') &&
      page.html.includes('name="listingQuantity"') &&
      !page.html.includes('name="productId"') &&
      !page.html.includes('<option value="RELEASE">'),
    "Form memakai identitas listing dan tidak mengekspos kontrak lama",
  );

  console.log("\n== Reserve melalui Server Action normalized ==");

  const reserveOccurredAt = nextEventDate();
  const listingSelection = JSON.stringify({
    channelCode: "SHOPEE",
    externalListingCode,
    listingName: displayName,
    listingType: "BUNDLE",
  });
  const reserveFields = {
    marketplaceListingSelection: listingSelection,
    occurredAt: jakartaDateTimeLocal(reserveOccurredAt),
    orderRef,
    eventRef: reserveEventRef,
    sourceLineRef,
    listingQuantity: 2,
    note: "Reserve bundle melalui focused UI smoke.",
  };

  page = await invokeServerActionForm({
    pageUri: marketplaceUrl,
    pageHtml: page.html,
    marker: "Reserve listing marketplace",
    fields: reserveFields,
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(page.html, orderRef) &&
      containsText(page.html, "2 komponen") &&
      containsText(page.html, "6 unit"),
    "Redirect reserve menampilkan feedback persisten",
  );

  const normalizations = await readNormalizations(orderRef);

  assertTest(
    normalizations.length === 2 &&
      normalizations.every(
        (row) =>
          row.external_listing_code_snapshot ===
            externalListingCode &&
          row.listing_type_code_snapshot === "BUNDLE" &&
          Number(row.mapping_version) === 1 &&
          Number(row.listing_quantity) === 2,
      ),
    "Bundle dinormalisasi menjadi dua immutable component snapshot",
    JSON.stringify(normalizations),
  );

  const byProduct = new Map(
    normalizations.map((row) => [row.product_id, row]),
  );
  const firstNormalized = byProduct.get(products[0].product_id);
  const secondNormalized = byProduct.get(products[1].product_id);

  assertTest(
    Number(firstNormalized?.unit_quantity_per_listing) === 2 &&
      Number(firstNormalized?.expanded_quantity) === 4 &&
      Number(secondNormalized?.unit_quantity_per_listing) === 1 &&
      Number(secondNormalized?.expanded_quantity) === 2,
    "Quantity listing dikalikan recipe component secara tepat",
    JSON.stringify(normalizations),
  );

  const afterReserveInventory = await readInventoryPair(products);
  const afterReserveLedger = readLedgerWatermark();
  const firstBaseline = inventoryNumbers(
    baselineInventory[products[0].product_id],
  );
  const secondBaseline = inventoryNumbers(
    baselineInventory[products[1].product_id],
  );
  const firstAfterReserve = inventoryNumbers(
    afterReserveInventory[products[0].product_id],
  );
  const secondAfterReserve = inventoryNumbers(
    afterReserveInventory[products[1].product_id],
  );

  assertTest(
    firstAfterReserve.sellable === firstBaseline.sellable &&
      secondAfterReserve.sellable === secondBaseline.sellable &&
      firstAfterReserve.reserved === firstBaseline.reserved + 4 &&
      secondAfterReserve.reserved === secondBaseline.reserved + 2 &&
      firstAfterReserve.available === firstBaseline.available - 4 &&
      secondAfterReserve.available === secondBaseline.available - 2 &&
      Number(afterReserveLedger.entryCount) ===
        Number(baselineLedger.entryCount) &&
      Number(afterReserveLedger.maxLedgerSeq) ===
        Number(baselineLedger.maxLedgerSeq),
    "Reserve bundle stock-neutral terhadap ledger dan stok fisik",
  );

  console.log("\n== Replay reserve idempotent ==");

  const reserveReplayBefore = await readInventoryPair(products);
  const reserveReplayPage = await invokeServerActionForm({
    pageUri: marketplaceUrl,
    pageHtml: (await getPage(marketplaceUrl)).html,
    marker: "Reserve listing marketplace",
    fields: reserveFields,
    baseUrl: args.baseUrl,
  });
  const reserveReplayAfter = await readInventoryPair(products);
  const normalizationsAfterReplay = await readNormalizations(orderRef);

  assertTest(
    containsText(reserveReplayPage.html, orderRef) &&
      JSON.stringify(reserveReplayAfter) ===
        JSON.stringify(reserveReplayBefore) &&
      normalizationsAfterReplay.length === 2,
    "Duplicate reserve mengembalikan effect yang sama tanpa double-count",
  );

  console.log("\n== Shipment canonical component melalui Server Action ==");

  const componentBeforeShip = (
    await readComponents(orderRef)
  ).find((row) => Number(row.component_no) === 1);

  assertTest(
    componentBeforeShip &&
      Number(componentBeforeShip.open_reserved_quantity) === 4 &&
      componentBeforeShip.product_id === products[0].product_id,
    "Canonical component pertama tersedia untuk shipment",
    JSON.stringify(componentBeforeShip),
  );

  const shipOccurredAt = nextEventDate();
  const shipSelection = JSON.stringify({
    channelCode: "SHOPEE",
    orderRef,
    orderSourceLineRef: sourceLineRef,
    componentNo: 1,
  });
  const shipFields = {
    marketplaceSelection: shipSelection,
    occurredAt: jakartaDateTimeLocal(shipOccurredAt),
    eventRef: shipEventRef,
    quantity: 1,
    note: "Ship satu canonical component melalui UI smoke.",
  };

  const shipPage = await invokeServerActionForm({
    pageUri: marketplaceUrl,
    pageHtml: (await getPage(marketplaceUrl)).html,
    marker: "Ship komponen hasil ekspansi",
    fields: shipFields,
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(shipPage.html, "mengirim 1 unit") &&
      containsText(shipPage.html, "alokasi batch fefo"),
    "Redirect shipment menampilkan feedback persisten",
  );

  const shipEvents = await readMarketplaceEvent(shipEventRef);
  const shipEvent = shipEvents[0] ?? null;
  const allocations = shipEvent
    ? await readShipAllocations(shipEvent.event_id)
    : [];
  const componentsAfterShip = await readComponents(orderRef);
  const firstAfterShip = componentsAfterShip.find(
    (row) => Number(row.component_no) === 1,
  );
  const inventoryAfterShip = await readInventoryPair(products);
  const firstInventoryAfterShip = inventoryNumbers(
    inventoryAfterShip[products[0].product_id],
  );

  assertTest(
    shipEvents.length === 1 &&
      shipEvent?.event_type_code === "SHIP" &&
      UUID_PATTERN.test(shipEvent?.transaction_id ?? "") &&
      allocations.length >= 1 &&
      allocations.reduce(
        (sum, allocation) =>
          sum + Number(allocation.quantity_allocated),
        0,
      ) === 1 &&
      Number(firstAfterShip?.consumed_qty) === 1 &&
      Number(firstAfterShip?.shipped_quantity) === 1 &&
      Number(firstAfterShip?.open_reserved_quantity) === 3 &&
      firstInventoryAfterShip.sellable ===
        firstBaseline.sellable - 1 &&
      firstInventoryAfterShip.reserved ===
        firstBaseline.reserved + 3,
    "Shipment mengonsumsi reservasi dan menulis exact FEFO physical effect",
    JSON.stringify({
      shipEvent,
      allocations,
      firstAfterShip,
      firstInventoryAfterShip,
    }),
  );

  console.log("\n== Replay shipment idempotent ==");

  const shipReplayInventoryBefore = await readInventoryPair(products);
  const shipReplayLedgerBefore = readLedgerWatermark();
  await invokeServerActionForm({
    pageUri: marketplaceUrl,
    pageHtml: (await getPage(marketplaceUrl)).html,
    marker: "Ship komponen hasil ekspansi",
    fields: shipFields,
    baseUrl: args.baseUrl,
  });
  const shipReplayInventoryAfter = await readInventoryPair(products);
  const shipReplayLedgerAfter = readLedgerWatermark();
  const shipEventsAfterReplay = await readMarketplaceEvent(shipEventRef);

  assertTest(
    JSON.stringify(shipReplayInventoryAfter) ===
      JSON.stringify(shipReplayInventoryBefore) &&
      JSON.stringify(shipReplayLedgerAfter) ===
        JSON.stringify(shipReplayLedgerBefore) &&
      shipEventsAfterReplay.length === 1,
    "Duplicate shipment tidak menggandakan ledger atau event",
  );

  console.log("\n== Cleanup melalui normalized cancellation dan archive ==");

  const cleanupResult = await cancelRemainingOrder({
    runId,
    targetOrderRef: orderRef,
    sourceLineRef,
  });

  assertTest(
    cleanupResult?.status === "POSTED",
    "Cleanup memakai normalized cancellation POSTED",
    JSON.stringify(cleanupResult),
  );

  const componentsAfterCleanup = await readComponents(orderRef);

  assertTest(
    componentsAfterCleanup.length === 2 &&
      componentsAfterCleanup.every(
        (row) => Number(row.open_reserved_quantity) === 0,
      ) &&
      Number(
        componentsAfterCleanup.find(
          (row) => Number(row.component_no) === 1,
        )?.post_shipment_cancelled_quantity,
      ) === 1,
    "Cleanup melepas reservasi dan membalik shipment secara exact",
    JSON.stringify(componentsAfterCleanup),
  );

  await archiveFixtureListing(runId, listingId);
  const archivedListing = await readListing(listingId);

  assertTest(
    archivedListing?.status_code === "ARCHIVED",
    "Listing fixture diarsipkan tanpa menghapus snapshot order",
    JSON.stringify(archivedListing),
  );

  const finalInventory = await readInventoryPair(products);

  assertTest(
    products.every((product) => {
      const baseline = inventoryNumbers(
        baselineInventory[product.product_id],
      );
      const final = inventoryNumbers(
        finalInventory[product.product_id],
      );

      return (
        final.sellable === baseline.sellable &&
        final.reserved === baseline.reserved &&
        final.available === baseline.available
      );
    }),
    "Inventory fisik dan reservasi kembali ke baseline setelah cleanup",
    JSON.stringify({ baselineInventory, finalInventory }),
  );

  const finalPage = await getPage(marketplaceUrl);

  assertTest(
    containsText(finalPage.html, orderRef) &&
      containsText(finalPage.html, externalListingCode) &&
      containsText(finalPage.html, "BUNDLE v1") &&
      !containsText(
        finalPage.html,
        "Data marketplace gagal dimuat",
      ),
    "Refresh mempertahankan order, mapping version, dan audit snapshot",
  );

  const serverErrors = relevantServerErrorText();

  assertTest(
    serverErrors.length === 0,
    "Tidak ada error runtime atau hydration pada server",
    serverErrors,
  );
}

const args = parseArgs(process.argv.slice(2));

try {
  await main(args);
} catch (error) {
  exitCode = 1;
  console.error(
    "\nSmoke test gagal:",
    error instanceof Error ? error.stack : error,
  );
  showServerLogs();
} finally {
  try {
    if (organizationId && accessToken && orderRef) {
      await cancelRemainingOrder({
        runId: randomUUID(),
        targetOrderRef: orderRef,
        sourceLineRef:
          (await readComponents(orderRef))[0]?.source_line_ref ?? "",
      });
    }
  } catch (cleanupError) {
    console.error(
      "Best-effort order cleanup gagal:",
      cleanupError instanceof Error
        ? cleanupError.message
        : String(cleanupError),
    );
    exitCode = 1;
  }

  try {
    if (organizationId && accessToken && listingId) {
      await archiveFixtureListing(randomUUID(), listingId);
    }
  } catch (cleanupError) {
    console.error(
      "Best-effort listing archive gagal:",
      cleanupError instanceof Error
        ? cleanupError.message
        : String(cleanupError),
    );
    exitCode = 1;
  }

  stopOwnedServer(args.keepServerRunning);

  console.log("\n== Ringkasan ==");
  console.table(results);

  if (exitCode !== 0) {
    process.exitCode = exitCode;
  }
}
