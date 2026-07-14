begin;

create extension if not exists pgtap with schema extensions;

select plan(73);

select has_table(
  'operations'::name,
  'stocktake_postings'::name,
  'operations.stocktake_postings exists'
);

select has_table(
  'operations'::name,
  'stocktake_posting_lines'::name,
  'operations.stocktake_posting_lines exists'
);

select function_returns(
  'api',
  'post_stocktake_adjustment',
  array[
    'uuid',
    'text',
    'uuid',
    'bigint',
    'boolean',
    'text',
    'jsonb'
  ]::text[],
  'jsonb'
);

select function_returns(
  'reconciliation',
  'run_post_stocktake_projection_checks',
  array[
    'uuid',
    'uuid',
    'bigint',
    'jsonb'
  ]::text[],
  'jsonb'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.post_stocktake_adjustment(uuid,text,uuid,bigint,boolean,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may post a stocktake adjustment'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.post_stocktake_adjustment(uuid,text,uuid,bigint,boolean,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot post a stocktake adjustment'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'reconciliation.run_post_stocktake_projection_checks(uuid,uuid,bigint,jsonb)',
    'EXECUTE'
  ),
  'authenticated users cannot invoke the trusted reconciliation wrapper'
);

select has_view(
  'api'::name,
  'stocktake_postings'::name,
  'api.stocktake_postings exists'
);

select has_view(
  'api'::name,
  'stocktake_posting_lines'::name,
  'api.stocktake_posting_lines exists'
);

select has_trigger(
  'operations'::name,
  'stocktake_postings'::name,
  'trg_stocktake_postings_immutable'::name,
  'stocktake postings are immutable'
);

select has_trigger(
  'operations'::name,
  'stocktake_posting_lines'::name,
  'trg_stocktake_posting_lines_immutable'::name,
  'stocktake posting lines are immutable'
);

select is(
  (
    select reason.direction_code
    from catalog.movement_reasons reason
    where reason.code = 'STOCKTAKE_ADJUSTMENT'
  ),
  'ADJUSTMENT',
  'generic stocktake adjustment reason is configured'
);

select ok(
  (
    select reason.requires_note
    from catalog.movement_reasons reason
    where reason.code = 'STOCKTAKE_ADJUSTMENT'
  ),
  'generic stocktake adjustment reason requires a transaction note'
);

select ok(
  (
    select reason.is_system and reason.is_active
    from catalog.movement_reasons reason
    where reason.code = 'STOCKTAKE_ADJUSTMENT'
  ),
  'generic stocktake adjustment reason is active system catalog data'
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
values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94000000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.stocktake.posting@glowlab.invalid',
  '2026-07-18 07:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-18 07:00:00+07'::timestamptz,
  '2026-07-18 07:00:00+07'::timestamptz,
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
values (
  '94000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Stocktake Posting Admin',
  'PGTAP-STK-POST',
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
  'PGTAP_STOCKTAKE_POST_OTHER',
  'pgTAP Stocktake Posting Other Organization',
  'Asia/Jakarta',
  true,
  '2026-07-18 07:00:00+07'::timestamptz,
  null
);

create temp table stocktake_posting_fixture_values (
  ledger_seq bigint not null,
  sellable_qty bigint not null,
  quarantine_qty bigint not null,
  damaged_qty bigint not null,
  product_sellable_qty bigint not null,
  product_quarantine_qty bigint not null,
  product_damaged_qty bigint not null,
  transaction_count bigint not null,
  ledger_count bigint not null,
  reconciliation_count bigint not null
) on commit drop;

insert into stocktake_posting_fixture_values
select
  coalesce(max(entry.ledger_seq), 0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.product_id =
      '30000000-0000-4000-8000-000000000001'::uuid
      and entry.batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code = 'SELLABLE'
  ), 0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.product_id =
      '30000000-0000-4000-8000-000000000001'::uuid
      and entry.batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code = 'QUARANTINE'
  ), 0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.product_id =
      '30000000-0000-4000-8000-000000000001'::uuid
      and entry.batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code = 'DAMAGED'
  ), 0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.product_id =
      '30000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code = 'SELLABLE'
  ), 0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.product_id =
      '30000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code = 'QUARANTINE'
  ), 0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.product_id =
      '30000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code = 'DAMAGED'
  ), 0)::bigint,
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select count(*)
    from inventory.stock_ledger_entries ledger_entry
    where ledger_entry.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select count(*)
    from reconciliation.runs run
    where run.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  )
from inventory.stock_ledger_entries entry
where entry.organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid;

grant select on stocktake_posting_fixture_values to authenticated;

create temp table stocktake_posting_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update on stocktake_posting_results to authenticated;

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
values
  (
    '85000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,
    'CREATE_STOCKTAKE',
    'PGTAP-STOCKTAKE-POST-CREATE-001',
    repeat('a', 64),
    'SUCCEEDED',
    '2026-07-18 08:00:00+07'::timestamptz,
    '2026-07-18 08:00:01+07'::timestamptz,
    '{"status":"REVIEW"}'::jsonb
  ),
  (
    '85000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,
    'APPROVE_STOCKTAKE',
    'PGTAP-STOCKTAKE-POST-APPROVE-001',
    repeat('b', 64),
    'SUCCEEDED',
    '2026-07-18 08:10:00+07'::timestamptz,
    '2026-07-18 08:10:01+07'::timestamptz,
    '{"status":"APPROVED"}'::jsonb
  ),
  (
    '85000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,
    'CREATE_STOCKTAKE',
    'PGTAP-STOCKTAKE-ZERO-CREATE-001',
    repeat('c', 64),
    'SUCCEEDED',
    '2026-07-18 08:20:00+07'::timestamptz,
    '2026-07-18 08:20:01+07'::timestamptz,
    '{"status":"REVIEW"}'::jsonb
  ),
  (
    '85000000-0000-4000-8000-000000000004'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,
    'APPROVE_STOCKTAKE',
    'PGTAP-STOCKTAKE-ZERO-APPROVE-001',
    repeat('d', 64),
    'SUCCEEDED',
    '2026-07-18 08:30:00+07'::timestamptz,
    '2026-07-18 08:30:01+07'::timestamptz,
    '{"status":"APPROVED"}'::jsonb
  ),
  (
    '85000000-0000-4000-8000-000000000005'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,
    'CREATE_STOCKTAKE',
    'PGTAP-STOCKTAKE-DRIFT-CREATE-001',
    repeat('e', 64),
    'SUCCEEDED',
    '2026-07-18 08:40:00+07'::timestamptz,
    '2026-07-18 08:40:01+07'::timestamptz,
    '{"status":"REVIEW"}'::jsonb
  ),
  (
    '85000000-0000-4000-8000-000000000006'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,
    'APPROVE_STOCKTAKE',
    'PGTAP-STOCKTAKE-DRIFT-APPROVE-001',
    repeat('f', 64),
    'SUCCEEDED',
    '2026-07-18 08:50:00+07'::timestamptz,
    '2026-07-18 08:50:01+07'::timestamptz,
    '{"status":"APPROVED"}'::jsonb
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
  counting_completed_at,
  created_by,
  process_name,
  create_idempotency_command_id,
  note,
  metadata,
  created_at,
  updated_at,
  version_no
)
select
  '86000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'STK-POST-001',
  'Stocktake mixed posting fixture',
  'CYCLE',
  'CONTINUOUS',
  'BLIND',
  'REVIEW',
  '{"mode":"BATCHES","batchIds":["40000000-0000-4000-8000-000000000001"],"bucketCodes":["SELLABLE","DAMAGED"]}'::jsonb,
  '{"units":0,"percent":0}'::jsonb,
  'stocktake-continuous-v1',
  'Asia/Jakarta',
  '2026-07-18 08:00:00+07'::timestamptz,
  ledger_seq,
  '2026-07-18 08:00:01+07'::timestamptz,
  '2026-07-18 08:10:00+07'::timestamptz,
  null::uuid,
  'pgtap.stocktake_posting',
  '85000000-0000-4000-8000-000000000001'::uuid,
  'Mixed posting fixture.',
  '{"fixture":"mixed-posting"}'::jsonb,
  '2026-07-18 08:00:00+07'::timestamptz,
  '2026-07-18 08:10:00+07'::timestamptz,
  5
from stocktake_posting_fixture_values
union all
select
  '86000000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'STK-ZERO-001',
  'Stocktake zero posting fixture',
  'CYCLE',
  'CONTINUOUS',
  'BLIND',
  'REVIEW',
  '{"mode":"BATCHES","batchIds":["40000000-0000-4000-8000-000000000001"],"bucketCodes":["QUARANTINE"]}'::jsonb,
  '{"units":0,"percent":0}'::jsonb,
  'stocktake-continuous-v1',
  'Asia/Jakarta',
  '2026-07-18 08:20:00+07'::timestamptz,
  ledger_seq,
  '2026-07-18 08:20:01+07'::timestamptz,
  '2026-07-18 08:30:00+07'::timestamptz,
  null::uuid,
  'pgtap.stocktake_zero_posting',
  '85000000-0000-4000-8000-000000000003'::uuid,
  'Zero posting fixture.',
  '{"fixture":"zero-posting"}'::jsonb,
  '2026-07-18 08:20:00+07'::timestamptz,
  '2026-07-18 08:30:00+07'::timestamptz,
  5
from stocktake_posting_fixture_values
union all
select
  '86000000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'STK-DRIFT-001',
  'Stocktake projection drift fixture',
  'CYCLE',
  'CONTINUOUS',
  'BLIND',
  'REVIEW',
  '{"mode":"BATCHES","batchIds":["40000000-0000-4000-8000-000000000001"],"bucketCodes":["SELLABLE"]}'::jsonb,
  '{"units":0,"percent":0}'::jsonb,
  'stocktake-continuous-v1',
  'Asia/Jakarta',
  '2026-07-18 08:40:00+07'::timestamptz,
  ledger_seq,
  '2026-07-18 08:40:01+07'::timestamptz,
  '2026-07-18 08:50:00+07'::timestamptz,
  null::uuid,
  'pgtap.stocktake_drift_posting',
  '85000000-0000-4000-8000-000000000005'::uuid,
  'Projection drift fixture.',
  '{"fixture":"drift-posting"}'::jsonb,
  '2026-07-18 08:40:00+07'::timestamptz,
  '2026-07-18 08:50:00+07'::timestamptz,
  5
from stocktake_posting_fixture_values;

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
  final_physical_qty,
  expected_qty_at_count,
  variance_qty,
  count_cutoff_ledger_seq,
  expected_formula_version,
  count_attempt_no,
  count_status_code,
  review_status_code,
  review_decision_code,
  reason_code,
  review_note,
  created_at,
  updated_at,
  version_no
)
select
  '87000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '86000000-0000-4000-8000-000000000001'::uuid,
  1,
  '30000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'SELLABLE',
  'SER-NIA-30',
  'Serum Niacinamide 30 ml',
  'SER-2608-A',
  '2026-08-01'::date,
  sellable_qty,
  sellable_qty - 1,
  sellable_qty,
  -1,
  ledger_seq,
  'continuous-ledger-cutoff-v1',
  1,
  'COUNTED',
  'REVIEWED',
  'VARIANCE_ACCEPTED',
  'PHYSICAL_LOSS',
  'Physical shortage verified.',
  '2026-07-18 08:01:00+07'::timestamptz,
  '2026-07-18 08:10:00+07'::timestamptz,
  3
from stocktake_posting_fixture_values
union all
select
  '87000000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '86000000-0000-4000-8000-000000000001'::uuid,
  2,
  '30000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'DAMAGED',
  'SER-NIA-30',
  'Serum Niacinamide 30 ml',
  'SER-2608-A',
  '2026-08-01'::date,
  damaged_qty,
  damaged_qty + 1,
  damaged_qty,
  1,
  ledger_seq,
  'continuous-ledger-cutoff-v1',
  1,
  'COUNTED',
  'REVIEWED',
  'VARIANCE_ACCEPTED',
  'PHYSICAL_SURPLUS',
  'Damaged surplus verified.',
  '2026-07-18 08:02:00+07'::timestamptz,
  '2026-07-18 08:10:00+07'::timestamptz,
  3
from stocktake_posting_fixture_values
union all
select
  '87000000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '86000000-0000-4000-8000-000000000002'::uuid,
  1,
  '30000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'QUARANTINE',
  'SER-NIA-30',
  'Serum Niacinamide 30 ml',
  'SER-2608-A',
  '2026-08-01'::date,
  quarantine_qty,
  quarantine_qty,
  quarantine_qty,
  0,
  ledger_seq,
  'continuous-ledger-cutoff-v1',
  1,
  'COUNTED',
  'REVIEWED',
  'MATCHED',
  null::text,
  'Matched quarantine quantity.',
  '2026-07-18 08:21:00+07'::timestamptz,
  '2026-07-18 08:30:00+07'::timestamptz,
  3
from stocktake_posting_fixture_values
union all
select
  '87000000-0000-4000-8000-000000000004'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '86000000-0000-4000-8000-000000000003'::uuid,
  1,
  '30000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'SELLABLE',
  'SER-NIA-30',
  'Serum Niacinamide 30 ml',
  'SER-2608-A',
  '2026-08-01'::date,
  sellable_qty,
  sellable_qty + 1,
  sellable_qty,
  1,
  ledger_seq,
  'continuous-ledger-cutoff-v1',
  1,
  'COUNTED',
  'REVIEWED',
  'VARIANCE_ACCEPTED',
  'PHYSICAL_SURPLUS',
  'Drift fixture surplus.',
  '2026-07-18 08:41:00+07'::timestamptz,
  '2026-07-18 08:50:00+07'::timestamptz,
  3
from stocktake_posting_fixture_values;

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
select
  case line.id
    when '87000000-0000-4000-8000-000000000001'::uuid
      then '88000000-0000-4000-8000-000000000001'::uuid
    when '87000000-0000-4000-8000-000000000002'::uuid
      then '88000000-0000-4000-8000-000000000002'::uuid
  end,
  line.organization_id,
  line.stocktake_id,
  line.id,
  1,
  line.final_physical_qty,
  line.updated_at,
  line.count_cutoff_ledger_seq,
  line.expected_qty_at_count,
  line.variance_qty,
  line.expected_formula_version,
  null::uuid,
  'pgtap.stocktake_posting',
  'MANUAL_ENTRY',
  line.final_physical_qty = 0,
  'Posting fixture attempt.',
  'PGTAP-STOCKTAKE-POST-COUNT-' || line.line_no::text,
  repeat('1', 64),
  'VALID',
  line.updated_at
from operations.stocktake_lines line
where line.stocktake_id =
  '86000000-0000-4000-8000-000000000001'::uuid
union all
select
  '88000000-0000-4000-8000-000000000003'::uuid,
  line.organization_id,
  line.stocktake_id,
  line.id,
  1,
  line.final_physical_qty,
  line.updated_at,
  line.count_cutoff_ledger_seq,
  line.expected_qty_at_count,
  line.variance_qty,
  line.expected_formula_version,
  null::uuid,
  'pgtap.stocktake_zero_posting',
  'MANUAL_ENTRY',
  line.final_physical_qty = 0,
  'Zero fixture attempt.',
  'PGTAP-STOCKTAKE-ZERO-COUNT-001',
  repeat('2', 64),
  'VALID',
  line.updated_at
from operations.stocktake_lines line
where line.stocktake_id =
  '86000000-0000-4000-8000-000000000002'::uuid
union all
select
  '88000000-0000-4000-8000-000000000004'::uuid,
  line.organization_id,
  line.stocktake_id,
  line.id,
  1,
  line.final_physical_qty,
  line.updated_at,
  line.count_cutoff_ledger_seq,
  line.expected_qty_at_count,
  line.variance_qty,
  line.expected_formula_version,
  null::uuid,
  'pgtap.stocktake_drift_posting',
  'MANUAL_ENTRY',
  line.final_physical_qty = 0,
  'Drift fixture attempt.',
  'PGTAP-STOCKTAKE-DRIFT-COUNT-001',
  repeat('3', 64),
  'VALID',
  line.updated_at
from operations.stocktake_lines line
where line.stocktake_id =
  '86000000-0000-4000-8000-000000000003'::uuid;

update operations.stocktake_lines line
set final_attempt_id = attempt.id
from operations.stocktake_count_attempts attempt
where attempt.organization_id = line.organization_id
  and attempt.stocktake_id = line.stocktake_id
  and attempt.stocktake_line_id = line.id;

-- Linking a new final attempt correctly invalidates an earlier review
-- decision. The fixture performs review only after that final attempt
-- has become authoritative.
update operations.stocktake_lines line
set review_decision_code = case
  when line.variance_qty = 0 then 'MATCHED'
  else 'VARIANCE_ACCEPTED'
end
where line.stocktake_id in (
  '86000000-0000-4000-8000-000000000001'::uuid,
  '86000000-0000-4000-8000-000000000002'::uuid,
  '86000000-0000-4000-8000-000000000003'::uuid
);

insert into operations.stocktake_approvals (
  id,
  organization_id,
  stocktake_id,
  approval_version_no,
  approval_hash,
  approved_at,
  approved_by,
  process_name,
  stocktake_version_no,
  snapshot_ledger_seq,
  tolerance_policy_snapshot,
  rule_version,
  line_count,
  variance_line_count,
  total_variance_qty,
  idempotency_command_id,
  note,
  metadata,
  created_at
)
select
  '89000000-0000-4000-8000-000000000001'::uuid,
  stocktake.organization_id,
  stocktake.id,
  1,
  repeat('a', 64),
  '2026-07-18 08:10:01+07'::timestamptz,
  '94000000-0000-4000-8000-000000000001'::uuid,
  null::text,
  5,
  stocktake.snapshot_ledger_seq,
  stocktake.tolerance_policy_snapshot,
  stocktake.rule_version,
  2,
  2,
  0,
  '85000000-0000-4000-8000-000000000002'::uuid,
  'Mixed approval fixture.',
  '{"fixture":"mixed-approval"}'::jsonb,
  '2026-07-18 08:10:01+07'::timestamptz
from operations.stocktakes stocktake
where stocktake.id =
  '86000000-0000-4000-8000-000000000001'::uuid
union all
select
  '89000000-0000-4000-8000-000000000002'::uuid,
  stocktake.organization_id,
  stocktake.id,
  1,
  repeat('b', 64),
  '2026-07-18 08:30:01+07'::timestamptz,
  '94000000-0000-4000-8000-000000000001'::uuid,
  null::text,
  5,
  stocktake.snapshot_ledger_seq,
  stocktake.tolerance_policy_snapshot,
  stocktake.rule_version,
  1,
  0,
  0,
  '85000000-0000-4000-8000-000000000004'::uuid,
  'Zero approval fixture.',
  '{"fixture":"zero-approval"}'::jsonb,
  '2026-07-18 08:30:01+07'::timestamptz
from operations.stocktakes stocktake
where stocktake.id =
  '86000000-0000-4000-8000-000000000002'::uuid
union all
select
  '89000000-0000-4000-8000-000000000003'::uuid,
  stocktake.organization_id,
  stocktake.id,
  1,
  repeat('c', 64),
  '2026-07-18 08:50:01+07'::timestamptz,
  '94000000-0000-4000-8000-000000000001'::uuid,
  null::text,
  5,
  stocktake.snapshot_ledger_seq,
  stocktake.tolerance_policy_snapshot,
  stocktake.rule_version,
  1,
  1,
  1,
  '85000000-0000-4000-8000-000000000006'::uuid,
  'Drift approval fixture.',
  '{"fixture":"drift-approval"}'::jsonb,
  '2026-07-18 08:50:01+07'::timestamptz
from operations.stocktakes stocktake
where stocktake.id =
  '86000000-0000-4000-8000-000000000003'::uuid;

insert into operations.stocktake_approval_lines (
  id,
  organization_id,
  stocktake_id,
  approval_id,
  stocktake_line_id,
  line_no,
  line_version_no,
  review_decision_code,
  final_attempt_id,
  final_physical_qty,
  expected_qty_at_count,
  variance_qty,
  reason_code,
  review_note,
  expected_formula_version,
  count_cutoff_ledger_seq,
  created_at
)
select
  case line.id
    when '87000000-0000-4000-8000-000000000001'::uuid
      then '8a000000-0000-4000-8000-000000000001'::uuid
    when '87000000-0000-4000-8000-000000000002'::uuid
      then '8a000000-0000-4000-8000-000000000002'::uuid
    when '87000000-0000-4000-8000-000000000003'::uuid
      then '8a000000-0000-4000-8000-000000000003'::uuid
    else '8a000000-0000-4000-8000-000000000004'::uuid
  end,
  line.organization_id,
  line.stocktake_id,
  case line.stocktake_id
    when '86000000-0000-4000-8000-000000000001'::uuid
      then '89000000-0000-4000-8000-000000000001'::uuid
    when '86000000-0000-4000-8000-000000000002'::uuid
      then '89000000-0000-4000-8000-000000000002'::uuid
    else '89000000-0000-4000-8000-000000000003'::uuid
  end,
  line.id,
  line.line_no,
  line.version_no,
  line.review_decision_code,
  line.final_attempt_id,
  line.final_physical_qty,
  line.expected_qty_at_count,
  line.variance_qty,
  line.reason_code,
  line.review_note,
  line.expected_formula_version,
  line.count_cutoff_ledger_seq,
  line.updated_at
from operations.stocktake_lines line
where line.stocktake_id in (
  '86000000-0000-4000-8000-000000000001'::uuid,
  '86000000-0000-4000-8000-000000000002'::uuid,
  '86000000-0000-4000-8000-000000000003'::uuid
);

update operations.stocktakes stocktake
set
  status_code = 'APPROVED',
  approved_at = approval.approved_at,
  current_approval_id = approval.id,
  approval_version_no = approval.approval_version_no,
  approved_by = approval.approved_by,
  approval_process_name = approval.process_name,
  updated_at = approval.approved_at,
  version_no = 6
from operations.stocktake_approvals approval
where approval.organization_id = stocktake.organization_id
  and approval.stocktake_id = stocktake.id;

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
    'pgtap.stocktake.posting@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

insert into stocktake_posting_results
select
  'MIXED_POST',
  api.post_stocktake_adjustment(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'stocktake:86000000-0000-4000-8000-000000000001:post:1',
    '86000000-0000-4000-8000-000000000001'::uuid,
    1,
    true,
    'Post the approved mixed stocktake variance.',
    '{"fixture":"mixed-post"}'::jsonb
  );

reset role;

select is(
  (
    select result ->> 'status'
    from stocktake_posting_results
    where kind = 'MIXED_POST'
  ),
  'POSTED',
  'mixed posting returns posted status'
);

select is(
  (
    select stocktake.status_code
    from operations.stocktakes stocktake
    where stocktake.id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'POSTED',
  'mixed posting transitions the stocktake to posted'
);

select ok(
  (
    select stocktake.stock_transaction_id is not null
    from operations.stocktakes stocktake
    where stocktake.id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'posted stocktake links its stock transaction'
);

select ok(
  (
    select stocktake.reconciliation_run_id is not null
    from operations.stocktakes stocktake
    where stocktake.id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'posted stocktake links its reconciliation run'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id =
        '86000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'mixed posting creates one stock transaction header'
);

select is(
  (
    select transaction.transaction_type_code
    from inventory.stock_transactions transaction
    where transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id =
        '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'STOCKTAKE_ADJUSTMENT',
  'stocktake posting uses the stocktake adjustment transaction type'
);

select is(
  (
    select transaction.reason_code_snapshot
    from inventory.stock_transactions transaction
    where transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id =
        '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'STOCKTAKE_ADJUSTMENT',
  'stocktake posting uses the generic header reason'
);

select is(
  (
    select transaction.channel_code_snapshot
    from inventory.stock_transactions transaction
    where transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id =
        '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'SYSTEM',
  'stocktake posting uses the system channel'
);

select is(
  (
    select transaction.source_type_code
    from inventory.stock_transactions transaction
    where transaction.source_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'STOCKTAKE',
  'stocktake posting preserves the stocktake source type'
);

select is(
  (
    select transaction.source_id
    from inventory.stock_transactions transaction
    where transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id =
        '86000000-0000-4000-8000-000000000001'::uuid
  ),
  '86000000-0000-4000-8000-000000000001'::uuid,
  'stocktake posting preserves the stocktake source id'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id =
        '86000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'mixed posting appends one ledger entry per nonzero line'
);

select is(
  (
    select sum(entry.quantity_delta)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id =
        '86000000-0000-4000-8000-000000000001'::uuid
  ),
  0::numeric,
  'mixed gain and loss preserve a net-zero product adjustment'
);

select is(
  (
    select entry.quantity_delta
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_id =
        '86000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code = 'SELLABLE'
  ),
  -1::bigint,
  'sellable shortage appends the approved negative variance'
);

select is(
  (
    select entry.quantity_delta
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_id =
        '86000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code = 'DAMAGED'
  ),
  1::bigint,
  'damaged surplus appends the approved positive variance'
);

select ok(
  (
    select bool_and(entry.entry_role_code = 'ADJUSTMENT')
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'every stocktake ledger entry uses the adjustment role'
);

select is(
  (
    select count(distinct entry.source_line_ref)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'ledger entries retain their stocktake line references'
);

select is(
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and balance.batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select fixture.sellable_qty - 1
    from stocktake_posting_fixture_values fixture
  ),
  'batch sellable projection uses the same negative delta'
);

select is(
  (
    select balance.damaged_qty
    from inventory.stock_batch_balances balance
    where balance.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and balance.batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select fixture.damaged_qty + 1
    from stocktake_posting_fixture_values fixture
  ),
  'batch damaged projection uses the same positive delta'
);

select is(
  (
    select position.sellable_qty
    from inventory.stock_product_positions position
    where position.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select fixture.product_sellable_qty - 1
    from stocktake_posting_fixture_values fixture
  ),
  'product sellable projection uses the same negative delta'
);

select is(
  (
    select position.damaged_qty
    from inventory.stock_product_positions position
    where position.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select fixture.product_damaged_qty + 1
    from stocktake_posting_fixture_values fixture
  ),
  'product damaged projection uses the same positive delta'
);

select is(
  (
    select count(*)
    from operations.stocktake_postings posting
    where posting.stocktake_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'mixed posting stores one immutable posting header'
);

select is(
  (
    select count(*)
    from operations.stocktake_posting_lines posting_line
    where posting_line.stocktake_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'mixed posting snapshots every approval line'
);

select is(
  (
    select posting.nonzero_line_count
    from operations.stocktake_postings posting
    where posting.stocktake_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'mixed posting records the nonzero line count'
);

select ok(
  (
    select
      posting.posting_ledger_seq_after >
      posting.posting_ledger_seq_before
    from operations.stocktake_postings posting
    where posting.stocktake_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'mixed posting stores increasing ledger boundaries'
);

select is(
  (
    select run.run_type_code
    from reconciliation.runs run
    join operations.stocktakes stocktake
      on stocktake.reconciliation_run_id = run.id
    where stocktake.id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'POST_STOCKTAKE',
  'automatic reconciliation is classified as post stocktake'
);

select is(
  (
    select run.trigger_code
    from reconciliation.runs run
    join operations.stocktakes stocktake
      on stocktake.reconciliation_run_id = run.id
    where stocktake.id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'SYSTEM',
  'automatic reconciliation uses the system trigger'
);

select is(
  (
    select run.status_code
    from reconciliation.runs run
    join operations.stocktakes stocktake
      on stocktake.reconciliation_run_id = run.id
    where stocktake.id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'SUCCEEDED',
  'automatic reconciliation completes successfully'
);

select is(
  (
    select run.summary ->> 'integrityStatus'
    from reconciliation.runs run
    join operations.stocktakes stocktake
      on stocktake.reconciliation_run_id = run.id
    where stocktake.id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'CLEAN',
  'automatic reconciliation verifies clean projections'
);

select is(
  (
    select posting.reconciliation_run_id
    from operations.stocktake_postings posting
    where posting.stocktake_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select stocktake.reconciliation_run_id
    from operations.stocktakes stocktake
    where stocktake.id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  'posting and stocktake link the same reconciliation run'
);

select throws_ok(
  $$
    update operations.stocktake_postings
    set note = 'Mutation must fail.'
    where stocktake_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  $$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'stocktake posting headers are immutable'
);

select throws_ok(
  $$
    delete from operations.stocktake_posting_lines
    where stocktake_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  $$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'stocktake posting lines are immutable'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'operations.stocktake_postings',
    'INSERT'
  ),
  'authenticated users cannot insert posting headers directly'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'operations.stocktake_posting_lines',
    'INSERT'
  ),
  'authenticated users cannot insert posting lines directly'
);

set local role authenticated;

insert into stocktake_posting_results
select
  'MIXED_REPLAY',
  api.post_stocktake_adjustment(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'stocktake:86000000-0000-4000-8000-000000000001:post:1',
    '86000000-0000-4000-8000-000000000001'::uuid,
    1,
    true,
    'Post the approved mixed stocktake variance.',
    '{"fixture":"mixed-post"}'::jsonb
  );

reset role;

select is(
  (
    select result
    from stocktake_posting_results
    where kind = 'MIXED_REPLAY'
  ),
  (
    select result
    from stocktake_posting_results
    where kind = 'MIXED_POST'
  ),
  'identical posting retry returns the stored response'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id =
        '86000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'identical posting retry creates no duplicate transaction'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_id =
      '86000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'identical posting retry appends no duplicate ledger entries'
);

select is(
  (
    select count(*)
    from reconciliation.runs run
    where run.run_type_code = 'POST_STOCKTAKE'
      and run.metadata ->> 'stocktakeId' =
        '86000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'identical posting retry creates no duplicate reconciliation run'
);

set local role authenticated;

select throws_ok(
  $$
    select api.post_stocktake_adjustment(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'stocktake:86000000-0000-4000-8000-000000000001:post:1',
      '86000000-0000-4000-8000-000000000001'::uuid,
      1,
      true,
      'Different payload.',
      '{"fixture":"mixed-post"}'::jsonb
    )
  $$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'posting key reuse with another payload is rejected'
);

select throws_ok(
  $$
    select api.post_stocktake_adjustment(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'wrong-key',
      '86000000-0000-4000-8000-000000000003'::uuid,
      1,
      true,
      null,
      '{}'::jsonb
    )
  $$,
  'P0001',
  'STOCKTAKE_POST_IDEMPOTENCY_KEY_INVALID',
  'posting requires the deterministic stocktake key'
);

select throws_ok(
  $$
    select api.post_stocktake_adjustment(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'stocktake:86000000-0000-4000-8000-000000000003:post:2',
      '86000000-0000-4000-8000-000000000003'::uuid,
      2,
      true,
      null,
      '{}'::jsonb
    )
  $$,
  'P0001',
  'STOCKTAKE_APPROVAL_VERSION_CONFLICT',
  'posting rejects a stale approval version'
);

select throws_ok(
  $$
    select api.post_stocktake_adjustment(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'stocktake:86000000-0000-4000-8000-000000000003:post:1',
      '86000000-0000-4000-8000-000000000003'::uuid,
      1,
      false,
      null,
      '{}'::jsonb
    )
  $$,
  'P0001',
  'STOCKTAKE_POST_CONFIRMATION_REQUIRED',
  'posting requires explicit confirmation'
);

select throws_ok(
  $$
    select api.post_stocktake_adjustment(
      '00000000-0000-4000-8000-000000000004'::uuid,
      'stocktake:86000000-0000-4000-8000-000000000003:post:1',
      '86000000-0000-4000-8000-000000000003'::uuid,
      1,
      true,
      null,
      '{}'::jsonb
    )
  $$,
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'cross-organization stocktake posting is denied'
);

reset role;

update inventory.stock_batch_balances balance
set sellable_qty = balance.sellable_qty + 1
where balance.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and balance.batch_id =
    '40000000-0000-4000-8000-000000000001'::uuid;

set local role authenticated;

select throws_ok(
  $$
    select api.post_stocktake_adjustment(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'stocktake:86000000-0000-4000-8000-000000000003:post:1',
      '86000000-0000-4000-8000-000000000003'::uuid,
      1,
      true,
      'Projection drift must block posting.',
      '{"fixture":"drift-post"}'::jsonb
    )
  $$,
  'P0001',
  'STOCKTAKE_PROJECTION_DRIFT',
  'projection drift blocks stocktake posting'
);

reset role;

select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id =
        '86000000-0000-4000-8000-000000000003'::uuid
  ),
  0::bigint,
  'projection drift creates no stock transaction'
);

select is(
  (
    select stocktake.status_code
    from operations.stocktakes stocktake
    where stocktake.id =
      '86000000-0000-4000-8000-000000000003'::uuid
  ),
  'APPROVED',
  'projection drift leaves the stocktake approved'
);

update inventory.stock_batch_balances balance
set sellable_qty = (
  select coalesce(sum(entry.quantity_delta), 0)::bigint
  from inventory.stock_ledger_entries entry
  where entry.organization_id = balance.organization_id
    and entry.product_id = balance.product_id
    and entry.batch_id = balance.batch_id
    and entry.bucket_code = 'SELLABLE'
)
where balance.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and balance.batch_id =
    '40000000-0000-4000-8000-000000000001'::uuid;

set local role authenticated;

insert into stocktake_posting_results
select
  'ZERO_POST',
  api.post_stocktake_adjustment(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'stocktake:86000000-0000-4000-8000-000000000002:post:1',
    '86000000-0000-4000-8000-000000000002'::uuid,
    1,
    true,
    null,
    '{"fixture":"zero-post"}'::jsonb
  );

reset role;

select is(
  (
    select result ->> 'status'
    from stocktake_posting_results
    where kind = 'ZERO_POST'
  ),
  'POSTED',
  'zero-variance posting returns posted status'
);

select is(
  (
    select stocktake.status_code
    from operations.stocktakes stocktake
    where stocktake.id =
      '86000000-0000-4000-8000-000000000002'::uuid
  ),
  'POSTED',
  'zero-variance stocktake transitions to posted'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id =
        '86000000-0000-4000-8000-000000000002'::uuid
  ),
  1::bigint,
  'zero-variance posting still records one transaction header'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_id =
      '86000000-0000-4000-8000-000000000002'::uuid
  ),
  0::bigint,
  'zero-variance posting creates no ledger entry'
);

select is(
  (
    select count(*)
    from operations.stocktake_posting_lines posting_line
    where posting_line.stocktake_id =
      '86000000-0000-4000-8000-000000000002'::uuid
  ),
  1::bigint,
  'zero-variance posting still snapshots its matched line'
);

select ok(
  (
    select posting_line.ledger_entry_id is null
    from operations.stocktake_posting_lines posting_line
    where posting_line.stocktake_id =
      '86000000-0000-4000-8000-000000000002'::uuid
  ),
  'zero-variance posting line has no ledger link'
);

select is(
  (
    select position.quarantine_qty
    from inventory.stock_product_positions position
    where position.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select fixture.product_quarantine_qty
    from stocktake_posting_fixture_values fixture
  ),
  'zero-variance posting does not change projections'
);

select is(
  (
    select run.run_type_code
    from reconciliation.runs run
    join operations.stocktakes stocktake
      on stocktake.reconciliation_run_id = run.id
    where stocktake.id =
      '86000000-0000-4000-8000-000000000002'::uuid
  ),
  'POST_STOCKTAKE',
  'zero-variance posting still creates post-stocktake reconciliation'
);

select is(
  (
    select run.trigger_code
    from reconciliation.runs run
    join operations.stocktakes stocktake
      on stocktake.reconciliation_run_id = run.id
    where stocktake.id =
      '86000000-0000-4000-8000-000000000002'::uuid
  ),
  'SYSTEM',
  'zero-variance reconciliation remains system-triggered'
);

select is(
  (
    select
      count(*) -
      (select fixture.transaction_count
       from stocktake_posting_fixture_values fixture)
    from inventory.stock_transactions transaction
    where transaction.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'two posted stocktakes create exactly two transaction headers'
);

select is(
  (
    select
      count(*) -
      (select fixture.ledger_count
       from stocktake_posting_fixture_values fixture)
    from inventory.stock_ledger_entries entry
    where entry.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'mixed and zero postings append exactly two ledger entries'
);

select is(
  (
    select
      count(*) -
      (select fixture.reconciliation_count
       from stocktake_posting_fixture_values fixture)
    from reconciliation.runs run
    where run.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'two posted stocktakes create exactly two reconciliation runs'
);

select is(
  (
    select posting_line.reason_code
    from operations.stocktake_posting_lines posting_line
    where posting_line.stocktake_line_id =
      '87000000-0000-4000-8000-000000000001'::uuid
  ),
  'PHYSICAL_LOSS',
  'posting audit preserves the approved shortage reason'
);

select is(
  (
    select posting_line.reason_code
    from operations.stocktake_posting_lines posting_line
    where posting_line.stocktake_line_id =
      '87000000-0000-4000-8000-000000000002'::uuid
  ),
  'PHYSICAL_SURPLUS',
  'posting audit preserves the approved surplus reason'
);

select * from finish();

rollback;
