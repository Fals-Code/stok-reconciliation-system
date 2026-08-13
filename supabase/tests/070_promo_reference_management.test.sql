begin;
create extension if not exists pgtap with schema extensions;
select plan(57);

-- 1. Schema and security tests.
select has_table('catalog', 'promo_references', 'promo_references table exists');
select has_column('catalog', 'promo_references', 'id', 'promo_references has id');
select has_column('catalog', 'promo_references', 'organization_id', 'promo_references has organization_id');
select has_column('catalog', 'promo_references', 'code', 'promo_references has code');
select has_column('catalog', 'promo_references', 'name', 'promo_references has name');
select has_column('catalog', 'promo_references', 'description', 'promo_references has description');
select has_column('catalog', 'promo_references', 'is_active', 'promo_references has is_active');
select has_column('catalog', 'promo_references', 'created_at', 'promo_references has created_at');
select has_column('catalog', 'promo_references', 'created_by', 'promo_references has created_by');
select has_column('catalog', 'promo_references', 'updated_at', 'promo_references has updated_at');
select has_column('catalog', 'promo_references', 'updated_by', 'promo_references has updated_by');
select has_column('catalog', 'promo_references', 'row_version', 'promo_references has row_version');

select has_index('catalog', 'promo_references', 'uidx_promo_references_org_normalized_code', 'normalized promo reference code index exists');
select ok((select relrowsecurity from pg_class where oid='catalog.promo_references'::regclass), 'promo_references RLS is enabled');

select has_view('api', 'promo_references', 'promo_references view exists');

select function_returns('api', 'create_promo_reference', array['uuid', 'text', 'text', 'text', 'text', 'text']::text[], 'jsonb');
select function_returns('api', 'update_promo_reference', array['uuid', 'text', 'uuid', 'bigint', 'text', 'text', 'text']::text[], 'jsonb');
select function_returns('api', 'archive_promo_reference', array['uuid', 'text', 'uuid', 'bigint', 'text']::text[], 'jsonb');
select function_returns('api', 'reactivate_promo_reference', array['uuid', 'text', 'uuid', 'bigint', 'text']::text[], 'jsonb');

-- Verify Security Definer & Fixed search_path
select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'api'
      and p.proname in ('create_promo_reference', 'update_promo_reference', 'archive_promo_reference', 'reactivate_promo_reference')
      and p.prosecdef
  ),
  4::bigint,
  'all promo RPC commands are SECURITY DEFINER'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'api'
      and p.proname in ('create_promo_reference', 'update_promo_reference', 'archive_promo_reference', 'reactivate_promo_reference')
      and p.proconfig is not null
      and p.proconfig[1] like 'search_path=%'
  ),
  4::bigint,
  'all promo RPC commands have fixed search_path'
);

-- Verify no PUBLIC EXECUTE
select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where n.nspname = 'api'
      and p.proname in ('create_promo_reference', 'update_promo_reference', 'archive_promo_reference', 'reactivate_promo_reference')
      and a.grantee = 0
      and a.privilege_type = 'EXECUTE'
  ),
  0::bigint,
  'PUBLIC has no EXECUTE privilege on promo RPC commands'
);
-- Internal helper is not directly callable by any external role.
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where n.nspname = 'catalog' and p.proname = 'change_promo_reference_active_state' and a.grantee = 0 and a.privilege_type = 'EXECUTE'), 0::bigint, 'PUBLIC has no EXECUTE on internal Promo active-state helper');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where n.nspname = 'catalog' and p.proname = 'change_promo_reference_active_state' and a.grantee = 'anon'::regrole and a.privilege_type = 'EXECUTE'), 0::bigint, 'anon has no EXECUTE on internal Promo active-state helper');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where n.nspname = 'catalog' and p.proname = 'change_promo_reference_active_state' and a.grantee = 'authenticated'::regrole and a.privilege_type = 'EXECUTE'), 0::bigint, 'authenticated has no EXECUTE on internal Promo active-state helper');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where n.nspname = 'catalog' and p.proname = 'change_promo_reference_active_state' and a.grantee = 'service_role'::regrole and a.privilege_type = 'EXECUTE'), 0::bigint, 'service_role has no EXECUTE on internal Promo active-state helper');

-- 2. Seed Data
insert into app.organizations (id, code, name, timezone, is_active, created_at) values
('00000000-0000-4000-8000-000000000070', 'ORG_PROMO_70', 'Org Promo 70', 'Asia/Jakarta', true, '2026-08-13 08:00:00+07'),
('00000000-0000-4000-8000-000000000071', 'ORG_PROMO_71', 'Org Promo 71', 'Asia/Jakarta', true, '2026-08-13 08:00:00+07');

insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous) values
('00000000-0000-0000-0000-000000000000', '97000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'admin70@glowlab.invalid', '2026-08-13 08:00:00+07', '{"provider":"email","providers":["email"]}'::jsonb, '{}', '2026-08-13 08:00:00+07', '2026-08-13 08:00:00+07', false, false),
('00000000-0000-0000-0000-000000000000', '97000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'admin71@glowlab.invalid', '2026-08-13 08:00:00+07', '{"provider":"email","providers":["email"]}'::jsonb, '{}', '2026-08-13 08:00:00+07', '2026-08-13 08:00:00+07', false, false);

insert into app.user_profiles (user_id, organization_id, display_name, employee_code, role_code, is_active) values
('97000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000070', 'Admin Promo 70', 'EMP-70', 'ADMIN', true),
('97000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000071', 'Admin Promo 71', 'EMP-71', 'ADMIN', true);

-- Temp tables for test baseline and results
create temp table promo_results (kind text primary key, result jsonb not null) on commit drop;
create temp table stock_baseline (phase text primary key, snapshot jsonb not null) on commit drop;

grant select, insert, update on promo_results, stock_baseline to authenticated;

-- Stock domain baseline
insert into stock_baseline values (
  'ZERO',
  jsonb_build_object(
    'tx', (select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4000-8000-000000000070'),
    'transactions', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from inventory.stock_transactions t where t.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb),
    'ledger_count', (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4000-8000-000000000070'),
    'ledger', coalesce((select jsonb_agg(to_jsonb(e) order by e.ledger_seq) from inventory.stock_ledger_entries e where e.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb),
    'positions_count', (select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4000-8000-000000000070'),
    'positions', coalesce((select jsonb_agg(to_jsonb(p) order by p.product_id) from inventory.stock_product_positions p where p.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb),
    'balances_count', (select count(*) from inventory.stock_batch_balances where organization_id = '00000000-0000-4000-8000-000000000070'),
    'balances', coalesce((select jsonb_agg(to_jsonb(b) order by b.batch_id) from inventory.stock_batch_balances b where b.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb),
    'reservations_count', (select count(*) from inventory.stock_reservations where organization_id = '00000000-0000-4000-8000-000000000070'),
    'reservations', coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from inventory.stock_reservations r where r.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb),
    'manual_outbounds_count', (select count(*) from operations.manual_outbounds where organization_id = '00000000-0000-4000-8000-000000000070'),
    'manual_outbounds', coalesce((select jsonb_agg(to_jsonb(o) order by o.id) from operations.manual_outbounds o where o.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb)
  )
);
-- Set JWT and local role for Admin 70
select set_config('request.jwt.claim.sub', '97000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', '97000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'email', 'admin70@glowlab.invalid')::text, true);
set local role authenticated;

-- Test: cross-org validation
select throws_ok(
  $sql$select api.create_promo_reference('00000000-0000-4000-8000-000000000071', 'key-cross', 'PROMO1', 'Promo 1')$sql$,
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'Admin cannot create promo reference in another organization'
);

-- Test: blank fields validation
select throws_ok(
  $sql$select api.create_promo_reference('00000000-0000-4000-8000-000000000070', 'key-blank', '   ', 'Promo Blank')$sql$,
  'P0001',
  'PROMO_REFERENCE_REQUIRED_FIELDS_MISSING',
  'empty promo code is rejected'
);

-- Test: normal create promo
insert into promo_results select 'CREATE_OK', api.create_promo_reference(
  '00000000-0000-4000-8000-000000000070',
  'key-create-ok',
  ' promo-kemerdekaan ',
  'Promo Kemerdekaan',
  'Promo menyambut kemerdekaan RI',
  'Catatan pembuatan'
);

select is(
  (select result->>'status' from promo_results where kind = 'CREATE_OK'),
  'CREATED',
  'create promo returns CREATED status'
);

select is(
  (select result->>'code' from promo_results where kind = 'CREATE_OK'),
  'PROMO-KEMERDEKAAN',
  'promo code is normalized upper and trimmed'
);

select is(
  (select (result->>'rowVersion')::bigint from promo_results where kind = 'CREATE_OK'),
  1::bigint,
  'row version starts at 1'
);

select is(
  (select result->>'isActive' from promo_results where kind = 'CREATE_OK'),
  'true',
  'promo is active by default'
);

-- Test: audit trail create
select ok(
  exists (
    select 1
    from catalog.master_data_audit_events
    where organization_id = '00000000-0000-4000-8000-000000000070'
      and entity_type_code = 'PROMO_REFERENCE'
      and action_code = 'PROMO_REFERENCE_CREATE'
  ),
  'audit trail for PROMO_REFERENCE_CREATE is recorded'
);

-- Test: create replay (same payload same key)
insert into promo_results select 'CREATE_REPLAY', api.create_promo_reference(
  '00000000-0000-4000-8000-000000000070',
  'key-create-ok',
  ' promo-kemerdekaan ',
  'Promo Kemerdekaan',
  'Promo menyambut kemerdekaan RI',
  'Catatan pembuatan'
);

select is(
  (select result->>'promoId' from promo_results where kind = 'CREATE_REPLAY'),
  (select result->>'promoId' from promo_results where kind = 'CREATE_OK'),
  'create replay returns the exact same promoId'
);

select is(
  (select count(*) from catalog.promo_references where organization_id = '00000000-0000-4000-8000-000000000070'),
  1::bigint,
  'create replay does not duplicate promo records'
);

-- Test: key reused but different payload
select throws_ok(
  $sql$select api.create_promo_reference(
    '00000000-0000-4000-8000-000000000070',
    'key-create-ok',
    'promo-kemerdekaan',
    'Promo Kemerdekaan Berbeda',
    'Deskripsi Berbeda',
    'Catatan berbeda'
  )$sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'reusing idempotency key with different payload is rejected'
);

-- Test: duplicate code rejection
select throws_ok(
  $sql$select api.create_promo_reference(
    '00000000-0000-4000-8000-000000000070',
    'key-create-dup',
    'promo-kemerdekaan',
    'Promo Kemerdekaan Dupe'
  )$sql$,
  'P0001',
  'DUPLICATE_PROMO_CODE',
  'duplicate promo code is rejected'
);

-- Test: Update Promo
insert into promo_results select 'UPDATE_OK', api.update_promo_reference(
  '00000000-0000-4000-8000-000000000070',
  'key-update-ok',
  (select (result->>'promoId')::uuid from promo_results where kind = 'CREATE_OK'),
  1,
  'Promo Kemerdekaan RI',
  'Deskripsi ter-update',
  'Catatan update'
);

select is(
  (select result->>'status' from promo_results where kind = 'UPDATE_OK'),
  'UPDATED',
  'update returns UPDATED status'
);

select is(
  (select (result->>'rowVersion')::bigint from promo_results where kind = 'UPDATE_OK'),
  2::bigint,
  'update increments row version'
);

-- Test: audit trail update
select ok(
  exists (
    select 1
    from catalog.master_data_audit_events
    where organization_id = '00000000-0000-4000-8000-000000000070'
      and entity_type_code = 'PROMO_REFERENCE'
      and action_code = 'PROMO_REFERENCE_UPDATE'
      and (before_snapshot->>'code') = 'PROMO-KEMERDEKAAN'  -- normalized code was saved as sku/code snapshot helper
  ),
  'audit trail for PROMO_REFERENCE_UPDATE is recorded'
);

-- Test: stale update concurrency check
select throws_ok(
  format(
    $sql$select api.update_promo_reference(
      '00000000-0000-4000-8000-000000000070',
      'key-update-stale',
      '%s',
      1, -- expected version is stale (current is 2)
      'Promo Stale Update'
    )$sql$,
    (select result->>'promoId' from promo_results where kind = 'CREATE_OK')
  ),
  'P0001',
  'CONCURRENCY_ERROR',
  'stale version update is rejected with CONCURRENCY_ERROR'
);

-- Test: Archive (Deactivate)
insert into promo_results select 'ARCHIVE_OK', api.archive_promo_reference(
  '00000000-0000-4000-8000-000000000070',
  'key-archive-ok',
  (select (result->>'promoId')::uuid from promo_results where kind = 'CREATE_OK'),
  2,
  'Selesai masa berlaku'
);

select is(
  (select result->>'isActive' from promo_results where kind = 'ARCHIVE_OK'),
  'false',
  'promo is successfully deactivated/archived'
);

-- Test: archive audit trail
select ok(
  exists (
    select 1
    from catalog.master_data_audit_events
    where organization_id = '00000000-0000-4000-8000-000000000070'
      and entity_type_code = 'PROMO_REFERENCE'
      and action_code = 'PROMO_REFERENCE_DEACTIVATE'
  ),
  'deactivate audit trail recorded'
);

-- Test: archive already archived rejection
select throws_ok(
  format(
    $sql$select api.archive_promo_reference(
      '00000000-0000-4000-8000-000000000070',
      'key-archive-again',
      '%s',
      3
    )$sql$,
    (select result->>'promoId' from promo_results where kind = 'CREATE_OK')
  ),
  'P0001',
  'PROMO_REFERENCE_ALREADY_INACTIVE',
  'archiving already archived promo is rejected'
);

-- Test: Reactivate
insert into promo_results select 'REACTIVATE_OK', api.reactivate_promo_reference(
  '00000000-0000-4000-8000-000000000070',
  'key-reactivate-ok',
  (select (result->>'promoId')::uuid from promo_results where kind = 'CREATE_OK'),
  3,
  'Mulai masa berlaku baru'
);

select is(
  (select result->>'isActive' from promo_results where kind = 'REACTIVATE_OK'),
  'true',
  'promo is successfully reactivated'
);

-- Test: reactivate audit trail
select ok(
  exists (
    select 1
    from catalog.master_data_audit_events
    where organization_id = '00000000-0000-4000-8000-000000000070'
      and entity_type_code = 'PROMO_REFERENCE'
      and action_code = 'PROMO_REFERENCE_REACTIVATE'
  ),
  'reactivate audit trail recorded'
);

-- Test: reactivate already active rejection
select throws_ok(
  format(
    $sql$select api.reactivate_promo_reference(
      '00000000-0000-4000-8000-000000000070',
      'key-reactivate-again',
      '%s',
      4
    )$sql$,
    (select result->>'promoId' from promo_results where kind = 'CREATE_OK')
  ),
  'P0001',
  'PROMO_REFERENCE_ALREADY_ACTIVE',
  'reactivating already active promo is rejected'
);

-- Test: RLS organization isolation read model
-- Switch to Admin 71
select set_config('request.jwt.claim.sub', '97000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', '97000000-0000-4000-8000-000000000002', 'role', 'authenticated', 'email', 'admin71@glowlab.invalid')::text, true);

select is(
  (select count(*) from api.promo_references),
  0::bigint,
  'Admin of another organization cannot read promos of Org 70'
);

-- Restore to Admin 70 for final checks
select set_config('request.jwt.claim.sub', '97000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', '97000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'email', 'admin70@glowlab.invalid')::text, true);

-- Test: physical delete forbidden (lapis 1: authenticated role)
select throws_ok(
  format(
    $sql$delete from catalog.promo_references where id = '%s'$sql$,
    (select result->>'promoId' from promo_results where kind = 'CREATE_OK')
  ),
  '42501', -- permission denied
  NULL,
  'authenticated role cannot delete from promo_references'
);

-- Test: physical delete forbidden (lapis 2: trusted/postgres role via trigger)
reset role;
select throws_ok(
  format(
    $sql$delete from catalog.promo_references where id = '%s'$sql$,
    (select result->>'promoId' from promo_results where kind = 'CREATE_OK')
  ),
  'P0001', -- trigger exception
  'PROMO_REFERENCE_DELETE_FORBIDDEN',
  'trusted role is forbidden from physical delete by trigger'
);

-- Restore to Admin 70 for final checks
select set_config('request.jwt.claim.sub', '97000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', '97000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'email', 'admin70@glowlab.invalid')::text, true);
set local role authenticated;


-- Deep stock state must remain byte-for-byte identical across all Promo master mutations.
select is(
  jsonb_build_object(
    'tx', (select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4000-8000-000000000070'),
    'transactions', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from inventory.stock_transactions t where t.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb),
    'ledger_count', (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4000-8000-000000000070'),
    'ledger', coalesce((select jsonb_agg(to_jsonb(e) order by e.ledger_seq) from inventory.stock_ledger_entries e where e.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb),
    'positions_count', (select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4000-8000-000000000070'),
    'positions', coalesce((select jsonb_agg(to_jsonb(p) order by p.product_id) from inventory.stock_product_positions p where p.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb),
    'balances_count', (select count(*) from inventory.stock_batch_balances where organization_id = '00000000-0000-4000-8000-000000000070'),
    'balances', coalesce((select jsonb_agg(to_jsonb(b) order by b.batch_id) from inventory.stock_batch_balances b where b.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb),
    'reservations_count', (select count(*) from inventory.stock_reservations where organization_id = '00000000-0000-4000-8000-000000000070'),
    'reservations', coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from inventory.stock_reservations r where r.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb),
    'manual_outbounds_count', (select count(*) from operations.manual_outbounds where organization_id = '00000000-0000-4000-8000-000000000070'),
    'manual_outbounds', coalesce((select jsonb_agg(to_jsonb(o) order by o.id) from operations.manual_outbounds o where o.organization_id = '00000000-0000-4000-8000-000000000070'), '[]'::jsonb)
  ),
  (select snapshot from stock_baseline where phase = 'ZERO'),
  'Promo create/update/deactivate/reactivate preserve deep stock state'
);
-- Test: Stock-neutrality proof
select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000070'
  ),
  (
    select (snapshot->>'tx')::bigint
    from stock_baseline
    where phase = 'ZERO'
  ),
  'Promo reference mutations did not insert any stock transactions'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id = '00000000-0000-4000-8000-000000000070'
  ),
  (
    select (snapshot->>'ledger_count')::bigint
    from stock_baseline
    where phase = 'ZERO'
  ),
  'Promo reference mutations did not insert any stock ledger entries'
);

select is(
  (
    select count(*)
    from inventory.stock_product_positions
    where organization_id = '00000000-0000-4000-8000-000000000070'
  ),
  (
    select (snapshot->>'positions_count')::bigint
    from stock_baseline
    where phase = 'ZERO'
  ),
  'Promo reference mutations did not modify stock product positions count'
);

select is(
  (
    select count(*)
    from inventory.stock_batch_balances
    where organization_id = '00000000-0000-4000-8000-000000000070'
  ),
  (
    select (snapshot->>'balances_count')::bigint
    from stock_baseline
    where phase = 'ZERO'
  ),
  'Promo reference mutations did not modify stock batch balances count'
);

select is(
  (
    select count(*)
    from inventory.stock_reservations
    where organization_id = '00000000-0000-4000-8000-000000000070'
  ),
  (
    select (snapshot->>'reservations_count')::bigint
    from stock_baseline
    where phase = 'ZERO'
  ),
  'Promo reference mutations did not modify stock reservations count'
);

select is(
  (
    select count(*)
    from operations.manual_outbounds
    where organization_id = '00000000-0000-4000-8000-000000000070'
  ),
  (
    select (snapshot->>'manual_outbounds_count')::bigint
    from stock_baseline
    where phase = 'ZERO'
  ),
  'Promo reference mutations did not insert any manual outbounds'
);

-- Finish pgTAP tests
select * from finish();
rollback;
