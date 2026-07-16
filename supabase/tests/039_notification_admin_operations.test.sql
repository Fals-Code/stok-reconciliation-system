begin;

create extension if not exists pgtap with schema extensions;

select plan(99);

-- Schema and function contracts.
select has_table(
  'notification'::name,
  'admin_operation_commands'::name
);

select has_column(
  'notification'::name,
  'admin_operation_commands'::name,
  'operation_code'::name,
  'admin operation audit stores operation code'
);

select has_column(
  'notification'::name,
  'admin_operation_commands'::name,
  'idempotency_key'::name,
  'admin operation audit stores idempotency key'
);

select has_column(
  'notification'::name,
  'admin_operation_commands'::name,
  'request_hash'::name,
  'admin operation audit stores request hash'
);

select has_column(
  'notification'::name,
  'admin_operation_commands'::name,
  'target_outbox_event_id'::name,
  'admin operation audit links target outbox event'
);

select has_column(
  'notification'::name,
  'admin_operation_commands'::name,
  'response_snapshot'::name,
  'admin operation audit stores response snapshot'
);

select has_column(
  'notification'::name,
  'outbox_events'::name,
  'retry_budget_started_at_attempt'::name,
  'outbox event stores retry budget attempt offset'
);

select has_function(
  'notification'::name,
  'retry_outbox_event'::name,
  array[
    'uuid',
    'uuid',
    'text',
    'text',
    'timestamp with time zone',
    'uuid',
    'uuid'
  ]::text[]
);

select has_function(
  'notification'::name,
  'request_manual_evaluation'::name,
  array[
    'uuid',
    'text',
    'text',
    'text',
    'timestamp with time zone',
    'uuid',
    'uuid'
  ]::text[]
);

select has_function(
  'notification'::name,
  'get_operations_summary'::name,
  array[
    'uuid',
    'uuid',
    'timestamp with time zone',
    'interval'
  ]::text[]
);

select has_function(
  'api'::name,
  'retry_notification_outbox_event'::name,
  array['uuid', 'text', 'text', 'uuid']::text[]
);

select has_function(
  'api'::name,
  'run_notification_evaluation'::name,
  array['text', 'text', 'text', 'uuid']::text[]
);

select has_function(
  'api'::name,
  'get_notification_operations_summary'::name,
  array[]::text[]
);

select function_returns(
  'notification',
  'retry_outbox_event',
  array[
    'uuid',
    'uuid',
    'text',
    'text',
    'timestamptz',
    'uuid',
    'uuid'
  ]::text[],
  'jsonb'
);

select function_returns(
  'notification',
  'request_manual_evaluation',
  array[
    'uuid',
    'text',
    'text',
    'text',
    'timestamptz',
    'uuid',
    'uuid'
  ]::text[],
  'jsonb'
);

select function_returns(
  'notification',
  'get_operations_summary',
  array[
    'uuid',
    'uuid',
    'timestamptz',
    'interval'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'retry_notification_outbox_event',
  array['uuid', 'text', 'text', 'uuid']::text[],
  'jsonb'
);

select function_returns(
  'api',
  'run_notification_evaluation',
  array['text', 'text', 'text', 'uuid']::text[],
  'jsonb'
);

select function_returns(
  'api',
  'get_notification_operations_summary',
  array[]::text[],
  'jsonb'
);

-- Trusted internals and authenticated wrappers.
select ok(
  has_function_privilege(
    'service_role',
    'notification.retry_outbox_event(uuid,uuid,text,text,timestamptz,uuid,uuid)',
    'EXECUTE'
  ),
  'service role may invoke trusted outbox retry'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.retry_outbox_event(uuid,uuid,text,text,timestamptz,uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated clients cannot provide trusted retry identity'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.request_manual_evaluation(uuid,text,text,text,timestamptz,uuid,uuid)',
    'EXECUTE'
  ),
  'service role may invoke trusted evaluation request'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.request_manual_evaluation(uuid,text,text,text,timestamptz,uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated clients cannot provide trusted evaluation identity'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.get_operations_summary(uuid,uuid,timestamptz,interval)',
    'EXECUTE'
  ),
  'service role may obtain trusted operations summary'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.get_operations_summary(uuid,uuid,timestamptz,interval)',
    'EXECUTE'
  ),
  'authenticated clients cannot select another summary identity'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.retry_notification_outbox_event(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated Admin may request an outbox retry'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.retry_notification_outbox_event(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot request an outbox retry'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.run_notification_evaluation(text,text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated Admin may request manual evaluation'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.run_notification_evaluation(text,text,text,uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot request manual evaluation'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.get_notification_operations_summary()',
    'EXECUTE'
  ),
  'authenticated Admin may read operations summary'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.get_notification_operations_summary()',
    'EXECUTE'
  ),
  'anonymous clients cannot read operations summary'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'notification.admin_operation_commands',
    'SELECT'
  ),
  'authenticated clients cannot read command audit directly'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'notification.admin_operation_commands',
    'INSERT'
  ),
  'authenticated clients cannot insert command audit directly'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'api.retry_notification_outbox_event(uuid,text,text,uuid)'::regprocedure
  ),
  'retry API is security definer'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'api.run_notification_evaluation(text,text,text,uuid)'::regprocedure
  ),
  'manual evaluation API is security definer'
);

select ok(
  position(
    'enqueue_outbox_event'
    in lower(
      pg_get_functiondef(
        'notification.request_manual_evaluation(uuid,text,text,text,timestamptz,uuid,uuid)'::regprocedure
      )
    )
  ) > 0,
  'manual evaluation command uses the outbox'
);

select ok(
  position(
    'evaluate_expiry'
    in lower(
      pg_get_functiondef(
        'notification.request_manual_evaluation(uuid,text,text,text,timestamptz,uuid,uuid)'::regprocedure
      )
    )
  ) = 0,
  'manual evaluation command does not invoke evaluator directly'
);

-- Isolated Admin identities.
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
  'f4200000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.operations.admin@glowlab.invalid',
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
  'f4200000-0000-4000-8000-000000000002'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.operations.other@glowlab.invalid',
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
  'f4200000-0000-4000-8000-000000000003'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.operations.inactive@glowlab.invalid',
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
  '00000000-0000-4000-8000-000000000013'::uuid,
  'PGTAP_NOTIFICATION_OPERATIONS',
  'pgTAP Notification Operations Organization',
  'Asia/Jakarta',
  true,
  clock_timestamp() - interval '1 day'
),
(
  '00000000-0000-4000-8000-000000000014'::uuid,
  'PGTAP_NOTIFICATION_OPERATIONS_OTHER',
  'pgTAP Notification Operations Other Organization',
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
  'f4200000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000013'::uuid,
  'pgTAP Notification Operations Admin',
  'PGTAP-NTF-OPS-ADMIN',
  'ADMIN',
  true,
  clock_timestamp() - interval '1 day',
  clock_timestamp() - interval '1 day'
),
(
  'f4200000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000014'::uuid,
  'pgTAP Notification Operations Other Admin',
  'PGTAP-NTF-OPS-OTHER',
  'ADMIN',
  true,
  clock_timestamp() - interval '1 day',
  clock_timestamp() - interval '1 day'
),
(
  'f4200000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000013'::uuid,
  'pgTAP Notification Operations Inactive Admin',
  'PGTAP-NTF-OPS-INACTIVE',
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
  'f5000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000013'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'admin-operations:retry-final',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000013'::uuid,
  clock_timestamp() - interval '2 hours',
  '{"fixture":"retry-final"}'::jsonb,
  encode(
    extensions.digest(
      '{"fixture":"retry-final"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  'f4700000-0000-4000-8000-000000000001'::uuid,
  'FAILED_FINAL',
  3,
  clock_timestamp() - interval '2 hours',
  null,
  null,
  clock_timestamp() - interval '30 minutes',
  'PGTAP_RETRY_FINAL',
  '{"fixture":"retry-final"}'::jsonb,
  null,
  'pgtap.notification_operations_fixture',
  clock_timestamp() - interval '2 hours'
),
(
  'f5000000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000013'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'admin-operations:completed',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000013'::uuid,
  clock_timestamp() - interval '2 hours',
  '{"fixture":"completed"}'::jsonb,
  encode(
    extensions.digest(
      '{"fixture":"completed"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  'f4700000-0000-4000-8000-000000000002'::uuid,
  'COMPLETED',
  1,
  clock_timestamp() - interval '2 hours',
  null,
  null,
  clock_timestamp() - interval '30 minutes',
  null,
  '{}'::jsonb,
  null,
  'pgtap.notification_operations_fixture',
  clock_timestamp() - interval '2 hours'
),
(
  'f5000000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000013'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'admin-operations:processing',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000013'::uuid,
  clock_timestamp() - interval '2 hours',
  '{"fixture":"processing"}'::jsonb,
  encode(
    extensions.digest(
      '{"fixture":"processing"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  'f4700000-0000-4000-8000-000000000003'::uuid,
  'PROCESSING',
  1,
  clock_timestamp() - interval '2 hours',
  clock_timestamp() - interval '10 minutes',
  'pgtap-stale-worker',
  null,
  null,
  '{}'::jsonb,
  null,
  'pgtap.notification_operations_fixture',
  clock_timestamp() - interval '2 hours'
),
(
  'f5000000-0000-4000-8000-000000000004'::uuid,
  '00000000-0000-4000-8000-000000000014'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'admin-operations:other-final',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000014'::uuid,
  clock_timestamp() - interval '2 hours',
  '{"fixture":"other-final"}'::jsonb,
  encode(
    extensions.digest(
      '{"fixture":"other-final"}'::jsonb::text,
      'sha256'
    ),
    'hex'
  ),
  'f4700000-0000-4000-8000-000000000004'::uuid,
  'FAILED_FINAL',
  2,
  clock_timestamp() - interval '2 hours',
  null,
  null,
  clock_timestamp() - interval '20 minutes',
  'PGTAP_OTHER_FINAL',
  '{"fixture":"other-final"}'::jsonb,
  null,
  'pgtap.notification_operations_fixture',
  clock_timestamp() - interval '2 hours'
);

create temporary table retry_event_before as
select
  event_row.id,
  event_row.event_type_code,
  event_row.source_event_key,
  event_row.entity_type_code,
  event_row.entity_id,
  event_row.occurred_at,
  event_row.payload,
  event_row.payload_hash,
  event_row.correlation_id,
  event_row.attempt_count,
  event_row.last_error_code,
  event_row.last_error_detail
from notification.outbox_events event_row
where event_row.id = 'f5000000-0000-4000-8000-000000000001'::uuid;

-- Primary Admin JWT.
select set_config(
  'request.jwt.claim.sub',
  'f4200000-0000-4000-8000-000000000001',
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
    'f4200000-0000-4000-8000-000000000001',
    'role',
    'authenticated',
    'email',
    'pgtap.notification.operations.admin@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

select is(
  (
    api.retry_notification_outbox_event(
      'f5000000-0000-4000-8000-000000000001'::uuid,
      '  Investigated and safe to retry.  ',
      'retry-final-command-1',
      'f4800000-0000-4000-8000-000000000001'::uuid
    ) ->> 'action'
  ),
  'RETRY_REQUESTED',
  'Admin may request retry for FAILED_FINAL event'
);

reset role;

-- Retry persistence, source immutability, and audit.
select is(
  (
    select status_code
    from notification.outbox_events
    where id = 'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  'FAILED_RETRYABLE',
  'retry request returns event to claimable failed state'
);

select is(
  (
    select attempt_count
    from notification.outbox_events
    where id = 'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  3,
  'retry preserves prior attempt count'
);

select is(
  (
    select retry_budget_started_at_attempt
    from notification.outbox_events
    where id =
      'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  3,
  'retry opens a new budget without resetting total attempts'
);

select ok(
  (
    select completed_at is null
      and locked_at is null
      and locked_by is null
    from notification.outbox_events
    where id = 'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  'retry clears terminal time and worker lock'
);

select is(
  (
    select payload
    from notification.outbox_events
    where id = 'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select payload
    from retry_event_before
  ),
  'retry preserves source payload'
);

select is(
  (
    select payload_hash
    from notification.outbox_events
    where id = 'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select payload_hash
    from retry_event_before
  ),
  'retry preserves source payload hash'
);

select is(
  (
    select source_event_key
    from notification.outbox_events
    where id = 'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select source_event_key
    from retry_event_before
  ),
  'retry preserves source event key'
);

select is(
  (
    select correlation_id
    from notification.outbox_events
    where id = 'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select correlation_id
    from retry_event_before
  ),
  'retry preserves source correlation ID'
);

select is(
  (
    select last_error_code
    from notification.outbox_events
    where id = 'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  'PGTAP_RETRY_FINAL',
  'retry preserves prior failure code'
);

select is(
  (
    select count(*)
    from notification.admin_operation_commands
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and operation_code = 'RETRY_OUTBOX_EVENT'
  ),
  1::bigint,
  'retry creates one append-only command audit row'
);

select is(
  (
    select reason
    from notification.admin_operation_commands
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and operation_code = 'RETRY_OUTBOX_EVENT'
  ),
  'Investigated and safe to retry.',
  'retry audit stores trimmed reason'
);

select is(
  (
    select actor_user_id
    from notification.admin_operation_commands
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and operation_code = 'RETRY_OUTBOX_EVENT'
  ),
  'f4200000-0000-4000-8000-000000000001'::uuid,
  'retry audit stores trusted session actor'
);

select is(
  (
    select length(request_hash)
    from notification.admin_operation_commands
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and operation_code = 'RETRY_OUTBOX_EVENT'
  ),
  64,
  'retry audit stores SHA-256 request hash'
);

-- Retry replay and conflict.
select set_config(
  'request.jwt.claim.sub',
  'f4200000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select is(
  (
    api.retry_notification_outbox_event(
      'f5000000-0000-4000-8000-000000000001'::uuid,
      'Investigated and safe to retry.',
      'retry-final-command-1',
      'f4800000-0000-4000-8000-000000000099'::uuid
    ) ->> 'action'
  ),
  'REPLAYED',
  'same retry command replays idempotently'
);

select throws_ok(
  format(
    'select api.retry_notification_outbox_event(%L::uuid,%L,%L,%L::uuid)',
    'f5000000-0000-4000-8000-000000000001'::uuid,
    'Different retry reason.',
    'retry-final-command-1',
    'f4800000-0000-4000-8000-000000000002'
  ),
  'P0001',
  'NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_CONFLICT',
  'same retry key with changed request is rejected'
);

select throws_ok(
  format(
    'select api.retry_notification_outbox_event(%L::uuid,%L,%L,%L::uuid)',
    'f5000000-0000-4000-8000-000000000002'::uuid,
    'Completed events must not be retried.',
    'retry-completed-command',
    'f4800000-0000-4000-8000-000000000003'
  ),
  'P0001',
  'OUTBOX_RETRY_STATUS_INVALID',
  'COMPLETED event cannot be retried'
);

select throws_ok(
  format(
    'select api.retry_notification_outbox_event(%L::uuid,%L,%L,%L::uuid)',
    'f5000000-0000-4000-8000-000000000003'::uuid,
    'Processing events must remain worker-owned.',
    'retry-processing-command',
    'f4800000-0000-4000-8000-000000000004'
  ),
  'P0001',
  'OUTBOX_RETRY_STATUS_INVALID',
  'PROCESSING event cannot be retried'
);

select throws_ok(
  format(
    'select api.retry_notification_outbox_event(%L::uuid,%L,%L,%L::uuid)',
    'f5000000-0000-4000-8000-000000000004'::uuid,
    'Cross organization retry must fail.',
    'retry-cross-org-command',
    'f4800000-0000-4000-8000-000000000005'
  ),
  'P0001',
  'OUTBOX_EVENT_NOT_FOUND',
  'Admin cannot retry another organization event'
);

select throws_ok(
  format(
    'select api.retry_notification_outbox_event(%L::uuid,%L,%L,%L::uuid)',
    'f5000000-0000-4000-8000-000000000001'::uuid,
    '   ',
    'retry-blank-reason',
    'f4800000-0000-4000-8000-000000000006'
  ),
  'P0001',
  'OUTBOX_RETRY_REASON_REQUIRED',
  'retry requires a reason'
);

reset role;

select is(
  (
    select count(*)
    from notification.admin_operation_commands
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and operation_code = 'RETRY_OUTBOX_EVENT'
  ),
  1::bigint,
  'retry replay and rejected requests do not duplicate audit'
);

-- Four manual evaluation families create PENDING outbox work.
select set_config(
  'request.jwt.claim.sub',
  'f4200000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select is(
  (
    api.run_notification_evaluation(
      'EXPIRY',
      'Refresh expiry risk projection.',
      'manual-evaluation-expiry',
      'f4900000-0000-4000-8000-000000000001'::uuid
    ) ->> 'action'
  ),
  'EVALUATION_REQUESTED',
  'Admin may request expiry evaluation'
);

select is(
  (
    api.run_notification_evaluation(
      'RETURN_INSPECTION',
      'Refresh pending return inspection alerts.',
      'manual-evaluation-return',
      'f4900000-0000-4000-8000-000000000002'::uuid
    ) ->> 'action'
  ),
  'EVALUATION_REQUESTED',
  'Admin may request return inspection evaluation'
);

select is(
  (
    api.run_notification_evaluation(
      'RECONCILIATION',
      'Refresh reconciliation notification family.',
      'manual-evaluation-reconciliation',
      'f4900000-0000-4000-8000-000000000003'::uuid
    ) ->> 'action'
  ),
  'EVALUATION_REQUESTED',
  'Admin may request reconciliation evaluation'
);

select is(
  (
    api.run_notification_evaluation(
      'STOCKTAKE',
      'Refresh stocktake notification family.',
      'manual-evaluation-stocktake',
      'f4900000-0000-4000-8000-000000000004'::uuid
    ) ->> 'action'
  ),
  'EVALUATION_REQUESTED',
  'Admin may request stocktake evaluation'
);

reset role;

select is(
  (
    select count(*)
    from notification.outbox_events
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and source_event_key like 'admin-evaluation:%'
  ),
  4::bigint,
  'manual requests create four outbox events'
);

select is(
  (
    select count(*)
    from notification.outbox_events
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and source_event_key like 'admin-evaluation:%'
      and status_code = 'PENDING'
  ),
  4::bigint,
  'manual evaluation events remain PENDING'
);

select is(
  (
    select array_agg(event_type_code order by event_type_code)
    from notification.outbox_events
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and source_event_key like 'admin-evaluation:%'
  ),
  array[
    'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
    'NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED',
    'NOTIFICATION_RETURN_INSPECTION_EVALUATION_REQUESTED',
    'NOTIFICATION_STOCKTAKE_EVALUATION_REQUESTED'
  ]::text[],
  'manual requests map to broad dispatcher event codes'
);

select is(
  (
    select count(*)
    from notification.outbox_events
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and source_event_key like 'admin-evaluation:%'
      and entity_type_code = 'ORGANIZATION'
      and entity_id =
        '00000000-0000-4000-8000-000000000013'::uuid
      and actor_user_id =
        'f4200000-0000-4000-8000-000000000001'::uuid
      and process_name is null
  ),
  4::bigint,
  'manual events use organization scope and trusted Admin actor'
);

select is(
  (
    select count(*)
    from notification.admin_operation_commands
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and operation_code = 'REQUEST_EVALUATION'
  ),
  4::bigint,
  'manual requests create four command audit rows'
);

select is(
  (
    select array_agg(
      evaluation_family_code
      order by evaluation_family_code
    )
    from notification.admin_operation_commands
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and operation_code = 'REQUEST_EVALUATION'
  ),
  array[
    'EXPIRY',
    'RECONCILIATION',
    'RETURN_INSPECTION',
    'STOCKTAKE'
  ]::text[],
  'manual command audit stores all evaluation families'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
  ),
  0::bigint,
  'manual request does not run evaluator in browser transaction'
);

-- Manual request replay, conflict, and validation.
select set_config(
  'request.jwt.claim.sub',
  'f4200000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select is(
  (
    api.run_notification_evaluation(
      'EXPIRY',
      'Refresh expiry risk projection.',
      'manual-evaluation-expiry',
      'f4900000-0000-4000-8000-000000000099'::uuid
    ) ->> 'action'
  ),
  'REPLAYED',
  'same manual evaluation request replays idempotently'
);

select throws_ok(
  $sql$
    select api.run_notification_evaluation(
      'STOCKTAKE',
      'Changed request with reused key.',
      'manual-evaluation-expiry',
      'f4900000-0000-4000-8000-000000000005'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_CONFLICT',
  'changed manual request with reused key is rejected'
);

select throws_ok(
  $sql$
    select api.run_notification_evaluation(
      'UNKNOWN',
      'Unknown family should fail.',
      'manual-evaluation-unknown',
      'f4900000-0000-4000-8000-000000000006'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_EVALUATION_FAMILY_INVALID',
  'unknown evaluation family is rejected'
);

select throws_ok(
  $sql$
    select api.run_notification_evaluation(
      'EXPIRY',
      '   ',
      'manual-evaluation-blank-reason',
      'f4900000-0000-4000-8000-000000000007'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_EVALUATION_REASON_REQUIRED',
  'manual evaluation requires reason'
);

select throws_ok(
  $sql$
    select api.run_notification_evaluation(
      'EXPIRY',
      'Blank idempotency key should fail.',
      '   ',
      'f4900000-0000-4000-8000-000000000008'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_REQUIRED',
  'manual evaluation requires idempotency key'
);

reset role;

select is(
  (
    select count(*)
    from notification.outbox_events
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
      and source_event_key like 'admin-evaluation:%'
  ),
  4::bigint,
  'replay and rejected requests do not duplicate outbox events'
);

select is(
  (
    select count(*)
    from notification.admin_operation_commands
    where organization_id =
      '00000000-0000-4000-8000-000000000013'::uuid
  ),
  5::bigint,
  'organization stores one retry and four evaluation audits'
);

-- Operations summary is scoped to current organization and user.
select set_config(
  'request.jwt.claim.sub',
  'f4200000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select is(
  api.get_notification_operations_summary()
    ->> 'organizationId',
  '00000000-0000-4000-8000-000000000013',
  'summary identifies current organization'
);

select is(
  api.get_notification_operations_summary()
    ->> 'userId',
  'f4200000-0000-4000-8000-000000000001',
  'summary identifies current Admin'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'outbox' ->> 'pendingCount'
  )::integer,
  4,
  'summary counts four pending manual evaluations'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'outbox' ->> 'processingCount'
  )::integer,
  1,
  'summary counts one processing event'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'outbox' ->> 'failedRetryableCount'
  )::integer,
  1,
  'summary counts retried event as failed-retryable'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'outbox' ->> 'failedFinalCount'
  )::integer,
  0,
  'summary excludes another organization final failure'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'outbox' ->> 'completedCount'
  )::integer,
  1,
  'summary counts one completed event'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'outbox' ->> 'actionableCount'
  )::integer,
  5,
  'summary counts pending and retryable work as actionable'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'outbox' ->> 'staleProcessingCount'
  )::integer,
  1,
  'summary identifies stale processing lock'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'adminOperations'
      ->> 'retryRequestsLast24Hours'
  )::integer,
  1,
  'summary counts recent retry request'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'adminOperations'
      ->> 'evaluationRequestsLast24Hours'
  )::integer,
  4,
  'summary counts recent evaluation requests'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'ruleRuns' ->> 'failedLast24Hours'
  )::integer,
  0,
  'summary reports no evaluator failures before processing'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'notifications' ->> 'unreadCount'
  )::integer,
  0,
  'summary reports no fabricated unread notifications'
);

reset role;

-- Other organization sees only its own final failure.
select set_config(
  'request.jwt.claim.sub',
  'f4200000-0000-4000-8000-000000000002',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'f4200000-0000-4000-8000-000000000002',
    'role',
    'authenticated'
  )::text,
  true
);
set local role authenticated;

select is(
  (
    api.get_notification_operations_summary()
      -> 'outbox' ->> 'failedFinalCount'
  )::integer,
  1,
  'other organization summary sees its own final failure'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'outbox' ->> 'pendingCount'
  )::integer,
  0,
  'other organization summary does not see primary pending work'
);

select is(
  (
    api.get_notification_operations_summary()
      -> 'adminOperations'
      ->> 'evaluationRequestsLast24Hours'
  )::integer,
  0,
  'other organization summary does not see primary commands'
);

reset role;

-- Inactive Admin cannot use operational API.
select set_config(
  'request.jwt.claim.sub',
  'f4200000-0000-4000-8000-000000000003',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'f4200000-0000-4000-8000-000000000003',
    'role',
    'authenticated'
  )::text,
  true
);
set local role authenticated;

select throws_ok(
  $sql$
    select api.get_notification_operations_summary()
  $sql$,
  '42501',
  'ADMIN_ACCESS_REQUIRED',
  'inactive Admin cannot read operations summary'
);

select throws_ok(
  $sql$
    select api.run_notification_evaluation(
      'EXPIRY',
      'Inactive Admin request.',
      'inactive-admin-evaluation',
      'f4900000-0000-4000-8000-000000000009'::uuid
    )
  $sql$,
  '42501',
  'ADMIN_ACCESS_REQUIRED',
  'inactive Admin cannot request evaluation'
);

reset role;

-- Invalid internal summary threshold is rejected.
select throws_ok(
  $sql$
    select notification.get_operations_summary(
      '00000000-0000-4000-8000-000000000013'::uuid,
      'f4200000-0000-4000-8000-000000000001'::uuid,
      clock_timestamp(),
      interval '0 seconds'
    )
  $sql$,
  'P0001',
  'OUTBOX_LOCK_TIMEOUT_INVALID',
  'summary rejects invalid stale-lock timeout'
);

-- Admin retry opens a new worker budget while preserving total history.
create temporary table claimed_after_admin_retry as
select *
from notification.claim_outbox_events(
  'pgtap-admin-retry-worker',
  100,
  clock_timestamp() + interval '1 minute',
  3
);

select is(
  (
    select count(*)
    from claimed_after_admin_retry
    where id =
      'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'retried event is claimable despite reaching old attempt ceiling'
);

select is(
  (
    select attempt_count
    from claimed_after_admin_retry
    where id =
      'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  4,
  'new worker claim increments total attempt history'
);

select is(
  (
    select retry_budget_started_at_attempt
    from claimed_after_admin_retry
    where id =
      'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  3,
  'new worker claim preserves retry budget origin'
);

select is(
  (
    select
      attempt_count
      - retry_budget_started_at_attempt
    from claimed_after_admin_retry
    where id =
      'f5000000-0000-4000-8000-000000000001'::uuid
  ),
  1,
  'new retry cycle records its first attempt independently'
);

select * from finish();
rollback;
