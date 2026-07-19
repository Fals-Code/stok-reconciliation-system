begin;

create extension if not exists pgtap with schema extensions;

select plan(82);

-- Contract surface.
select has_table('operations', 'stock_disposals', 'stock disposal header table exists');
select has_table('operations', 'stock_disposal_lines', 'stock disposal line table exists');
select has_view('api', 'stock_disposals', 'stock disposal read view exists');
select has_view('api', 'stock_disposal_lines', 'stock disposal line read view exists');
select has_view('api', 'stock_disposal_candidates', 'stock disposal candidate view exists');

select function_returns(
  'inventory',
  'preview_stock_disposal_core',
  array[
    'uuid', 'text', 'timestamptz', 'text', 'jsonb',
    'text', 'text', 'jsonb', 'boolean'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'preview_stock_disposal',
  array[
    'uuid', 'text', 'timestamptz', 'text',
    'jsonb', 'text', 'text', 'jsonb'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'post_stock_disposal',
  array[
    'uuid', 'text', 'text', 'timestamptz', 'text', 'jsonb',
    'text', 'boolean', 'text', 'text', 'jsonb'
  ]::text[],
  'jsonb'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.preview_stock_disposal(uuid,text,timestamptz,text,jsonb,text,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot preview stock disposal'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.preview_stock_disposal(uuid,text,timestamptz,text,jsonb,text,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may preview stock disposal'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.post_stock_disposal(uuid,text,text,timestamptz,text,jsonb,text,boolean,text,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot post stock disposal'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.post_stock_disposal(uuid,text,text,timestamptz,text,jsonb,text,boolean,text,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may post stock disposal'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'inventory.preview_stock_disposal_core(uuid,text,timestamptz,text,jsonb,text,text,jsonb,boolean)',
    'EXECUTE'
  ),
  'authenticated role cannot execute internal disposal preview core'
);

select ok(
  not has_table_privilege('authenticated', 'operations.stock_disposals', 'INSERT'),
  'authenticated role cannot insert disposal headers directly'
);

select ok(
  not has_table_privilege('authenticated', 'operations.stock_disposal_lines', 'INSERT'),
  'authenticated role cannot insert disposal lines directly'
);

select ok(
  (
    select class.relrowsecurity
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'stock_disposals'
  ),
  'stock disposal headers have RLS enabled'
);

select ok(
  (
    select class.relrowsecurity
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'stock_disposal_lines'
  ),
  'stock disposal lines have RLS enabled'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    cross join lateral unnest(procedure.proconfig) config(value)
    where namespace.nspname = 'api'
      and procedure.proname = 'post_stock_disposal'
      and procedure.pronargs = 11
      and config.value =
        'search_path=pg_catalog, auth, app, catalog, inventory, operations, extensions'
  ),
  'stock disposal posting has a fixed search_path'
);

-- Dedicated isolated fixture organization and Admin.
insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active,
  created_at,
  created_by
) values (
  '00000000-0000-4000-8000-000000000038'::uuid,
  'PGTAP_DISPOSAL',
  'pgTAP Stock Disposal',
  'Asia/Jakarta',
  true,
  '2026-07-20 08:00:00+07'::timestamptz,
  null
);

insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active,
  created_at,
  created_by
) values (
  '00000000-0000-4000-8000-000000000039'::uuid,
  'PGTAP_DISPOSAL_OTHER',
  'pgTAP Stock Disposal Other',
  'Asia/Jakarta',
  true,
  '2026-07-20 08:00:00+07'::timestamptz,
  null
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
) values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  '98000000-0000-4000-8000-000000000038'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.stock.disposal@glowlab.invalid',
  '2026-07-20 08:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-20 08:00:00+07'::timestamptz,
  '2026-07-20 08:00:00+07'::timestamptz,
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
) values (
  '98000000-0000-4000-8000-000000000038'::uuid,
  '00000000-0000-4000-8000-000000000038'::uuid,
  'pgTAP Stock Disposal Admin',
  'PGTAP-DISPOSAL',
  'ADMIN',
  true
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
  row_version
) values
  (
    '38000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    'DSP-DAMAGED',
    'Disposal Damaged Fixture',
    'UNIT', true, true, true,
    '2026-07-01 08:00:00+07'::timestamptz,
    1
  ),
  (
    '38000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    'DSP-EXPIRED',
    'Disposal Expired Fixture',
    'UNIT', true, true, true,
    '2026-07-01 08:00:00+07'::timestamptz,
    1
  ),
  (
    '38000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    'DSP-BOUNDARY',
    'Disposal Boundary Fixture',
    'UNIT', true, true, true,
    '2026-07-01 08:00:00+07'::timestamptz,
    1
  ),
  (
    '38000000-0000-4000-8000-000000000004'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    'DSP-ARCHIVED',
    'Disposal Archived Fixture',
    'UNIT', true, true, true,
    '2026-07-01 08:00:00+07'::timestamptz,
    1
  ),
  (
    '38000000-0000-4000-8000-000000000005'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    'DSP-BLOCKED',
    'Disposal Blocked Fixture',
    'UNIT', true, true, true,
    '2026-07-01 08:00:00+07'::timestamptz,
    1
  ),
  (
    '38000000-0000-4000-8000-000000000006'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    'DSP-AUDIT-ONLY',
    'Return Audit Only Fixture',
    'UNIT', true, true, true,
    '2026-07-01 08:00:00+07'::timestamptz,
    1
  ),
  (
    '38000000-0000-4000-8000-000000000099'::uuid,
    '00000000-0000-4000-8000-000000000039'::uuid,
    'DSP-OTHER',
    'Other Organization Fixture',
    'UNIT', true, true, true,
    '2026-07-01 08:00:00+07'::timestamptz,
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
  block_reason,
  created_at,
  updated_at,
  row_version,
  batch_kind_code
) values
  (
    '48000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    '38000000-0000-4000-8000-000000000001'::uuid,
    'DAMAGED-01',
    '2026-01-01'::date,
    '2026-12-31'::date,
    '2026-01-15 08:00:00+07'::timestamptz,
    'ACTIVE', null,
    '2026-01-15 08:00:00+07'::timestamptz,
    '2026-07-20 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  ),
  (
    '48000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    '38000000-0000-4000-8000-000000000002'::uuid,
    'EXPIRED-01',
    '2025-12-01'::date,
    '2026-07-19'::date,
    '2026-01-10 08:00:00+07'::timestamptz,
    'EXPIRED', null,
    '2026-01-10 08:00:00+07'::timestamptz,
    '2026-07-20 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  ),
  (
    '48000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    '38000000-0000-4000-8000-000000000003'::uuid,
    'BOUNDARY-01',
    '2026-01-01'::date,
    '2026-07-20'::date,
    '2026-01-10 08:00:00+07'::timestamptz,
    'ACTIVE', null,
    '2026-01-10 08:00:00+07'::timestamptz,
    '2026-07-20 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  ),
  (
    '48000000-0000-4000-8000-000000000004'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    '38000000-0000-4000-8000-000000000003'::uuid,
    'NEAR-01',
    '2026-01-01'::date,
    '2026-07-21'::date,
    '2026-01-11 08:00:00+07'::timestamptz,
    'ACTIVE', null,
    '2026-01-11 08:00:00+07'::timestamptz,
    '2026-07-20 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  ),
  (
    '48000000-0000-4000-8000-000000000005'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    '38000000-0000-4000-8000-000000000004'::uuid,
    'ARCHIVED-01',
    '2025-12-01'::date,
    '2026-07-18'::date,
    '2026-01-12 08:00:00+07'::timestamptz,
    'ARCHIVED', null,
    '2026-01-12 08:00:00+07'::timestamptz,
    '2026-07-20 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  ),
  (
    '48000000-0000-4000-8000-000000000006'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    '38000000-0000-4000-8000-000000000005'::uuid,
    'BLOCKED-01',
    '2025-12-01'::date,
    '2026-07-18'::date,
    '2026-01-13 08:00:00+07'::timestamptz,
    'BLOCKED', 'HOLD_FOR_REVIEW',
    '2026-01-13 08:00:00+07'::timestamptz,
    '2026-07-20 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  ),
  (
    '48000000-0000-4000-8000-000000000007'::uuid,
    '00000000-0000-4000-8000-000000000038'::uuid,
    '38000000-0000-4000-8000-000000000006'::uuid,
    'AUDIT-ONLY-01',
    '2025-12-01'::date,
    '2026-12-31'::date,
    '2026-01-14 08:00:00+07'::timestamptz,
    'ACTIVE', null,
    '2026-01-14 08:00:00+07'::timestamptz,
    '2026-07-20 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  ),
  (
    '48000000-0000-4000-8000-000000000099'::uuid,
    '00000000-0000-4000-8000-000000000039'::uuid,
    '38000000-0000-4000-8000-000000000099'::uuid,
    'OTHER-01',
    '2025-12-01'::date,
    '2026-07-18'::date,
    '2026-01-14 08:00:00+07'::timestamptz,
    'EXPIRED', null,
    '2026-01-14 08:00:00+07'::timestamptz,
    '2026-07-20 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  );

-- Ledger-backed physical fixture stock.
insert into inventory.idempotency_commands (
  id, organization_id, scope, key, request_hash, status_code,
  started_at, completed_at, result_transaction_id, response_snapshot
) values (
  '58000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000038'::uuid,
  'PGTAP_DISPOSAL_FIXTURE',
  'PGTAP-DISPOSAL-FIXTURE-001',
  repeat('1', 64),
  'STARTED',
  '2026-07-01 08:00:00+07'::timestamptz,
  null,
  null,
  '{}'::jsonb
);

insert into inventory.stock_transactions (
  id, organization_id, transaction_no, transaction_type_code,
  reason_id, reason_code_snapshot, channel_id, channel_code_snapshot,
  source_type_code, source_id, source_ref_snapshot,
  occurred_at, recorded_at, effective_local_date,
  actor_user_id, process_name, created_by_role_code,
  correlation_id, idempotency_command_id, reversal_of_transaction_id,
  note, metadata, schema_version
) values (
  '68000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000038'::uuid,
  'INIT-DISPOSAL-001',
  'INITIAL_BALANCE',
  (select id from catalog.movement_reasons where code = 'INITIAL_BALANCE'),
  'INITIAL_BALANCE',
  (select id from catalog.channels where code = 'MANUAL'),
  'MANUAL',
  'PGTAP_FIXTURE',
  null,
  'PGTAP-DISPOSAL-FIXTURE-001',
  '2026-07-01 08:00:00+07'::timestamptz,
  '2026-07-01 08:00:00+07'::timestamptz,
  '2026-07-01'::date,
  null,
  'pgtap.stock_disposal_fixture',
  'SYSTEM_PROCESS',
  '78000000-0000-4000-8000-000000000001'::uuid,
  '58000000-0000-4000-8000-000000000001'::uuid,
  null,
  'Fixture saldo disposal.',
  '{"test":true}'::jsonb,
  1
);

insert into inventory.stock_ledger_entries (
  organization_id, transaction_id, line_no, product_id, batch_id,
  product_sku_snapshot, batch_code_snapshot, expiry_date_snapshot,
  bucket_code, quantity_delta, entry_role_code, pair_no,
  source_line_ref, occurred_at, recorded_at, created_at
) values
  (
    '00000000-0000-4000-8000-000000000038'::uuid,
    '68000000-0000-4000-8000-000000000001'::uuid,
    1,
    '38000000-0000-4000-8000-000000000001'::uuid,
    '48000000-0000-4000-8000-000000000001'::uuid,
    'DSP-DAMAGED', 'DAMAGED-01', '2026-12-31'::date,
    'DAMAGED', 10, 'EXTERNAL_IN', null, 'FIXTURE-1',
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz
  ),
  (
    '00000000-0000-4000-8000-000000000038'::uuid,
    '68000000-0000-4000-8000-000000000001'::uuid,
    2,
    '38000000-0000-4000-8000-000000000002'::uuid,
    '48000000-0000-4000-8000-000000000002'::uuid,
    'DSP-EXPIRED', 'EXPIRED-01', '2026-07-19'::date,
    'SELLABLE', 20, 'EXTERNAL_IN', null, 'FIXTURE-2',
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz
  ),
  (
    '00000000-0000-4000-8000-000000000038'::uuid,
    '68000000-0000-4000-8000-000000000001'::uuid,
    3,
    '38000000-0000-4000-8000-000000000002'::uuid,
    '48000000-0000-4000-8000-000000000002'::uuid,
    'DSP-EXPIRED', 'EXPIRED-01', '2026-07-19'::date,
    'QUARANTINE', 5, 'EXTERNAL_IN', null, 'FIXTURE-3',
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz
  ),
  (
    '00000000-0000-4000-8000-000000000038'::uuid,
    '68000000-0000-4000-8000-000000000001'::uuid,
    4,
    '38000000-0000-4000-8000-000000000002'::uuid,
    '48000000-0000-4000-8000-000000000002'::uuid,
    'DSP-EXPIRED', 'EXPIRED-01', '2026-07-19'::date,
    'DAMAGED', 4, 'EXTERNAL_IN', null, 'FIXTURE-4',
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz
  ),
  (
    '00000000-0000-4000-8000-000000000038'::uuid,
    '68000000-0000-4000-8000-000000000001'::uuid,
    5,
    '38000000-0000-4000-8000-000000000003'::uuid,
    '48000000-0000-4000-8000-000000000003'::uuid,
    'DSP-BOUNDARY', 'BOUNDARY-01', '2026-07-20'::date,
    'SELLABLE', 3, 'EXTERNAL_IN', null, 'FIXTURE-5',
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz
  ),
  (
    '00000000-0000-4000-8000-000000000038'::uuid,
    '68000000-0000-4000-8000-000000000001'::uuid,
    6,
    '38000000-0000-4000-8000-000000000003'::uuid,
    '48000000-0000-4000-8000-000000000004'::uuid,
    'DSP-BOUNDARY', 'NEAR-01', '2026-07-21'::date,
    'SELLABLE', 3, 'EXTERNAL_IN', null, 'FIXTURE-6',
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz
  ),
  (
    '00000000-0000-4000-8000-000000000038'::uuid,
    '68000000-0000-4000-8000-000000000001'::uuid,
    7,
    '38000000-0000-4000-8000-000000000004'::uuid,
    '48000000-0000-4000-8000-000000000005'::uuid,
    'DSP-ARCHIVED', 'ARCHIVED-01', '2026-07-18'::date,
    'SELLABLE', 2, 'EXTERNAL_IN', null, 'FIXTURE-7',
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz
  ),
  (
    '00000000-0000-4000-8000-000000000038'::uuid,
    '68000000-0000-4000-8000-000000000001'::uuid,
    8,
    '38000000-0000-4000-8000-000000000005'::uuid,
    '48000000-0000-4000-8000-000000000006'::uuid,
    'DSP-BLOCKED', 'BLOCKED-01', '2026-07-18'::date,
    'SELLABLE', 2, 'EXTERNAL_IN', null, 'FIXTURE-8',
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz
  );

update inventory.idempotency_commands
set
  status_code = 'SUCCEEDED',
  completed_at = '2026-07-01 08:00:00+07'::timestamptz,
  result_transaction_id = '68000000-0000-4000-8000-000000000001'::uuid,
  response_snapshot = '{"status":"SUCCEEDED"}'::jsonb
where id = '58000000-0000-4000-8000-000000000001'::uuid;

insert into inventory.stock_batch_balances (
  organization_id, batch_id, product_id,
  sellable_qty, quarantine_qty, damaged_qty,
  last_ledger_seq, updated_at, version
)
select
  entry.organization_id,
  entry.batch_id,
  entry.product_id,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.bucket_code = 'SELLABLE'
  ), 0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.bucket_code = 'QUARANTINE'
  ), 0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.bucket_code = 'DAMAGED'
  ), 0)::bigint,
  max(entry.ledger_seq),
  '2026-07-20 08:00:00+07'::timestamptz,
  1
from inventory.stock_ledger_entries entry
where entry.transaction_id = '68000000-0000-4000-8000-000000000001'::uuid
group by entry.organization_id, entry.batch_id, entry.product_id;

insert into inventory.stock_batch_balances (
  organization_id, batch_id, product_id,
  sellable_qty, quarantine_qty, damaged_qty,
  last_ledger_seq, updated_at, version
) values (
  '00000000-0000-4000-8000-000000000038'::uuid,
  '48000000-0000-4000-8000-000000000007'::uuid,
  '38000000-0000-4000-8000-000000000006'::uuid,
  0, 0, 0, 0,
  '2026-07-20 08:00:00+07'::timestamptz,
  1
);

insert into inventory.stock_product_positions (
  organization_id, product_id,
  sellable_qty, quarantine_qty, damaged_qty, reserved_qty,
  last_ledger_seq, updated_at, version
)
select
  entry.organization_id,
  entry.product_id,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.bucket_code = 'SELLABLE'
  ), 0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.bucket_code = 'QUARANTINE'
  ), 0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.bucket_code = 'DAMAGED'
  ), 0)::bigint,
  case
    when entry.product_id = '38000000-0000-4000-8000-000000000002'::uuid
      then 6
    else 0
  end,
  max(entry.ledger_seq),
  '2026-07-20 08:00:00+07'::timestamptz,
  1
from inventory.stock_ledger_entries entry
where entry.transaction_id = '68000000-0000-4000-8000-000000000001'::uuid
group by entry.organization_id, entry.product_id;

insert into inventory.stock_product_positions (
  organization_id, product_id,
  sellable_qty, quarantine_qty, damaged_qty, reserved_qty,
  last_ledger_seq, updated_at, version
) values (
  '00000000-0000-4000-8000-000000000038'::uuid,
  '38000000-0000-4000-8000-000000000006'::uuid,
  0, 0, 0, 0, 0,
  '2026-07-20 08:00:00+07'::timestamptz,
  1
);

create temp table stock_disposal_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update on stock_disposal_results to authenticated;

create temp table stock_disposal_baseline (
  transaction_count bigint not null,
  ledger_count bigint not null,
  disposal_count bigint not null,
  idempotency_count bigint not null,
  damaged_batch_qty bigint not null,
  damaged_product_qty bigint not null
) on commit drop;

insert into stock_disposal_baseline
select
  (select count(*) from inventory.stock_transactions
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid),
  (select count(*) from inventory.stock_ledger_entries
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid),
  (select count(*) from operations.stock_disposals
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid),
  (select count(*) from inventory.idempotency_commands
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid),
  (select damaged_qty from inventory.stock_batch_balances
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid
     and batch_id = '48000000-0000-4000-8000-000000000001'::uuid),
  (select damaged_qty from inventory.stock_product_positions
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid
     and product_id = '38000000-0000-4000-8000-000000000001'::uuid);

grant select on stock_disposal_baseline to authenticated;

select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-4000-8000-000000000038',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98000000-0000-4000-8000-000000000038',
    'role', 'authenticated',
    'email', 'pgtap.stock.disposal@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

-- Stock-neutral authoritative previews.
insert into stock_disposal_results (kind, result)
select 'DAMAGED_READY', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-DAMAGED-READY-001',
  '2026-07-20 12:00:00+07'::timestamptz,
  'DAMAGED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000001',
    'batchId', '48000000-0000-4000-8000-000000000001',
    'sourceBucketCode', 'DAMAGED',
    'quantity', 3,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-001',
  'Barang rusak telah dipisahkan dan diverifikasi.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'DAMAGED_READY_REPEAT', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-DAMAGED-READY-001',
  '2026-07-20 12:00:00+07'::timestamptz,
  'DAMAGED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000001',
    'batchId', '48000000-0000-4000-8000-000000000001',
    'sourceBucketCode', 'DAMAGED',
    'quantity', 3,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-001',
  'Barang rusak telah dipisahkan dan diverifikasi.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'DAMAGED_WRONG_BUCKET', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-DAMAGED-WRONG-001',
  '2026-07-20 12:01:00+07'::timestamptz,
  'DAMAGED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000002',
    'batchId', '48000000-0000-4000-8000-000000000002',
    'sourceBucketCode', 'SELLABLE',
    'quantity', 1,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-002',
  'Sumber bucket salah untuk fixture.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'EXPIRED_SELLABLE_READY', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-EXPIRED-SELLABLE-001',
  '2026-07-20 12:02:00+07'::timestamptz,
  'EXPIRED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000002',
    'batchId', '48000000-0000-4000-8000-000000000002',
    'sourceBucketCode', 'SELLABLE',
    'quantity', 2,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-003',
  'Batch kedaluwarsa dari sellable.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'EXPIRED_QUARANTINE_READY', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-EXPIRED-QUARANTINE-001',
  '2026-07-20 12:03:00+07'::timestamptz,
  'EXPIRED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000002',
    'batchId', '48000000-0000-4000-8000-000000000002',
    'sourceBucketCode', 'QUARANTINE',
    'quantity', 2,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-004',
  'Batch kedaluwarsa dari quarantine.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'EXPIRED_DAMAGED_READY', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-EXPIRED-DAMAGED-001',
  '2026-07-20 12:04:00+07'::timestamptz,
  'EXPIRED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000002',
    'batchId', '48000000-0000-4000-8000-000000000002',
    'sourceBucketCode', 'DAMAGED',
    'quantity', 2,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-005',
  'Batch kedaluwarsa dari damaged.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'BOUNDARY_BLOCKED', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-BOUNDARY-001',
  '2026-07-20 12:05:00+07'::timestamptz,
  'EXPIRED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000003',
    'batchId', '48000000-0000-4000-8000-000000000003',
    'sourceBucketCode', 'SELLABLE',
    'quantity', 1,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-006',
  'Tanggal kemasan sama dengan tanggal lokal.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'NEAR_EXPIRY_BLOCKED', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-NEAR-001',
  '2026-07-20 12:06:00+07'::timestamptz,
  'EXPIRED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000003',
    'batchId', '48000000-0000-4000-8000-000000000004',
    'sourceBucketCode', 'SELLABLE',
    'quantity', 1,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-007',
  'Batch baru mendekati kedaluwarsa.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'ARCHIVED_BLOCKED', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-ARCHIVED-001',
  '2026-07-20 12:07:00+07'::timestamptz,
  'EXPIRED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000004',
    'batchId', '48000000-0000-4000-8000-000000000005',
    'sourceBucketCode', 'SELLABLE',
    'quantity', 1,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-008',
  'Batch arsip harus diblokir.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'BLOCKED_BATCH_READY', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-BLOCKED-BATCH-001',
  '2026-07-20 12:08:00+07'::timestamptz,
  'EXPIRED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000005',
    'batchId', '48000000-0000-4000-8000-000000000006',
    'sourceBucketCode', 'SELLABLE',
    'quantity', 1,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-009',
  'Batch blocked tetap memiliki stok fisik.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'AUDIT_ONLY_BLOCKED', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-AUDIT-ONLY-001',
  '2026-07-20 12:09:00+07'::timestamptz,
  'DAMAGED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000006',
    'batchId', '48000000-0000-4000-8000-000000000007',
    'sourceBucketCode', 'DAMAGED',
    'quantity', 1,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-010',
  'Audit rusak tanpa ledger tidak boleh menjadi stok.',
  '{"test":true,"returnDamagedAuditQuantity":99}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'INSUFFICIENT_BLOCKED', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-INSUFFICIENT-001',
  '2026-07-20 12:10:00+07'::timestamptz,
  'DAMAGED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000001',
    'batchId', '48000000-0000-4000-8000-000000000001',
    'sourceBucketCode', 'DAMAGED',
    'quantity', 99,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-011',
  'Kuantitas melebihi saldo.',
  '{"test":true}'::jsonb
);

insert into stock_disposal_results (kind, result)
select 'RESERVED_CONFLICT', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-RESERVED-001',
  '2026-07-20 12:11:00+07'::timestamptz,
  'EXPIRED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000002',
    'batchId', '48000000-0000-4000-8000-000000000002',
    'sourceBucketCode', 'SELLABLE',
    'quantity', 15,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-012',
  'Reserved tidak boleh melebihi sellable hasil.',
  '{"test":true}'::jsonb
);

select is(
  (select result ->> 'status' from stock_disposal_results where kind = 'DAMAGED_READY'),
  'PREVIEW_READY',
  'damaged disposal is preview-ready from DAMAGED'
);
select ok(
  (select (result ->> 'eligible')::boolean from stock_disposal_results where kind = 'DAMAGED_READY'),
  'damaged disposal preview is eligible'
);
select is(
  (select result #>> '{lines,0,currentBatchBucketQty}' from stock_disposal_results where kind = 'DAMAGED_READY'),
  '10',
  'damaged preview shows authoritative current batch bucket quantity'
);
select is(
  (select result #>> '{lines,0,resultingBatchBucketQty}' from stock_disposal_results where kind = 'DAMAGED_READY'),
  '7',
  'damaged preview shows resulting batch bucket quantity'
);
select is(
  (select result ->> 'basisHash' from stock_disposal_results where kind = 'DAMAGED_READY'),
  (select result ->> 'basisHash' from stock_disposal_results where kind = 'DAMAGED_READY_REPEAT'),
  'identical preview input has a stable basis hash'
);
select is(
  (select result #>> '{blockers,0,code}' from stock_disposal_results where kind = 'DAMAGED_WRONG_BUCKET'),
  'INVALID_DAMAGED_DISPOSAL_SOURCE',
  'damaged disposal rejects a non-DAMAGED source bucket'
);
select ok(
  (select (result ->> 'eligible')::boolean from stock_disposal_results where kind = 'EXPIRED_SELLABLE_READY'),
  'expired disposal accepts SELLABLE physical stock'
);
select ok(
  (select (result ->> 'eligible')::boolean from stock_disposal_results where kind = 'EXPIRED_QUARANTINE_READY'),
  'expired disposal accepts QUARANTINE physical stock'
);
select ok(
  (select (result ->> 'eligible')::boolean from stock_disposal_results where kind = 'EXPIRED_DAMAGED_READY'),
  'expired disposal accepts DAMAGED physical stock'
);
select is(
  (select result #>> '{blockers,0,code}' from stock_disposal_results where kind = 'BOUNDARY_BLOCKED'),
  'INVALID_EXPIRED_DISPOSAL_SOURCE',
  'expiry date equal to local operation date is not yet expired'
);
select is(
  (select result #>> '{blockers,0,code}' from stock_disposal_results where kind = 'NEAR_EXPIRY_BLOCKED'),
  'INVALID_EXPIRED_DISPOSAL_SOURCE',
  'near-expiry stock is not postable as expired disposal'
);
select is(
  (select result #>> '{blockers,0,code}' from stock_disposal_results where kind = 'ARCHIVED_BLOCKED'),
  'DISPOSAL_BATCH_ARCHIVED',
  'archived batch is rejected'
);
select ok(
  (select (result ->> 'eligible')::boolean from stock_disposal_results where kind = 'BLOCKED_BATCH_READY'),
  'blocked expired batch remains disposable while physical stock exists'
);
select is(
  (select result #>> '{lines,0,currentBatchDamagedQty}' from stock_disposal_results where kind = 'AUDIT_ONLY_BLOCKED'),
  '0',
  'return audit metadata does not manufacture DAMAGED inventory'
);
select is(
  (select result #>> '{blockers,0,code}' from stock_disposal_results where kind = 'AUDIT_ONLY_BLOCKED'),
  'DISPOSAL_EXCEEDS_BALANCE',
  'damaged disposal requires ledger-backed damaged balance'
);
select is(
  (select result #>> '{blockers,0,code}' from stock_disposal_results where kind = 'INSUFFICIENT_BLOCKED'),
  'DISPOSAL_EXCEEDS_BALANCE',
  'disposal cannot exceed the selected bucket balance'
);
select is(
  (select result #>> '{blockers,0,code}' from stock_disposal_results where kind = 'RESERVED_CONFLICT'),
  'DISPOSAL_RESERVED_CONFLICT',
  'sellable expired disposal cannot violate reserved <= sellable'
);

select is(
  (select count(*) from inventory.stock_transactions
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid),
  (select transaction_count from stock_disposal_baseline),
  'preview creates no stock transaction'
);
select is(
  (select count(*) from inventory.stock_ledger_entries
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid),
  (select ledger_count from stock_disposal_baseline),
  'preview creates no ledger entry'
);
select is(
  (select count(*) from operations.stock_disposals
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid),
  (select disposal_count from stock_disposal_baseline),
  'preview creates no disposal document'
);
select is(
  (select count(*) from inventory.idempotency_commands
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid),
  (select idempotency_count from stock_disposal_baseline),
  'preview creates no idempotency command'
);

select throws_ok(
  $sql$
    select api.preview_stock_disposal(
      '00000000-0000-4000-8000-000000000038'::uuid,
      'DSP-DUP-LINE-001',
      '2026-07-20 12:12:00+07'::timestamptz,
      'DAMAGED_DISPOSAL',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '38000000-0000-4000-8000-000000000001',
          'batchId', '48000000-0000-4000-8000-000000000001',
          'sourceBucketCode', 'DAMAGED',
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        ),
        jsonb_build_object(
          'productId', '38000000-0000-4000-8000-000000000001',
          'batchId', '48000000-0000-4000-8000-000000000001',
          'sourceBucketCode', 'DAMAGED',
          'quantity', 1,
          'sourceLineRef', 'LINE-2'
        )
      ),
      'BA-DUP-001',
      'Duplicate exact batch bucket.',
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'DISPOSAL_DUPLICATE_BATCH_BUCKET_LINE',
  'preview rejects duplicate exact batch and bucket lines'
);

select throws_ok(
  $sql$
    select api.preview_stock_disposal(
      '00000000-0000-4000-8000-000000000038'::uuid,
      'DSP-ZERO-001',
      '2026-07-20 12:13:00+07'::timestamptz,
      'DAMAGED_DISPOSAL',
      jsonb_build_array(jsonb_build_object(
        'productId', '38000000-0000-4000-8000-000000000001',
        'batchId', '48000000-0000-4000-8000-000000000001',
        'sourceBucketCode', 'DAMAGED',
        'quantity', 0,
        'sourceLineRef', 'LINE-1'
      )),
      'BA-ZERO-001',
      'Zero quantity fixture.',
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'DISPOSAL_LINE_INVALID',
  'preview rejects non-positive quantity'
);

select throws_ok(
  $sql$
    select api.preview_stock_disposal(
      '00000000-0000-4000-8000-000000000039'::uuid,
      'DSP-CROSS-ORG-001',
      '2026-07-20 12:14:00+07'::timestamptz,
      'EXPIRED_DISPOSAL',
      jsonb_build_array(jsonb_build_object(
        'productId', '38000000-0000-4000-8000-000000000099',
        'batchId', '48000000-0000-4000-8000-000000000099',
        'sourceBucketCode', 'SELLABLE',
        'quantity', 1,
        'sourceLineRef', 'LINE-1'
      )),
      'BA-CROSS-ORG-001',
      'Cross organization fixture.',
      '{}'::jsonb
    )
  $sql$,
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'Admin cannot preview another organization'
);

select throws_ok(
  format(
    $sql$
      select api.post_stock_disposal(
        '00000000-0000-4000-8000-000000000038'::uuid,
        'PGTAP-DSP-CONFIRM-001',
        'DSP-DAMAGED-READY-001',
        '2026-07-20 12:00:00+07'::timestamptz,
        'DAMAGED_DISPOSAL',
        %L::jsonb,
        %L,
        false,
        'BA-Pemusnahan-001',
        'Barang rusak telah dipisahkan dan diverifikasi.',
        '{"test":true}'::jsonb
      )
    $sql$,
    jsonb_build_array(jsonb_build_object(
      'productId', '38000000-0000-4000-8000-000000000001',
      'batchId', '48000000-0000-4000-8000-000000000001',
      'sourceBucketCode', 'DAMAGED',
      'quantity', 3,
      'sourceLineRef', 'LINE-1'
    ))::text,
    (select result ->> 'basisHash' from stock_disposal_results where kind = 'DAMAGED_READY')
  ),
  'P0001',
  'STOCK_DISPOSAL_CONFIRMATION_REQUIRED',
  'posting requires explicit final confirmation'
);

select throws_ok(
  $sql$
    select api.post_stock_disposal(
      '00000000-0000-4000-8000-000000000038'::uuid,
      'PGTAP-DSP-HASH-001',
      'DSP-DAMAGED-READY-001',
      '2026-07-20 12:00:00+07'::timestamptz,
      'DAMAGED_DISPOSAL',
      jsonb_build_array(jsonb_build_object(
        'productId', '38000000-0000-4000-8000-000000000001',
        'batchId', '48000000-0000-4000-8000-000000000001',
        'sourceBucketCode', 'DAMAGED',
        'quantity', 3,
        'sourceLineRef', 'LINE-1'
      )),
      'not-a-hash',
      true,
      'BA-Pemusnahan-001',
      'Barang rusak telah dipisahkan dan diverifikasi.',
      '{"test":true}'::jsonb
    )
  $sql$,
  'P0001',
  'STOCK_DISPOSAL_PREVIEW_HASH_INVALID',
  'posting requires a valid preview basis hash'
);

-- Successful damaged posting.
insert into stock_disposal_results (kind, result)
select 'DAMAGED_POSTED', api.post_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'PGTAP-DSP-DAMAGED-001',
  'DSP-DAMAGED-READY-001',
  '2026-07-20 12:00:00+07'::timestamptz,
  'DAMAGED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000001',
    'batchId', '48000000-0000-4000-8000-000000000001',
    'sourceBucketCode', 'DAMAGED',
    'quantity', 3,
    'sourceLineRef', 'LINE-1'
  )),
  (select result ->> 'basisHash' from stock_disposal_results where kind = 'DAMAGED_READY'),
  true,
  'BA-Pemusnahan-001',
  'Barang rusak telah dipisahkan dan diverifikasi.',
  '{"test":true}'::jsonb
);

select is(
  (select result ->> 'status' from stock_disposal_results where kind = 'DAMAGED_POSTED'),
  'POSTED',
  'damaged disposal posts successfully'
);
select is(
  (select count(*) from operations.stock_disposals
   where source_ref = 'DSP-DAMAGED-READY-001'),
  1::bigint,
  'posting creates one immutable disposal header'
);
select is(
  (select transaction_type_code from inventory.stock_transactions
   where id = (
     select (result ->> 'transactionId')::uuid
     from stock_disposal_results where kind = 'DAMAGED_POSTED'
   )),
  'DISPOSAL',
  'posting creates a DISPOSAL stock transaction'
);
select is(
  (select reason_code_snapshot from inventory.stock_transactions
   where id = (
     select (result ->> 'transactionId')::uuid
     from stock_disposal_results where kind = 'DAMAGED_POSTED'
   )),
  'DAMAGED_DISPOSAL',
  'transaction snapshots the damaged disposal reason'
);
select is(
  (select bucket_code from inventory.stock_ledger_entries
   where transaction_id = (
     select (result ->> 'transactionId')::uuid
     from stock_disposal_results where kind = 'DAMAGED_POSTED'
   )),
  'DAMAGED',
  'ledger consumes the exact selected DAMAGED bucket'
);
select is(
  (select quantity_delta from inventory.stock_ledger_entries
   where transaction_id = (
     select (result ->> 'transactionId')::uuid
     from stock_disposal_results where kind = 'DAMAGED_POSTED'
   )),
  -3::bigint,
  'ledger appends the exact negative quantity'
);
select is(
  (select damaged_qty from inventory.stock_batch_balances
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid
     and batch_id = '48000000-0000-4000-8000-000000000001'::uuid),
  7::bigint,
  'batch damaged projection decreases exactly once'
);
select is(
  (select damaged_qty from inventory.stock_product_positions
   where organization_id = '00000000-0000-4000-8000-000000000038'::uuid
     and product_id = '38000000-0000-4000-8000-000000000001'::uuid),
  7::bigint,
  'product damaged projection decreases exactly once'
);
select is(
  (select bucket_before_qty from operations.stock_disposal_lines
   where disposal_id = (
     select (result ->> 'disposalId')::uuid
     from stock_disposal_results where kind = 'DAMAGED_POSTED'
   )),
  10::bigint,
  'disposal line stores authoritative bucket-before quantity'
);
select is(
  (select bucket_after_qty from operations.stock_disposal_lines
   where disposal_id = (
     select (result ->> 'disposalId')::uuid
     from stock_disposal_results where kind = 'DAMAGED_POSTED'
   )),
  7::bigint,
  'disposal line stores authoritative bucket-after quantity'
);
select is(
  (select ledger_entry_id from operations.stock_disposal_lines
   where disposal_id = (
     select (result ->> 'disposalId')::uuid
     from stock_disposal_results where kind = 'DAMAGED_POSTED'
   )),
  (select id from inventory.stock_ledger_entries
   where transaction_id = (
     select (result ->> 'transactionId')::uuid
     from stock_disposal_results where kind = 'DAMAGED_POSTED'
   )),
  'disposal line links directly to its ledger entry'
);

-- Exact duplicate replay has one domain effect.
insert into stock_disposal_results (kind, result)
select 'DAMAGED_REPLAY', api.post_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'PGTAP-DSP-DAMAGED-001',
  'DSP-DAMAGED-READY-001',
  '2026-07-20 12:00:00+07'::timestamptz,
  'DAMAGED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000001',
    'batchId', '48000000-0000-4000-8000-000000000001',
    'sourceBucketCode', 'DAMAGED',
    'quantity', 3,
    'sourceLineRef', 'LINE-1'
  )),
  (select result ->> 'basisHash' from stock_disposal_results where kind = 'DAMAGED_READY'),
  true,
  'BA-Pemusnahan-001',
  'Barang rusak telah dipisahkan dan diverifikasi.',
  '{"test":true}'::jsonb
);

select is(
  (select result ->> 'disposalId' from stock_disposal_results where kind = 'DAMAGED_REPLAY'),
  (select result ->> 'disposalId' from stock_disposal_results where kind = 'DAMAGED_POSTED'),
  'exact duplicate replay returns the original disposal'
);
select is(
  (select count(*) from operations.stock_disposals
   where source_ref = 'DSP-DAMAGED-READY-001'),
  1::bigint,
  'duplicate replay does not create a second disposal'
);
select is(
  (select count(*) from inventory.stock_ledger_entries
   where transaction_id = (
     select (result ->> 'transactionId')::uuid
     from stock_disposal_results where kind = 'DAMAGED_POSTED'
   )),
  1::bigint,
  'duplicate replay does not append a second ledger effect'
);

select throws_ok(
  format(
    $sql$
      select api.post_stock_disposal(
        '00000000-0000-4000-8000-000000000038'::uuid,
        'PGTAP-DSP-DAMAGED-001',
        'DSP-DAMAGED-READY-001',
        '2026-07-20 12:00:00+07'::timestamptz,
        'DAMAGED_DISPOSAL',
        %L::jsonb,
        %L,
        true,
        'BA-Pemusnahan-001-CHANGED',
        'Changed payload under same key.',
        '{"test":true}'::jsonb
      )
    $sql$,
    jsonb_build_array(jsonb_build_object(
      'productId', '38000000-0000-4000-8000-000000000001',
      'batchId', '48000000-0000-4000-8000-000000000001',
      'sourceBucketCode', 'DAMAGED',
      'quantity', 3,
      'sourceLineRef', 'LINE-1'
    ))::text,
    (select result ->> 'basisHash' from stock_disposal_results where kind = 'DAMAGED_READY')
  ),
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'changed payload under the same idempotency key is rejected'
);

insert into stock_disposal_results (kind, result)
select 'SOURCE_ALREADY_POSTED', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-DAMAGED-READY-001',
  '2026-07-20 12:00:00+07'::timestamptz,
  'DAMAGED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000001',
    'batchId', '48000000-0000-4000-8000-000000000001',
    'sourceBucketCode', 'DAMAGED',
    'quantity', 1,
    'sourceLineRef', 'LINE-1'
  )),
  'BA-Pemusnahan-001',
  'Source already posted fixture.',
  '{"test":true}'::jsonb
);

select is(
  (select result #>> '{blockers,0,code}' from stock_disposal_results where kind = 'SOURCE_ALREADY_POSTED'),
  'DISPOSAL_SOURCE_ALREADY_POSTED',
  'duplicate source reference is blocked by preview'
);

-- Stale preview after an authoritative basis change.
reset role;
update inventory.stock_batch_balances
set quarantine_qty = quarantine_qty + 1, version = version + 1
where organization_id = '00000000-0000-4000-8000-000000000038'::uuid
  and batch_id = '48000000-0000-4000-8000-000000000002'::uuid;
update inventory.stock_product_positions
set quarantine_qty = quarantine_qty + 1, version = version + 1
where organization_id = '00000000-0000-4000-8000-000000000038'::uuid
  and product_id = '38000000-0000-4000-8000-000000000002'::uuid;
set local role authenticated;

select throws_ok(
  format(
    $sql$
      select api.post_stock_disposal(
        '00000000-0000-4000-8000-000000000038'::uuid,
        'PGTAP-DSP-STALE-001',
        'DSP-EXPIRED-QUARANTINE-001',
        '2026-07-20 12:03:00+07'::timestamptz,
        'EXPIRED_DISPOSAL',
        %L::jsonb,
        %L,
        true,
        'BA-Pemusnahan-004',
        'Batch kedaluwarsa dari quarantine.',
        '{"test":true}'::jsonb
      )
    $sql$,
    jsonb_build_array(jsonb_build_object(
      'productId', '38000000-0000-4000-8000-000000000002',
      'batchId', '48000000-0000-4000-8000-000000000002',
      'sourceBucketCode', 'QUARANTINE',
      'quantity', 2,
      'sourceLineRef', 'LINE-1'
    ))::text,
    (select result ->> 'basisHash' from stock_disposal_results where kind = 'EXPIRED_QUARANTINE_READY')
  ),
  'P0001',
  'STALE_STOCK_DISPOSAL_PREVIEW',
  'posting rejects a stale disposal preview'
);

reset role;
update inventory.stock_batch_balances
set quarantine_qty = quarantine_qty - 1, version = version + 1
where organization_id = '00000000-0000-4000-8000-000000000038'::uuid
  and batch_id = '48000000-0000-4000-8000-000000000002'::uuid;
update inventory.stock_product_positions
set quarantine_qty = quarantine_qty - 1, version = version + 1
where organization_id = '00000000-0000-4000-8000-000000000038'::uuid
  and product_id = '38000000-0000-4000-8000-000000000002'::uuid;
set local role authenticated;

select is(
  (select count(*) from operations.stock_disposals
   where source_ref = 'DSP-EXPIRED-QUARANTINE-001'),
  0::bigint,
  'stale posting creates no disposal document'
);

-- Multi-line blocked request remains atomic.
insert into stock_disposal_results (kind, result)
select 'MULTI_BLOCKED', api.preview_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'DSP-MULTI-BLOCKED-001',
  '2026-07-20 12:20:00+07'::timestamptz,
  'EXPIRED_DISPOSAL',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '38000000-0000-4000-8000-000000000002',
      'batchId', '48000000-0000-4000-8000-000000000002',
      'sourceBucketCode', 'QUARANTINE',
      'quantity', 1,
      'sourceLineRef', 'LINE-1'
    ),
    jsonb_build_object(
      'productId', '38000000-0000-4000-8000-000000000004',
      'batchId', '48000000-0000-4000-8000-000000000005',
      'sourceBucketCode', 'SELLABLE',
      'quantity', 1,
      'sourceLineRef', 'LINE-2'
    )
  ),
  'BA-Pemusnahan-013',
  'Satu baris valid dan satu baris arsip.',
  '{"test":true}'::jsonb
);

select throws_ok(
  format(
    $sql$
      select api.post_stock_disposal(
        '00000000-0000-4000-8000-000000000038'::uuid,
        'PGTAP-DSP-MULTI-001',
        'DSP-MULTI-BLOCKED-001',
        '2026-07-20 12:20:00+07'::timestamptz,
        'EXPIRED_DISPOSAL',
        %L::jsonb,
        %L,
        true,
        'BA-Pemusnahan-013',
        'Satu baris valid dan satu baris arsip.',
        '{"test":true}'::jsonb
      )
    $sql$,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '38000000-0000-4000-8000-000000000002',
        'batchId', '48000000-0000-4000-8000-000000000002',
        'sourceBucketCode', 'QUARANTINE',
        'quantity', 1,
        'sourceLineRef', 'LINE-1'
      ),
      jsonb_build_object(
        'productId', '38000000-0000-4000-8000-000000000004',
        'batchId', '48000000-0000-4000-8000-000000000005',
        'sourceBucketCode', 'SELLABLE',
        'quantity', 1,
        'sourceLineRef', 'LINE-2'
      )
    )::text,
    (select result ->> 'basisHash' from stock_disposal_results where kind = 'MULTI_BLOCKED')
  ),
  'P0001',
  'DISPOSAL_BATCH_ARCHIVED',
  'blocked multi-line posting fails atomically'
);
select is(
  (select count(*) from operations.stock_disposals
   where source_ref = 'DSP-MULTI-BLOCKED-001'),
  0::bigint,
  'failed multi-line posting creates no document'
);

-- Post an expired disposal from a BLOCKED batch, then reverse exact batch/bucket.
insert into stock_disposal_results (kind, result)
select 'BLOCKED_BATCH_POSTED', api.post_stock_disposal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'PGTAP-DSP-BLOCKED-001',
  'DSP-BLOCKED-BATCH-001',
  '2026-07-20 12:08:00+07'::timestamptz,
  'EXPIRED_DISPOSAL',
  jsonb_build_array(jsonb_build_object(
    'productId', '38000000-0000-4000-8000-000000000005',
    'batchId', '48000000-0000-4000-8000-000000000006',
    'sourceBucketCode', 'SELLABLE',
    'quantity', 1,
    'sourceLineRef', 'LINE-1'
  )),
  (select result ->> 'basisHash' from stock_disposal_results where kind = 'BLOCKED_BATCH_READY'),
  true,
  'BA-Pemusnahan-009',
  'Batch blocked tetap memiliki stok fisik.',
  '{"test":true}'::jsonb
);

select is(
  (select sellable_qty from inventory.stock_batch_balances
   where batch_id = '48000000-0000-4000-8000-000000000006'::uuid),
  1::bigint,
  'expired disposal posts from the exact blocked batch'
);

insert into stock_disposal_results (kind, result)
select 'DISPOSAL_REVERSAL_PREVIEW', api.preview_stock_transaction_reversal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  (
    select (result ->> 'transactionId')::uuid
    from stock_disposal_results where kind = 'BLOCKED_BATCH_POSTED'
  )
);

select ok(
  (select (result ->> 'eligible')::boolean
   from stock_disposal_results where kind = 'DISPOSAL_REVERSAL_PREVIEW'),
  'generic correction preview supports DISPOSAL'
);
select is(
  (select result #>> '{originalTransaction,transactionTypeCode}'
   from stock_disposal_results where kind = 'DISPOSAL_REVERSAL_PREVIEW'),
  'DISPOSAL',
  'reversal preview identifies the disposal transaction type'
);
select is(
  (select result #>> '{lines,0,batchId}'
   from stock_disposal_results where kind = 'DISPOSAL_REVERSAL_PREVIEW'),
  '48000000-0000-4000-8000-000000000006',
  'reversal preview keeps the exact original batch'
);
select is(
  (select result #>> '{lines,0,bucketCode}'
   from stock_disposal_results where kind = 'DISPOSAL_REVERSAL_PREVIEW'),
  'SELLABLE',
  'reversal preview keeps the exact original bucket'
);
select is(
  (select result #>> '{lines,0,reversalDelta}'
   from stock_disposal_results where kind = 'DISPOSAL_REVERSAL_PREVIEW'),
  '1',
  'reversal preview restores the exact disposed quantity'
);

insert into stock_disposal_results (kind, result)
select 'DISPOSAL_REVERSED', api.reverse_stock_transaction(
  '00000000-0000-4000-8000-000000000038'::uuid,
  'PGTAP-DSP-REVERSAL-001',
  (
    select (result ->> 'transactionId')::uuid
    from stock_disposal_results where kind = 'BLOCKED_BATCH_POSTED'
  ),
  (
    select result ->> 'basisHash'
    from stock_disposal_results where kind = 'DISPOSAL_REVERSAL_PREVIEW'
  ),
  true,
  'Koreksi pemusnahan fixture.',
  '{"test":true}'::jsonb
);

select is(
  (select result ->> 'status' from stock_disposal_results where kind = 'DISPOSAL_REVERSED'),
  'REVERSED',
  'disposal reversal posts successfully'
);
select is(
  (select sellable_qty from inventory.stock_batch_balances
   where batch_id = '48000000-0000-4000-8000-000000000006'::uuid),
  2::bigint,
  'disposal reversal restores the exact original batch bucket'
);
select is(
  (select quantity_delta from inventory.stock_ledger_entries
   where transaction_id = (
     select (result ->> 'reversalTransactionId')::uuid
     from stock_disposal_results where kind = 'DISPOSAL_REVERSED'
   )),
  1::bigint,
  'disposal reversal ledger delta is the exact opposite'
);
select is(
  (select count(*) from inventory.stock_reversal_applications
   where original_transaction_id = (
     select (result ->> 'transactionId')::uuid
     from stock_disposal_results where kind = 'BLOCKED_BATCH_POSTED'
   )),
  1::bigint,
  'disposal reversal stores exact entry linkage'
);

insert into stock_disposal_results (kind, result)
select 'DISPOSAL_REVERSAL_AFTER', api.preview_stock_transaction_reversal(
  '00000000-0000-4000-8000-000000000038'::uuid,
  (
    select (result ->> 'transactionId')::uuid
    from stock_disposal_results where kind = 'BLOCKED_BATCH_POSTED'
  )
);

select is(
  (select result #>> '{blockers,0,code}'
   from stock_disposal_results where kind = 'DISPOSAL_REVERSAL_AFTER'),
  'ORIGINAL_TRANSACTION_ALREADY_REVERSED',
  'second reversal effect is blocked'
);

-- Projection remains reconstructible from append-only ledger.
select is(
  (
    select balance.damaged_qty
    from inventory.stock_batch_balances balance
    where balance.organization_id = '00000000-0000-4000-8000-000000000038'::uuid
      and balance.batch_id = '48000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select coalesce(sum(entry.quantity_delta), 0)::bigint
    from inventory.stock_ledger_entries entry
    where entry.organization_id = '00000000-0000-4000-8000-000000000038'::uuid
      and entry.batch_id = '48000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code = 'DAMAGED'
  ),
  'damaged batch projection equals append-only ledger sum'
);

select is(
  (
    select position.sellable_qty
    from inventory.stock_product_positions position
    where position.organization_id = '00000000-0000-4000-8000-000000000038'::uuid
      and position.product_id = '38000000-0000-4000-8000-000000000005'::uuid
  ),
  (
    select coalesce(sum(entry.quantity_delta), 0)::bigint
    from inventory.stock_ledger_entries entry
    where entry.organization_id = '00000000-0000-4000-8000-000000000038'::uuid
      and entry.product_id = '38000000-0000-4000-8000-000000000005'::uuid
      and entry.bucket_code = 'SELLABLE'
  ),
  'reversed disposal product projection equals ledger sum'
);

-- Candidate view exposes physical queues without mutating stock.
select ok(
  exists (
    select 1
    from api.stock_disposal_candidates candidate
    where candidate.organization_id = '00000000-0000-4000-8000-000000000038'::uuid
      and candidate.batch_id = '48000000-0000-4000-8000-000000000001'::uuid
      and candidate.damaged_qty = 7
  ),
  'candidate view exposes ledger-backed damaged stock'
);
select ok(
  exists (
    select 1
    from api.stock_disposal_candidates candidate
    where candidate.organization_id = '00000000-0000-4000-8000-000000000038'::uuid
      and candidate.batch_id = '48000000-0000-4000-8000-000000000004'::uuid
      and candidate.expiry_date = '2026-07-21'::date
  ),
  'candidate view exposes near-expiry stock as a warning candidate'
);

-- Posted records cannot be edited or deleted, even by the table owner path.
reset role;
select throws_ok(
  $sql$
    update operations.stock_disposals
    set note = 'Mutation forbidden.'
    where source_ref = 'DSP-DAMAGED-READY-001'
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'posted disposal header is immutable'
);
select throws_ok(
  $sql$
    delete from operations.stock_disposal_lines
    where disposal_id = (
      select id from operations.stock_disposals
      where source_ref = 'DSP-DAMAGED-READY-001'
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'posted disposal line is immutable'
);

select ok(
  position(
    'operations.return_' in pg_get_functiondef(
      'inventory.preview_stock_disposal_core(uuid,text,timestamptz,text,jsonb,text,text,jsonb,boolean)'::regprocedure
    )
  ) = 0,
  'disposal preview does not derive inventory from return audit tables'
);

select * from finish();
rollback;
