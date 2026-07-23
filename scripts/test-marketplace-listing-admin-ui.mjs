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

function findInputValue(formHtml, name) {
  const inputs = formHtml.match(/<input\b[^>]*>/gi) ?? [];

  for (const input of inputs) {
    const nameMatch = input.match(/\bname="([^"]*)"/i);

    if (!nameMatch || decodeHtml(nameMatch[1]) !== name) continue;

    const valueMatch = input.match(/\bvalue="([^"]*)"/i);
    return valueMatch ? decodeHtml(valueMatch[1]) : "";
  }

  throw new Error(`Input "${name}" tidak ditemukan pada form.`);
}

function hasForm(html, marker) {
  const forms = html.match(/<form\b[^>]*>.*?<\/form>/gis) ?? [];
  const normalizedMarker = normalizeRenderedText(marker);

  return forms.some((candidate) =>
    normalizeRenderedText(candidate).includes(normalizedMarker),
  );
}

function readStockNeutralSnapshot() {
  return runSqlJson(`
select jsonb_build_object(
  'reservationCount',
    (
      select count(*)
      from inventory.stock_reservations
      where organization_id = ${sqlLiteral(organizationId)}::uuid
    ),
  'transactionCount',
    (
      select count(*)
      from inventory.stock_transactions
      where organization_id = ${sqlLiteral(organizationId)}::uuid
    ),
  'ledgerCount',
    (
      select count(*)
      from inventory.stock_ledger_entries
      where organization_id = ${sqlLiteral(organizationId)}::uuid
    ),
  'products',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'productId', product_id,
            'sellable', sellable_qty,
            'quarantine', quarantine_qty,
            'damaged', damaged_qty,
            'reserved', reserved_qty,
            'available', available_qty,
            'lastLedgerSeq', last_ledger_seq
          )
          order by product_id
        )
        from api.product_inventory
        where organization_id = ${sqlLiteral(organizationId)}::uuid
      ),
      '[]'::jsonb
    )
);
`);
}

async function readListingByCode(channelCode, externalListingCode) {
  const rows = await restRows(
    "marketplace_listing_catalog" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&channel_code=eq.${encodeURIComponent(channelCode)}` +
      `&external_listing_code=eq.${encodeURIComponent(externalListingCode)}` +
      "&select=*&limit=2",
  );

  return rows;
}

async function readListingVersions(targetListingId) {
  return restRows(
    "marketplace_listing_versions" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&listing_id=eq.${encodeURIComponent(targetListingId)}` +
      "&select=*&order=version.asc",
  );
}

async function readRecipeComponents(targetListingId) {
  return restRows(
    "marketplace_bundle_recipe_components" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&listing_id=eq.${encodeURIComponent(targetListingId)}` +
      "&select=*&order=version.asc,line_no.asc",
  );
}

async function selectActiveProducts() {
  const rows = await restRows(
    "product_inventory" +
      `?organization_id=eq.${encodeURIComponent(organizationId)}` +
      "&is_active=eq.true" +
      "&select=product_id,sku,name,is_active,sellable_qty,reserved_qty,available_qty" +
      "&order=sku.asc&limit=20",
  );

  if (rows.length < 2) {
    throw new Error(
      "Smoke Admin listing membutuhkan minimal dua produk aktif.",
    );
  }

  return rows.slice(0, 2);
}

function setProductActive(productId, active) {
  runSql(`
update catalog.products
set is_active = ${active ? "true" : "false"}
where organization_id = ${sqlLiteral(organizationId)}::uuid
  and id = ${sqlLiteral(productId)}::uuid;
`);
}

function listingDetailUrl(baseUrl, listingId, versionId = null) {
  const uri = new URL("/marketplace/listings", baseUrl);
  uri.searchParams.set("selectedListingId", listingId);

  if (versionId) {
    uri.searchParams.set("selectedVersionId", versionId);
  }

  uri.hash = "version-detail";
  return uri.toString();
}

function listingPreviewUrl(baseUrl, listingId, versionId) {
  const uri = new URL("/marketplace/listings", baseUrl);
  uri.searchParams.set("selectedListingId", listingId);
  uri.searchParams.set("selectedVersionId", versionId);
  uri.searchParams.set("previewListingId", listingId);
  uri.searchParams.set("previewVersionId", versionId);
  uri.hash = "activation-preview";
  return uri.toString();
}

function cloneListingUrl(baseUrl, listingId) {
  const uri = new URL("/marketplace/listings", baseUrl);
  uri.searchParams.set("cloneListingId", listingId);
  uri.hash = "listing-draft";
  return uri.toString();
}

async function main(args) {
  const runId = randomUUID();
  const shortRunId = runId.replaceAll("-", "").slice(0, 12).toUpperCase();
  const externalListingCode = `SHP-ADMIN-BUNDLE-${shortRunId}`;
  const displayName = `Admin Bundle ${shortRunId}`;
  const adminUrl = `${args.baseUrl}/marketplace/listings`;

  console.log("== Preflight ==");

  const requiredPaths = [
    ".env.local",
    "package.json",
    "scripts/create-demo-admin.mjs",
    "scripts/test-marketplace-listing-admin-ui.mjs",
    "scripts/test-marketplace-listing-simulator-ui.mjs",
    "src/app/app-shell/navigation.ts",
    "src/app/marketplace/page.tsx",
    "src/app/marketplace/listings/actions.ts",
    "src/app/marketplace/listings/components/listing-draft-form.tsx",
    "src/app/marketplace/listings/draft.ts",
    "src/app/marketplace/listings/page.tsx",
    "src/lib/supabase-rest.ts",
    "supabase/migrations/202607220016_marketplace_listing_admin_lifecycle.sql",
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
      throw new Error(`BaseUrl nonlokal ditolak: ${args.baseUrl}.`);
    }

    if (!isLoopback(supabaseUri.hostname)) {
      throw new Error(`Supabase nonlokal ditolak: ${supabaseUrl}.`);
    }
  }

  assertTest(
    Boolean(
      publishableKey &&
        !publishableKey.includes("REPLACE_ME"),
    ),
    "Publishable key lokal tersedia",
  );
  assertTest(
    Boolean(serviceKey && !serviceKey.includes("REPLACE_ME")),
    "Service key lokal tersedia",
  );

  dbContainer = resolveDbContainer();
  assertTest(
    Boolean(dbContainer),
    "Database Supabase lokal ditemukan",
    dbContainer,
  );

  console.log("\n== Provision dan autentikasi Admin ==");

  runCommand(
    process.execPath,
    [
      "scripts/create-demo-admin.mjs",
      "--email",
      args.email,
      "--password",
      args.password,
      "--name",
      args.displayName,
    ],
    {
      printStdout: true,
      printStderr: true,
    },
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

  assertTest(
    tokenResponse.ok && Boolean(tokenPayload?.access_token),
    "Password grant menghasilkan access token",
    tokenResponse.ok
      ? `User=${String(tokenPayload?.user?.id ?? "")}`
      : JSON.stringify(tokenPayload),
  );

  accessToken = String(tokenPayload.access_token);
  smokeUserId = String(tokenPayload.user?.id ?? "");

  assertTest(
    UUID_PATTERN.test(smokeUserId),
    "Auth user smoke memiliki UUID",
    smokeUserId,
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
    "Profil Admin aktif pada satu organisasi",
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

  console.log("\n== Next.js dan proteksi route ==");

  if (await isServerReady(args.baseUrl)) {
    addResult("Next.js server existing siap", true);
  } else {
    startServer(args.baseUrl);
    const ready = await waitForServer(
      args.baseUrl,
      args.startupTimeoutSeconds,
    );
    assertTest(ready, "Next.js dev server siap");
  }

  const unauthenticated = await getUnauthenticated(adminUrl);

  assertTest(
    [302, 303, 307, 308].includes(
      unauthenticated.statusCode,
    ) &&
      String(unauthenticated.location ?? "").includes("/login"),
    "Route Admin listing menolak sesi anonim",
    `Status=${unauthenticated.statusCode} ` +
      `Location=${unauthenticated.location ?? ""}`,
  );

  const products = await selectActiveProducts();
  const baseline = readStockNeutralSnapshot();

  let page = await getPage(adminUrl);

  assertTest(
    containsText(
      page.html,
      "Kelola mapping listing dan resep bundle versi demi versi.",
    ) &&
      containsText(page.html, "Simpan draft mapping") &&
      containsText(page.html, "Stock-neutral"),
    "Halaman Admin listing render tanpa placeholder",
  );

  console.log("\n== Create dan save draft bundle ==");

  const createForm = findForm(page.html, "Simpan draft mapping");
  const createIntentId = findInputValue(createForm, "intentId");
  const effectiveV1 = jakartaDateTimeLocal(nextEventDate());
  const componentsV1 = [
    {
      productId: products[0].product_id,
      quantity: 2,
    },
    {
      productId: products[1].product_id,
      quantity: 1,
    },
  ];

  const createdPage = await invokeServerActionForm({
    pageUri: page.uri,
    pageHtml: page.html,
    marker: "Simpan draft mapping",
    fields: {
      intentId: createIntentId,
      channelCode: "SHOPEE",
      externalListingCode,
      listingTypeCode: "BUNDLE",
      displayName,
      effectiveFrom: effectiveV1,
      productId: "",
      components: JSON.stringify(componentsV1),
      note: "Draft bundle dari focused smoke Admin listing.",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(createdPage.html, externalListingCode) &&
      containsText(
        createdPage.html,
        "disimpan sebagai draft tanpa dampak stok",
      ),
    "Create draft menampilkan feedback persisten",
  );

  let listingRows = await readListingByCode(
    "SHOPEE",
    externalListingCode,
  );

  assertTest(
    listingRows.length === 1 &&
      listingRows[0].listing_type_code === "BUNDLE" &&
      listingRows[0].mapping_readiness_code === "DRAFT_ONLY",
    "Registry menyimpan satu listing bundle draft",
    JSON.stringify(listingRows),
  );

  const listingId = listingRows[0].listing_id;
  let versions = await readListingVersions(listingId);

  assertTest(
    versions.length === 1 &&
      versions[0].version === 1 &&
      versions[0].status_code === "DRAFT" &&
      Number(versions[0].component_count) === 2,
    "Versi pertama dan dua komponen tersimpan",
    JSON.stringify(versions),
  );

  const versionV1Id = versions[0].version_id;
  const editUrl = listingDetailUrl(
    args.baseUrl,
    listingId,
    versionV1Id,
  );
  const editPage = await getPage(editUrl);
  const saveForm = findForm(editPage.html, "Simpan perubahan");
  const oldRowVersion = Number(
    findInputValue(saveForm, "expectedRowVersion"),
  );
  const revisedName = `${displayName} Revisi`;
  const revisedComponents = [
    {
      productId: products[0].product_id,
      quantity: 3,
    },
    {
      productId: products[1].product_id,
      quantity: 1,
    },
  ];

  const savedPage = await invokeServerActionForm({
    pageUri: editPage.uri,
    pageHtml: editPage.html,
    marker: "Simpan perubahan",
    fields: {
      listingId,
      versionId: versionV1Id,
      expectedRowVersion: oldRowVersion,
      channelCode: "SHOPEE",
      externalListingCode,
      listingTypeCode: "BUNDLE",
      displayName: revisedName,
      effectiveFrom: effectiveV1,
      productId: "",
      components: JSON.stringify(revisedComponents),
      note: "Draft bundle direvisi melalui UI.",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      savedPage.html,
      "Draft disimpan dengan row version",
    ) && containsText(savedPage.html, revisedName),
    "Save draft menampilkan row-version feedback dan data terbaru",
  );

  versions = await readListingVersions(listingId);

  assertTest(
    versions[0].display_name === revisedName &&
      Number(versions[0].row_version) > oldRowVersion,
    "Optimistic save menaikkan row version",
    JSON.stringify(versions[0]),
  );

  const stalePage = await invokeServerActionForm({
    pageUri: editPage.uri,
    pageHtml: editPage.html,
    marker: "Simpan perubahan",
    fields: {
      listingId,
      versionId: versionV1Id,
      expectedRowVersion: oldRowVersion,
      channelCode: "SHOPEE",
      externalListingCode,
      listingTypeCode: "BUNDLE",
      displayName: `${displayName} Stale`,
      effectiveFrom: effectiveV1,
      productId: "",
      components: JSON.stringify(componentsV1),
      note: "Payload stale tidak boleh menang.",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      stalePage.html,
      "Draft berubah sejak halaman dibuka.",
    ),
    "Stale draft update ditolak dengan feedback persisten",
  );

  versions = await readListingVersions(listingId);

  assertTest(
    versions[0].display_name === revisedName,
    "Payload stale tidak menimpa draft terbaru",
  );

  assertTest(
    JSON.stringify(readStockNeutralSnapshot()) ===
      JSON.stringify(baseline),
    "Create dan save draft tetap stock-neutral",
  );

  console.log("\n== Blocked dan eligible activation preview ==");

  let productRestored = false;

  try {
    setProductActive(products[1].product_id, false);

    const blockedPage = await getPage(
      listingPreviewUrl(
        args.baseUrl,
        listingId,
        versionV1Id,
      ),
    );

    assertTest(
      containsText(blockedPage.html, "Aktivasi diblokir") &&
        containsText(
          blockedPage.html,
          "MARKETPLACE_BUNDLE_COMPONENT_INACTIVE",
        ) &&
        !hasForm(blockedPage.html, "Aktifkan versi mapping"),
      "Preview blocker tidak menampilkan commit action",
    );
  } finally {
    setProductActive(products[1].product_id, true);
    productRestored = true;
  }

  assertTest(
    productRestored,
    "Status produk fixture dipulihkan setelah blocked preview",
  );

  const previewUrl = listingPreviewUrl(
    args.baseUrl,
    listingId,
    versionV1Id,
  );
  const previewPage = await getPage(previewUrl);
  const activationForm = findForm(
    previewPage.html,
    "Aktifkan versi mapping",
  );
  const activationIntentId = findInputValue(
    activationForm,
    "intentId",
  );
  const activationRowVersion = Number(
    findInputValue(
      activationForm,
      "expectedRowVersion",
    ),
  );
  const previewBasisHash = findInputValue(
    activationForm,
    "previewBasisHash",
  );

  assertTest(
    HASH_PATTERN.test(previewBasisHash) &&
      containsText(previewPage.html, products[0].sku) &&
      containsText(previewPage.html, products[1].sku) &&
      containsText(previewPage.html, "Dapat diaktifkan"),
    "Preview eligible menampilkan komponen dan basis hash",
  );

  const directPreview = await rpc(
    "preview_marketplace_listing_version_activation",
    {
      p_organization_id: organizationId,
      p_listing_id: listingId,
      p_version_id: versionV1Id,
    },
  );

  assertTest(
    directPreview?.eligible === true &&
      directPreview?.basisHash === previewBasisHash &&
      Number(directPreview?.componentCount) === 2,
    "Preview UI memakai basis authoritative yang sama dengan RPC",
    JSON.stringify(directPreview),
  );

  const missingConfirmationPage =
    await invokeServerActionForm({
      pageUri: previewPage.uri,
      pageHtml: previewPage.html,
      marker: "Aktifkan versi mapping",
      fields: {
        intentId: activationIntentId,
        listingId,
        versionId: versionV1Id,
        expectedRowVersion: activationRowVersion,
        previewBasisHash,
      },
      baseUrl: args.baseUrl,
    });

  assertTest(
    containsText(
      missingConfirmationPage.html,
      "Konfirmasi final wajib dicentang sebelum aktivasi.",
    ),
    "Aktivasi tanpa konfirmasi ditolak",
  );

  const activatedPage = await invokeServerActionForm({
    pageUri: previewPage.uri,
    pageHtml: previewPage.html,
    marker: "Aktifkan versi mapping",
    fields: {
      intentId: activationIntentId,
      listingId,
      versionId: versionV1Id,
      expectedRowVersion: activationRowVersion,
      previewBasisHash,
      confirmation: "on",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(activatedPage.html, "Versi 1 aktif mulai"),
    "Aktivasi menampilkan feedback persisten",
  );

  await invokeServerActionForm({
    pageUri: previewPage.uri,
    pageHtml: previewPage.html,
    marker: "Aktifkan versi mapping",
    fields: {
      intentId: activationIntentId,
      listingId,
      versionId: versionV1Id,
      expectedRowVersion: activationRowVersion,
      previewBasisHash,
      confirmation: "on",
    },
    baseUrl: args.baseUrl,
  });

  versions = await readListingVersions(listingId);

  assertTest(
    versions.filter(
      (version) =>
        version.version === 1 &&
        version.status_code === "ACTIVE",
    ).length === 1,
    "Replay aktivasi tidak menggandakan versi atau effect",
    JSON.stringify(versions),
  );

  assertTest(
    JSON.stringify(readStockNeutralSnapshot()) ===
      JSON.stringify(baseline),
    "Aktivasi mapping tetap stock-neutral",
  );

  console.log("\n== Versi dua, boundary, retirement, dan archive ==");

  const clonePage = await getPage(
    cloneListingUrl(args.baseUrl, listingId),
  );
  const cloneForm = findForm(
    clonePage.html,
    "Simpan draft mapping",
  );
  const cloneIntentId = findInputValue(
    cloneForm,
    "intentId",
  );
  const effectiveV2 = jakartaDateTimeLocal(nextEventDate());
  const componentsV2 = [
    {
      productId: products[0].product_id,
      quantity: 1,
    },
    {
      productId: products[1].product_id,
      quantity: 2,
    },
  ];

  const versionTwoPage = await invokeServerActionForm({
    pageUri: clonePage.uri,
    pageHtml: clonePage.html,
    marker: "Simpan draft mapping",
    fields: {
      intentId: cloneIntentId,
      channelCode: "SHOPEE",
      externalListingCode,
      listingTypeCode: "BUNDLE",
      displayName: `${displayName} V2`,
      effectiveFrom: effectiveV2,
      productId: "",
      components: JSON.stringify(componentsV2),
      note: "Versi kedua dari focused smoke Admin listing.",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(versionTwoPage.html, "versi 2 disimpan sebagai draft"),
    "Create versi kedua memakai identity listing yang sama",
  );

  versions = await readListingVersions(listingId);
  const versionV2 = versions.find(
    (version) => Number(version.version) === 2,
  );

  assertTest(
    versions.length === 2 &&
      versionV2?.status_code === "DRAFT",
    "Histori menyimpan dua versi berbeda",
    JSON.stringify(versions),
  );

  const previewV2Page = await getPage(
    listingPreviewUrl(
      args.baseUrl,
      listingId,
      versionV2.version_id,
    ),
  );
  const activationV2Form = findForm(
    previewV2Page.html,
    "Aktifkan versi mapping",
  );
  const activationV2Fields = {
    intentId: findInputValue(
      activationV2Form,
      "intentId",
    ),
    listingId,
    versionId: versionV2.version_id,
    expectedRowVersion: findInputValue(
      activationV2Form,
      "expectedRowVersion",
    ),
    previewBasisHash: findInputValue(
      activationV2Form,
      "previewBasisHash",
    ),
    confirmation: "on",
  };

  await invokeServerActionForm({
    pageUri: previewV2Page.uri,
    pageHtml: previewV2Page.html,
    marker: "Aktifkan versi mapping",
    fields: activationV2Fields,
    baseUrl: args.baseUrl,
  });

  versions = await readListingVersions(listingId);
  const persistedV1 = versions.find(
    (version) => Number(version.version) === 1,
  );
  const persistedV2 = versions.find(
    (version) => Number(version.version) === 2,
  );

  assertTest(
    persistedV2?.status_code === "ACTIVE" &&
      persistedV1?.effective_to ===
        persistedV2?.effective_from,
    "Aktivasi versi baru menutup versi lama pada boundary exact",
    JSON.stringify({ persistedV1, persistedV2 }),
  );

  const retirePage = await getPage(
    listingDetailUrl(
      args.baseUrl,
      listingId,
      persistedV2.version_id,
    ),
  );
  const retireForm = findForm(
    retirePage.html,
    "Hentikan versi",
  );
  const effectiveTo = jakartaDateTimeLocal(nextEventDate());

  const retiredPage = await invokeServerActionForm({
    pageUri: retirePage.uri,
    pageHtml: retirePage.html,
    marker: "Hentikan versi",
    fields: {
      intentId: findInputValue(
        retireForm,
        "intentId",
      ),
      listingId,
      versionId: persistedV2.version_id,
      expectedRowVersion: findInputValue(
        retireForm,
        "expectedRowVersion",
      ),
      effectiveTo,
      confirmation: "on",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      retiredPage.html,
      "dijadwalkan berhenti tanpa menghapus histori order",
    ),
    "Retirement menampilkan feedback persisten",
  );

  versions = await readListingVersions(listingId);
  const retiredV2 = versions.find(
    (version) => Number(version.version) === 2,
  );

  assertTest(
    retiredV2?.status_code === "RETIRED" &&
      Boolean(retiredV2?.effective_to),
    "Versi aktif berubah menjadi RETIRED tanpa dihapus",
    JSON.stringify(retiredV2),
  );

  const archivePage = await getPage(
    listingDetailUrl(args.baseUrl, listingId),
  );
  const archiveForm = findForm(
    archivePage.html,
    "Arsipkan listing",
  );
  const archiveFields = {
    intentId: findInputValue(
      archiveForm,
      "intentId",
    ),
    listingId,
    expectedRowVersion: findInputValue(
      archiveForm,
      "expectedRowVersion",
    ),
    confirmation: "on",
  };

  const archivedPage = await invokeServerActionForm({
    pageUri: archivePage.uri,
    pageHtml: archivePage.html,
    marker: "Arsipkan listing",
    fields: archiveFields,
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      archivedPage.html,
      "Snapshot order lama tetap dapat diaudit.",
    ),
    "Archive menampilkan feedback persisten",
  );

  await invokeServerActionForm({
    pageUri: archivePage.uri,
    pageHtml: archivePage.html,
    marker: "Arsipkan listing",
    fields: archiveFields,
    baseUrl: args.baseUrl,
  });

  listingRows = await readListingByCode(
    "SHOPEE",
    externalListingCode,
  );
  versions = await readListingVersions(listingId);
  const persistedComponents = await readRecipeComponents(
    listingId,
  );

  assertTest(
    listingRows[0]?.status_code === "ARCHIVED" &&
      versions.length === 2 &&
      persistedComponents.length === 4,
    "Archive replay idempotent dan histori versi/komponen tetap utuh",
    JSON.stringify({
      listing: listingRows[0],
      versions,
      componentCount: persistedComponents.length,
    }),
  );

  assertTest(
    JSON.stringify(readStockNeutralSnapshot()) ===
      JSON.stringify(baseline),
    "Seluruh lifecycle Admin listing tidak mengubah stok atau ledger",
  );

  const finalPage = await getPage(
    listingDetailUrl(args.baseUrl, listingId),
  );

  assertTest(
    containsText(finalPage.html, externalListingCode) &&
      containsText(finalPage.html, "ARCHIVED") &&
      containsText(finalPage.html, "v1") &&
      containsText(finalPage.html, "v2") &&
      !containsText(
        finalPage.html,
        "Data listing gagal dimuat.",
      ),
    "Refresh mempertahankan registry dan histori versi",
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