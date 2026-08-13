begin;

select plan(23);

select has_function('api', 'product_stock_explanation', array['uuid'], 'product stock explanation read contract exists');
select ok(not (select p.prosecdef from pg_proc p where p.oid = 'api.product_stock_explanation(uuid)'::regprocedure), 'read contract is security invoker');
select ok((select p.provolatile = 's' from pg_proc p where p.oid = 'api.product_stock_explanation(uuid)'::regprocedure), 'read contract is stable');
select ok((select p.proconfig @> array['search_path=pg_catalog, catalog, inventory'] from pg_proc p where p.oid = 'api.product_stock_explanation(uuid)'::regprocedure), 'read contract fixes search path');
select ok(has_function_privilege('authenticated', 'api.product_stock_explanation(uuid)', 'EXECUTE'), 'authenticated may read explanation');
select ok(not has_function_privilege('anon', 'api.product_stock_explanation(uuid)', 'EXECUTE'), 'anon cannot read explanation');
select ok(not has_function_privilege('public', 'api.product_stock_explanation(uuid)', 'EXECUTE'), 'PUBLIC has no explanation execute grant');

insert into auth.users(instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4072-8000-000000000001', 'authenticated', 'authenticated', 'pgtap.explain.072@glowlab.invalid', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), false, false);
insert into app.user_profiles(user_id, organization_id, display_name, employee_code, role_code, is_active)
values ('00000000-0000-4072-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'Explain 072 Admin', 'PGTAP-EXPLAIN-072', 'ADMIN', true);
insert into app.organizations(id, code, name, timezone, is_active)
values ('00000000-0000-4072-8000-000000000002', 'PGTAP_EXPLAIN_072_OTHER', 'Explain Other', 'Asia/Jakarta', true);
insert into catalog.products(id, organization_id, sku, name)
values
  ('00000000-0000-4072-8000-000000000011', '00000000-0000-4000-8000-000000000001', 'EXPLAIN-ZERO-072', 'Explain zero history'),
  ('00000000-0000-4072-8000-000000000012', '00000000-0000-4000-8000-000000000001', 'EXPLAIN-MISMATCH-072', 'Explain mismatch'),
  ('00000000-0000-4072-8000-000000000013', '00000000-0000-4072-8000-000000000002', 'EXPLAIN-OTHER-072', 'Explain other');
insert into inventory.stock_product_positions(organization_id, product_id, sellable_qty, quarantine_qty, damaged_qty, reserved_qty, last_ledger_seq, version)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4072-8000-000000000011', 0, 0, 0, 0, 0, 0),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4072-8000-000000000012', 3, 0, 0, 1, 0, 0),
  ('00000000-0000-4072-8000-000000000002', '00000000-0000-4072-8000-000000000013', 9, 0, 0, 0, 0, 0);

select set_config('request.jwt.claim.sub', '00000000-0000-4072-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4072-8000-000000000001', 'role', 'authenticated')::text, true);
set local role authenticated;

create temp table explain_before as
select
  (select count(*) from inventory.stock_transactions) as transaction_count,
  (select count(*) from inventory.stock_ledger_entries) as ledger_count,
  (select count(*) from inventory.stock_product_positions) as projection_count,
  (select count(*) from inventory.stock_reservations) as reservation_count,
  (select count(*) from reconciliation.runs) as reconciliation_run_count,
  (select count(*) from reconciliation.issues) as reconciliation_issue_count,
  (select count(*) from inventory.idempotency_commands) as idempotency_count;

create temp table serum_explanation as
select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) as value;

select is((select (value -> 'ledger' ->> 'sellableQty')::bigint from serum_explanation), (select coalesce(sum(quantity_delta) filter (where bucket_code = 'SELLABLE'), 0)::bigint from inventory.stock_ledger_entries where product_id = '30000000-0000-4000-8000-000000000001'), 'SELLABLE is exact signed ledger sum');
select is((select (value -> 'ledger' ->> 'quarantineQty')::bigint from serum_explanation), (select coalesce(sum(quantity_delta) filter (where bucket_code = 'QUARANTINE'), 0)::bigint from inventory.stock_ledger_entries where product_id = '30000000-0000-4000-8000-000000000001'), 'QUARANTINE is exact signed ledger sum');
select is((select (value -> 'ledger' ->> 'damagedQty')::bigint from serum_explanation), (select coalesce(sum(quantity_delta) filter (where bucket_code = 'DAMAGED'), 0)::bigint from inventory.stock_ledger_entries where product_id = '30000000-0000-4000-8000-000000000001'), 'DAMAGED is exact signed ledger sum');
select is((select (value -> 'ledger' ->> 'onHandQty')::bigint from serum_explanation), (select ((value -> 'ledger' ->> 'sellableQty')::bigint + (value -> 'ledger' ->> 'quarantineQty')::bigint + (value -> 'ledger' ->> 'damagedQty')::bigint) from serum_explanation), 'ON_HAND equals physical bucket sum');
select is((select (value -> 'projection' ->> 'availableQty')::bigint from serum_explanation), (select (value -> 'projection' ->> 'sellableQty')::bigint - (value -> 'projection' ->> 'reservedQty')::bigint from serum_explanation), 'Available equals projection sellable minus reserved');
select is((select (value ->> 'ledgerBoundarySeq')::bigint from serum_explanation), (select coalesce(max(ledger_seq), 0)::bigint from inventory.stock_ledger_entries where product_id = '30000000-0000-4000-8000-000000000001'), 'deterministic boundary is maximum included ledger sequence');
select is((select coalesce(sum((grouped.value ->> 'sellableDelta')::bigint), 0)::bigint from serum_explanation, jsonb_array_elements(value -> 'groupedMovements') grouped(value)), (select (value -> 'ledger' ->> 'sellableQty')::bigint from serum_explanation), 'grouped sellable totals reconcile to aggregate');
select is((select coalesce(sum((grouped.value ->> 'onHandDelta')::bigint), 0)::bigint from serum_explanation, jsonb_array_elements(value -> 'groupedMovements') grouped(value)), (select (value -> 'ledger' ->> 'onHandQty')::bigint from serum_explanation), 'grouped on hand totals reconcile to aggregate');
select ok((select value -> 'comparison' ->> 'sellableMatches' = 'true' from serum_explanation), 'matching projection is explicit');

select is(api.product_stock_explanation('00000000-0000-4072-8000-000000000011'::uuid), jsonb_build_object('ledgerBoundarySeq', 0, 'ledger', jsonb_build_object('sellableQty', 0, 'quarantineQty', 0, 'damagedQty', 0, 'onHandQty', 0), 'projection', jsonb_build_object('sellableQty', 0, 'quarantineQty', 0, 'damagedQty', 0, 'reservedQty', 0, 'availableQty', 0, 'onHandQty', 0), 'comparison', jsonb_build_object('sellableMatches', true, 'quarantineMatches', true, 'damagedMatches', true, 'onHandMatches', true), 'groupedMovements', '[]'::jsonb), 'zero ledger plus zero projection is a normal empty explanation');
select ok((api.product_stock_explanation('00000000-0000-4072-8000-000000000012'::uuid) -> 'comparison' ->> 'sellableMatches') = 'false', 'zero ledger plus nonzero projection is explicit mismatch');
select is((api.product_stock_explanation('00000000-0000-4072-8000-000000000012'::uuid) -> 'projection' ->> 'availableQty')::bigint, 2::bigint, 'reservation remains neutral and only affects Available');
select is(api.product_stock_explanation('00000000-0000-4072-8000-000000000013'::uuid), null::jsonb, 'cross-organization product is safe no-data');

select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid);
select api.product_stock_explanation('00000000-0000-4072-8000-000000000011'::uuid);
reset role;

select is((select row((select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4000-8000-000000000001'), (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4000-8000-000000000001'), (select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4000-8000-000000000001'), (select count(*) from inventory.stock_reservations where organization_id = '00000000-0000-4000-8000-000000000001'), (select count(*) from reconciliation.runs where organization_id = '00000000-0000-4000-8000-000000000001'), (select count(*) from reconciliation.issues where organization_id = '00000000-0000-4000-8000-000000000001'), (select count(*) from inventory.idempotency_commands where organization_id = '00000000-0000-4000-8000-000000000001'))::text), (select row(transaction_count, ledger_count, projection_count, reservation_count, reconciliation_run_count, reconciliation_issue_count, idempotency_count)::text from explain_before), 'repeated reads create zero transaction, ledger, projection, reservation, reconciliation, issue, and idempotency effects');

select position('sum(quantity_delta) filter (where bucket_code = ''SELLABLE'')' in (select pg_get_functiondef('api.product_stock_explanation(uuid)'::regprocedure))) > 0 as test;
select ok((select test from (select position('sum(quantity_delta) filter (where bucket_code = ''SELLABLE'')' in (select pg_get_functiondef('api.product_stock_explanation(uuid)'::regprocedure))) > 0 as test) assertion), 'function keeps signed bucket aggregation');
select ok(not ((select pg_get_functiondef('api.product_stock_explanation(uuid)'::regprocedure)) ~* '(insert|update|delete|run_reconciliation)'), 'read contract contains no mutation or reconciliation command');

select * from finish();
rollback;
