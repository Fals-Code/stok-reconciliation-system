begin;

create extension if not exists pgtap with schema extensions;

select plan(86);

-- 1-10: function contracts and privilege boundaries
select has_function(
  'notification'::name,
  'ensure_expiry_rule'::name,
  array['uuid', 'timestamp with time zone']::text[]
);

select has_function(
  'notification'::name,
  'evaluate_expiry'::name,
  array[
    'uuid',
    'text',
    'timestamp with time zone',
    'text',
    'uuid',
    'text'
  ]::text[]
);

select function_returns(
  'notification',
  'ensure_expiry_rule',
  array['uuid', 'timestamptz']::text[],
  'uuid'
);

select function_returns(
  'notification',
  'evaluate_expiry',
  array[
    'uuid',
    'text',
    'timestamptz',
    'text',
    'uuid',
    'text'
  ]::text[],
  'jsonb'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.ensure_expiry_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'service role may provision the default expiry rule'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.ensure_expiry_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'authenticated clients cannot provision notification rules'
);

select ok(
  not has_function_privilege(
    'anon',
    'notification.ensure_expiry_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'anonymous clients cannot provision notification rules'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.evaluate_expiry(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'service role may run the expiry evaluator'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.evaluate_expiry(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot invoke the trusted evaluator directly'
);

select ok(
  not has_function_privilege(
    'anon',
    'notification.evaluate_expiry(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'anonymous clients cannot invoke the expiry evaluator'
);

-- Isolated organization and one active Admin account
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
  '94400000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.expiry.admin@glowlab.invalid',
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
  '00000000-0000-4000-8000-000000000008'::uuid,
  'PGTAP_EXPIRY_EVALUATOR',
  'pgTAP Expiry Evaluator Organization',
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
  '94400000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
  'pgTAP Expiry Admin',
  'PGTAP-EXPIRY-ADMIN',
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
  '60800000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
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
  '30800000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
  'PGTAP-EXPIRY-SKU',
  'pgTAP Expiry Product',
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
values
(
  '40800000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-D90',
  '2026-01-01'::date,
  '2026-07-16'::date + 75,
  '2026-07-01 08:00:00+07'::timestamptz,
  'ACTIVE',
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '40800000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-D60',
  '2026-01-01'::date,
  '2026-07-16'::date + 45,
  '2026-07-01 08:00:00+07'::timestamptz,
  'ACTIVE',
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '40800000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-D30',
  '2026-01-01'::date,
  '2026-07-16'::date + 15,
  '2026-07-01 08:00:00+07'::timestamptz,
  'ACTIVE',
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '40800000-0000-4000-8000-000000000004'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-SAME-DAY',
  '2026-01-01'::date,
  '2026-07-16'::date,
  '2026-07-01 08:00:00+07'::timestamptz,
  'ACTIVE',
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '40800000-0000-4000-8000-000000000005'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-EXPIRED',
  '2026-01-01'::date,
  '2026-07-16'::date - 1,
  '2026-07-01 08:00:00+07'::timestamptz,
  'ACTIVE',
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '40800000-0000-4000-8000-000000000006'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-FUTURE',
  '2026-01-01'::date,
  '2026-07-16'::date + 120,
  '2026-07-01 08:00:00+07'::timestamptz,
  'ACTIVE',
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '40800000-0000-4000-8000-000000000007'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-DAMAGED-ONLY',
  '2026-01-01'::date,
  '2026-07-16'::date + 20,
  '2026-07-01 08:00:00+07'::timestamptz,
  'ACTIVE',
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '40800000-0000-4000-8000-000000000008'::uuid,
  '00000000-0000-4000-8000-000000000008'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-ZERO',
  '2026-01-01'::date,
  '2026-07-16'::date + 10,
  '2026-07-01 08:00:00+07'::timestamptz,
  'ARCHIVED',
  '2026-07-16 09:00:00+07'::timestamptz,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
);

update catalog.product_batches
set
  status_code = 'BLOCKED',
  block_reason = 'Expired batch awaiting disposal',
  updated_at = '2026-07-16 09:00:00+07'::timestamptz
where id = '40800000-0000-4000-8000-000000000005'::uuid;

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
values
(
  '00000000-0000-4000-8000-000000000008'::uuid,
  '40800000-0000-4000-8000-000000000001'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  10,
  0,
  0,
  0,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '00000000-0000-4000-8000-000000000008'::uuid,
  '40800000-0000-4000-8000-000000000002'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  0,
  8,
  0,
  0,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '00000000-0000-4000-8000-000000000008'::uuid,
  '40800000-0000-4000-8000-000000000003'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  6,
  0,
  0,
  0,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '00000000-0000-4000-8000-000000000008'::uuid,
  '40800000-0000-4000-8000-000000000004'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  4,
  0,
  0,
  0,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '00000000-0000-4000-8000-000000000008'::uuid,
  '40800000-0000-4000-8000-000000000005'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  0,
  0,
  3,
  0,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '00000000-0000-4000-8000-000000000008'::uuid,
  '40800000-0000-4000-8000-000000000006'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  5,
  0,
  0,
  0,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
),
(
  '00000000-0000-4000-8000-000000000008'::uuid,
  '40800000-0000-4000-8000-000000000007'::uuid,
  '30800000-0000-4000-8000-000000000001'::uuid,
  0,
  0,
  4,
  0,
  '2026-07-16 09:00:00+07'::timestamptz,
  1
);

-- 11-15: deterministic rule provisioning
select lives_ok(
  $sql$
    select notification.ensure_expiry_rule(
      '00000000-0000-4000-8000-000000000008'::uuid,
      '2026-07-16 10:00:00+07'::timestamptz
    )
  $sql$,
  'expiry rule can be provisioned from organization settings'
);

select is(
  (
    select count(*)
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and code = 'EXPIRY_RISK'
  ),
  1::bigint,
  'rule provisioning creates one expiry rule'
);

select is(
  (
    select config -> 'thresholdDays'
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and code = 'EXPIRY_RISK'
  ),
  '[90,60,30,0]'::jsonb,
  'provisioned rule snapshots configured threshold days'
);

select is(
  (
    select action_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and code = 'EXPIRY_RISK'
  ),
  'OPEN_BATCH_EXPIRY_DETAIL',
  'provisioned rule uses the approved expiry deep-link action'
);

select is(
  notification.ensure_expiry_rule(
    '00000000-0000-4000-8000-000000000008'::uuid,
    '2026-07-16 10:00:00+07'::timestamptz
  ),
  (
    select id
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and code = 'EXPIRY_RISK'
  ),
  'rule provisioning is idempotent'
);

create temporary table domain_counts_before as
select
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  )::bigint as transaction_count,
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  )::bigint as ledger_count,
  (
    select count(*)
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  )::bigint as product_position_count;

create temporary table first_run_result as
select notification.evaluate_expiry(
  '00000000-0000-4000-8000-000000000008'::uuid,
  'expiry:2026-07-16',
  '2026-07-16 10:00:00+07'::timestamptz,
  'SCHEDULED',
  '97800000-0000-4000-8000-000000000001'::uuid,
  'pgtap.notification_expiry'
) as result;

-- 16-24: first scheduled evaluation
select is(
  (select result ->> 'status' from first_run_result),
  'SUCCEEDED',
  'first expiry evaluation succeeds'
);

select is(
  (select (result ->> 'evaluatedCount')::integer from first_run_result),
  8,
  'first evaluation inspects every batch exactly once'
);

select is(
  (select (result ->> 'createdCount')::integer from first_run_result),
  5,
  'first evaluation creates five eligible expiry notifications'
);

select is(
  (select (result ->> 'updatedCount')::integer from first_run_result),
  0,
  'first evaluation has no existing episode to update'
);

select is(
  (select (result ->> 'resolvedCount')::integer from first_run_result),
  0,
  'first evaluation has no active episode to resolve'
);

select is(
  (select (result ->> 'skippedCount')::integer from first_run_result),
  3,
  'future, damaged-only approaching, and zero-balance batches are skipped'
);

select is(
  (select (result ->> 'errorCount')::integer from first_run_result),
  0,
  'first evaluation records no entity errors'
);

select is(
  (
    select status_code
    from notification.rule_runs
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and idempotency_key = 'expiry:2026-07-16'
  ),
  'SUCCEEDED',
  'rule execution persists a successful terminal status'
);

select ok(
  (
    select actor_user_id is null
      and process_name = 'pgtap.notification_expiry'
    from notification.rule_runs
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and idempotency_key = 'expiry:2026-07-16'
  ),
  'scheduled execution records a trusted process actor'
);

-- 25-36: expiry condition, stage, severity, and source projection
select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  ),
  5::bigint,
  'one active notification is created per eligible batch'
);

select is(
  (
    select stage_code
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000001'::uuid
  ),
  'D90',
  '75 remaining days maps to D90'
);

select is(
  (
    select severity_code
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000002'::uuid
  ),
  'WARNING',
  '45 remaining days maps to WARNING severity'
);

select is(
  (
    select stage_code
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000003'::uuid
  ),
  'D30',
  '15 remaining days maps to D30'
);

select is(
  (
    select stage_code
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000004'::uuid
  ),
  'D30',
  'same-day expiry remains D30 rather than EXPIRED'
);

select is(
  (
    select severity_code
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000005'::uuid
  ),
  'CRITICAL',
  'past local expiry with physical balance maps to CRITICAL'
);

select is(
  (
    select count(*)
    from notification.notifications
    where entity_id in (
      '40800000-0000-4000-8000-000000000006'::uuid,
      '40800000-0000-4000-8000-000000000007'::uuid,
      '40800000-0000-4000-8000-000000000008'::uuid
    )
  ),
  0::bigint,
  'ineligible batches do not receive notification rows'
);

select is(
  (
    select source_snapshot ->> 'riskQty'
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000002'::uuid
  ),
  '8',
  'approaching-expiry risk quantity includes quarantine stock'
);

select is(
  (
    select source_snapshot ->> 'physicalQty'
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000005'::uuid
  ),
  '3',
  'expired physical quantity includes damaged stock'
);

select is(
  (
    select action_route
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000001'::uuid
  ),
  '/admin/products/30800000-0000-4000-8000-000000000001/batches/40800000-0000-4000-8000-000000000001',
  'expiry notification stores a server-generated batch deep link'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and event_type_code = 'CREATED'
  ),
  5::bigint,
  'first evaluation appends one CREATED event per new episode'
);

select is(
  (
    select count(*)
    from notification.user_states
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  ),
  0::bigint,
  'creating notifications does not eagerly create presentation state'
);

-- 37-39: evaluator does not mutate stock-domain truth
select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  ),
  (select transaction_count from domain_counts_before),
  'expiry evaluation creates no stock transaction'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  ),
  (select ledger_count from domain_counts_before),
  'expiry evaluation creates no ledger entry'
);

select is(
  (
    select count(*)
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  ),
  (select product_position_count from domain_counts_before),
  'expiry evaluation does not rewrite product positions'
);

create temporary table first_replay_result as
select notification.evaluate_expiry(
  '00000000-0000-4000-8000-000000000008'::uuid,
  'expiry:2026-07-16',
  '2026-07-16 10:00:00+07'::timestamptz,
  'SCHEDULED',
  '97800000-0000-4000-8000-000000000001'::uuid,
  'pgtap.notification_expiry'
) as result;

-- 40-42: run idempotency
select is(
  (select result ->> 'action' from first_replay_result),
  'REPLAYED',
  'reusing the run idempotency key replays the stored execution'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  ),
  1::bigint,
  'idempotent replay does not create a second rule run'
);

select is(
  (
    select sum(occurrence_count)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  ),
  5::bigint,
  'idempotent replay does not re-observe active episodes'
);

-- Mark two escalating episodes READ for the only active Admin.
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
select
  notification_row.organization_id,
  notification_row.id,
  '94400000-0000-4000-8000-000000000001'::uuid,
  'READ',
  '2026-07-16 10:30:00+07'::timestamptz,
  null,
  notification_row.version_no,
  '2026-07-16 10:30:00+07'::timestamptz,
  '2026-07-16 10:30:00+07'::timestamptz
from notification.notifications notification_row
where notification_row.organization_id =
    '00000000-0000-4000-8000-000000000008'::uuid
  and notification_row.entity_id in (
    '40800000-0000-4000-8000-000000000002'::uuid,
    '40800000-0000-4000-8000-000000000004'::uuid
  );

-- Change source truth before the next local-day evaluation.
update catalog.product_batches
set expiry_date = '2026-07-17'::date + 100
where id = '40800000-0000-4000-8000-000000000001'::uuid;

update catalog.product_batches
set expiry_date = '2026-07-17'::date + 29
where id = '40800000-0000-4000-8000-000000000002'::uuid;

update inventory.stock_batch_balances
set
  sellable_qty = 0,
  version = version + 1,
  updated_at = '2026-07-17 09:00:00+07'::timestamptz
where organization_id =
    '00000000-0000-4000-8000-000000000008'::uuid
  and batch_id =
    '40800000-0000-4000-8000-000000000003'::uuid;

update inventory.stock_batch_balances
set
  damaged_qty = 0,
  version = version + 1,
  updated_at = '2026-07-17 09:00:00+07'::timestamptz
where organization_id =
    '00000000-0000-4000-8000-000000000008'::uuid
  and batch_id =
    '40800000-0000-4000-8000-000000000005'::uuid;

create temporary table second_run_result as
select notification.evaluate_expiry(
  '00000000-0000-4000-8000-000000000008'::uuid,
  'expiry:2026-07-17',
  '2026-07-17 10:00:00+07'::timestamptz,
  'SCHEDULED',
  '97800000-0000-4000-8000-000000000002'::uuid,
  'pgtap.notification_expiry'
) as result;

-- 43-59: escalation, resolution, and per-user reset
select is(
  (select result ->> 'status' from second_run_result),
  'SUCCEEDED',
  'second expiry evaluation succeeds'
);

select is(
  (select (result ->> 'evaluatedCount')::integer from second_run_result),
  8,
  'second evaluation still evaluates each source batch once'
);

select is(
  (select (result ->> 'createdCount')::integer from second_run_result),
  0,
  'second evaluation creates no duplicate episode'
);

select is(
  (select (result ->> 'updatedCount')::integer from second_run_result),
  2,
  'two still-active conditions are updated'
);

select is(
  (select (result ->> 'resolvedCount')::integer from second_run_result),
  3,
  'three cleared source conditions resolve active episodes'
);

select is(
  (select (result ->> 'skippedCount')::integer from second_run_result),
  3,
  'three source batches remain ineligible without active episodes'
);

select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  2::bigint,
  'only two expiry episodes remain active after source reconciliation'
);

select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and lifecycle_status_code = 'RESOLVED'
  ),
  3::bigint,
  'three resolved episodes remain as history'
);

select is(
  (
    select stage_code
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  'D30',
  'D60 episode escalates to D30'
);

select is(
  (
    select stage_code
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000004'::uuid
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  'EXPIRED',
  'same-day D30 episode escalates to EXPIRED on the next local date'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and event_type_code = 'STAGE_ESCALATED'
  ),
  2::bigint,
  'both stage crossings are recorded append-only'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and event_type_code = 'READ_STATE_RESET_BY_ESCALATION'
  ),
  2::bigint,
  'each escalation records a read-state reset event'
);

select is(
  (
    select count(*)
    from notification.user_states
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and read_state_code = 'UNREAD'
      and read_at is null
      and archived_at is null
  ),
  2::bigint,
  'escalation resets both Admin presentation states to UNREAD'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'RESOLVED'
  ),
  'OUTSIDE_EXPIRY_WINDOW',
  'expiry correction outside thresholds records its resolution reason'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000003'::uuid
      and lifecycle_status_code = 'RESOLVED'
  ),
  'RISK_BALANCE_ZERO',
  'approaching-expiry episode resolves when risk quantity becomes zero'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000005'::uuid
      and lifecycle_status_code = 'RESOLVED'
  ),
  'PHYSICAL_BALANCE_ZERO',
  'expired episode resolves when all physical quantity becomes zero'
);

select is(
  (
    select resolved_count
    from notification.rule_runs
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and idempotency_key = 'expiry:2026-07-17'
  ),
  3,
  'rule-run audit persists the resolved count'
);

-- De-escalate the expired episode after an audited expiry-date correction.
update catalog.product_batches
set expiry_date = '2026-07-18'::date + 45
where id = '40800000-0000-4000-8000-000000000004'::uuid;

update notification.user_states
set
  read_state_code = 'READ',
  read_at = '2026-07-18 09:00:00+07'::timestamptz,
  archived_at = null,
  last_seen_version_no = (
    select notification_row.version_no
    from notification.notifications notification_row
    where notification_row.entity_id =
      '40800000-0000-4000-8000-000000000004'::uuid
      and notification_row.lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  )
where organization_id =
    '00000000-0000-4000-8000-000000000008'::uuid
  and user_id =
    '94400000-0000-4000-8000-000000000001'::uuid
  and notification_id = (
    select notification_row.id
    from notification.notifications notification_row
    where notification_row.entity_id =
      '40800000-0000-4000-8000-000000000004'::uuid
      and notification_row.lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  );

create temporary table third_run_result as
select notification.evaluate_expiry(
  '00000000-0000-4000-8000-000000000008'::uuid,
  'expiry:2026-07-18',
  '2026-07-18 10:00:00+07'::timestamptz,
  'SCHEDULED',
  '97800000-0000-4000-8000-000000000003'::uuid,
  'pgtap.notification_expiry'
) as result;

-- 60-66: de-escalation preserves read state
select is(
  (select result ->> 'status' from third_run_result),
  'SUCCEEDED',
  'third expiry evaluation succeeds'
);

select is(
  (select (result ->> 'updatedCount')::integer from third_run_result),
  2,
  'third evaluation updates both active episodes'
);

select is(
  (select (result ->> 'skippedCount')::integer from third_run_result),
  6,
  'third evaluation skips six inactive or ineligible source batches'
);

select is(
  (
    select stage_code
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000004'::uuid
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  'D60',
  'corrected expiry date de-escalates EXPIRED to D60'
);

select is(
  (
    select severity_code
    from notification.notifications
    where entity_id =
      '40800000-0000-4000-8000-000000000004'::uuid
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  'WARNING',
  'de-escalated D60 episode receives WARNING severity'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and event_type_code = 'STAGE_DEESCALATED'
  ),
  1::bigint,
  'de-escalation appends its own history event'
);

select is(
  (
    select read_state_code
    from notification.user_states
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and user_id =
        '94400000-0000-4000-8000-000000000001'::uuid
      and notification_id = (
        select notification_row.id
        from notification.notifications notification_row
        where notification_row.entity_id =
          '40800000-0000-4000-8000-000000000004'::uuid
          and notification_row.lifecycle_status_code in (
            'OPEN',
            'ACKNOWLEDGED'
          )
      )
  ),
  'READ',
  'de-escalation does not reset the Admin read state'
);

-- Bring the previously resolved D90 condition back inside the window.
update catalog.product_batches
set expiry_date = '2026-07-19'::date + 80
where id = '40800000-0000-4000-8000-000000000001'::uuid;

create temporary table fourth_run_result as
select notification.evaluate_expiry(
  '00000000-0000-4000-8000-000000000008'::uuid,
  'expiry:2026-07-19',
  '2026-07-19 10:00:00+07'::timestamptz,
  'SCHEDULED',
  '97800000-0000-4000-8000-000000000004'::uuid,
  'pgtap.notification_expiry'
) as result;

-- 67-74: recurrence creates a linked new episode
select is(
  (select result ->> 'status' from fourth_run_result),
  'SUCCEEDED',
  'fourth expiry evaluation succeeds'
);

select is(
  (select (result ->> 'createdCount')::integer from fourth_run_result),
  1,
  'recurring source condition creates one new episode'
);

select is(
  (select (result ->> 'updatedCount')::integer from fourth_run_result),
  2,
  'fourth evaluation re-observes the two existing active episodes'
);

select is(
  (select (result ->> 'skippedCount')::integer from fourth_run_result),
  5,
  'fourth evaluation skips the five remaining ineligible batches'
);

select is(
  (
    select max(episode_no)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and entity_id =
        '40800000-0000-4000-8000-000000000001'::uuid
  ),
  2,
  'recurring expiry condition advances the episode number'
);

select ok(
  (
    select previous_notification_id is not null
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and entity_id =
        '40800000-0000-4000-8000-000000000001'::uuid
      and episode_no = 2
  ),
  'new expiry episode links its resolved predecessor'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and event_type_code = 'REOPENED_AS_NEW_EPISODE'
  ),
  1::bigint,
  'recurrence appends a REOPENED_AS_NEW_EPISODE event'
);

select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  3::bigint,
  'three source conditions are active after recurrence'
);

-- Invalid rule config must produce an auditable FAILED run without partial effects.
create temporary table before_failed_run as
select
  count(*)::bigint as notification_count,
  coalesce(sum(version_no), 0)::bigint as notification_version_sum
from notification.notifications
where organization_id =
  '00000000-0000-4000-8000-000000000008'::uuid;

update notification.rules
set config = jsonb_set(
  config,
  '{thresholdDays}',
  '[90,30,60,0]'::jsonb,
  false
)
where organization_id =
    '00000000-0000-4000-8000-000000000008'::uuid
  and code = 'EXPIRY_RISK';

create temporary table failed_run_result as
select notification.evaluate_expiry(
  '00000000-0000-4000-8000-000000000008'::uuid,
  'expiry:invalid-config',
  '2026-07-20 10:00:00+07'::timestamptz,
  'SCHEDULED',
  '97800000-0000-4000-8000-000000000005'::uuid,
  'pgtap.notification_expiry'
) as result;

-- 75-80: structural failure is retained and idempotent
select is(
  (select result ->> 'status' from failed_run_result),
  'FAILED',
  'invalid rule configuration produces a FAILED evaluation'
);

select is(
  (
    select status_code
    from notification.rule_runs
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and idempotency_key = 'expiry:invalid-config'
  ),
  'FAILED',
  'failed evaluation remains visible in rule-run history'
);

select is(
  (
    select error_code
    from notification.rule_runs
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
      and idempotency_key = 'expiry:invalid-config'
  ),
  'EXPIRY_EVALUATION_FAILED',
  'failed evaluation stores a stable audit error code'
);

select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  ),
  (select notification_count from before_failed_run),
  'failed evaluation does not create or delete notification episodes'
);

select is(
  (
    select coalesce(sum(version_no), 0)::bigint
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000008'::uuid
  ),
  (select notification_version_sum from before_failed_run),
  'failed evaluation rolls back partial notification updates'
);

select is(
  (
    notification.evaluate_expiry(
      '00000000-0000-4000-8000-000000000008'::uuid,
      'expiry:invalid-config',
      '2026-07-20 10:00:00+07'::timestamptz,
      'SCHEDULED',
      '97800000-0000-4000-8000-000000000005'::uuid,
      'pgtap.notification_expiry'
    ) ->> 'action'
  ),
  'REPLAYED',
  'failed rule run is also idempotently replayed'
);

-- Restore valid config for input-validation checks.
update notification.rules
set config = jsonb_set(
  config,
  '{thresholdDays}',
  '[90,60,30,0]'::jsonb,
  false
)
where organization_id =
    '00000000-0000-4000-8000-000000000008'::uuid
  and code = 'EXPIRY_RISK';

-- 81-85: trusted invocation validation
select throws_ok(
  $sql$
    select notification.evaluate_expiry(
      '00000000-0000-4000-8000-000000000008'::uuid,
      '   '
    )
  $sql$,
  'P0001',
  'NOTIFICATION_RULE_RUN_IDEMPOTENCY_REQUIRED',
  'evaluator requires an idempotency key'
);

select throws_ok(
  $sql$
    select notification.evaluate_expiry(
      '00000000-0000-4000-8000-000000000008'::uuid,
      'expiry:bad-trigger',
      '2026-07-20 10:00:00+07'::timestamptz,
      'EVENT_DRIVEN'
    )
  $sql$,
  'P0001',
  'EXPIRY_TRIGGER_TYPE_INVALID',
  'expiry evaluator rejects unsupported trigger types'
);

select throws_ok(
  $sql$
    select notification.evaluate_expiry(
      '00000000-0000-4000-8000-000000000008'::uuid,
      'expiry:null-observed-at',
      null
    )
  $sql$,
  'P0001',
  'NOTIFICATION_OBSERVED_AT_REQUIRED',
  'evaluator requires an observation time'
);

select throws_ok(
  $sql$
    select notification.evaluate_expiry(
      '00000000-0000-4000-8000-000000000008'::uuid,
      'expiry:blank-process',
      '2026-07-20 10:00:00+07'::timestamptz,
      'SCHEDULED',
      '97800000-0000-4000-8000-000000000006'::uuid,
      '   '
    )
  $sql$,
  'P0001',
  'NOTIFICATION_PROCESS_NAME_REQUIRED',
  'evaluator requires a trusted process name'
);

select throws_ok(
  $sql$
    select notification.ensure_expiry_rule(
      '00000000-0000-4000-8000-000000000099'::uuid,
      '2026-07-20 10:00:00+07'::timestamptz
    )
  $sql$,
  'P0001',
  'NOTIFICATION_ORGANIZATION_NOT_FOUND',
  'rule provisioning rejects an unknown organization'
);

-- 86: an explicitly disabled rule is not silently recreated
update notification.rules
set is_active = false
where organization_id =
    '00000000-0000-4000-8000-000000000008'::uuid
  and code = 'EXPIRY_RISK';

select throws_ok(
  $sql$
    select notification.ensure_expiry_rule(
      '00000000-0000-4000-8000-000000000008'::uuid,
      '2026-07-20 10:00:00+07'::timestamptz
    )
  $sql$,
  'P0001',
  'EXPIRY_RULE_NOT_ACTIVE',
  'disabled expiry rule is respected rather than silently replaced'
);

select * from finish();
rollback;
