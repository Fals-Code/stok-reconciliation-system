begin;

create extension if not exists pgtap with schema extensions;

select plan(75);

-- 1-4: public read API contract
select has_function(
  'api'::name,
  'notification_list'::name,
  array[
    'text',
    'text',
    'text',
    'text',
    'boolean',
    'integer',
    'timestamp with time zone',
    'uuid'
  ]::text[]
);

select has_function(
  'api'::name,
  'notification_detail'::name,
  array['uuid']::text[]
);

select has_function(
  'api'::name,
  'notification_unread_count'::name,
  array[]::text[]
);

select has_function(
  'api'::name,
  'notification_event_history'::name,
  array[
    'uuid',
    'integer',
    'timestamp with time zone',
    'uuid'
  ]::text[]
);

-- 5: badge query has a scalar contract
select function_returns(
  'api',
  'notification_unread_count',
  array[]::text[],
  'bigint'
);

-- 6-13: only authenticated clients execute the public read API
select ok(
  has_function_privilege(
    'authenticated',
    'api.notification_list(text,text,text,text,boolean,integer,timestamptz,uuid)',
    'EXECUTE'
  ),
  'authenticated Admin may list notifications'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.notification_list(text,text,text,text,boolean,integer,timestamptz,uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot list notifications'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.notification_detail(uuid)',
    'EXECUTE'
  ),
  'authenticated Admin may read notification detail'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.notification_detail(uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot read notification detail'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.notification_unread_count()',
    'EXECUTE'
  ),
  'authenticated Admin may read their unread badge count'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.notification_unread_count()',
    'EXECUTE'
  ),
  'anonymous clients cannot read unread badge count'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.notification_event_history(uuid,integer,timestamptz,uuid)',
    'EXECUTE'
  ),
  'authenticated Admin may read notification event history'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.notification_event_history(uuid,integer,timestamptz,uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot read notification event history'
);

-- 14-21: query functions are stable security-definer boundaries
select is(
  (
    select procedure.prosecdef
    from pg_proc procedure
    where procedure.oid =
      'api.notification_list(text,text,text,text,boolean,integer,timestamptz,uuid)'::regprocedure
  ),
  true,
  'notification list derives identity inside a security-definer boundary'
);

select is(
  (
    select procedure.provolatile::text
    from pg_proc procedure
    where procedure.oid =
      'api.notification_list(text,text,text,text,boolean,integer,timestamptz,uuid)'::regprocedure
  ),
  's',
  'notification list is declared stable'
);

select is(
  (
    select procedure.prosecdef
    from pg_proc procedure
    where procedure.oid =
      'api.notification_detail(uuid)'::regprocedure
  ),
  true,
  'notification detail derives identity inside a security-definer boundary'
);

select is(
  (
    select procedure.provolatile::text
    from pg_proc procedure
    where procedure.oid =
      'api.notification_detail(uuid)'::regprocedure
  ),
  's',
  'notification detail is declared stable'
);

select is(
  (
    select procedure.prosecdef
    from pg_proc procedure
    where procedure.oid =
      'api.notification_unread_count()'::regprocedure
  ),
  true,
  'unread count derives identity inside a security-definer boundary'
);

select is(
  (
    select procedure.provolatile::text
    from pg_proc procedure
    where procedure.oid =
      'api.notification_unread_count()'::regprocedure
  ),
  's',
  'unread count is declared stable'
);

select is(
  (
    select procedure.prosecdef
    from pg_proc procedure
    where procedure.oid =
      'api.notification_event_history(uuid,integer,timestamptz,uuid)'::regprocedure
  ),
  true,
  'event history derives identity inside a security-definer boundary'
);

select is(
  (
    select procedure.provolatile::text
    from pg_proc procedure
    where procedure.oid =
      'api.notification_event_history(uuid,integer,timestamptz,uuid)'::regprocedure
  ),
  's',
  'event history is declared stable'
);

-- Isolated users and organizations
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
  '94300000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.read.one@glowlab.invalid',
  '2026-07-16 21:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-07-16 21:00:00+07'::timestamptz,
  false,
  false
),
(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94300000-0000-4000-8000-000000000002'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.read.two@glowlab.invalid',
  '2026-07-16 21:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-07-16 21:00:00+07'::timestamptz,
  false,
  false
),
(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94300000-0000-4000-8000-000000000003'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.read.other@glowlab.invalid',
  '2026-07-16 21:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-07-16 21:00:00+07'::timestamptz,
  false,
  false
);

insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active
)
values (
  '00000000-0000-4000-8000-000000000007'::uuid,
  'PGTAP_NOTIFICATION_READ_OTHER',
  'pgTAP Notification Read Other Organization',
  'Asia/Jakarta',
  true
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
  '94300000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Notification Read Admin One',
  'PGTAP-NTF-READ-ONE',
  'ADMIN',
  true
),
(
  '94300000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Notification Read Admin Two',
  'PGTAP-NTF-READ-TWO',
  'ADMIN',
  true
),
(
  '94300000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000007'::uuid,
  'pgTAP Notification Read Other Admin',
  'PGTAP-NTF-READ-OTHER',
  'ADMIN',
  true
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
  created_at,
  updated_at
)
values
(
  '80400000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'READ_API_EXPIRY',
  '1.0.0',
  'EXPIRY',
  'SCHEDULED',
  'PRODUCT_BATCH',
  'EXPIRY_SEVERITY',
  'EXPIRY_STAGE',
  'POSITIVE_BALANCE',
  'ZERO_BALANCE',
  '1.0.0',
  'OPEN_BATCH_EXPIRY_DETAIL',
  '{}'::jsonb,
  true,
  '2026-07-16 00:00:00+07'::timestamptz,
  null,
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-07-16 21:00:00+07'::timestamptz
),
(
  '80400000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'READ_API_RETURN',
  '1.0.0',
  'RETURN',
  'EVENT_DRIVEN',
  'RETURN',
  'RETURN_SEVERITY',
  'RETURN_STAGE',
  'AWAITING_INSPECTION',
  'INSPECTION_COMPLETED',
  '1.0.0',
  'OPEN_RETURN_DETAIL',
  '{}'::jsonb,
  true,
  '2026-07-16 00:00:00+07'::timestamptz,
  null,
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-07-16 21:00:00+07'::timestamptz
),
(
  '80400000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'READ_API_RECONCILIATION',
  '1.0.0',
  'RECONCILIATION',
  'EVENT_DRIVEN',
  'RECONCILIATION_RUN',
  'RUN_SEVERITY',
  'RUN_STAGE',
  'RUN_FAILED',
  'RUN_RECOVERED',
  '1.0.0',
  'OPEN_RECONCILIATION_RUN',
  '{}'::jsonb,
  true,
  '2026-07-16 00:00:00+07'::timestamptz,
  null,
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-07-16 21:00:00+07'::timestamptz
),
(
  '80400000-0000-4000-8000-000000000004'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'READ_API_SYSTEM_JOB',
  '1.0.0',
  'SYSTEM_JOB',
  'HYBRID',
  'SYSTEM_JOB',
  'JOB_SEVERITY',
  'JOB_STAGE',
  'JOB_FAILED',
  'JOB_RECOVERED',
  '1.0.0',
  'OPEN_JOB_DETAIL',
  '{}'::jsonb,
  true,
  '2026-07-16 00:00:00+07'::timestamptz,
  null,
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-07-16 21:00:00+07'::timestamptz
),
(
  '80500000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000007'::uuid,
  'READ_API_OTHER_ORG',
  '1.0.0',
  'SYSTEM_JOB',
  'SCHEDULED',
  'SYSTEM_JOB',
  'JOB_SEVERITY',
  'JOB_STAGE',
  'JOB_FAILED',
  'JOB_RECOVERED',
  '1.0.0',
  'OPEN_JOB_DETAIL',
  '{}'::jsonb,
  true,
  '2026-07-16 00:00:00+07'::timestamptz,
  null,
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-07-16 21:00:00+07'::timestamptz
);

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
  acknowledged_at,
  acknowledged_by,
  acknowledgment_note,
  resolved_at,
  resolution_code,
  resolution_snapshot,
  source_snapshot,
  config_snapshot,
  created_at,
  updated_at,
  version_no
)
values
(
  '95300000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '80400000-0000-4000-8000-000000000001'::uuid,
  'READ_API_EXPIRY',
  '1.0.0',
  '1.0.0',
  'BATCH_EXPIRY_RISK',
  'EXPIRY',
  'PRODUCT_BATCH',
  '40400000-0000-4000-8000-000000000001'::uuid,
  1,
  null,
  'read_api_expiry:40400000-0000-4000-8000-000000000001',
  repeat('1', 64),
  'OPEN',
  'D30',
  'HIGH',
  'Batch mendekati kedaluwarsa',
  'Batch serum berada dalam ambang 30 hari.',
  'OPEN_BATCH_EXPIRY_DETAIL',
  '/products/read-api/batches/40400000-0000-4000-8000-000000000001',
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-08-01 23:59:59+07'::timestamptz,
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-07-16 21:10:00+07'::timestamptz,
  3,
  null,
  null,
  null,
  null,
  null,
  null,
  '{"riskQty":5,"daysRemaining":16}'::jsonb,
  '{"thresholdDays":[90,60,30,0]}'::jsonb,
  '2026-07-16 21:00:00+07'::timestamptz,
  '2026-07-16 21:10:00+07'::timestamptz,
  3
),
(
  '95300000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '80400000-0000-4000-8000-000000000002'::uuid,
  'READ_API_RETURN',
  '1.0.0',
  '1.0.0',
  'RETURN_AWAITING_INSPECTION',
  'RETURN',
  'RETURN',
  '40400000-0000-4000-8000-000000000002'::uuid,
  1,
  null,
  'read_api_return:40400000-0000-4000-8000-000000000002',
  repeat('2', 64),
  'ACKNOWLEDGED',
  'AWAITING_INSPECTION',
  'WARNING',
  'Return menunggu inspeksi',
  'Return sudah diterima dan masih menunggu inspeksi.',
  'OPEN_RETURN_DETAIL',
  '/returns/40400000-0000-4000-8000-000000000002',
  '2026-07-16 21:01:00+07'::timestamptz,
  null,
  '2026-07-16 21:01:00+07'::timestamptz,
  '2026-07-16 21:09:00+07'::timestamptz,
  2,
  '2026-07-16 21:02:00+07'::timestamptz,
  '94300000-0000-4000-8000-000000000002'::uuid,
  'Inspection owner confirmed.',
  null,
  null,
  null,
  '{"returnStatus":"RECEIVED"}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 21:01:00+07'::timestamptz,
  '2026-07-16 21:09:00+07'::timestamptz,
  2
),
(
  '95300000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '80400000-0000-4000-8000-000000000003'::uuid,
  'READ_API_RECONCILIATION',
  '1.0.0',
  '1.0.0',
  'RECONCILIATION_RUN_FAILED',
  'RECONCILIATION',
  'RECONCILIATION_RUN',
  '40400000-0000-4000-8000-000000000003'::uuid,
  1,
  null,
  'read_api_reconciliation:40400000-0000-4000-8000-000000000003',
  repeat('3', 64),
  'RESOLVED',
  'FAILED',
  'CRITICAL',
  'Reconciliation run gagal',
  'Reconciliation run gagal sebelum seluruh comparison selesai.',
  'OPEN_RECONCILIATION_RUN',
  '/reconciliation/runs/40400000-0000-4000-8000-000000000003',
  '2026-07-16 21:02:00+07'::timestamptz,
  null,
  '2026-07-16 21:02:00+07'::timestamptz,
  '2026-07-16 21:08:00+07'::timestamptz,
  1,
  null,
  null,
  null,
  '2026-07-16 21:08:00+07'::timestamptz,
  'SOURCE_CONDITION_CLEARED',
  '{"runStatus":"SUCCEEDED"}'::jsonb,
  '{"runStatus":"FAILED","errorCode":"PGTAP"}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 21:02:00+07'::timestamptz,
  '2026-07-16 21:08:00+07'::timestamptz,
  2
),
(
  '95300000-0000-4000-8000-000000000004'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '80400000-0000-4000-8000-000000000004'::uuid,
  'READ_API_SYSTEM_JOB',
  '1.0.0',
  '1.0.0',
  'SYSTEM_JOB_FAILED',
  'SYSTEM_JOB',
  'SYSTEM_JOB',
  '40400000-0000-4000-8000-000000000004'::uuid,
  1,
  null,
  'read_api_system_job:40400000-0000-4000-8000-000000000004',
  repeat('4', 64),
  'OPEN',
  'FAILED',
  'INFO',
  'System job membutuhkan perhatian',
  'A scheduled job reported a recoverable failure.',
  'OPEN_JOB_DETAIL',
  '/system/jobs/40400000-0000-4000-8000-000000000004',
  '2026-07-16 21:03:00+07'::timestamptz,
  null,
  '2026-07-16 21:03:00+07'::timestamptz,
  '2026-07-16 21:10:00+07'::timestamptz,
  1,
  null,
  null,
  null,
  null,
  null,
  null,
  '{"jobStatus":"FAILED_RETRYABLE"}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 21:03:00+07'::timestamptz,
  '2026-07-16 21:10:00+07'::timestamptz,
  1
),
(
  '95300000-0000-4000-8000-000000000099'::uuid,
  '00000000-0000-4000-8000-000000000007'::uuid,
  '80500000-0000-4000-8000-000000000001'::uuid,
  'READ_API_OTHER_ORG',
  '1.0.0',
  '1.0.0',
  'OTHER_ORG_JOB_FAILED',
  'SYSTEM_JOB',
  'SYSTEM_JOB',
  '40400000-0000-4000-8000-000000000099'::uuid,
  1,
  null,
  'read_api_other_org:40400000-0000-4000-8000-000000000099',
  repeat('5', 64),
  'OPEN',
  'FAILED',
  'HIGH',
  'Other organization job failed',
  'This notification must remain isolated.',
  'OPEN_JOB_DETAIL',
  '/system/jobs/other-organization',
  '2026-07-16 21:04:00+07'::timestamptz,
  null,
  '2026-07-16 21:04:00+07'::timestamptz,
  '2026-07-16 21:11:00+07'::timestamptz,
  1,
  null,
  null,
  null,
  null,
  null,
  null,
  '{"jobStatus":"FAILED"}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 21:04:00+07'::timestamptz,
  '2026-07-16 21:11:00+07'::timestamptz,
  1
);

insert into notification.user_states (
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
  '00000000-0000-4000-8000-000000000001'::uuid,
  '95300000-0000-4000-8000-000000000002'::uuid,
  '94300000-0000-4000-8000-000000000001'::uuid,
  'READ',
  '2026-07-16 21:11:00+07'::timestamptz,
  null,
  2,
  '2026-07-16 21:11:00+07'::timestamptz,
  '2026-07-16 21:11:00+07'::timestamptz
),
(
  '00000000-0000-4000-8000-000000000001'::uuid,
  '95300000-0000-4000-8000-000000000003'::uuid,
  '94300000-0000-4000-8000-000000000001'::uuid,
  'ARCHIVED',
  '2026-07-16 21:11:00+07'::timestamptz,
  '2026-07-16 21:12:00+07'::timestamptz,
  2,
  '2026-07-16 21:11:00+07'::timestamptz,
  '2026-07-16 21:12:00+07'::timestamptz
),
(
  '00000000-0000-4000-8000-000000000001'::uuid,
  '95300000-0000-4000-8000-000000000001'::uuid,
  '94300000-0000-4000-8000-000000000002'::uuid,
  'READ',
  '2026-07-16 21:12:00+07'::timestamptz,
  null,
  3,
  '2026-07-16 21:12:00+07'::timestamptz,
  '2026-07-16 21:12:00+07'::timestamptz
);

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
  correlation_id,
  created_at
)
values
(
  '96300000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '95300000-0000-4000-8000-000000000001'::uuid,
  'CREATED',
  null,
  'OPEN',
  null,
  'D60',
  null,
  'WARNING',
  '{"riskQty":5,"daysRemaining":60}'::jsonb,
  'Initial expiry-risk episode.',
  'SYSTEM_PROCESS',
  null,
  'pgtap.notification_read_api',
  '2026-07-16 21:00:00+07'::timestamptz,
  '97300000-0000-4000-8000-000000000001'::uuid,
  '2026-07-16 21:00:00+07'::timestamptz
),
(
  '96300000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '95300000-0000-4000-8000-000000000001'::uuid,
  'SEVERITY_CHANGED',
  'OPEN',
  'OPEN',
  'D60',
  'D60',
  'WARNING',
  'HIGH',
  '{"riskQty":5,"daysRemaining":30}'::jsonb,
  'Severity increased after Admin review.',
  'USER',
  '94300000-0000-4000-8000-000000000002'::uuid,
  null,
  '2026-07-16 21:05:00+07'::timestamptz,
  '97300000-0000-4000-8000-000000000002'::uuid,
  '2026-07-16 21:05:00+07'::timestamptz
),
(
  '96300000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '95300000-0000-4000-8000-000000000001'::uuid,
  'STAGE_ESCALATED',
  'OPEN',
  'OPEN',
  'D60',
  'D30',
  'HIGH',
  'HIGH',
  '{"riskQty":5,"daysRemaining":16}'::jsonb,
  'Expiry stage moved to D30.',
  'SYSTEM_PROCESS',
  null,
  'pgtap.notification_read_api',
  '2026-07-16 21:10:00+07'::timestamptz,
  '97300000-0000-4000-8000-000000000003'::uuid,
  '2026-07-16 21:10:00+07'::timestamptz
),
(
  '96300000-0000-4000-8000-000000000099'::uuid,
  '00000000-0000-4000-8000-000000000007'::uuid,
  '95300000-0000-4000-8000-000000000099'::uuid,
  'CREATED',
  null,
  'OPEN',
  null,
  'FAILED',
  null,
  'HIGH',
  '{"jobStatus":"FAILED"}'::jsonb,
  'Other organization event.',
  'SYSTEM_PROCESS',
  null,
  'pgtap.notification_read_api',
  '2026-07-16 21:11:00+07'::timestamptz,
  '97300000-0000-4000-8000-000000000099'::uuid,
  '2026-07-16 21:11:00+07'::timestamptz
);

-- Admin One trusted session
select set_config(
  'request.jwt.claim.sub',
  '94300000-0000-4000-8000-000000000001',
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
    '94300000-0000-4000-8000-000000000001',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 22-43: list filters, per-user state, stable ordering, and validation
select is(
  (select count(*) from api.notification_list()),
  3::bigint,
  'default list excludes only the current Admin archived state'
);

select is(
  (
    select count(*)
    from api.notification_list()
    where notification_id =
      '95300000-0000-4000-8000-000000000003'::uuid
  ),
  0::bigint,
  'default list excludes the current Admin archived notification'
);

select is(
  (
    select notification_id
    from api.notification_list()
    limit 1
  ),
  '95300000-0000-4000-8000-000000000004'::uuid,
  'list orders equal timestamps by notification id descending'
);

select is(
  (
    select notification_id
    from api.notification_list()
    offset 1
    limit 1
  ),
  '95300000-0000-4000-8000-000000000001'::uuid,
  'stable ordering places the second equal-timestamp id next'
);

select is(
  (
    select read_state_code
    from api.notification_list()
    where notification_id =
      '95300000-0000-4000-8000-000000000001'::uuid
  ),
  'UNREAD',
  'another Admin READ state is not exposed to Admin One'
);

select is(
  (
    select read_state_code
    from api.notification_list()
    where notification_id =
      '95300000-0000-4000-8000-000000000002'::uuid
  ),
  'READ',
  'Admin One sees only their own READ state'
);

select is(
  (
    select count(*)
    from api.notification_list(
      p_lifecycle_status_code => 'open'
    )
  ),
  2::bigint,
  'lifecycle filter is normalized and applied'
);

select is(
  (
    select count(*)
    from api.notification_list(
      p_severity_code => 'high'
    )
  ),
  1::bigint,
  'severity filter is normalized and applied'
);

select is(
  (
    select count(*)
    from api.notification_list(
      p_category_code => 'return'
    )
  ),
  1::bigint,
  'category filter is normalized and applied'
);

select is(
  (
    select count(*)
    from api.notification_list(
      p_read_state_code => 'UNREAD'
    )
  ),
  2::bigint,
  'UNREAD filter includes rows without stored user state'
);

select is(
  (
    select count(*)
    from api.notification_list(
      p_read_state_code => 'READ'
    )
  ),
  1::bigint,
  'READ filter uses only the current Admin state'
);

select is(
  (
    select count(*)
    from api.notification_list(
      p_read_state_code => 'ARCHIVED_FOR_USER',
      p_include_archived => true
    )
  ),
  1::bigint,
  'archive alias returns only the current Admin archived row'
);

select is(
  (
    select count(*)
    from api.notification_list(
      p_include_archived => true
    )
  ),
  4::bigint,
  'include archived returns all current-organization notifications'
);

select is(
  (
    select count(*)
    from api.notification_list(p_limit => 1)
  ),
  1::bigint,
  'list respects the requested page size'
);

select is(
  (
    select notification_id
    from api.notification_list(
      p_limit => 1,
      p_before_last_seen_at =>
        '2026-07-16 21:10:00+07'::timestamptz,
      p_before_id =>
        '95300000-0000-4000-8000-000000000004'::uuid
    )
  ),
  '95300000-0000-4000-8000-000000000001'::uuid,
  'compound cursor advances deterministically across equal timestamps'
);

select throws_ok(
  $sql$
    select *
    from api.notification_list(
      p_before_last_seen_at =>
        '2026-07-16 21:10:00+07'::timestamptz
    )
  $sql$,
  'P0001',
  'NOTIFICATION_LIST_CURSOR_INVALID',
  'list rejects half of a compound cursor'
);

select throws_ok(
  $sql$
    select *
    from api.notification_list(p_limit => 101)
  $sql$,
  'P0001',
  'NOTIFICATION_LIST_LIMIT_INVALID',
  'list rejects an excessive page size'
);

select throws_ok(
  $sql$
    select *
    from api.notification_list(
      p_lifecycle_status_code => 'DISMISSED'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_LIFECYCLE_FILTER_INVALID',
  'list rejects unsupported lifecycle filters'
);

select throws_ok(
  $sql$
    select *
    from api.notification_list(
      p_severity_code => 'EMERGENCY'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_SEVERITY_FILTER_INVALID',
  'list rejects unsupported severity filters'
);

select throws_ok(
  $sql$
    select *
    from api.notification_list(
      p_read_state_code => 'HIDDEN'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_READ_STATE_FILTER_INVALID',
  'list rejects unsupported read-state filters'
);

select throws_ok(
  $sql$
    select *
    from api.notification_list(p_category_code => '   ')
  $sql$,
  'P0001',
  'NOTIFICATION_CATEGORY_FILTER_INVALID',
  'list rejects a blank category filter'
);

select is(
  (select count(*) from notification.user_states),
  2::bigint,
  'listing notifications creates no current-user state side effect'
);

-- 44: unread badge is current-user scoped
select is(
  api.notification_unread_count(),
  2::bigint,
  'Admin One unread count includes only their UNREAD rows'
);

-- 45-53: detail remains read-only and includes full current-user context
select is(
  (
    select read_state_code
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000001'::uuid
    )
  ),
  'UNREAD',
  'detail treats missing current-user state as UNREAD'
);

select is(
  (
    select read_state_code
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000003'::uuid
    )
  ),
  'ARCHIVED_FOR_USER',
  'detail exposes the public archive alias for the current Admin'
);

select is(
  (
    select lifecycle_status_code
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000003'::uuid
    )
  ),
  'RESOLVED',
  'resolved notification remains available as history'
);

select is(
  (
    select source_snapshot
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000003'::uuid
    )
  ),
  '{"runStatus":"FAILED","errorCode":"PGTAP"}'::jsonb,
  'detail returns the source-condition snapshot'
);

select is(
  (
    select resolution_snapshot
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000003'::uuid
    )
  ),
  '{"runStatus":"SUCCEEDED"}'::jsonb,
  'detail returns the immutable resolution snapshot'
);

select is(
  (
    select action_route
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000003'::uuid
    )
  ),
  '/reconciliation/runs/40400000-0000-4000-8000-000000000003',
  'detail returns the deep link without executing it'
);

select is(
  (
    select acknowledged_by_display_name
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000002'::uuid
    )
  ),
  'pgTAP Notification Read Admin Two',
  'detail resolves the organization-scoped acknowledgment actor name'
);

select throws_ok(
  $sql$
    select *
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000099'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_NOT_FOUND',
  'detail does not disclose another organization notification'
);

select is(
  (select count(*) from notification.user_states),
  2::bigint,
  'reading detail does not mark the notification as read'
);

-- 54-64: event history is chronological, paginated, isolated, and read-only
select is(
  (
    select count(*)
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000001'::uuid
    )
  ),
  3::bigint,
  'event history returns all current-organization events'
);

select is(
  (
    select event_type_code
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000001'::uuid
    )
    limit 1
  ),
  'CREATED',
  'event history begins with the earliest event'
);

select is(
  (
    select event_type_code
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000001'::uuid
    )
    order by occurred_at desc, event_id desc
    limit 1
  ),
  'STAGE_ESCALATED',
  'event history exposes the latest event without reversing storage'
);

select is(
  (
    select actor_display_name
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000001'::uuid
    )
    where event_type_code = 'SEVERITY_CHANGED'
  ),
  'pgTAP Notification Read Admin Two',
  'event history resolves a user actor inside the organization'
);

select is(
  (
    select count(*)
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000001'::uuid,
      p_limit => 2
    )
  ),
  2::bigint,
  'event history respects its page size'
);

select is(
  (
    select count(*)
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000001'::uuid,
      p_limit => 2,
      p_after_occurred_at =>
        '2026-07-16 21:05:00+07'::timestamptz,
      p_after_id =>
        '96300000-0000-4000-8000-000000000002'::uuid
    )
  ),
  1::bigint,
  'event cursor returns only later history'
);

select is(
  (
    select event_type_code
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000001'::uuid,
      p_limit => 2,
      p_after_occurred_at =>
        '2026-07-16 21:05:00+07'::timestamptz,
      p_after_id =>
        '96300000-0000-4000-8000-000000000002'::uuid
    )
  ),
  'STAGE_ESCALATED',
  'event cursor resumes at the correct next event'
);

select throws_ok(
  $sql$
    select *
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000001'::uuid,
      p_after_occurred_at =>
        '2026-07-16 21:05:00+07'::timestamptz
    )
  $sql$,
  'P0001',
  'NOTIFICATION_EVENT_CURSOR_INVALID',
  'event history rejects half of a compound cursor'
);

select throws_ok(
  $sql$
    select *
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000001'::uuid,
      p_limit => 201
    )
  $sql$,
  'P0001',
  'NOTIFICATION_EVENT_LIMIT_INVALID',
  'event history rejects an excessive page size'
);

select throws_ok(
  $sql$
    select *
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000099'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_NOT_FOUND',
  'event history does not disclose another organization notification'
);

select is(
  (select count(*) from notification.user_states),
  2::bigint,
  'reading event history creates no current-user state side effect'
);

reset role;

-- Admin Two has a different read-state projection over the same notifications
select set_config(
  'request.jwt.claim.sub',
  '94300000-0000-4000-8000-000000000002',
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
    '94300000-0000-4000-8000-000000000002',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 65-70: per-user list and badge isolation
select is(
  (select count(*) from api.notification_list()),
  4::bigint,
  'Admin Two default list includes the row archived only by Admin One'
);

select is(
  (
    select read_state_code
    from api.notification_list()
    where notification_id =
      '95300000-0000-4000-8000-000000000001'::uuid
  ),
  'READ',
  'Admin Two sees their own READ state'
);

select is(
  (
    select read_state_code
    from api.notification_list()
    where notification_id =
      '95300000-0000-4000-8000-000000000002'::uuid
  ),
  'UNREAD',
  'Admin Two sees missing state as UNREAD'
);

select is(
  (
    select read_state_code
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000003'::uuid
    )
  ),
  'UNREAD',
  'Admin One archive state is not disclosed to Admin Two'
);

select is(
  api.notification_unread_count(),
  3::bigint,
  'Admin Two receives an independent unread badge count'
);

select is(
  (
    select count(*)
    from api.notification_list(
      p_read_state_code => 'ARCHIVED_FOR_USER',
      p_include_archived => true
    )
  ),
  0::bigint,
  'Admin Two has no archived notification state'
);

reset role;

-- Other organization trusted session
select set_config(
  'request.jwt.claim.sub',
  '94300000-0000-4000-8000-000000000003',
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
    '94300000-0000-4000-8000-000000000003',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 71-75: organization isolation in every public query
select is(
  (select count(*) from api.notification_list()),
  1::bigint,
  'other organization lists only its notification'
);

select is(
  api.notification_unread_count(),
  1::bigint,
  'other organization receives only its unread count'
);

select throws_ok(
  $sql$
    select *
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000001'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_NOT_FOUND',
  'other organization cannot read the default organization detail'
);

select is(
  (
    select title
    from api.notification_detail(
      '95300000-0000-4000-8000-000000000099'::uuid
    )
  ),
  'Other organization job failed',
  'other organization may read its own detail'
);

select is(
  (
    select count(*)
    from api.notification_event_history(
      '95300000-0000-4000-8000-000000000099'::uuid
    )
  ),
  1::bigint,
  'other organization may read only its own event history'
);

reset role;

select * from finish();
rollback;
