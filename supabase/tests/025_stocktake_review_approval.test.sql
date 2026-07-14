begin;

create extension if not exists pgtap with schema extensions;

select plan(65);

select has_table('operations'::name, 'stocktake_approvals'::name);
select has_table('operations'::name, 'stocktake_approval_lines'::name);
select has_column('operations'::name, 'stocktake_lines'::name, 'review_decision_code'::name, 'operations.stocktake_lines.review_decision_code exists');
select has_column('operations'::name, 'stocktakes'::name, 'current_approval_id'::name, 'operations.stocktakes.current_approval_id exists');
select has_column('operations'::name, 'stocktakes'::name, 'approval_version_no'::name, 'operations.stocktakes.approval_version_no exists');
select has_column('operations'::name, 'stocktakes'::name, 'approved_by'::name, 'operations.stocktakes.approved_by exists');
select function_returns('api', 'review_stocktake_line', array['uuid','text','uuid','uuid','bigint','text','text','text','text','jsonb']::text[], 'jsonb');
select function_returns('api', 'request_stocktake_review_recount', array['uuid','text','uuid','uuid','bigint','text','jsonb']::text[], 'jsonb');
select function_returns('api', 'approve_stocktake', array['uuid','text','uuid','bigint','boolean','text','jsonb']::text[], 'jsonb');
select ok(has_function_privilege('authenticated','api.review_stocktake_line(uuid,text,uuid,uuid,bigint,text,text,text,text,jsonb)','EXECUTE'),'authenticated Admin may review stocktake lines');
select ok(has_function_privilege('authenticated','api.request_stocktake_review_recount(uuid,text,uuid,uuid,bigint,text,jsonb)','EXECUTE'),'authenticated Admin may request recount from review');
select ok(has_function_privilege('authenticated','api.approve_stocktake(uuid,text,uuid,bigint,boolean,text,jsonb)','EXECUTE'),'authenticated Admin may approve a stocktake');
select ok(not has_function_privilege('anon','api.review_stocktake_line(uuid,text,uuid,uuid,bigint,text,text,text,text,jsonb)','EXECUTE'),'anonymous users cannot review stocktake lines');
select ok(not has_function_privilege('anon','api.request_stocktake_review_recount(uuid,text,uuid,uuid,bigint,text,jsonb)','EXECUTE'),'anonymous users cannot request recount from review');
select ok(not has_function_privilege('anon','api.approve_stocktake(uuid,text,uuid,bigint,boolean,text,jsonb)','EXECUTE'),'anonymous users cannot approve a stocktake');
select has_view('api'::name, 'stocktake_approvals'::name);
select has_view('api'::name, 'stocktake_approval_lines'::name);
select has_trigger('operations'::name, 'stocktake_approvals'::name, 'trg_stocktake_approvals_immutable'::name, 'approval headers have an immutable trigger');
select has_trigger('operations'::name, 'stocktake_approval_lines'::name, 'trg_stocktake_approval_lines_immutable'::name, 'approval lines have an immutable trigger');
select has_trigger('operations'::name, 'stocktake_lines'::name, 'trg_stocktake_lines_reset_review_decision'::name, 'new count attempts reset stale review decisions');

insert into auth.users (
  instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,
  raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous
)
values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  '93000000-0000-4000-8000-000000000001'::uuid,
  'authenticated','authenticated','pgtap.stocktake.review@glowlab.invalid',
  '2026-07-17 07:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,
  '2026-07-17 07:00:00+07'::timestamptz,
  '2026-07-17 07:00:00+07'::timestamptz,false,false
);

insert into app.user_profiles (
  user_id,organization_id,display_name,employee_code,role_code,is_active
)
values (
  '93000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Stocktake Review Admin','PGTAP-STK-REVIEW','ADMIN',true
);

insert into app.organizations (
  id,code,name,timezone,is_active,created_at,created_by
)
values (
  '00000000-0000-4000-8000-000000000003'::uuid,
  'PGTAP_STOCKTAKE_REVIEW_OTHER',
  'pgTAP Stocktake Review Other Organization',
  'Asia/Jakarta',true,'2026-07-17 07:00:00+07'::timestamptz,null
);

create temp table stocktake_review_fixture_values (
  ledger_seq bigint not null,
  sellable_qty bigint not null,
  damaged_qty bigint not null
) on commit drop;

insert into stocktake_review_fixture_values
select
  coalesce(max(entry.ledger_seq),0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.product_id='30000000-0000-4000-8000-000000000001'::uuid
      and entry.batch_id='40000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code='SELLABLE'
  ),0)::bigint,
  coalesce(sum(entry.quantity_delta) filter (
    where entry.product_id='30000000-0000-4000-8000-000000000001'::uuid
      and entry.batch_id='40000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code='DAMAGED'
  ),0)::bigint
from inventory.stock_ledger_entries entry
where entry.organization_id='00000000-0000-4000-8000-000000000001'::uuid;

grant select on stocktake_review_fixture_values to authenticated;

create temp table stocktake_review_results (
  kind text primary key,
  result jsonb not null
) on commit drop;
grant select,insert,update on stocktake_review_results to authenticated;

create temp table stocktake_review_stock_baseline (
  transaction_count bigint not null,
  ledger_count bigint not null,
  batch_sellable bigint not null,
  product_sellable bigint not null
) on commit drop;

insert into stocktake_review_stock_baseline
select
  (select count(*) from inventory.stock_transactions where organization_id='00000000-0000-4000-8000-000000000001'::uuid),
  (select count(*) from inventory.stock_ledger_entries where organization_id='00000000-0000-4000-8000-000000000001'::uuid),
  (select sellable_qty from inventory.stock_batch_balances where organization_id='00000000-0000-4000-8000-000000000001'::uuid and batch_id='40000000-0000-4000-8000-000000000001'::uuid),
  (select sellable_qty from inventory.stock_product_positions where organization_id='00000000-0000-4000-8000-000000000001'::uuid and product_id='30000000-0000-4000-8000-000000000001'::uuid);

insert into inventory.idempotency_commands (
  id,organization_id,scope,key,request_hash,status_code,started_at,
  completed_at,response_snapshot
)
values
('84000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000001'::uuid,'CREATE_STOCKTAKE','PGTAP-STOCKTAKE-REVIEW-CREATE-001',repeat('a',64),'SUCCEEDED','2026-07-17 08:00:00+07'::timestamptz,'2026-07-17 08:00:01+07'::timestamptz,'{"status":"REVIEW"}'::jsonb),
('84000000-0000-4000-8000-000000000002'::uuid,'00000000-0000-4000-8000-000000000001'::uuid,'CREATE_STOCKTAKE','PGTAP-STOCKTAKE-RECOUNT-CREATE-001',repeat('b',64),'SUCCEEDED','2026-07-17 08:10:00+07'::timestamptz,'2026-07-17 08:10:01+07'::timestamptz,'{"status":"REVIEW"}'::jsonb);

insert into operations.stocktakes (
  id,organization_id,stocktake_no,title,stocktake_type_code,mode_code,
  visibility_code,status_code,scope_definition,tolerance_policy_snapshot,
  rule_version,timezone_snapshot,planned_at,snapshot_ledger_seq,started_at,
  counting_completed_at,created_by,process_name,create_idempotency_command_id,
  note,metadata,created_at,updated_at,version_no
)
select
  '80000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000001'::uuid,
  'STK-REVIEW-001','Stocktake review approval fixture','CYCLE','CONTINUOUS',
  'BLIND','REVIEW','{"mode":"BATCHES","batchIds":["40000000-0000-4000-8000-000000000001"],"bucketCodes":["SELLABLE","DAMAGED"]}'::jsonb,
  '{"units":0,"percent":0}'::jsonb,'stocktake-continuous-v1','Asia/Jakarta',
  '2026-07-17 08:00:00+07'::timestamptz,ledger_seq,'2026-07-17 08:00:01+07'::timestamptz,
  '2026-07-17 08:20:00+07'::timestamptz,null::uuid,'pgtap.stocktake_review_approval',
  '84000000-0000-4000-8000-000000000001'::uuid,'Review fixture.',
  '{"fixture":"review"}'::jsonb,'2026-07-17 08:00:00+07'::timestamptz,'2026-07-17 08:20:00+07'::timestamptz,5
from stocktake_review_fixture_values
union all
select
  '80000000-0000-4000-8000-000000000002'::uuid,'00000000-0000-4000-8000-000000000001'::uuid,
  'STK-RECOUNT-001','Stocktake review recount fixture','CYCLE','CONTINUOUS',
  'BLIND','REVIEW','{"mode":"BATCHES","batchIds":["40000000-0000-4000-8000-000000000001"],"bucketCodes":["SELLABLE"]}'::jsonb,
  '{"units":0,"percent":0}'::jsonb,'stocktake-continuous-v1','Asia/Jakarta',
  '2026-07-17 08:10:00+07'::timestamptz,ledger_seq,'2026-07-17 08:10:01+07'::timestamptz,
  '2026-07-17 08:25:00+07'::timestamptz,null::uuid,'pgtap.stocktake_review_recount',
  '84000000-0000-4000-8000-000000000002'::uuid,'Review recount fixture.',
  '{"fixture":"review-recount"}'::jsonb,'2026-07-17 08:10:00+07'::timestamptz,'2026-07-17 08:25:00+07'::timestamptz,3
from stocktake_review_fixture_values;

insert into operations.stocktake_lines (
  id,organization_id,stocktake_id,line_no,product_id,batch_id,bucket_code,
  product_sku_snapshot,product_name_snapshot,batch_code_snapshot,
  expiry_date_snapshot,system_qty_at_snapshot,count_status_code,
  review_status_code,created_at,updated_at,version_no
)
select
  '81000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000001'::uuid,
  '80000000-0000-4000-8000-000000000001'::uuid,1,
  '30000000-0000-4000-8000-000000000001'::uuid,'40000000-0000-4000-8000-000000000001'::uuid,
  'SELLABLE','SER-NIA-30','Serum Niacinamide 30 ml','SER-2608-A','2026-08-01'::date,
  sellable_qty,'PENDING','PENDING','2026-07-17 08:00:01+07'::timestamptz,'2026-07-17 08:00:01+07'::timestamptz,1
from stocktake_review_fixture_values
union all
select
  '81000000-0000-4000-8000-000000000002'::uuid,'00000000-0000-4000-8000-000000000001'::uuid,
  '80000000-0000-4000-8000-000000000001'::uuid,2,
  '30000000-0000-4000-8000-000000000001'::uuid,'40000000-0000-4000-8000-000000000001'::uuid,
  'DAMAGED','SER-NIA-30','Serum Niacinamide 30 ml','SER-2608-A','2026-08-01'::date,
  damaged_qty,'PENDING','PENDING','2026-07-17 08:00:01+07'::timestamptz,'2026-07-17 08:00:01+07'::timestamptz,1
from stocktake_review_fixture_values
union all
select
  '81000000-0000-4000-8000-000000000003'::uuid,'00000000-0000-4000-8000-000000000001'::uuid,
  '80000000-0000-4000-8000-000000000002'::uuid,1,
  '30000000-0000-4000-8000-000000000001'::uuid,'40000000-0000-4000-8000-000000000001'::uuid,
  'SELLABLE','SER-NIA-30','Serum Niacinamide 30 ml','SER-2608-A','2026-08-01'::date,
  sellable_qty,'PENDING','PENDING','2026-07-17 08:10:01+07'::timestamptz,'2026-07-17 08:10:01+07'::timestamptz,1
from stocktake_review_fixture_values;

insert into operations.stocktake_snapshots (
  id,organization_id,stocktake_id,stocktake_line_id,product_id,batch_id,
  bucket_code,snapshot_ledger_seq,system_qty_at_snapshot,product_sku_snapshot,
  product_name_snapshot,batch_code_snapshot,expiry_date_snapshot,created_at
)
select
  ('82000000-0000-4000-8000-00000000000' || line.line_no)::uuid,
  line.organization_id,line.stocktake_id,line.id,line.product_id,line.batch_id,
  line.bucket_code,stocktake.snapshot_ledger_seq,line.system_qty_at_snapshot,
  line.product_sku_snapshot,line.product_name_snapshot,line.batch_code_snapshot,
  line.expiry_date_snapshot,stocktake.started_at
from operations.stocktake_lines line
join operations.stocktakes stocktake
  on stocktake.organization_id=line.organization_id and stocktake.id=line.stocktake_id
where line.stocktake_id='80000000-0000-4000-8000-000000000001'::uuid;

insert into operations.stocktake_snapshots (
  id,organization_id,stocktake_id,stocktake_line_id,product_id,batch_id,
  bucket_code,snapshot_ledger_seq,system_qty_at_snapshot,product_sku_snapshot,
  product_name_snapshot,batch_code_snapshot,expiry_date_snapshot,created_at
)
select
  '82000000-0000-4000-8000-000000000003',
  line.organization_id,line.stocktake_id,line.id,line.product_id,line.batch_id,
  line.bucket_code,stocktake.snapshot_ledger_seq,line.system_qty_at_snapshot,
  line.product_sku_snapshot,line.product_name_snapshot,line.batch_code_snapshot,
  line.expiry_date_snapshot,stocktake.started_at
from operations.stocktake_lines line
join operations.stocktakes stocktake
  on stocktake.organization_id=line.organization_id and stocktake.id=line.stocktake_id
where line.id='81000000-0000-4000-8000-000000000003'::uuid;

insert into operations.stocktake_count_attempts (
  id,organization_id,stocktake_id,stocktake_line_id,attempt_no,physical_qty,
  counted_at,count_cutoff_ledger_seq,expected_qty_at_count,variance_qty,
  expected_formula_version,counted_by,process_name,count_method_code,
  zero_confirmed,note,idempotency_key,request_hash,status_code,created_at
)
select
  '83000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000001'::uuid,
  '80000000-0000-4000-8000-000000000001'::uuid,'81000000-0000-4000-8000-000000000001'::uuid,
  1,sellable_qty,'2026-07-17 08:15:00+07'::timestamptz,ledger_seq,sellable_qty,0,
  'continuous-ledger-cutoff-v1',null::uuid,'pgtap.stocktake_review_approval',
  'MANUAL_ENTRY',(sellable_qty=0)::boolean,'Matched fixture attempt.',
  'PGTAP-STOCKTAKE-REVIEW-COUNT-001',repeat('c',64),'VALID','2026-07-17 08:15:00+07'::timestamptz
from stocktake_review_fixture_values
union all
select
  '83000000-0000-4000-8000-000000000002'::uuid,'00000000-0000-4000-8000-000000000001'::uuid,
  '80000000-0000-4000-8000-000000000001'::uuid,'81000000-0000-4000-8000-000000000002'::uuid,
  1,damaged_qty+2,'2026-07-17 08:16:00+07'::timestamptz,ledger_seq,damaged_qty,2,
  'continuous-ledger-cutoff-v1',null::uuid,'pgtap.stocktake_review_approval',
  'MANUAL_ENTRY',false,'Variance fixture attempt.',
  'PGTAP-STOCKTAKE-REVIEW-COUNT-002',repeat('d',64),'VALID','2026-07-17 08:16:00+07'::timestamptz
from stocktake_review_fixture_values
union all
select
  '83000000-0000-4000-8000-000000000003'::uuid,'00000000-0000-4000-8000-000000000001'::uuid,
  '80000000-0000-4000-8000-000000000002'::uuid,'81000000-0000-4000-8000-000000000003'::uuid,
  1,sellable_qty+1,'2026-07-17 08:17:00+07'::timestamptz,ledger_seq,sellable_qty,1,
  'continuous-ledger-cutoff-v1',null::uuid,'pgtap.stocktake_review_recount',
  'MANUAL_ENTRY',false,'Review recount fixture attempt.',
  'PGTAP-STOCKTAKE-RECOUNT-COUNT-001',repeat('e',64),'VALID','2026-07-17 08:17:00+07'::timestamptz
from stocktake_review_fixture_values;

update operations.stocktake_lines line
set
  final_attempt_id=attempt.id,
  final_physical_qty=attempt.physical_qty,
  expected_qty_at_count=attempt.expected_qty_at_count,
  variance_qty=attempt.variance_qty,
  count_cutoff_ledger_seq=attempt.count_cutoff_ledger_seq,
  expected_formula_version=attempt.expected_formula_version,
  count_attempt_no=attempt.attempt_no,
  count_status_code='COUNTED',
  review_status_code='READY',
  version_no=2
from operations.stocktake_count_attempts attempt
where attempt.organization_id=line.organization_id
  and attempt.stocktake_id=line.stocktake_id
  and attempt.stocktake_line_id=line.id
  and attempt.attempt_no=1;

select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','93000000-0000-4000-8000-000000000001',
    'role','authenticated',
    'email','pgtap.stocktake.review@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

select throws_ok(
  $$select api.review_stocktake_line(
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-STOCKTAKE-REVIEW-STALE-LINE-001',
    '80000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    1,'MATCHED',null,null,null,'{}'::jsonb
  )$$,
  'P0001','STOCKTAKE_LINE_VERSION_CONFLICT',
  'review rejects a stale line version'
);
select throws_ok(
  $$select api.review_stocktake_line(
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-STOCKTAKE-REVIEW-MATCH-NONZERO-001',
    '80000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000002',
    2,'MATCHED',null,null,null,'{}'::jsonb
  )$$,
  'P0001','STOCKTAKE_REVIEW_DECISION_INVALID',
  'nonzero variance cannot be marked matched'
);
select throws_ok(
  $$select api.review_stocktake_line(
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-STOCKTAKE-REVIEW-NO-REASON-001',
    '80000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000002',
    2,'VARIANCE_ACCEPTED',null,null,null,'{}'::jsonb
  )$$,
  'P0001','STOCKTAKE_REASON_REQUIRED',
  'accepted variance requires a reason'
);
select throws_ok(
  $$select api.review_stocktake_line(
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-STOCKTAKE-REVIEW-UNKNOWN-NOTE-001',
    '80000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000002',
    2,'VARIANCE_ACCEPTED','UNKNOWN',null,null,'{}'::jsonb
  )$$,
  'P0001','STOCKTAKE_REVIEW_NOTE_REQUIRED',
  'UNKNOWN reason requires a review note'
);

insert into stocktake_review_results
select 'MATCHED_REVIEW',api.review_stocktake_line(
  '00000000-0000-4000-8000-000000000001',
  'PGTAP-STOCKTAKE-REVIEW-MATCHED-001',
  '80000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  2,'MATCHED',null,'Count matches the ledger basis.',null,
  '{"fixture":"matched-review"}'::jsonb
);

reset role;

select is((select result->>'decisionCode' from stocktake_review_results where kind='MATCHED_REVIEW'),'MATCHED','matched review returns the matched decision');
select is((select review_status_code from operations.stocktake_lines where id='81000000-0000-4000-8000-000000000001'),'REVIEWED','matched review marks the line reviewed');
select is((select review_decision_code from operations.stocktake_lines where id='81000000-0000-4000-8000-000000000001'),'MATCHED','matched review stores the explicit decision');

set local role authenticated;

insert into stocktake_review_results
select 'VARIANCE_REVIEW',api.review_stocktake_line(
  '00000000-0000-4000-8000-000000000001',
  'PGTAP-STOCKTAKE-REVIEW-VARIANCE-001',
  '80000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000002',
  2,'VARIANCE_ACCEPTED','PHYSICAL_SURPLUS',
  'Physical surplus verified during review.',null,
  '{"fixture":"variance-review"}'::jsonb
);

reset role;

select is((select result->>'decisionCode' from stocktake_review_results where kind='VARIANCE_REVIEW'),'VARIANCE_ACCEPTED','accepted variance returns the explicit decision');
select is((select reason_code from operations.stocktake_lines where id='81000000-0000-4000-8000-000000000002'),'PHYSICAL_SURPLUS','accepted variance stores the approved reason');
select is((select version_no from operations.stocktakes where id='80000000-0000-4000-8000-000000000001'),7::bigint,'each review decision increments the stocktake version');

set local role authenticated;

select throws_ok(
  $$select api.approve_stocktake(
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-STOCKTAKE-APPROVE-STALE-001',
    '80000000-0000-4000-8000-000000000001',
    6,true,null,'{}'::jsonb
  )$$,
  'P0001','STOCKTAKE_APPROVAL_VERSION_CONFLICT',
  'approval rejects a stale stocktake version'
);
select throws_ok(
  $$select api.approve_stocktake(
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-STOCKTAKE-APPROVE-NO-CONFIRM-001',
    '80000000-0000-4000-8000-000000000001',
    7,false,null,'{}'::jsonb
  )$$,
  'P0001','STOCKTAKE_APPROVAL_CONFIRMATION_REQUIRED',
  'approval requires explicit confirmation'
);

insert into stocktake_review_results
select 'APPROVAL',api.approve_stocktake(
  '00000000-0000-4000-8000-000000000001',
  'PGTAP-STOCKTAKE-APPROVE-001',
  '80000000-0000-4000-8000-000000000001',
  7,true,'Approval fixture.','{"fixture":"approval"}'::jsonb
);

reset role;

select is((select result->>'status' from stocktake_review_results where kind='APPROVAL'),'APPROVED','approval command returns approved status');
select is((select status_code from operations.stocktakes where id='80000000-0000-4000-8000-000000000001'),'APPROVED','approval transitions the stocktake to approved');
select is((select count(*) from operations.stocktake_approvals where stocktake_id='80000000-0000-4000-8000-000000000001'),1::bigint,'approval stores one immutable header');
select is((select count(*) from operations.stocktake_approval_lines where stocktake_id='80000000-0000-4000-8000-000000000001'),2::bigint,'approval snapshots every reviewed line');
select matches((select approval_hash from operations.stocktake_approvals where stocktake_id='80000000-0000-4000-8000-000000000001'),'^[0-9a-f]{64}$','approval stores a deterministic SHA-256 hash');
select ok((select current_approval_id is not null from operations.stocktakes where id='80000000-0000-4000-8000-000000000001'),'approved stocktake links the current approval');
select is((select approved_by from operations.stocktakes where id='80000000-0000-4000-8000-000000000001'),'93000000-0000-4000-8000-000000000001'::uuid,'approved stocktake records the authenticated Admin');
select throws_ok(
  $$update operations.stocktake_approvals set note='Mutation must fail.' where stocktake_id='80000000-0000-4000-8000-000000000001'$$,
  'P0001','IMMUTABLE_LEDGER_RECORD','approval headers are immutable'
);
select throws_ok(
  $$delete from operations.stocktake_approval_lines where stocktake_id='80000000-0000-4000-8000-000000000001'$$,
  'P0001','IMMUTABLE_LEDGER_RECORD','approval line snapshots are immutable'
);

set local role authenticated;

insert into stocktake_review_results
select 'APPROVAL_REPLAY',api.approve_stocktake(
  '00000000-0000-4000-8000-000000000001',
  'PGTAP-STOCKTAKE-APPROVE-001',
  '80000000-0000-4000-8000-000000000001',
  7,true,'Approval fixture.','{"fixture":"approval"}'::jsonb
);

reset role;

select is((select result from stocktake_review_results where kind='APPROVAL_REPLAY'),(select result from stocktake_review_results where kind='APPROVAL'),'identical approval replay returns the stored response');

set local role authenticated;

select throws_ok(
  $$select api.approve_stocktake(
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-STOCKTAKE-APPROVE-001',
    '80000000-0000-4000-8000-000000000001',
    7,true,'Different payload.','{"fixture":"approval"}'::jsonb
  )$$,
  'P0001','IDEMPOTENCY_KEY_REUSED',
  'approval key reuse with another payload is rejected'
);
select throws_ok(
  $$select api.review_stocktake_line(
    '00000000-0000-4000-8000-000000000003',
    'PGTAP-STOCKTAKE-REVIEW-CROSS-ORG-001',
    '80000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    3,'MATCHED',null,null,null,'{}'::jsonb
  )$$,
  '42501','ORGANIZATION_ACCESS_DENIED',
  'cross-organization review command is denied'
);

insert into stocktake_review_results
select 'REVIEW_RECOUNT',api.request_stocktake_review_recount(
  '00000000-0000-4000-8000-000000000001',
  'PGTAP-STOCKTAKE-REVIEW-RECOUNT-001',
  '80000000-0000-4000-8000-000000000002',
  '81000000-0000-4000-8000-000000000003',
  2,'Recount the physical quantity during review.',
  '{"fixture":"review-recount"}'::jsonb
);

reset role;

select is((select result->>'status' from stocktake_review_results where kind='REVIEW_RECOUNT'),'COUNTING','review recount returns counting status');
select is((select status_code from operations.stocktakes where id='80000000-0000-4000-8000-000000000002'),'COUNTING','review recount returns the session to counting');
select is((select count_status_code from operations.stocktake_lines where id='81000000-0000-4000-8000-000000000003'),'RECOUNT_REQUESTED','review recount marks the line for recount');
select is((select review_decision_code from operations.stocktake_lines where id='81000000-0000-4000-8000-000000000003'),'RECOUNT_REQUIRED','review recount stores the explicit recount decision');
select is((select final_attempt_id from operations.stocktake_lines where id='81000000-0000-4000-8000-000000000003'),'83000000-0000-4000-8000-000000000003'::uuid,'review recount preserves the prior final attempt');
select is((select count(*) from operations.stocktake_count_attempts where stocktake_line_id='81000000-0000-4000-8000-000000000003'),1::bigint,'review recount does not create a count attempt');

set local role authenticated;

insert into stocktake_review_results
select 'RECOUNT_COUNT',api.submit_stocktake_count(
  '00000000-0000-4000-8000-000000000001',
  'PGTAP-STOCKTAKE-REVIEW-RECOUNT-COUNT-002',
  '80000000-0000-4000-8000-000000000002',
  '81000000-0000-4000-8000-000000000003',
  (select sellable_qty from stocktake_review_fixture_values),
  (select sellable_qty=0 from stocktake_review_fixture_values),
  'MANUAL_ENTRY','Second count after review recount.',
  '{"fixture":"review-recount-second-count"}'::jsonb
);

reset role;

select is((select result->>'status' from stocktake_review_results where kind='RECOUNT_COUNT'),'COUNTED','review recount can submit a new count');
select is((select count(*) from operations.stocktake_count_attempts where stocktake_line_id='81000000-0000-4000-8000-000000000003'),2::bigint,'recount appends a second count attempt');
select is((select count(*) from operations.stocktake_count_attempts where id='83000000-0000-4000-8000-000000000003'),1::bigint,'recount preserves the first count attempt');
select is((select review_decision_code from operations.stocktake_lines where id='81000000-0000-4000-8000-000000000003'),null,'a new final attempt clears the stale review decision');
select is((select review_status_code from operations.stocktake_lines where id='81000000-0000-4000-8000-000000000003'),'READY','a new final attempt returns the line to ready review status');

set local role authenticated;

insert into stocktake_review_results
select 'RECOUNT_COMPLETE',api.complete_stocktake_counting(
  '00000000-0000-4000-8000-000000000001',
  'PGTAP-STOCKTAKE-REVIEW-RECOUNT-COMPLETE-001',
  '80000000-0000-4000-8000-000000000002',
  '{"fixture":"review-recount-complete"}'::jsonb
);

reset role;

select is((select result->>'status' from stocktake_review_results where kind='RECOUNT_COMPLETE'),'REVIEW','recounted session can complete counting again');
select is((select status_code from operations.stocktakes where id='80000000-0000-4000-8000-000000000002'),'REVIEW','recounted session returns to review');

select ok(not has_table_privilege('authenticated','operations.stocktake_approvals','INSERT'),'authenticated users cannot insert approval headers directly');
select ok(not has_table_privilege('authenticated','operations.stocktake_approval_lines','INSERT'),'authenticated users cannot insert approval line snapshots directly');

select is((select count(*) from inventory.stock_transactions where organization_id='00000000-0000-4000-8000-000000000001'),(select transaction_count from stocktake_review_stock_baseline),'review and approval create no stock transaction');
select is((select count(*) from inventory.stock_ledger_entries where organization_id='00000000-0000-4000-8000-000000000001'),(select ledger_count from stocktake_review_stock_baseline),'review and approval append no ledger entry');
select is((select sellable_qty from inventory.stock_batch_balances where organization_id='00000000-0000-4000-8000-000000000001' and batch_id='40000000-0000-4000-8000-000000000001'),(select batch_sellable from stocktake_review_stock_baseline),'review and approval do not change the batch projection');
select is((select sellable_qty from inventory.stock_product_positions where organization_id='00000000-0000-4000-8000-000000000001' and product_id='30000000-0000-4000-8000-000000000001'),(select product_sellable from stocktake_review_stock_baseline),'review and approval do not change the product projection');

select is((select line_version_no from operations.stocktake_approval_lines where stocktake_line_id='81000000-0000-4000-8000-000000000001'),3::bigint,'approval snapshot preserves the reviewed line version');
select is((select final_attempt_id from operations.stocktake_approval_lines where stocktake_line_id='81000000-0000-4000-8000-000000000001'),'83000000-0000-4000-8000-000000000001'::uuid,'approval snapshot preserves the approved final attempt');

select * from finish();

rollback;
