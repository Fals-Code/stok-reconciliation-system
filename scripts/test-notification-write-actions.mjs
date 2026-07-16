import { readFile } from "node:fs/promises";
import { spawn, spawnSync } from "node:child_process";
import path from "node:path";
import process from "node:process";
import { randomUUID } from "node:crypto";

const DEFAULTS = {
  baseUrl: "http://127.0.0.1:3000",
  email: "smoke.notification.admin@glowlab.invalid",
  password: "LocalSmoke123!",
  displayName: "Notification Smoke Admin",
  startupTimeoutSeconds: 90,
  keepServerRunning: false,
  allowRemote: false,
};

const results = [];
let exitCode = 0;
let ownedServer = null;
let serverStdout = "";
let serverStderr = "";
let dbContainer = null;
let smokeUserId = null;
let organizationId = null;
let notificationId = null;
let supabaseUrl = null;
let publishableKey = null;
let accessToken = null;

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

  const prefix = passed ? "\x1b[32m[PASS]\x1b[0m" : "\x1b[31m[FAIL]\x1b[0m";
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
    const output = [result.stdout, result.stderr].filter(Boolean).join("\n");
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
    throw new Error("Container database Supabase lokal tidak ditemukan.");
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

function removeStaleNotificationFixtures() {
  runSql(`
begin;
set local session_replication_role = replica;

delete from notification.user_states
where notification_id in (
  select id
  from notification.notifications
  where source_snapshot ->> 'smokeSuite' =
        'notification-write-actions'
);

delete from notification.notification_events
where notification_id in (
  select id
  from notification.notifications
  where source_snapshot ->> 'smokeSuite' =
        'notification-write-actions'
);

delete from notification.notifications
where source_snapshot ->> 'smokeSuite' =
      'notification-write-actions';

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
    .find((value) =>
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        value,
      ),
    );

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

function newNotificationFixture(runId) {
  const entityId = randomUUID();
  const correlationId = randomUUID();

  const output = runSql(
    `
with fixture_clock as (
  select clock_timestamp() as observed_at
),
selected_rule as (
  select rule.id
  from notification.rules rule
  where rule.organization_id = ${sqlLiteral(organizationId)}::uuid
    and rule.is_active
    and rule.effective_from <= clock_timestamp()
    and (
      rule.effective_to is null
      or rule.effective_to > clock_timestamp()
    )
  order by rule.code
  limit 1
)
select notification.upsert_active_notification(
  p_organization_id => ${sqlLiteral(organizationId)}::uuid,
  p_rule_id => selected_rule.id,
  p_entity_id => ${sqlLiteral(entityId)}::uuid,
  p_deduplication_key =>
    ${sqlLiteral(`notification-write-actions:${runId}`)},
  p_stage_code => 'SMOKE_OPEN',
  p_severity_code => 'WARNING',
  p_title => 'Smoke Test Notification Actions',
  p_message =>
    'Fixture lokal sementara untuk menguji Server Actions Notification Center.',
  p_action_route => '/notifications',
  p_condition_started_at => fixture_clock.observed_at,
  p_observed_at => fixture_clock.observed_at,
  p_due_at => fixture_clock.observed_at + interval '1 day',
  p_source_snapshot => jsonb_build_object(
    'smokeSuite', 'notification-write-actions',
    'runId', ${sqlLiteral(runId)},
    'temporary', true
  ),
  p_stage_direction_code => 'UNCHANGED',
  p_correlation_id => ${sqlLiteral(correlationId)}::uuid,
  p_process_name => 'notification-write-actions-smoke'
)::text
from selected_rule
cross join fixture_clock;
`,
    { tuplesOnly: true },
  );

  const jsonLine = output
    .split(/\r?\n/)
    .map((value) => value.trim())
    .findLast((value) => value.startsWith("{"));

  if (!jsonLine) {
    throw new Error(
      "Fixture notification gagal dibuat. Pastikan ada notification rule aktif.",
    );
  }

  const parsed = JSON.parse(jsonLine);
  const id = String(parsed.notificationId ?? "");

  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      id,
    )
  ) {
    throw new Error("Fixture tidak mengembalikan notification ID valid.");
  }

  return id;
}

function removeNotificationFixture() {
  if (!notificationId) {
    removeStaleNotificationFixtures();
    return;
  }

  runSql(`
begin;
set local session_replication_role = replica;

delete from notification.user_states
where notification_id = ${sqlLiteral(notificationId)}::uuid;

delete from notification.notification_events
where notification_id = ${sqlLiteral(notificationId)}::uuid;

delete from notification.notifications
where id = ${sqlLiteral(notificationId)}::uuid;

commit;
`);

  notificationId = null;
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
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: apiHeaders(),
    body: JSON.stringify(body),
    cache: "no-store",
  });
  const payload = await parseResponse(response);

  if (!response.ok) {
    throw new Error(
      `RPC ${name} gagal (${response.status}): ${JSON.stringify(payload)}`,
    );
  }

  return payload;
}

async function getUnreadCount() {
  const value = await rpc("notification_unread_count", {});
  const normalized = Number(value);

  if (!Number.isFinite(normalized)) {
    throw new Error(`Unread count bukan angka: ${JSON.stringify(value)}`);
  }

  return normalized;
}

async function getNotificationDetail(id) {
  const rows = await rpc("notification_detail", {
    p_notification_id: id,
  });

  return Array.isArray(rows) ? rows[0] ?? null : null;
}

async function getNotificationHistory(id) {
  const rows = await rpc("notification_event_history", {
    p_notification_id: id,
    p_limit: 100,
    p_after_occurred_at: null,
    p_after_id: null,
  });

  return Array.isArray(rows) ? rows : [];
}

async function getNotificationList(includeArchived) {
  const rows = await rpc("notification_list", {
    p_lifecycle_status_code: null,
    p_severity_code: null,
    p_category_code: null,
    p_read_state_code: null,
    p_include_archived: includeArchived,
    p_limit: 100,
    p_before_last_seen_at: null,
    p_before_id: null,
  });

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
      `GET ${uri} gagal (${response.status}): ${html.slice(0, 2000)}`,
    );
  }

  return {
    uri: response.url || uri,
    html,
    statusCode: response.status,
  };
}

function findServerActionName(html, marker) {
  const forms = html.match(/<form\b[^>]*>.*?<\/form>/gis) ?? [];

  for (const form of forms) {
    if (!form.toLowerCase().includes(marker.toLowerCase())) continue;

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
  return html.toLowerCase().includes(text.toLowerCase());
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
        `Next.js dev server berhenti dengan exit code ${ownedServer.exitCode}.`,
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
    "src/app/notifications/actions.ts",
    "src/app/notifications/page.tsx",
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
    env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321",
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

  removeStaleNotificationFixtures();

  console.log("\n== Provision dan aktivasi Admin smoke ==");

  const nodeCommand = process.execPath;
  const provisionOutput = runCommand(
    nodeCommand,
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
    throw new Error("Provision akun smoke tidak memberi konfirmasi.");
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
    /^[0-9a-f-]{36}$/i.test(smokeUserId),
    "Auth user smoke memiliki UUID",
  );

  setSmokeProfileActive(smokeUserId, true);

  assertTest(
    /^[0-9a-f-]{36}$/i.test(organizationId),
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

  const baselineUnread = await getUnreadCount();

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

  console.log("\n== Membuat fixture notification ==");

  const runId = randomUUID();
  notificationId = newNotificationFixture(runId);

  assertTest(
    /^[0-9a-f-]{36}$/i.test(notificationId),
    "Fixture notification OPEN dibuat",
    notificationId,
  );

  let detail = await getNotificationDetail(notificationId);

  assertTest(
    detail?.lifecycle_status_code === "OPEN" &&
      detail?.read_state_code === "UNREAD",
    "Fixture mulai sebagai OPEN dan UNREAD",
  );

  const afterCreateUnread = await getUnreadCount();

  assertTest(
    afterCreateUnread === baselineUnread + 1,
    "Fixture menambah unread count satu",
    `Baseline=${baselineUnread} Current=${afterCreateUnread}`,
  );

  const detailUrl =
    `${args.baseUrl}/notifications?notificationId=` +
    `${encodeURIComponent(notificationId)}#detail`;

  let page = await getPage(detailUrl);

  assertTest(
    containsText(page.html, "Smoke Test Notification Actions"),
    "Fixture tampil pada halaman Notification Center",
  );

  assertTest(
    containsText(page.html, "Tandai sudah dibaca"),
    "Form READ dirender",
  );

  assertTest(
    containsText(page.html, "Acknowledge notification"),
    "Form acknowledge dirender untuk lifecycle OPEN",
  );

  console.log("\n== Server Action READ ==");

  page = await invokeServerActionForm({
    pageUri: detailUrl,
    pageHtml: page.html,
    marker: "Tandai sudah dibaca",
    fields: {
      notificationId,
      returnTo:
        `/notifications?notificationId=${notificationId}#detail`,
      readStateCode: "READ",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(page.html, "Notifikasi ditandai sudah dibaca."),
    "Server Action READ memberi feedback sukses",
  );

  detail = await getNotificationDetail(notificationId);

  assertTest(
    detail?.read_state_code === "READ",
    "READ tersimpan pada API",
  );

  assertTest(
    (await getUnreadCount()) === baselineUnread,
    "READ menurunkan unread count",
  );

  console.log("\n== Server Action UNREAD ==");

  page = await getPage(detailUrl);
  page = await invokeServerActionForm({
    pageUri: detailUrl,
    pageHtml: page.html,
    marker: "Tandai belum dibaca",
    fields: {
      notificationId,
      returnTo:
        `/notifications?notificationId=${notificationId}#detail`,
      readStateCode: "UNREAD",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(page.html, "Notifikasi ditandai belum dibaca."),
    "Server Action UNREAD memberi feedback sukses",
  );

  detail = await getNotificationDetail(notificationId);

  assertTest(
    detail?.read_state_code === "UNREAD",
    "UNREAD tersimpan pada API",
  );

  assertTest(
    (await getUnreadCount()) === baselineUnread + 1,
    "UNREAD menaikkan unread count kembali",
  );

  console.log("\n== Server Action ARCHIVE ==");

  page = await getPage(detailUrl);
  page = await invokeServerActionForm({
    pageUri: detailUrl,
    pageHtml: page.html,
    marker: "Arsipkan",
    fields: {
      notificationId,
      returnTo:
        `/notifications?notificationId=${notificationId}#detail`,
      readStateCode: "ARCHIVED_FOR_USER",
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      page.html,
      "Notifikasi dipindahkan ke arsip pribadi.",
    ),
    "Server Action ARCHIVE memberi feedback sukses",
  );

  detail = await getNotificationDetail(notificationId);

  assertTest(
    detail?.read_state_code === "ARCHIVED_FOR_USER",
    "ARCHIVED_FOR_USER tersimpan pada API",
  );

  assertTest(
    (await getUnreadCount()) === baselineUnread,
    "Arsip pribadi tidak dihitung sebagai unread",
  );

  let visibleRows = await getNotificationList(false);
  const archivedRows = await getNotificationList(true);

  assertTest(
    !visibleRows.some(
      (row) => row.notification_id === notificationId,
    ),
    "Arsip tersembunyi dari daftar utama",
  );

  assertTest(
    archivedRows.some(
      (row) => row.notification_id === notificationId,
    ),
    "Arsip tampil ketika includeArchived aktif",
  );

  console.log("\n== Unarchive melalui READ ==");

  page = await getPage(detailUrl);
  await invokeServerActionForm({
    pageUri: detailUrl,
    pageHtml: page.html,
    marker: "Tandai sudah dibaca",
    fields: {
      notificationId,
      returnTo:
        `/notifications?notificationId=${notificationId}#detail`,
      readStateCode: "READ",
    },
    baseUrl: args.baseUrl,
  });

  detail = await getNotificationDetail(notificationId);

  assertTest(
    detail?.read_state_code === "READ",
    "READ mengeluarkan notification dari arsip pribadi",
  );

  visibleRows = await getNotificationList(false);

  assertTest(
    visibleRows.some(
      (row) => row.notification_id === notificationId,
    ),
    "Notification kembali ke daftar utama",
  );

  console.log("\n== Server Action ACKNOWLEDGE ==");

  const acknowledgmentNote = `Diambil alih oleh smoke test ${runId}`;
  page = await getPage(detailUrl);
  page = await invokeServerActionForm({
    pageUri: detailUrl,
    pageHtml: page.html,
    marker: "Acknowledge notification",
    fields: {
      notificationId,
      returnTo:
        `/notifications?notificationId=${notificationId}#detail`,
      note: acknowledgmentNote,
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      page.html,
      "Notifikasi berhasil di-acknowledge.",
    ),
    "Server Action acknowledge memberi feedback sukses",
  );

  detail = await getNotificationDetail(notificationId);

  assertTest(
    detail?.lifecycle_status_code === "ACKNOWLEDGED" &&
      detail?.acknowledgment_note === acknowledgmentNote,
    "ACKNOWLEDGED dan catatan tersimpan pada API",
  );

  assertTest(
    containsText(page.html, "Batalkan acknowledgment"),
    "UI beralih ke aksi revoke",
  );

  let history = await getNotificationHistory(notificationId);
  const acknowledgeEvents = history.filter(
    (event) => event.event_type_code === "ACKNOWLEDGED",
  );

  assertTest(
    acknowledgeEvents.length === 1 &&
      acknowledgeEvents[0]?.note === acknowledgmentNote,
    "Audit event ACKNOWLEDGED tercatat sekali",
  );

  console.log("\n== Server Action REVOKE ACKNOWLEDGMENT ==");

  const revokeNote =
    `Dikembalikan ke antrean oleh smoke test ${runId}`;
  page = await getPage(detailUrl);
  page = await invokeServerActionForm({
    pageUri: detailUrl,
    pageHtml: page.html,
    marker: "Batalkan acknowledgment",
    fields: {
      notificationId,
      returnTo:
        `/notifications?notificationId=${notificationId}#detail`,
      note: revokeNote,
    },
    baseUrl: args.baseUrl,
  });

  assertTest(
    containsText(
      page.html,
      "Acknowledgment berhasil dibatalkan dan notification kembali open.",
    ),
    "Server Action revoke memberi feedback sukses",
  );

  detail = await getNotificationDetail(notificationId);

  assertTest(
    detail?.lifecycle_status_code === "OPEN" &&
      detail?.acknowledged_at == null &&
      detail?.acknowledged_by == null &&
      detail?.acknowledgment_note == null,
    "Revoke mengembalikan lifecycle ke OPEN",
  );

  history = await getNotificationHistory(notificationId);
  const revokeEvents = history.filter(
    (event) =>
      event.event_type_code === "ACKNOWLEDGMENT_REVOKED",
  );

  assertTest(
    revokeEvents.length === 1 &&
      revokeEvents[0]?.note === revokeNote,
    "Audit event ACKNOWLEDGMENT_REVOKED tercatat sekali",
  );

  assertTest(
    containsText(page.html, "Acknowledge notification"),
    "UI kembali menawarkan acknowledge setelah revoke",
  );

  console.log("\n== Cleanup fixture dan regression guard ==");

  removeNotificationFixture();
  removeSmokeUserStates();
  setSmokeProfileActive(smokeUserId, false);

  const remainingCount = Number(
    runSql(
      `
select count(*)::text
from notification.notifications
where source_snapshot ->> 'smokeSuite' =
      'notification-write-actions';
`,
      { tuplesOnly: true },
    ).trim(),
  );

  assertTest(
    remainingCount === 0,
    "Fixture notification dibersihkan",
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
where profile.user_id = ${sqlLiteral(smokeUserId)}::uuid;
`,
    { tuplesOnly: true },
  ).trim();

  assertTest(
    profileState === "false|0",
    "Admin smoke dinonaktifkan tanpa user state tersisa",
    profileState,
  );

  const npxCommand = process.platform === "win32" ? "npx.cmd" : "npx";

  runCommand(
    npxCommand,
    [
      "supabase",
      "test",
      "db",
      "supabase/tests/030_notification_lifecycle_functions.test.sql",
    ],
    {
      printStdout: true,
      printStderr: true,
    },
  );

  addResult(
    "Regression guard notification lifecycle tetap PASS",
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
    if (dbContainer) removeNotificationFixture();
  } catch (error) {
    exitCode = 1;
    console.error(
      `[CLEANUP FAIL] Fixture notification: ${
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

  console.log("\n== Ringkasan smoke test write actions ==");

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
    `${"Status".padEnd(widths.status)}  ${"Test".padEnd(widths.test)}  Detail`,
  );
  console.log(
    `${"-".repeat(widths.status)}  ${"-".repeat(widths.test)}  ------`,
  );

  for (const item of results) {
    console.log(
      `${item.status.padEnd(widths.status)}  ` +
        `${item.test.padEnd(widths.test)}  ${item.detail}`,
    );
  }

  const passed = results.filter(
    (item) => item.status === "PASS",
  ).length;
  const failed = results.filter(
    (item) => item.status === "FAIL",
  ).length;

  const color =
    failed === 0 && exitCode === 0 ? "\x1b[32m" : "\x1b[31m";

  console.log(
    `\n${color}PASS: ${passed} | FAIL: ${failed}\x1b[0m`,
  );
}

process.exitCode = exitCode;
