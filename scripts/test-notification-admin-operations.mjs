import { readFile } from "node:fs/promises";
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import path from "node:path";
import process from "node:process";

const DEFAULTS = {
  baseUrl: "http://127.0.0.1:3000",
  email: "smoke.notification.admin@glowlab.invalid",
  password: "LocalSmoke123!",
  displayName: "Notification Smoke Admin",
  startupTimeoutSeconds: 90,
  keepServerRunning: false,
  allowRemote: false,
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FIXTURE_PREFIX = "notification-admin-operations-smoke:";

const results = [];
let exitCode = 0;
let ownedServer = null;
let serverStdout = "";
let serverStderr = "";
let dbContainer = null;
let smokeUserId = null;
let organizationId = null;
let supabaseUrl = null;
let publishableKey = null;
let accessToken = null;
let evaluationOutboxEventId = null;
let retryOutboxEventId = null;
let runId = null;
let evaluationIdempotencyKey = null;
let retryIdempotencyKey = null;

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

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
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

function removeStaleOperationFixtures() {
  runSql(`
begin;
set local session_replication_role = replica;

delete from notification.admin_operation_commands
where idempotency_key like
      ${sqlLiteral(`${FIXTURE_PREFIX}%`)};

delete from notification.rule_runs
where triggered_by_outbox_event_id in (
  select event_row.id
  from notification.outbox_events event_row
  where event_row.source_event_key like
        ${sqlLiteral(`admin-evaluation:%:${FIXTURE_PREFIX}%`)}
     or event_row.source_event_key like
        ${sqlLiteral(`${FIXTURE_PREFIX}%`)}
);

delete from notification.outbox_events
where source_event_key like
      ${sqlLiteral(`admin-evaluation:%:${FIXTURE_PREFIX}%`)}
   or source_event_key like
      ${sqlLiteral(`${FIXTURE_PREFIX}%`)};

commit;
`);
}

function setSmokeProfileActive(userId, active) {
  const output = runSql(
    `
update app.user_profiles
set is_active = ${active ? "true" : "false"}
where user_id = ${sqlLiteral(userId)}::uuid
returning organization_id::text;
`,
    { tuplesOnly: true },
  );

  const resolvedOrganizationId = output
    .split(/\r?\n/)
    .map((value) => value.trim())
    .find((value) => UUID_PATTERN.test(value));

  if (active && !resolvedOrganizationId) {
    throw new Error("Profil Admin smoke gagal diaktifkan.");
  }

  if (resolvedOrganizationId) {
    organizationId = resolvedOrganizationId;
  }
}

function removeSmokeUserStates() {
  if (!smokeUserId) return;

  runSql(`
delete from notification.user_states
where user_id = ${sqlLiteral(smokeUserId)}::uuid;
`);
}

function createRetryFixture() {
  const eventId = randomUUID();
  const correlationId = randomUUID();
  const sourceEventKey = `${FIXTURE_PREFIX}retry:${runId}`;
  const payload = JSON.stringify({
    schemaVersion: 1,
    smokeSuite: "notification-admin-operations",
    runId,
    fixture: "retry",
    temporary: true,
  });

  runSql(`
insert into notification.outbox_events (
  id,
  organization_id,
  event_type_code,
  source_event_key,
  entity_type_code,
  entity_id,
  occurred_at,
  payload,
  payload_hash,
  correlation_id,
  status_code,
  attempt_count,
  retry_budget_started_at_attempt,
  available_at,
  locked_at,
  locked_by,
  completed_at,
  last_error_code,
  last_error_detail,
  actor_user_id,
  process_name,
  created_at
)
values (
  ${sqlLiteral(eventId)}::uuid,
  ${sqlLiteral(organizationId)}::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  ${sqlLiteral(sourceEventKey)},
  'ORGANIZATION',
  ${sqlLiteral(organizationId)}::uuid,
  clock_timestamp() - interval '3 hours',
  ${sqlLiteral(payload)}::jsonb,
  encode(
    extensions.digest(
      ${sqlLiteral(payload)}::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  ${sqlLiteral(correlationId)}::uuid,
  'FAILED_FINAL',
  4,
  1,
  clock_timestamp() - interval '3 hours',
  null,
  null,
  clock_timestamp() - interval '30 minutes',
  'SMOKE_RETRY_FINAL',
  jsonb_build_object(
    'smokeSuite', 'notification-admin-operations',
    'runId', ${sqlLiteral(runId)},
    'message', 'Temporary terminal failure for retry smoke test.'
  ),
  null,
  'notification-admin-operations-smoke',
  clock_timestamp() - interval '3 hours'
);
`);

  return eventId;
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

async function getOperationsSummary() {
  return rpc("get_notification_operations_summary", {});
}

async function getActionableOutbox(
  statusCode = null,
  limit = 100,
) {
  const rows = await rpc(
    "notification_outbox_actionable_list",
    {
      p_status_code: statusCode,
      p_limit: limit,
    },
  );

  return Array.isArray(rows) ? rows : [];
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
        html.slice(0, 2000),
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

function normalizeRenderedText(value) {
  return String(value)
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#x27;|&#39;/gi, "'")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function findServerActionName(html, marker) {
  const forms = html.match(/<form\b[^>]*>.*?<\/form>/gis) ?? [];
  const normalizedMarker = normalizeRenderedText(marker);

  for (const form of forms) {
    const rawForm = form.toLowerCase();
    const rawMarker = String(marker).toLowerCase();

    if (
      !rawForm.includes(rawMarker) &&
      !normalizeRenderedText(form).includes(normalizedMarker)
    ) {
      continue;
    }

    const match = form.match(/name="(\$ACTION_ID_[^"]+)"/i);

    if (match) return match[1];
  }

  throw new Error(
    `Form Server Action dengan marker "${marker}" tidak ditemukan.`,
  );
}

async function invokeServerActionForm({
  pageUri,
  pageHtml,
  marker,
  fields,
  baseUrl,
}) {
  const actionName = findServerActionName(pageHtml, marker);
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

function containsText(html, text) {
  return normalizeRenderedText(html).includes(
    normalizeRenderedText(text),
  );
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
    serverStdout = (serverStdout + chunk.toString()).slice(-20000);
  });

  ownedServer.stderr.on("data", (chunk) => {
    serverStderr = (serverStderr + chunk.toString()).slice(-20000);
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

async function main(args) {
  console.log("== Preflight ==");

  const requiredPaths = [
    ".env.local",
    "package.json",
    "scripts/create-demo-admin.mjs",
    "src/app/notifications/operations/actions.ts",
    "src/app/notifications/operations/page.tsx",
    "src/lib/supabase-rest.ts",
    "supabase/migrations/202607170001_notification_outbox_actionable_list.sql",
    "supabase/tests/040_notification_outbox_actionable_list.test.sql",
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

  dbContainer = resolveDbContainer();

  assertTest(
    Boolean(dbContainer),
    "Database Supabase lokal ditemukan",
    dbContainer,
  );

  removeStaleOperationFixtures();

  console.log("\n== Provision dan aktivasi Admin smoke ==");

  const provisionOutput = runCommand(
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

  if (!provisionOutput.includes("Demo Admin siap")) {
    throw new Error(
      "Provision akun smoke tidak memberi konfirmasi.",
    );
  }

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

  setSmokeProfileActive(smokeUserId, true);

  assertTest(
    UUID_PATTERN.test(organizationId),
    "Profil smoke aktif pada satu organisasi",
    organizationId,
  );

  const profileResponse = await fetch(
    `${supabaseUrl}/rest/v1/current_admin_profile?select=*`,
    {
      headers: apiHeaders(),
      cache: "no-store",
    },
  );
  const profiles = await parseResponse(profileResponse);
  const profile = Array.isArray(profiles) ? profiles[0] : null;

  assertTest(
    profileResponse.ok &&
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

  const operationsUrl =
    `${args.baseUrl}/notifications/operations`;

  const unauthenticated = await getUnauthenticated(
    operationsUrl,
  );

  assertTest(
    [302, 303, 307, 308].includes(
      unauthenticated.statusCode,
    ) &&
      String(unauthenticated.location ?? "").includes(
        "/login",
      ),
    "Halaman Operations menolak sesi anonim",
    `Status=${unauthenticated.statusCode} ` +
      `Location=${unauthenticated.location ?? ""}`,
  );

  const baselineSummary = await getOperationsSummary();

  assertTest(
    baselineSummary?.organizationId === organizationId &&
      baselineSummary?.userId === smokeUserId,
    "Summary menggunakan organisasi dan Admin aktif",
  );

  console.log("\n== Fixture outbox gagal dan UI awal ==");

  runId = randomUUID();
  evaluationIdempotencyKey =
    `${FIXTURE_PREFIX}evaluation:${runId}`;
  retryIdempotencyKey =
    `${FIXTURE_PREFIX}retry:${runId}`;
  retryOutboxEventId = createRetryFixture();

  assertTest(
    UUID_PATTERN.test(retryOutboxEventId),
    "Fixture FAILED_FINAL dibuat",
    retryOutboxEventId,
  );

  const fixtureSummary = await getOperationsSummary();

  assertTest(
    fixtureSummary.outbox.failedFinalCount ===
      baselineSummary.outbox.failedFinalCount + 1,
    "Summary menghitung fixture failed final",
  );

  assertTest(
    fixtureSummary.outbox.actionableCount ===
      baselineSummary.outbox.actionableCount + 1,
    "Summary menghitung fixture sebagai actionable",
  );

  let page = await getPage(
    `${operationsUrl}?status=FAILED_FINAL`,
  );

  assertTest(
    containsText(
      page.html,
      "Kendali evaluator dan outbox",
    ),
    "Halaman Notification Operations dirender",
  );

  assertTest(
    [
      "Jalankan evaluasi Expiry",
      "Jalankan evaluasi Return inspection",
      "Jalankan evaluasi Reconciliation",
      "Jalankan evaluasi Stocktake",
    ].every((label) => containsText(page.html, label)),
    "Empat form evaluator manual dirender",
  );

  assertTest(
    containsText(page.html, retryOutboxEventId),
    "Fixture gagal tampil pada daftar outbox",
  );

  assertTest(
    containsText(page.html, "Retry event"),
    "Form retry dirender untuk FAILED_FINAL",
  );

  console.log("\n== Server Action manual evaluation ==");

  const evaluationReason =
    `  Smoke evaluation EXPIRY ${runId}.  `;

  page = await invokeServerActionForm({
    pageUri: page.uri,
    pageHtml: page.html,
    marker: "Jalankan evaluasi Expiry",
    fields: {
      evaluationFamilyCode: "EXPIRY",
      idempotencyKey: evaluationIdempotencyKey,
      returnTo: "/notifications/operations#evaluations",
      reason: evaluationReason,
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      page.html,
      "Evaluasi EXPIRY berhasil dimasukkan ke outbox.",
    ),
    "Server Action evaluation memberi feedback sukses",
  );

  const evaluationState = runSqlJson(`
select jsonb_build_object(
  'commandCount',
    (
      select count(*)
      from notification.admin_operation_commands command
      where command.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and command.operation_code =
            'REQUEST_EVALUATION'
        and command.idempotency_key =
            ${sqlLiteral(evaluationIdempotencyKey)}
    ),
  'commandReason',
    (
      select command.reason
      from notification.admin_operation_commands command
      where command.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and command.operation_code =
            'REQUEST_EVALUATION'
        and command.idempotency_key =
            ${sqlLiteral(evaluationIdempotencyKey)}
    ),
  'commandActor',
    (
      select command.actor_user_id
      from notification.admin_operation_commands command
      where command.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and command.operation_code =
            'REQUEST_EVALUATION'
        and command.idempotency_key =
            ${sqlLiteral(evaluationIdempotencyKey)}
    ),
  'outboxCount',
    (
      select count(*)
      from notification.outbox_events event_row
      where event_row.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and event_row.source_event_key =
            ${sqlLiteral(
              `admin-evaluation:expiry:${evaluationIdempotencyKey}`,
            )}
    ),
  'outboxEventId',
    (
      select event_row.id
      from notification.outbox_events event_row
      where event_row.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and event_row.source_event_key =
            ${sqlLiteral(
              `admin-evaluation:expiry:${evaluationIdempotencyKey}`,
            )}
    ),
  'outboxStatus',
    (
      select event_row.status_code
      from notification.outbox_events event_row
      where event_row.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and event_row.source_event_key =
            ${sqlLiteral(
              `admin-evaluation:expiry:${evaluationIdempotencyKey}`,
            )}
    ),
  'eventType',
    (
      select event_row.event_type_code
      from notification.outbox_events event_row
      where event_row.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and event_row.source_event_key =
            ${sqlLiteral(
              `admin-evaluation:expiry:${evaluationIdempotencyKey}`,
            )}
    ),
  'payloadReason',
    (
      select event_row.payload ->> 'reason'
      from notification.outbox_events event_row
      where event_row.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and event_row.source_event_key =
            ${sqlLiteral(
              `admin-evaluation:expiry:${evaluationIdempotencyKey}`,
            )}
    )
)::text;
`);

  evaluationOutboxEventId = String(
    evaluationState.outboxEventId ?? "",
  );

  assertTest(
    Number(evaluationState.commandCount) === 1 &&
      evaluationState.commandReason ===
        evaluationReason.trim() &&
      evaluationState.commandActor === smokeUserId,
    "Audit command evaluation tersimpan sekali",
  );

  assertTest(
    Number(evaluationState.outboxCount) === 1 &&
      UUID_PATTERN.test(evaluationOutboxEventId) &&
      evaluationState.outboxStatus === "PENDING" &&
      evaluationState.eventType ===
        "NOTIFICATION_EXPIRY_EVALUATION_REQUESTED" &&
      evaluationState.payloadReason ===
        evaluationReason.trim(),
    "Evaluation membuat satu outbox PENDING yang benar",
    evaluationOutboxEventId,
  );

  const pendingEvents = await getActionableOutbox(
    "PENDING",
  );

  assertTest(
    pendingEvents.some(
      (event) =>
        event.outbox_event_id ===
        evaluationOutboxEventId,
    ),
    "Read API menampilkan outbox evaluation",
  );

  const afterEvaluationSummary =
    await getOperationsSummary();

  assertTest(
    afterEvaluationSummary.adminOperations
      .evaluationRequestsLast24Hours ===
      baselineSummary.adminOperations
        .evaluationRequestsLast24Hours +
        1 &&
      afterEvaluationSummary.outbox.pendingCount ===
        baselineSummary.outbox.pendingCount + 1,
    "Summary diperbarui setelah manual evaluation",
  );

  page = await invokeServerActionForm({
    pageUri: page.uri,
    pageHtml: page.html,
    marker: "Jalankan evaluasi Expiry",
    fields: {
      evaluationFamilyCode: "EXPIRY",
      idempotencyKey: evaluationIdempotencyKey,
      returnTo: "/notifications/operations#evaluations",
      reason: evaluationReason,
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      page.html,
      "sudah pernah diterima dan diputar ulang",
    ),
    "Replay evaluation memberi feedback idempotent",
  );

  const evaluationReplayState = runSqlJson(`
select jsonb_build_object(
  'commandCount',
    (
      select count(*)
      from notification.admin_operation_commands command
      where command.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and command.operation_code =
            'REQUEST_EVALUATION'
        and command.idempotency_key =
            ${sqlLiteral(evaluationIdempotencyKey)}
    ),
  'outboxCount',
    (
      select count(*)
      from notification.outbox_events event_row
      where event_row.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and event_row.source_event_key =
            ${sqlLiteral(
              `admin-evaluation:expiry:${evaluationIdempotencyKey}`,
            )}
    )
)::text;
`);

  assertTest(
    Number(evaluationReplayState.commandCount) === 1 &&
      Number(evaluationReplayState.outboxCount) === 1,
    "Replay evaluation tidak menggandakan audit atau outbox",
  );

  console.log("\n== Server Action retry outbox ==");

  page = await getPage(
    `${operationsUrl}?status=FAILED_FINAL`,
  );

  const retryReason =
    `  Diagnosis selesai; fixture aman di-retry ${runId}.  `;

  page = await invokeServerActionForm({
    pageUri: page.uri,
    pageHtml: page.html,
    marker: retryOutboxEventId,
    fields: {
      outboxEventId: retryOutboxEventId,
      idempotencyKey: retryIdempotencyKey,
      returnTo:
        "/notifications/operations?status=FAILED_RETRYABLE#outbox",
      reason: retryReason,
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      page.html,
      "Outbox event dikembalikan ke antrean retry dengan budget baru.",
    ),
    "Server Action retry memberi feedback sukses",
  );

  const retryableEvents = await getActionableOutbox(
    "FAILED_RETRYABLE",
  );
  const retriedEvent = retryableEvents.find(
    (event) =>
      event.outbox_event_id === retryOutboxEventId,
  );

  assertTest(
    retriedEvent?.status_code === "FAILED_RETRYABLE" &&
      retriedEvent?.attempt_count === 4 &&
      retriedEvent?.retry_budget_started_at_attempt === 4 &&
      retriedEvent?.retry_cycle_attempt_count === 0 &&
      retriedEvent?.can_retry === true &&
      retriedEvent?.locked_at == null &&
      retriedEvent?.completed_at == null &&
      retriedEvent?.last_error_code ===
        "SMOKE_RETRY_FINAL",
    "Retry membuka budget baru tanpa menghapus histori kegagalan",
  );

  const retryAuditState = runSqlJson(`
select jsonb_build_object(
  'commandCount',
    (
      select count(*)
      from notification.admin_operation_commands command
      where command.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and command.operation_code =
            'RETRY_OUTBOX_EVENT'
        and command.idempotency_key =
            ${sqlLiteral(retryIdempotencyKey)}
    ),
  'commandReason',
    (
      select command.reason
      from notification.admin_operation_commands command
      where command.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and command.operation_code =
            'RETRY_OUTBOX_EVENT'
        and command.idempotency_key =
            ${sqlLiteral(retryIdempotencyKey)}
    ),
  'commandActor',
    (
      select command.actor_user_id
      from notification.admin_operation_commands command
      where command.organization_id =
            ${sqlLiteral(organizationId)}::uuid
        and command.operation_code =
            'RETRY_OUTBOX_EVENT'
        and command.idempotency_key =
            ${sqlLiteral(retryIdempotencyKey)}
    )
)::text;
`);

  assertTest(
    Number(retryAuditState.commandCount) === 1 &&
      retryAuditState.commandReason ===
        retryReason.trim() &&
      retryAuditState.commandActor === smokeUserId,
    "Audit command retry tersimpan sekali",
  );

  const afterRetrySummary = await getOperationsSummary();

  assertTest(
    afterRetrySummary.adminOperations
      .retryRequestsLast24Hours ===
      baselineSummary.adminOperations
        .retryRequestsLast24Hours +
        1 &&
      afterRetrySummary.outbox.failedFinalCount ===
        baselineSummary.outbox.failedFinalCount &&
      afterRetrySummary.outbox.failedRetryableCount ===
        baselineSummary.outbox.failedRetryableCount +
        1 &&
      afterRetrySummary.outbox.actionableCount ===
        baselineSummary.outbox.actionableCount + 2,
    "Summary diperbarui setelah retry",
  );

  page = await invokeServerActionForm({
    pageUri: page.uri,
    pageHtml: page.html,
    marker: retryOutboxEventId,
    fields: {
      outboxEventId: retryOutboxEventId,
      idempotencyKey: retryIdempotencyKey,
      returnTo:
        "/notifications/operations?status=FAILED_RETRYABLE#outbox",
      reason: retryReason,
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      page.html,
      "sudah pernah diterima dan diputar ulang",
    ),
    "Replay retry memberi feedback idempotent",
  );

  const retryReplayCount = Number(
    runSql(
      `
select count(*)::text
from notification.admin_operation_commands command
where command.organization_id =
      ${sqlLiteral(organizationId)}::uuid
  and command.operation_code =
      'RETRY_OUTBOX_EVENT'
  and command.idempotency_key =
      ${sqlLiteral(retryIdempotencyKey)};
`,
      { tuplesOnly: true },
    ).trim(),
  );

  assertTest(
    retryReplayCount === 1,
    "Replay retry tidak menggandakan audit command",
  );

  console.log("\n== Cleanup fixture dan regression guard ==");

  removeStaleOperationFixtures();
  removeSmokeUserStates();
  setSmokeProfileActive(smokeUserId, false);

  const remainingState = runSqlJson(`
select jsonb_build_object(
  'commands',
    (
      select count(*)
      from notification.admin_operation_commands command
      where command.idempotency_key like
            ${sqlLiteral(`${FIXTURE_PREFIX}%`)}
    ),
  'outbox',
    (
      select count(*)
      from notification.outbox_events event_row
      where event_row.source_event_key like
            ${sqlLiteral(
              `admin-evaluation:%:${FIXTURE_PREFIX}%`,
            )}
         or event_row.source_event_key like
            ${sqlLiteral(`${FIXTURE_PREFIX}%`)}
    )
)::text;
`);

  assertTest(
    Number(remainingState.commands) === 0 &&
      Number(remainingState.outbox) === 0,
    "Fixture operasi dan outbox dibersihkan",
  );

  const profileState = runSql(
    `
select
  profile.is_active::text
  || '|'
  || (
    select count(*)::text
    from notification.user_states state
    where state.user_id = profile.user_id
  )
from app.user_profiles profile
where profile.user_id =
      ${sqlLiteral(smokeUserId)}::uuid;
`,
    { tuplesOnly: true },
  ).trim();

  assertTest(
    profileState === "false|0",
    "Admin smoke dinonaktifkan tanpa user state tersisa",
    profileState,
  );

  const npxCommand =
    process.platform === "win32" ? "npx.cmd" : "npx";

  runCommand(
    npxCommand,
    [
      "supabase",
      "test",
      "db",
      "supabase/tests/039_notification_admin_operations.test.sql",
    ],
    {
      printStdout: true,
      printStderr: true,
    },
  );

  addResult(
    "Regression guard Admin Operations tetap PASS",
    true,
  );

  runCommand(
    npxCommand,
    [
      "supabase",
      "test",
      "db",
      "supabase/tests/040_notification_outbox_actionable_list.test.sql",
    ],
    {
      printStdout: true,
      printStderr: true,
    },
  );

  addResult(
    "Regression guard actionable outbox tetap PASS",
    true,
  );
}

let args = { ...DEFAULTS };

try {
  args = parseArgs(process.argv.slice(2));
  await main(args);
} catch (error) {
  exitCode = 1;
  const fatalMessage =
    error instanceof Error ? error.message : String(error);

  if (!results.some((item) => item.status === "FAIL")) {
    addResult(
      "Eksekusi smoke test selesai tanpa fatal error",
      false,
      fatalMessage,
    );
  }

  console.error(
    `\n\x1b[31m[FATAL]\x1b[0m ${fatalMessage}`,
  );
  showServerLogs();
} finally {
  console.log("\n== Final cleanup ==");

  try {
    if (dbContainer) {
      removeStaleOperationFixtures();
    }
  } catch (error) {
    exitCode = 1;
    console.error(
      `[CLEANUP FAIL] Fixture operations: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }

  try {
    if (dbContainer) removeSmokeUserStates();
  } catch (error) {
    exitCode = 1;
    console.error(
      `[CLEANUP FAIL] Smoke user states: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }

  try {
    if (dbContainer && smokeUserId) {
      setSmokeProfileActive(smokeUserId, false);
    }
  } catch (error) {
    exitCode = 1;
    console.error(
      `[CLEANUP FAIL] Profil smoke: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }

  stopOwnedServer(args.keepServerRunning);

  console.log(
    "\n== Ringkasan smoke test Admin Operations ==",
  );

  const widths = {
    status: Math.max(
      6,
      ...results.map((item) => item.status.length),
    ),
    test: Math.max(
      4,
      ...results.map((item) => item.test.length),
    ),
  };

  console.log(
    `${"Status".padEnd(widths.status)}  ` +
      `${"Test".padEnd(widths.test)}  Detail`,
  );
  console.log(
    `${"-".repeat(widths.status)}  ` +
      `${"-".repeat(widths.test)}  ------`,
  );

  for (const item of results) {
    console.log(
      `${item.status.padEnd(widths.status)}  ` +
        `${item.test.padEnd(widths.test)}  ` +
        `${item.detail}`,
    );
  }

  const passed = results.filter(
    (item) => item.status === "PASS",
  ).length;
  const failed = results.filter(
    (item) => item.status === "FAIL",
  ).length;

  const color =
    failed === 0 && exitCode === 0
      ? "\x1b[32m"
      : "\x1b[31m";

  console.log(
    `\n${color}PASS: ${passed} | FAIL: ${failed}\x1b[0m`,
  );
}

process.exitCode = exitCode;
