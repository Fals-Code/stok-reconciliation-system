begin;

create extension if not exists pgtap with schema extensions;

select plan(97);

-- 1-24: function contracts, trusted execution, and locking implementation
select has_function(
  'notification'::name,
  'enqueue_outbox_event'::name,
  array[
    'uuid',
    'text',
    'text',
    'text',
    'uuid',
    'timestamp with time zone',
    'jsonb',
    'uuid',
    'uuid',
    'text'
  ]::text[]
);

select has_function(
  'notification'::name,
  'recover_stale_outbox_events'::name,
  array[
    'timestamp with time zone',
    'interval',
    'integer'
  ]::text[]
);

select has_function(
  'notification'::name,
  'claim_outbox_events'::name,
  array[
    'text',
    'integer',
    'timestamp with time zone',
    'integer'
  ]::text[]
);

select has_function(
  'notification'::name,
  'complete_outbox_event'::name,
  array[
    'uuid',
    'text',
    'timestamp with time zone'
  ]::text[]
);

select has_function(
  'notification'::name,
  'fail_outbox_event'::name,
  array[
    'uuid',
    'text',
    'text',
    'jsonb',
    'timestamp with time zone',
    'boolean',
    'integer',
    'integer',
    'integer'
  ]::text[]
);

select has_function(
  'notification'::name,
  'process_outbox'::name,
  array[
    'text',
    'integer',
    'timestamp with time zone',
    'interval',
    'integer',
    'integer',
    'integer',
    'text'
  ]::text[]
);

select function_returns(
  'notification',
  'enqueue_outbox_event',
  array[
    'uuid',
    'text',
    'text',
    'text',
    'uuid',
    'timestamptz',
    'jsonb',
    'uuid',
    'uuid',
    'text'
  ]::text[],
  'jsonb'
);

select function_returns(
  'notification',
  'recover_stale_outbox_events',
  array[
    'timestamptz',
    'interval',
    'integer'
  ]::text[],
  'jsonb'
);

select function_returns(
  'notification',
  'complete_outbox_event',
  array[
    'uuid',
    'text',
    'timestamptz'
  ]::text[],
  'jsonb'
);

select function_returns(
  'notification',
  'fail_outbox_event',
  array[
    'uuid',
    'text',
    'text',
    'jsonb',
    'timestamptz',
    'boolean',
    'integer',
    'integer',
    'integer'
  ]::text[],
  'jsonb'
);

select function_returns(
  'notification',
  'process_outbox',
  array[
    'text',
    'integer',
    'timestamptz',
    'interval',
    'integer',
    'integer',
    'integer',
    'text'
  ]::text[],
  'jsonb'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.enqueue_outbox_event(uuid,text,text,text,uuid,timestamptz,jsonb,uuid,uuid,text)',
    'EXECUTE'
  ),
  'service role may enqueue outbox events'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.enqueue_outbox_event(uuid,text,text,text,uuid,timestamptz,jsonb,uuid,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot enqueue trusted outbox facts'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.claim_outbox_events(text,integer,timestamptz,integer)',
    'EXECUTE'
  ),
  'service role may claim outbox events'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.claim_outbox_events(text,integer,timestamptz,integer)',
    'EXECUTE'
  ),
  'authenticated clients cannot claim outbox events'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.complete_outbox_event(uuid,text,timestamptz)',
    'EXECUTE'
  ),
  'service role may complete claimed outbox events'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.complete_outbox_event(uuid,text,timestamptz)',
    'EXECUTE'
  ),
  'authenticated clients cannot complete outbox events'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.fail_outbox_event(uuid,text,text,jsonb,timestamptz,boolean,integer,integer,integer)',
    'EXECUTE'
  ),
  'service role may transition failed outbox events'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.fail_outbox_event(uuid,text,text,jsonb,timestamptz,boolean,integer,integer,integer)',
    'EXECUTE'
  ),
  'authenticated clients cannot transition failed outbox events'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.process_outbox(text,integer,timestamptz,interval,integer,integer,integer,text)',
    'EXECUTE'
  ),
  'service role may run the outbox processor'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.process_outbox(text,integer,timestamptz,interval,integer,integer,integer,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot run the outbox processor'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    join pg_namespace namespace
      on namespace.oid = process.pronamespace
    where namespace.nspname = 'notification'
      and process.proname = 'process_outbox'
      and pg_get_function_identity_arguments(process.oid) =
        'p_worker_id text, p_limit integer, p_now timestamp with time zone, p_lock_timeout interval, p_max_attempts integer, p_base_retry_seconds integer, p_max_retry_seconds integer, p_process_name text'
  ),
  'outbox processor is security definer'
);

select ok(
  position(
    'for update skip locked'
    in lower(
      pg_get_functiondef(
        'notification.claim_outbox_events(text,integer,timestamptz,integer)'::regprocedure
      )
    )
  ) > 0,
  'outbox claim implementation uses FOR UPDATE SKIP LOCKED'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'notification.outbox_events',
    'INSERT'
  ),
  'authenticated clients still have no direct outbox insert privilege'
);

-- Isolated organization, Admin, and one expiry-tracked batch.
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
values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94500000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.outbox.admin@glowlab.invalid',
  '2026-07-16 09:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
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
values (
  '00000000-0000-4000-8000-000000000009'::uuid,
  'PGTAP_OUTBOX_PROCESSOR',
  'pgTAP Outbox Processor Organization',
  'Asia/Jakarta',
  true,
  '2026-07-16 09:00:00+07'::timestamptz
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
values (
  '94500000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000009'::uuid,
  'pgTAP Outbox Admin',
  'PGTAP-OUTBOX-ADMIN',
  'ADMIN',
  true,
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz
);

insert into app.settings (
  id,
  organization_id,
  key,
  value,
  version,
  effective_from,
  effective_to,
  created_at
)
values (
  '60900000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000009'::uuid,
  'expiry.warning_days',
  '[90,60,30,0]'::jsonb,
  1,
  '2026-07-16 00:00:00+07'::timestamptz,
  null,
  '2026-07-16 09:00:00+07'::timestamptz
);

insert into catalog.products (
  id,
  organization_id,
  sku,
  name,
  unit_code,
  is_batch_tracked,
  is_expiry_tracked,
  is_active,
  created_at,
  updated_at,
  row_version
)
values (
  '30900000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000009'::uuid,
  'PGTAP-OUTBOX-SKU',
  'pgTAP Outbox Product',
  'UNIT',
  true,
  true,
  true,
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
);

insert into catalog.product_batches (
  id,
  organization_id,
  product_id,
  batch_code,
  manufactured_date,
  expiry_date,
  received_first_at,
  status_code,
  created_at,
  updated_at,
  row_version
)
values (
  '40900000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000009'::uuid,
  '30900000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-OUTBOX-D30',
  '2026-01-01'::date,
  '2026-07-25'::date,
  '2026-07-01 08:00:00+07'::timestamptz,
  'ACTIVE',
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
);

insert into inventory.stock_batch_balances (
  organization_id,
  batch_id,
  product_id,
  sellable_qty,
  quarantine_qty,
  damaged_qty,
  last_ledger_seq,
  updated_at,
  version
)
values (
  '00000000-0000-4000-8000-000000000009'::uuid,
  '40900000-0000-4000-8000-000000000001'::uuid,
  '30900000-0000-4000-8000-000000000001'::uuid,
  7,
  0,
  0,
  0,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
);

create temporary table outbox_domain_counts_before as
select
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
  )::bigint as transaction_count,
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
  )::bigint as ledger_count,
  (
    select count(*)
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
  )::bigint as product_position_count;

create temporary table enqueue_success as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000009'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'expiry-evaluation:2026-07-16',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000009'::uuid,
  '2026-07-16 10:00:00+07'::timestamptz,
  '{"reason":"DAILY_SCHEDULE"}'::jsonb,
  '97900000-0000-4000-8000-000000000001'::uuid,
  null,
  'pgtap.outbox.producer'
) as result;

-- 25-36: idempotent enqueue and stable outbox fact
select is(
  (select result ->> 'action' from enqueue_success),
  'CREATED',
  'first source fact creates one pending outbox event'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_success
    )
  ),
  'PENDING',
  'new outbox event starts PENDING'
);

select is(
  (
    select attempt_count
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_success
    )
  ),
  0,
  'new outbox event starts with zero attempts'
);

select is(
  (
    select available_at
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_success
    )
  ),
  '2026-07-16 10:00:00+07'::timestamptz,
  'new outbox event is available from its occurrence time'
);

select is(
  (
    select length(payload_hash)
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_success
    )
  ),
  64,
  'outbox event stores a SHA-256 payload hash'
);

select ok(
  (
    select actor_user_id is null
      and process_name = 'pgtap.outbox.producer'
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_success
    )
  ),
  'outbox event stores exactly one trusted producer identity'
);

select is(
  (
    notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000009'::uuid,
      'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
      'expiry-evaluation:2026-07-16',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000009'::uuid,
      '2026-07-16 10:00:00+07'::timestamptz,
      '{"reason":"DAILY_SCHEDULE"}'::jsonb,
      '97900000-0000-4000-8000-000000000099'::uuid,
      null,
      'pgtap.outbox.producer'
    ) ->> 'action'
  ),
  'REPLAYED',
  'same source fact is replayed idempotently'
);

select is(
  (
    select count(*)
    from notification.outbox_events
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
      and event_type_code =
        'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED'
      and source_event_key = 'expiry-evaluation:2026-07-16'
  ),
  1::bigint,
  'idempotent enqueue does not duplicate the source event'
);

select throws_ok(
  $sql$
    select notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000009'::uuid,
      'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
      'expiry-evaluation:2026-07-16',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000009'::uuid,
      '2026-07-16 10:00:00+07'::timestamptz,
      '{"reason":"CHANGED_PAYLOAD"}'::jsonb,
      '97900000-0000-4000-8000-000000000001'::uuid,
      null,
      'pgtap.outbox.producer'
    )
  $sql$,
  'P0001',
  'OUTBOX_SOURCE_EVENT_CONFLICT',
  'same source key with different payload is rejected'
);

select throws_ok(
  $sql$
    select notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000009'::uuid,
      '   ',
      'invalid-type',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000009'::uuid,
      '2026-07-16 10:00:00+07'::timestamptz,
      '{}'::jsonb,
      '97900000-0000-4000-8000-000000000002'::uuid,
      null,
      'pgtap.outbox.producer'
    )
  $sql$,
  'P0001',
  'OUTBOX_EVENT_TYPE_INVALID',
  'enqueue rejects blank event type'
);

select throws_ok(
  $sql$
    select notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000009'::uuid,
      'TEST_EVENT',
      'invalid-payload',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000009'::uuid,
      '2026-07-16 10:00:00+07'::timestamptz,
      '[]'::jsonb,
      '97900000-0000-4000-8000-000000000003'::uuid,
      null,
      'pgtap.outbox.producer'
    )
  $sql$,
  'P0001',
  'OUTBOX_PAYLOAD_INVALID',
  'enqueue requires an object payload'
);

select throws_ok(
  $sql$
    select notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000009'::uuid,
      'TEST_EVENT',
      'invalid-actor',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000009'::uuid,
      '2026-07-16 10:00:00+07'::timestamptz,
      '{}'::jsonb,
      '97900000-0000-4000-8000-000000000004'::uuid,
      null,
      null
    )
  $sql$,
  'P0001',
  'NOTIFICATION_ACTOR_CONTEXT_INVALID',
  'enqueue requires exactly one producer identity'
);

create temporary table first_process as
select notification.process_outbox(
  'worker-success',
  10,
  '2026-07-16 10:05:00+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox'
) as result;

-- 37-53: successful dispatch, audit linkage, and source isolation
select is(
  (select (result ->> 'claimedCount')::integer from first_process),
  1,
  'processor claims the available event'
);

select is(
  (select (result ->> 'completedCount')::integer from first_process),
  1,
  'successful evaluator dispatch completes the event'
);

select is(
  (
    select (result ->> 'retryableFailureCount')::integer
    from first_process
  ),
  0,
  'successful processor run records no retryable failure'
);

select is(
  (
    select (result ->> 'finalFailureCount')::integer
    from first_process
  ),
  0,
  'successful processor run records no final failure'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_success
    )
  ),
  'COMPLETED',
  'processed outbox event reaches COMPLETED'
);

select is(
  (
    select attempt_count
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_success
    )
  ),
  1,
  'successful processing records one attempt'
);

select ok(
  (
    select locked_at is null
      and locked_by is null
      and completed_at =
        '2026-07-16 10:05:00+07'::timestamptz
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_success
    )
  ),
  'completion clears the worker lock and stores completion time'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
      and triggered_by_outbox_event_id = (
        select (result ->> 'outboxEventId')::uuid
        from enqueue_success
      )
  ),
  1::bigint,
  'processor links one evaluator run to the source outbox event'
);

select is(
  (
    select trigger_type_code
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_success
    )
  ),
  'OUTBOX',
  'linked evaluator run is classified as OUTBOX-triggered'
);

select is(
  (
    select status_code
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_success
    )
  ),
  'SUCCEEDED',
  'linked evaluator run preserves its terminal result'
);

select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
      and entity_id =
        '40900000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  1::bigint,
  'successful outbox dispatch creates one active expiry episode'
);

select is(
  (
    select stage_code
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
      and entity_id =
        '40900000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  'D30',
  'outbox-driven expiry evaluation uses source condition mapping'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
  ),
  (select transaction_count from outbox_domain_counts_before),
  'processor does not create a stock transaction'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
  ),
  (select ledger_count from outbox_domain_counts_before),
  'processor does not create a ledger entry'
);

select is(
  (
    select count(*)
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
  ),
  (select product_position_count from outbox_domain_counts_before),
  'processor does not rewrite product positions'
);

select is(
  (
    notification.process_outbox(
      'worker-empty',
      10,
      '2026-07-16 10:06:00+07'::timestamptz,
      interval '5 minutes',
      3,
      10,
      30,
      'pgtap.notification_outbox'
    ) ->> 'claimedCount'
  )::integer,
  0,
  'completed events are not claimed again'
);

select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
      and entity_id =
        '40900000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'empty replay does not duplicate the active notification'
);

-- Retryable evaluator failure, delayed retry, and successful recovery.
create temporary table enqueue_retry as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000009'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'expiry-evaluation:2026-07-17',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000009'::uuid,
  '2026-07-17 10:00:00+07'::timestamptz,
  '{"reason":"DAILY_SCHEDULE"}'::jsonb,
  '97900000-0000-4000-8000-000000000005'::uuid,
  null,
  'pgtap.outbox.producer'
) as result;

update notification.rules
set config = jsonb_set(
  config,
  '{thresholdDays}',
  '[90,30,60,0]'::jsonb,
  false
)
where organization_id =
    '00000000-0000-4000-8000-000000000009'::uuid
  and code = 'EXPIRY_RISK';

create temporary table failed_process as
select notification.process_outbox(
  'worker-retry-1',
  10,
  '2026-07-17 10:05:00+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox'
) as result;

-- 54-65: retry policy and failed-run auditability
select is(
  (select (result ->> 'claimedCount')::integer from failed_process),
  1,
  'processor claims the event whose evaluator will fail'
);

select is(
  (
    select (result ->> 'retryableFailureCount')::integer
    from failed_process
  ),
  1,
  'failed evaluator dispatch becomes retryable'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_retry
    )
  ),
  'FAILED_RETRYABLE',
  'failed evaluator leaves a retryable outbox event'
);

select is(
  (
    select attempt_count
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_retry
    )
  ),
  1,
  'failed evaluator records its first processing attempt'
);

select is(
  (
    select available_at
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_retry
    )
  ),
  '2026-07-17 10:05:10+07'::timestamptz,
  'first retry uses the configured ten-second delay'
);

select is(
  (
    select last_error_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_retry
    )
  ),
  'OUTBOX_EVALUATOR_FAILED',
  'retryable event exposes a stable evaluator failure code'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_retry
    )
      and status_code = 'FAILED'
  ),
  1::bigint,
  'failed evaluator run remains linked and auditable'
);

select is(
  (
    notification.process_outbox(
      'worker-too-early',
      10,
      '2026-07-17 10:05:09+07'::timestamptz,
      interval '5 minutes',
      3,
      10,
      30,
      'pgtap.notification_outbox'
    ) ->> 'claimedCount'
  )::integer,
  0,
  'retryable event is not claimed before available_at'
);

update notification.rules
set config = jsonb_set(
  config,
  '{thresholdDays}',
  '[90,60,30,0]'::jsonb,
  false
)
where organization_id =
    '00000000-0000-4000-8000-000000000009'::uuid
  and code = 'EXPIRY_RISK';

create temporary table retry_success as
select notification.process_outbox(
  'worker-retry-2',
  10,
  '2026-07-17 10:05:10+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox'
) as result;

select is(
  (select (result ->> 'completedCount')::integer from retry_success),
  1,
  'event completes after the source evaluator is repaired'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_retry
    )
  ),
  'COMPLETED',
  'successful retry transitions the event to COMPLETED'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_retry
    )
  ),
  2::bigint,
  'each outbox attempt receives a distinct auditable evaluator run'
);

select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
      and entity_id =
        '40900000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  1::bigint,
  'successful retry updates rather than duplicates the active episode'
);

-- Unsupported/poison event becomes visibly final without pointless retries.
create temporary table enqueue_unsupported as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000009'::uuid,
  'UNSUPPORTED_TEST_EVENT',
  'unsupported:2026-07-18',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000009'::uuid,
  '2026-07-18 10:00:00+07'::timestamptz,
  '{}'::jsonb,
  '97900000-0000-4000-8000-000000000006'::uuid,
  null,
  'pgtap.outbox.producer'
) as result;

create temporary table unsupported_process as
select notification.process_outbox(
  'worker-unsupported',
  10,
  '2026-07-18 10:01:00+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox'
) as result;

-- 66-71: poison/final failure visibility
select is(
  (
    select (result ->> 'finalFailureCount')::integer
    from unsupported_process
  ),
  1,
  'unsupported event is counted as a final failure'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_unsupported
    )
  ),
  'FAILED_FINAL',
  'unsupported event reaches FAILED_FINAL'
);

select is(
  (
    select last_error_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_unsupported
    )
  ),
  'OUTBOX_EVENT_TYPE_UNSUPPORTED',
  'unsupported event exposes a stable poison-event code'
);

select ok(
  (
    select completed_at is not null
      and locked_at is null
      and locked_by is null
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_unsupported
    )
  ),
  'final failure clears its lock and records terminal time'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_unsupported
    )
  ),
  0::bigint,
  'unsupported event does not fabricate an evaluator run'
);

select is(
  (
    notification.process_outbox(
      'worker-unsupported-replay',
      10,
      '2026-07-18 10:02:00+07'::timestamptz,
      interval '5 minutes',
      3,
      10,
      30,
      'pgtap.notification_outbox'
    ) ->> 'claimedCount'
  )::integer,
  0,
  'final poison event is never claimed automatically again'
);

-- Stale lock recovery below retry budget should requeue and process safely.
create temporary table enqueue_stale_retry as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000009'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'expiry-evaluation:2026-07-19',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000009'::uuid,
  '2026-07-19 10:00:00+07'::timestamptz,
  '{}'::jsonb,
  '97900000-0000-4000-8000-000000000007'::uuid,
  null,
  'pgtap.outbox.producer'
) as result;

update notification.outbox_events
set
  status_code = 'PROCESSING',
  attempt_count = 1,
  locked_at = '2026-07-19 10:00:00+07'::timestamptz,
  locked_by = 'dead-worker'
where id = (
  select (result ->> 'outboxEventId')::uuid
  from enqueue_stale_retry
);

create temporary table stale_retry_process as
select notification.process_outbox(
  'worker-stale-recovery',
  10,
  '2026-07-19 10:10:00+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox'
) as result;

-- 72-77: stale lock recovery and safe reprocessing
select is(
  (
    select (result -> 'recovery' ->> 'staleRetryableCount')::integer
    from stale_retry_process
  ),
  1,
  'stale processing lock below retry budget is recovered'
);

select is(
  (select (result ->> 'claimedCount')::integer from stale_retry_process),
  1,
  'recovered event is claimed in the same processor run'
);

select is(
  (select (result ->> 'completedCount')::integer from stale_retry_process),
  1,
  'recovered event completes successfully'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_stale_retry
    )
  ),
  'COMPLETED',
  'recovered stale event reaches COMPLETED'
);

select is(
  (
    select attempt_count
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_stale_retry
    )
  ),
  2,
  'stale recovery preserves the abandoned attempt and records a new one'
);

select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000009'::uuid
      and entity_id =
        '40900000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  1::bigint,
  'stale recovery still preserves one active notification episode'
);

-- Stale lock at the retry ceiling becomes terminal.
create temporary table enqueue_stale_final as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000009'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'expiry-evaluation:stale-final',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000009'::uuid,
  '2026-07-20 10:00:00+07'::timestamptz,
  '{}'::jsonb,
  '97900000-0000-4000-8000-000000000008'::uuid,
  null,
  'pgtap.outbox.producer'
) as result;

update notification.outbox_events
set
  status_code = 'PROCESSING',
  attempt_count = 3,
  locked_at = '2026-07-20 10:00:00+07'::timestamptz,
  locked_by = 'dead-worker-final'
where id = (
  select (result ->> 'outboxEventId')::uuid
  from enqueue_stale_final
);

create temporary table stale_final_process as
select notification.process_outbox(
  'worker-stale-final',
  10,
  '2026-07-20 10:10:00+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox'
) as result;

-- 78-82: stale exhausted work becomes visible final failure
select is(
  (
    select (result -> 'recovery' ->> 'staleFinalCount')::integer
    from stale_final_process
  ),
  1,
  'stale processing lock at retry ceiling is finalized'
);

select is(
  (select (result ->> 'claimedCount')::integer from stale_final_process),
  0,
  'stale exhausted event is not claimed again'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_stale_final
    )
  ),
  'FAILED_FINAL',
  'stale exhausted event reaches FAILED_FINAL'
);

select is(
  (
    select last_error_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_stale_final
    )
  ),
  'OUTBOX_STALE_LOCK_EXHAUSTED',
  'stale exhausted event records a specific recovery code'
);

select ok(
  (
    select completed_at =
        '2026-07-20 10:10:00+07'::timestamptz
      and locked_at is null
      and locked_by is null
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_stale_final
    )
  ),
  'stale finalization clears the dead worker lock'
);

-- Retryable row already at the ceiling is finalized before claiming.
create temporary table enqueue_exhausted_retry as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000009'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'expiry-evaluation:exhausted-retryable',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000009'::uuid,
  '2026-07-20 11:00:00+07'::timestamptz,
  '{}'::jsonb,
  '97900000-0000-4000-8000-000000000009'::uuid,
  null,
  'pgtap.outbox.producer'
) as result;

update notification.outbox_events
set
  status_code = 'FAILED_RETRYABLE',
  attempt_count = 3,
  available_at = '2026-07-20 11:01:00+07'::timestamptz,
  locked_at = null,
  locked_by = null,
  completed_at = null,
  last_error_code = 'TEST_RETRYABLE_FAILURE',
  last_error_detail = '{}'::jsonb
where id = (
  select (result ->> 'outboxEventId')::uuid
  from enqueue_exhausted_retry
);

create temporary table exhausted_retry_process as
select notification.process_outbox(
  'worker-exhausted-retry',
  10,
  '2026-07-20 11:02:00+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox'
) as result;

-- 83-85: exhausted retryable status cannot become an immortal queue item
select is(
  (
    select (
      result -> 'recovery' ->> 'exhaustedRetryableCount'
    )::integer
    from exhausted_retry_process
  ),
  1,
  'retryable row at attempt ceiling is finalized'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_exhausted_retry
    )
  ),
  'FAILED_FINAL',
  'exhausted retryable row reaches FAILED_FINAL'
);

select is(
  (
    select last_error_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_exhausted_retry
    )
  ),
  'OUTBOX_RETRY_EXHAUSTED',
  'exhausted retryable row stores a stable exhaustion code'
);

-- Worker ownership and direct retry transition semantics.
create temporary table enqueue_owned as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000009'::uuid,
  'MANUAL_TEST_EVENT',
  'worker-ownership-event',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000009'::uuid,
  '2026-07-21 10:00:00+07'::timestamptz,
  '{}'::jsonb,
  '97900000-0000-4000-8000-000000000010'::uuid,
  null,
  'pgtap.outbox.producer'
) as result;

create temporary table owned_claim as
select *
from notification.claim_outbox_events(
  'owner-worker',
  1,
  '2026-07-21 10:00:00+07'::timestamptz,
  3
);

-- 86-91: claim ownership and idempotent completion
select is(
  (select count(*) from owned_claim),
  1::bigint,
  'manual claim returns exactly one available event'
);

select is(
  (select locked_by from owned_claim),
  'owner-worker',
  'claimed row records its worker owner'
);

select throws_ok(
  $sql$
    select notification.complete_outbox_event(
      (
        select id
        from owned_claim
      ),
      'wrong-worker',
      '2026-07-21 10:01:00+07'::timestamptz
    )
  $sql$,
  'P0001',
  'OUTBOX_LOCK_OWNERSHIP_INVALID',
  'different worker cannot complete a claimed event'
);

select throws_ok(
  $sql$
    select notification.fail_outbox_event(
      (
        select id
        from owned_claim
      ),
      'wrong-worker',
      'TEST_FAILURE',
      '{}'::jsonb,
      '2026-07-21 10:01:00+07'::timestamptz,
      true,
      3,
      10,
      30
    )
  $sql$,
  'P0001',
  'OUTBOX_LOCK_OWNERSHIP_INVALID',
  'different worker cannot fail a claimed event'
);

select is(
  (
    notification.complete_outbox_event(
      (
        select id
        from owned_claim
      ),
      'owner-worker',
      '2026-07-21 10:01:00+07'::timestamptz
    ) ->> 'action'
  ),
  'COMPLETED',
  'owning worker may complete its claimed event'
);

select is(
  (
    notification.complete_outbox_event(
      (
        select id
        from owned_claim
      ),
      'another-worker',
      '2026-07-21 10:02:00+07'::timestamptz
    ) ->> 'action'
  ),
  'ALREADY_COMPLETED',
  'completion is idempotent after terminal success'
);

-- Direct retry lifecycle reaches final failure at the configured ceiling.
create temporary table enqueue_direct_retry as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000009'::uuid,
  'MANUAL_RETRY_TEST_EVENT',
  'direct-retry-event',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000009'::uuid,
  '2026-07-22 10:00:00+07'::timestamptz,
  '{}'::jsonb,
  '97900000-0000-4000-8000-000000000011'::uuid,
  null,
  'pgtap.outbox.producer'
) as result;

create temporary table direct_retry_claim_one as
select *
from notification.claim_outbox_events(
  'retry-owner-one',
  1,
  '2026-07-22 10:00:00+07'::timestamptz,
  2
);

create temporary table direct_retry_failure_one as
select notification.fail_outbox_event(
  (select id from direct_retry_claim_one),
  'retry-owner-one',
  'TEST_RETRYABLE',
  '{}'::jsonb,
  '2026-07-22 10:00:00+07'::timestamptz,
  true,
  2,
  10,
  30
) as result;

-- 92-97: bounded retry delay and terminal ceiling
select is(
  (
    select result ->> 'action'
    from direct_retry_failure_one
  ),
  'FAILED_RETRYABLE',
  'first direct failure is retryable below attempt ceiling'
);

select is(
  (
    select (result ->> 'retryDelaySeconds')::integer
    from direct_retry_failure_one
  ),
  10,
  'first direct failure uses base retry delay'
);

select is(
  (
    select available_at
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_direct_retry
    )
  ),
  '2026-07-22 10:00:10+07'::timestamptz,
  'retryable transition stores its next available time'
);

create temporary table direct_retry_claim_two as
select *
from notification.claim_outbox_events(
  'retry-owner-two',
  1,
  '2026-07-22 10:00:10+07'::timestamptz,
  2
);

create temporary table direct_retry_failure_two as
select notification.fail_outbox_event(
  (select id from direct_retry_claim_two),
  'retry-owner-two',
  'TEST_RETRYABLE',
  '{}'::jsonb,
  '2026-07-22 10:00:10+07'::timestamptz,
  true,
  2,
  10,
  30
) as result;

select is(
  (
    select result ->> 'action'
    from direct_retry_failure_two
  ),
  'FAILED_FINAL',
  'second direct failure reaches the configured attempt ceiling'
);

select is(
  (
    select attempt_count
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_direct_retry
    )
  ),
  2,
  'terminal retry event preserves total claim attempts'
);

select ok(
  (
    select completed_at =
        '2026-07-22 10:00:10+07'::timestamptz
      and locked_at is null
      and locked_by is null
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from enqueue_direct_retry
    )
  ),
  'terminal retry failure records completion and releases lock'
);

select * from finish();
rollback;
