begin;

create extension if not exists pgtap with schema extensions;

select plan(62);

-- 1-10: tables and safe API views
select has_table('operations'::name, 'stocktakes'::name);
select has_table('operations'::name, 'stocktake_lines'::name);
select has_table('operations'::name, 'stocktake_snapshots'::name);
select has_table('operations'::name, 'stocktake_count_attempts'::name);
select has_view('api'::name, 'stocktake_list'::name);
select has_view('api'::name, 'stocktake_details'::name);
select has_view('api'::name, 'stocktake_review_lines'::name);
select has_view('api'::name, 'stocktake_count_attempts'::name);
select has_view('api'::name, 'stocktake_blind_lines'::name);
select has_view('api'::name, 'stocktake_non_blind_lines'::name);

-- 11-16: core audit columns
select has_column(
  'operations'::name,
  'stocktakes'::name,
  'snapshot_ledger_seq'::name,
  'operations.stocktakes.snapshot_ledger_seq contract'
);
select has_column(
  'operations'::name,
  'stocktake_lines'::name,
  'system_qty_at_snapshot'::name,
  'operations.stocktake_lines.system_qty_at_snapshot contract'
);
select has_column(
  'operations'::name,
  'stocktake_lines'::name,
  'final_attempt_id'::name,
  'operations.stocktake_lines.final_attempt_id contract'
);
select has_column(
  'operations'::name,
  'stocktake_count_attempts'::name,
  'count_cutoff_ledger_seq'::name,
  'operations.stocktake_count_attempts.count_cutoff_ledger_seq contract'
);
select has_column(
  'operations'::name,
  'stocktake_count_attempts'::name,
  'request_hash'::name,
  'operations.stocktake_count_attempts.request_hash contract'
);
select has_column(
  'operations'::name,
  'stocktake_count_attempts'::name,
  'expected_qty_at_count'::name,
  'operations.stocktake_count_attempts.expected_qty_at_count contract'
);

-- 17-20: organization-scoped read policies
select policies_are(
  'operations',
  'stocktakes',
  array['stocktakes_read_current_org']
);
select policies_are(
  'operations',
  'stocktake_lines',
  array['stocktake_lines_read_current_org']
);
select policies_are(
  'operations',
  'stocktake_snapshots',
  array['stocktake_snapshots_read_current_org']
);
select policies_are(
  'operations',
  'stocktake_count_attempts',
  array['stocktake_attempts_read_current_org']
);

-- 21-24: RLS is enabled
select ok(
  (
    select class.relrowsecurity
    from pg_class class
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'stocktakes'
  ),
  'stocktakes has RLS enabled'
);
select ok(
  (
    select class.relrowsecurity
    from pg_class class
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'stocktake_lines'
  ),
  'stocktake lines have RLS enabled'
);
select ok(
  (
    select class.relrowsecurity
    from pg_class class
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'stocktake_snapshots'
  ),
  'stocktake snapshots have RLS enabled'
);
select ok(
  (
    select class.relrowsecurity
    from pg_class class
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'stocktake_count_attempts'
  ),
  'stocktake count attempts have RLS enabled'
);

-- 25-31: authenticated clients can read but cannot write directly
select ok(
  has_table_privilege(
    'authenticated',
    'operations.stocktakes',
    'SELECT'
  ),
  'authenticated can select stocktakes'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.stocktakes',
    'INSERT'
  ),
  'authenticated cannot insert stocktakes directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.stocktakes',
    'UPDATE'
  ),
  'authenticated cannot update stocktakes directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.stocktakes',
    'DELETE'
  ),
  'authenticated cannot delete stocktakes directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.stocktake_lines',
    'INSERT'
  ),
  'authenticated cannot insert stocktake lines directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.stocktake_snapshots',
    'INSERT'
  ),
  'authenticated cannot insert stocktake snapshots directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.stocktake_count_attempts',
    'INSERT'
  ),
  'authenticated cannot insert count attempts directly'
);

create temp table stocktake_baseline (
  ledger_count bigint not null,
  batch_sellable bigint not null,
  product_sellable bigint not null
) on commit drop;

insert into stocktake_baseline (
  ledger_count,
  batch_sellable,
  product_sellable
)
select
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select sellable_qty
    from inventory.stock_batch_balances
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select sellable_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  );

insert into inventory.idempotency_commands (
  id,
  organization_id,
  scope,
  key,
  request_hash,
  status_code,
  started_at,
  completed_at,
  response_snapshot
)
values (
  '74000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'CREATE_STOCKTAKE',
  'PGTAP-STOCKTAKE-CREATE-001',
  repeat('a', 64),
  'SUCCEEDED',
  '2026-07-16 08:00:00+07'::timestamptz,
  '2026-07-16 08:00:01+07'::timestamptz,
  '{"status": "COUNTING"}'::jsonb
);

insert into operations.stocktakes (
  id,
  organization_id,
  stocktake_no,
  title,
  stocktake_type_code,
  mode_code,
  visibility_code,
  status_code,
  scope_definition,
  tolerance_policy_snapshot,
  rule_version,
  timezone_snapshot,
  planned_at,
  snapshot_ledger_seq,
  started_at,
  created_by,
  process_name,
  create_idempotency_command_id,
  note,
  metadata,
  created_at,
  updated_at,
  version_no
)
values (
  '70000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'STK-TEST-001',
  'Stocktake schema contract',
  'CYCLE',
  'CONTINUOUS',
  'BLIND',
  'COUNTING',
  '{
    "mode": "BATCHES",
    "batchIds": ["40000000-0000-4000-8000-000000000001"],
    "bucketCodes": ["SELLABLE"]
  }'::jsonb,
  '{"units": 0, "percent": 0}'::jsonb,
  'stocktake-continuous-v1',
  'Asia/Jakarta',
  '2026-07-16 08:00:00+07'::timestamptz,
  0,
  '2026-07-16 08:00:01+07'::timestamptz,
  null,
  'pgtap.stocktake_schema_contract',
  '74000000-0000-4000-8000-000000000001'::uuid,
  'Schema contract fixture.',
  '{"fixture": true}'::jsonb,
  '2026-07-16 08:00:00+07'::timestamptz,
  '2026-07-16 08:00:01+07'::timestamptz,
  1
);

insert into operations.stocktake_lines (
  id,
  organization_id,
  stocktake_id,
  line_no,
  product_id,
  batch_id,
  bucket_code,
  product_sku_snapshot,
  product_name_snapshot,
  batch_code_snapshot,
  expiry_date_snapshot,
  system_qty_at_snapshot,
  count_status_code,
  review_status_code,
  created_at,
  updated_at,
  version_no
)
values (
  '71000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '70000000-0000-4000-8000-000000000001'::uuid,
  1,
  '30000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'SELLABLE',
  'SER-NIA-30',
  'Serum Niacinamide 30 ml',
  'SER-2608-A',
  '2026-08-01'::date,
  5,
  'PENDING',
  'PENDING',
  '2026-07-16 08:00:01+07'::timestamptz,
  '2026-07-16 08:00:01+07'::timestamptz,
  1
);

insert into operations.stocktake_snapshots (
  id,
  organization_id,
  stocktake_id,
  stocktake_line_id,
  product_id,
  batch_id,
  bucket_code,
  snapshot_ledger_seq,
  system_qty_at_snapshot,
  product_sku_snapshot,
  product_name_snapshot,
  batch_code_snapshot,
  expiry_date_snapshot,
  created_at
)
values (
  '72000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '70000000-0000-4000-8000-000000000001'::uuid,
  '71000000-0000-4000-8000-000000000001'::uuid,
  '30000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'SELLABLE',
  0,
  5,
  'SER-NIA-30',
  'Serum Niacinamide 30 ml',
  'SER-2608-A',
  '2026-08-01'::date,
  '2026-07-16 08:00:01+07'::timestamptz
);

insert into operations.stocktake_count_attempts (
  id,
  organization_id,
  stocktake_id,
  stocktake_line_id,
  attempt_no,
  physical_qty,
  counted_at,
  count_cutoff_ledger_seq,
  expected_qty_at_count,
  variance_qty,
  expected_formula_version,
  counted_by,
  process_name,
  count_method_code,
  zero_confirmed,
  note,
  idempotency_key,
  request_hash,
  status_code,
  created_at
)
values (
  '73000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '70000000-0000-4000-8000-000000000001'::uuid,
  '71000000-0000-4000-8000-000000000001'::uuid,
  1,
  4,
  '2026-07-16 08:15:00+07'::timestamptz,
  0,
  5,
  -1,
  'continuous-ledger-cutoff-v1',
  null,
  'pgtap.stocktake_schema_contract',
  'MANUAL_ENTRY',
  false,
  'Count fixture.',
  'PGTAP-STOCKTAKE-COUNT-001',
  repeat('b', 64),
  'VALID',
  '2026-07-16 08:15:00+07'::timestamptz
);

update operations.stocktake_lines
set
  final_attempt_id =
    '73000000-0000-4000-8000-000000000001'::uuid,
  final_physical_qty = 4,
  expected_qty_at_count = 5,
  variance_qty = -1,
  count_cutoff_ledger_seq = 0,
  expected_formula_version = 'continuous-ledger-cutoff-v1',
  count_attempt_no = 1,
  count_status_code = 'COUNTED',
  review_status_code = 'READY',
  version_no = 2
where id = '71000000-0000-4000-8000-000000000001'::uuid;

-- 32-35: fixture rows satisfy the schema
select is(
  (
    select count(*)
    from operations.stocktakes
    where id = '70000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'one stocktake fixture is stored'
);
select is(
  (
    select count(*)
    from operations.stocktake_lines
    where stocktake_id =
      '70000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'one stocktake line fixture is stored'
);
select is(
  (
    select count(*)
    from operations.stocktake_snapshots
    where stocktake_id =
      '70000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'one immutable snapshot fixture is stored'
);
select is(
  (
    select count(*)
    from operations.stocktake_count_attempts
    where stocktake_line_id =
      '71000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'one immutable count attempt fixture is stored'
);

-- 36-41: blind and non-blind contracts
select hasnt_column(
  'api'::name,
  'stocktake_blind_lines'::name,
  'system_qty_at_snapshot'::name,
  'api.stocktake_blind_lines.system_qty_at_snapshot contract'
);
select hasnt_column(
  'api'::name,
  'stocktake_blind_lines'::name,
  'expected_qty_at_count'::name,
  'api.stocktake_blind_lines.expected_qty_at_count contract'
);
select hasnt_column(
  'api'::name,
  'stocktake_blind_lines'::name,
  'variance_qty'::name,
  'api.stocktake_blind_lines.variance_qty contract'
);
select has_column(
  'api'::name,
  'stocktake_non_blind_lines'::name,
  'system_qty_at_snapshot'::name,
  'api.stocktake_non_blind_lines.system_qty_at_snapshot contract'
);
select has_column(
  'api'::name,
  'stocktake_non_blind_lines'::name,
  'expected_qty_at_count'::name,
  'api.stocktake_non_blind_lines.expected_qty_at_count contract'
);
select has_column(
  'api'::name,
  'stocktake_non_blind_lines'::name,
  'variance_qty'::name,
  'api.stocktake_non_blind_lines.variance_qty contract'
);

-- 42: serialized blind rows do not leak expected quantity
select ok(
  not (
    (
      select to_jsonb(blind_line)
      from api.stocktake_blind_lines blind_line
      where blind_line.stocktake_line_id =
        '71000000-0000-4000-8000-000000000001'::uuid
    ) ? 'expected_qty_at_count'
  ),
  'blind line JSON does not contain expected quantity'
);

-- 43-46: snapshots and attempts are append-only
select throws_ok(
  $sql$
    update operations.stocktake_snapshots
    set system_qty_at_snapshot = 6
    where id =
      '72000000-0000-4000-8000-000000000001'::uuid
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'stocktake snapshots cannot be updated'
);
select throws_ok(
  $sql$
    delete from operations.stocktake_snapshots
    where id =
      '72000000-0000-4000-8000-000000000001'::uuid
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'stocktake snapshots cannot be deleted'
);
select throws_ok(
  $sql$
    update operations.stocktake_count_attempts
    set physical_qty = 5
    where id =
      '73000000-0000-4000-8000-000000000001'::uuid
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'count attempts cannot be updated'
);
select throws_ok(
  $sql$
    delete from operations.stocktake_count_attempts
    where id =
      '73000000-0000-4000-8000-000000000001'::uuid
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'count attempts cannot be deleted'
);

-- 47-51: critical constraints
select throws_ok(
  $sql$
    insert into operations.stocktake_count_attempts (
      organization_id,
      stocktake_id,
      stocktake_line_id,
      attempt_no,
      physical_qty,
      counted_at,
      count_cutoff_ledger_seq,
      expected_qty_at_count,
      variance_qty,
      expected_formula_version,
      process_name,
      count_method_code,
      zero_confirmed,
      idempotency_key,
      request_hash
    )
    values (
      '00000000-0000-4000-8000-000000000001'::uuid,
      '70000000-0000-4000-8000-000000000001'::uuid,
      '71000000-0000-4000-8000-000000000001'::uuid,
      2,
      -1,
      clock_timestamp(),
      0,
      5,
      -6,
      'continuous-ledger-cutoff-v1',
      'pgtap.invalid_negative',
      'MANUAL_ENTRY',
      false,
      'PGTAP-STOCKTAKE-COUNT-NEGATIVE',
      repeat('c', 64)
    )
  $sql$,
  '23514',
  null,
  'negative physical quantity is rejected'
);
select throws_ok(
  $sql$
    insert into operations.stocktake_count_attempts (
      organization_id,
      stocktake_id,
      stocktake_line_id,
      attempt_no,
      physical_qty,
      counted_at,
      count_cutoff_ledger_seq,
      expected_qty_at_count,
      variance_qty,
      expected_formula_version,
      process_name,
      count_method_code,
      zero_confirmed,
      idempotency_key,
      request_hash
    )
    values (
      '00000000-0000-4000-8000-000000000001'::uuid,
      '70000000-0000-4000-8000-000000000001'::uuid,
      '71000000-0000-4000-8000-000000000001'::uuid,
      2,
      0,
      clock_timestamp(),
      0,
      5,
      -5,
      'continuous-ledger-cutoff-v1',
      'pgtap.invalid_zero',
      'MANUAL_ENTRY',
      false,
      'PGTAP-STOCKTAKE-COUNT-ZERO',
      repeat('d', 64)
    )
  $sql$,
  '23514',
  null,
  'zero physical quantity requires explicit confirmation'
);
select throws_ok(
  $sql$
    insert into operations.stocktake_count_attempts (
      organization_id,
      stocktake_id,
      stocktake_line_id,
      attempt_no,
      physical_qty,
      counted_at,
      count_cutoff_ledger_seq,
      expected_qty_at_count,
      variance_qty,
      expected_formula_version,
      process_name,
      count_method_code,
      zero_confirmed,
      idempotency_key,
      request_hash
    )
    values (
      '00000000-0000-4000-8000-000000000001'::uuid,
      '70000000-0000-4000-8000-000000000001'::uuid,
      '71000000-0000-4000-8000-000000000001'::uuid,
      2,
      6,
      clock_timestamp(),
      0,
      5,
      99,
      'continuous-ledger-cutoff-v1',
      'pgtap.invalid_variance',
      'MANUAL_ENTRY',
      false,
      'PGTAP-STOCKTAKE-COUNT-VARIANCE',
      repeat('e', 64)
    )
  $sql$,
  '23514',
  null,
  'variance must equal physical minus expected'
);
select throws_ok(
  $sql$
    insert into inventory.idempotency_commands (
      id,
      organization_id,
      scope,
      key,
      request_hash,
      status_code,
      started_at,
      completed_at,
      response_snapshot
    )
    values (
      '74000000-0000-4000-8000-000000000002'::uuid,
      '00000000-0000-4000-8000-000000000001'::uuid,
      'CREATE_STOCKTAKE',
      'PGTAP-STOCKTAKE-CREATE-FROZEN',
      repeat('f', 64),
      'SUCCEEDED',
      clock_timestamp(),
      clock_timestamp(),
      '{}'::jsonb
    );

    insert into operations.stocktakes (
      organization_id,
      stocktake_no,
      title,
      stocktake_type_code,
      mode_code,
      visibility_code,
      scope_definition,
      timezone_snapshot,
      process_name,
      create_idempotency_command_id
    )
    values (
      '00000000-0000-4000-8000-000000000001'::uuid,
      'STK-TEST-FROZEN',
      'Unsupported frozen fixture',
      'CYCLE',
      'FROZEN',
      'BLIND',
      '{"mode": "ALL_ACTIVE_INVENTORY"}'::jsonb,
      'Asia/Jakarta',
      'pgtap.invalid_frozen',
      '74000000-0000-4000-8000-000000000002'::uuid
    )
  $sql$,
  '23514',
  null,
  'frozen mode is not accepted by the first schema slice'
);
select throws_ok(
  $sql$
    insert into operations.stocktake_lines (
      organization_id,
      stocktake_id,
      line_no,
      product_id,
      batch_id,
      bucket_code,
      product_sku_snapshot,
      product_name_snapshot,
      batch_code_snapshot,
      expiry_date_snapshot,
      system_qty_at_snapshot
    )
    values (
      '00000000-0000-4000-8000-000000000001'::uuid,
      '70000000-0000-4000-8000-000000000001'::uuid,
      2,
      '30000000-0000-4000-8000-000000000001'::uuid,
      '40000000-0000-4000-8000-000000000001'::uuid,
      'SELLABLE',
      'SER-NIA-30',
      'Serum Niacinamide 30 ml',
      'SER-2608-A',
      '2026-08-01'::date,
      5
    )
  $sql$,
  '23505',
  null,
  'duplicate stocktake product batch bucket line is rejected'
);

-- 52-54: schema-only lifecycle remains stock-neutral
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (select ledger_count from stocktake_baseline),
  'schema fixtures do not create ledger entries'
);
select is(
  (
    select sellable_qty
    from inventory.stock_batch_balances
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (select batch_sellable from stocktake_baseline),
  'schema fixtures do not change batch projection'
);
select is(
  (
    select sellable_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (select product_sellable from stocktake_baseline),
  'schema fixtures do not change product projection'
);

-- 55-62: API views preserve blind counting and review visibility
select is(
  (
    select count(*)
    from api.stocktake_list
    where stocktake_id =
      '70000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'stocktake list exposes the session'
);
select is(
  (
    select line_count
    from api.stocktake_list
    where stocktake_id =
      '70000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'stocktake list exposes line count'
);
select is(
  (
    select count(*)
    from api.stocktake_details
    where stocktake_id =
      '70000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'stocktake details expose the session'
);
select is(
  (
    select count(*)
    from api.stocktake_review_lines
    where stocktake_line_id =
      '71000000-0000-4000-8000-000000000001'::uuid
  ),
  0::bigint,
  'blind counting hides review rows until review'
);
select is(
  (
    select count(*)
    from api.stocktake_count_attempts
    where stocktake_line_id =
      '71000000-0000-4000-8000-000000000001'::uuid
  ),
  0::bigint,
  'blind counting hides count attempts until review'
);

update operations.stocktakes
set
  status_code = 'REVIEW',
  counting_completed_at =
    '2026-07-16 08:30:00+07'::timestamptz,
  updated_at =
    '2026-07-16 08:30:00+07'::timestamptz,
  version_no = version_no + 1
where id = '70000000-0000-4000-8000-000000000001'::uuid;

select is(
  (
    select variance_qty
    from api.stocktake_review_lines
    where stocktake_line_id =
      '71000000-0000-4000-8000-000000000001'::uuid
  ),
  -1::bigint,
  'review lines expose the server variance after counting completes'
);
select is(
  (
    select count(*)
    from api.stocktake_count_attempts
    where stocktake_line_id =
      '71000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'count attempt view exposes attempts during review'
);
select is(
  (
    select count(*)
    from api.stocktake_blind_lines
    where stocktake_line_id =
      '71000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'blind line view exposes the blind session line'
);
select * from finish();
rollback;
