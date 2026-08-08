import { spawn, spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import process from "node:process";

const baseUrl = process.env.TODAY_CONTROL_CENTER_SMOKE_URL ?? "http://127.0.0.1:3000";
const serverPort = new URL(baseUrl).port || "3000";
const password = process.env.TODAY_CONTROL_CENTER_SMOKE_PASSWORD ?? "LocalSmoke123!";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const results = [];
let server;
let supabaseUrl = "";
let publishableKey = "";
let serviceKey = "";
let accessToken = "";
let organizationId = "";

function check(name, condition, detail = "") {
  if (!condition) throw new Error(`${name}${detail ? `: ${detail}` : ""}`);
  results.push(name);
  console.log(`[PASS] ${name}${detail ? ` — ${detail}` : ""}`);
}

function run(command, args, input) {
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    input,
    encoding: "utf8",
    windowsHide: true,
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} gagal (${result.status})\n${result.stdout}\n${result.stderr}`);
  return result.stdout ?? "";
}

function resolveDbContainer() {
  return run("docker", ["ps", "--format", "{{.Names}}"])
    .split(/\r?\n/)
    .find((name) => name.startsWith("supabase_db_"));
}

function runSql(sql) {
  const db = resolveDbContainer();
  if (!db) throw new Error("Container Supabase lokal tidak ditemukan.");
  return run("docker", ["exec", "-i", db, "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-q", "-v", "ON_ERROR_STOP=1"], sql);
}

function parseJsonLine(output) {
  const line = output.split(/\r?\n/).map((item) => item.trim()).findLast((item) => item.startsWith("{") || item.startsWith("["));
  if (!line) throw new Error(`SQL tidak mengembalikan JSON: ${output.slice(-2000)}`);
  return JSON.parse(line);
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

async function loadEnv() {
  const raw = await readFile(".env.local", "utf8");
  const env = Object.fromEntries(raw.split(/\r?\n/).filter((line) => line.trim() && !line.trimStart().startsWith("#")).map((line) => {
    const separator = line.indexOf("=");
    return [line.slice(0, separator).trim(), line.slice(separator + 1).trim().replace(/^['"]|['"]$/g, "")];
  }));
  supabaseUrl = String(env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321").replace(/\/$/, "");
  publishableKey = String(env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "");
  serviceKey = String(env.SUPABASE_SECRET_KEY ?? "");
  check("Konfigurasi Supabase lokal tersedia", Boolean(publishableKey && serviceKey));
}

async function responseJson(response) {
  const raw = await response.text();
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return raw; }
}

async function login() {
  const admin = parseJsonLine(runSql(`select jsonb_build_object('email', lower(auth_user.email), 'userId', profile.user_id) from app.user_profiles profile join auth.users auth_user on auth_user.id = profile.user_id where profile.employee_code = 'DEMO-ADMIN' and profile.role_code = 'ADMIN' order by profile.is_active desc, profile.created_at asc limit 1;`));
  const email = String(admin.email ?? "");
  const userId = String(admin.userId ?? "");
  check("Fixture Admin demo tersedia", email.includes("@") && UUID.test(userId));
  runSql(`update app.user_profiles set is_active = true where user_id = '${userId}'::uuid;`);
  const passwordResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users/${userId}`, {
    method: "PUT",
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ password, email_confirm: true }),
  });
  check("Password Admin demo siap", passwordResponse.ok);
  const tokenResponse = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: publishableKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const token = await responseJson(tokenResponse);
  check("Login Admin berhasil", tokenResponse.ok && Boolean(token?.access_token));
  accessToken = String(token.access_token);
  const profileResponse = await fetch(`${supabaseUrl}/rest/v1/current_admin_profile?select=*`, { headers: apiHeaders() });
  const profile = await responseJson(profileResponse);
  organizationId = String(profile?.[0]?.organization_id ?? "");
  check("Scope organisasi berasal dari profil Admin", UUID.test(organizationId));
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

async function rpc(body) {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/today_control_center_work_items`, {
    method: "POST",
    headers: apiHeaders(),
    body: JSON.stringify(body),
    cache: "no-store",
  });
  const payload = await responseJson(response);
  if (!response.ok) throw new Error(`RPC work item gagal (${response.status}): ${JSON.stringify(payload)}`);
  return payload;
}

async function waitReady() {
  for (let attempt = 0; attempt < 90; attempt += 1) {
    try {
      const response = await fetch(`${baseUrl}/login`);
      if (response.status === 200) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error("Next server tidak siap");
}

async function startServerIfNeeded() {
  const health = await fetch(`${baseUrl}/login`).catch(() => null);
  if (health?.status === 200) return;
  server = spawn(process.execPath, ["node_modules/next/dist/bin/next", "dev", "--hostname", "127.0.0.1", "--port", serverPort], { stdio: "ignore", windowsHide: true });
  await waitReady();
}

function cookie() { return `glowlab_access_token=${accessToken}`; }

async function page(path, authenticated = true) {
  const uri = new URL(path, baseUrl).toString();
  const response = await fetch(uri, {
    headers: authenticated ? { Cookie: cookie() } : {},
    redirect: "manual",
  });
  return { uri, response, html: await response.text() };
}

function stateSnapshot() {
  return parseJsonLine(runSql(`select jsonb_build_object(
    'ledger', (select count(*) from inventory.stock_ledger_entries),
    'transactions', (select count(*) from inventory.stock_transactions),
    'reservations', (select count(*) from inventory.stock_reservations),
    'productPositions', (select count(*) from inventory.stock_product_positions),
    'batchBalances', (select count(*) from inventory.stock_batch_balances),
    'notifications', (select count(*) from notification.notifications),
    'outbox', (select count(*) from notification.outbox_events),
    'ruleRuns', (select count(*) from notification.rule_runs),
    'returns', (select count(*) from operations.returns),
    'claims', (select count(*) from operations.return_claims),
    'stocktakes', (select count(*) from operations.stocktakes),
    'importJobs', (select count(*) from integration.import_jobs)
  );`));
}

function cursorFor(row) {
  return Buffer.from(JSON.stringify({
    severityRank: row.sort_severity_rank,
    sortAt: row.sort_at,
    workItemId: row.work_item_id,
  })).toString("base64url");
}

function provisionReadOnlyFixture() {
  const fixture = parseJsonLine(runSql(`
    select jsonb_build_object(
      'batchId', (
        select balance.batch_id
        from inventory.stock_batch_balances balance
        where balance.organization_id = ${sqlLiteral(organizationId)}::uuid
        order by balance.batch_id
        limit 1
      ),
      'ruleId', (
        select rule.id
        from notification.rules rule
        where rule.organization_id = ${sqlLiteral(organizationId)}::uuid
          and rule.code = 'EXPIRY_RISK'
          and rule.is_active
        order by rule.effective_from desc, rule.id
        limit 1
      )
    );
  `));
  const batchId = String(fixture.batchId ?? "");
  const ruleId = String(fixture.ruleId ?? "");
  check("Fixture batch dan rule expiry tersedia", UUID.test(batchId) && UUID.test(ruleId));
  const notificationKey = `expiry_risk:product_batch:${batchId}:today-control-center-ui-smoke:expiry:v1`;
  const resolvedNotificationKey = `expiry_risk:product_batch:${batchId}:today-control-center-ui-smoke:resolved:v1`;
  const unsafeRouteNotificationKey = `expiry_risk:product_batch:${batchId}:today-control-center-ui-smoke:unsafe-route:v2`;

  runSql(`
    select notification.upsert_active_notification(
      p_organization_id => ${sqlLiteral(organizationId)}::uuid,
      p_rule_id => ${sqlLiteral(ruleId)}::uuid,
      p_entity_id => ${sqlLiteral(batchId)}::uuid,
      p_deduplication_key => 'today-control-center-ui-smoke:expiry:v1',
      p_stage_code => 'D30',
      p_severity_code => 'WARNING',
      p_title => 'Fixture Pusat Kendali: batch perlu diperiksa',
      p_message => 'Fixture baca stabil untuk Pusat Kendali Hari Ini.',
      p_action_route => '/?batchId=${batchId}',
      p_condition_started_at => '2026-07-26 08:00:00+00'::timestamptz,
      p_observed_at => '2026-07-26 08:00:00+00'::timestamptz,
      p_due_at => '2026-08-25 08:00:00+00'::timestamptz,
      p_source_snapshot => jsonb_build_object('smokeSuite', 'today-control-center-ui', 'fixtureVersion', 1, 'stockEffectCode', 'NONE'),
      p_stage_direction_code => 'ESCALATED',
      p_process_name => 'today-control-center-ui-smoke'
    )
    where not exists (
      select 1
      from notification.notifications notification_row
      where notification_row.organization_id = ${sqlLiteral(organizationId)}::uuid
        and notification_row.deduplication_key = ${sqlLiteral(notificationKey)}
        and notification_row.lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
    );

    insert into notification.rule_runs(
      organization_id, rule_id, rule_code_snapshot, rule_version_snapshot,
      trigger_type_code, idempotency_key, status_code, started_at, completed_at,
      evaluated_count, created_count, updated_count, resolved_count, skipped_count,
      error_count, summary, error_code, error_detail, correlation_id, process_name, created_at
    )
    select
      rule.organization_id, rule.id, rule.code, rule.version,
      'SCHEDULED', 'today-control-center-ui-smoke:rule-run-failed:v1', 'FAILED',
      '2026-07-26 08:05:00+00'::timestamptz, '2026-07-26 08:06:00+00'::timestamptz,
      1, 0, 0, 0, 0, 1, '{}'::jsonb, 'TODAY_CONTROL_CENTER_SMOKE_FAILURE', '{}'::jsonb,
      gen_random_uuid(), 'today-control-center-ui-smoke', '2026-07-26 08:05:00+00'::timestamptz
    from notification.rules rule
    where rule.id = ${sqlLiteral(ruleId)}::uuid
      and not exists (
        select 1
        from notification.rule_runs existing_run
        where existing_run.organization_id = rule.organization_id
          and existing_run.rule_code_snapshot = rule.code
          and existing_run.idempotency_key = 'today-control-center-ui-smoke:rule-run-failed:v1'
      );

    select notification.upsert_active_notification(
      p_organization_id => ${sqlLiteral(organizationId)}::uuid,
      p_rule_id => ${sqlLiteral(ruleId)}::uuid,
      p_entity_id => ${sqlLiteral(batchId)}::uuid,
      p_deduplication_key => 'today-control-center-ui-smoke:resolved:v1',
      p_stage_code => 'D60',
      p_severity_code => 'INFO',
      p_title => 'Fixture resolved Pusat Kendali',
      p_message => 'Fixture episode yang telah selesai dan tidak boleh tampil aktif.',
      p_action_route => '/?batchId=${batchId}',
      p_condition_started_at => '2026-07-26 07:00:00+00'::timestamptz,
      p_observed_at => '2026-07-26 07:00:00+00'::timestamptz,
      p_due_at => '2026-09-24 07:00:00+00'::timestamptz,
      p_source_snapshot => jsonb_build_object('smokeSuite', 'today-control-center-ui', 'fixtureVersion', 1, 'resolvedFixture', true, 'stockEffectCode', 'NONE'),
      p_stage_direction_code => 'ESCALATED',
      p_process_name => 'today-control-center-ui-smoke'
    )
    where not exists (
      select 1
      from notification.notifications notification_row
      where notification_row.organization_id = ${sqlLiteral(organizationId)}::uuid
        and notification_row.deduplication_key = ${sqlLiteral(resolvedNotificationKey)}
    );

    select notification.resolve_notification(
      p_organization_id => ${sqlLiteral(organizationId)}::uuid,
      p_notification_id => notification_row.id,
      p_resolution_code => 'SMOKE_SOURCE_RESOLVED',
      p_resolution_snapshot => jsonb_build_object('smokeSuite', 'today-control-center-ui', 'stockEffectCode', 'NONE'),
      p_resolved_at => '2026-07-26 07:05:00+00'::timestamptz,
      p_correlation_id => gen_random_uuid(),
      p_note => 'Fixture resolved untuk memverifikasi antrean aktif.',
      p_process_name => 'today-control-center-ui-smoke'
    )
    from notification.notifications notification_row
    where notification_row.organization_id = ${sqlLiteral(organizationId)}::uuid
      and notification_row.deduplication_key = ${sqlLiteral(resolvedNotificationKey)}
      and notification_row.lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED');

    select notification.upsert_active_notification(
      p_organization_id => ${sqlLiteral(organizationId)}::uuid,
      p_rule_id => ${sqlLiteral(ruleId)}::uuid,
      p_entity_id => ${sqlLiteral(batchId)}::uuid,
      p_deduplication_key => 'today-control-center-ui-smoke:unsafe-route:v2',
      p_stage_code => 'D90',
      p_severity_code => 'INFO',
      p_title => 'Fixture route double-encoded tidak aman Pusat Kendali',
      p_message => 'Fixture untuk memastikan route ter-encode tidak menjadi deep-link.',
      p_action_route => '/%252F%252Fevil.example',
      p_condition_started_at => '2026-07-26 06:00:00+00'::timestamptz,
      p_observed_at => '2026-07-26 06:00:00+00'::timestamptz,
      p_due_at => '2026-10-24 06:00:00+00'::timestamptz,
      p_source_snapshot => jsonb_build_object('smokeSuite', 'today-control-center-ui', 'fixtureVersion', 1, 'unsafeRouteFixture', true, 'stockEffectCode', 'NONE'),
      p_stage_direction_code => 'ESCALATED',
      p_process_name => 'today-control-center-ui-smoke'
    )
    where not exists (
      select 1
      from notification.notifications notification_row
      where notification_row.organization_id = ${sqlLiteral(organizationId)}::uuid
        and notification_row.deduplication_key = ${sqlLiteral(unsafeRouteNotificationKey)}
    );
  `);

  const counts = parseJsonLine(runSql(`
    select jsonb_build_object(
      'notificationCount', count(*) filter (where deduplication_key = ${sqlLiteral(notificationKey)}),
      'resolvedNotificationCount', count(*) filter (where deduplication_key = ${sqlLiteral(resolvedNotificationKey)} and lifecycle_status_code = 'RESOLVED'),
      'unsafeRouteNotificationCount', count(*) filter (where deduplication_key = ${sqlLiteral(unsafeRouteNotificationKey)} and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')),
      'ruleRunCount', (
        select count(*)
        from notification.rule_runs
        where organization_id = ${sqlLiteral(organizationId)}::uuid
          and idempotency_key = 'today-control-center-ui-smoke:rule-run-failed:v1'
      )
    )
    from notification.notifications
    where organization_id = ${sqlLiteral(organizationId)}::uuid;
  `));
  check("Fixture durable tidak membuat episode atau rule-run ganda", counts.notificationCount === 1 && counts.resolvedNotificationCount === 1 && counts.unsafeRouteNotificationCount === 1 && counts.ruleRunCount === 1, JSON.stringify(counts));
}

async function main() {
  await loadEnv();
  await login();
  await startServerIfNeeded();
  provisionReadOnlyFixture();
  const baseline = stateSnapshot();
  const allRows = await rpc({ p_severity_code: null, p_work_type_code: null, p_limit: 100, p_after_severity_rank: null, p_after_sort_at: null, p_after_work_item_id: null });
  check("Sinyal aktif tersedia untuk smoke read-only", Array.isArray(allRows) && allRows.length > 0);
  check("Episode resolved tidak tetap tampil aktif", !allRows.some((row) => row.title === "Fixture resolved Pusat Kendali"));

  const anonymous = await page("/today", false);
  check("Tanpa Admin diarahkan ke login", [302, 303, 307, 308].includes(anonymous.response.status) && String(anonymous.response.headers.get("location") ?? "").includes("/login"));
  const home = await page("/today");
  check("Route Hari Ini dapat dibuka", home.response.status === 200 && home.html.includes("Hari Ini") && !home.html.includes("Read-only"));
  check(
    "Shared PageHeader dan breadcrumb tampil",
    home.html.includes('data-page-header="shared"') &&
      home.html.includes('data-breadcrumb="shared"') &&
      home.html.includes('aria-label="Breadcrumb"') &&
      home.html.includes("Utama") &&
      home.html.includes("Pusat Kendali"),
  );
  const todayNavigationTag =
    home.html.match(/<a\b[^>]*href="\/today"[^>]*>/)?.[0] ?? "";

  check(
    "Navigasi sidebar tersedia dan route aktif",
    Boolean(todayNavigationTag) &&
      todayNavigationTag.includes('aria-current="page"') &&
      home.html.includes("Pusat Kendali"),
  );
  const summaryBlock = home.html.match(/<div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4" data-testid="today-severity-summary">([\s\S]*?)<\/div>\s*<\/section>/)?.[1] ?? "";
  check("Summary severity hanya operasional", home.html.includes("Prioritas pada halaman ini") && summaryBlock.includes("Kritis") && summaryBlock.includes("Mendesak") && summaryBlock.includes("Perlu Diperiksa") && summaryBlock.includes("Informasi") && !summaryBlock.includes("RUN_FAILED") && !summaryBlock.includes("Outbox notifikasi gagal") && !summaryBlock.includes("Evaluasi notifikasi gagal"));
  const filterForm = home.html.match(/<form\b[^>]*data-testid="today-filter-form"[^>]*>/)?.[0] ?? "";
  check("Daftar tindakan operasional tampil", home.html.includes("Sinyal aktif yang perlu diperiksa") && home.html.includes("Saring prioritas") && home.html.includes("Prioritas") && Boolean(filterForm) && !filterForm.includes("action="));
  check("Status sistem dipisahkan dari pekerjaan gudang", home.html.includes("Status Sistem") && home.html.includes("Gangguan di luar pekerjaan gudang."));
  check("Tidak ada label Tenggat generik", home.html.includes("Batas klaim") || home.html.includes("Periksa sebelum") || home.html.includes("Kedaluwarsa") || home.html.includes("Batas hitung ulang") || home.html.includes("Batas posting ulang") || home.html.includes("Waktu gangguan"));

  const first = allRows[0];
  const severity = await page(`/today?severity=${encodeURIComponent(first.severity_code)}`);
  check("Filter severity memakai URL", severity.response.status === 200 && severity.html.includes(first.title));
  const workType = await page(`/today?workType=${encodeURIComponent(first.work_type_code)}`);
  check("Filter work type memakai URL", workType.response.status === 200 && workType.html.includes(first.title));
  const combinedPath = `/today?severity=${encodeURIComponent(first.severity_code)}&workType=${encodeURIComponent(first.work_type_code)}`;
  const combined = await page(combinedPath);
  check("Kombinasi filter mempertahankan item exact", combined.response.status === 200 && combined.html.includes(first.title));
  const refreshed = await page(combinedPath);
  check("Filter bertahan setelah refresh", refreshed.html.includes(first.title));

  const routed = allRows.find((row) => typeof row.route_path === "string" && row.route_path.startsWith("/") && !row.route_path.startsWith("//"));
  check("Ada work item dengan deep-link exact", Boolean(routed));
  const routedPage = await page(`/today?severity=${encodeURIComponent(routed.severity_code)}&workType=${encodeURIComponent(routed.work_type_code)}`);
  check("Deep-link exact dirender untuk source yang mendukung", routedPage.html.includes(`href="${routed.route_path.replaceAll("&", "&amp;")}"`));
  const target = await page(routed.route_path);
  check("Target deep-link source dapat dibuka exact", target.response.status === 200 && target.html.includes("dipilih dari Notification Center."));
  const invalidTarget = await page("/?batchId=not-a-uuid");
  check("Deep-link ID invalid aman tanpa fallback", invalidTarget.response.status === 200 && invalidTarget.html.includes("Batch sumber notifikasi tidak ditemukan dalam organisasi aktif.") && !invalidTarget.html.includes("dipilih dari Notification Center."));
  const crossOrganizationBatch = parseJsonLine(runSql(`
    select jsonb_build_object(
      'batchId',
      (
        select batch_id
        from inventory.stock_batch_balances
        where organization_id <> ${sqlLiteral(organizationId)}::uuid
        order by organization_id, batch_id
        limit 1
      )
    );
  `));
  const crossOrganizationBatchId = String(crossOrganizationBatch.batchId ?? "");

  if (UUID.test(crossOrganizationBatchId)) {
    check("Fixture batch lintas organisasi tersedia", true);

    const crossOrganizationTarget = await page(
      `/?batchId=${encodeURIComponent(crossOrganizationBatchId)}`,
    );

    check(
      "Deep-link lintas organisasi aman tanpa fallback",
      crossOrganizationTarget.response.status === 200 &&
        crossOrganizationTarget.html.includes(
          "Batch sumber notifikasi tidak ditemukan dalam organisasi aktif.",
        ) &&
        !crossOrganizationTarget.html.includes(
          "dipilih dari Notification Center.",
        ),
    );
  } else {
    console.log(
      "[SKIP] Deep-link lintas organisasi: fixture batch organisasi lain tidak tersedia di database lokal.",
    );
  }

  const blocked = allRows.find((row) => !row.route_path);
  check("Ada work item tanpa action route untuk state blocked", Boolean(blocked));
  const blockedPage = await page(`/today?severity=${encodeURIComponent(blocked.severity_code)}&workType=${encodeURIComponent(blocked.work_type_code)}`);
  check("Item tanpa route tidak membuat link palsu", blockedPage.html.includes("Detail tindakan belum tersedia"));
  check("Desktop worklist tetap padat dan mobile tetap kartu", home.html.includes('data-testid="today-work-list-desktop"') && home.html.includes('data-testid="today-work-list-mobile"') && home.html.includes('data-testid="today-system-failures"'));
  const unsafeRoutePage = await page("/today?severity=INFO&workType=BATCH_EXPIRY");
  check("Protocol-relative route ter-encode tidak menjadi link", unsafeRoutePage.html.includes("Fixture route double-encoded tidak aman Pusat Kendali") && !unsafeRoutePage.html.includes('href="/%252F%252Fevil.example"'));

  const filterPairs = ["CRITICAL", "HIGH", "WARNING", "INFO"].flatMap((severityCode) => ["NOTIFICATION_OUTBOX_FAILURE", "NOTIFICATION_RULE_RUN_FAILURE", "STOCKTAKE_POST_FAILED"].map((workTypeCode) => ({ severityCode, workTypeCode })));
  let emptyPair;
  for (const pair of filterPairs) {
    const rows = await rpc({ p_severity_code: pair.severityCode, p_work_type_code: pair.workTypeCode, p_limit: 1, p_after_severity_rank: null, p_after_sort_at: null, p_after_work_item_id: null });
    if (Array.isArray(rows) && rows.length === 0) { emptyPair = pair; break; }
  }
  check("Kombinasi filter kosong tersedia", Boolean(emptyPair));
  const empty = await page(`/today?severity=${emptyPair.severityCode}&workType=${emptyPair.workTypeCode}`);
  check("Empty state aman", empty.response.status === 200 && empty.html.includes("Tidak ada tindakan aktif untuk filter ini"));

  const invalid = await page("/today?severity=DROP_TABLE&cursor=not-a-valid-cursor");
  check("Filter dan cursor invalid fallback aman", invalid.response.status === 200 && invalid.html.includes("Filter atau tautan halaman tidak valid"));

  const firstPage = await rpc({ p_severity_code: null, p_work_type_code: null, p_limit: 1, p_after_severity_rank: null, p_after_sort_at: null, p_after_work_item_id: null });
  if (allRows.length > 1) {
    const last = firstPage.at(-1);
    const next = await page(`/today?cursor=${cursorFor(last)}`);
    check("Pagination keyset tidak mengulang item terakhir", next.response.status === 200 && !next.html.includes(last.title));
    const previousTag = next.html.match(/<a\b[^>]*data-testid="today-previous-page"[^>]*>/)?.[0] ?? "";
    const previousHref = previousTag.match(/href="([^"]+)"/)?.[1]?.replaceAll("&amp;", "&");
    check("Navigasi previous tersedia", Boolean(previousHref));
    const previous = await page(previousHref);
    check("Navigasi previous kembali ke halaman stabil", previous.response.status === 200 && previous.html.includes(first.work_item_id));
  } else {
    check("Pagination stabil saat antrean satu halaman", !home.html.includes('data-testid="today-next-page"'));
  }

  const after = stateSnapshot();
  check("Buka/filter/refresh/navigasi tidak mengubah domain", JSON.stringify(after) === JSON.stringify(baseline), `organization=${organizationId}`);
  console.log(`Today Control Center UI smoke PASS: ${results.length} checks (durable read-only smoke)`);
}

try {
  await main();
} catch (error) {
  console.error("Today Control Center UI smoke FAIL", error instanceof Error ? error.stack ?? error.message : String(error));
  process.exitCode = 1;
} finally {
  if (server?.pid) {
    spawnSync("taskkill", ["/PID", String(server.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
  }
}
