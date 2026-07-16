begin;

create extension if not exists pgtap with schema extensions;

select plan(66);

-- 1-7: schema and tables
select has_schema('notification');
select has_table('notification'::name, 'rules'::name);
select has_table('notification'::name, 'outbox_events'::name);
select has_table('notification'::name, 'rule_runs'::name);
select has_table('notification'::name, 'notifications'::name);
select has_table('notification'::name, 'notification_events'::name);
select has_table('notification'::name, 'user_states'::name);

-- 8-13: primary keys
select col_is_pk('notification'::name, 'rules'::name, 'id'::name);
select col_is_pk('notification'::name, 'outbox_events'::name, 'id'::name);
select col_is_pk('notification'::name, 'rule_runs'::name, 'id'::name);
select col_is_pk('notification'::name, 'notifications'::name, 'id'::name);
select col_is_pk('notification'::name, 'notification_events'::name, 'id'::name);
select col_is_pk('notification'::name, 'user_states'::name, 'id'::name);

-- 14-19: indexes
select has_index(
  'notification'::name,
  'rules'::name,
  'uidx_notification_rules_active'::name
);
select has_index(
  'notification'::name,
  'outbox_events'::name,
  'idx_notification_outbox_pending'::name
);
select has_index(
  'notification'::name,
  'rule_runs'::name,
  'idx_notification_rule_runs_status'::name
);
select has_index(
  'notification'::name,
  'notifications'::name,
  'uidx_notifications_active_dedup'::name
);
select has_index(
  'notification'::name,
  'notifications'::name,
  'idx_notifications_org_active'::name
);
select has_index(
  'notification'::name,
  'user_states'::name,
  'idx_notification_user_states_user'::name
);

-- 20-22: triggers
select has_trigger(
  'notification'::name,
  'notifications'::name,
  'trg_notifications_touch_version'::name
);
select has_trigger(
  'notification'::name,
  'notification_events'::name,
  'trg_notification_events_immutable'::name
);
select has_trigger(
  'notification'::name,
  'user_states'::name,
  'trg_notification_user_states_touch_updated_at'::name
);

-- 23-26: RLS policies
select policies_are(
  'notification',
  'rule_runs',
  array['notification_rule_runs_read_current_org']
);
select policies_are(
  'notification',
  'notifications',
  array['notifications_read_current_org']
);
select policies_are(
  'notification',
  'notification_events',
  array['notification_events_read_current_org']
);
select policies_are(
  'notification',
  'user_states',
  array['notification_user_states_read_self']
);

-- 27-39: privilege surface
select ok(
  has_table_privilege('authenticated', 'notification.rules', 'SELECT'),
  'authenticated Admin may read notification rules'
);
select ok(
  has_table_privilege('authenticated', 'notification.rule_runs', 'SELECT'),
  'authenticated Admin may read safe rule-run rows under RLS'
);
select ok(
  has_table_privilege('authenticated', 'notification.notifications', 'SELECT'),
  'authenticated Admin may read notification rows under RLS'
);
select ok(
  has_table_privilege(
    'authenticated',
    'notification.notification_events',
    'SELECT'
  ),
  'authenticated Admin may read notification history under RLS'
);
select ok(
  has_table_privilege(
    'authenticated',
    'notification.user_states',
    'SELECT'
  ),
  'authenticated Admin may read only their own user state under RLS'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'notification.outbox_events',
    'SELECT'
  ),
  'authenticated clients cannot read raw outbox payloads'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'notification.notifications',
    'INSERT'
  ),
  'authenticated clients cannot insert notifications directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'notification.notifications',
    'UPDATE'
  ),
  'authenticated clients cannot update notification lifecycle directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'notification.notification_events',
    'DELETE'
  ),
  'authenticated clients cannot delete notification history'
);
select ok(
  has_table_privilege(
    'service_role',
    'notification.outbox_events',
    'INSERT'
  ),
  'service role may write outbox events'
);
select ok(
  has_table_privilege(
    'service_role',
    'notification.notifications',
    'UPDATE'
  ),
  'service role may update notification lifecycle'
);
select ok(
  has_table_privilege(
    'service_role',
    'notification.user_states',
    'DELETE'
  ),
  'service role may maintain notification user states'
);
select ok(
  not has_table_privilege(
    'anon',
    'notification.notifications',
    'SELECT'
  ),
  'anonymous users cannot read notifications'
);

-- 40-46: expected constraints exist
select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'uq_notification_outbox_source_event'
  ),
  'outbox source identity has a unique constraint'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'uq_notification_rule_runs_idempotency'
  ),
  'rule runs have an idempotency constraint'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'uq_notifications_episode'
  ),
  'notification episode number is unique per dedup hash'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'ck_notifications_lifecycle_payload'
  ),
  'notification lifecycle payload is constrained'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'ck_notification_events_actor'
  ),
  'notification event actor identity is constrained'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'ck_notification_user_states_state_payload'
  ),
  'per-user read-state payload is constrained'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'ck_notification_outbox_status_payload'
  ),
  'outbox processing state is constrained'
);

-- Fixtures
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
)
values
(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94000000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.one@glowlab.invalid',
  '2026-07-16 20:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 20:00:00+07'::timestamptz,
  '2026-07-16 20:00:00+07'::timestamptz,
  false,
  false
),
(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94000000-0000-4000-8000-000000000002'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.two@glowlab.invalid',
  '2026-07-16 20:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 20:00:00+07'::timestamptz,
  '2026-07-16 20:00:00+07'::timestamptz,
  false,
  false
);

insert into app.user_profiles (
  user_id,
  organization_id,
  display_name,
  employee_code,
  role_code,
  is_active
)
values
(
  '94000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Notification Admin One',
  'PGTAP-NTF-ONE',
  'ADMIN',
  true
),
(
  '94000000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Notification Admin Two',
  'PGTAP-NTF-TWO',
  'ADMIN',
  true
);

insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active,
  created_at,
  created_by
)
values (
  '00000000-0000-4000-8000-000000000004'::uuid,
  'PGTAP_NOTIFICATION_OTHER',
  'pgTAP Notification Other Organization',
  'Asia/Jakarta',
  true,
  '2026-07-16 20:00:00+07'::timestamptz,
  null
);

insert into notification.rules (
  id,
  organization_id,
  code,
  version,
  category_code,
  trigger_mode_code,
  entity_type_code,
  severity_strategy_code,
  stage_strategy_code,
  condition_strategy_code,
  resolution_strategy_code,
  template_version,
  action_code,
  config,
  is_active,
  effective_from,
  effective_to,
  created_by,
  created_at,
  updated_by,
  updated_at
)
values (
  '80000000-0000-4000-8000-000000000099'::uuid,
  '00000000-0000-4000-8000-000000000004'::uuid,
  'PGTAP_OTHER_RULE',
  '1.0.0',
  'SYSTEM_JOB',
  'SCHEDULED',
  'SYSTEM_JOB',
  'STATIC',
  'JOB_STATUS',
  'JOB_FAILED',
  'JOB_RECOVERED',
  '1.0.0',
  'OPEN_JOB_DETAIL',
  '{}'::jsonb,
  true,
  '2026-07-16 20:00:00+07'::timestamptz,
  null,
  null,
  '2026-07-16 20:00:00+07'::timestamptz,
  null,
  '2026-07-16 20:00:00+07'::timestamptz
);

-- 47: valid outbox event
select lives_ok(
  $sql$
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
      available_at,
      actor_user_id,
      process_name
    )
    values (
      '97000000-0000-4000-8000-000000000001'::uuid,
      '00000000-0000-4000-8000-000000000001'::uuid,
      'NOTIFICATION_EVALUATION_REQUESTED',
      'PGTAP-OUTBOX-001',
      'PRODUCT_BATCH',
      '40000000-0000-4000-8000-000000000001'::uuid,
      '2026-07-16 20:01:00+07'::timestamptz,
      '{"fixture":"notification-foundation"}'::jsonb,
      repeat('a', 64),
      '97000000-0000-4000-8000-000000000101'::uuid,
      'PENDING',
      0,
      '2026-07-16 20:01:00+07'::timestamptz,
      null,
      'pgtap.notification_foundation'
    )
  $sql$,
  'valid outbox event can be persisted'
);

-- 48: duplicate outbox identity is rejected
select throws_like(
  $sql$
    insert into notification.outbox_events (
      organization_id,
      event_type_code,
      source_event_key,
      entity_type_code,
      entity_id,
      occurred_at,
      payload,
      payload_hash,
      correlation_id,
      available_at,
      actor_user_id,
      process_name
    )
    values (
      '00000000-0000-4000-8000-000000000001'::uuid,
      'NOTIFICATION_EVALUATION_REQUESTED',
      'PGTAP-OUTBOX-001',
      'PRODUCT_BATCH',
      '40000000-0000-4000-8000-000000000001'::uuid,
      '2026-07-16 20:01:00+07'::timestamptz,
      '{}'::jsonb,
      repeat('a', 64),
      gen_random_uuid(),
      '2026-07-16 20:01:00+07'::timestamptz,
      null,
      'pgtap.notification_foundation'
    )
  $sql$,
  '%uq_notification_outbox_source_event%',
  'duplicate outbox source identity is rejected'
);

-- 49: completed outbox state requires completion time
select throws_like(
  $sql$
    insert into notification.outbox_events (
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
      available_at,
      actor_user_id,
      process_name
    )
    values (
      '00000000-0000-4000-8000-000000000001'::uuid,
      'NOTIFICATION_EVALUATION_REQUESTED',
      'PGTAP-OUTBOX-INVALID-COMPLETED',
      'PRODUCT_BATCH',
      '40000000-0000-4000-8000-000000000001'::uuid,
      '2026-07-16 20:02:00+07'::timestamptz,
      '{}'::jsonb,
      repeat('b', 64),
      gen_random_uuid(),
      'COMPLETED',
      1,
      '2026-07-16 20:02:00+07'::timestamptz,
      null,
      'pgtap.notification_foundation'
    )
  $sql$,
  '%ck_notification_outbox_status_payload%',
  'completed outbox event requires completed_at'
);

-- 50: valid rule run
select lives_ok(
  $sql$
    insert into notification.rule_runs (
      id,
      organization_id,
      rule_id,
      rule_code_snapshot,
      rule_version_snapshot,
      trigger_type_code,
      triggered_by_outbox_event_id,
      idempotency_key,
      status_code,
      started_at,
      evaluated_count,
      created_count,
      updated_count,
      resolved_count,
      skipped_count,
      error_count,
      summary,
      error_detail,
      correlation_id,
      actor_user_id,
      process_name
    )
    values (
      '98000000-0000-4000-8000-000000000001'::uuid,
      '00000000-0000-4000-8000-000000000001'::uuid,
      '80000000-0000-4000-8000-000000000001'::uuid,
      'EXPIRY_RISK',
      '1.0.0',
      'OUTBOX',
      '97000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-RUN-001',
      'STARTED',
      '2026-07-16 20:03:00+07'::timestamptz,
      0,
      0,
      0,
      0,
      0,
      0,
      '{}'::jsonb,
      '{}'::jsonb,
      '98000000-0000-4000-8000-000000000101'::uuid,
      null,
      'pgtap.notification_foundation'
    )
  $sql$,
  'valid notification rule run can start'
);

-- 51: duplicate rule-run idempotency is rejected
select throws_like(
  $sql$
    insert into notification.rule_runs (
      organization_id,
      rule_id,
      rule_code_snapshot,
      rule_version_snapshot,
      trigger_type_code,
      idempotency_key,
      status_code,
      started_at,
      summary,
      error_detail,
      correlation_id,
      actor_user_id,
      process_name
    )
    values (
      '00000000-0000-4000-8000-000000000001'::uuid,
      '80000000-0000-4000-8000-000000000001'::uuid,
      'EXPIRY_RISK',
      '1.0.0',
      'SCHEDULED',
      'PGTAP-RUN-001',
      'STARTED',
      '2026-07-16 20:04:00+07'::timestamptz,
      '{}'::jsonb,
      '{}'::jsonb,
      gen_random_uuid(),
      null,
      'pgtap.notification_foundation'
    )
  $sql$,
  '%uq_notification_rule_runs_idempotency%',
  'duplicate notification run identity is rejected'
);

-- 52: valid first episode
select lives_ok(
  $sql$
    insert into notification.notifications (
      id,
      organization_id,
      rule_id,
      rule_code_snapshot,
      rule_version_snapshot,
      template_version_snapshot,
      notification_type_code,
      category_code,
      entity_type_code,
      entity_id,
      episode_no,
      previous_notification_id,
      deduplication_key,
      deduplication_hash,
      lifecycle_status_code,
      stage_code,
      severity_code,
      title,
      message,
      action_code,
      action_route,
      condition_started_at,
      due_at,
      first_seen_at,
      last_seen_at,
      occurrence_count,
      source_snapshot,
      config_snapshot,
      created_at,
      updated_at,
      version_no
    )
    values (
      '95000000-0000-4000-8000-000000000001'::uuid,
      '00000000-0000-4000-8000-000000000001'::uuid,
      '80000000-0000-4000-8000-000000000001'::uuid,
      'EXPIRY_RISK',
      '1.0.0',
      '1.0.0',
      'EXPIRY_RISK',
      'EXPIRY',
      'PRODUCT_BATCH',
      '40000000-0000-4000-8000-000000000001'::uuid,
      1,
      null,
      'EXPIRY_RISK:40000000-0000-4000-8000-000000000001',
      repeat('c', 64),
      'OPEN',
      'D30',
      'HIGH',
      'Batch mendekati kedaluwarsa',
      'Batch demo berada dalam ambang 30 hari.',
      'OPEN_BATCH_EXPIRY_DETAIL',
      '/products/30000000-0000-4000-8000-000000000001/batches/40000000-0000-4000-8000-000000000001',
      '2026-07-16 20:05:00+07'::timestamptz,
      '2026-08-01 23:59:59+07'::timestamptz,
      '2026-07-16 20:05:00+07'::timestamptz,
      '2026-07-16 20:05:00+07'::timestamptz,
      1,
      '{"riskQty":5}'::jsonb,
      '{"thresholdDays":[90,60,30,0]}'::jsonb,
      '2026-07-16 20:05:00+07'::timestamptz,
      '2026-07-16 20:05:00+07'::timestamptz,
      1
    )
  $sql$,
  'first notification episode can be persisted'
);

-- 53: active duplicate is rejected
select throws_like(
  $sql$
    insert into notification.notifications (
      organization_id,
      rule_id,
      rule_code_snapshot,
      rule_version_snapshot,
      template_version_snapshot,
      notification_type_code,
      category_code,
      entity_type_code,
      entity_id,
      episode_no,
      deduplication_key,
      deduplication_hash,
      lifecycle_status_code,
      stage_code,
      severity_code,
      title,
      message,
      action_code,
      action_route,
      condition_started_at,
      first_seen_at,
      last_seen_at,
      source_snapshot,
      config_snapshot
    )
    values (
      '00000000-0000-4000-8000-000000000001'::uuid,
      '80000000-0000-4000-8000-000000000001'::uuid,
      'EXPIRY_RISK',
      '1.0.0',
      '1.0.0',
      'EXPIRY_RISK',
      'EXPIRY',
      'PRODUCT_BATCH',
      '40000000-0000-4000-8000-000000000001'::uuid,
      2,
      'EXPIRY_RISK:40000000-0000-4000-8000-000000000001',
      repeat('c', 64),
      'OPEN',
      'D30',
      'HIGH',
      'Duplicate',
      'This active duplicate must be rejected.',
      'OPEN_BATCH_EXPIRY_DETAIL',
      '/products/30000000-0000-4000-8000-000000000001/batches/40000000-0000-4000-8000-000000000001',
      '2026-07-16 20:05:00+07'::timestamptz,
      '2026-07-16 20:05:00+07'::timestamptz,
      '2026-07-16 20:05:00+07'::timestamptz,
      '{}'::jsonb,
      '{}'::jsonb
    )
  $sql$,
  '%uidx_notifications_active_dedup%',
  'one active dedup hash cannot produce a second active episode'
);

-- 54: resolution preserves history
select lives_ok(
  $sql$
    update notification.notifications
    set
      lifecycle_status_code = 'RESOLVED',
      resolved_at = '2026-07-16 20:06:00+07'::timestamptz,
      resolution_code = 'SOURCE_CONDITION_CLEARED',
      resolution_snapshot = '{"riskQty":0}'::jsonb,
      last_seen_at = '2026-07-16 20:06:00+07'::timestamptz
    where id = '95000000-0000-4000-8000-000000000001'::uuid
  $sql$,
  'source-cleared notification can be resolved'
);

-- 55: row version increments on lifecycle mutation
select is(
  (
    select version_no
    from notification.notifications
    where id = '95000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'notification version increments after lifecycle update'
);

-- 56: recurrence creates a linked new episode
select lives_ok(
  $sql$
    insert into notification.notifications (
      id,
      organization_id,
      rule_id,
      rule_code_snapshot,
      rule_version_snapshot,
      template_version_snapshot,
      notification_type_code,
      category_code,
      entity_type_code,
      entity_id,
      episode_no,
      previous_notification_id,
      deduplication_key,
      deduplication_hash,
      lifecycle_status_code,
      stage_code,
      severity_code,
      title,
      message,
      action_code,
      action_route,
      condition_started_at,
      first_seen_at,
      last_seen_at,
      occurrence_count,
      source_snapshot,
      config_snapshot
    )
    values (
      '95000000-0000-4000-8000-000000000002'::uuid,
      '00000000-0000-4000-8000-000000000001'::uuid,
      '80000000-0000-4000-8000-000000000001'::uuid,
      'EXPIRY_RISK',
      '1.0.0',
      '1.0.0',
      'EXPIRY_RISK',
      'EXPIRY',
      'PRODUCT_BATCH',
      '40000000-0000-4000-8000-000000000001'::uuid,
      2,
      '95000000-0000-4000-8000-000000000001'::uuid,
      'EXPIRY_RISK:40000000-0000-4000-8000-000000000001',
      repeat('c', 64),
      'OPEN',
      'D30',
      'HIGH',
      'Batch kembali mendekati kedaluwarsa',
      'Kondisi yang telah selesai muncul kembali sebagai episode baru.',
      'OPEN_BATCH_EXPIRY_DETAIL',
      '/products/30000000-0000-4000-8000-000000000001/batches/40000000-0000-4000-8000-000000000001',
      '2026-07-16 20:07:00+07'::timestamptz,
      '2026-07-16 20:07:00+07'::timestamptz,
      '2026-07-16 20:07:00+07'::timestamptz,
      1,
      '{"riskQty":5}'::jsonb,
      '{"thresholdDays":[90,60,30,0]}'::jsonb
    )
  $sql$,
  'resolved condition may recur as a linked new episode'
);

-- 57-58: one active and one resolved episode remain
select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and deduplication_hash = repeat('c', 64)
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  1::bigint,
  'only one episode is active for the dedup hash'
);
select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and deduplication_hash = repeat('c', 64)
      and lifecycle_status_code = 'RESOLVED'
  ),
  1::bigint,
  'resolved episode remains available as history'
);

-- Other-organization fixture for RLS
insert into notification.notifications (
  id,
  organization_id,
  rule_id,
  rule_code_snapshot,
  rule_version_snapshot,
  template_version_snapshot,
  notification_type_code,
  category_code,
  entity_type_code,
  entity_id,
  episode_no,
  deduplication_key,
  deduplication_hash,
  lifecycle_status_code,
  stage_code,
  severity_code,
  title,
  message,
  action_code,
  action_route,
  condition_started_at,
  first_seen_at,
  last_seen_at,
  source_snapshot,
  config_snapshot
)
values (
  '95000000-0000-4000-8000-000000000099'::uuid,
  '00000000-0000-4000-8000-000000000004'::uuid,
  '80000000-0000-4000-8000-000000000099'::uuid,
  'PGTAP_OTHER_RULE',
  '1.0.0',
  '1.0.0',
  'SYSTEM_JOB_FAILED',
  'SYSTEM_JOB',
  'SYSTEM_JOB',
  '95000000-0000-4000-8000-000000000199'::uuid,
  1,
  'SYSTEM_JOB_FAILED:OTHER',
  repeat('d', 64),
  'OPEN',
  'FAILED',
  'HIGH',
  'Other organization notification',
  'This row must remain isolated.',
  'OPEN_JOB_DETAIL',
  '/system/jobs/other',
  '2026-07-16 20:08:00+07'::timestamptz,
  '2026-07-16 20:08:00+07'::timestamptz,
  '2026-07-16 20:08:00+07'::timestamptz,
  '{}'::jsonb,
  '{}'::jsonb
);

-- 59: append-only event can be written
select lives_ok(
  $sql$
    insert into notification.notification_events (
      id,
      organization_id,
      notification_id,
      event_type_code,
      from_lifecycle_status_code,
      to_lifecycle_status_code,
      from_stage_code,
      to_stage_code,
      from_severity_code,
      to_severity_code,
      source_snapshot,
      note,
      actor_type_code,
      actor_user_id,
      process_name,
      occurred_at,
      correlation_id
    )
    values (
      '96000000-0000-4000-8000-000000000001'::uuid,
      '00000000-0000-4000-8000-000000000001'::uuid,
      '95000000-0000-4000-8000-000000000002'::uuid,
      'CREATED',
      null,
      'OPEN',
      null,
      'D30',
      null,
      'HIGH',
      '{"riskQty":5}'::jsonb,
      'Episode created by pgTAP.',
      'SYSTEM_PROCESS',
      null,
      'pgtap.notification_foundation',
      '2026-07-16 20:07:00+07'::timestamptz,
      '96000000-0000-4000-8000-000000000101'::uuid
    )
  $sql$,
  'notification history event can be appended'
);

-- 60-61: history is immutable
select throws_ok(
  $sql$
    update notification.notification_events
    set note = 'mutated'
    where id = '96000000-0000-4000-8000-000000000001'::uuid
  $sql$,
  'P0001',
  'IMMUTABLE_NOTIFICATION_EVENT',
  'notification event updates are rejected'
);
select throws_ok(
  $sql$
    delete from notification.notification_events
    where id = '96000000-0000-4000-8000-000000000001'::uuid
  $sql$,
  'P0001',
  'IMMUTABLE_NOTIFICATION_EVENT',
  'notification event deletes are rejected'
);

insert into notification.user_states (
  id,
  organization_id,
  notification_id,
  user_id,
  read_state_code,
  read_at,
  archived_at,
  last_seen_version_no,
  created_at,
  updated_at
)
values
(
  '99000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '95000000-0000-4000-8000-000000000002'::uuid,
  '94000000-0000-4000-8000-000000000001'::uuid,
  'UNREAD',
  null,
  null,
  1,
  '2026-07-16 20:09:00+07'::timestamptz,
  '2026-07-16 20:09:00+07'::timestamptz
),
(
  '99000000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '95000000-0000-4000-8000-000000000002'::uuid,
  '94000000-0000-4000-8000-000000000002'::uuid,
  'READ',
  '2026-07-16 20:09:30+07'::timestamptz,
  null,
  1,
  '2026-07-16 20:09:30+07'::timestamptz,
  '2026-07-16 20:09:30+07'::timestamptz
);

-- 62: each Admin has independent state
select is(
  (
    select count(*)
    from notification.user_states
    where notification_id =
      '95000000-0000-4000-8000-000000000002'::uuid
  ),
  2::bigint,
  'one notification may have independent state for two Admin accounts'
);

-- JWT context for RLS verification
select set_config(
  'request.jwt.claim.sub',
  '94000000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94000000-0000-4000-8000-000000000001',
    'role',
    'authenticated',
    'email',
    'pgtap.notification.one@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

-- 63: notification RLS isolates organization
select is(
  (
    select count(*)
    from notification.notifications
    where id in (
      '95000000-0000-4000-8000-000000000002'::uuid,
      '95000000-0000-4000-8000-000000000099'::uuid
    )
  ),
  1::bigint,
  'authenticated Admin sees only current-organization notifications'
);

-- 64: user-state RLS isolates account
select is(
  (
    select count(*)
    from notification.user_states
    where notification_id =
      '95000000-0000-4000-8000-000000000002'::uuid
  ),
  1::bigint,
  'authenticated Admin sees only their own notification state'
);

reset role;

-- 65: READ requires read_at
select throws_like(
  $sql$
    insert into notification.user_states (
      organization_id,
      notification_id,
      user_id,
      read_state_code,
      read_at,
      archived_at,
      last_seen_version_no
    )
    values (
      '00000000-0000-4000-8000-000000000001'::uuid,
      '95000000-0000-4000-8000-000000000001'::uuid,
      '94000000-0000-4000-8000-000000000001'::uuid,
      'READ',
      null,
      null,
      1
    )
  $sql$,
  '%ck_notification_user_states_state_payload%',
  'READ state requires a read timestamp'
);

-- 66: updating one Admin state does not change the other
update notification.user_states
set
  read_state_code = 'READ',
  read_at = '2026-07-16 20:10:00+07'::timestamptz,
  last_seen_version_no = 1
where id = '99000000-0000-4000-8000-000000000001'::uuid;

select is(
  (
    select read_state_code
    from notification.user_states
    where id = '99000000-0000-4000-8000-000000000002'::uuid
  ),
  'READ',
  'changing one Admin state leaves the other Admin state unchanged'
);

select * from finish();
rollback;
