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

const results = [];
let exitCode = 0;
let ownedServer = null;
let serverStdout = "";
let serverStderr = "";
let supabaseUrl = "";
let publishableKey = "";
let serviceKey = "";
let accessToken = "";
let organizationId = "";

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
    const mapping = {
      "base-url": "baseUrl",
      email: "email",
      password: "password",
      name: "displayName",
      "startup-timeout-seconds": "startupTimeoutSeconds",
    };
    const target = mapping[key];

    if (!target || !value || value.startsWith("--")) {
      throw new Error(`Argumen --${key} tidak valid.`);
    }

    args[target] =
      target === "startupTimeoutSeconds" ? Number(value) : value;
    index += 1;
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

function isLoopback(hostname) {
  return ["127.0.0.1", "localhost", "::1"].includes(hostname);
}

function addResult(name, passed, detail = "") {
  results.push({
    status: passed ? "PASS" : "FAIL",
    test: name,
    detail,
  });
  console.log(`${passed ? "[PASS]" : "[FAIL]"} ${name}`);

  if (!passed) {
    exitCode = 1;
    if (detail) console.log(`       ${detail}`);
  }
}

function assertTest(condition, name, detail = "") {
  addResult(name, Boolean(condition), detail);

  if (!condition) {
    throw new Error(`Assertion gagal: ${name}`);
  }
}

function quoteWindowsCommandArgument(value) {
  const normalized = String(value);
  if (!/[ \t"&|<>^()%!]/.test(normalized)) return normalized;
  return `"${normalized.replace(/"/g, '""')}"`;
}

function runCommand(command, args) {
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
    shell: false,
    windowsHide: true,
    maxBuffer: 20 * 1024 * 1024,
  });

  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `${command} gagal.\n${result.stdout ?? ""}\n${result.stderr ?? ""}`,
    );
  }

  return result.stdout ?? "";
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
      `RPC ${name} gagal (${response.status}): ${JSON.stringify(payload)}`,
    );
  }

  return payload;
}

async function restRows(resourcePath) {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/${resourcePath}`,
    {
      headers: apiHeaders(),
      cache: "no-store",
    },
  );
  const payload = await parseResponse(response);

  if (!response.ok) {
    throw new Error(
      `REST ${resourcePath} gagal (${response.status}): ${JSON.stringify(payload)}`,
    );
  }

  return Array.isArray(payload) ? payload : [];
}

function cookieHeader() {
  return `glowlab_access_token=${accessToken}`;
}

async function getPage(uri) {
  const response = await fetch(uri, {
    headers: { Cookie: cookieHeader() },
    redirect: "manual",
    cache: "no-store",
  });
  const html = await response.text();

  if (!response.ok) {
    throw new Error(`GET ${uri} gagal (${response.status}): ${html.slice(0, 2000)}`);
  }

  return { uri: response.url || uri, html };
}

function normalizeText(value) {
  return String(value)
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function containsText(html, text) {
  return normalizeText(html).includes(normalizeText(text));
}

function findForm(html, marker) {
  const forms = html.match(/<form\b[^>]*>.*?<\/form>/gis) ?? [];
  const form = forms.find((candidate) =>
    containsText(candidate, marker),
  );

  if (!form) throw new Error(`Form "${marker}" tidak ditemukan.`);
  return form;
}

function hasForm(html, marker) {
  const forms = html.match(/<form\b[^>]*>.*?<\/form>/gis) ?? [];
  return forms.some((candidate) => containsText(candidate, marker));
}

function findServerActionName(formHtml) {
  const match = formHtml.match(/name="(\$ACTION_ID_[^"]+)"/i);
  if (!match) throw new Error("Nama Server Action tidak ditemukan.");
  return match[1];
}

async function invokeServerActionForm({
  page,
  marker,
  fields,
  baseUrl,
}) {
  const formHtml = findForm(page.html, marker);
  const actionName = findServerActionName(formHtml);
  const form = new FormData();
  form.append(actionName, "");

  for (const [key, value] of Object.entries(fields)) {
    form.append(key, value == null ? "" : String(value));
  }

  const response = await fetch(page.uri, {
    method: "POST",
    headers: {
      Cookie: cookieHeader(),
      Origin: new URL(baseUrl).origin,
      Referer: page.uri,
    },
    body: form,
    redirect: "manual",
  });

  const body = await response.text();

  if (![302, 303, 307, 308].includes(response.status)) {
    throw new Error(
      `Server Action "${marker}" tidak redirect. ` +
        `Status=${response.status} Body=${body.slice(0, 2000)}`,
    );
  }

  const location = response.headers.get("location");
  if (!location) throw new Error("Location redirect tidak tersedia.");

  return getPage(new URL(location, page.uri).toString());
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
    if (ownedServer?.exitCode != null) return false;
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

function stopServer(keepRunning) {
  if (!ownedServer || keepRunning) return;

  if (process.platform === "win32") {
    spawnSync(
      "taskkill",
      ["/PID", String(ownedServer.pid), "/T", "/F"],
      { windowsHide: true, stdio: "ignore" },
    );
    return;
  }

  try {
    process.kill(-ownedServer.pid, "SIGTERM");
  } catch {
    ownedServer.kill("SIGTERM");
  }
}

function datetimeLocal() {
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

async function reverseCutover(cutoverId, runId) {
  const preview = await rpc("preview_opening_balance_reversal", {
    p_organization_id: organizationId,
    p_cutover_id: cutoverId,
  });

  return rpc("reverse_opening_balance_cutover", {
    p_organization_id: organizationId,
    p_idempotency_key: `opening-balance-smoke:${runId}:reverse:${cutoverId}`,
    p_cutover_id: cutoverId,
    p_preview_basis_hash: preview.basisHash,
    p_confirmation: true,
    p_note: "Cleanup smoke test melalui exact reversal.",
    p_metadata: {
      source: "opening-balance-ui-smoke",
      runId,
      temporary: true,
    },
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const uri = new URL(args.baseUrl);

  if (!args.allowRemote && !isLoopback(uri.hostname)) {
    throw new Error("Smoke test hanya diizinkan pada host loopback.");
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
  serviceKey = String(env.SUPABASE_SECRET_KEY ?? "");

  assertTest(
    publishableKey && !publishableKey.includes("REPLACE_ME"),
    "Publishable key lokal tersedia",
  );
  assertTest(
    serviceKey && !serviceKey.includes("REPLACE_ME"),
    "Secret key lokal tersedia untuk trusted Auth bootstrap",
  );

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

  const linkResponse = await fetch(
    `${supabaseUrl}/auth/v1/admin/generate_link`,
    {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        type: "magiclink",
        email: args.email,
      }),
    },
  );
  const linkPayload = await parseResponse(linkResponse);
  assertTest(
    linkResponse.ok &&
      typeof linkPayload?.action_link === "string",
    "Trusted magic link Admin berhasil dibuat",
    JSON.stringify(linkPayload),
  );

  const verifyResponse = await fetch(linkPayload.action_link, {
    method: "GET",
    redirect: "manual",
    cache: "no-store",
  });
  const verifyLocation = verifyResponse.headers.get("location");

  assertTest(
    [302, 303, 307, 308].includes(verifyResponse.status) &&
      Boolean(verifyLocation),
    "Magic link menghasilkan redirect sesi Auth",
    `status=${verifyResponse.status} location=${verifyLocation ?? "-"}`,
  );

  const callbackUrl = new URL(
    verifyLocation,
    linkPayload.action_link,
  );
  const callbackParams = new URLSearchParams(
    callbackUrl.hash.replace(/^#/, ""),
  );

  accessToken = callbackParams.get("access_token") ?? "";

  assertTest(
    Boolean(accessToken),
    "Access token smoke tersedia",
    verifyLocation ?? "Redirect Auth tidak tersedia.",
  );

  const profileRows = await restRows(
    "current_admin_profile?select=organization_id&limit=1",
  );
  organizationId = profileRows[0]?.organization_id;
  assertTest(Boolean(organizationId), "Organization Admin ter-resolve");

  if (!(await isServerReady(args.baseUrl))) {
    startServer(args.baseUrl);
    assertTest(
      await waitForServer(args.baseUrl, args.startupTimeoutSeconds),
      "Next.js dev server siap",
      serverStderr,
    );
  } else {
    addResult("Next.js dev server siap", true, "server sudah aktif");
  }

  const unauthenticated = await fetch(
    `${args.baseUrl}/opening-balances`,
    { redirect: "manual" },
  );
  assertTest(
    [302, 303, 307, 308].includes(unauthenticated.status) &&
      unauthenticated.headers.get("location")?.includes("/login"),
    "Route anonim ditolak",
  );

  const runId = randomUUID();
  const sourceRef = `OB-SMOKE-${runId.slice(0, 8)}`;
  const batches = await restRows(
    `batch_inventory?organization_id=eq.${encodeURIComponent(organizationId)}` +
      "&status_code=eq.ACTIVE&select=product_id,batch_id,sku,batch_code,expiry_date" +
      "&order=expiry_date.desc&limit=1",
  );
  const batch = batches[0];
  assertTest(Boolean(batch), "Fixture batch aktif tersedia");

  let page = await getPage(`${args.baseUrl}/opening-balances`);
  assertTest(
    containsText(page.html, "Saldo Awal produksi yang dapat diaudit"),
    "Halaman authenticated dapat dirender",
  );
  assertTest(
    hasForm(page.html, "Buat draft saldo awal"),
    "Form pembuatan draft tersedia",
  );

  page = await invokeServerActionForm({
    page,
    marker: "Buat draft saldo awal",
    baseUrl: args.baseUrl,
    fields: {
      sourceRef,
      cutoverAt: datetimeLocal(),
      sourceEstimateRef: `BA-SMOKE-${runId}`,
      note: "Fixture sementara untuk smoke UI saldo awal.",
    },
  });
  assertTest(
    containsText(page.html, "dibuat sebagai draft"),
    "Server Action membuat draft",
  );

  const selectedRows = await restRows(
    `opening_balance_cutovers?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&source_ref=eq.${encodeURIComponent(sourceRef)}&select=*&limit=1`,
  );
  const cutover = selectedRows[0];
  assertTest(cutover?.status_code === "DRAFT", "Draft persisten di read model");

  const lines = [
    {
      productId: batch.product_id,
      batchId: batch.batch_id,
      bucketCode: "SELLABLE",
      quantity: 1,
      batchIdentityVerified: true,
      exceptionReference: null,
      sourceLineRef: "SMOKE-1",
    },
  ];

  page = await invokeServerActionForm({
    page,
    marker: "Simpan draft saldo awal",
    baseUrl: args.baseUrl,
    fields: {
      cutoverId: cutover.cutover_id,
      rowVersion: cutover.row_version,
      cutoverAt: datetimeLocal(),
      sourceEstimateRef: `BA-SMOKE-${runId}`,
      note: "Fixture sementara untuk smoke UI saldo awal.",
      linesJson: JSON.stringify(lines),
    },
  });
  assertTest(
    containsText(page.html, "Draft tersimpan"),
    "Server Action menyimpan baris draft",
  );

  const savedRows = await restRows(
    `opening_balance_cutovers?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&cutover_id=eq.${cutover.cutover_id}&select=*&limit=1`,
  );
  const saved = savedRows[0];
  assertTest(saved?.line_count === 1, "Satu baris draft tersimpan");

  const ledgerBefore = await restRows(
    `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}` +
      "&select=ledger_seq&order=ledger_seq.desc&limit=1",
  );

  page = await invokeServerActionForm({
    page,
    marker: "Kirim ke review",
    baseUrl: args.baseUrl,
    fields: {
      cutoverId: saved.cutover_id,
      rowVersion: saved.row_version,
    },
  });
  assertTest(
    containsText(page.html, "Preview authoritative"),
    "Review menampilkan preview authoritative",
  );
  assertTest(
    hasForm(page.html, "Posting Saldo Awal"),
    "Preview eligible menyediakan konfirmasi final",
  );

  const ledgerAfterPreview = await restRows(
    `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}` +
      "&select=ledger_seq&order=ledger_seq.desc&limit=1",
  );
  assertTest(
    JSON.stringify(ledgerAfterPreview) === JSON.stringify(ledgerBefore),
    "Preview tidak mengubah ledger",
  );

  const preview = await rpc("preview_opening_balance_cutover", {
    p_organization_id: organizationId,
    p_cutover_id: saved.cutover_id,
  });
  assertTest(preview.eligible === true, "Database menyatakan preview eligible");

  page = await invokeServerActionForm({
    page,
    marker: "Posting Saldo Awal",
    baseUrl: args.baseUrl,
    fields: {
      cutoverId: saved.cutover_id,
      previewBasisHash: preview.basisHash,
      intentId: runId,
      confirmation: "on",
    },
  });
  assertTest(
    containsText(page.html, "berhasil diposting"),
    "Server Action posting berhasil",
  );
  assertTest(
    containsText(page.html, "UNVERIFIED"),
    "Status sesudah posting tetap UNVERIFIED",
  );
  assertTest(
    !hasForm(page.html, "Posting Saldo Awal"),
    "Dokumen posted tidak menyediakan posting ulang",
  );

  const postedRows = await restRows(
    `opening_balance_cutovers?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&cutover_id=eq.${saved.cutover_id}&select=*&limit=1`,
  );
  const posted = postedRows[0];
  assertTest(posted?.operational_status_code === "ACTIVE", "Cutover menjadi aktif");
  assertTest(posted?.verification_status_code === "UNVERIFIED", "Read model UNVERIFIED");

  const entryRows = await restRows(
    `stock_ledger?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&transaction_id=eq.${posted.transaction_id}&select=*`,
  );
  assertTest(
    entryRows.length === 1 && Number(entryRows[0].quantity_delta) === 1,
    "Ledger menerima satu INITIAL_BALANCE movement",
  );

  const replay = await rpc("post_opening_balance_cutover", {
    p_organization_id: organizationId,
    p_idempotency_key: `opening-balance:${saved.cutover_id}:post:${runId}`,
    p_cutover_id: saved.cutover_id,
    p_preview_basis_hash: preview.basisHash,
    p_confirmation: true,
  });
  assertTest(
    replay.transactionId === posted.transaction_id,
    "Replay idempoten mengembalikan transaksi yang sama",
  );

  const refreshed = await getPage(
    `${args.baseUrl}/opening-balances?cutoverId=${saved.cutover_id}#detail`,
  );
  assertTest(
    containsText(refreshed.html, posted.cutover_no) &&
      containsText(refreshed.html, "Ledger drill-down"),
    "Detail dan feedback bertahan setelah refresh",
  );

  const replacementSourceRef = `OB-SMOKE-REPL-${runId.slice(0, 8)}`;
  const replacement = await rpc("create_opening_balance_cutover", {
    p_organization_id: organizationId,
    p_source_ref: replacementSourceRef,
    p_cutover_at: new Date().toISOString(),
    p_source_estimate_ref: `BA-SMOKE-REPL-${runId}`,
    p_note: "Fixture replacement untuk menguji active-cutover blocker.",
    p_metadata: {
      source: "opening-balance-ui-smoke",
      runId,
      replacement: true,
    },
  });
  const replacementSaved = await rpc(
    "save_opening_balance_cutover_draft",
    {
      p_organization_id: organizationId,
      p_cutover_id: replacement.cutoverId,
      p_expected_row_version: replacement.rowVersion,
      p_cutover_at: new Date().toISOString(),
      p_source_estimate_ref: `BA-SMOKE-REPL-${runId}`,
      p_note: "Fixture replacement untuk menguji active-cutover blocker.",
      p_lines: lines,
      p_metadata: {
        source: "opening-balance-ui-smoke",
        runId,
        replacement: true,
      },
    },
  );
  await rpc("submit_opening_balance_cutover_review", {
    p_organization_id: organizationId,
    p_cutover_id: replacement.cutoverId,
    p_expected_row_version: replacementSaved.rowVersion,
  });

  const blockedPage = await getPage(
    `${args.baseUrl}/opening-balances?cutoverId=${replacement.cutoverId}#preview`,
  );
  assertTest(
    containsText(blockedPage.html, "Diblokir") &&
      !hasForm(blockedPage.html, "Posting Saldo Awal"),
    "Active cutover menghasilkan blocked preview tanpa commit action",
  );

  await reverseCutover(saved.cutover_id, runId);
  const reversedRows = await restRows(
    `opening_balance_cutovers?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&cutover_id=eq.${saved.cutover_id}&select=*&limit=1`,
  );
  assertTest(
    reversedRows[0]?.operational_status_code === "REVERSED",
    "Cutover pertama dibersihkan melalui exact reversal",
  );

  const replacementPreview = await rpc(
    "preview_opening_balance_cutover",
    {
      p_organization_id: organizationId,
      p_cutover_id: replacement.cutoverId,
    },
  );
  assertTest(
    replacementPreview.eligible === true,
    "Replacement cutover eligible setelah reversal",
  );

  await rpc("post_opening_balance_cutover", {
    p_organization_id: organizationId,
    p_idempotency_key:
      `opening-balance-smoke:${runId}:replacement-post`,
    p_cutover_id: replacement.cutoverId,
    p_preview_basis_hash: replacementPreview.basisHash,
    p_confirmation: true,
  });
  await reverseCutover(replacement.cutoverId, `${runId}:replacement`);

  const replacementRows = await restRows(
    `opening_balance_cutovers?organization_id=eq.${encodeURIComponent(organizationId)}` +
      `&cutover_id=eq.${replacement.cutoverId}&select=*&limit=1`,
  );
  assertTest(
    replacementRows[0]?.operational_status_code === "REVERSED",
    "Replacement fixture diposting lalu dibersihkan melalui exact reversal",
  );

  const fatalPattern =
    /(uncaught|unhandled|referenceerror|typeerror|syntaxerror|hydration failed)/i;
  assertTest(
    !fatalPattern.test(`${serverStdout}\n${serverStderr}`),
    "Tidak ada browser/server fatal error",
    serverStderr,
  );
}

const args = parseArgs(process.argv.slice(2));

try {
  await main();
} catch (error) {
  addResult(
    "Smoke workflow selesai tanpa exception",
    false,
    error instanceof Error ? error.stack ?? error.message : String(error),
  );
} finally {
  stopServer(args.keepServerRunning);
  console.log(
    `\nOpening balance UI smoke: ${results.filter((item) => item.status === "PASS").length}/${results.length} PASS`,
  );
  process.exitCode = exitCode;
}
