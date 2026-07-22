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
    throw new Error(
      `GET ${uri} gagal (${response.status}): ${html.slice(0, 2000)}`,
    );
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

function encoded(value) {
  return encodeURIComponent(String(value));
}

async function readBatchQuantity(batchId) {
  const rows = await restRows(
    `batch_inventory?organization_id=eq.${encoded(organizationId)}` +
      `&batch_id=eq.${encoded(batchId)}` +
      "&select=batch_id,product_id,batch_code,sellable_qty&limit=1",
  );
  return rows[0] ?? null;
}

async function readProductQuantity(productId) {
  const rows = await restRows(
    `product_inventory?organization_id=eq.${encoded(organizationId)}` +
      `&product_id=eq.${encoded(productId)}` +
      "&select=product_id,sellable_qty,reserved_qty,available_qty&limit=1",
  );
  return rows[0] ?? null;
}

async function readOpeningCutover(cutoverId) {
  const rows = await restRows(
    `opening_balance_cutovers?organization_id=eq.${encoded(organizationId)}` +
      `&cutover_id=eq.${encoded(cutoverId)}&select=*&limit=1`,
  );
  return rows[0] ?? null;
}

async function readOpeningLines(cutoverId) {
  return restRows(
    `opening_balance_cutover_lines?organization_id=eq.${encoded(organizationId)}` +
      `&cutover_id=eq.${encoded(cutoverId)}&select=*&order=line_no.asc`,
  );
}

async function readVerificationApplications(cutoverId) {
  return restRows(
    `opening_balance_verification_applications?organization_id=eq.${encoded(organizationId)}` +
      `&opening_balance_cutover_id=eq.${encoded(cutoverId)}` +
      "&select=*&order=verified_at.asc",
  );
}

async function latestLedgerSeq() {
  const rows = await restRows(
    `stock_ledger?organization_id=eq.${encoded(organizationId)}` +
      "&select=ledger_seq&order=ledger_seq.desc&limit=1",
  );
  return Number(rows[0]?.ledger_seq ?? 0);
}

async function postZeroVarianceStocktake({
  runId,
  batch,
  ordinal,
}) {
  const stocktakeKey = `${runId}:stocktake:${ordinal}`;
  const create = await rpc("create_stocktake", {
    p_organization_id: organizationId,
    p_idempotency_key: `${stocktakeKey}:create`,
    p_title: `Verifikasi saldo awal ${ordinal}`,
    p_stocktake_type_code: "CYCLE",
    p_mode_code: "CONTINUOUS",
    p_visibility_code: "NON_BLIND",
    p_scope: {
      mode: "BATCHES",
      batchIds: [batch.batch_id],
      bucketCodes: ["SELLABLE"],
      includeZeroSystemBalance: false,
      includeInactiveWithBalance: false,
      includeBlockedBatches: false,
      includeExpiredBatches: false,
    },
    p_planned_at: null,
    p_note: "Smoke first-stocktake verification saldo awal.",
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      ordinal,
      temporary: true,
    },
  });

  assertTest(
    create?.status === "DRAFT" && Boolean(create.stocktakeId),
    `Stocktake ${ordinal} dibuat sebagai Draft`,
    JSON.stringify(create),
  );

  const prepared = await rpc("prepare_stocktake", {
    p_organization_id: organizationId,
    p_idempotency_key: `${stocktakeKey}:prepare`,
    p_stocktake_id: create.stocktakeId,
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      ordinal,
      action: "prepare",
    },
  });

  assertTest(
    prepared?.status === "READY" && prepared.scopeLineCount === 1,
    `Stocktake ${ordinal} memvalidasi tepat satu scope`,
    JSON.stringify(prepared),
  );

  const started = await rpc("start_stocktake", {
    p_organization_id: organizationId,
    p_idempotency_key: `${stocktakeKey}:start`,
    p_stocktake_id: create.stocktakeId,
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      ordinal,
      action: "start",
    },
  });

  assertTest(
    started?.status === "COUNTING" && started.lineCount === 1,
    `Stocktake ${ordinal} masuk Counting`,
    JSON.stringify(started),
  );

  const countingLines = await restRows(
    `stocktake_non_blind_lines?organization_id=eq.${encoded(organizationId)}` +
      `&stocktake_id=eq.${encoded(create.stocktakeId)}` +
      "&select=*&order=line_no.asc",
  );
  const countingLine = countingLines[0];

  assertTest(
    countingLines.length === 1 &&
      countingLine?.batch_id === batch.batch_id &&
      countingLine?.bucket_code === "SELLABLE",
    `Stocktake ${ordinal} menghitung exact batch dan bucket`,
    JSON.stringify(countingLines),
  );

  const physicalQty = Number(countingLine.system_qty_at_snapshot);
  const count = await rpc("submit_stocktake_count", {
    p_organization_id: organizationId,
    p_idempotency_key: `${stocktakeKey}:count:1`,
    p_stocktake_id: create.stocktakeId,
    p_stocktake_line_id: countingLine.stocktake_line_id,
    p_physical_qty: physicalQty,
    p_zero_confirmed: physicalQty === 0,
    p_count_method_code: "MANUAL_ENTRY",
    p_note: "Physical count sama dengan ledger.",
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      ordinal,
      action: "count",
    },
  });

  assertTest(
    count?.status === "COUNTED" &&
      Number(count.varianceQty ?? 0) === 0,
    `Stocktake ${ordinal} menyimpan zero-variance count`,
    JSON.stringify(count),
  );

  const completed = await rpc("complete_stocktake_counting", {
    p_organization_id: organizationId,
    p_idempotency_key: `${stocktakeKey}:complete`,
    p_stocktake_id: create.stocktakeId,
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      ordinal,
      action: "complete-counting",
    },
  });

  assertTest(
    completed?.status === "REVIEW" &&
      Number(completed.varianceLineCount) === 0,
    `Stocktake ${ordinal} masuk Review tanpa variance`,
    JSON.stringify(completed),
  );

  const reviewLines = await restRows(
    `stocktake_review_lines?organization_id=eq.${encoded(organizationId)}` +
      `&stocktake_id=eq.${encoded(create.stocktakeId)}` +
      "&select=*&order=line_no.asc",
  );
  const reviewLine = reviewLines[0];

  assertTest(
    reviewLines.length === 1 &&
      Number(reviewLine?.variance_qty) === 0,
    `Stocktake ${ordinal} memiliki satu review line zero variance`,
    JSON.stringify(reviewLines),
  );

  const reviewed = await rpc("review_stocktake_line", {
    p_organization_id: organizationId,
    p_idempotency_key: `${stocktakeKey}:review:${reviewLine.version_no}`,
    p_stocktake_id: create.stocktakeId,
    p_stocktake_line_id: reviewLine.stocktake_line_id,
    p_expected_line_version: reviewLine.version_no,
    p_decision_code: "MATCHED",
    p_reason_code: null,
    p_review_note: "Physical count cocok dengan ledger.",
    p_exception_code: null,
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      ordinal,
      action: "review",
    },
  });

  assertTest(
    reviewed?.status === "REVIEWED" &&
      reviewed.decisionCode === "MATCHED",
    `Stocktake ${ordinal} direview sebagai MATCHED`,
    JSON.stringify(reviewed),
  );

  const detailRows = await restRows(
    `stocktake_details?organization_id=eq.${encoded(organizationId)}` +
      `&stocktake_id=eq.${encoded(create.stocktakeId)}` +
      "&select=*&limit=1",
  );
  const details = detailRows[0];

  assertTest(
    details?.status_code === "REVIEW" &&
      Number(details.version_no) > 0,
    `Stocktake ${ordinal} menyediakan version approval`,
    JSON.stringify(details),
  );

  const approval = await rpc("approve_stocktake", {
    p_organization_id: organizationId,
    p_idempotency_key: `${stocktakeKey}:approve:${details.version_no}`,
    p_stocktake_id: create.stocktakeId,
    p_expected_stocktake_version: details.version_no,
    p_confirmation: true,
    p_note: "Approval zero-variance verification.",
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      ordinal,
      action: "approve",
    },
  });

  assertTest(
    approval?.status === "APPROVED" &&
      Number(approval.approvalVersion) === 1,
    `Stocktake ${ordinal} memiliki approval immutable version 1`,
    JSON.stringify(approval),
  );

  const ledgerBefore = await latestLedgerSeq();
  const postingKey = `stocktake:${create.stocktakeId}:post:1`;
  const posting = await rpc("post_stocktake_adjustment", {
    p_organization_id: organizationId,
    p_idempotency_key: postingKey,
    p_stocktake_id: create.stocktakeId,
    p_approval_version: 1,
    p_confirmation: true,
    p_note: "Posting zero-variance first-stocktake verification.",
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      ordinal,
      action: "post",
    },
  });
  const ledgerAfter = await latestLedgerSeq();

  assertTest(
    posting?.status === "POSTED" &&
      Number(posting.nonzeroLineCount ?? 0) === 0,
    `Stocktake ${ordinal} diposting tanpa adjustment movement`,
    JSON.stringify(posting),
  );
  assertTest(
    ledgerAfter === ledgerBefore,
    `Zero variance stocktake ${ordinal} tidak menulis ledger`,
    JSON.stringify({ ledgerBefore, ledgerAfter }),
  );

  const postingLines = await restRows(
    `stocktake_posting_lines?organization_id=eq.${encoded(organizationId)}` +
      `&stocktake_id=eq.${encoded(create.stocktakeId)}` +
      `&posting_id=eq.${encoded(posting.postingId)}` +
      "&select=*&order=line_no.asc",
  );

  assertTest(
    postingLines.length === 1 &&
      postingLines[0]?.ledger_entry_id === null &&
      Number(postingLines[0]?.adjustment_qty) === 0,
    `Posting line ${ordinal} menyimpan zero variance tanpa ledger entry`,
    JSON.stringify(postingLines),
  );

  return {
    create,
    approval,
    posting,
    postingKey,
    countingLine,
    count,
  };
}

async function reverseCutover(cutoverId, runId) {
  const preview = await rpc("preview_opening_balance_reversal", {
    p_organization_id: organizationId,
    p_cutover_id: cutoverId,
  });

  assertTest(
    preview?.eligible === true && Boolean(preview.basisHash),
    "Cutover terverifikasi tetap menyediakan exact reversal preview",
    JSON.stringify(preview),
  );

  return rpc("reverse_opening_balance_cutover", {
    p_organization_id: organizationId,
    p_idempotency_key: `${runId}:cutover-reversal`,
    p_cutover_id: cutoverId,
    p_preview_basis_hash: preview.basisHash,
    p_confirmation: true,
    p_note: "Cleanup verification smoke melalui exact reversal.",
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
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

  const requiredPaths = [
    ".env.local",
    "package.json",
    "scripts/create-demo-admin.mjs",
    "scripts/test-opening-balance-verification-ui.mjs",
    "src/app/opening-balances/page.tsx",
    "src/app/stocktakes/actions.ts",
    "src/app/stocktakes/[stocktakeId]/page.tsx",
    "src/lib/stocktakes/queries.ts",
    "supabase/migrations/202607210010_opening_balance_cutover.sql",
    "supabase/migrations/202607210011_opening_balance_first_stocktake_verification.sql",
    "supabase/migrations/202607210012_opening_balance_exact_reversal.sql",
    "supabase/tests/047_opening_balance_first_stocktake_verification.test.sql",
  ];

  for (const requiredPath of requiredPaths) {
    let exists = true;
    try {
      await readFile(path.resolve(process.cwd(), requiredPath));
    } catch {
      exists = false;
    }
    assertTest(exists, `File tersedia: ${requiredPath}`);
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
  );

  const callbackUrl = new URL(
    verifyLocation,
    linkPayload.action_link,
  );
  const callbackParams = new URLSearchParams(
    callbackUrl.hash.replace(/^#/, ""),
  );
  accessToken = callbackParams.get("access_token") ?? "";
  assertTest(Boolean(accessToken), "Access token smoke tersedia");

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
    "Route opening balance anonim ditolak",
  );

  const runId = randomUUID();
  const batchRows = await restRows(
    `batch_inventory?organization_id=eq.${encoded(organizationId)}` +
      "&status_code=eq.ACTIVE&sellable_qty=gt.0" +
      "&select=batch_id,product_id,sku,product_name,batch_code,expiry_date,sellable_qty" +
      "&order=product_id.asc,expiry_date.asc,batch_code.asc",
  );
  const uniqueBatches = [];
  const seen = new Set();

  for (const batch of batchRows) {
    if (seen.has(batch.batch_id)) continue;
    seen.add(batch.batch_id);
    uniqueBatches.push(batch);
    if (uniqueBatches.length === 2) break;
  }

  assertTest(
    uniqueBatches.length === 2,
    "Dua batch aktif tersedia untuk partial-scope verification",
    JSON.stringify(batchRows.slice(0, 5)),
  );

  const affectedProductIds = [
    ...new Set(uniqueBatches.map((batch) => batch.product_id)),
  ];
  const baselineBatches = Object.fromEntries(
    await Promise.all(
      uniqueBatches.map(async (batch) => [
        batch.batch_id,
        await readBatchQuantity(batch.batch_id),
      ]),
    ),
  );
  const baselineProducts = Object.fromEntries(
    await Promise.all(
      affectedProductIds.map(async (productId) => [
        productId,
        await readProductQuantity(productId),
      ]),
    ),
  );

  const sourceRef = `OBV-UI-${runId.slice(0, 8)}`;
  const created = await rpc("create_opening_balance_cutover", {
    p_organization_id: organizationId,
    p_source_ref: sourceRef,
    p_cutover_at: new Date().toISOString(),
    p_source_estimate_ref: `BA-OBV-UI-${runId}`,
    p_note: "Two-line first-stocktake verification smoke fixture.",
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      temporary: true,
    },
  });
  const openingLines = uniqueBatches.map((batch, index) => ({
    productId: batch.product_id,
    batchId: batch.batch_id,
    bucketCode: "SELLABLE",
    quantity: 1,
    batchIdentityVerified: true,
    exceptionReference: null,
    sourceLineRef: `OBV-UI-${index + 1}`,
  }));
  const saved = await rpc("save_opening_balance_cutover_draft", {
    p_organization_id: organizationId,
    p_cutover_id: created.cutoverId,
    p_expected_row_version: created.rowVersion,
    p_cutover_at: new Date().toISOString(),
    p_source_estimate_ref: `BA-OBV-UI-${runId}`,
    p_note: "Two-line first-stocktake verification smoke fixture.",
    p_lines: openingLines,
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      temporary: true,
    },
  });
  await rpc("submit_opening_balance_cutover_review", {
    p_organization_id: organizationId,
    p_cutover_id: created.cutoverId,
    p_expected_row_version: saved.rowVersion,
  });
  const preview = await rpc("preview_opening_balance_cutover", {
    p_organization_id: organizationId,
    p_cutover_id: created.cutoverId,
  });

  assertTest(
    preview?.eligible === true && preview.lineCount === 2,
    "Preview cutover dua baris eligible",
    JSON.stringify(preview),
  );

  const posted = await rpc("post_opening_balance_cutover", {
    p_organization_id: organizationId,
    p_idempotency_key: `${runId}:cutover-post`,
    p_cutover_id: created.cutoverId,
    p_preview_basis_hash: preview.basisHash,
    p_confirmation: true,
  });

  assertTest(
    posted?.status === "POSTED" && posted.lineCount === 2,
    "Cutover dua baris diposting",
    JSON.stringify(posted),
  );

  let cutover = await readOpeningCutover(created.cutoverId);
  let cutoverLines = await readOpeningLines(created.cutoverId);

  assertTest(
    cutover?.verification_status_code === "UNVERIFIED" &&
      Number(cutover.verified_line_count) === 0 &&
      Number(cutover.unverified_line_count) === 2,
    "Cutover posted mulai UNVERIFIED 0/2",
    JSON.stringify(cutover),
  );
  assertTest(
    cutoverLines.every(
      (line) => line.verification_status_code === "UNVERIFIED",
    ),
    "Kedua line mulai UNVERIFIED",
    JSON.stringify(cutoverLines),
  );

  const first = await postZeroVarianceStocktake({
    runId,
    batch: uniqueBatches[0],
    ordinal: 1,
  });

  cutover = await readOpeningCutover(created.cutoverId);
  cutoverLines = await readOpeningLines(created.cutoverId);
  let applications = await readVerificationApplications(created.cutoverId);

  assertTest(
    cutover?.verification_status_code === "PARTIALLY_VERIFIED" &&
      Number(cutover.verified_line_count) === 1 &&
      Number(cutover.unverified_line_count) === 1,
    "Stocktake pertama membuat cutover PARTIALLY_VERIFIED 1/1",
    JSON.stringify(cutover),
  );
  assertTest(
    cutoverLines.filter(
      (line) => line.verification_status_code === "VERIFIED",
    ).length === 1 &&
      cutoverLines.filter(
        (line) => line.verification_status_code === "UNVERIFIED",
      ).length === 1,
    "Partial scope hanya memverifikasi exact opening line",
    JSON.stringify(cutoverLines),
  );
  assertTest(
    applications.length === 1 &&
      applications[0]?.stocktake_id === first.create.stocktakeId &&
      Number(applications[0]?.stocktake_variance_quantity) === 0,
    "Satu immutable zero-variance verification application tercatat",
    JSON.stringify(applications),
  );

  let page = await getPage(
    `${args.baseUrl}/opening-balances?cutoverId=${created.cutoverId}#detail`,
  );
  assertTest(
    containsText(page.html, "PARTIALLY_VERIFIED") &&
      containsText(page.html, "Bukti verifikasi immutable") &&
      containsText(page.html, first.create.stocktakeNo) &&
      containsText(
        page.html,
        "Zero variance tanpa movement adjustment",
      ) &&
      containsText(page.html, "Approval version 1"),
    "UI partial verification menampilkan status dan evidence lengkap",
  );

  const firstStocktakePage = await getPage(
    `${args.baseUrl}/stocktakes/${first.create.stocktakeId}`,
  );
  assertTest(
    containsText(firstStocktakePage.html, first.create.stocktakeNo) &&
      containsText(firstStocktakePage.html, "Adjustment berhasil diposting"),
    "Link evidence membuka stocktake posted",
  );

  const firstReplay = await rpc("post_stocktake_adjustment", {
    p_organization_id: organizationId,
    p_idempotency_key: first.postingKey,
    p_stocktake_id: first.create.stocktakeId,
    p_approval_version: 1,
    p_confirmation: true,
    p_note: "Posting zero-variance first-stocktake verification.",
    p_metadata: {
      source: "opening-balance-verification-ui-smoke",
      runId,
      ordinal: 1,
      action: "post",
    },
  });
  applications = await readVerificationApplications(created.cutoverId);

  assertTest(
    firstReplay.postingId === first.posting.postingId &&
      applications.length === 1,
    "Replay stocktake pertama tidak menggandakan verification effect",
    JSON.stringify({ firstReplay, applications }),
  );

  const second = await postZeroVarianceStocktake({
    runId,
    batch: uniqueBatches[1],
    ordinal: 2,
  });

  cutover = await readOpeningCutover(created.cutoverId);
  cutoverLines = await readOpeningLines(created.cutoverId);
  applications = await readVerificationApplications(created.cutoverId);

  assertTest(
    cutover?.verification_status_code === "VERIFIED" &&
      Number(cutover.verified_line_count) === 2 &&
      Number(cutover.unverified_line_count) === 0,
    "Stocktake kedua membuat cutover VERIFIED 2/0",
    JSON.stringify(cutover),
  );
  assertTest(
    cutoverLines.every(
      (line) =>
        line.verification_status_code === "VERIFIED" &&
        line.verification_application_id &&
        line.verifying_stocktake_approval_id &&
        line.verifying_stocktake_posting_id &&
        line.verifying_stocktake_posting_line_id &&
        line.verifying_count_attempt_id,
    ),
    "Kedua line memiliki linkage count, approval, posting, dan evidence",
    JSON.stringify(cutoverLines),
  );
  assertTest(
    applications.length === 2 &&
      applications.every(
        (application) =>
          Number(application.stocktake_variance_quantity) === 0 &&
          application.stocktake_adjustment_ledger_entry_id === null,
      ),
    "Dua zero-variance evidence tersimpan tanpa adjustment ledger",
    JSON.stringify(applications),
  );

  page = await getPage(
    `${args.baseUrl}/opening-balances?cutoverId=${created.cutoverId}#detail`,
  );
  assertTest(
    containsText(page.html, "VERIFIED") &&
      containsText(page.html, first.create.stocktakeNo) &&
      containsText(page.html, second.create.stocktakeNo) &&
      containsText(page.html, "Verification application") &&
      containsText(page.html, "Posting line") &&
      containsText(page.html, "Count attempt"),
    "UI full verification bertahan setelah refresh",
  );

  const secondStocktakePage = await getPage(
    `${args.baseUrl}/stocktakes/${second.create.stocktakeId}`,
  );
  assertTest(
    containsText(secondStocktakePage.html, second.create.stocktakeNo) &&
      containsText(secondStocktakePage.html, "Adjustment berhasil diposting"),
    "Stocktake kedua memiliki audit posting",
  );

  const reversal = await reverseCutover(created.cutoverId, runId);
  assertTest(
    reversal?.status === "REVERSED",
    "Cutover terverifikasi dibersihkan melalui exact reversal",
    JSON.stringify(reversal),
  );

  const reversedPage = await getPage(
    `${args.baseUrl}/opening-balances?cutoverId=${created.cutoverId}#detail`,
  );
  assertTest(
    containsText(reversedPage.html, "Cutover sudah dibalik") &&
      containsText(reversedPage.html, first.create.stocktakeNo) &&
      containsText(reversedPage.html, second.create.stocktakeNo),
    "Reversal mempertahankan immutable verification evidence",
  );

  const finalBatches = Object.fromEntries(
    await Promise.all(
      uniqueBatches.map(async (batch) => [
        batch.batch_id,
        await readBatchQuantity(batch.batch_id),
      ]),
    ),
  );
  const finalProducts = Object.fromEntries(
    await Promise.all(
      affectedProductIds.map(async (productId) => [
        productId,
        await readProductQuantity(productId),
      ]),
    ),
  );

  const batchQuantitiesRestored = uniqueBatches.every(
    (batch) =>
      Number(finalBatches[batch.batch_id]?.sellable_qty) ===
      Number(baselineBatches[batch.batch_id]?.sellable_qty),
  );
  const productQuantitiesRestored = affectedProductIds.every(
    (productId) =>
      Number(finalProducts[productId]?.sellable_qty) ===
        Number(baselineProducts[productId]?.sellable_qty) &&
      Number(finalProducts[productId]?.reserved_qty) ===
        Number(baselineProducts[productId]?.reserved_qty),
  );

  assertTest(
    batchQuantitiesRestored && productQuantitiesRestored,
    "Cleanup mengembalikan quantity projection ke baseline",
    JSON.stringify({
      baselineBatches,
      finalBatches,
      baselineProducts,
      finalProducts,
    }),
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
  const passed = results.filter(
    (item) => item.status === "PASS",
  ).length;
  console.log(
    `\nOpening balance verification UI smoke: ${passed}/${results.length} PASS`,
  );
  process.exitCode = exitCode;
}
