begin;

create extension if not exists pgtap with schema extensions;

select plan(54);

-- Contract, security, and read surfaces.
select has_table(
  'operations',
  'opening_balance_verification_applications',
  'opening balance verification application table exists'
);
select has_view(
  'api',
  'opening_balance_verification_applications',
  'opening balance verification drill-down view exists'
);
select function_returns(
  'inventory',
  'apply_opening_balance_first_verification',
  array[]::text[],
  'trigger'
);
select has_trigger(
  'operations',
  'stocktake_posting_lines',
  'trg_stocktake_posting_lines_opening_balance_verification',
  'stocktake posting lines apply opening balance first verification'
);
select has_trigger(
  'operations',
  'opening_balance_verification_applications',
  'trg_opening_balance_verification_immutable',
  'opening balance verification applications are immutable'
);
select ok(
  (
    select class.relrowsecurity
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'opening_balance_verification_applications'
  ),
  'opening balance verification applications have RLS enabled'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.opening_balance_verification_applications',
    'INSERT'
  ),
  'authenticated users cannot insert verification applications directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.opening_balance_verification_applications',
    'UPDATE'
  ),
  'authenticated users cannot update verification applications directly'
);
select ok(
  has_table_privilege(
    'authenticated',
    'operations.opening_balance_verification_applications',
    'SELECT'
  ),
  'authenticated users may read organization-scoped verification evidence'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'inventory.apply_opening_balance_first_verification()',
    'EXECUTE'
  ),
  'authenticated users cannot invoke the internal verification trigger directly'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    cross join lateral unnest(procedure.proconfig) config(value)
    where namespace.nspname = 'inventory'
      and procedure.proname = 'apply_opening_balance_first_verification'
      and procedure.pronargs = 0
      and config.value =
        'search_path=pg_catalog, auth, app, catalog, inventory, operations'
  ),
  'verification trigger function uses a fixed search_path'
);

-- Isolated organization, Admin, products, and batches.
insert into app.organizations (
  id, code, name, timezone, is_active, created_at, created_by
) values
  (
    '00000000-0000-4000-8000-000000000047'::uuid,
    'PGTAP_OB_VERIFICATION',
    'pgTAP Opening Balance Verification',
    'Asia/Jakarta',
    true,
    clock_timestamp(),
    null
  ),
  (
    '00000000-0000-4000-8000-000000000048'::uuid,
    'PGTAP_OB_VERIFICATION_OTHER',
    'pgTAP Opening Balance Verification Other',
    'Asia/Jakarta',
    true,
    clock_timestamp(),
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
  '94000000-0000-4000-8000-000000000047'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.opening.verification@glowlab.invalid',
  clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  clock_timestamp(),
  clock_timestamp(),
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
  '94000000-0000-4000-8000-000000000047'::uuid,
  '00000000-0000-4000-8000-000000000047'::uuid,
  'pgTAP Opening Verification Admin',
  'PGTAP-OB-VERIFY',
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
    '47000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000047'::uuid,
    'OBV-SERUM',
    'Opening Verification Serum',
    'UNIT', true, true, true, clock_timestamp(), 1
  ),
  (
    '47000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000047'::uuid,
    'OBV-CLEANSER',
    'Opening Verification Cleanser',
    'UNIT', true, true, true, clock_timestamp(), 1
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
    '57000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000047'::uuid,
    '47000000-0000-4000-8000-000000000001'::uuid,
    'OBV-SERUM-A',
    '2026-01-01'::date,
    '2027-01-01'::date,
    clock_timestamp(),
    'ACTIVE', null, clock_timestamp(), clock_timestamp(), 1, 'STANDARD'
  ),
  (
    '57000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000047'::uuid,
    '47000000-0000-4000-8000-000000000002'::uuid,
    'OBV-CLEANSER-A',
    '2026-02-01'::date,
    '2027-02-01'::date,
    clock_timestamp(),
    'ACTIVE', null, clock_timestamp(), clock_timestamp(), 1, 'STANDARD'
  );

create temp table opening_verification_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update on opening_verification_results to authenticated;

select set_config(
  'request.jwt.claim.sub',
  '94000000-0000-4000-8000-000000000047',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '94000000-0000-4000-8000-000000000047',
    'role', 'authenticated',
    'email', 'pgtap.opening.verification@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

insert into opening_verification_results(kind, result)
select
  'CUTOVER_CREATED',
  api.create_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000047'::uuid,
    'OBV-CUTOVER-001',
    clock_timestamp(),
    'OBV-LEGACY-SPREADSHEET',
    'Opening balance verification integration fixture.',
    '{"test":true,"group":"verification"}'::jsonb
  );

insert into opening_verification_results(kind, result)
select
  'CUTOVER_SAVED',
  api.save_opening_balance_cutover_draft(
    '00000000-0000-4000-8000-000000000047'::uuid,
    (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    ),
    1,
    clock_timestamp(),
    'OBV-LEGACY-SPREADSHEET',
    'Opening balance verification integration fixture.',
    jsonb_build_array(
      jsonb_build_object(
        'productId', '47000000-0000-4000-8000-000000000001',
        'batchId', '57000000-0000-4000-8000-000000000001',
        'bucketCode', 'SELLABLE',
        'quantity', 5,
        'sourceLineRef', 'OBV-SERUM-SELLABLE'
      ),
      jsonb_build_object(
        'productId', '47000000-0000-4000-8000-000000000002',
        'batchId', '57000000-0000-4000-8000-000000000002',
        'bucketCode', 'QUARANTINE',
        'quantity', 2,
        'sourceLineRef', 'OBV-CLEANSER-QUARANTINE'
      )
    ),
    '{"test":true,"group":"verification"}'::jsonb
  );

insert into opening_verification_results(kind, result)
select
  'CUTOVER_REVIEW',
  api.submit_opening_balance_cutover_review(
    '00000000-0000-4000-8000-000000000047'::uuid,
    (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    ),
    2
  );

insert into opening_verification_results(kind, result)
select
  'CUTOVER_PREVIEW',
  api.preview_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000047'::uuid,
    (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    )
  );

insert into opening_verification_results(kind, result)
select
  'CUTOVER_POSTED',
  api.post_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000047'::uuid,
    'OBV-CUTOVER-POST-001',
    (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    ),
    (
      select result ->> 'basisHash'
      from opening_verification_results
      where kind = 'CUTOVER_PREVIEW'
    ),
    true
  );

select is(
  (
    select verification_status_code
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    )
  ),
  'UNVERIFIED',
  'posted opening balance starts unverified'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_cutover_lines
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    )
      and quantity > 0
      and verification_status_code = 'UNVERIFIED'
  ),
  '2',
  'both positive opening balance lines start unverified'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '0',
  'posting opening balance alone creates no verification application'
);

reset role;

-- Test helper that creates a complete APPROVED stocktake fixture from line specs.
create or replace function pg_temp.create_approved_stocktake_fixture(
  p_organization_id uuid,
  p_stocktake_id uuid,
  p_stocktake_no text,
  p_counted_at timestamptz,
  p_lines jsonb
)
returns jsonb
language plpgsql
set search_path =
  pg_catalog,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
declare
  v_create_command_id uuid := gen_random_uuid();
  v_approve_command_id uuid := gen_random_uuid();
  v_approval_id uuid := gen_random_uuid();
  v_cutoff bigint;
  v_line_count bigint;
  v_variance_line_count bigint;
  v_total_variance bigint;
  v_spec jsonb;
  v_line_no integer := 0;
  v_line_id uuid;
  v_attempt_id uuid;
  v_product_id uuid;
  v_batch_id uuid;
  v_bucket_code text;
  v_expected_qty bigint;
  v_variance_qty bigint;
  v_physical_qty bigint;
  v_product_sku text;
  v_product_name text;
  v_batch_code text;
  v_expiry_date date;
  v_reason_code text;
  v_decision_code text;
  v_review_note text;
begin
  if jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) = 0 then
    raise exception using errcode = 'P0001', message = 'TEST_LINES_REQUIRED';
  end if;

  select coalesce(max(entry.ledger_seq), 0)::bigint
  into v_cutoff
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  v_line_count := jsonb_array_length(p_lines);

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
  ) values
    (
      v_create_command_id,
      p_organization_id,
      'CREATE_STOCKTAKE',
      p_stocktake_no || ':create',
      encode(
        extensions.digest(
          convert_to(p_stocktake_no || ':create', 'UTF8'),
          'sha256'
        ),
        'hex'
      ),
      'SUCCEEDED',
      p_counted_at - interval '20 minutes',
      p_counted_at - interval '19 minutes',
      '{"status":"REVIEW"}'::jsonb
    ),
    (
      v_approve_command_id,
      p_organization_id,
      'APPROVE_STOCKTAKE',
      p_stocktake_no || ':approve',
      encode(
        extensions.digest(
          convert_to(p_stocktake_no || ':approve', 'UTF8'),
          'sha256'
        ),
        'hex'
      ),
      'SUCCEEDED',
      p_counted_at - interval '5 minutes',
      p_counted_at - interval '4 minutes',
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
  ) values (
    p_stocktake_id,
    p_organization_id,
    p_stocktake_no,
    'Opening balance verification fixture ' || p_stocktake_no,
    'CYCLE',
    'CONTINUOUS',
    'BLIND',
    'REVIEW',
    jsonb_build_object('mode', 'VERIFICATION_FIXTURE'),
    '{"units":0,"percent":0}'::jsonb,
    'stocktake-continuous-v1',
    'Asia/Jakarta',
    p_counted_at - interval '30 minutes',
    v_cutoff,
    p_counted_at - interval '20 minutes',
    p_counted_at,
    null,
    'pgtap.opening_balance_verification',
    v_create_command_id,
    'Opening balance verification stocktake fixture.',
    jsonb_build_object('test', true, 'fixture', p_stocktake_no),
    p_counted_at - interval '30 minutes',
    p_counted_at,
    5
  );

  for v_spec in
    select value
    from jsonb_array_elements(p_lines)
  loop
    v_line_no := v_line_no + 1;
    v_line_id := gen_random_uuid();
    v_attempt_id := gen_random_uuid();
    v_product_id := (v_spec ->> 'productId')::uuid;
    v_batch_id := (v_spec ->> 'batchId')::uuid;
    v_bucket_code := upper(btrim(v_spec ->> 'bucketCode'));
    v_variance_qty := coalesce((v_spec ->> 'varianceQty')::bigint, 0);

    select
      product.sku,
      product.name,
      batch.batch_code,
      batch.expiry_date
    into
      v_product_sku,
      v_product_name,
      v_batch_code,
      v_expiry_date
    from catalog.products product
    join catalog.product_batches batch
      on batch.organization_id = product.organization_id
     and batch.product_id = product.id
    where product.organization_id = p_organization_id
      and product.id = v_product_id
      and batch.id = v_batch_id;

    if not found then
      raise exception using errcode = 'P0001', message = 'TEST_BATCH_NOT_FOUND';
    end if;

    select coalesce(sum(entry.quantity_delta), 0)::bigint
    into v_expected_qty
    from inventory.stock_ledger_entries entry
    where entry.organization_id = p_organization_id
      and entry.product_id = v_product_id
      and entry.batch_id = v_batch_id
      and entry.bucket_code = v_bucket_code
      and entry.ledger_seq <= v_cutoff;

    v_physical_qty := v_expected_qty + v_variance_qty;

    if v_physical_qty < 0 then
      raise exception using errcode = 'P0001', message = 'TEST_NEGATIVE_PHYSICAL_QTY';
    end if;

    if v_variance_qty = 0 then
      v_reason_code := null;
      v_decision_code := 'MATCHED';
      v_review_note := 'Physical count matches ledger quantity.';
    elsif v_variance_qty > 0 then
      v_reason_code := 'PHYSICAL_SURPLUS';
      v_decision_code := 'VARIANCE_ACCEPTED';
      v_review_note := 'Physical surplus accepted for verification fixture.';
    else
      v_reason_code := 'PHYSICAL_LOSS';
      v_decision_code := 'VARIANCE_ACCEPTED';
      v_review_note := 'Physical shortage accepted for verification fixture.';
    end if;

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
    ) values (
      v_line_id,
      p_organization_id,
      p_stocktake_id,
      v_line_no,
      v_product_id,
      v_batch_id,
      v_bucket_code,
      v_product_sku,
      v_product_name,
      v_batch_code,
      v_expiry_date,
      v_expected_qty,
      v_physical_qty,
      v_expected_qty,
      v_variance_qty,
      v_cutoff,
      'continuous-ledger-cutoff-v1',
      1,
      'COUNTED',
      'PENDING',
      null,
      null,
      null,
      p_counted_at - interval '10 minutes',
      p_counted_at,
      1
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
    ) values (
      v_attempt_id,
      p_organization_id,
      p_stocktake_id,
      v_line_id,
      1,
      v_physical_qty,
      p_counted_at,
      v_cutoff,
      v_expected_qty,
      v_variance_qty,
      'continuous-ledger-cutoff-v1',
      null,
      'pgtap.opening_balance_verification',
      'MANUAL_ENTRY',
      v_physical_qty = 0,
      'Opening balance verification count evidence.',
      p_stocktake_no || ':count:' || v_line_no::text,
      encode(
        extensions.digest(
          convert_to(
            p_stocktake_no || ':count:' || v_line_no::text,
            'UTF8'
          ),
          'sha256'
        ),
        'hex'
      ),
      'VALID',
      p_counted_at
    );

    update operations.stocktake_lines line
    set
      final_attempt_id = v_attempt_id,
      updated_at = p_counted_at,
      version_no = 2
    where line.organization_id = p_organization_id
      and line.stocktake_id = p_stocktake_id
      and line.id = v_line_id;

    update operations.stocktake_lines line
    set
      review_status_code = 'REVIEWED',
      review_decision_code = v_decision_code,
      reason_code = v_reason_code,
      review_note = v_review_note,
      updated_at = p_counted_at,
      version_no = 3
    where line.organization_id = p_organization_id
      and line.stocktake_id = p_stocktake_id
      and line.id = v_line_id;
  end loop;

  select
    count(*) filter (where line.variance_qty <> 0),
    coalesce(sum(line.variance_qty), 0)::bigint
  into
    v_variance_line_count,
    v_total_variance
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id;

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
  ) values (
    v_approval_id,
    p_organization_id,
    p_stocktake_id,
    1,
    encode(
      extensions.digest(
        convert_to(p_stocktake_no || ':approval:1', 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    p_counted_at,
    null,
    'pgtap.opening_balance_verification',
    5,
    v_cutoff,
    '{"units":0,"percent":0}'::jsonb,
    'stocktake-continuous-v1',
    v_line_count,
    v_variance_line_count,
    v_total_variance,
    v_approve_command_id,
    'Opening balance verification approval fixture.',
    jsonb_build_object('test', true, 'fixture', p_stocktake_no),
    p_counted_at
  );

  insert into operations.stocktake_approval_lines (
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
    line.organization_id,
    line.stocktake_id,
    v_approval_id,
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
    p_counted_at
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
  order by line.line_no;

  update operations.stocktakes stocktake
  set
    status_code = 'APPROVED',
    approved_at = p_counted_at,
    current_approval_id = v_approval_id,
    approval_version_no = 1,
    approved_by = null,
    approval_process_name = 'pgtap.opening_balance_verification',
    updated_at = p_counted_at,
    version_no = 6
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id;

  return jsonb_build_object(
    'stocktakeId', p_stocktake_id,
    'approvalId', v_approval_id,
    'approvalVersion', 1,
    'countCutoffLedgerSeq', v_cutoff,
    'lineCount', v_line_count
  );
end;
$$;

-- A two-line stocktake must roll back verification atomically when the second
-- verification insert fails.
insert into opening_verification_results(kind, result)
select
  'ROLLBACK_FIXTURE',
  pg_temp.create_approved_stocktake_fixture(
    '00000000-0000-4000-8000-000000000047'::uuid,
    '67000000-0000-4000-8000-000000000001'::uuid,
    'OBV-STK-ROLLBACK-001',
    (
      select posted_at + interval '1 microsecond'
      from operations.opening_balance_cutovers
      where id = (
        select (result ->> 'cutoverId')::uuid
        from opening_verification_results
        where kind = 'CUTOVER_CREATED'
      )
    ),
    jsonb_build_array(
      jsonb_build_object(
        'productId', '47000000-0000-4000-8000-000000000001',
        'batchId', '57000000-0000-4000-8000-000000000001',
        'bucketCode', 'SELLABLE',
        'varianceQty', 0
      ),
      jsonb_build_object(
        'productId', '47000000-0000-4000-8000-000000000002',
        'batchId', '57000000-0000-4000-8000-000000000002',
        'bucketCode', 'QUARANTINE',
        'varianceQty', 0
      )
    )
  );

create or replace function pg_temp.reject_quarantine_verification()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.bucket_code = 'QUARANTINE' then
    raise exception using errcode = 'P0001', message = 'TEST_VERIFICATION_FAILURE';
  end if;

  return new;
end;
$$;

create trigger trg_test_reject_quarantine_verification
before insert
on operations.opening_balance_verification_applications
for each row execute function pg_temp.reject_quarantine_verification();

set local role authenticated;

select throws_ok(
  $$
    select api.post_stocktake_adjustment(
      '00000000-0000-4000-8000-000000000047'::uuid,
      'stocktake:67000000-0000-4000-8000-000000000001:post:1',
      '67000000-0000-4000-8000-000000000001'::uuid,
      1,
      true,
      'Atomic verification rollback fixture.',
      '{"test":true}'::jsonb
    )
  $$,
  'P0001',
  'TEST_VERIFICATION_FAILURE',
  'verification failure rolls back the complete stocktake posting'
);

reset role;

drop trigger trg_test_reject_quarantine_verification
on operations.opening_balance_verification_applications;
drop function pg_temp.reject_quarantine_verification();

select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '0',
  'failed multi-line posting leaves no partial verification application'
);
select is(
  (
    select status_code
    from operations.stocktakes
    where id = '67000000-0000-4000-8000-000000000001'::uuid
  ),
  'APPROVED',
  'failed verification restores stocktake state through transaction rollback'
);
select is(
  (
    select count(*)::text
    from operations.stocktake_postings
    where stocktake_id =
      '67000000-0000-4000-8000-000000000001'::uuid
  ),
  '0',
  'failed verification leaves no stocktake posting header'
);

-- A physical count taken before the opening-balance cutover cannot verify it.
insert into opening_verification_results(kind, result)
select
  'PRE_CUTOVER_FIXTURE',
  pg_temp.create_approved_stocktake_fixture(
    '00000000-0000-4000-8000-000000000047'::uuid,
    '67000000-0000-4000-8000-000000000002'::uuid,
    'OBV-STK-PRE-CUTOVER-001',
    (
      select posted_at - interval '1 microsecond'
      from operations.opening_balance_cutovers
      where id = (
        select (result ->> 'cutoverId')::uuid
        from opening_verification_results
        where kind = 'CUTOVER_CREATED'
      )
    ),
    jsonb_build_array(jsonb_build_object(
      'productId', '47000000-0000-4000-8000-000000000001',
      'batchId', '57000000-0000-4000-8000-000000000001',
      'bucketCode', 'SELLABLE',
      'varianceQty', 0
    ))
  );

set local role authenticated;

insert into opening_verification_results(kind, result)
select
  'PRE_CUTOVER_POSTED',
  api.post_stocktake_adjustment(
    '00000000-0000-4000-8000-000000000047'::uuid,
    'stocktake:67000000-0000-4000-8000-000000000002:post:1',
    '67000000-0000-4000-8000-000000000002'::uuid,
    1,
    true,
    'Pre-cutover count must not verify opening balance.',
    '{"test":true}'::jsonb
  );

select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '0',
  'posted stocktake with pre-cutover count evidence does not verify'
);

reset role;

-- A different bucket remains unrelated to the opening-balance lines.
insert into opening_verification_results(kind, result)
select
  'UNMATCHED_FIXTURE',
  pg_temp.create_approved_stocktake_fixture(
    '00000000-0000-4000-8000-000000000047'::uuid,
    '67000000-0000-4000-8000-000000000003'::uuid,
    'OBV-STK-UNMATCHED-001',
    (
      select posted_at + interval '1 microsecond'
      from operations.opening_balance_cutovers
      where id = (
        select (result ->> 'cutoverId')::uuid
        from opening_verification_results
        where kind = 'CUTOVER_CREATED'
      )
    ),
    jsonb_build_array(jsonb_build_object(
      'productId', '47000000-0000-4000-8000-000000000001',
      'batchId', '57000000-0000-4000-8000-000000000001',
      'bucketCode', 'DAMAGED',
      'varianceQty', 0
    ))
  );

set local role authenticated;

insert into opening_verification_results(kind, result)
select
  'UNMATCHED_POSTED',
  api.post_stocktake_adjustment(
    '00000000-0000-4000-8000-000000000047'::uuid,
    'stocktake:67000000-0000-4000-8000-000000000003:post:1',
    '67000000-0000-4000-8000-000000000003'::uuid,
    1,
    true,
    'Different bucket must not verify opening balance.',
    '{"test":true}'::jsonb
  );

select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '0',
  'different product-batch-bucket scope does not verify opening balance'
);

reset role;

-- The first exact SELLABLE count verifies one line even with zero variance.
insert into opening_verification_results(kind, result)
select
  'PARTIAL_FIXTURE',
  pg_temp.create_approved_stocktake_fixture(
    '00000000-0000-4000-8000-000000000047'::uuid,
    '67000000-0000-4000-8000-000000000004'::uuid,
    'OBV-STK-PARTIAL-001',
    (
      select posted_at + interval '1 microsecond'
      from operations.opening_balance_cutovers
      where id = (
        select (result ->> 'cutoverId')::uuid
        from opening_verification_results
        where kind = 'CUTOVER_CREATED'
      )
    ),
    jsonb_build_array(jsonb_build_object(
      'productId', '47000000-0000-4000-8000-000000000001',
      'batchId', '57000000-0000-4000-8000-000000000001',
      'bucketCode', 'SELLABLE',
      'varianceQty', 0
    ))
  );

set local role authenticated;

insert into opening_verification_results(kind, result)
select
  'PARTIAL_POSTED',
  api.post_stocktake_adjustment(
    '00000000-0000-4000-8000-000000000047'::uuid,
    'stocktake:67000000-0000-4000-8000-000000000004:post:1',
    '67000000-0000-4000-8000-000000000004'::uuid,
    1,
    true,
    'Zero-variance opening balance verification.',
    '{"test":true}'::jsonb
  );

select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '1',
  'first exact posted stocktake creates one verification application'
);
select is(
  (
    select bucket_code
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  'SELLABLE',
  'verification matches the exact physical bucket'
);
select is(
  (
    select stocktake_variance_quantity::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '0',
  'zero-variance physical count still verifies the opening balance line'
);
select is(
  (
    select count(*)::text
    from operations.stocktake_posting_lines posting_line
    join operations.opening_balance_verification_applications application
      on application.stocktake_posting_line_id = posting_line.id
    where application.organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and posting_line.ledger_entry_id is null
  ),
  '1',
  'zero-variance verification does not manufacture a ledger entry'
);
select is(
  (
    select verification_status_code
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    )
  ),
  'PARTIALLY_VERIFIED',
  'cutover becomes partially verified after one of two positive lines'
);
select is(
  (
    select verified_line_count::text
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    )
  ),
  '1',
  'cutover read model counts one verified line'
);
select is(
  (
    select unverified_line_count::text
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    )
  ),
  '1',
  'cutover read model leaves one line unverified'
);
select is(
  (
    select verification_status_code
    from api.opening_balance_cutover_lines
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and source_line_ref = 'OBV-SERUM-SELLABLE'
  ),
  'VERIFIED',
  'matching opening balance line exposes VERIFIED'
);
select is(
  (
    select verification_status_code
    from api.opening_balance_cutover_lines
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and source_line_ref = 'OBV-CLEANSER-QUARANTINE'
  ),
  'UNVERIFIED',
  'partial stocktake scope leaves unrelated opening balance line unverified'
);
select ok(
  (
    select verifying_stocktake_id =
      '67000000-0000-4000-8000-000000000004'::uuid
      and verifying_stocktake_approval_id is not null
      and verifying_stocktake_posting_id is not null
      and verifying_stocktake_posting_line_id is not null
      and verifying_stocktake_line_id is not null
      and verifying_count_attempt_id is not null
    from api.opening_balance_cutover_lines
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and source_line_ref = 'OBV-SERUM-SELLABLE'
  ),
  'verified line read model preserves complete stocktake evidence linkage'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and stocktake_id =
        '67000000-0000-4000-8000-000000000004'::uuid
  ),
  '1',
  'verification drill-down exposes the first matching stocktake'
);

insert into opening_verification_results(kind, result)
select
  'PARTIAL_REPLAY',
  api.post_stocktake_adjustment(
    '00000000-0000-4000-8000-000000000047'::uuid,
    'stocktake:67000000-0000-4000-8000-000000000004:post:1',
    '67000000-0000-4000-8000-000000000004'::uuid,
    1,
    true,
    'Zero-variance opening balance verification.',
    '{"test":true}'::jsonb
  );

select is(
  (
    select result
    from opening_verification_results
    where kind = 'PARTIAL_REPLAY'
  ),
  (
    select result
    from opening_verification_results
    where kind = 'PARTIAL_POSTED'
  ),
  'identical stocktake posting replay returns the saved response'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '1',
  'idempotent stocktake replay creates no second verification effect'
);
select is(
  (
    select count(*)::text
    from operations.stocktake_postings
    where stocktake_id =
      '67000000-0000-4000-8000-000000000004'::uuid
  ),
  '1',
  'idempotent stocktake replay creates no second posting'
);

reset role;

-- A later exact QUARANTINE count verifies the remaining line.
insert into opening_verification_results(kind, result)
select
  'FULL_FIXTURE',
  pg_temp.create_approved_stocktake_fixture(
    '00000000-0000-4000-8000-000000000047'::uuid,
    '67000000-0000-4000-8000-000000000005'::uuid,
    'OBV-STK-FULL-001',
    (
      select posted_at + interval '2 microseconds'
      from operations.opening_balance_cutovers
      where id = (
        select (result ->> 'cutoverId')::uuid
        from opening_verification_results
        where kind = 'CUTOVER_CREATED'
      )
    ),
    jsonb_build_array(jsonb_build_object(
      'productId', '47000000-0000-4000-8000-000000000002',
      'batchId', '57000000-0000-4000-8000-000000000002',
      'bucketCode', 'QUARANTINE',
      'varianceQty', 1
    ))
  );

set local role authenticated;

insert into opening_verification_results(kind, result)
select
  'FULL_POSTED',
  api.post_stocktake_adjustment(
    '00000000-0000-4000-8000-000000000047'::uuid,
    'stocktake:67000000-0000-4000-8000-000000000005:post:1',
    '67000000-0000-4000-8000-000000000005'::uuid,
    1,
    true,
    'Nonzero verification line remains a normal stocktake adjustment.',
    '{"test":true}'::jsonb
  );

select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '2',
  'second exact scope verifies the remaining opening balance line'
);
select is(
  (
    select verification_status_code
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    )
  ),
  'VERIFIED',
  'cutover becomes fully verified after all positive lines are counted'
);
select is(
  (
    select verified_line_count::text
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    )
  ),
  '2',
  'fully verified cutover reports all positive lines verified'
);
select is(
  (
    select unverified_line_count::text
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_verification_results
      where kind = 'CUTOVER_CREATED'
    )
  ),
  '0',
  'fully verified cutover reports no unverified positive lines'
);
select is(
  (
    select stocktake_variance_quantity::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and bucket_code = 'QUARANTINE'
  ),
  '1',
  'verification preserves the ordinary nonzero stocktake variance'
);
select ok(
  (
    select posting_line.ledger_entry_id is not null
    from operations.opening_balance_verification_applications application
    join operations.stocktake_posting_lines posting_line
      on posting_line.id = application.stocktake_posting_line_id
    where application.organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and application.bucket_code = 'QUARANTINE'
  ),
  'nonzero stocktake variance keeps its normal adjustment ledger entry'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_cutover_lines
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and quantity > 0
      and verification_status_code = 'VERIFIED'
  ),
  '2',
  'both positive line read models expose VERIFIED'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications application
    join operations.stocktake_count_attempts attempt
      on attempt.id = application.count_attempt_id
     and attempt.organization_id = application.organization_id
     and attempt.stocktake_line_id = application.stocktake_line_id
    join operations.stocktake_posting_lines posting_line
      on posting_line.id = application.stocktake_posting_line_id
     and posting_line.stocktake_line_id = application.stocktake_line_id
    join operations.stocktake_postings posting
      on posting.id = application.stocktake_posting_id
     and posting.stocktake_id = application.stocktake_id
     and posting.approval_id = application.stocktake_approval_id
    where application.organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '2',
  'every verification application has complete count, line, posting, and approval linkage'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications application
    join operations.opening_balance_cutover_lines line
      on line.id = application.opening_balance_line_id
     and line.organization_id = application.organization_id
     and line.cutover_id = application.opening_balance_cutover_id
     and line.product_id = application.product_id
     and line.batch_id = application.batch_id
     and line.bucket_code = application.bucket_code
    where application.organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '2',
  'every verification application matches the exact opening balance scope'
);
select ok(
  not exists (
    select 1
    from operations.opening_balance_verification_applications application
    where application.organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and application.count_cutoff_ledger_seq <
          application.opening_balance_ledger_seq_after
  ),
  'every verification count covers the opening balance ledger boundary'
);
select is(
  (
    select count(distinct opening_balance_line_id)::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '2',
  'each opening balance line receives at most one first-verification effect'
);

reset role;

update app.user_profiles profile
set organization_id = '00000000-0000-4000-8000-000000000048'::uuid
where profile.user_id = '94000000-0000-4000-8000-000000000047'::uuid;

set local role authenticated;

select is(
  (
    select count(*)::text
    from api.opening_balance_verification_applications
  ),
  '0',
  'RLS hides opening balance verification evidence from another organization'
);

reset role;

update app.user_profiles profile
set organization_id = '00000000-0000-4000-8000-000000000047'::uuid
where profile.user_id = '94000000-0000-4000-8000-000000000047'::uuid;

set local role authenticated;

select throws_ok(
  $$
    insert into operations.opening_balance_verification_applications (
      organization_id,
      opening_balance_cutover_id,
      opening_balance_line_id,
      stocktake_id,
      stocktake_approval_id,
      approval_version_no,
      stocktake_posting_id,
      stocktake_posting_line_id,
      stocktake_line_id,
      count_attempt_id,
      product_id,
      batch_id,
      bucket_code,
      opening_balance_quantity,
      physical_quantity,
      stocktake_variance_quantity,
      count_cutoff_ledger_seq,
      opening_balance_ledger_seq_after,
      verified_at,
      verified_by,
      process_name
    ) values (
      gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
      gen_random_uuid(), gen_random_uuid(), 1, gen_random_uuid(),
      gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
      gen_random_uuid(), gen_random_uuid(), 'SELLABLE', 1, 1, 0,
      1, 1, clock_timestamp(),
      '94000000-0000-4000-8000-000000000047'::uuid, null
    )
  $$,
  '42501',
  'permission denied for table opening_balance_verification_applications',
  'authenticated direct verification insertion is denied'
);

reset role;

select throws_ok(
  $$
    update operations.opening_balance_verification_applications
    set metadata = metadata || '{"tampered":true}'::jsonb
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  $$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'verification applications cannot be updated'
);
select throws_ok(
  $$
    delete from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  $$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'verification applications cannot be deleted'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications
    where organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
  ),
  '2',
  'immutability failures leave verification history intact'
);
select is(
  (
    select count(*)::text
    from inventory.stock_ledger_entries entry
    join inventory.stock_batch_balances balance
      on balance.organization_id = entry.organization_id
     and balance.product_id = entry.product_id
     and balance.batch_id = entry.batch_id
    where entry.organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and (
        balance.sellable_qty <> (
          select coalesce(sum(scope_entry.quantity_delta), 0)::bigint
          from inventory.stock_ledger_entries scope_entry
          where scope_entry.organization_id = balance.organization_id
            and scope_entry.product_id = balance.product_id
            and scope_entry.batch_id = balance.batch_id
            and scope_entry.bucket_code = 'SELLABLE'
        )
        or balance.quarantine_qty <> (
          select coalesce(sum(scope_entry.quantity_delta), 0)::bigint
          from inventory.stock_ledger_entries scope_entry
          where scope_entry.organization_id = balance.organization_id
            and scope_entry.product_id = balance.product_id
            and scope_entry.batch_id = balance.batch_id
            and scope_entry.bucket_code = 'QUARANTINE'
        )
        or balance.damaged_qty <> (
          select coalesce(sum(scope_entry.quantity_delta), 0)::bigint
          from inventory.stock_ledger_entries scope_entry
          where scope_entry.organization_id = balance.organization_id
            and scope_entry.product_id = balance.product_id
            and scope_entry.batch_id = balance.batch_id
            and scope_entry.bucket_code = 'DAMAGED'
        )
      )
  ),
  '0',
  'verification creates no ledger-projection inconsistency'
);
select is(
  (
    with ledger as (
      select
        product.id as product_id,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'SELLABLE'
        ), 0)::bigint as sellable_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'QUARANTINE'
        ), 0)::bigint as quarantine_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'DAMAGED'
        ), 0)::bigint as damaged_qty
      from catalog.products product
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = product.organization_id
       and entry.product_id = product.id
      where product.organization_id =
        '00000000-0000-4000-8000-000000000047'::uuid
      group by product.id
    )
    select count(*)::text
    from ledger
    join inventory.stock_product_positions position
      on position.organization_id =
        '00000000-0000-4000-8000-000000000047'::uuid
     and position.product_id = ledger.product_id
    where position.sellable_qty <> ledger.sellable_qty
       or position.quarantine_qty <> ledger.quarantine_qty
       or position.damaged_qty <> ledger.damaged_qty
  ),
  '0',
  'verification preserves product projection consistency with the ledger'
);

select is(
  (
    select count(*)::text
    from inventory.stock_ledger_entries entry
    where entry.organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and entry.transaction_id in (
        select posting.transaction_id
        from operations.stocktake_postings posting
        where posting.organization_id =
          '00000000-0000-4000-8000-000000000047'::uuid
          and posting.stocktake_id in (
            '67000000-0000-4000-8000-000000000002'::uuid,
            '67000000-0000-4000-8000-000000000003'::uuid,
            '67000000-0000-4000-8000-000000000004'::uuid
          )
      )
  ),
  '0',
  'zero-variance pre-cutover, unmatched, and matching counts add no stock movement'
);
select is(
  (
    select count(*)::text
    from inventory.stock_ledger_entries entry
    where entry.organization_id =
      '00000000-0000-4000-8000-000000000047'::uuid
      and entry.transaction_id = (
        select posting.transaction_id
        from operations.stocktake_postings posting
        where posting.stocktake_id =
          '67000000-0000-4000-8000-000000000005'::uuid
      )
  ),
  '1',
  'nonzero verification stocktake keeps exactly one normal adjustment movement'
);

select * from finish();
rollback;
