begin;

select plan(109);

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

create temp table reversal_072(kind text primary key, result jsonb not null);
create temp table reversal_072_baseline as select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;
insert into reversal_072 select 'receipt', api.post_receipt('00000000-0000-4000-8000-000000000001'::uuid,'PGTAP-072-REVERSAL-RECEIPT','PGTAP-072-REVERSAL-RECEIPT','2026-07-18 09:00:00+07',jsonb_build_array(jsonb_build_object('productId','30000000-0000-4000-8000-000000000001','batchId','40000000-0000-4000-8000-000000000001','quantity',4,'sourceLineRef','REVERSAL-072-LINE-1')),'Receipt Scenario A 072','{"fixture":"072-reversal"}'::jsonb);
insert into reversal_072 select 'preview', api.preview_stock_transaction_reversal('00000000-0000-4000-8000-000000000001'::uuid,(select (result->>'transactionId')::uuid from reversal_072 where kind='receipt'));
insert into reversal_072 select 'reversal', api.reverse_stock_transaction('00000000-0000-4000-8000-000000000001'::uuid,'PGTAP-072-REVERSAL-COMMIT',(select (result->>'transactionId')::uuid from reversal_072 where kind='receipt'),(select result->>'basisHash' from reversal_072 where kind='preview'),true,'Reverse receipt Scenario A 072','{"fixture":"072-reversal"}'::jsonb);
create temp table reversal_072_after as select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;
select ok((select (result->>'eligible')::boolean from reversal_072 where kind='preview'),'Scenario A preview eligible');
select ok((select nullif(result->>'basisHash','') is not null from reversal_072 where kind='preview'),'Scenario A preview has basis hash');
select is((select coalesce(sum(quantity_delta),0)::bigint from inventory.stock_ledger_entries where transaction_id in ((select (result->>'transactionId')::uuid from reversal_072 where kind='receipt'),(select (result->>'reversalTransactionId')::uuid from reversal_072 where kind='reversal')) and bucket_code='SELLABLE'),0::bigint,'receipt and reversal signed ledger net zero');
select is((select (value->'ledger'->>'sellableQty')::bigint from reversal_072_after),(select (value->'ledger'->>'sellableQty')::bigint from reversal_072_baseline),'Explain sellable returns baseline after reversal');
select is((select (value->'ledger'->>'onHandQty')::bigint from reversal_072_after),(select (value->'ledger'->>'onHandQty')::bigint from reversal_072_baseline),'Explain physical total returns baseline after reversal');
select is((select count(*) from inventory.stock_reversal_applications where original_transaction_id=(select (result->>'transactionId')::uuid from reversal_072 where kind='receipt')),1::bigint,'one reversal application links receipt');
select ok((select exists(select 1 from inventory.stock_reversal_applications a join inventory.stock_ledger_entries o on o.id=a.original_entry_id join inventory.stock_ledger_entries r on r.id=a.reversal_entry_id where a.original_transaction_id=(select (result->>'transactionId')::uuid from reversal_072 where kind='receipt') and a.reversal_transaction_id=(select (result->>'reversalTransactionId')::uuid from reversal_072 where kind='reversal') and r.quantity_delta=-o.quantity_delta and r.product_id=o.product_id and r.batch_id=o.batch_id and r.bucket_code=o.bucket_code and a.quantity_applied=abs(o.quantity_delta))),'reversal application links exact opposite ledger entry');
select is((select (value->'projection'->>'sellableQty')::bigint from reversal_072_after),(select (value->'projection'->>'sellableQty')::bigint from reversal_072_baseline),'projection sellable returns baseline after reversal');
select ok((select value::text like '%REVERSAL%' from reversal_072_after),'Explain grouped evidence retains reversal');
select ok((select value::text like '%RECEIPT%' from reversal_072_after),'Explain grouped evidence retains receipt');create temp table fefo_072_baseline as select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;
create temp table fefo_072_result(result jsonb not null);
reset role;
insert into fefo_072_result select api.post_manual_outbound('00000000-0000-4000-8000-000000000001'::uuid,'PGTAP-072-FEFO-OUTBOUND','PGTAP-072-FEFO-OUTBOUND','2026-07-16 11:00:00+07'::timestamptz,'OFFLINE_SALE',jsonb_build_array(jsonb_build_object('productId','30000000-0000-4000-8000-000000000001','quantity',8,'sourceLineRef','FEFO-072-LINE-1')),'Outbound FEFO Scenario B 072','{"fixture":"072-fefo"}'::jsonb);
set local role authenticated;
create temp table fefo_072_after as select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;
select is((select result->>'status' from fefo_072_result),'POSTED','Scenario B manual outbound posted');
select is((select (result->>'allocationCount')::bigint from fefo_072_result),2::bigint,'Scenario B command creates two FEFO allocations');
select is((select count(*) from operations.manual_outbound_allocations a join operations.manual_outbound_lines l on l.id=a.outbound_line_id join operations.manual_outbounds h on h.id=l.outbound_id where h.source_ref='PGTAP-072-FEFO-OUTBOUND'),2::bigint,'Scenario B persists two allocation rows');
select is((select count(distinct a.batch_id) from operations.manual_outbound_allocations a join operations.manual_outbound_lines l on l.id=a.outbound_line_id join operations.manual_outbounds h on h.id=l.outbound_id where h.source_ref='PGTAP-072-FEFO-OUTBOUND'),2::bigint,'Scenario B allocation evidence spans two batches');
select is((select coalesce(sum(a.quantity_allocated),0)::bigint from operations.manual_outbound_allocations a join operations.manual_outbound_lines l on l.id=a.outbound_line_id join operations.manual_outbounds h on h.id=l.outbound_id where h.source_ref='PGTAP-072-FEFO-OUTBOUND'),8::bigint,'Scenario B allocation quantities total eight');
select ok((select (array_agg(a.expiry_date_snapshot order by a.allocation_no))[1] < (array_agg(a.expiry_date_snapshot order by a.allocation_no))[2] from operations.manual_outbound_allocations a join operations.manual_outbounds h on h.id=a.outbound_id where h.source_ref='PGTAP-072-FEFO-OUTBOUND'),'Scenario B earlier expiry is allocated first');
select is((select array_agg(a.quantity_allocated order by a.allocation_no) from operations.manual_outbound_allocations a join operations.manual_outbounds h on h.id=a.outbound_id where h.source_ref='PGTAP-072-FEFO-OUTBOUND'),array[5,3]::bigint[],'Scenario B FEFO allocation split is five then three');
select is((select array_agg(batch_id order by batch_id)::text from operations.manual_outbound_allocations a join operations.manual_outbounds h on h.id=a.outbound_id where h.source_ref='PGTAP-072-FEFO-OUTBOUND'),(select array_agg(e.batch_id order by e.batch_id)::text from inventory.stock_ledger_entries e join inventory.stock_transactions t on t.id=e.transaction_id where t.source_ref_snapshot='PGTAP-072-FEFO-OUTBOUND'),'Scenario B allocation and ledger use the same FEFO batch set');
select is((select count(*) from inventory.stock_ledger_entries e join inventory.stock_transactions t on t.id=e.transaction_id where t.source_ref_snapshot='PGTAP-072-FEFO-OUTBOUND'),2::bigint,'Scenario B has two raw ledger rows');
select is((select coalesce(sum(e.quantity_delta),0)::bigint from inventory.stock_ledger_entries e join inventory.stock_transactions t on t.id=e.transaction_id where t.source_ref_snapshot='PGTAP-072-FEFO-OUTBOUND' and e.bucket_code='SELLABLE'),-8::bigint,'Scenario B raw SELLABLE split totals negative eight');
select is((select (value->'ledger'->>'sellableQty')::bigint from fefo_072_after),(select (value->'ledger'->>'sellableQty')::bigint-8 from fefo_072_baseline),'Scenario B Explain aggregates both batches into SELLABLE');
select is((select (value->'ledger'->>'onHandQty')::bigint from fefo_072_after),(select (value->'ledger'->>'onHandQty')::bigint-8 from fefo_072_baseline),'Scenario B Explain physical total falls eight');

-- Scenario C: construct only the approved stocktake prerequisite. The posting
-- command remains the sole writer of its transaction, ledger, projection, and
-- reconciliation records.
reset role;
create temp table stocktake_072_registry as
select
  gen_random_uuid() as stocktake_id,
  gen_random_uuid() as stocktake_line_id,
  gen_random_uuid() as count_attempt_id,
  gen_random_uuid() as approval_id,
  gen_random_uuid() as approval_line_id,
  gen_random_uuid() as create_command_id,
  gen_random_uuid() as approve_command_id,
  '30000000-0000-4000-8000-000000000001'::uuid as product_id,
  '40000000-0000-4000-8000-000000000002'::uuid as batch_id;

create temp table stocktake_072_values as
select
  registry.*,
  product.organization_id,
  product.sku as product_sku_snapshot,
  product.name as product_name_snapshot,
  batch.batch_code as batch_code_snapshot,
  batch.expiry_date as expiry_date_snapshot,
  coalesce(sum(entry.quantity_delta) filter (where entry.bucket_code = 'SELLABLE'), 0)::bigint as expected_qty,
  coalesce(max(entry.ledger_seq), 0)::bigint as snapshot_ledger_seq
from stocktake_072_registry registry
join catalog.products product on product.id = registry.product_id
join catalog.product_batches batch
  on batch.organization_id = product.organization_id
 and batch.product_id = product.id
 and batch.id = registry.batch_id
left join inventory.stock_ledger_entries entry
  on entry.organization_id = product.organization_id
 and entry.product_id = product.id
 and entry.batch_id = batch.id
group by registry.stocktake_id, registry.stocktake_line_id, registry.count_attempt_id,
  registry.approval_id, registry.approval_line_id, registry.create_command_id,
  registry.approve_command_id, registry.product_id, registry.batch_id,
  product.organization_id, product.sku, product.name, batch.batch_code, batch.expiry_date;

insert into inventory.idempotency_commands (
  id, organization_id, scope, key, request_hash, status_code, started_at,
  completed_at, response_snapshot
)
select values.create_command_id, values.organization_id, 'CREATE_STOCKTAKE',
  'PGTAP-072-STOCKTAKE-CREATE-' || values.stocktake_id::text, repeat('c', 64),
  'SUCCEEDED', clock_timestamp(), clock_timestamp(), '{"status":"REVIEW"}'::jsonb
from stocktake_072_values values
union all
select values.approve_command_id, values.organization_id, 'APPROVE_STOCKTAKE',
  'PGTAP-072-STOCKTAKE-APPROVE-' || values.stocktake_id::text, repeat('d', 64),
  'SUCCEEDED', clock_timestamp(), clock_timestamp(), '{"status":"APPROVED"}'::jsonb
from stocktake_072_values values;

insert into operations.stocktakes (
  id, organization_id, stocktake_no, title, stocktake_type_code, mode_code,
  visibility_code, status_code, scope_definition, tolerance_policy_snapshot,
  rule_version, timezone_snapshot, planned_at, snapshot_ledger_seq, started_at,
  counting_completed_at, created_by, process_name, create_idempotency_command_id,
  note, metadata, created_at, updated_at, version_no
)
select values.stocktake_id, values.organization_id,
  'STK-072-' || upper(substr(replace(values.stocktake_id::text, '-', ''), 1, 8)),
  'Scenario C stocktake adjustment fixture', 'CYCLE', 'CONTINUOUS', 'BLIND',
  'REVIEW', jsonb_build_object('mode', 'BATCHES',
    'batchIds', jsonb_build_array(values.batch_id),
    'bucketCodes', jsonb_build_array('SELLABLE')),
  '{"units":0,"percent":0}'::jsonb, 'stocktake-continuous-v1', 'Asia/Jakarta',
  clock_timestamp(), values.snapshot_ledger_seq, clock_timestamp(), clock_timestamp(),
  null, 'pgtap.stocktake_072', values.create_command_id,
  'Scenario C approved stocktake prerequisite.', '{"fixture":"072-stocktake"}'::jsonb,
  clock_timestamp(), clock_timestamp(), 5
from stocktake_072_values values;

insert into operations.stocktake_lines (
  id, organization_id, stocktake_id, line_no, product_id, batch_id, bucket_code,
  product_sku_snapshot, product_name_snapshot, batch_code_snapshot,
  expiry_date_snapshot, system_qty_at_snapshot, final_physical_qty,
  expected_qty_at_count, variance_qty, count_cutoff_ledger_seq,
  expected_formula_version, count_attempt_no, count_status_code,
  review_status_code, review_decision_code, reason_code, review_note,
  created_at, updated_at, version_no
)
select values.stocktake_line_id, values.organization_id, values.stocktake_id, 1,
  values.product_id, values.batch_id, 'SELLABLE', values.product_sku_snapshot,
  values.product_name_snapshot, values.batch_code_snapshot, values.expiry_date_snapshot,
  values.expected_qty, values.expected_qty + 2, values.expected_qty, 2,
  values.snapshot_ledger_seq, 'continuous-ledger-cutoff-v1', 1, 'COUNTED',
  'REVIEWED', 'VARIANCE_ACCEPTED', 'PHYSICAL_SURPLUS',
  'Scenario C verified physical surplus.', clock_timestamp(), clock_timestamp(), 3
from stocktake_072_values values;

insert into operations.stocktake_count_attempts (
  id, organization_id, stocktake_id, stocktake_line_id, attempt_no, physical_qty,
  counted_at, count_cutoff_ledger_seq, expected_qty_at_count, variance_qty,
  expected_formula_version, counted_by, process_name, count_method_code,
  zero_confirmed, note, idempotency_key, request_hash, status_code, created_at
)
select values.count_attempt_id, values.organization_id, values.stocktake_id,
  values.stocktake_line_id, 1, values.expected_qty + 2, clock_timestamp(),
  values.snapshot_ledger_seq, values.expected_qty, 2, 'continuous-ledger-cutoff-v1',
  null, 'pgtap.stocktake_072', 'MANUAL_ENTRY', false, 'Scenario C count attempt.',
  'PGTAP-072-STOCKTAKE-COUNT-' || values.stocktake_id::text, repeat('e', 64),
  'VALID', clock_timestamp()
from stocktake_072_values values;

update operations.stocktake_lines line
set final_attempt_id = values.count_attempt_id
from stocktake_072_values values
where line.organization_id = values.organization_id and line.id = values.stocktake_line_id;
update operations.stocktake_lines line
set review_decision_code = 'VARIANCE_ACCEPTED'
from stocktake_072_values values
where line.organization_id = values.organization_id and line.id = values.stocktake_line_id;

insert into operations.stocktake_approvals (
  id, organization_id, stocktake_id, approval_version_no, approval_hash,
  approved_at, approved_by, process_name, stocktake_version_no, snapshot_ledger_seq,
  tolerance_policy_snapshot, rule_version, line_count, variance_line_count,
  total_variance_qty, idempotency_command_id, note, metadata, created_at
)
select values.approval_id, values.organization_id, values.stocktake_id, 1,
  repeat('f', 64), clock_timestamp(),
  '00000000-0000-4072-8000-000000000001'::uuid, null, 5,
  values.snapshot_ledger_seq, '{"units":0,"percent":0}'::jsonb,
  'stocktake-continuous-v1', 1, 1, 2, values.approve_command_id,
  'Scenario C approval fixture.', '{"fixture":"072-stocktake"}'::jsonb, clock_timestamp()
from stocktake_072_values values;

insert into operations.stocktake_approval_lines (
  id, organization_id, stocktake_id, approval_id, stocktake_line_id, line_no,
  line_version_no, review_decision_code, final_attempt_id, final_physical_qty,
  expected_qty_at_count, variance_qty, reason_code, review_note,
  expected_formula_version, count_cutoff_ledger_seq, created_at
)
select values.approval_line_id, line.organization_id, line.stocktake_id,
  values.approval_id, line.id, line.line_no, line.version_no,
  line.review_decision_code, line.final_attempt_id, line.final_physical_qty,
  line.expected_qty_at_count, line.variance_qty, line.reason_code, line.review_note,
  line.expected_formula_version, line.count_cutoff_ledger_seq, line.updated_at
from operations.stocktake_lines line
join stocktake_072_values values
  on values.organization_id = line.organization_id
 and values.stocktake_id = line.stocktake_id
 and values.stocktake_line_id = line.id;

update operations.stocktakes stocktake
set status_code = 'APPROVED', approved_at = approval.approved_at,
  current_approval_id = approval.id, approval_version_no = approval.approval_version_no,
  approved_by = approval.approved_by, approval_process_name = approval.process_name,
  updated_at = approval.approved_at, version_no = 6
from operations.stocktake_approvals approval
where stocktake.organization_id = approval.organization_id
  and stocktake.id = approval.stocktake_id
  and stocktake.id = (select stocktake_id from stocktake_072_values);

grant select on stocktake_072_values to authenticated;
set local role authenticated;
create temp table stocktake_072_baseline as
select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;
create temp table stocktake_072_result(result jsonb not null);
grant select, insert on stocktake_072_result to authenticated;
insert into stocktake_072_result
select api.post_stocktake_adjustment(
  values.organization_id, 'stocktake:' || values.stocktake_id::text || ':post:1',
  values.stocktake_id, 1, true, 'Post Scenario C stocktake physical gain.',
  '{"fixture":"072-stocktake"}'::jsonb
)
from stocktake_072_values values;
create temp table stocktake_072_after as
select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;

select is((select result->>'status' from stocktake_072_result),'POSTED','Scenario C stocktake adjustment posted');
select ok((select nullif(result->>'transactionId','') is not null from stocktake_072_result),'Scenario C posting returns a transaction id');
select is((select (result->>'netAdjustmentQty')::bigint from stocktake_072_result),2::bigint,'Scenario C net adjustment is positive two');
select is((select (result->>'totalAbsoluteAdjustmentQty')::bigint from stocktake_072_result),2::bigint,'Scenario C absolute adjustment is two');
select is((select (result->>'nonzeroLineCount')::bigint from stocktake_072_result),1::bigint,'Scenario C posts one nonzero line');
select is((select row(transaction_type_code,reason_code_snapshot,channel_code_snapshot,source_type_code,source_id)::text from inventory.stock_transactions where id=(select (result->>'transactionId')::uuid from stocktake_072_result)),(select row('STOCKTAKE_ADJUSTMENT'::text,'STOCKTAKE_ADJUSTMENT'::text,'SYSTEM'::text,'STOCKTAKE'::text,stocktake_id)::text from stocktake_072_values),'Scenario C transaction keeps stocktake dimensions and source');
select is((select count(*) from inventory.stock_ledger_entries where transaction_id=(select (result->>'transactionId')::uuid from stocktake_072_result)),1::bigint,'Scenario C posts one raw ledger entry');
select is((select row(product_id,batch_id,bucket_code,entry_role_code,quantity_delta)::text from inventory.stock_ledger_entries where transaction_id=(select (result->>'transactionId')::uuid from stocktake_072_result)),(select row(product_id,batch_id,'SELLABLE'::text,'ADJUSTMENT'::text,2::bigint)::text from stocktake_072_values),'Scenario C raw ledger entry is a SELLABLE adjustment gain');
select is((select coalesce(sum(quantity_delta),0)::bigint from inventory.stock_ledger_entries where transaction_id=(select (result->>'transactionId')::uuid from stocktake_072_result)),2::bigint,'Scenario C raw signed ledger delta is positive two');
select is((select (value->'ledger'->>'sellableQty')::bigint from stocktake_072_after),(select (value->'ledger'->>'sellableQty')::bigint+2 from stocktake_072_baseline),'Scenario C Explain SELLABLE rises two');
select is((select (value->'ledger'->>'onHandQty')::bigint from stocktake_072_after),(select (value->'ledger'->>'onHandQty')::bigint+2 from stocktake_072_baseline),'Scenario C Explain physical total rises two');
select is((select (value->'projection'->>'sellableQty')::bigint from stocktake_072_after),(select (value->'projection'->>'sellableQty')::bigint+2 from stocktake_072_baseline),'Scenario C projection SELLABLE rises two');
select ok((select (value->'comparison'->>'sellableMatches') <> 'true' from stocktake_072_baseline) or (select (value->'comparison'->>'sellableMatches') = 'true' from stocktake_072_after),'Scenario C retains sellable comparison when baseline matched');
select ok((select (value->'comparison'->>'onHandMatches') <> 'true' from stocktake_072_baseline) or (select (value->'comparison'->>'onHandMatches') = 'true' from stocktake_072_after),'Scenario C retains physical comparison when baseline matched');
select is((select coalesce(sum((grouped.value->>'sellableDelta')::bigint),0)::bigint from stocktake_072_after, jsonb_array_elements(value->'groupedMovements') grouped(value) join inventory.stock_transactions transaction on transaction.id=(select (result->>'transactionId')::uuid from stocktake_072_result) where grouped.value->>'transactionTypeCode'=transaction.transaction_type_code and grouped.value->>'reasonCode'=transaction.reason_code_snapshot and grouped.value->>'channelCode'=transaction.channel_code_snapshot and grouped.value->>'sourceTypeCode'=transaction.source_type_code) - (select coalesce(sum((grouped.value->>'sellableDelta')::bigint),0)::bigint from stocktake_072_baseline, jsonb_array_elements(value->'groupedMovements') grouped(value) join inventory.stock_transactions transaction on transaction.id=(select (result->>'transactionId')::uuid from stocktake_072_result) where grouped.value->>'transactionTypeCode'=transaction.transaction_type_code and grouped.value->>'reasonCode'=transaction.reason_code_snapshot and grouped.value->>'channelCode'=transaction.channel_code_snapshot and grouped.value->>'sourceTypeCode'=transaction.source_type_code),2::bigint,'Scenario C grouped SELLABLE delta is positive two');
select is((select coalesce(sum((grouped.value->>'onHandDelta')::bigint),0)::bigint from stocktake_072_after, jsonb_array_elements(value->'groupedMovements') grouped(value) join inventory.stock_transactions transaction on transaction.id=(select (result->>'transactionId')::uuid from stocktake_072_result) where grouped.value->>'transactionTypeCode'=transaction.transaction_type_code and grouped.value->>'reasonCode'=transaction.reason_code_snapshot and grouped.value->>'channelCode'=transaction.channel_code_snapshot and grouped.value->>'sourceTypeCode'=transaction.source_type_code) - (select coalesce(sum((grouped.value->>'onHandDelta')::bigint),0)::bigint from stocktake_072_baseline, jsonb_array_elements(value->'groupedMovements') grouped(value) join inventory.stock_transactions transaction on transaction.id=(select (result->>'transactionId')::uuid from stocktake_072_result) where grouped.value->>'transactionTypeCode'=transaction.transaction_type_code and grouped.value->>'reasonCode'=transaction.reason_code_snapshot and grouped.value->>'channelCode'=transaction.channel_code_snapshot and grouped.value->>'sourceTypeCode'=transaction.source_type_code),2::bigint,'Scenario C grouped physical delta is positive two');
select is((select coalesce(sum((grouped.value->>'quarantineDelta')::bigint),0)::bigint from stocktake_072_after, jsonb_array_elements(value->'groupedMovements') grouped(value) join inventory.stock_transactions transaction on transaction.id=(select (result->>'transactionId')::uuid from stocktake_072_result) where grouped.value->>'transactionTypeCode'=transaction.transaction_type_code and grouped.value->>'reasonCode'=transaction.reason_code_snapshot and grouped.value->>'channelCode'=transaction.channel_code_snapshot and grouped.value->>'sourceTypeCode'=transaction.source_type_code) - (select coalesce(sum((grouped.value->>'quarantineDelta')::bigint),0)::bigint from stocktake_072_baseline, jsonb_array_elements(value->'groupedMovements') grouped(value) join inventory.stock_transactions transaction on transaction.id=(select (result->>'transactionId')::uuid from stocktake_072_result) where grouped.value->>'transactionTypeCode'=transaction.transaction_type_code and grouped.value->>'reasonCode'=transaction.reason_code_snapshot and grouped.value->>'channelCode'=transaction.channel_code_snapshot and grouped.value->>'sourceTypeCode'=transaction.source_type_code),0::bigint,'Scenario C grouped QUARANTINE delta is zero');
select is((select coalesce(sum((grouped.value->>'damagedDelta')::bigint),0)::bigint from stocktake_072_after, jsonb_array_elements(value->'groupedMovements') grouped(value) join inventory.stock_transactions transaction on transaction.id=(select (result->>'transactionId')::uuid from stocktake_072_result) where grouped.value->>'transactionTypeCode'=transaction.transaction_type_code and grouped.value->>'reasonCode'=transaction.reason_code_snapshot and grouped.value->>'channelCode'=transaction.channel_code_snapshot and grouped.value->>'sourceTypeCode'=transaction.source_type_code) - (select coalesce(sum((grouped.value->>'damagedDelta')::bigint),0)::bigint from stocktake_072_baseline, jsonb_array_elements(value->'groupedMovements') grouped(value) join inventory.stock_transactions transaction on transaction.id=(select (result->>'transactionId')::uuid from stocktake_072_result) where grouped.value->>'transactionTypeCode'=transaction.transaction_type_code and grouped.value->>'reasonCode'=transaction.reason_code_snapshot and grouped.value->>'channelCode'=transaction.channel_code_snapshot and grouped.value->>'sourceTypeCode'=transaction.source_type_code),0::bigint,'Scenario C grouped DAMAGED delta is zero');

-- Scenario D: Phase 2 return arrival is stock-neutral; only SELLABLE inspection
-- creates the real inbound transaction and its new RETURN batch.
create temp table return_072_registry as
select
  'PGTAP-072-RETURN-ORDER'::text as order_ref,
  'PGTAP-072-RETURN-RETURN'::text as return_ref,
  'PGTAP-072-RETURN-SHIP-EVENT'::text as ship_event_ref,
  '30000000-0000-4000-8000-000000000001'::uuid as product_id;
create temp table return_072_results(kind text primary key, result jsonb not null);

insert into return_072_results
select 'reserve', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-072-RETURN-RESERVE', 'SHOPEE', 'RESERVE',
  'PGTAP-072-RETURN-RESERVE-EVENT', registry.order_ref,
  '2026-07-16 09:00:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', registry.product_id::text,
    'quantity', 2,
    'sourceLineRef', 'PGTAP-072-RETURN-LINE-1'
  )),
  'Scenario D reserve prerequisite.', '{"fixture":"072-return-sellable"}'::jsonb
)
from return_072_registry registry;
insert into return_072_results
select 'ship', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-072-RETURN-SHIP', 'SHOPEE', 'SHIP', registry.ship_event_ref,
  registry.order_ref, '2026-07-16 09:10:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', registry.product_id::text,
    'quantity', 2,
    'sourceLineRef', 'PGTAP-072-RETURN-LINE-1'
  )),
  'Scenario D shipment prerequisite.', '{"fixture":"072-return-sellable"}'::jsonb
)
from return_072_registry registry;
create temp table return_072_after_ship as
select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;

insert into return_072_results
select 'expected', api.create_expected_return(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-072-RETURN-EXPECTED', 'SHOPEE', registry.return_ref, registry.order_ref,
  '2026-07-16 10:00:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', registry.product_id::text,
    'quantity', 2,
    'sourceLineRef', 'PGTAP-072-RETURN-LINE-1'
  )),
  'RETURN_REQUESTED', 'Scenario D expected return.',
  '{"fixture":"072-return-sellable"}'::jsonb
)
from return_072_registry registry;
create temp table return_072_after_expected as
select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;

insert into return_072_results
select 'receipt', api.confirm_return_receipt(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-072-RETURN-RECEIPT', registry.return_ref, 'PGTAP-072-RETURN-RECEIPT-REF',
  '2026-07-16 10:10:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'returnItemId', (
      select item.id::text
      from operations.return_items item
      join operations.returns header on header.id = item.return_id
      where header.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
        and header.external_return_ref = registry.return_ref
        and item.product_id = registry.product_id
    ),
    'marketplaceShipAllocationId', (
      select allocation.id::text
      from operations.marketplace_ship_allocations allocation
      join operations.marketplace_events event on event.id = allocation.event_id
      where event.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
        and event.external_event_ref = registry.ship_event_ref
      order by allocation.allocation_no
      limit 1
    ),
    'quantity', 2,
    'sourceLineRef', 'PGTAP-072-RETURN-RECEIPT-LINE-1'
  )),
  'Scenario D physical receipt.', '{"fixture":"072-return-sellable"}'::jsonb
)
from return_072_registry registry;
create temp table return_072_baseline as
select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;

insert into return_072_results
select 'inspect', api.inspect_return(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-072-RETURN-INSPECT', registry.return_ref, 'PGTAP-072-RETURN-INSPECTION-REF',
  '2026-07-16 10:20:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'receiptLineId', (
      select receipt_line.id::text
      from operations.return_receipt_lines receipt_line
      join operations.return_receipts receipt on receipt.id = receipt_line.receipt_id
      where receipt.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
        and receipt.receipt_ref = 'PGTAP-072-RETURN-RECEIPT-REF'
      limit 1
    ),
    'sellableQuantity', 2,
    'damagedQuantity', 0,
    'sourceLineRef', 'PGTAP-072-RETURN-INSPECTION-LINE-1'
  )),
  'Scenario D sellable inspection.', '{"fixture":"072-return-sellable"}'::jsonb
)
from return_072_registry registry;
create temp table return_072_after as
select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;
create temp table return_072_transaction as
select transaction.*
from inventory.stock_transactions transaction
where transaction.id = (
  select (result->>'transactionId')::uuid
  from return_072_results
  where kind = 'inspect'
);
create temp table return_072_group_totals(stage text primary key, sellable_qty bigint not null, quarantine_qty bigint not null, damaged_qty bigint not null, on_hand_qty bigint not null);
insert into return_072_group_totals
select 'before',
  coalesce(sum((grouped.value->>'sellableDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'quarantineDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'damagedDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'onHandDelta')::bigint),0)::bigint
from return_072_baseline explanation
cross join return_072_transaction transaction
cross join lateral jsonb_array_elements(explanation.value->'groupedMovements') grouped(value)
where grouped.value->>'transactionTypeCode' = transaction.transaction_type_code
  and grouped.value->>'reasonCode' = transaction.reason_code_snapshot
  and grouped.value->>'channelCode' = transaction.channel_code_snapshot
  and grouped.value->>'sourceTypeCode' = transaction.source_type_code
union all
select 'after',
  coalesce(sum((grouped.value->>'sellableDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'quarantineDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'damagedDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'onHandDelta')::bigint),0)::bigint
from return_072_after explanation
cross join return_072_transaction transaction
cross join lateral jsonb_array_elements(explanation.value->'groupedMovements') grouped(value)
where grouped.value->>'transactionTypeCode' = transaction.transaction_type_code
  and grouped.value->>'reasonCode' = transaction.reason_code_snapshot
  and grouped.value->>'channelCode' = transaction.channel_code_snapshot
  and grouped.value->>'sourceTypeCode' = transaction.source_type_code;

select is((select result->>'status' from return_072_results where kind='ship'),'APPLIED','Scenario D shipped marketplace prerequisite is applied');
select is((select value->'ledger' from return_072_after_expected),(select value->'ledger' from return_072_after_ship),'Scenario D expected return is stock-neutral');
select is((select value->'ledger' from return_072_baseline),(select value->'ledger' from return_072_after_expected),'Scenario D physical receipt is stock-neutral before inspection');
select is((select result->>'stockEffectCode' from return_072_results where kind='inspect'),'SELLABLE_INBOUND','Scenario D inspection uses the sellable inbound stock effect');
select is((select row(transaction_type_code,reason_code_snapshot,source_type_code,source_id)::text from return_072_transaction),(select row('RETURN_SELLABLE_INBOUND'::text,'RETURN_SELLABLE'::text,'RETURN'::text,header.id)::text from operations.returns header join return_072_registry registry on registry.return_ref=header.external_return_ref),'Scenario D transaction uses current Phase 2 return semantics');
select is((select channel_code_snapshot from return_072_transaction),(select channel.code from operations.returns header join catalog.channels channel on channel.id=header.channel_id join return_072_registry registry on registry.return_ref=header.external_return_ref),'Scenario D transaction preserves the return channel');
select is((select count(*) from inventory.stock_ledger_entries where transaction_id=(select id from return_072_transaction)),1::bigint,'Scenario D writes one sellable-return ledger row');
select ok((select exists(select 1 from inventory.stock_ledger_entries entry join return_072_registry registry on registry.product_id=entry.product_id where entry.transaction_id=(select id from return_072_transaction) and entry.bucket_code='SELLABLE' and entry.quantity_delta=2 and entry.entry_role_code='EXTERNAL_IN' and entry.batch_id is not null)),'Scenario D ledger is a real SELLABLE external inbound');
select is((select coalesce(sum(quantity_delta),0)::bigint from inventory.stock_ledger_entries where transaction_id=(select id from return_072_transaction) and bucket_code='SELLABLE'),2::bigint,'Scenario D raw SELLABLE ledger delta is positive two');
select ok((select exists(select 1 from inventory.stock_ledger_entries entry join operations.return_stock_batches provenance on provenance.organization_id=entry.organization_id and provenance.batch_id=entry.batch_id join catalog.product_batches batch on batch.organization_id=entry.organization_id and batch.id=entry.batch_id where entry.transaction_id=(select id from return_072_transaction) and entry.batch_id=((select result->'lines'->0->>'returnBatchId' from return_072_results where kind='inspect')::uuid) and provenance.return_id=(select source_id from return_072_transaction) and batch.batch_kind_code='RETURN')),'Scenario D ledger targets the new return batch with typed provenance');
select is((select count(*) from inventory.stock_ledger_entries where transaction_id=(select id from return_072_transaction) and bucket_code='QUARANTINE'),0::bigint,'Scenario D has no legacy quarantine transfer counterpart');
select is((select (value->'ledger'->>'sellableQty')::bigint from return_072_after),(select (value->'ledger'->>'sellableQty')::bigint+2 from return_072_baseline),'Scenario D Explain SELLABLE rises two');
select is((select (value->'ledger'->>'quarantineQty')::bigint from return_072_after),(select (value->'ledger'->>'quarantineQty')::bigint from return_072_baseline),'Scenario D Explain QUARANTINE is unchanged');
select is((select (value->'ledger'->>'damagedQty')::bigint from return_072_after),(select (value->'ledger'->>'damagedQty')::bigint from return_072_baseline),'Scenario D Explain DAMAGED is unchanged');
select is((select (value->'ledger'->>'onHandQty')::bigint from return_072_after),(select (value->'ledger'->>'onHandQty')::bigint+2 from return_072_baseline),'Scenario D Explain physical total rises two');
select is((select (value->'projection'->>'sellableQty')::bigint from return_072_after),(select (value->'projection'->>'sellableQty')::bigint+2 from return_072_baseline),'Scenario D projection SELLABLE rises two');
select ok((select (value->'comparison'->>'sellableMatches') <> 'true' from return_072_baseline) or (select (value->'comparison'->>'sellableMatches') = 'true' from return_072_after),'Scenario D retains sellable comparison when baseline matched');
select ok((select (value->'comparison'->>'onHandMatches') <> 'true' from return_072_baseline) or (select (value->'comparison'->>'onHandMatches') = 'true' from return_072_after),'Scenario D retains physical comparison when baseline matched');
select is((select sellable_qty from return_072_group_totals where stage='after')-(select sellable_qty from return_072_group_totals where stage='before'),2::bigint,'Scenario D grouped SELLABLE delta is positive two');
select is((select on_hand_qty from return_072_group_totals where stage='after')-(select on_hand_qty from return_072_group_totals where stage='before'),2::bigint,'Scenario D grouped physical delta is positive two');
select is((select quarantine_qty from return_072_group_totals where stage='after')-(select quarantine_qty from return_072_group_totals where stage='before'),0::bigint,'Scenario D grouped QUARANTINE delta is zero');
select is((select damaged_qty from return_072_group_totals where stage='after')-(select damaged_qty from return_072_group_totals where stage='before'),0::bigint,'Scenario D grouped DAMAGED delta is zero');
-- Scenario E: HISTORICAL LEDGER COMPATIBILITY / accounting fixture only.
-- Scenario D remains the current Phase 2 SELLABLE-return model; this fixture
-- exercises the legacy paired-bucket accounting shape without defining a new flow.
create temp table transfer_072_baseline as
select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;
reset role;
create temp table transfer_072_registry as
select gen_random_uuid() as command_id, gen_random_uuid() as transaction_id,
  gen_random_uuid() as correlation_id, gen_random_uuid() as source_id;
create temp table transfer_072_values as
with candidate as (
  select
    registry.command_id,
    registry.transaction_id,
    registry.correlation_id,
    registry.source_id,
    product.organization_id,
    product.id as product_id,
    product.sku as product_sku_snapshot,
    batch.id as batch_id,
    batch.batch_code as batch_code_snapshot,
    batch.expiry_date as expiry_date_snapshot,
    reason.id as reason_id,
    reason.code as reason_code_snapshot,
    channel.id as channel_id,
    channel.code as channel_code_snapshot,
    organization.timezone
  from transfer_072_registry registry
  join app.organizations organization
    on organization.id = '00000000-0000-4000-8000-000000000001'::uuid
  join catalog.products product
    on product.organization_id = organization.id
   and product.id = '30000000-0000-4000-8000-000000000001'::uuid
  join inventory.stock_batch_balances batch_balance
    on batch_balance.organization_id = product.organization_id
   and batch_balance.product_id = product.id
   and batch_balance.sellable_qty >= 2
  join catalog.product_batches batch
    on batch.organization_id = batch_balance.organization_id
   and batch.product_id = batch_balance.product_id
   and batch.id = batch_balance.batch_id
  join inventory.stock_product_positions position
    on position.organization_id = product.organization_id
   and position.product_id = product.id
   and position.sellable_qty - position.reserved_qty >= 2
  join catalog.movement_reasons reason
    on reason.code = 'RETURN_INSPECTION'
   and reason.direction_code = 'TRANSFER'
   and reason.is_active
  join catalog.channels channel
    on channel.code = 'SHOPEE'
   and channel.is_active
  order by batch_balance.sellable_qty desc, batch.id
  limit 1
), timing as (
  select clock_timestamp() as occurred_at
)
select candidate.*, timing.occurred_at, timing.occurred_at as recorded_at,
  (timing.occurred_at at time zone candidate.timezone)::date as effective_local_date
from candidate cross join timing;

insert into inventory.idempotency_commands (
  id, organization_id, scope, key, request_hash, status_code, started_at,
  completed_at, response_snapshot
)
select command_id, organization_id, 'PGTAP_072_HISTORICAL_TRANSFER',
  'PGTAP-072-HISTORICAL-TRANSFER-' || transaction_id::text, repeat('7', 64),
  'SUCCEEDED', recorded_at, recorded_at, '{"fixture":"072-historical-transfer"}'::jsonb
from transfer_072_values;
insert into inventory.stock_transactions (
  id, organization_id, transaction_no, transaction_type_code, reason_id,
  reason_code_snapshot, channel_id, channel_code_snapshot, source_type_code,
  source_id, source_ref_snapshot, occurred_at, recorded_at, effective_local_date,
  process_name, created_by_role_code, correlation_id, idempotency_command_id,
  reversal_of_transaction_id, note, metadata
)
select transaction_id, organization_id,
  'HIST-072-' || upper(substr(replace(transaction_id::text, '-', ''), 1, 8)),
  'RETURN_INSPECTION_TRANSFER', reason_id, reason_code_snapshot, channel_id,
  channel_code_snapshot, 'RETURN_INSPECTION', source_id,
  'PGTAP-072-HISTORICAL-TRANSFER', occurred_at, recorded_at, effective_local_date,
  'pgtap.072.historical_transfer', 'SYSTEM_PROCESS', correlation_id, command_id,
  null, 'Historical paired bucket accounting fixture.',
  '{"fixture":"072-historical-transfer","compatibilityOnly":true}'::jsonb
from transfer_072_values;
insert into inventory.stock_ledger_entries (
  organization_id, transaction_id, line_no, product_id, batch_id,
  product_sku_snapshot, batch_code_snapshot, expiry_date_snapshot, bucket_code,
  quantity_delta, entry_role_code, pair_no, source_line_ref, occurred_at,
  recorded_at, created_at
)
select organization_id, transaction_id, 1, product_id, batch_id,
  product_sku_snapshot, batch_code_snapshot, expiry_date_snapshot, 'SELLABLE',
  -2, 'SOURCE', 1, 'PGTAP-072-HISTORICAL-TRANSFER:SELLABLE:SOURCE', occurred_at,
  recorded_at, recorded_at
from transfer_072_values
union all
select organization_id, transaction_id, 2, product_id, batch_id,
  product_sku_snapshot, batch_code_snapshot, expiry_date_snapshot, 'QUARANTINE',
  2, 'DESTINATION', 1, 'PGTAP-072-HISTORICAL-TRANSFER:QUARANTINE:DESTINATION', occurred_at,
  recorded_at, recorded_at
from transfer_072_values;
update inventory.stock_batch_balances balance
set sellable_qty = balance.sellable_qty - 2,
  quarantine_qty = balance.quarantine_qty + 2,
  last_ledger_seq = greatest(balance.last_ledger_seq, (
    select max(entry.ledger_seq) from inventory.stock_ledger_entries entry
    where entry.transaction_id = values.transaction_id
  )),
  updated_at = values.recorded_at,
  version = balance.version + 1
from transfer_072_values values
where balance.organization_id = values.organization_id
  and balance.product_id = values.product_id
  and balance.batch_id = values.batch_id;
update inventory.stock_product_positions position
set sellable_qty = position.sellable_qty - 2,
  quarantine_qty = position.quarantine_qty + 2,
  last_ledger_seq = greatest(position.last_ledger_seq, (
    select max(entry.ledger_seq) from inventory.stock_ledger_entries entry
    where entry.transaction_id = values.transaction_id
  )),
  updated_at = values.recorded_at,
  version = position.version + 1
from transfer_072_values values
where position.organization_id = values.organization_id
  and position.product_id = values.product_id;

set local role authenticated;
create temp table transfer_072_after as
select api.product_stock_explanation('30000000-0000-4000-8000-000000000001'::uuid) value;
reset role;
create temp table transfer_072_group_totals(stage text primary key, sellable_qty bigint not null, quarantine_qty bigint not null, damaged_qty bigint not null, on_hand_qty bigint not null);
insert into transfer_072_group_totals
select 'before',
  coalesce(sum((grouped.value->>'sellableDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'quarantineDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'damagedDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'onHandDelta')::bigint),0)::bigint
from transfer_072_baseline explanation
cross join transfer_072_values values
cross join lateral jsonb_array_elements(explanation.value->'groupedMovements') grouped(value)
where grouped.value->>'transactionTypeCode' = 'RETURN_INSPECTION_TRANSFER'
  and grouped.value->>'reasonCode' = values.reason_code_snapshot
  and grouped.value->>'channelCode' = values.channel_code_snapshot
  and grouped.value->>'sourceTypeCode' = 'RETURN_INSPECTION'
union all
select 'after',
  coalesce(sum((grouped.value->>'sellableDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'quarantineDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'damagedDelta')::bigint),0)::bigint,
  coalesce(sum((grouped.value->>'onHandDelta')::bigint),0)::bigint
from transfer_072_after explanation
cross join transfer_072_values values
cross join lateral jsonb_array_elements(explanation.value->'groupedMovements') grouped(value)
where grouped.value->>'transactionTypeCode' = 'RETURN_INSPECTION_TRANSFER'
  and grouped.value->>'reasonCode' = values.reason_code_snapshot
  and grouped.value->>'channelCode' = values.channel_code_snapshot
  and grouped.value->>'sourceTypeCode' = 'RETURN_INSPECTION';

select ok((select count(*) = 1 from transfer_072_values),'Scenario E selects a batch with at least two available SELLABLE units');
select is((select transaction_type_code from inventory.stock_transactions where id=(select transaction_id from transfer_072_values)),'RETURN_INSPECTION_TRANSFER','Scenario E uses historical paired-transfer transaction semantics only');
select is((select count(*) from inventory.stock_ledger_entries where transaction_id=(select transaction_id from transfer_072_values)),2::bigint,'Scenario E writes exactly two paired ledger rows');
select is((select count(distinct bucket_code) from inventory.stock_ledger_entries where transaction_id=(select transaction_id from transfer_072_values)),2::bigint,'Scenario E paired ledger rows use two physical buckets');
select is((select coalesce(sum(quantity_delta) filter (where bucket_code='SELLABLE'),0)::bigint from inventory.stock_ledger_entries where transaction_id=(select transaction_id from transfer_072_values)),-2::bigint,'Scenario E raw SELLABLE source delta is negative two');
select is((select coalesce(sum(quantity_delta) filter (where bucket_code='QUARANTINE'),0)::bigint from inventory.stock_ledger_entries where transaction_id=(select transaction_id from transfer_072_values)),2::bigint,'Scenario E raw QUARANTINE destination delta is positive two');
select is((select coalesce(sum(quantity_delta),0)::bigint from inventory.stock_ledger_entries where transaction_id=(select transaction_id from transfer_072_values)),0::bigint,'Scenario E paired raw ledger net is zero');
select ok((select count(*)=2 and count(distinct product_id)=1 and count(distinct batch_id)=1 and count(distinct pair_no)=1 and min(pair_no)=1 and bool_and((bucket_code='SELLABLE' and entry_role_code='SOURCE') or (bucket_code='QUARANTINE' and entry_role_code='DESTINATION')) from inventory.stock_ledger_entries where transaction_id=(select transaction_id from transfer_072_values)),'Scenario E preserves same-product same-batch paired SOURCE and DESTINATION linkage');
select is((select (value->'ledger'->>'sellableQty')::bigint from transfer_072_after),(select (value->'ledger'->>'sellableQty')::bigint-2 from transfer_072_baseline),'Scenario E Explain SELLABLE falls two');
select is((select (value->'ledger'->>'quarantineQty')::bigint from transfer_072_after),(select (value->'ledger'->>'quarantineQty')::bigint+2 from transfer_072_baseline),'Scenario E Explain QUARANTINE rises two');
select is((select (value->'ledger'->>'damagedQty')::bigint from transfer_072_after),(select (value->'ledger'->>'damagedQty')::bigint from transfer_072_baseline),'Scenario E Explain DAMAGED is unchanged');
select is((select (value->'ledger'->>'onHandQty')::bigint from transfer_072_after),(select (value->'ledger'->>'onHandQty')::bigint from transfer_072_baseline),'Scenario E Explain physical total is unchanged');
select is((select (value->'projection'->>'sellableQty')::bigint from transfer_072_after),(select (value->'projection'->>'sellableQty')::bigint-2 from transfer_072_baseline),'Scenario E projection SELLABLE falls two');
select is((select (value->'projection'->>'quarantineQty')::bigint from transfer_072_after),(select (value->'projection'->>'quarantineQty')::bigint+2 from transfer_072_baseline),'Scenario E projection QUARANTINE rises two');
select is((select (value->'projection'->>'damagedQty')::bigint from transfer_072_after),(select (value->'projection'->>'damagedQty')::bigint from transfer_072_baseline),'Scenario E projection DAMAGED is unchanged');
select is((select (value->'projection'->>'onHandQty')::bigint from transfer_072_after),(select (value->'projection'->>'onHandQty')::bigint from transfer_072_baseline),'Scenario E projection physical total is unchanged');
select ok((select (value->'comparison'->>'sellableMatches') <> 'true' from transfer_072_baseline) or (select (value->'comparison'->>'sellableMatches') = 'true' from transfer_072_after),'Scenario E retains sellable comparison when baseline matched');
select ok((select (value->'comparison'->>'onHandMatches') <> 'true' from transfer_072_baseline) or (select (value->'comparison'->>'onHandMatches') = 'true' from transfer_072_after),'Scenario E retains physical comparison when baseline matched');
select is((select sellable_qty from transfer_072_group_totals where stage='after')-(select sellable_qty from transfer_072_group_totals where stage='before'),-2::bigint,'Scenario E grouped SELLABLE delta is negative two');
select is((select quarantine_qty from transfer_072_group_totals where stage='after')-(select quarantine_qty from transfer_072_group_totals where stage='before'),2::bigint,'Scenario E grouped QUARANTINE delta is positive two');
select is((select damaged_qty from transfer_072_group_totals where stage='after')-(select damaged_qty from transfer_072_group_totals where stage='before'),0::bigint,'Scenario E grouped DAMAGED delta is zero');
select is((select on_hand_qty from transfer_072_group_totals where stage='after')-(select on_hand_qty from transfer_072_group_totals where stage='before'),0::bigint,'Scenario E grouped physical delta is zero');
select is((select ((sellable_qty+quarantine_qty+damaged_qty)-on_hand_qty)::bigint from transfer_072_group_totals where stage='after')-(select ((sellable_qty+quarantine_qty+damaged_qty)-on_hand_qty)::bigint from transfer_072_group_totals where stage='before'),0::bigint,'Scenario E grouped bucket equation equals on-hand delta without double count');
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
select ok((select pg_get_functiondef('api.product_stock_explanation(uuid)'::regprocedure)) ~ 'raw_entries', 'authoritative totals are derived from raw ledger entries before metadata enrichment');

select * from finish();
rollback;
