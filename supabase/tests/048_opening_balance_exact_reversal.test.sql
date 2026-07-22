begin;

create extension if not exists pgtap with schema extensions;

select plan(93);

-- Contract and security surface.
select has_table('operations', 'opening_balance_active_cutovers', 'active cutover pointer exists');
select has_table('operations', 'opening_balance_cutover_reversals', 'opening balance reversal audit exists');
select has_view('api', 'opening_balance_active_cutovers', 'active cutover read model exists');
select has_view('api', 'opening_balance_cutover_reversals', 'opening balance reversal read model exists');
select function_returns(
  'inventory',
  'preview_opening_balance_reversal_core',
  array['uuid', 'uuid', 'boolean']::text[],
  'jsonb'
);
select function_returns(
  'api',
  'preview_opening_balance_reversal',
  array['uuid', 'uuid']::text[],
  'jsonb'
);
select function_returns(
  'api',
  'reverse_opening_balance_cutover',
  array['uuid', 'text', 'uuid', 'text', 'boolean', 'text', 'jsonb']::text[],
  'jsonb'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.preview_opening_balance_reversal(uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated Admin may preview an opening balance reversal'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.preview_opening_balance_reversal(uuid,uuid)',
    'EXECUTE'
  ),
  'anonymous callers cannot preview an opening balance reversal'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.reverse_opening_balance_cutover(uuid,text,uuid,text,boolean,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may reverse an opening balance cutover'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.reverse_opening_balance_cutover(uuid,text,uuid,text,boolean,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous callers cannot reverse an opening balance cutover'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'inventory.preview_opening_balance_reversal_core(uuid,uuid,boolean)',
    'EXECUTE'
  ),
  'authenticated callers cannot invoke the internal reversal preview core'
);
select ok(
  (
    select class.relrowsecurity
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'opening_balance_active_cutovers'
  ),
  'active opening balance pointer has RLS enabled'
);
select ok(
  (
    select class.relrowsecurity
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'opening_balance_cutover_reversals'
  ),
  'opening balance reversal audit has RLS enabled'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.opening_balance_active_cutovers',
    'INSERT'
  ),
  'authenticated callers cannot insert active pointers directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.opening_balance_cutover_reversals',
    'INSERT'
  ),
  'authenticated callers cannot insert reversal audit rows directly'
);
select has_trigger(
  'operations',
  'opening_balance_cutovers',
  'trg_opening_balance_cutovers_register_active',
  'posting a cutover registers the active pointer'
);
select has_trigger(
  'operations',
  'opening_balance_cutover_reversals',
  'trg_opening_balance_cutover_reversals_immutable',
  'opening balance reversal audit is immutable'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    cross join lateral unnest(procedure.proconfig) config(value)
    where namespace.nspname = 'inventory'
      and procedure.proname = 'preview_opening_balance_reversal_core'
      and procedure.pronargs = 3
      and config.value =
        'search_path=pg_catalog, auth, app, catalog, inventory, operations, extensions'
  ),
  'opening balance reversal preview core has a fixed search_path'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    cross join lateral unnest(procedure.proconfig) config(value)
    where namespace.nspname = 'api'
      and procedure.proname = 'reverse_opening_balance_cutover'
      and procedure.pronargs = 7
      and config.value =
        'search_path=pg_catalog, auth, app, catalog, inventory, operations, extensions'
  ),
  'opening balance reversal command has a fixed search_path'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'uidx_opening_balance_cutovers_posted_org'
  ),
  'legacy one-posted-cutover index is replaced by the active pointer contract'
);

-- Isolated organizations, users, products, and batches.
insert into app.organizations (
  id, code, name, timezone, is_active, created_at, created_by
) values
  (
    '00000000-0000-4000-8000-000000000048'::uuid,
    'PGTAP_OB_REVERSAL',
    'pgTAP Opening Balance Reversal',
    'Asia/Jakarta',
    true,
    '2026-07-21 08:00:00+07'::timestamptz,
    null
  ),
  (
    '00000000-0000-4000-8000-000000000049'::uuid,
    'PGTAP_OB_RESERVED',
    'pgTAP Opening Balance Reserved Conflict',
    'Asia/Jakarta',
    true,
    '2026-07-21 08:00:00+07'::timestamptz,
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
) values
  (
    '00000000-0000-0000-0000-000000000000'::uuid,
    '94000000-0000-4000-8000-000000000048'::uuid,
    'authenticated',
    'authenticated',
    'pgtap.opening.reversal@glowlab.invalid',
    '2026-07-21 08:00:00+07'::timestamptz,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    '2026-07-21 08:00:00+07'::timestamptz,
    '2026-07-21 08:00:00+07'::timestamptz,
    false,
    false
  ),
  (
    '00000000-0000-0000-0000-000000000000'::uuid,
    '94000000-0000-4000-8000-000000000049'::uuid,
    'authenticated',
    'authenticated',
    'pgtap.opening.reserved@glowlab.invalid',
    '2026-07-21 08:00:00+07'::timestamptz,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    '2026-07-21 08:00:00+07'::timestamptz,
    '2026-07-21 08:00:00+07'::timestamptz,
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
) values
  (
    '94000000-0000-4000-8000-000000000048'::uuid,
    '00000000-0000-4000-8000-000000000048'::uuid,
    'pgTAP Opening Reversal Admin',
    'PGTAP-OB-REV',
    'ADMIN',
    true
  ),
  (
    '94000000-0000-4000-8000-000000000049'::uuid,
    '00000000-0000-4000-8000-000000000049'::uuid,
    'pgTAP Opening Reserved Admin',
    'PGTAP-OB-RES',
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
    '48000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000048'::uuid,
    'OBR-SERUM',
    'Opening Reversal Serum',
    'UNIT', true, true, true,
    '2026-07-01 08:00:00+07'::timestamptz,
    1
  ),
  (
    '49000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000049'::uuid,
    'OBR-RESERVED',
    'Opening Reserved Product',
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
    '58000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000048'::uuid,
    '48000000-0000-4000-8000-000000000001'::uuid,
    'OBR-SERUM-A',
    '2026-01-01'::date,
    '2027-01-01'::date,
    '2026-01-15 08:00:00+07'::timestamptz,
    'ACTIVE', null,
    '2026-01-15 08:00:00+07'::timestamptz,
    '2026-01-15 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  ),
  (
    '58000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000048'::uuid,
    '48000000-0000-4000-8000-000000000001'::uuid,
    'OBR-SERUM-B',
    '2026-02-01'::date,
    '2027-02-01'::date,
    '2026-02-15 08:00:00+07'::timestamptz,
    'ACTIVE', null,
    '2026-02-15 08:00:00+07'::timestamptz,
    '2026-02-15 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  ),
  (
    '59000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000049'::uuid,
    '49000000-0000-4000-8000-000000000001'::uuid,
    'OBR-RESERVED-A',
    '2026-01-01'::date,
    '2027-01-01'::date,
    '2026-01-15 08:00:00+07'::timestamptz,
    'ACTIVE', null,
    '2026-01-15 08:00:00+07'::timestamptz,
    '2026-01-15 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  );

create temp table opening_balance_reversal_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update on opening_balance_reversal_results to authenticated;

-- Main organization authentication.
select set_config(
  'request.jwt.claim.sub',
  '94000000-0000-4000-8000-000000000048',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '94000000-0000-4000-8000-000000000048',
    'role', 'authenticated',
    'email', 'pgtap.opening.reversal@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

insert into opening_balance_reversal_results(kind, result)
select 'FIRST_CREATED', api.create_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000048'::uuid,
  'OB-REV-FIRST',
  '2026-07-21 09:00:00+07'::timestamptz,
  'LEGACY-REVERSAL-FIRST',
  'Saldo awal untuk pengujian pembalikan exact.',
  '{"test":true,"fixture":"opening-reversal-first"}'::jsonb
);

insert into opening_balance_reversal_results(kind, result)
select 'FIRST_SAVED', api.save_opening_balance_cutover_draft(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'FIRST_CREATED'),
  1,
  '2026-07-21 09:00:00+07'::timestamptz,
  'LEGACY-REVERSAL-FIRST',
  'Saldo awal untuk pengujian pembalikan exact.',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '48000000-0000-4000-8000-000000000001',
      'batchId', '58000000-0000-4000-8000-000000000001',
      'bucketCode', 'SELLABLE',
      'quantity', 5,
      'sourceLineRef', 'FIRST-SELLABLE'
    ),
    jsonb_build_object(
      'productId', '48000000-0000-4000-8000-000000000001',
      'batchId', '58000000-0000-4000-8000-000000000001',
      'bucketCode', 'DAMAGED',
      'quantity', 1,
      'sourceLineRef', 'FIRST-DAMAGED'
    ),
    jsonb_build_object(
      'productId', '48000000-0000-4000-8000-000000000001',
      'batchId', '58000000-0000-4000-8000-000000000002',
      'bucketCode', 'QUARANTINE',
      'quantity', 0,
      'sourceLineRef', 'FIRST-ZERO'
    )
  ),
  '{"test":true,"revision":1}'::jsonb
);

insert into opening_balance_reversal_results(kind, result)
select 'FIRST_REVIEW', api.submit_opening_balance_cutover_review(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'FIRST_CREATED'),
  2
);

insert into opening_balance_reversal_results(kind, result)
select 'FIRST_POST_PREVIEW', api.preview_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'FIRST_CREATED')
);

insert into opening_balance_reversal_results(kind, result)
select 'FIRST_POSTED', api.post_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000048'::uuid,
  'OB-REV-FIRST-POST',
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'FIRST_CREATED'),
  (select result ->> 'basisHash'
   from opening_balance_reversal_results where kind = 'FIRST_POST_PREVIEW'),
  true
);

select is(
  (select result ->> 'status'
   from opening_balance_reversal_results where kind = 'FIRST_POSTED'),
  'POSTED',
  'first cutover posts successfully'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_active_cutovers
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
  ),
  '1',
  'posting registers one active opening balance pointer'
);
select is(
  (
    select operational_status_code
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_reversal_results where kind = 'FIRST_CREATED'
    )
  ),
  'ACTIVE',
  'posted cutover is exposed as active'
);
select is(
  (
    select transaction_type_code
    from inventory.stock_transactions
    where id = (
      select (result ->> 'transactionId')::uuid
      from opening_balance_reversal_results where kind = 'FIRST_POSTED'
    )
  ),
  'INITIAL_BALANCE',
  'posted cutover creates an INITIAL_BALANCE transaction'
);
select is(
  (
    select count(*)::text
    from inventory.stock_ledger_entries
    where transaction_id = (
      select (result ->> 'transactionId')::uuid
      from opening_balance_reversal_results where kind = 'FIRST_POSTED'
    )
  ),
  '2',
  'only positive opening balance lines create ledger entries'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_cutover_lines
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_reversal_results where kind = 'FIRST_CREATED'
    )
      and quantity = 0
      and ledger_entry_id is null
  ),
  '1',
  'zero opening balance line remains stock-neutral'
);
select is(
  (
    select sellable_qty::text
    from inventory.stock_batch_balances
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and batch_id = '58000000-0000-4000-8000-000000000001'::uuid
  ),
  '5',
  'opening balance posts the sellable quantity'
);
select is(
  (
    select damaged_qty::text
    from inventory.stock_batch_balances
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and batch_id = '58000000-0000-4000-8000-000000000001'::uuid
  ),
  '1',
  'opening balance posts the damaged quantity'
);

insert into opening_balance_reversal_results(kind, result)
select 'REVERSAL_PREVIEW_1', api.preview_opening_balance_reversal(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'FIRST_CREATED')
);

insert into opening_balance_reversal_results(kind, result)
select 'REVERSAL_PREVIEW_2', api.preview_opening_balance_reversal(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'FIRST_CREATED')
);

select is(
  (select result ->> 'status'
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_1'),
  'PREVIEW_READY',
  'active posted cutover has a ready reversal preview'
);
select ok(
  (select (result ->> 'eligible')::boolean
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_1'),
  'reversal preview is eligible'
);
select is(
  (select result ->> 'lineCount'
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_1'),
  '2',
  'reversal preview includes every positive line'
);
select is(
  (select result ->> 'totalAbsoluteQuantity'
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_1'),
  '6',
  'reversal preview totals the exact opening quantity'
);
select is(
  (select result ->> 'basisHash'
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_1'),
  (select result ->> 'basisHash'
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_2'),
  'unchanged reversal previews have a deterministic basis hash'
);
select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and transaction_type_code = 'REVERSAL'
  ),
  '0',
  'preview creates no reversal transaction'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_cutover_reversals
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
  ),
  '0',
  'preview creates no reversal audit effect'
);
select is(
  (
    select line.value ->> 'reversalDelta'
    from opening_balance_reversal_results result_row
    cross join lateral jsonb_array_elements(result_row.result -> 'lines') line(value)
    where result_row.kind = 'REVERSAL_PREVIEW_1'
      and line.value ->> 'sourceLineRef' = 'FIRST-SELLABLE'
  ),
  '-5',
  'sellable preview is the exact opposite quantity'
);
select is(
  (
    select line.value ->> 'reversalDelta'
    from opening_balance_reversal_results result_row
    cross join lateral jsonb_array_elements(result_row.result -> 'lines') line(value)
    where result_row.kind = 'REVERSAL_PREVIEW_1'
      and line.value ->> 'sourceLineRef' = 'FIRST-DAMAGED'
  ),
  '-1',
  'damaged preview is the exact opposite quantity'
);
select is(
  (
    select line.value ->> 'resultingBatchBucketQty'
    from opening_balance_reversal_results result_row
    cross join lateral jsonb_array_elements(result_row.result -> 'lines') line(value)
    where result_row.kind = 'REVERSAL_PREVIEW_1'
      and line.value ->> 'sourceLineRef' = 'FIRST-SELLABLE'
  ),
  '0',
  'initial sellable preview returns the batch bucket to zero'
);
select is(
  (
    select result ->> 'status'
    from opening_balance_reversal_results result_row
    where kind = 'REVERSAL_PREVIEW_1'
  ),
  'PREVIEW_READY',
  'opening balance uses the dedicated reversal path'
);
select throws_ok(
  format(
    $sql$
      select api.reverse_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000048'::uuid,
        'OB-REV-CONFIRM-FALSE',
        %L::uuid,
        %L,
        false,
        'Konfirmasi tidak diberikan.',
        '{}'::jsonb
      )
    $sql$,
    (select result ->> 'cutoverId'
     from opening_balance_reversal_results where kind = 'FIRST_CREATED'),
    (select result ->> 'basisHash'
     from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_1')
  ),
  'P0001',
  'OPENING_BALANCE_REVERSAL_CONFIRMATION_REQUIRED',
  'reversal requires explicit final confirmation'
);

select lives_ok(
  $sql$
    select api.post_receipt(
      '00000000-0000-4000-8000-000000000048'::uuid,
      'OB-REV-RECEIPT-001',
      'OB-REV-RECEIPT-SOURCE-001',
      '2026-07-21 10:00:00+07'::timestamptz,
      jsonb_build_array(jsonb_build_object(
        'productId', '48000000-0000-4000-8000-000000000001',
        'batchId', '58000000-0000-4000-8000-000000000001',
        'quantity', 1,
        'sourceLineRef', 'RECEIPT-AFTER-OPENING'
      )),
      'Receipt setelah opening balance untuk stale-basis test.',
      '{"test":true}'::jsonb
    )
  $sql$,
  'valid receipt changes the reversal basis'
);
select throws_ok(
  format(
    $sql$
      select api.reverse_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000048'::uuid,
        'OB-REV-STALE-001',
        %L::uuid,
        %L,
        true,
        'Percobaan dengan preview lama.',
        '{}'::jsonb
      )
    $sql$,
    (select result ->> 'cutoverId'
     from opening_balance_reversal_results where kind = 'FIRST_CREATED'),
    (select result ->> 'basisHash'
     from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_1')
  ),
  'P0001',
  'STALE_OPENING_BALANCE_REVERSAL_PREVIEW',
  'stale reversal preview is rejected'
);
select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and transaction_type_code = 'REVERSAL'
  ),
  '0',
  'stale attempt creates no reversal effect'
);

insert into opening_balance_reversal_results(kind, result)
select 'REVERSAL_PREVIEW_FRESH', api.preview_opening_balance_reversal(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'FIRST_CREATED')
);

select isnt(
  (select result ->> 'basisHash'
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_FRESH'),
  (select result ->> 'basisHash'
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_1'),
  'stock movement changes the reversal basis hash'
);
select ok(
  (select (result ->> 'eligible')::boolean
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_FRESH'),
  'fresh reversal preview remains eligible'
);
select is(
  (
    select line.value ->> 'resultingBatchBucketQty'
    from opening_balance_reversal_results result_row
    cross join lateral jsonb_array_elements(result_row.result -> 'lines') line(value)
    where result_row.kind = 'REVERSAL_PREVIEW_FRESH'
      and line.value ->> 'sourceLineRef' = 'FIRST-SELLABLE'
  ),
  '1',
  'exact reversal preserves the later receipt quantity'
);

insert into opening_balance_reversal_results(kind, result)
select 'REVERSED', api.reverse_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000048'::uuid,
  'OB-REV-EXECUTE-001',
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'FIRST_CREATED'),
  (select result ->> 'basisHash'
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_FRESH'),
  true,
  'Membalik saldo awal yang salah tanpa mengubah ledger asal.',
  '{"test":true,"reason":"wrong-opening-balance"}'::jsonb
);

select is(
  (select result ->> 'status'
   from opening_balance_reversal_results where kind = 'REVERSED'),
  'REVERSED',
  'confirmed exact reversal succeeds'
);
select is(
  (select result ->> 'lineCount'
   from opening_balance_reversal_results where kind = 'REVERSED'),
  '2',
  'reversal posts one entry per positive opening line'
);
select is(
  (select result ->> 'totalAbsoluteQuantity'
   from opening_balance_reversal_results where kind = 'REVERSED'),
  '6',
  'reversal response reports the exact total quantity'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_cutover_reversals
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
  ),
  '1',
  'one immutable opening balance reversal audit is stored'
);
select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and transaction_type_code = 'REVERSAL'
      and reversal_of_transaction_id = (
        select (result ->> 'transactionId')::uuid
        from opening_balance_reversal_results where kind = 'FIRST_POSTED'
      )
  ),
  '1',
  'one REVERSAL transaction links to the INITIAL_BALANCE transaction'
);
select is(
  (
    select count(*)::text
    from inventory.stock_ledger_entries
    where transaction_id = (
      select (result ->> 'reversalTransactionId')::uuid
      from opening_balance_reversal_results where kind = 'REVERSED'
    )
  ),
  '2',
  'reversal transaction has two exact ledger entries'
);
select is(
  (
    select sum(quantity_delta)::text
    from inventory.stock_ledger_entries
    where transaction_id = (
      select (result ->> 'reversalTransactionId')::uuid
      from opening_balance_reversal_results where kind = 'REVERSED'
    )
  ),
  '-6',
  'reversal ledger entries are the exact opposite total'
);
select is(
  (
    select count(*)::text
    from inventory.stock_reversal_applications
    where original_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from opening_balance_reversal_results where kind = 'FIRST_POSTED'
    )
  ),
  '2',
  'every original entry has one exact reversal application'
);
select is(
  (
    select transaction_type_code
    from inventory.stock_transactions
    where id = (
      select (result ->> 'transactionId')::uuid
      from opening_balance_reversal_results where kind = 'FIRST_POSTED'
    )
  ),
  'INITIAL_BALANCE',
  'original transaction remains unchanged'
);
select is(
  (
    select sum(quantity_delta)::text
    from inventory.stock_ledger_entries
    where transaction_id = (
      select (result ->> 'transactionId')::uuid
      from opening_balance_reversal_results where kind = 'FIRST_POSTED'
    )
  ),
  '6',
  'original opening balance ledger remains append-only'
);
select is(
  (
    select status_code
    from operations.opening_balance_cutovers
    where id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_reversal_results where kind = 'FIRST_CREATED'
    )
  ),
  'POSTED',
  'historical cutover header remains POSTED and immutable'
);
select is(
  (
    select operational_status_code
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_reversal_results where kind = 'FIRST_CREATED'
    )
  ),
  'REVERSED',
  'read model derives REVERSED without mutating the cutover header'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_active_cutovers
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
  ),
  '0',
  'successful reversal releases the active cutover pointer'
);
select is(
  (
    select sellable_qty::text
    from inventory.stock_batch_balances
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and batch_id = '58000000-0000-4000-8000-000000000001'::uuid
  ),
  '1',
  'later receipt quantity remains after exact opening balance reversal'
);
select is(
  (
    select damaged_qty::text
    from inventory.stock_batch_balances
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and batch_id = '58000000-0000-4000-8000-000000000001'::uuid
  ),
  '0',
  'damaged opening quantity is fully reversed'
);
select is(
  (
    select sellable_qty::text
    from inventory.stock_product_positions
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and product_id = '48000000-0000-4000-8000-000000000001'::uuid
  ),
  '1',
  'product projection preserves only the later receipt'
);
select is(
  (
    select count(*)::text
    from inventory.stock_batch_balances balance
    where balance.organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and balance.batch_id = '58000000-0000-4000-8000-000000000001'::uuid
      and balance.sellable_qty = (
        select coalesce(sum(entry.quantity_delta), 0)
        from inventory.stock_ledger_entries entry
        where entry.organization_id = balance.organization_id
          and entry.batch_id = balance.batch_id
          and entry.bucket_code = 'SELLABLE'
      )
      and balance.damaged_qty = (
        select coalesce(sum(entry.quantity_delta), 0)
        from inventory.stock_ledger_entries entry
        where entry.organization_id = balance.organization_id
          and entry.batch_id = balance.batch_id
          and entry.bucket_code = 'DAMAGED'
      )
  ),
  '1',
  'batch projection remains equal to the ledger'
);
select is(
  (
    select count(*)::text
    from inventory.stock_product_positions position
    where position.organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and position.product_id = '48000000-0000-4000-8000-000000000001'::uuid
      and position.sellable_qty = (
        select coalesce(sum(entry.quantity_delta), 0)
        from inventory.stock_ledger_entries entry
        where entry.organization_id = position.organization_id
          and entry.product_id = position.product_id
          and entry.bucket_code = 'SELLABLE'
      )
      and position.damaged_qty = (
        select coalesce(sum(entry.quantity_delta), 0)
        from inventory.stock_ledger_entries entry
        where entry.organization_id = position.organization_id
          and entry.product_id = position.product_id
          and entry.bucket_code = 'DAMAGED'
      )
  ),
  '1',
  'product projection remains equal to the ledger'
);

insert into opening_balance_reversal_results(kind, result)
select 'REPLAY', api.reverse_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000048'::uuid,
  'OB-REV-EXECUTE-001',
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'FIRST_CREATED'),
  (select result ->> 'basisHash'
   from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_FRESH'),
  true,
  'Membalik saldo awal yang salah tanpa mengubah ledger asal.',
  '{"test":true,"reason":"wrong-opening-balance"}'::jsonb
);

select is(
  (select result ->> 'reversalTransactionId'
   from opening_balance_reversal_results where kind = 'REPLAY'),
  (select result ->> 'reversalTransactionId'
   from opening_balance_reversal_results where kind = 'REVERSED'),
  'exact idempotent replay returns the original reversal transaction'
);
select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and transaction_type_code = 'REVERSAL'
  ),
  '1',
  'idempotent replay creates no second reversal effect'
);
select throws_ok(
  format(
    $sql$
      select api.reverse_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000048'::uuid,
        'OB-REV-EXECUTE-001',
        %L::uuid,
        %L,
        true,
        'Payload berbeda dengan key yang sama.',
        '{"test":true}'::jsonb
      )
    $sql$,
    (select result ->> 'cutoverId'
     from opening_balance_reversal_results where kind = 'FIRST_CREATED'),
    (select result ->> 'basisHash'
     from opening_balance_reversal_results where kind = 'REVERSAL_PREVIEW_FRESH')
  ),
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'changed payload under the same idempotency key is rejected'
);

insert into opening_balance_reversal_results(kind, result)
select 'AFTER_REVERSAL_PREVIEW', api.preview_opening_balance_reversal(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'FIRST_CREATED')
);

select is(
  (select result ->> 'status'
   from opening_balance_reversal_results where kind = 'AFTER_REVERSAL_PREVIEW'),
  'BLOCKED',
  'already reversed cutover cannot be previewed as eligible again'
);
select ok(
  exists (
    select 1
    from opening_balance_reversal_results result_row
    cross join lateral jsonb_array_elements(result_row.result -> 'blockers') blocker(value)
    where result_row.kind = 'AFTER_REVERSAL_PREVIEW'
      and blocker.value ->> 'code' = 'OPENING_BALANCE_ALREADY_REVERSED'
  ),
  'already reversed preview exposes the audit blocker'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_verification_applications
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
  ),
  '0',
  'reversal does not manufacture or delete stocktake verification evidence'
);

-- Replacement cutover is allowed only after exact reversal released the pointer.
insert into opening_balance_reversal_results(kind, result)
select 'REPLACEMENT_CREATED', api.create_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000048'::uuid,
  'OB-REV-REPLACEMENT',
  '2026-07-21 11:00:00+07'::timestamptz,
  'LEGACY-REVERSAL-REPLACEMENT',
  'Saldo awal pengganti setelah pembalikan exact.',
  '{"test":true,"fixture":"replacement"}'::jsonb
);

insert into opening_balance_reversal_results(kind, result)
select 'REPLACEMENT_SAVED', api.save_opening_balance_cutover_draft(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'REPLACEMENT_CREATED'),
  1,
  '2026-07-21 11:00:00+07'::timestamptz,
  'LEGACY-REVERSAL-REPLACEMENT',
  'Saldo awal pengganti setelah pembalikan exact.',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '48000000-0000-4000-8000-000000000001',
      'batchId', '58000000-0000-4000-8000-000000000001',
      'bucketCode', 'SELLABLE',
      'quantity', 4,
      'sourceLineRef', 'REPLACEMENT-SELLABLE'
    ),
    jsonb_build_object(
      'productId', '48000000-0000-4000-8000-000000000001',
      'batchId', '58000000-0000-4000-8000-000000000002',
      'bucketCode', 'QUARANTINE',
      'quantity', 2,
      'sourceLineRef', 'REPLACEMENT-QUARANTINE'
    )
  ),
  '{"test":true,"revision":1}'::jsonb
);

insert into opening_balance_reversal_results(kind, result)
select 'REPLACEMENT_REVIEW', api.submit_opening_balance_cutover_review(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'REPLACEMENT_CREATED'),
  2
);

insert into opening_balance_reversal_results(kind, result)
select 'REPLACEMENT_PREVIEW', api.preview_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'REPLACEMENT_CREATED')
);

select is(
  (select result ->> 'status'
   from opening_balance_reversal_results where kind = 'REPLACEMENT_PREVIEW'),
  'PREVIEW_READY',
  'replacement cutover becomes eligible after the old cutover is reversed'
);

insert into opening_balance_reversal_results(kind, result)
select 'REPLACEMENT_POSTED', api.post_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000048'::uuid,
  'OB-REV-REPLACEMENT-POST',
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'REPLACEMENT_CREATED'),
  (select result ->> 'basisHash'
   from opening_balance_reversal_results where kind = 'REPLACEMENT_PREVIEW'),
  true
);

select is(
  (select result ->> 'status'
   from opening_balance_reversal_results where kind = 'REPLACEMENT_POSTED'),
  'POSTED',
  'replacement opening balance posts successfully'
);
select is(
  (
    select cutover_id::text
    from operations.opening_balance_active_cutovers
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
  ),
  (select result ->> 'cutoverId'
   from opening_balance_reversal_results where kind = 'REPLACEMENT_CREATED'),
  'active pointer moves to the replacement cutover'
);
select is(
  (
    select operational_status_code
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_reversal_results where kind = 'FIRST_CREATED'
    )
  ),
  'REVERSED',
  'historical cutover remains visibly reversed after replacement'
);
select is(
  (
    select operational_status_code
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_reversal_results where kind = 'REPLACEMENT_CREATED'
    )
  ),
  'ACTIVE',
  'replacement cutover is the only active cutover'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_cutovers
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and status_code = 'POSTED'
  ),
  '2',
  'historical and replacement cutovers remain posted audit records'
);

insert into opening_balance_reversal_results(kind, result)
select 'THIRD_CREATED', api.create_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000048'::uuid,
  'OB-REV-THIRD',
  '2026-07-21 12:00:00+07'::timestamptz,
  'LEGACY-REVERSAL-THIRD',
  'Cutover ketiga harus diblokir saat replacement masih aktif.',
  '{"test":true,"fixture":"third"}'::jsonb
);

insert into opening_balance_reversal_results(kind, result)
select 'THIRD_SAVED', api.save_opening_balance_cutover_draft(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'THIRD_CREATED'),
  1,
  '2026-07-21 12:00:00+07'::timestamptz,
  'LEGACY-REVERSAL-THIRD',
  'Cutover ketiga harus diblokir saat replacement masih aktif.',
  jsonb_build_array(jsonb_build_object(
    'productId', '48000000-0000-4000-8000-000000000001',
    'batchId', '58000000-0000-4000-8000-000000000001',
    'bucketCode', 'SELLABLE',
    'quantity', 1,
    'sourceLineRef', 'THIRD-SELLABLE'
  )),
  '{"test":true}'::jsonb
);

insert into opening_balance_reversal_results(kind, result)
select 'THIRD_REVIEW', api.submit_opening_balance_cutover_review(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'THIRD_CREATED'),
  2
);

insert into opening_balance_reversal_results(kind, result)
select 'THIRD_PREVIEW', api.preview_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000048'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'THIRD_CREATED')
);

select is(
  (select result ->> 'status'
   from opening_balance_reversal_results where kind = 'THIRD_PREVIEW'),
  'BLOCKED',
  'another cutover is blocked while the replacement is active'
);
select ok(
  exists (
    select 1
    from opening_balance_reversal_results result_row
    cross join lateral jsonb_array_elements(result_row.result -> 'blockers') blocker(value)
    where result_row.kind = 'THIRD_PREVIEW'
      and blocker.value ->> 'code' = 'OPENING_BALANCE_POSTED_CUTOVER_EXISTS'
  ),
  'blocked preview identifies the current active cutover'
);
select throws_ok(
  format(
    $sql$
      select api.post_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000048'::uuid,
        'OB-REV-THIRD-POST',
        %L::uuid,
        %L,
        true
      )
    $sql$,
    (select result ->> 'cutoverId'
     from opening_balance_reversal_results where kind = 'THIRD_CREATED'),
    (select result ->> 'basisHash'
     from opening_balance_reversal_results where kind = 'THIRD_PREVIEW')
  ),
  'P0001',
  'OPENING_BALANCE_PREVIEW_BLOCKED',
  'blocked replacement cannot be committed'
);
select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000048'::uuid
      and transaction_type_code = 'INITIAL_BALANCE'
  ),
  '2',
  'blocked third cutover creates no additional INITIAL_BALANCE transaction'
);

-- Reserved-stock conflict and atomic rollback in another organization.
reset role;
select set_config(
  'request.jwt.claim.sub',
  '94000000-0000-4000-8000-000000000049',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '94000000-0000-4000-8000-000000000049',
    'role', 'authenticated',
    'email', 'pgtap.opening.reserved@glowlab.invalid'
  )::text,
  true
);
set local role authenticated;

insert into opening_balance_reversal_results(kind, result)
select 'RESERVED_CREATED', api.create_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000049'::uuid,
  'OB-RESERVED-FIRST',
  '2026-07-21 09:00:00+07'::timestamptz,
  'LEGACY-RESERVED-FIRST',
  'Saldo awal untuk reserved conflict.',
  '{"test":true}'::jsonb
);
insert into opening_balance_reversal_results(kind, result)
select 'RESERVED_SAVED', api.save_opening_balance_cutover_draft(
  '00000000-0000-4000-8000-000000000049'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'RESERVED_CREATED'),
  1,
  '2026-07-21 09:00:00+07'::timestamptz,
  'LEGACY-RESERVED-FIRST',
  'Saldo awal untuk reserved conflict.',
  jsonb_build_array(jsonb_build_object(
    'productId', '49000000-0000-4000-8000-000000000001',
    'batchId', '59000000-0000-4000-8000-000000000001',
    'bucketCode', 'SELLABLE',
    'quantity', 5,
    'sourceLineRef', 'RESERVED-SELLABLE'
  )),
  '{"test":true}'::jsonb
);
insert into opening_balance_reversal_results(kind, result)
select 'RESERVED_REVIEW', api.submit_opening_balance_cutover_review(
  '00000000-0000-4000-8000-000000000049'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'RESERVED_CREATED'),
  2
);
insert into opening_balance_reversal_results(kind, result)
select 'RESERVED_POST_PREVIEW', api.preview_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000049'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'RESERVED_CREATED')
);
insert into opening_balance_reversal_results(kind, result)
select 'RESERVED_POSTED', api.post_opening_balance_cutover(
  '00000000-0000-4000-8000-000000000049'::uuid,
  'OB-RESERVED-POST',
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'RESERVED_CREATED'),
  (select result ->> 'basisHash'
   from opening_balance_reversal_results where kind = 'RESERVED_POST_PREVIEW'),
  true
);

reset role;
update inventory.stock_product_positions
set reserved_qty = 5,
    updated_at = clock_timestamp(),
    version = version + 1
where organization_id = '00000000-0000-4000-8000-000000000049'::uuid
  and product_id = '49000000-0000-4000-8000-000000000001'::uuid;
set local role authenticated;

insert into opening_balance_reversal_results(kind, result)
select 'RESERVED_REVERSAL_PREVIEW', api.preview_opening_balance_reversal(
  '00000000-0000-4000-8000-000000000049'::uuid,
  (select (result ->> 'cutoverId')::uuid
   from opening_balance_reversal_results where kind = 'RESERVED_CREATED')
);

select is(
  (select result ->> 'status'
   from opening_balance_reversal_results where kind = 'RESERVED_REVERSAL_PREVIEW'),
  'BLOCKED',
  'reserved stock conflict blocks opening balance reversal'
);
select ok(
  exists (
    select 1
    from opening_balance_reversal_results result_row
    cross join lateral jsonb_array_elements(result_row.result -> 'blockers') blocker(value)
    where result_row.kind = 'RESERVED_REVERSAL_PREVIEW'
      and blocker.value ->> 'code' = 'OPENING_BALANCE_REVERSAL_RESERVED_CONFLICT'
  ),
  'reserved conflict is exposed as an authoritative blocker'
);
select throws_ok(
  format(
    $sql$
      select api.reverse_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000049'::uuid,
        'OB-RESERVED-REVERSE',
        %L::uuid,
        %L,
        true,
        'Tidak boleh mengurangi sellable di bawah reserved.',
        '{}'::jsonb
      )
    $sql$,
    (select result ->> 'cutoverId'
     from opening_balance_reversal_results where kind = 'RESERVED_CREATED'),
    (select result ->> 'basisHash'
     from opening_balance_reversal_results where kind = 'RESERVED_REVERSAL_PREVIEW')
  ),
  'P0001',
  'OPENING_BALANCE_REVERSAL_RESERVED_CONFLICT',
  'blocked reserved conflict rolls back the command'
);
select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000049'::uuid
      and transaction_type_code = 'REVERSAL'
  ),
  '0',
  'blocked reserved conflict creates no reversal transaction'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_cutover_reversals
    where organization_id = '00000000-0000-4000-8000-000000000049'::uuid
  ),
  '0',
  'blocked reserved conflict creates no reversal audit record'
);
select is(
  (
    select count(*)::text
    from inventory.idempotency_commands
    where organization_id = '00000000-0000-4000-8000-000000000049'::uuid
      and scope = 'REVERSE_OPENING_BALANCE_CUTOVER'
  ),
  '0',
  'blocked reversal creates no partial idempotency command'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_active_cutovers
    where organization_id = '00000000-0000-4000-8000-000000000049'::uuid
  ),
  '1',
  'blocked reversal leaves the active cutover intact'
);

-- Organization isolation.
reset role;
select set_config(
  'request.jwt.claim.sub',
  '94000000-0000-4000-8000-000000000048',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '94000000-0000-4000-8000-000000000048',
    'role', 'authenticated',
    'email', 'pgtap.opening.reversal@glowlab.invalid'
  )::text,
  true
);
set local role authenticated;

select throws_ok(
  format(
    $sql$
      select api.preview_opening_balance_reversal(
        '00000000-0000-4000-8000-000000000049'::uuid,
        %L::uuid
      )
    $sql$,
    (select result ->> 'cutoverId'
     from opening_balance_reversal_results where kind = 'RESERVED_CREATED')
  ),
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'Admin cannot preview another organization reversal'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_active_cutovers
    where organization_id = '00000000-0000-4000-8000-000000000049'::uuid
  ),
  '0',
  'RLS hides another organization active pointer'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_cutover_reversals
    where organization_id = '00000000-0000-4000-8000-000000000049'::uuid
  ),
  '0',
  'RLS hides another organization reversal audit'
);

-- Immutable history is enforced even for a trusted SQL fixture role.
reset role;
select throws_ok(
  format(
    $sql$
      update operations.opening_balance_cutover_reversals
      set note = 'Tidak boleh diubah'
      where id = %L::uuid
    $sql$,
    (select result ->> 'reversalRecordId'
     from opening_balance_reversal_results where kind = 'REVERSED')
  ),
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'opening balance reversal audit cannot be edited'
);
select throws_ok(
  format(
    $sql$
      update inventory.stock_ledger_entries
      set quantity_delta = quantity_delta - 1
      where id = %L::uuid
    $sql$,
    (
      select line.ledger_entry_id::text
      from operations.opening_balance_cutover_lines line
      where line.cutover_id = (
        select (result ->> 'cutoverId')::uuid
        from opening_balance_reversal_results where kind = 'FIRST_CREATED'
      )
        and line.quantity > 0
      order by line.line_no
      limit 1
    )
  ),
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'original opening balance ledger entry cannot be edited'
);

select * from finish();
rollback;
