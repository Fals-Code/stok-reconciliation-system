begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

select has_view(
  'api'::name,
  'stocktake_list'::name,
  'api.stocktake_list exists'
);

select col_type_is(
  'api'::name,
  'stocktake_list'::name,
  'variance_line_count'::name,
  'bigint'::name
);

select ok(
  has_table_privilege(
    'authenticated',
    'api.stocktake_list',
    'SELECT'
  ),
  'authenticated users may read stocktake list'
);

select ok(
  not has_table_privilege(
    'anon',
    'api.stocktake_list',
    'SELECT'
  ),
  'anonymous users cannot read stocktake list'
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
  '97000000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.stocktake.list@glowlab.invalid',
  '2026-07-15 08:00:00+07'::timestamptz,
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-15 08:00:00+07'::timestamptz,
  '2026-07-15 08:00:00+07'::timestamptz,
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
  '97000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Stocktake List Admin',
  'PGTAP-STK-LIST',
  'ADMIN',
  true
);

create temp table stocktake_list_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update
on stocktake_list_results
to authenticated;

select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000001',
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
    '97000000-0000-4000-8000-000000000001',
    'role',
    'authenticated',
    'email',
    'pgtap.stocktake.list@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

insert into stocktake_list_results (kind, result)
select
  'BLIND_CREATE',
  api.create_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-LIST-BLIND-CREATE-001',
    'Blind list confidentiality fixture',
    'CYCLE',
    'CONTINUOUS',
    'BLIND',
    jsonb_build_object(
      'mode',
      'BATCHES',
      'batchIds',
      jsonb_build_array(
        '40000000-0000-4000-8000-000000000001'
      ),
      'bucketCodes',
      jsonb_build_array('SELLABLE'),
      'includeZeroSystemBalance',
      false,
      'includeInactiveWithBalance',
      false,
      'includeBlockedBatches',
      false,
      'includeExpiredBatches',
      true
    ),
    '2026-07-15 09:00:00+07'::timestamptz,
    'Blind stocktake list fixture.',
    '{"fixture": "stocktake-list-blind"}'::jsonb
  );

insert into stocktake_list_results (kind, result)
select
  'BLIND_PREPARE',
  api.prepare_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-LIST-BLIND-PREPARE-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_list_results
      where kind = 'BLIND_CREATE'
    ),
    '{"fixture": "stocktake-list-blind-prepare"}'::jsonb
  );

insert into stocktake_list_results (kind, result)
select
  'BLIND_START',
  api.start_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-LIST-BLIND-START-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_list_results
      where kind = 'BLIND_CREATE'
    ),
    '{"fixture": "stocktake-list-blind-start"}'::jsonb
  );

insert into stocktake_list_results (kind, result)
select
  'BLIND_COUNT',
  api.submit_stocktake_count(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-LIST-BLIND-COUNT-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_list_results
      where kind = 'BLIND_CREATE'
    ),
    (
      select line.id
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_list_results
        where kind = 'BLIND_CREATE'
      )
    ),
    (
      select line.system_qty_at_snapshot + 1
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_list_results
        where kind = 'BLIND_CREATE'
      )
    ),
    false,
    'MANUAL_ENTRY',
    'Blind variance fixture.',
    '{"fixture": "stocktake-list-blind-count"}'::jsonb
  );

insert into stocktake_list_results (kind, result)
select
  'NON_BLIND_CREATE',
  api.create_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-LIST-NONBLIND-CREATE-001',
    'Non-blind list visibility fixture',
    'CYCLE',
    'CONTINUOUS',
    'NON_BLIND',
    jsonb_build_object(
      'mode',
      'BATCHES',
      'batchIds',
      jsonb_build_array(
        '40000000-0000-4000-8000-000000000001'
      ),
      'bucketCodes',
      jsonb_build_array('SELLABLE'),
      'includeZeroSystemBalance',
      false,
      'includeInactiveWithBalance',
      false,
      'includeBlockedBatches',
      false,
      'includeExpiredBatches',
      true
    ),
    '2026-07-15 09:30:00+07'::timestamptz,
    'Non-blind stocktake list fixture.',
    '{"fixture": "stocktake-list-nonblind"}'::jsonb
  );

insert into stocktake_list_results (kind, result)
select
  'NON_BLIND_PREPARE',
  api.prepare_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-LIST-NONBLIND-PREPARE-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_list_results
      where kind = 'NON_BLIND_CREATE'
    ),
    '{"fixture": "stocktake-list-nonblind-prepare"}'::jsonb
  );

insert into stocktake_list_results (kind, result)
select
  'NON_BLIND_START',
  api.start_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-LIST-NONBLIND-START-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_list_results
      where kind = 'NON_BLIND_CREATE'
    ),
    '{"fixture": "stocktake-list-nonblind-start"}'::jsonb
  );

insert into stocktake_list_results (kind, result)
select
  'NON_BLIND_COUNT',
  api.submit_stocktake_count(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-LIST-NONBLIND-COUNT-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_list_results
      where kind = 'NON_BLIND_CREATE'
    ),
    (
      select line.id
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_list_results
        where kind = 'NON_BLIND_CREATE'
      )
    ),
    (
      select line.system_qty_at_snapshot + 1
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_list_results
        where kind = 'NON_BLIND_CREATE'
      )
    ),
    false,
    'MANUAL_ENTRY',
    'Non-blind variance fixture.',
    '{"fixture": "stocktake-list-nonblind-count"}'::jsonb
  );

select is(
  (
    select counted_line_count
    from api.stocktake_list
    where stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_list_results
      where kind = 'BLIND_CREATE'
    )
  ),
  1::bigint,
  'blind counting keeps progress visible'
);

select ok(
  (
    select variance_line_count is null
    from api.stocktake_list
    where stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_list_results
      where kind = 'BLIND_CREATE'
    )
  ),
  'blind counting hides variance line count'
);

select is(
  (
    select variance_line_count
    from api.stocktake_list
    where stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_list_results
      where kind = 'NON_BLIND_CREATE'
    )
  ),
  1::bigint,
  'non-blind counting exposes variance line count'
);

reset role;

update operations.stocktakes
set
  status_code = 'REVIEW',
  counting_completed_at = '2026-07-15 10:00:00+07'::timestamptz
where id = (
  select (result ->> 'stocktakeId')::uuid
  from stocktake_list_results
  where kind = 'BLIND_CREATE'
);

set local role authenticated;

select is(
  (
    select variance_line_count
    from api.stocktake_list
    where stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_list_results
      where kind = 'BLIND_CREATE'
    )
  ),
  1::bigint,
  'blind review exposes variance line count after counting ends'
);

reset role;

select * from finish();

rollback;