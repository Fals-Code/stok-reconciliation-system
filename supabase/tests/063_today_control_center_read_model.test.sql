begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_function(
  'api'::name,
  'today_control_center_work_items'::name,
  array[
    'text',
    'text',
    'integer',
    'integer',
    'timestamp with time zone',
    'text'
  ]::text[],
  'today control center list contract exists'
);

select ok(
  (select p.prosecdef
   from pg_proc p
   where p.oid =
     'api.today_control_center_work_items(text,text,integer,integer,timestamp with time zone,text)'::regprocedure),
  'today control center list is security definer'
);

select ok(
  (select p.proconfig @> array['search_path=pg_catalog, auth, app, notification']
   from pg_proc p
   where p.oid =
     'api.today_control_center_work_items(text,text,integer,integer,timestamp with time zone,text)'::regprocedure),
  'today control center list fixes search_path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.today_control_center_work_items(text,text,integer,integer,timestamp with time zone,text)',
    'EXECUTE'
  ),
  'authenticated Admin may read today control center items'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.today_control_center_work_items(text,text,integer,integer,timestamp with time zone,text)',
    'EXECUTE'
  ),
  'anonymous clients cannot read today control center items'
);

select ok(
  not has_function_privilege(
    'public',
    'api.today_control_center_work_items(text,text,integer,integer,timestamp with time zone,text)',
    'EXECUTE'
  ),
  'PUBLIC has no today control center execute grant'
);

select has_index(
  'notification',
  'notifications',
  'idx_notifications_today_control_active',
  'active notification index supports today control center source selection'
);

select has_index(
  'notification',
  'outbox_events',
  'idx_notification_outbox_today_control_failure',
  'outbox failure index supports today control center source selection'
);

select has_index(
  'notification',
  'rule_runs',
  'idx_notification_rule_runs_today_control_failure',
  'rule-run failure index supports today control center source selection'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'notification.notifications'::regclass),
  'notification rows retain RLS'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'notification.outbox_events'::regclass),
  'outbox rows retain RLS'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'notification.rule_runs'::regclass),
  'rule runs retain RLS'
);

select ok(
  has_table_privilege('authenticated', 'notification.notifications', 'SELECT')
  and not has_table_privilege('authenticated', 'notification.notifications', 'INSERT')
  and not has_table_privilege('authenticated', 'notification.notifications', 'UPDATE')
  and not has_table_privilege('authenticated', 'notification.notifications', 'DELETE'),
  'existing notification source access remains read-only for authenticated clients'
);

insert into app.organizations(id, code, name, timezone, is_active, created_at)
values
  ('00000000-0000-4063-8000-000000000001', 'PGTAP_TODAY_063_A', 'Today Control Center 063 A', 'Asia/Jakarta', true, '2026-07-26 08:00:00+07'),
  ('00000000-0000-4063-8000-000000000002', 'PGTAP_TODAY_063_B', 'Today Control Center 063 B', 'Asia/Jakarta', true, '2026-07-26 08:00:00+07');

insert into auth.users(
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4063-8000-000000000001', 'authenticated', 'authenticated', 'pgtap.today.063.a@glowlab.invalid', '2026-07-26 08:00:00+07', '{"provider":"email","providers":["email"]}', '{}', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', false, false),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4063-8000-000000000002', 'authenticated', 'authenticated', 'pgtap.today.063.b@glowlab.invalid', '2026-07-26 08:00:00+07', '{"provider":"email","providers":["email"]}', '{}', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', false, false),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4063-8000-000000000003', 'authenticated', 'authenticated', 'pgtap.today.063.inactive@glowlab.invalid', '2026-07-26 08:00:00+07', '{"provider":"email","providers":["email"]}', '{}', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', false, false);

insert into app.user_profiles(user_id, organization_id, display_name, employee_code, role_code, is_active)
values
  ('00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000001', 'Today Control Center Admin A', 'PGTAP-TODAY-063-A', 'ADMIN', true),
  ('00000000-0000-4063-8000-000000000002', '00000000-0000-4063-8000-000000000002', 'Today Control Center Admin B', 'PGTAP-TODAY-063-B', 'ADMIN', true),
  ('00000000-0000-4063-8000-000000000003', '00000000-0000-4063-8000-000000000001', 'Today Control Center Inactive', 'PGTAP-TODAY-063-INACTIVE', 'ADMIN', false);

insert into notification.rules(
  id, organization_id, code, version, category_code, trigger_mode_code,
  entity_type_code, severity_strategy_code, stage_strategy_code,
  condition_strategy_code, resolution_strategy_code, template_version,
  action_code, config, is_active, effective_from, created_at, updated_at
)
values
  ('00000000-0000-4063-8000-000000000011', '00000000-0000-4063-8000-000000000001', 'RECONCILIATION_ISSUE_HIGH_CRITICAL', '1.0.0', 'RECONCILIATION', 'SCHEDULED', 'RECONCILIATION_ISSUE', 'FIXTURE', 'FIXTURE', 'FIXTURE', 'FIXTURE', '1.0.0', 'OPEN', '{}', true, '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07'),
  ('00000000-0000-4063-8000-000000000012', '00000000-0000-4063-8000-000000000001', 'RECONCILIATION_RUN_FAILED', '1.0.0', 'RECONCILIATION', 'SCHEDULED', 'RECONCILIATION_RUN', 'FIXTURE', 'FIXTURE', 'FIXTURE', 'FIXTURE', '1.0.0', 'OPEN', '{}', true, '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07'),
  ('00000000-0000-4063-8000-000000000013', '00000000-0000-4063-8000-000000000001', 'CLAIM_DEADLINE', '1.0.0', 'RETURN', 'SCHEDULED', 'RETURN_CLAIM', 'FIXTURE', 'FIXTURE', 'FIXTURE', 'FIXTURE', '1.0.0', 'OPEN', '{}', true, '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07'),
  ('00000000-0000-4063-8000-000000000014', '00000000-0000-4063-8000-000000000001', 'RETURN_INSPECTION_PENDING', '1.0.0', 'RETURN', 'SCHEDULED', 'RETURN', 'FIXTURE', 'FIXTURE', 'FIXTURE', 'FIXTURE', '1.0.0', 'OPEN', '{}', true, '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07'),
  ('00000000-0000-4063-8000-000000000015', '00000000-0000-4063-8000-000000000001', 'EXPIRY_RISK', '1.0.0', 'EXPIRY', 'SCHEDULED', 'BATCH', 'FIXTURE', 'FIXTURE', 'FIXTURE', 'FIXTURE', '1.0.0', 'OPEN', '{}', true, '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07'),
  ('00000000-0000-4063-8000-000000000016', '00000000-0000-4063-8000-000000000001', 'STOCKTAKE_RECOUNT_REQUIRED', '1.0.0', 'STOCKTAKE', 'SCHEDULED', 'STOCKTAKE', 'FIXTURE', 'FIXTURE', 'FIXTURE', 'FIXTURE', '1.0.0', 'OPEN', '{}', true, '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07'),
  ('00000000-0000-4063-8000-000000000017', '00000000-0000-4063-8000-000000000001', 'STOCKTAKE_POST_FAILED', '1.0.0', 'STOCKTAKE', 'SCHEDULED', 'STOCKTAKE', 'FIXTURE', 'FIXTURE', 'FIXTURE', 'FIXTURE', '1.0.0', 'OPEN', '{}', true, '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07');

insert into notification.notifications(
  id, organization_id, rule_id, rule_code_snapshot, rule_version_snapshot,
  template_version_snapshot, notification_type_code, category_code,
  entity_type_code, entity_id, episode_no, previous_notification_id,
  deduplication_key, deduplication_hash, lifecycle_status_code, stage_code,
  severity_code, title, message, action_code, action_route,
  condition_started_at, due_at, first_seen_at, last_seen_at, occurrence_count,
  acknowledged_at, acknowledged_by, acknowledgment_note, resolved_at,
  resolution_code, resolution_snapshot, source_snapshot, config_snapshot,
  created_at, updated_at, version_no
)
values
  ('00000000-0000-4063-8000-000000000101', '00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000011', 'RECONCILIATION_ISSUE_HIGH_CRITICAL', '1.0.0', '1.0.0', 'RECONCILIATION_ISSUE', 'RECONCILIATION', 'RECONCILIATION_ISSUE', '00000000-0000-4063-8000-000000000201', 1, null, 'today-063-reconciliation-issue', repeat('1', 64), 'OPEN', 'CRITICAL', 'CRITICAL', 'Issue rekonsiliasi kritis', 'Evidence mismatch.', 'OPEN_RECONCILIATION', '/reconciliation?issueId=00000000-0000-4063-8000-000000000201', '2026-07-26 08:00:00+07', null, '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', 1, null, null, null, null, null, null, '{}', '{}', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', 1),
  ('00000000-0000-4063-8000-000000000102', '00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000012', 'RECONCILIATION_RUN_FAILED', '1.0.0', '1.0.0', 'RECONCILIATION_RUN', 'RECONCILIATION', 'RECONCILIATION_RUN', '00000000-0000-4063-8000-000000000202', 1, null, 'today-063-reconciliation-run', repeat('2', 64), 'OPEN', 'FAILED', 'CRITICAL', 'Run rekonsiliasi gagal', 'Run gagal.', 'OPEN_RECONCILIATION', '/reconciliation?runId=00000000-0000-4063-8000-000000000202', '2026-07-26 08:01:00+07', null, '2026-07-26 08:01:00+07', '2026-07-26 08:01:00+07', 1, null, null, null, null, null, null, '{}', '{}', '2026-07-26 08:01:00+07', '2026-07-26 08:01:00+07', 1),
  ('00000000-0000-4063-8000-000000000103', '00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000013', 'CLAIM_DEADLINE', '1.0.0', '1.0.0', 'RETURN_CLAIM', 'RETURN', 'RETURN_CLAIM', '00000000-0000-4063-8000-000000000203', 1, null, 'today-063-claim', repeat('3', 64), 'OPEN', 'D14', 'WARNING', 'Claim mendekati tenggat', 'Deadline D14.', 'OPEN_CLAIM', '/returns?claimId=00000000-0000-4063-8000-000000000203', '2026-07-26 08:02:00+07', '2026-08-09 08:02:00+07', '2026-07-26 08:02:00+07', '2026-07-26 08:02:00+07', 1, null, null, null, null, null, null, '{}', '{}', '2026-07-26 08:02:00+07', '2026-07-26 08:02:00+07', 1),
  ('00000000-0000-4063-8000-000000000104', '00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000014', 'RETURN_INSPECTION_PENDING', '1.0.0', '1.0.0', 'RETURN', 'RETURN', 'RETURN', '00000000-0000-4063-8000-000000000204', 1, null, 'today-063-return-inspection', repeat('4', 64), 'OPEN', 'PENDING_24H', 'HIGH', 'Retur menunggu inspeksi', 'Pending 24 jam.', 'OPEN_RETURN', '/returns?returnId=00000000-0000-4063-8000-000000000204', '2026-07-26 08:03:00+07', '2026-07-27 08:03:00+07', '2026-07-26 08:03:00+07', '2026-07-26 08:03:00+07', 1, null, null, null, null, null, null, '{}', '{}', '2026-07-26 08:03:00+07', '2026-07-26 08:03:00+07', 1),
  ('00000000-0000-4063-8000-000000000105', '00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000015', 'EXPIRY_RISK', '1.0.0', '1.0.0', 'BATCH', 'EXPIRY', 'BATCH', '00000000-0000-4063-8000-000000000205', 1, null, 'today-063-expiry', repeat('5', 64), 'OPEN', 'EXPIRED', 'CRITICAL', 'Batch kedaluwarsa', 'Batch expired.', 'OPEN_BATCH', '/?batchId=00000000-0000-4063-8000-000000000205', '2026-07-26 08:04:00+07', '2026-07-26 08:04:00+07', '2026-07-26 08:04:00+07', '2026-07-26 08:04:00+07', 1, null, null, null, null, null, null, '{}', '{}', '2026-07-26 08:04:00+07', '2026-07-26 08:04:00+07', 1),
  ('00000000-0000-4063-8000-000000000106', '00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000016', 'STOCKTAKE_RECOUNT_REQUIRED', '1.0.0', '1.0.0', 'STOCKTAKE', 'STOCKTAKE', 'STOCKTAKE', '00000000-0000-4063-8000-000000000206', 1, null, 'today-063-recount', repeat('6', 64), 'OPEN', 'RECOUNT_REQUIRED', 'HIGH', 'Stok opname perlu hitung ulang', 'Recount required.', 'OPEN_STOCKTAKE', '/stocktakes/00000000-0000-4063-8000-000000000206', '2026-07-26 08:05:00+07', null, '2026-07-26 08:05:00+07', '2026-07-26 08:05:00+07', 1, null, null, null, null, null, null, '{}', '{}', '2026-07-26 08:05:00+07', '2026-07-26 08:05:00+07', 1),
  ('00000000-0000-4063-8000-000000000107', '00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000017', 'STOCKTAKE_POST_FAILED', '1.0.0', '1.0.0', 'STOCKTAKE', 'STOCKTAKE', 'STOCKTAKE', '00000000-0000-4063-8000-000000000207', 1, null, 'today-063-post-failed', repeat('7', 64), 'OPEN', 'RECONCILIATION_FAILED', 'CRITICAL', 'Posting stok opname gagal', 'Posting failed.', 'OPEN_STOCKTAKE', '/stocktakes/00000000-0000-4063-8000-000000000207', '2026-07-26 08:06:00+07', null, '2026-07-26 08:06:00+07', '2026-07-26 08:06:00+07', 1, null, null, null, null, null, null, '{}', '{}', '2026-07-26 08:06:00+07', '2026-07-26 08:06:00+07', 1),
  ('00000000-0000-4063-8000-000000000108', '00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000013', 'CLAIM_DEADLINE', '1.0.0', '1.0.0', 'RETURN_CLAIM', 'RETURN', 'RETURN_CLAIM', '00000000-0000-4063-8000-000000000208', 1, null, 'today-063-resolved-claim', repeat('8', 64), 'RESOLVED', 'D14', 'WARNING', 'Claim terselesaikan', 'Resolved claim.', 'OPEN_CLAIM', '/returns?claimId=00000000-0000-4063-8000-000000000208', '2026-07-26 08:07:00+07', '2026-08-09 08:07:00+07', '2026-07-26 08:07:00+07', '2026-07-26 08:07:00+07', 1, null, null, null, '2026-07-26 08:08:00+07', 'CLAIM_COMPLETED', '{}', '{}', '{}', '2026-07-26 08:07:00+07', '2026-07-26 08:08:00+07', 2);

insert into notification.outbox_events(
  id, organization_id, event_type_code, source_event_key, entity_type_code,
  entity_id, occurred_at, payload, payload_hash, correlation_id, status_code,
  attempt_count, available_at, locked_at, locked_by, completed_at,
  last_error_code, last_error_detail, process_name, created_at
)
values
  ('00000000-0000-4063-8000-000000000301', '00000000-0000-4063-8000-000000000001', 'NOTIFICATION_FIXTURE', 'today-063-outbox-final', 'ORGANIZATION', '00000000-0000-4063-8000-000000000001', '2026-07-26 08:10:00+07', '{}', repeat('a', 64), '00000000-0000-4063-8000-000000000401', 'FAILED_FINAL', 2, '2026-07-26 08:10:00+07', null, null, '2026-07-26 08:11:00+07', 'OUTBOX_FINAL', '{}', 'pgtap.today.063', '2026-07-26 08:10:00+07'),
  ('00000000-0000-4063-8000-000000000302', '00000000-0000-4063-8000-000000000001', 'NOTIFICATION_FIXTURE', 'today-063-outbox-retryable', 'ORGANIZATION', '00000000-0000-4063-8000-000000000001', '2026-07-26 08:12:00+07', '{}', repeat('b', 64), '00000000-0000-4063-8000-000000000402', 'FAILED_RETRYABLE', 1, '2026-07-26 08:12:00+07', null, null, null, 'OUTBOX_RETRY', '{}', 'pgtap.today.063', '2026-07-26 08:12:00+07');

insert into notification.rule_runs(
  id, organization_id, rule_id, rule_code_snapshot, rule_version_snapshot,
  trigger_type_code, idempotency_key, status_code, started_at, completed_at,
  evaluated_count, created_count, updated_count, resolved_count, skipped_count,
  error_count, summary, error_code, error_detail, correlation_id, process_name,
  created_at
)
values
  ('00000000-0000-4063-8000-000000000501', '00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000011', 'RECONCILIATION_ISSUE_HIGH_CRITICAL', '1.0.0', 'SCHEDULED', 'today-063-rule-failed', 'FAILED', '2026-07-26 08:14:00+07', '2026-07-26 08:15:00+07', 1, 0, 0, 0, 0, 1, '{}', 'RULE_FAILED', '{}', '00000000-0000-4063-8000-000000000601', 'pgtap.today.063', '2026-07-26 08:14:00+07'),
  ('00000000-0000-4063-8000-000000000502', '00000000-0000-4063-8000-000000000001', '00000000-0000-4063-8000-000000000012', 'RECONCILIATION_RUN_FAILED', '1.0.0', 'SCHEDULED', 'today-063-rule-partial', 'PARTIALLY_FAILED', '2026-07-26 08:16:00+07', '2026-07-26 08:17:00+07', 2, 0, 0, 0, 1, 1, '{}', 'RULE_PARTIAL', '{}', '00000000-0000-4063-8000-000000000602', 'pgtap.today.063', '2026-07-26 08:16:00+07');

insert into notification.rules(
  id, organization_id, code, version, category_code, trigger_mode_code,
  entity_type_code, severity_strategy_code, stage_strategy_code,
  condition_strategy_code, resolution_strategy_code, template_version,
  action_code, config, is_active, effective_from, created_at, updated_at
)
values
  ('00000000-0000-4063-8000-000000000021', '00000000-0000-4063-8000-000000000002', 'EXPIRY_RISK', '1.0.0', 'EXPIRY', 'SCHEDULED', 'BATCH', 'FIXTURE', 'FIXTURE', 'FIXTURE', 'FIXTURE', '1.0.0', 'OPEN', '{}', true, '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07', '2026-01-01 00:00:00+07');

insert into notification.notifications(
  id, organization_id, rule_id, rule_code_snapshot, rule_version_snapshot,
  template_version_snapshot, notification_type_code, category_code,
  entity_type_code, entity_id, episode_no, deduplication_key,
  deduplication_hash, lifecycle_status_code, stage_code, severity_code, title,
  message, action_code, action_route, condition_started_at, due_at,
  first_seen_at, last_seen_at, occurrence_count, source_snapshot,
  config_snapshot, created_at, updated_at, version_no
)
values
  ('00000000-0000-4063-8000-000000000109', '00000000-0000-4063-8000-000000000002', '00000000-0000-4063-8000-000000000021', 'EXPIRY_RISK', '1.0.0', '1.0.0', 'BATCH', 'EXPIRY', 'BATCH', '00000000-0000-4063-8000-000000000209', 1, 'today-063-other', repeat('9', 64), 'OPEN', 'EXPIRED', 'CRITICAL', 'Other organization batch', 'Other organization only.', 'OPEN_BATCH', '/?batchId=00000000-0000-4063-8000-000000000209', '2026-07-26 08:20:00+07', '2026-07-26 08:20:00+07', '2026-07-26 08:20:00+07', '2026-07-26 08:20:00+07', 1, '{}', '{}', '2026-07-26 08:20:00+07', '2026-07-26 08:20:00+07', 1);

create temp table today_read_baseline as
select
  (select count(*) from notification.notifications where organization_id = '00000000-0000-4063-8000-000000000001') as notification_count,
  (select count(*) from notification.outbox_events where organization_id = '00000000-0000-4063-8000-000000000001') as outbox_count,
  (select count(*) from notification.rule_runs where organization_id = '00000000-0000-4063-8000-000000000001') as rule_run_count,
  (select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4063-8000-000000000001') as transaction_count,
  (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4063-8000-000000000001') as ledger_count,
  (select count(*) from inventory.stock_reservations where organization_id = '00000000-0000-4063-8000-000000000001') as reservation_count,
  (select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4063-8000-000000000001') as projection_count;

select set_config('request.jwt.claim.sub', '00000000-0000-4063-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4063-8000-000000000001', 'role', 'authenticated')::text, true);
set local role authenticated;

select is(
  (select count(*) from api.today_control_center_work_items()),
  11::bigint,
  'all supported active source episodes and operational failures are returned'
);

select is(
  (select array_agg(distinct work_type_code order by work_type_code)
   from api.today_control_center_work_items()
   where notification_id is not null),
  array[
    'BATCH_EXPIRY',
    'RECONCILIATION_ISSUE',
    'RECONCILIATION_RUN_FAILED',
    'RETURN_INSPECTION_PENDING',
    'STOCKTAKE_POST_FAILED',
    'STOCKTAKE_RECOUNT_REQUIRED',
    'TIKTOK_CLAIM_DEADLINE'
  ]::text[],
  'each supported notification evaluator family produces its work-item type'
);

select is(
  (select array_agg(resolution_status order by resolution_status)
   from api.today_control_center_work_items()
   where work_type_code = 'NOTIFICATION_OUTBOX_FAILURE'),
  array['FAILED_FINAL', 'FAILED_RETRYABLE']::text[],
  'retryable and final outbox failures remain distinct actionable sources'
);

select is(
  (select array_agg(resolution_status order by resolution_status)
   from api.today_control_center_work_items()
   where work_type_code = 'NOTIFICATION_RULE_RUN_FAILURE'),
  array['FAILED', 'PARTIALLY_FAILED']::text[],
  'failed and partially failed rule runs remain distinct actionable sources'
);

select is(
  (select count(*) from api.today_control_center_work_items() where source_entity_id = '00000000-0000-4063-8000-000000000208'),
  0::bigint,
  'resolved notification source does not remain active'
);

select is(
  (select count(*) from api.today_control_center_work_items() where source_entity_id = '00000000-0000-4063-8000-000000000209'),
  0::bigint,
  'cross-organization source is safe not-found'
);

select is(
  (select count(*) from api.today_control_center_work_items() where source_entity_id = '00000000-0000-4063-8000-000000000999'),
  0::bigint,
  'invalid source is safe not-found'
);

select is(
  (select work_type_code from api.today_control_center_work_items() where notification_id = '00000000-0000-4063-8000-000000000103'),
  'TIKTOK_CLAIM_DEADLINE',
  'claim deadline work type comes from the evaluator rule contract'
);

select is(
  (select due_at from api.today_control_center_work_items() where notification_id = '00000000-0000-4063-8000-000000000103'),
  '2026-08-09 08:02:00+07'::timestamptz,
  'claim due time is preserved from the authoritative notification episode'
);

select is(
  (select route_path from api.today_control_center_work_items() where notification_id = '00000000-0000-4063-8000-000000000104'),
  '/returns?returnId=00000000-0000-4063-8000-000000000204',
  'return inspection preserves the exact evaluator deep link'
);

select is(
  (select count(*) from api.today_control_center_work_items(p_work_type_code => 'BATCH_EXPIRY')),
  1::bigint,
  'work type filter returns the supported expiry episode only'
);

select is(
  (select count(*) from api.today_control_center_work_items(p_severity_code => 'CRITICAL')),
  6::bigint,
  'severity filter applies deterministic source-derived severity'
);

select throws_ok(
  $$select * from api.today_control_center_work_items(p_severity_code => 'URGENT')$$,
  'P0001',
  'TODAY_CONTROL_CENTER_SEVERITY_FILTER_INVALID',
  'unsupported severity filter is rejected'
);

select throws_ok(
  $$select * from api.today_control_center_work_items(p_limit => 0)$$,
  'P0001',
  'TODAY_CONTROL_CENTER_LIMIT_INVALID',
  'page limit below one is rejected'
);

select throws_ok(
  $$select * from api.today_control_center_work_items(p_after_severity_rank => 1)$$,
  'P0001',
  'TODAY_CONTROL_CENTER_CURSOR_INVALID',
  'partial cursor is rejected'
);

create temp table today_page_one as
select * from api.today_control_center_work_items(p_limit => 3);

select is((select count(*) from today_page_one), 3::bigint, 'server-side page limit is honored');

create temp table today_page_two as
select *
from api.today_control_center_work_items(
  p_limit => 100,
  p_after_severity_rank => (
    select sort_severity_rank
    from today_page_one
    order by sort_severity_rank desc, sort_at desc, work_item_id desc
    limit 1
  ),
  p_after_sort_at => (
    select sort_at
    from today_page_one
    order by sort_severity_rank desc, sort_at desc, work_item_id desc
    limit 1
  ),
  p_after_work_item_id => (
    select work_item_id
    from today_page_one
    order by sort_severity_rank desc, sort_at desc, work_item_id desc
    limit 1
  )
);

select is((select count(*) from today_page_two), 8::bigint, 'keyset cursor returns every remaining work item');

select is(
  (select count(*)
   from today_page_two next_page
   join today_page_one first_page using (work_item_id)),
  0::bigint,
  'keyset page has no duplicate work item from the preceding page'
);

select ok(
  (select count(*) = count(distinct work_item_id)
   from api.today_control_center_work_items()),
  'one active source episode produces at most one work item'
);

select count(*) from api.today_control_center_work_items();
select count(*) from api.today_control_center_work_items(p_work_type_code => 'TIKTOK_CLAIM_DEADLINE');

reset role;

select is(
  (select row(
    (select count(*) from notification.notifications where organization_id = '00000000-0000-4063-8000-000000000001'),
    (select count(*) from notification.outbox_events where organization_id = '00000000-0000-4063-8000-000000000001'),
    (select count(*) from notification.rule_runs where organization_id = '00000000-0000-4063-8000-000000000001'),
    (select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4063-8000-000000000001'),
    (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4063-8000-000000000001'),
    (select count(*) from inventory.stock_reservations where organization_id = '00000000-0000-4063-8000-000000000001'),
    (select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4063-8000-000000000001')
  )::text),
  (select row(notification_count, outbox_count, rule_run_count, transaction_count, ledger_count, reservation_count, projection_count)::text from today_read_baseline),
  'repeated reads preserve notification, ledger, projection, and reservation state'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4063-8000-000000000003', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4063-8000-000000000003', 'role', 'authenticated')::text, true);
set local role authenticated;

select throws_ok(
  $$select * from api.today_control_center_work_items()$$,
  '42501',
  'ADMIN_ACCESS_REQUIRED',
  'inactive Admin cannot read today control center items'
);

reset role;

select * from finish();

rollback;
