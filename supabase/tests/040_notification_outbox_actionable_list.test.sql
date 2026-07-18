begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

select has_function(
  'api'::name,
  'notification_outbox_actionable_list'::name,
  array['text', 'integer']::text[]
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'api.notification_outbox_actionable_list(text,integer)'::regprocedure
  ),
  'outbox actionable list API is security definer'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.notification_outbox_actionable_list(text,integer)',
    'EXECUTE'
  ),
  'authenticated Admin may read actionable outbox list'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.notification_outbox_actionable_list(text,integer)',
    'EXECUTE'
  ),
  'anonymous clients cannot read actionable outbox list'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'notification.outbox_events',
    'SELECT'
  ),
  'authenticated clients still cannot select raw outbox rows'
);

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
  'fa200000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.outbox.list.admin@glowlab.invalid',
  clock_timestamp() - interval '1 day',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  clock_timestamp() - interval '1 day',
  clock_timestamp() - interval '1 day',
  false,
  false
),
(
  '00000000-0000-0000-0000-000000000000'::uuid,
  'fa200000-0000-4000-8000-000000000002'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.outbox.list.other@glowlab.invalid',
  clock_timestamp() - interval '1 day',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  clock_timestamp() - interval '1 day',
  clock_timestamp() - interval '1 day',
  false,
  false
),
(
  '00000000-0000-0000-0000-000000000000'::uuid,
  'fa200000-0000-4000-8000-000000000003'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.outbox.list.inactive@glowlab.invalid',
  clock_timestamp() - interval '1 day',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  clock_timestamp() - interval '1 day',
  clock_timestamp() - interval '1 day',
  false,
  false
);

insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active,
  created_at
)
values
(
  '00000000-0000-4000-8000-000000000015'::uuid,
  'PGTAP_NOTIFICATION_OUTBOX_LIST',
  'pgTAP Notification Outbox List Organization',
  'Asia/Jakarta',
  true,
  clock_timestamp() - interval '1 day'
),
(
  '00000000-0000-4000-8000-000000000016'::uuid,
  'PGTAP_NOTIFICATION_OUTBOX_LIST_OTHER',
  'pgTAP Notification Outbox List Other Organization',
  'Asia/Jakarta',
  true,
  clock_timestamp() - interval '1 day'
);

insert into app.user_profiles (
  user_id,
  organization_id,
  display_name,
  employee_code,
  role_code,
  is_active,
  created_at,
  updated_at
)
values
(
  'fa200000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000015'::uuid,
  'pgTAP Notification Outbox List Admin',
  'PGTAP-NTF-OUTBOX-LIST',
  'ADMIN',
  true,
  clock_timestamp() - interval '1 day',
  clock_timestamp() - interval '1 day'
),
(
  'fa200000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000016'::uuid,
  'pgTAP Notification Outbox List Other Admin',
  'PGTAP-NTF-OUTBOX-OTHER',
  'ADMIN',
  true,
  clock_timestamp() - interval '1 day',
  clock_timestamp() - interval '1 day'
),
(
  'fa200000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000015'::uuid,
  'pgTAP Notification Outbox List Inactive Admin',
  'PGTAP-NTF-OUTBOX-INACTIVE',
  'ADMIN',
  false,
  clock_timestamp() - interval '1 day',
  clock_timestamp() - interval '1 day'
);

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
values
(
  'fa500000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000015'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'outbox-list:failed-final',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000015'::uuid,
  clock_timestamp() - interval '4 hours',
  '{"fixture":"failed-final"}'::jsonb,
  encode(
    extensions.digest(
      '{"fixture":"failed-final"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  'fa700000-0000-4000-8000-000000000001'::uuid,
  'FAILED_FINAL',
  5,
  1,
  clock_timestamp() - interval '4 hours',
  null,
  null,
  clock_timestamp() - interval '1 hour',
  'PGTAP_FAILED_FINAL',
  '{"message":"terminal fixture"}'::jsonb,
  null,
  'pgtap.notification_outbox_list',
  clock_timestamp() - interval '4 hours'
),
(
  'fa500000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000015'::uuid,
  'NOTIFICATION_RETURN_INSPECTION_EVALUATION_REQUESTED',
  'outbox-list:failed-retryable',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000015'::uuid,
  clock_timestamp() - interval '3 hours',
  '{"fixture":"failed-retryable"}'::jsonb,
  encode(
    extensions.digest(
      '{"fixture":"failed-retryable"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  'fa700000-0000-4000-8000-000000000002'::uuid,
  'FAILED_RETRYABLE',
  3,
  1,
  clock_timestamp() - interval '20 minutes',
  null,
  null,
  null,
  'PGTAP_FAILED_RETRYABLE',
  '{"message":"retryable fixture"}'::jsonb,
  null,
  'pgtap.notification_outbox_list',
  clock_timestamp() - interval '3 hours'
),
(
  'fa500000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000015'::uuid,
  'NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED',
  'outbox-list:stale-processing',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000015'::uuid,
  clock_timestamp() - interval '2 hours',
  '{"fixture":"stale-processing"}'::jsonb,
  encode(
    extensions.digest(
      '{"fixture":"stale-processing"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  'fa700000-0000-4000-8000-000000000003'::uuid,
  'PROCESSING',
  2,
  0,
  clock_timestamp() - interval '2 hours',
  clock_timestamp() - interval '10 minutes',
  'pgtap-stale-worker',
  null,
  null,
  '{}'::jsonb,
  null,
  'pgtap.notification_outbox_list',
  clock_timestamp() - interval '2 hours'
),
(
  'fa500000-0000-4000-8000-000000000004'::uuid,
  '00000000-0000-4000-8000-000000000015'::uuid,
  'NOTIFICATION_STOCKTAKE_EVALUATION_REQUESTED',
  'outbox-list:pending',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000015'::uuid,
  clock_timestamp() - interval '1 hour',
  '{"fixture":"pending"}'::jsonb,
  encode(
    extensions.digest(
      '{"fixture":"pending"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  'fa700000-0000-4000-8000-000000000004'::uuid,
  'PENDING',
  0,
  0,
  clock_timestamp() - interval '1 hour',
  null,
  null,
  null,
  null,
  '{}'::jsonb,
  null,
  'pgtap.notification_outbox_list',
  clock_timestamp() - interval '1 hour'
),
(
  'fa500000-0000-4000-8000-000000000005'::uuid,
  '00000000-0000-4000-8000-000000000015'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'outbox-list:completed',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000015'::uuid,
  clock_timestamp() - interval '5 hours',
  '{"fixture":"completed"}'::jsonb,
  encode(
    extensions.digest(
      '{"fixture":"completed"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  'fa700000-0000-4000-8000-000000000005'::uuid,
  'COMPLETED',
  1,
  0,
  clock_timestamp() - interval '5 hours',
  null,
  null,
  clock_timestamp() - interval '4 hours',
  null,
  '{}'::jsonb,
  null,
  'pgtap.notification_outbox_list',
  clock_timestamp() - interval '5 hours'
),
(
  'fa500000-0000-4000-8000-000000000006'::uuid,
  '00000000-0000-4000-8000-000000000016'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'outbox-list:other-final',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000016'::uuid,
  clock_timestamp() - interval '2 hours',
  '{"fixture":"other-final"}'::jsonb,
  encode(
    extensions.digest(
      '{"fixture":"other-final"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  'fa700000-0000-4000-8000-000000000006'::uuid,
  'FAILED_FINAL',
  2,
  0,
  clock_timestamp() - interval '2 hours',
  null,
  null,
  clock_timestamp() - interval '1 hour',
  'PGTAP_OTHER_FINAL',
  '{"message":"other organization"}'::jsonb,
  null,
  'pgtap.notification_outbox_list',
  clock_timestamp() - interval '2 hours'
);

select set_config(
  'request.jwt.claim.sub',
  'fa200000-0000-4000-8000-000000000001',
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
    'fa200000-0000-4000-8000-000000000001',
    'role',
    'authenticated',
    'email',
    'pgtap.notification.outbox.list.admin@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

select is(
  (
    select count(*)
    from api.notification_outbox_actionable_list(null, 50)
  ),
  4::bigint,
  'list includes only actionable rows from current organization'
);

select is(
  (
    select count(*)
    from api.notification_outbox_actionable_list(
      'FAILED_FINAL',
      50
    )
  ),
  1::bigint,
  'status filter narrows actionable rows'
);

select is(
  (
    select outbox_event_id
    from api.notification_outbox_actionable_list(null, 1)
  ),
  'fa500000-0000-4000-8000-000000000001'::uuid,
  'failed final event is ordered first'
);

select is(
  (
    select count(*)
    from api.notification_outbox_actionable_list(null, 50)
    where can_retry
  ),
  2::bigint,
  'only failed states are retryable'
);

select is(
  (
    select count(*)
    from api.notification_outbox_actionable_list(null, 50)
    where is_stale_processing
  ),
  1::bigint,
  'stale processing lock is identified'
);

select is(
  (
    select retry_cycle_attempt_count
    from api.notification_outbox_actionable_list(
      'FAILED_FINAL',
      50
    )
  ),
  4,
  'retry cycle attempt count uses retry budget offset'
);

select is(
  (
    select last_error_code
    from api.notification_outbox_actionable_list(
      'FAILED_RETRYABLE',
      50
    )
  ),
  'PGTAP_FAILED_RETRYABLE',
  'safe failure metadata is exposed'
);

select is(
  (
    select count(*)
    from api.notification_outbox_actionable_list(null, 50)
    where outbox_event_id =
      'fa500000-0000-4000-8000-000000000006'::uuid
  ),
  0::bigint,
  'rows from another organization are not exposed'
);

select throws_ok(
  $sql$
    select *
    from api.notification_outbox_actionable_list(
      'COMPLETED',
      50
    )
  $sql$,
  'P0001',
  'NOTIFICATION_OUTBOX_STATUS_FILTER_INVALID',
  'completed status is outside actionable list contract'
);

select throws_ok(
  $sql$
    select *
    from api.notification_outbox_actionable_list(
      null,
      0
    )
  $sql$,
  'P0001',
  'NOTIFICATION_OUTBOX_LIST_LIMIT_INVALID',
  'limit below one is rejected'
);

reset role;

select set_config(
  'request.jwt.claim.sub',
  'fa200000-0000-4000-8000-000000000003',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'fa200000-0000-4000-8000-000000000003',
    'role',
    'authenticated',
    'email',
    'pgtap.notification.outbox.list.inactive@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

select throws_ok(
  $sql$
    select *
    from api.notification_outbox_actionable_list(
      null,
      50
    )
  $sql$,
  '42501',
  'ADMIN_ACCESS_REQUIRED',
  'inactive Admin cannot read actionable outbox list'
);

reset role;

select * from finish();

rollback;
