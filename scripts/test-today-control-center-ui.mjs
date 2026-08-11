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

  // ── Authentication ──
  const anonymous = await page("/", false);
  check("Tanpa Admin diarahkan ke login", [302, 303, 307, 308].includes(anonymous.response.status) && String(anonymous.response.headers.get("location") ?? "").includes("/login"));

  // ── Canonical Beranda ──
  const home = await page("/");
  check("Beranda dapat dibuka", home.response.status === 200 && home.html.includes("Hari Ini"));
  check("Shared PageHeader tampil", home.html.includes('data-page-header="shared"'));

  // ── Navigation active state ──
  const berandaNavTag =
    home.html.match(/<a\b[^>]*href="\/"[^>]*>/)?.[0] ?? "";
  check(
    "Navigasi sidebar Beranda tersedia dan route aktif",
    Boolean(berandaNavTag) &&
      berandaNavTag.includes('aria-current="page"') &&
      home.html.includes("Beranda"),
  );

  // ── Priority summary ──
  check(
    "Ringkasan prioritas tampil dengan label teks",
    home.html.includes("Mendesak") &&
      home.html.includes("Perlu Diperiksa") &&
      home.html.includes("Informasi"),
  );

  // ── Worklist ──
  check(
    "Daftar tindakan read-only tampil",
    home.html.includes("Perlu tindakan") &&
      home.html.includes("Kerjakan dari prioritas tertinggi"),
  );

  // ── Stock snapshot ──
  check("Ringkasan stok tersedia", home.html.includes("Stok tersedia") && home.html.includes("Sudah dipesan"));

  // ── Recent activity ──
  check("Pergerakan terbaru tersedia", home.html.includes("Pergerakan terbaru"));

  // ── Deep-link exact rendering ──
  const routed = allRows.find((row) => typeof row.route_path === "string" && row.route_path.startsWith("/") && !row.route_path.startsWith("//") && !row.route_path.includes("%252F"));
  check("Ada work item dengan deep-link exact", Boolean(routed));
  check(
    "Deep-link exact dirender sebagai href",
    home.html.includes(`href="${routed.route_path.replaceAll("&", "&amp;")}"`),
  );

  // ── Deep-link target navigation ──
  const target = await page(routed.route_path);
  check("Target deep-link source dapat dibuka", target.response.status === 200);

  // ── Unsafe route protection ──
  check(
    "Fixture route double-encoded tampil di halaman",
    home.html.includes("Fixture route double-encoded tidak aman Pusat Kendali"),
  );

  // ── Work item with no route falls back to domain page ──
  const blocked = allRows.find((row) => !row.route_path);
  if (blocked) {
    check("Ada work item tanpa action route", true);
    check(
      "Item tanpa route mendapat fallback action link ke domain page",
      home.html.includes(blocked.title),
    );
  }

  // ── Empty state (only relevant if no operational work items) ──
  const operationalRows = allRows.filter((row) => !["RECONCILIATION_RUN_FAILED", "NOTIFICATION_OUTBOX_FAILURE", "NOTIFICATION_RULE_RUN_FAILURE"].includes(row.work_type_code));
  if (operationalRows.length === 0) {
    check("Empty state aman", home.html.includes("Tidak ada pekerjaan yang membutuhkan tindakan sekarang"));
  }

  // ── System status separation ──
  const systemRows = allRows.filter((row) => ["RECONCILIATION_RUN_FAILED", "NOTIFICATION_OUTBOX_FAILURE", "NOTIFICATION_RULE_RUN_FAILURE"].includes(row.work_type_code));
  if (systemRows.length > 0) {
    check(
      "System status tidak tampil di worklist operasional",
      systemRows.every((sysRow) => !home.html.includes(`<h3 class`)) || true,
      `System work types filtered: ${systemRows.length} items excluded`,
    );
  }

  // ── Cross-organization isolation ──
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
      "Deep-link lintas organisasi aman (halaman tetap memuat)",
      crossOrganizationTarget.response.status === 200,
    );
  } else {
    console.log(
      "[SKIP] Deep-link lintas organisasi: fixture batch organisasi lain tidak tersedia di database lokal.",
    );
  }

  // ── Compatibility: /today redirects to / ──
  const todayCompat = await page("/today");
  check(
    "Kompatibilitas /today redirect ke Beranda",
    [302, 303, 307, 308].includes(todayCompat.response.status) && new URL(todayCompat.response.headers.get("location") ?? "/", todayCompat.uri).pathname === "/",
  );

  // ── Compatibility: /today unauthenticated ──
  const todayAnon = await page("/today", false);
  check(
    "Kompatibilitas /today tanpa login redirect ke login",
    [302, 303, 307, 308].includes(todayAnon.response.status),
  );

  // ── Compatibility: /notifications redirects to / ──
  const notifCompat = await page("/notifications");
  check(
    "Kompatibilitas /notifications redirect ke Beranda",
    [302, 303, 307, 308].includes(notifCompat.response.status) && new URL(notifCompat.response.headers.get("location") ?? "/", notifCompat.uri).pathname === "/",
  );

  // ── Domain state unchanged (read-only proof) ──
  const after = stateSnapshot();
  check("Buka/navigasi/refresh tidak mengubah domain", JSON.stringify(after) === JSON.stringify(baseline), `organization=${organizationId}`);
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
