begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_view('api', 'ledger_explorer', 'ledger explorer list view exists');
select has_view('api', 'ledger_transaction_detail', 'exact transaction detail view exists');
select has_view('api', 'ledger_reversal_links', 'reversal linkage view exists');
select has_view('api', 'ledger_stock_story', 'stock story view exists');
select has_column('api', 'ledger_explorer', 'ledger_seq', 'cursor sequence is exposed');
select has_column('api', 'ledger_explorer', 'occurred_at', 'occurred time is exposed');
select has_column('api', 'ledger_explorer', 'recorded_at', 'recorded time is exposed');
select has_column('api', 'ledger_explorer', 'quantity_direction', 'quantity direction is exposed');
select has_column('api', 'ledger_explorer', 'reversal_state', 'reversal state is exposed');
select has_column('api', 'ledger_reversal_links', 'original_entry_id', 'original entry linkage is exposed');
select has_column('api', 'ledger_reversal_links', 'reversal_entry_id', 'reversal entry linkage is exposed');
select has_index('inventory', 'stock_ledger_entries', 'idx_stock_ledger_entries_org_seq', 'global cursor index is organization-first');
select has_index('inventory', 'stock_transactions', 'idx_stock_transactions_org_recorded', 'recorded-time index is organization-first');
select ok(
  (select reloptions @> array['security_invoker=true', 'security_barrier=true']
   from pg_class where oid = 'api.ledger_explorer'::regclass),
  'ledger explorer is an invoker security-barrier view'
);
select ok(
  (select reloptions @> array['security_invoker=true', 'security_barrier=true']
   from pg_class where oid = 'api.ledger_transaction_detail'::regclass),
  'transaction detail is an invoker security-barrier view'
);
select ok(
  (select relrowsecurity
   from pg_class where oid = 'inventory.stock_transactions'::regclass),
  'transactions retain RLS'
);
select ok(
  (select relrowsecurity
   from pg_class where oid = 'inventory.stock_ledger_entries'::regclass),
  'ledger entries retain RLS'
);
select ok(has_table_privilege('authenticated', 'api.ledger_explorer', 'SELECT'), 'authenticated can read explorer');
select ok(has_table_privilege('service_role', 'api.ledger_explorer', 'SELECT'), 'service role can read explorer');
select ok(not has_table_privilege('anon', 'api.ledger_explorer', 'SELECT'), 'anon cannot read explorer');
select ok(not has_table_privilege('authenticated', 'api.ledger_explorer', 'INSERT'), 'explorer has no direct insert');
select ok(not has_table_privilege('authenticated', 'api.ledger_explorer', 'UPDATE'), 'explorer has no direct update');
select ok(not has_table_privilege('authenticated', 'api.ledger_explorer', 'DELETE'), 'explorer has no direct delete');

insert into app.organizations(id, code, name, timezone, is_active, created_at)
values
  ('00000000-0000-4059-8000-000000000001', 'PGTAP_LEDGER_059_A', 'Ledger Explorer 059 A', 'Asia/Jakarta', true, '2026-07-26 08:00:00+07'),
  ('00000000-0000-4059-8000-000000000002', 'PGTAP_LEDGER_059_B', 'Ledger Explorer 059 B', 'Asia/Jakarta', true, '2026-07-26 08:00:00+07');

insert into auth.users(instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4059-8000-000000000001', 'authenticated', 'authenticated', 'pgtap.ledger.059@glowlab.invalid', '2026-07-26 08:00:00+07', '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', false, false);

insert into app.user_profiles(user_id, organization_id, display_name, employee_code, role_code, is_active)
values ('00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000001', 'Ledger Explorer Admin', 'PGTAP-LEDGER-059', 'ADMIN', true);

insert into catalog.channels(id, code, name, is_marketplace, is_active)
values ('00000000-0000-4059-8000-000000000011', 'PGTAP_LEDGER_059', 'Ledger Explorer Channel 059', false, true);

insert into catalog.movement_reasons(id, code, name, direction_code, requires_note, is_system, is_active)
values ('00000000-0000-4059-8000-000000000012', 'PGTAP_LEDGER_059', 'Ledger Explorer Reason 059', 'ADJUSTMENT', false, true, true);

insert into catalog.products(id, organization_id, sku, name, created_at)
values
  ('00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000001', 'LEDGER-059-A', 'Ledger Product 059', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4059-8000-000000000102', '00000000-0000-4059-8000-000000000002', 'LEDGER-059-B', 'Other Ledger Product 059', '2026-07-26 08:00:00+07');

insert into catalog.product_batches(id, organization_id, product_id, batch_code, expiry_date, created_at)
values
  ('00000000-0000-4059-8000-000000000201', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000101', 'LEDGER-BATCH-059-A1', '2027-12-31', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4059-8000-000000000202', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000101', 'LEDGER-BATCH-059-A2', '2028-01-31', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4059-8000-000000000203', '00000000-0000-4059-8000-000000000002', '00000000-0000-4059-8000-000000000102', 'LEDGER-BATCH-059-B1', '2028-02-28', '2026-07-26 08:00:00+07');

insert into inventory.idempotency_commands(id, organization_id, scope, key, request_hash, status_code, started_at, completed_at, response_snapshot)
values
  ('00000000-0000-4059-8000-000000000501', '00000000-0000-4059-8000-000000000001', 'PGTAP_LEDGER_059', 'INITIAL', repeat('1', 64), 'SUCCEEDED', '2026-07-26 08:00:00+07', '2026-07-26 08:00:01+07', '{}'),
  ('00000000-0000-4059-8000-000000000502', '00000000-0000-4059-8000-000000000001', 'PGTAP_LEDGER_059', 'RECEIPT', repeat('2', 64), 'SUCCEEDED', '2026-07-26 08:00:00+07', '2026-07-26 08:00:01+07', '{}'),
  ('00000000-0000-4059-8000-000000000503', '00000000-0000-4059-8000-000000000001', 'PGTAP_LEDGER_059', 'REVERSAL', repeat('3', 64), 'SUCCEEDED', '2026-07-26 08:00:00+07', '2026-07-26 08:00:01+07', '{}'),
  ('00000000-0000-4059-8000-000000000504', '00000000-0000-4059-8000-000000000001', 'PGTAP_LEDGER_059', 'OUTBOUND', repeat('4', 64), 'SUCCEEDED', '2026-07-26 08:00:00+07', '2026-07-26 08:00:01+07', '{}'),
  ('00000000-0000-4059-8000-000000000505', '00000000-0000-4059-8000-000000000001', 'PGTAP_LEDGER_059', 'INSPECTION', repeat('5', 64), 'SUCCEEDED', '2026-07-26 08:00:00+07', '2026-07-26 08:00:01+07', '{}'),
  ('00000000-0000-4059-8000-000000000506', '00000000-0000-4059-8000-000000000001', 'PGTAP_LEDGER_059', 'STOCKTAKE', repeat('6', 64), 'SUCCEEDED', '2026-07-26 08:00:00+07', '2026-07-26 08:00:01+07', '{}'),
  ('00000000-0000-4059-8000-000000000507', '00000000-0000-4059-8000-000000000002', 'PGTAP_LEDGER_059', 'OTHER', repeat('7', 64), 'SUCCEEDED', '2026-07-26 08:00:00+07', '2026-07-26 08:00:01+07', '{}');

insert into inventory.stock_transactions(id, organization_id, transaction_no, transaction_type_code, reason_id, reason_code_snapshot, channel_id, channel_code_snapshot, source_type_code, source_id, source_ref_snapshot, occurred_at, recorded_at, effective_local_date, process_name, created_by_role_code, correlation_id, idempotency_command_id, reversal_of_transaction_id, note, metadata)
values
  ('00000000-0000-4059-8000-000000000301', '00000000-0000-4059-8000-000000000001', 'LEDGER-059-INITIAL', 'INITIAL_BALANCE', '00000000-0000-4059-8000-000000000012', 'PGTAP_LEDGER_059', '00000000-0000-4059-8000-000000000011', 'PGTAP_LEDGER_059', 'OPENING_BALANCE', '00000000-0000-4059-8000-000000000901', 'LEDGER-059-INITIAL', '2026-07-26 09:00:00+07', '2026-07-26 09:00:01+07', '2026-07-26', 'pgtap-ledger-059', 'ADMIN', '00000000-0000-4059-8000-000000000911', '00000000-0000-4059-8000-000000000501', null, 'Opening balance evidence', '{"fixture":"ledger-059"}'),
  ('00000000-0000-4059-8000-000000000302', '00000000-0000-4059-8000-000000000001', 'LEDGER-059-RECEIPT', 'RECEIPT', '00000000-0000-4059-8000-000000000012', 'PGTAP_LEDGER_059', '00000000-0000-4059-8000-000000000011', 'PGTAP_LEDGER_059', 'RETURN_RECEIPT', '00000000-0000-4059-8000-000000000921', 'RETURN-059-RECEIPT', '2026-07-26 09:00:00+07', '2026-07-26 09:00:02+07', '2026-07-26', 'pgtap-ledger-059', 'ADMIN', '00000000-0000-4059-8000-000000000912', '00000000-0000-4059-8000-000000000502', null, 'Return receipt evidence', '{"fixture":"ledger-059"}'),
  ('00000000-0000-4059-8000-000000000303', '00000000-0000-4059-8000-000000000001', 'LEDGER-059-REVERSAL', 'REVERSAL', '00000000-0000-4059-8000-000000000012', 'PGTAP_LEDGER_059', '00000000-0000-4059-8000-000000000011', 'PGTAP_LEDGER_059', 'CORRECTION', '00000000-0000-4059-8000-000000000302', 'LEDGER-059-RECEIPT', '2026-07-26 09:00:00+07', '2026-07-26 09:00:03+07', '2026-07-26', 'pgtap-ledger-059', 'ADMIN', '00000000-0000-4059-8000-000000000913', '00000000-0000-4059-8000-000000000503', '00000000-0000-4059-8000-000000000302', 'Correction reversal evidence', '{"fixture":"ledger-059"}'),
  ('00000000-0000-4059-8000-000000000304', '00000000-0000-4059-8000-000000000001', 'LEDGER-059-OUTBOUND', 'MARKETPLACE_OUTBOUND', '00000000-0000-4059-8000-000000000012', 'PGTAP_LEDGER_059', '00000000-0000-4059-8000-000000000011', 'PGTAP_LEDGER_059', 'MARKETPLACE_SHIPMENT', '00000000-0000-4059-8000-000000000922', 'SHIPMENT-059-FEFO', '2026-07-26 09:00:00+07', '2026-07-26 09:00:04+07', '2026-07-26', 'pgtap-ledger-059', 'ADMIN', '00000000-0000-4059-8000-000000000914', '00000000-0000-4059-8000-000000000504', null, 'Split FEFO evidence', '{"fixture":"ledger-059"}'),
  ('00000000-0000-4059-8000-000000000305', '00000000-0000-4059-8000-000000000001', 'LEDGER-059-INSPECTION', 'RETURN_INSPECTION_TRANSFER', '00000000-0000-4059-8000-000000000012', 'PGTAP_LEDGER_059', '00000000-0000-4059-8000-000000000011', 'PGTAP_LEDGER_059', 'RETURN_INSPECTION', '00000000-0000-4059-8000-000000000923', 'RETURN-059-SELLABLE', '2026-07-26 09:00:00+07', '2026-07-26 09:00:05+07', '2026-07-26', 'pgtap-ledger-059', 'ADMIN', '00000000-0000-4059-8000-000000000915', '00000000-0000-4059-8000-000000000505', null, 'SELLABLE return evidence', '{"fixture":"ledger-059"}'),
  ('00000000-0000-4059-8000-000000000306', '00000000-0000-4059-8000-000000000001', 'LEDGER-059-STOCKTAKE', 'STOCKTAKE_ADJUSTMENT', '00000000-0000-4059-8000-000000000012', 'PGTAP_LEDGER_059', '00000000-0000-4059-8000-000000000011', 'PGTAP_LEDGER_059', 'STOCKTAKE', '00000000-0000-4059-8000-000000000924', 'STOCKTAKE-059', '2026-07-26 09:00:00+07', '2026-07-26 09:00:06+07', '2026-07-26', 'pgtap-ledger-059', 'ADMIN', '00000000-0000-4059-8000-000000000916', '00000000-0000-4059-8000-000000000506', null, 'Stocktake evidence', '{"fixture":"ledger-059"}'),
  ('00000000-0000-4059-8000-000000000307', '00000000-0000-4059-8000-000000000002', 'LEDGER-059-OTHER', 'RECEIPT', '00000000-0000-4059-8000-000000000012', 'PGTAP_LEDGER_059', '00000000-0000-4059-8000-000000000011', 'PGTAP_LEDGER_059', 'OTHER_ORG', '00000000-0000-4059-8000-000000000925', 'OTHER-059', '2026-07-26 09:00:00+07', '2026-07-26 09:00:07+07', '2026-07-26', 'pgtap-ledger-059', 'ADMIN', '00000000-0000-4059-8000-000000000917', '00000000-0000-4059-8000-000000000507', null, 'Other organization evidence', '{"fixture":"ledger-059"}');

insert into inventory.stock_ledger_entries(id, organization_id, transaction_id, line_no, product_id, batch_id, product_sku_snapshot, batch_code_snapshot, expiry_date_snapshot, bucket_code, quantity_delta, entry_role_code, pair_no, source_line_ref, occurred_at, recorded_at, created_at)
values
  ('00000000-0000-4059-8000-000000000401', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000301', 1, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000201', 'LEDGER-059-A', 'LEDGER-BATCH-059-A1', '2027-12-31', 'SELLABLE', 10, 'EXTERNAL_IN', 1, 'INITIAL-1', '2026-07-26 09:00:00+07', '2026-07-26 09:00:01+07', '2026-07-26 09:00:01+07'),
  ('00000000-0000-4059-8000-000000000411', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000301', 2, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000202', 'LEDGER-059-A', 'LEDGER-BATCH-059-A2', '2028-01-31', 'SELLABLE', 5, 'EXTERNAL_IN', 2, 'INITIAL-2', '2026-07-26 09:00:00+07', '2026-07-26 09:00:01+07', '2026-07-26 09:00:01+07'),
  ('00000000-0000-4059-8000-000000000402', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000302', 1, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000201', 'LEDGER-059-A', 'LEDGER-BATCH-059-A1', '2027-12-31', 'QUARANTINE', 5, 'EXTERNAL_IN', 1, 'RETURN-1', '2026-07-26 09:00:00+07', '2026-07-26 09:00:02+07', '2026-07-26 09:00:02+07'),
  ('00000000-0000-4059-8000-000000000403', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000302', 2, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000202', 'LEDGER-059-A', 'LEDGER-BATCH-059-A2', '2028-01-31', 'QUARANTINE', 2, 'EXTERNAL_IN', 2, 'RETURN-2', '2026-07-26 09:00:00+07', '2026-07-26 09:00:02+07', '2026-07-26 09:00:02+07'),
  ('00000000-0000-4059-8000-000000000404', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000303', 1, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000201', 'LEDGER-059-A', 'LEDGER-BATCH-059-A1', '2027-12-31', 'QUARANTINE', -5, 'REVERSAL', 1, '00000000-0000-4059-8000-000000000402', '2026-07-26 09:00:00+07', '2026-07-26 09:00:03+07', '2026-07-26 09:00:03+07'),
  ('00000000-0000-4059-8000-000000000405', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000303', 2, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000202', 'LEDGER-059-A', 'LEDGER-BATCH-059-A2', '2028-01-31', 'QUARANTINE', -2, 'REVERSAL', 2, '00000000-0000-4059-8000-000000000403', '2026-07-26 09:00:00+07', '2026-07-26 09:00:03+07', '2026-07-26 09:00:03+07'),
  ('00000000-0000-4059-8000-000000000406', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000304', 1, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000201', 'LEDGER-059-A', 'LEDGER-BATCH-059-A1', '2027-12-31', 'SELLABLE', -3, 'SOURCE', 1, 'FEFO-1', '2026-07-26 09:00:00+07', '2026-07-26 09:00:04+07', '2026-07-26 09:00:04+07'),
  ('00000000-0000-4059-8000-000000000407', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000304', 2, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000202', 'LEDGER-059-A', 'LEDGER-BATCH-059-A2', '2028-01-31', 'SELLABLE', -2, 'SOURCE', 2, 'FEFO-2', '2026-07-26 09:00:00+07', '2026-07-26 09:00:04+07', '2026-07-26 09:00:04+07'),
  ('00000000-0000-4059-8000-000000000408', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000305', 1, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000201', 'LEDGER-059-A', 'LEDGER-BATCH-059-A1', '2027-12-31', 'QUARANTINE', -3, 'SOURCE', 1, 'RETURN-QUARANTINE', '2026-07-26 09:00:00+07', '2026-07-26 09:00:05+07', '2026-07-26 09:00:05+07'),
  ('00000000-0000-4059-8000-000000000409', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000305', 2, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000201', 'LEDGER-059-A', 'LEDGER-BATCH-059-A1', '2027-12-31', 'SELLABLE', 3, 'DESTINATION', 1, 'RETURN-SELLABLE', '2026-07-26 09:00:00+07', '2026-07-26 09:00:05+07', '2026-07-26 09:00:05+07'),
  ('00000000-0000-4059-8000-000000000410', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000306', 1, '00000000-0000-4059-8000-000000000101', '00000000-0000-4059-8000-000000000201', 'LEDGER-059-A', 'LEDGER-BATCH-059-A1', '2027-12-31', 'SELLABLE', 1, 'ADJUSTMENT', 1, 'STOCKTAKE-ADJUSTMENT', '2026-07-26 09:00:00+07', '2026-07-26 09:00:06+07', '2026-07-26 09:00:06+07');

insert into inventory.stock_reversal_applications(id, organization_id, original_transaction_id, reversal_transaction_id, original_entry_id, reversal_entry_id, quantity_applied)
values
  ('00000000-0000-4059-8000-000000000601', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000302', '00000000-0000-4059-8000-000000000303', '00000000-0000-4059-8000-000000000402', '00000000-0000-4059-8000-000000000404', 5),
  ('00000000-0000-4059-8000-000000000602', '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000302', '00000000-0000-4059-8000-000000000303', '00000000-0000-4059-8000-000000000403', '00000000-0000-4059-8000-000000000405', 2);

insert into inventory.stock_batch_balances(organization_id, batch_id, product_id, sellable_qty, quarantine_qty, damaged_qty, last_ledger_seq, version)
select '00000000-0000-4059-8000-000000000001', balances.batch_id, '00000000-0000-4059-8000-000000000101', balances.sellable_qty, 0, 0, max(entry.ledger_seq), 1
from (values
  ('00000000-0000-4059-8000-000000000201'::uuid, 11::bigint),
  ('00000000-0000-4059-8000-000000000202'::uuid, 3::bigint)
) balances(batch_id, sellable_qty)
join inventory.stock_ledger_entries entry on entry.organization_id = '00000000-0000-4059-8000-000000000001' and entry.batch_id = balances.batch_id
group by balances.batch_id, balances.sellable_qty;

insert into inventory.stock_product_positions(organization_id, product_id, sellable_qty, quarantine_qty, damaged_qty, reserved_qty, last_ledger_seq, version)
select '00000000-0000-4059-8000-000000000001', '00000000-0000-4059-8000-000000000101', 14, 0, 0, 0, max(ledger_seq), 1
from inventory.stock_ledger_entries
where organization_id = '00000000-0000-4059-8000-000000000001';

select set_config('request.jwt.claim.sub', '00000000-0000-4059-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4059-8000-000000000001', 'role', 'authenticated')::text, true);
set local role authenticated;

select is((select count(*) from api.ledger_explorer), 11::bigint, 'explorer is organization-scoped');
select is((select count(*) from api.ledger_explorer where transaction_id = '00000000-0000-4059-8000-000000000302'), 2::bigint, 'exact transaction returns all entries');
select is((select count(*) from api.ledger_transaction_detail where transaction_id = '00000000-0000-4059-8000-000000000999'), 0::bigint, 'invalid transaction is safe not-found');
select is((select count(*) from api.ledger_transaction_detail where transaction_id = '00000000-0000-4059-8000-000000000307'), 0::bigint, 'cross-organization transaction is safe not-found');
select is((select array_agg(line_no order by line_no) from api.ledger_transaction_detail where transaction_id = '00000000-0000-4059-8000-000000000302'), array[1,2]::integer[], 'transaction lines have stable line order');
select is((select count(*) from api.ledger_explorer where transaction_type_code = 'MARKETPLACE_OUTBOUND' and source_type_code = 'MARKETPLACE_SHIPMENT' and product_id = '00000000-0000-4059-8000-000000000101' and quantity_direction = 'OUT'), 2::bigint, 'combined filters narrow split FEFO entries');
select is((select count(*) from (select ledger_seq from api.ledger_explorer order by ledger_seq desc, ledger_entry_id desc limit 3) page), 3::bigint, 'page limit is honored');
select ok((select exists (select 1 from api.ledger_explorer candidate where candidate.ledger_seq < (select cursor_row.ledger_seq from (select ledger_seq from api.ledger_explorer order by ledger_seq desc, ledger_entry_id desc limit 1 offset 2) cursor_row) order by candidate.ledger_seq desc, candidate.ledger_entry_id desc limit 1)), 'ledger sequence supports keyset cursor predicates');
select ok((select count(*) = count(distinct ledger_seq) from api.ledger_explorer where occurred_at = '2026-07-26 09:00:00+07'), 'same-time entries have unique deterministic tie-breakers');
select is((select quantity_direction from api.ledger_explorer where ledger_entry_id = '00000000-0000-4059-8000-000000000406'), 'OUT', 'negative quantity is classified as outbound');
select is((select reversal_state from api.ledger_explorer where ledger_entry_id = '00000000-0000-4059-8000-000000000402'), 'FULLY_REVERSED', 'original entry is fully reversed from actual application linkage');
select is((select reversal_state from api.ledger_explorer where ledger_entry_id = '00000000-0000-4059-8000-000000000404'), 'REVERSAL', 'reversal entry is identified from transaction linkage');
select is((select count(*) from api.ledger_reversal_links where original_transaction_id = '00000000-0000-4059-8000-000000000302'), 2::bigint, 'reversal links expose both original applications');
select is((select count(*) from api.ledger_reversal_links where reversal_transaction_id = '00000000-0000-4059-8000-000000000303'), 2::bigint, 'reversal links are bidirectional');
select is((select source_ref_snapshot from api.ledger_explorer where transaction_id = '00000000-0000-4059-8000-000000000305' and line_no = 2), 'RETURN-059-SELLABLE', 'return SELLABLE source evidence is preserved');
select is((select count(*) from api.ledger_stock_story where product_id = '00000000-0000-4059-8000-000000000101' and batch_id = '00000000-0000-4059-8000-000000000201'), 7::bigint, 'stock story is product and batch scoped');
select is((select count(*) from api.ledger_explorer where transaction_type_code = 'STOCKTAKE_ADJUSTMENT'), 1::bigint, 'stocktake adjustment evidence is visible');
select is((select count(*) from api.ledger_explorer where transaction_type_code = 'RETURN_INSPECTION_TRANSFER'), 2::bigint, 'return inspection transfer exposes both physical sides');
select is((select count(*) from api.ledger_explorer where bucket_code = 'DAMAGED'), 0::bigint, 'unsupported damaged or lost movement is not fabricated');

create temp table read_baseline as
select
  (select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4059-8000-000000000001') as transaction_count,
  (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4059-8000-000000000001') as ledger_count,
  (select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4059-8000-000000000001') as product_projection_count;
select count(*) from api.ledger_explorer;
select count(*) from api.ledger_transaction_detail where transaction_id = '00000000-0000-4059-8000-000000000302';
reset role;
select is((select row((select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4059-8000-000000000001'), (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4059-8000-000000000001'), (select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4059-8000-000000000001'))::text), (select row(transaction_count, ledger_count, product_projection_count)::text from read_baseline), 'read baseline is stable');
select is((select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4059-8000-000000000001'), 6::bigint, 'read does not mutate transactions');
select is((select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4059-8000-000000000001'), 11::bigint, 'read does not mutate ledger');
select is((select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4059-8000-000000000001'), 1::bigint, 'read does not mutate projection');
select is((select sellable_qty from inventory.stock_product_positions where organization_id = '00000000-0000-4059-8000-000000000001' and product_id = '00000000-0000-4059-8000-000000000101'), (select coalesce(sum(quantity_delta) filter (where bucket_code = 'SELLABLE'), 0)::bigint from inventory.stock_ledger_entries where organization_id = '00000000-0000-4059-8000-000000000001' and product_id = '00000000-0000-4059-8000-000000000101'), 'product projection is explainable from ledger');

select * from finish();
rollback;
