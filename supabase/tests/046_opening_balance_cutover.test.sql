begin;

create extension if not exists pgtap with schema extensions;

select plan(99);

-- Contract, security, and privilege surface.
select has_table(
  'operations',
  'opening_balance_cutovers',
  'opening balance cutover header table exists'
);
select has_table(
  'operations',
  'opening_balance_cutover_lines',
  'opening balance cutover line table exists'
);
select has_view(
  'api',
  'opening_balance_cutovers',
  'opening balance cutover read view exists'
);
select has_view(
  'api',
  'opening_balance_cutover_lines',
  'opening balance cutover line read view exists'
);

select function_returns(
  'inventory',
  'opening_balance_cutover_request_payload',
  array['uuid', 'uuid']::text[],
  'jsonb'
);
select function_returns(
  'inventory',
  'preview_opening_balance_cutover_core',
  array['uuid', 'uuid', 'boolean']::text[],
  'jsonb'
);
select function_returns(
  'api',
  'create_opening_balance_cutover',
  array['uuid', 'text', 'timestamptz', 'text', 'text', 'jsonb']::text[],
  'jsonb'
);
select function_returns(
  'api',
  'save_opening_balance_cutover_draft',
  array[
    'uuid', 'uuid', 'bigint', 'timestamptz',
    'text', 'text', 'jsonb', 'jsonb'
  ]::text[],
  'jsonb'
);
select function_returns(
  'api',
  'submit_opening_balance_cutover_review',
  array['uuid', 'uuid', 'bigint']::text[],
  'jsonb'
);
select function_returns(
  'api',
  'preview_opening_balance_cutover',
  array['uuid', 'uuid']::text[],
  'jsonb'
);
select function_returns(
  'api',
  'post_opening_balance_cutover',
  array['uuid', 'text', 'uuid', 'text', 'boolean']::text[],
  'jsonb'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.create_opening_balance_cutover(uuid,text,timestamptz,text,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot create opening balance cutovers'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.create_opening_balance_cutover(uuid,text,timestamptz,text,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may create opening balance cutovers'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.preview_opening_balance_cutover(uuid,uuid)',
    'EXECUTE'
  ),
  'anonymous users cannot preview opening balances'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.preview_opening_balance_cutover(uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated Admin may preview opening balances'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.post_opening_balance_cutover(uuid,text,uuid,text,boolean)',
    'EXECUTE'
  ),
  'anonymous users cannot post opening balances'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.post_opening_balance_cutover(uuid,text,uuid,text,boolean)',
    'EXECUTE'
  ),
  'authenticated Admin may post opening balances'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'inventory.preview_opening_balance_cutover_core(uuid,uuid,boolean)',
    'EXECUTE'
  ),
  'authenticated role cannot execute the internal preview core'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.opening_balance_cutovers',
    'INSERT'
  ),
  'authenticated role cannot insert opening balance headers directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.opening_balance_cutover_lines',
    'INSERT'
  ),
  'authenticated role cannot insert opening balance lines directly'
);
select ok(
  (
    select class.relrowsecurity
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'opening_balance_cutovers'
  ),
  'opening balance cutover headers have RLS enabled'
);
select ok(
  (
    select class.relrowsecurity
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'opening_balance_cutover_lines'
  ),
  'opening balance cutover lines have RLS enabled'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    cross join lateral unnest(procedure.proconfig) config(value)
    where namespace.nspname = 'api'
      and procedure.proname = 'post_opening_balance_cutover'
      and procedure.pronargs = 5
      and config.value =
        'search_path=pg_catalog, auth, app, catalog, inventory, operations, extensions'
  ),
  'opening balance posting has a fixed search_path'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    cross join lateral unnest(procedure.proconfig) config(value)
    where namespace.nspname = 'inventory'
      and procedure.proname = 'preview_opening_balance_cutover_core'
      and procedure.pronargs = 3
      and config.value =
        'search_path=pg_catalog, auth, app, catalog, inventory, operations, extensions'
  ),
  'opening balance preview core has a fixed search_path'
);

-- Isolated organizations and Admin fixture.
insert into app.organizations (
  id, code, name, timezone, is_active, created_at, created_by
) values
  (
    '00000000-0000-4000-8000-000000000042'::uuid,
    'PGTAP_OPENING_BALANCE',
    'pgTAP Opening Balance',
    'Asia/Jakarta',
    true,
    '2026-07-21 08:00:00+07'::timestamptz,
    null
  ),
  (
    '00000000-0000-4000-8000-000000000043'::uuid,
    'PGTAP_OPENING_BALANCE_OTHER',
    'pgTAP Opening Balance Other',
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
) values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94000000-0000-4000-8000-000000000042'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.opening.balance@glowlab.invalid',
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
) values (
  '94000000-0000-4000-8000-000000000042'::uuid,
  '00000000-0000-4000-8000-000000000042'::uuid,
  'pgTAP Opening Balance Admin',
  'PGTAP-OPENING-BALANCE',
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
    '42000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000042'::uuid,
    'OB-SERUM',
    'Opening Balance Serum',
    'UNIT', true, true, true,
    '2026-07-01 08:00:00+07'::timestamptz,
    1
  ),
  (
    '42000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000042'::uuid,
    'OB-CLEANSER',
    'Opening Balance Cleanser',
    'UNIT', true, true, true,
    '2026-07-01 08:00:00+07'::timestamptz,
    1
  ),
  (
    '42000000-0000-4000-8000-000000000099'::uuid,
    '00000000-0000-4000-8000-000000000043'::uuid,
    'OB-OTHER',
    'Opening Balance Other Organization',
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
    '52000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000042'::uuid,
    '42000000-0000-4000-8000-000000000001'::uuid,
    'OB-SERUM-A',
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
    '52000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000042'::uuid,
    '42000000-0000-4000-8000-000000000001'::uuid,
    'OB-SERUM-B',
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
    '52000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000042'::uuid,
    '42000000-0000-4000-8000-000000000002'::uuid,
    'OB-CLEANSER-A',
    '2026-03-01'::date,
    '2027-03-01'::date,
    '2026-03-15 08:00:00+07'::timestamptz,
    'ACTIVE', null,
    '2026-03-15 08:00:00+07'::timestamptz,
    '2026-03-15 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  ),
  (
    '52000000-0000-4000-8000-000000000099'::uuid,
    '00000000-0000-4000-8000-000000000043'::uuid,
    '42000000-0000-4000-8000-000000000099'::uuid,
    'OB-OTHER-A',
    '2026-01-01'::date,
    '2027-01-01'::date,
    '2026-01-15 08:00:00+07'::timestamptz,
    'ACTIVE', null,
    '2026-01-15 08:00:00+07'::timestamptz,
    '2026-01-15 08:00:00+07'::timestamptz,
    1,
    'STANDARD'
  );

create temp table opening_balance_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update on opening_balance_results to authenticated;

select set_config(
  'request.jwt.claim.sub',
  '94000000-0000-4000-8000-000000000042',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '94000000-0000-4000-8000-000000000042',
    'role', 'authenticated',
    'email', 'pgtap.opening.balance@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

insert into opening_balance_results(kind, result)
select
  'CREATED',
  api.create_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000042'::uuid,
    'OB-CUTOVER-001',
    '2026-07-21 09:00:00+07'::timestamptz,
    'LEGACY-SPREADSHEET-2026-07-20',
    'Saldo awal hasil konsolidasi spreadsheet dan pemeriksaan dokumen gudang.',
    '{"test":true,"source":"legacy-spreadsheet"}'::jsonb
  );

select is(
  (select result ->> 'status' from opening_balance_results where kind = 'CREATED'),
  'DRAFT',
  'create command starts the cutover in DRAFT'
);
select is(
  (select result ->> 'rowVersion' from opening_balance_results where kind = 'CREATED'),
  '1',
  'new cutover starts at row version one'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_cutovers
    where source_ref = 'OB-CUTOVER-001'
  ),
  '1',
  'current organization can read its draft cutover through the API view'
);

select throws_ok(
  $sql$
    select api.create_opening_balance_cutover(
      '00000000-0000-4000-8000-000000000042'::uuid,
      'OB-CUTOVER-001',
      '2026-07-21 09:00:00+07'::timestamptz,
      'LEGACY-SPREADSHEET-DUP',
      'Duplicate source fixture.',
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'OPENING_BALANCE_SOURCE_ALREADY_EXISTS',
  'duplicate cutover source reference is rejected'
);

select throws_ok(
  $sql$
    select api.create_opening_balance_cutover(
      '00000000-0000-4000-8000-000000000043'::uuid,
      'OB-CROSS-ORG-001',
      '2026-07-21 09:00:00+07'::timestamptz,
      'OTHER-SPREADSHEET',
      'Cross organization fixture.',
      '{}'::jsonb
    )
  $sql$,
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'Admin cannot create a cutover for another organization'
);

select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000042'::uuid,
        %L::uuid,
        1,
        '2026-07-21 09:00:00+07'::timestamptz,
        'LEGACY-SPREADSHEET-2026-07-20',
        'Invalid negative quantity fixture.',
        %L::jsonb,
        '{}'::jsonb
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED'),
    jsonb_build_array(jsonb_build_object(
      'productId', '42000000-0000-4000-8000-000000000001',
      'batchId', '52000000-0000-4000-8000-000000000001',
      'bucketCode', 'SELLABLE',
      'quantity', -1,
      'sourceLineRef', 'NEGATIVE-1'
    ))::text
  ),
  'P0001',
  'OPENING_BALANCE_LINE_INVALID',
  'negative opening balance quantity is rejected'
);

select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000042'::uuid,
        %L::uuid,
        1,
        '2026-07-21 09:00:00+07'::timestamptz,
        'LEGACY-SPREADSHEET-2026-07-20',
        'Duplicate identity fixture.',
        %L::jsonb,
        '{}'::jsonb
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED'),
    jsonb_build_array(
      jsonb_build_object(
        'productId', '42000000-0000-4000-8000-000000000001',
        'batchId', '52000000-0000-4000-8000-000000000001',
        'bucketCode', 'SELLABLE',
        'quantity', 1,
        'sourceLineRef', 'DUP-1'
      ),
      jsonb_build_object(
        'productId', '42000000-0000-4000-8000-000000000001',
        'batchId', '52000000-0000-4000-8000-000000000001',
        'bucketCode', 'SELLABLE',
        'quantity', 2,
        'sourceLineRef', 'DUP-2'
      )
    )::text
  ),
  'P0001',
  'OPENING_BALANCE_DUPLICATE_BATCH_BUCKET_LINE',
  'duplicate product, batch, and bucket lines are rejected'
);

select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000042'::uuid,
        %L::uuid,
        1,
        '2026-07-21 09:00:00+07'::timestamptz,
        'LEGACY-SPREADSHEET-2026-07-20',
        'Duplicate source line fixture.',
        %L::jsonb,
        '{}'::jsonb
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED'),
    jsonb_build_array(
      jsonb_build_object(
        'productId', '42000000-0000-4000-8000-000000000001',
        'batchId', '52000000-0000-4000-8000-000000000001',
        'bucketCode', 'SELLABLE',
        'quantity', 1,
        'sourceLineRef', 'SAME-LINE'
      ),
      jsonb_build_object(
        'productId', '42000000-0000-4000-8000-000000000001',
        'batchId', '52000000-0000-4000-8000-000000000002',
        'bucketCode', 'QUARANTINE',
        'quantity', 1,
        'sourceLineRef', 'SAME-LINE'
      )
    )::text
  ),
  'P0001',
  'OPENING_BALANCE_DUPLICATE_SOURCE_LINE',
  'duplicate source line references are rejected'
);

select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000042'::uuid,
        %L::uuid,
        1,
        '2026-07-21 09:00:00+07'::timestamptz,
        'LEGACY-SPREADSHEET-2026-07-20',
        'Unverified sellable fixture.',
        %L::jsonb,
        '{}'::jsonb
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED'),
    jsonb_build_array(jsonb_build_object(
      'productId', '42000000-0000-4000-8000-000000000001',
      'batchId', '52000000-0000-4000-8000-000000000002',
      'bucketCode', 'SELLABLE',
      'quantity', 1,
      'batchIdentityVerified', false,
      'exceptionReference', 'UNKNOWN-LOT-1',
      'sourceLineRef', 'UNVERIFIED-SELLABLE'
    ))::text
  ),
  'P0001',
  'UNKNOWN_BATCH_NOT_QUARANTINED',
  'unverified batch identity cannot be saved as sellable'
);

insert into opening_balance_results(kind, result)
select
  'SAVED',
  api.save_opening_balance_cutover_draft(
    '00000000-0000-4000-8000-000000000042'::uuid,
    (select (result ->> 'cutoverId')::uuid
     from opening_balance_results where kind = 'CREATED'),
    1,
    '2026-07-21 09:00:00+07'::timestamptz,
    'LEGACY-SPREADSHEET-2026-07-20',
    'Saldo awal hasil konsolidasi spreadsheet dan pemeriksaan dokumen gudang.',
    jsonb_build_array(
      jsonb_build_object(
        'productId', '42000000-0000-4000-8000-000000000001',
        'batchId', '52000000-0000-4000-8000-000000000001',
        'bucketCode', 'SELLABLE',
        'quantity', 5,
        'sourceLineRef', 'SERUM-A-SELLABLE'
      ),
      jsonb_build_object(
        'productId', '42000000-0000-4000-8000-000000000001',
        'batchId', '52000000-0000-4000-8000-000000000001',
        'bucketCode', 'DAMAGED',
        'quantity', 0,
        'sourceLineRef', 'SERUM-A-DAMAGED-ZERO'
      ),
      jsonb_build_object(
        'productId', '42000000-0000-4000-8000-000000000001',
        'batchId', '52000000-0000-4000-8000-000000000002',
        'bucketCode', 'QUARANTINE',
        'quantity', 2,
        'batchIdentityVerified', false,
        'exceptionReference', 'LEGACY-LOT-NOT-FULLY-VERIFIED',
        'sourceLineRef', 'SERUM-B-QUARANTINE'
      )
    ),
    '{"test":true,"source":"legacy-spreadsheet","revision":1}'::jsonb
  );

select is(
  (select result ->> 'status' from opening_balance_results where kind = 'SAVED'),
  'DRAFT',
  'saving lines keeps the cutover in DRAFT'
);
select is(
  (select result ->> 'rowVersion' from opening_balance_results where kind = 'SAVED'),
  '2',
  'saving the draft increments row version'
);
select is(
  (select result ->> 'lineCount' from opening_balance_results where kind = 'SAVED'),
  '3',
  'draft stores all three opening balance lines'
);
select is(
  (select result ->> 'positiveLineCount' from opening_balance_results where kind = 'SAVED'),
  '2',
  'draft distinguishes positive lines from zero lines'
);
select is(
  (select result ->> 'totalQuantity' from opening_balance_results where kind = 'SAVED'),
  '7',
  'draft total includes only actual quantities'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_cutover_lines
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_results where kind = 'CREATED'
    )
      and quantity = 0
  ),
  '1',
  'zero quantity line remains available in the draft'
);

select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000042'::uuid,
        %L::uuid,
        1,
        '2026-07-21 09:00:00+07'::timestamptz,
        'LEGACY-SPREADSHEET-2026-07-20',
        'Stale version fixture.',
        '[]'::jsonb,
        '{}'::jsonb
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED')
  ),
  'P0001',
  'STALE_OPENING_BALANCE_DRAFT',
  'stale draft version is rejected'
);

insert into opening_balance_results(kind, result)
select
  'REVIEW',
  api.submit_opening_balance_cutover_review(
    '00000000-0000-4000-8000-000000000042'::uuid,
    (select (result ->> 'cutoverId')::uuid
     from opening_balance_results where kind = 'CREATED'),
    2
  );

select is(
  (select result ->> 'status' from opening_balance_results where kind = 'REVIEW'),
  'REVIEW',
  'submit command transitions the cutover into REVIEW'
);
select matches(
  (select result ->> 'requestHash' from opening_balance_results where kind = 'REVIEW'),
  '^[0-9a-f]{64}$',
  'review stores a canonical request hash'
);

select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000042'::uuid,
        %L::uuid,
        3,
        '2026-07-21 09:00:00+07'::timestamptz,
        'LEGACY-SPREADSHEET-2026-07-20',
        'Review edit fixture.',
        '[]'::jsonb,
        '{}'::jsonb
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED')
  ),
  'P0001',
  'OPENING_BALANCE_DRAFT_NOT_EDITABLE',
  'reviewed cutover cannot return to draft editing'
);

insert into opening_balance_results(kind, result)
select
  'PREVIEW_1',
  api.preview_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000042'::uuid,
    (select (result ->> 'cutoverId')::uuid
     from opening_balance_results where kind = 'CREATED')
  );

insert into opening_balance_results(kind, result)
select
  'PREVIEW_2',
  api.preview_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000042'::uuid,
    (select (result ->> 'cutoverId')::uuid
     from opening_balance_results where kind = 'CREATED')
  );

select is(
  (select result ->> 'status' from opening_balance_results where kind = 'PREVIEW_1'),
  'PREVIEW_READY',
  'reviewed opening balance produces a ready preview'
);
select ok(
  (select (result ->> 'eligible')::boolean
   from opening_balance_results where kind = 'PREVIEW_1'),
  'opening balance preview is eligible'
);
select is(
  (select result ->> 'basisHash' from opening_balance_results where kind = 'PREVIEW_1'),
  (select result ->> 'basisHash' from opening_balance_results where kind = 'PREVIEW_2'),
  'identical opening balance previews have a stable basis hash'
);
select is(
  (
    select line.value ->> 'currentBatchBucketQty'
    from opening_balance_results result_row
    cross join lateral jsonb_array_elements(
      result_row.result -> 'lines'
    ) line(value)
    where result_row.kind = 'PREVIEW_1'
      and line.value ->> 'sourceLineRef' = 'SERUM-A-SELLABLE'
  ),
  '0',
  'preview shows the authoritative batch quantity before posting'
);
select is(
  (
    select line.value ->> 'resultingBatchBucketQty'
    from opening_balance_results result_row
    cross join lateral jsonb_array_elements(
      result_row.result -> 'lines'
    ) line(value)
    where result_row.kind = 'PREVIEW_1'
      and line.value ->> 'sourceLineRef' = 'SERUM-A-SELLABLE'
  ),
  '5',
  'preview shows the resulting batch quantity'
);
select is(
  (
    select line.value ->> 'verificationStatusCode'
    from opening_balance_results result_row
    cross join lateral jsonb_array_elements(result_row.result -> 'lines') line(value)
    where result_row.kind = 'PREVIEW_1'
      and line.value ->> 'sourceLineRef' = 'SERUM-B-QUARANTINE'
  ),
  'UNVERIFIED',
  'positive preview line is explicitly unverified'
);

select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
  ),
  '0',
  'preview creates no stock transaction'
);
select is(
  (
    select count(*)::text
    from inventory.stock_ledger_entries
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
  ),
  '0',
  'preview creates no ledger entry'
);
select is(
  (
    select count(*)::text
    from inventory.idempotency_commands
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
  ),
  '0',
  'preview creates no idempotency command'
);
select is(
  (
    select count(*)::text
    from inventory.stock_batch_balances
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
  ),
  '0',
  'preview creates no stock balance projection'
);

select throws_ok(
  format(
    $sql$
      select api.preview_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000043'::uuid,
        %L::uuid
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED')
  ),
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'Admin cannot preview another organization'
);

select throws_ok(
  format(
    $sql$
      select api.post_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000042'::uuid,
        'OB-CONFIRM-001',
        %L::uuid,
        %L,
        false
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED'),
    (select result ->> 'basisHash' from opening_balance_results where kind = 'PREVIEW_1')
  ),
  'P0001',
  'OPENING_BALANCE_CONFIRMATION_REQUIRED',
  'posting requires explicit final confirmation'
);

select lives_ok(
  $sql$
    select api.post_receipt(
      '00000000-0000-4000-8000-000000000042'::uuid,
      'OB-STALE-RECEIPT-001',
      'OB-STALE-RECEIPT-SOURCE-001',
      '2026-07-21 09:30:00+07'::timestamptz,
      jsonb_build_array(jsonb_build_object(
        'productId', '42000000-0000-4000-8000-000000000002',
        'batchId', '52000000-0000-4000-8000-000000000003',
        'quantity', 1,
        'sourceLineRef', 'RECEIPT-LINE-1'
      )),
      'Receipt terpisah untuk mengubah basis preview.',
      '{"test":true}'::jsonb
    )
  $sql$,
  'unrelated valid receipt changes the organization ledger basis'
);

select throws_ok(
  format(
    $sql$
      select api.post_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000042'::uuid,
        'OB-POST-STALE-001',
        %L::uuid,
        %L,
        true
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED'),
    (select result ->> 'basisHash' from opening_balance_results where kind = 'PREVIEW_1')
  ),
  'P0001',
  'STALE_OPENING_BALANCE_PREVIEW',
  'posting rejects a stale opening balance preview'
);
select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and transaction_type_code = 'INITIAL_BALANCE'
  ),
  '0',
  'stale posting attempt creates no initial balance transaction'
);

insert into opening_balance_results(kind, result)
select
  'PREVIEW_FRESH',
  api.preview_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000042'::uuid,
    (select (result ->> 'cutoverId')::uuid
     from opening_balance_results where kind = 'CREATED')
  );

select is(
  (select result ->> 'status' from opening_balance_results where kind = 'PREVIEW_FRESH'),
  'PREVIEW_READY',
  'fresh preview remains eligible after unrelated valid movement'
);
select isnt(
  (select result ->> 'basisHash' from opening_balance_results where kind = 'PREVIEW_FRESH'),
  (select result ->> 'basisHash' from opening_balance_results where kind = 'PREVIEW_1'),
  'ledger movement changes the opening balance basis hash'
);

insert into opening_balance_results(kind, result)
select
  'POSTED',
  api.post_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000042'::uuid,
    'OB-POST-001',
    (select (result ->> 'cutoverId')::uuid
     from opening_balance_results where kind = 'CREATED'),
    (select result ->> 'basisHash'
     from opening_balance_results where kind = 'PREVIEW_FRESH'),
    true
  );

select is(
  (select result ->> 'status' from opening_balance_results where kind = 'POSTED'),
  'POSTED',
  'confirmed command posts the opening balance'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_cutovers
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and status_code = 'POSTED'
  ),
  '1',
  'organization has exactly one posted opening balance cutover'
);
select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and transaction_type_code = 'INITIAL_BALANCE'
  ),
  '1',
  'posting creates one INITIAL_BALANCE transaction'
);
select is(
  (
    select count(*)::text
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and transaction.transaction_type_code = 'INITIAL_BALANCE'
  ),
  '2',
  'only positive cutover lines create ledger entries'
);
select is(
  (
    select sum(entry.quantity_delta)::text
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and transaction.transaction_type_code = 'INITIAL_BALANCE'
  ),
  '7',
  'opening balance ledger quantity equals the positive line total'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_cutover_lines line
    where line.cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_results where kind = 'CREATED'
    )
      and line.quantity = 0
      and line.ledger_entry_id is null
  ),
  '1',
  'zero quantity line creates no ledger entry'
);
select is(
  (
    select count(*)::text
    from operations.opening_balance_cutover_lines line
    where line.cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_results where kind = 'CREATED'
    )
      and line.quantity > 0
      and line.ledger_entry_id is not null
  ),
  '2',
  'every positive line stores exact ledger linkage'
);
select is(
  (
    select sellable_qty::text
    from inventory.stock_batch_balances
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and batch_id = '52000000-0000-4000-8000-000000000001'::uuid
  ),
  '5',
  'sellable opening balance updates the exact selected batch'
);
select is(
  (
    select quarantine_qty::text
    from inventory.stock_batch_balances
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and batch_id = '52000000-0000-4000-8000-000000000002'::uuid
  ),
  '2',
  'quarantine opening balance updates the exact selected batch'
);
select is(
  (
    select sellable_qty::text
    from inventory.stock_product_positions
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and product_id = '42000000-0000-4000-8000-000000000001'::uuid
  ),
  '5',
  'product sellable projection matches opening balance ledger delta'
);
select is(
  (
    select quarantine_qty::text
    from inventory.stock_product_positions
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and product_id = '42000000-0000-4000-8000-000000000001'::uuid
  ),
  '2',
  'product quarantine projection matches opening balance ledger delta'
);
select is(
  (
    select transaction_id::text
    from operations.opening_balance_cutovers
    where id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_results where kind = 'CREATED'
    )
  ),
  (select result ->> 'transactionId' from opening_balance_results where kind = 'POSTED'),
  'posted cutover links to the exact INITIAL_BALANCE transaction'
);
select ok(
  (
    select ledger_seq_after >= ledger_seq_before
    from operations.opening_balance_cutovers
    where id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_results where kind = 'CREATED'
    )
  ),
  'posted cutover stores valid ledger boundaries'
);
select is(
  (
    select count(*)::text
    from inventory.idempotency_commands
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and scope = 'POST_OPENING_BALANCE'
      and status_code = 'SUCCEEDED'
  ),
  '1',
  'posting persists one successful opening balance idempotency command'
);

select is(
  (
    select source_type_code
    from inventory.stock_transactions
    where id = (
      select (result ->> 'transactionId')::uuid
      from opening_balance_results where kind = 'POSTED'
    )
  ),
  'OPENING_BALANCE_CUTOVER',
  'stock transaction retains the cutover source type'
);
select is(
  (
    select verification_status_code
    from api.opening_balance_cutovers
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_results where kind = 'CREATED'
    )
  ),
  'UNVERIFIED',
  'posted cutover remains explicitly unverified'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_cutover_lines
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_results where kind = 'CREATED'
    )
      and verification_status_code = 'UNVERIFIED'
  ),
  '2',
  'both positive opening balance lines remain unverified'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_cutover_lines
    where cutover_id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_results where kind = 'CREATED'
    )
      and verification_status_code = 'NOT_APPLICABLE'
  ),
  '1',
  'zero quantity line does not require verification'
);

insert into opening_balance_results(kind, result)
select
  'REPLAY',
  api.post_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000042'::uuid,
    'OB-POST-001',
    (select (result ->> 'cutoverId')::uuid
     from opening_balance_results where kind = 'CREATED'),
    (select result ->> 'basisHash'
     from opening_balance_results where kind = 'PREVIEW_FRESH'),
    true
  );

select is(
  (select result from opening_balance_results where kind = 'REPLAY'),
  (select result from opening_balance_results where kind = 'POSTED'),
  'identical idempotent replay returns the stored response'
);
select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and transaction_type_code = 'INITIAL_BALANCE'
  ),
  '1',
  'idempotent replay creates no second INITIAL_BALANCE transaction'
);
select is(
  (
    select count(*)::text
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and transaction.transaction_type_code = 'INITIAL_BALANCE'
  ),
  '2',
  'idempotent replay creates no second ledger effect'
);

select throws_ok(
  format(
    $sql$
      select api.post_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000042'::uuid,
        'OB-POST-001',
        %L::uuid,
        repeat('0', 64),
        true
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED')
  ),
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'same idempotency key with a changed payload is rejected'
);

select throws_ok(
  format(
    $sql$
      select api.post_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000042'::uuid,
        'OB-POST-SECOND-KEY',
        %L::uuid,
        %L,
        true
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED'),
    (select result ->> 'basisHash' from opening_balance_results where kind = 'PREVIEW_FRESH')
  ),
  'P0001',
  'OPENING_BALANCE_CUTOVER_NOT_IN_REVIEW',
  'posted cutover cannot receive a second domain effect under another key'
);

insert into opening_balance_results(kind, result)
select
  'SECOND_CREATED',
  api.create_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000042'::uuid,
    'OB-CUTOVER-002',
    '2026-07-22 09:00:00+07'::timestamptz,
    'LEGACY-SPREADSHEET-SECOND',
    'Second posted cutover blocker fixture.',
    '{"test":true,"sequence":2}'::jsonb
  );

insert into opening_balance_results(kind, result)
select
  'SECOND_SAVED',
  api.save_opening_balance_cutover_draft(
    '00000000-0000-4000-8000-000000000042'::uuid,
    (select (result ->> 'cutoverId')::uuid
     from opening_balance_results where kind = 'SECOND_CREATED'),
    1,
    '2026-07-22 09:00:00+07'::timestamptz,
    'LEGACY-SPREADSHEET-SECOND',
    'Second posted cutover blocker fixture.',
    jsonb_build_array(jsonb_build_object(
      'productId', '42000000-0000-4000-8000-000000000002',
      'batchId', '52000000-0000-4000-8000-000000000003',
      'bucketCode', 'SELLABLE',
      'quantity', 1,
      'sourceLineRef', 'SECOND-LINE-1'
    )),
    '{"test":true,"sequence":2}'::jsonb
  );

insert into opening_balance_results(kind, result)
select
  'SECOND_REVIEW',
  api.submit_opening_balance_cutover_review(
    '00000000-0000-4000-8000-000000000042'::uuid,
    (select (result ->> 'cutoverId')::uuid
     from opening_balance_results where kind = 'SECOND_CREATED'),
    2
  );

insert into opening_balance_results(kind, result)
select
  'SECOND_PREVIEW',
  api.preview_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000042'::uuid,
    (select (result ->> 'cutoverId')::uuid
     from opening_balance_results where kind = 'SECOND_CREATED')
  );

select is(
  (select result ->> 'status' from opening_balance_results where kind = 'SECOND_CREATED'),
  'DRAFT',
  'a second cutover may exist as an auditable draft'
);
select is(
  (select result ->> 'status' from opening_balance_results where kind = 'SECOND_SAVED'),
  'DRAFT',
  'second cutover draft can store its proposed lines'
);
select is(
  (select result ->> 'status' from opening_balance_results where kind = 'SECOND_REVIEW'),
  'REVIEW',
  'second cutover may reach review without changing stock'
);
select is(
  (select result ->> 'status' from opening_balance_results where kind = 'SECOND_PREVIEW'),
  'BLOCKED',
  'second cutover preview is blocked after one cutover is posted'
);
select is(
  (
    select blocker.value ->> 'code'
    from opening_balance_results result_row
    cross join lateral jsonb_array_elements(result_row.result -> 'blockers') blocker(value)
    where result_row.kind = 'SECOND_PREVIEW'
      and blocker.value ->> 'code' = 'OPENING_BALANCE_POSTED_CUTOVER_EXISTS'
    limit 1
  ),
  'OPENING_BALANCE_POSTED_CUTOVER_EXISTS',
  'preview explains the one-posted-cutover invariant'
);

select throws_ok(
  format(
    $sql$
      select api.post_opening_balance_cutover(
        '00000000-0000-4000-8000-000000000042'::uuid,
        'OB-POST-SECOND-001',
        %L::uuid,
        %L,
        true
      )
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'SECOND_CREATED'),
    (select result ->> 'basisHash' from opening_balance_results where kind = 'SECOND_PREVIEW')
  ),
  'P0001',
  'OPENING_BALANCE_PREVIEW_BLOCKED',
  'blocked second cutover cannot be posted'
);
select is(
  (
    select count(*)::text
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and transaction_type_code = 'INITIAL_BALANCE'
  ),
  '1',
  'blocked second cutover creates no additional stock transaction'
);
select is(
  (
    select count(*)::text
    from api.opening_balance_cutovers
    where organization_id = '00000000-0000-4000-8000-000000000043'::uuid
  ),
  '0',
  'RLS hides another organization opening balance data'
);

reset role;

select throws_ok(
  format(
    $sql$
      update operations.opening_balance_cutovers
      set note = 'Mutation forbidden'
      where id = %L::uuid
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED')
  ),
  'P0001',
  'OPENING_BALANCE_CUTOVER_IMMUTABLE',
  'posted opening balance header is immutable'
);
select throws_ok(
  format(
    $sql$
      update operations.opening_balance_cutover_lines
      set quantity = quantity + 1
      where cutover_id = %L::uuid
        and quantity > 0
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED')
  ),
  'P0001',
  'OPENING_BALANCE_CUTOVER_LINE_IMMUTABLE',
  'posted opening balance lines are immutable'
);
select throws_ok(
  format(
    $sql$
      delete from operations.opening_balance_cutovers
      where id = %L::uuid
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED')
  ),
  'P0001',
  'OPENING_BALANCE_CUTOVER_DELETE_FORBIDDEN',
  'opening balance cutover history cannot be deleted'
);
select throws_ok(
  format(
    $sql$
      delete from operations.opening_balance_cutover_lines
      where cutover_id = %L::uuid
    $sql$,
    (select result ->> 'cutoverId' from opening_balance_results where kind = 'CREATED')
  ),
  'P0001',
  'OPENING_BALANCE_CUTOVER_LINE_IMMUTABLE',
  'posted opening balance line history cannot be deleted'
);

select ok(
  not exists (
    with affected as (
      select distinct line.product_id, line.batch_id
      from operations.opening_balance_cutover_lines line
      where line.cutover_id = (
        select (result ->> 'cutoverId')::uuid
        from opening_balance_results where kind = 'CREATED'
      )
        and line.quantity > 0
    ),
    ledger as (
      select
        affected.product_id,
        affected.batch_id,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'SELLABLE'
        ), 0)::bigint as sellable_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'QUARANTINE'
        ), 0)::bigint as quarantine_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'DAMAGED'
        ), 0)::bigint as damaged_qty
      from affected
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = '00000000-0000-4000-8000-000000000042'::uuid
       and entry.product_id = affected.product_id
       and entry.batch_id = affected.batch_id
      group by affected.product_id, affected.batch_id
    )
    select 1
    from ledger
    join inventory.stock_batch_balances balance
      on balance.organization_id = '00000000-0000-4000-8000-000000000042'::uuid
     and balance.product_id = ledger.product_id
     and balance.batch_id = ledger.batch_id
    where balance.sellable_qty <> ledger.sellable_qty
       or balance.quarantine_qty <> ledger.quarantine_qty
       or balance.damaged_qty <> ledger.damaged_qty
  ),
  'opening balance batch projections remain equal to ledger totals'
);
select ok(
  not exists (
    with affected as (
      select distinct line.product_id
      from operations.opening_balance_cutover_lines line
      where line.cutover_id = (
        select (result ->> 'cutoverId')::uuid
        from opening_balance_results where kind = 'CREATED'
      )
        and line.quantity > 0
    ),
    ledger as (
      select
        affected.product_id,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'SELLABLE'
        ), 0)::bigint as sellable_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'QUARANTINE'
        ), 0)::bigint as quarantine_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'DAMAGED'
        ), 0)::bigint as damaged_qty
      from affected
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = '00000000-0000-4000-8000-000000000042'::uuid
       and entry.product_id = affected.product_id
      group by affected.product_id
    )
    select 1
    from ledger
    join inventory.stock_product_positions position
      on position.organization_id = '00000000-0000-4000-8000-000000000042'::uuid
     and position.product_id = ledger.product_id
    where position.sellable_qty <> ledger.sellable_qty
       or position.quarantine_qty <> ledger.quarantine_qty
       or position.damaged_qty <> ledger.damaged_qty
  ),
  'opening balance product projections remain equal to ledger totals'
);
select ok(
  not exists (
    select 1
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.organization_id = '00000000-0000-4000-8000-000000000042'::uuid
      and transaction.transaction_type_code = 'INITIAL_BALANCE'
      and entry.quantity_delta <= 0
  ),
  'all INITIAL_BALANCE ledger entries are positive'
);
select is(
  (
    select posted_by::text
    from operations.opening_balance_cutovers
    where id = (
      select (result ->> 'cutoverId')::uuid
      from opening_balance_results where kind = 'CREATED'
    )
  ),
  '94000000-0000-4000-8000-000000000042',
  'posted cutover retains the authenticated Admin actor'
);

select * from finish();
rollback;
