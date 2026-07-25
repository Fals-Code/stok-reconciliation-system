begin;

create extension if not exists pgtap with schema extensions;

select plan(58);

select has_table('operations','return_late_arrivals','late-arrival header exists');
select has_table('operations','return_late_arrival_lines','append-only late-arrival allocations exist');
select has_table('operations','return_late_arrival_claim_links','claim-conflict snapshots exist');
select has_column('operations','return_items','late_arrival_qty','return item exposes late-arrival cache');
select has_column('operations','return_receipt_lines','late_arrival_line_id','receipt line has typed late-arrival linkage');
select has_view('api','return_late_arrivals','safe late-arrival header view exists');
select has_view('api','return_late_arrival_lines','safe late-arrival line view exists');
select has_view('api','return_late_arrival_claim_links','safe late-arrival claim-link view exists');
select has_function('api','confirm_late_return_arrival',array['uuid','text','text','text','text','timestamp with time zone','jsonb','text','jsonb'],'trusted late-arrival command exists');
select ok((select relrowsecurity from pg_class where oid='operations.return_late_arrivals'::regclass),'late-arrival headers have RLS');
select ok((select relrowsecurity from pg_class where oid='operations.return_late_arrival_lines'::regclass),'late-arrival lines have RLS');
select ok((select relrowsecurity from pg_class where oid='operations.return_late_arrival_claim_links'::regclass),'late-arrival claim links have RLS');
select ok(not has_table_privilege('authenticated','operations.return_late_arrivals','INSERT'),'authenticated cannot insert late-arrival headers directly');
select ok(not has_table_privilege('authenticated','operations.return_late_arrival_lines','INSERT'),'authenticated cannot insert late-arrival lines directly');
select ok(not has_table_privilege('authenticated','operations.return_late_arrival_claim_links','INSERT'),'authenticated cannot insert late-arrival claim links directly');
select ok(has_function_privilege('authenticated','api.confirm_late_return_arrival(uuid,text,text,text,text,timestamp with time zone,jsonb,text,jsonb)','EXECUTE'),'authenticated Admin may invoke the trusted late-arrival command');
select ok(not has_function_privilege('anon','api.confirm_late_return_arrival(uuid,text,text,text,text,timestamp with time zone,jsonb,text,jsonb)','EXECUTE'),'anonymous users cannot invoke the late-arrival command');
select ok((select prosecdef from pg_proc where oid='api.confirm_late_return_arrival(uuid,text,text,text,text,timestamp with time zone,jsonb,text,jsonb)'::regprocedure),'late-arrival command is SECURITY DEFINER');
select matches(coalesce((select array_to_string(proconfig,',') from pg_proc where oid='api.confirm_late_return_arrival(uuid,text,text,text,text,timestamp with time zone,jsonb,text,jsonb)'::regprocedure),''),'^search_path=pg_catalog, auth, app, catalog, inventory, operations, extensions$','late-arrival command has a fixed search_path');
select ok(exists(select 1 from pg_trigger where tgrelid='operations.return_late_arrival_lines'::regclass and tgname='trg_return_late_arrival_lines_immutable'),'late-arrival allocation history is immutable');
select ok(exists(select 1 from pg_constraint where conrelid='operations.return_items'::regclass and conname='ck_return_items_late_arrival_accounting'),'gross-lost correction accounting is constrained');
select ok(exists(select 1 from pg_constraint where conname='fk_return_late_arrival_lines_lost_event_line' and conrelid='operations.return_late_arrival_lines'::regclass and contype='f') and exists(select 1 from pg_constraint where conname='fk_return_receipt_lines_late_arrival_line' and conrelid='operations.return_receipt_lines'::regclass and contype='f') and exists(select 1 from pg_constraint where conname='fk_return_late_arrival_claim_links_claim' and conrelid='operations.return_late_arrival_claim_links'::regclass and contype='f'),'late-arrival allocations retain typed LOST, receipt, and claim foreign-key links');
select ok(exists(select 1 from pg_indexes where schemaname='operations' and indexname='idx_return_late_arrivals_return') and exists(select 1 from pg_indexes where schemaname='operations' and indexname='idx_return_late_arrival_lines_item') and exists(select 1 from pg_indexes where schemaname='operations' and indexname='idx_return_late_arrival_claim_links_claim'),'late-arrival header, allocation, and claim-link lookup indexes exist');

create temp table late_results(kind text primary key,result jsonb not null) on commit drop;
grant select, insert, update on late_results to authenticated;
insert into app.organizations(id,code,name,timezone,is_active) values('00000000-0000-4000-8000-000000000002'::uuid,'ORG-057-CROSS','Organization 057 cross-org','Asia/Jakarta',true);
select set_config('request.jwt.claim.sub','720d8ca5-3f95-4a20-8063-d24981ad551d',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"720d8ca5-3f95-4a20-8063-d24981ad551d","role":"authenticated"}',true);
set local role authenticated;

insert into late_results select 'RESERVE',api.apply_marketplace_event('00000000-0000-4000-8000-000000000001','057-RESERVE','TIKTOK_SHOP','RESERVE','057-RESERVE-EVENT','057-ORDER','2026-07-01 09:00:00+07',jsonb_build_array(jsonb_build_object('productId','30000000-0000-4000-8000-000000000001','quantity',3,'sourceLineRef','057-A'),jsonb_build_object('productId','30000000-0000-4000-8000-000000000002','quantity',3,'sourceLineRef','057-B')),'fixture','{}');
insert into late_results select 'SHIP',api.apply_marketplace_event('00000000-0000-4000-8000-000000000001','057-SHIP','TIKTOK_SHOP','SHIP','057-SHIP-EVENT','057-ORDER','2026-07-02 09:00:00+07',jsonb_build_array(jsonb_build_object('productId','30000000-0000-4000-8000-000000000001','quantity',3,'sourceLineRef','057-A'),jsonb_build_object('productId','30000000-0000-4000-8000-000000000002','quantity',3,'sourceLineRef','057-B')),'fixture','{}');
insert into late_results select 'EXPECTED',api.create_expected_return('00000000-0000-4000-8000-000000000001','057-EXPECTED','TIKTOK_SHOP','057-RETURN','057-ORDER','2026-07-03 09:00:00+07',jsonb_build_array(jsonb_build_object('productId','30000000-0000-4000-8000-000000000001','quantity',3,'sourceLineRef','057-A'),jsonb_build_object('productId','30000000-0000-4000-8000-000000000002','quantity',3,'sourceLineRef','057-B')),'RETURN_REQUESTED','fixture','{}');
create temp table late_fixture as select returned.id return_id,item_a.id product_a_return_item_id,item_b.id product_b_return_item_id from operations.returns returned join operations.return_items item_a on item_a.organization_id=returned.organization_id and item_a.return_id=returned.id and item_a.product_id='30000000-0000-4000-8000-000000000001'::uuid and item_a.source_line_ref='057-A' join operations.return_items item_b on item_b.organization_id=returned.organization_id and item_b.return_id=returned.id and item_b.product_id='30000000-0000-4000-8000-000000000002'::uuid and item_b.source_line_ref='057-B' where returned.organization_id='00000000-0000-4000-8000-000000000001'::uuid and returned.external_return_ref='057-RETURN';
insert into late_results select 'LOST_ONE',api.mark_return_lost('00000000-0000-4000-8000-000000000001','057-LOST-ONE','057-RETURN','057-LOST-ONE-EVENT','2026-07-04 09:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',2,'sourceLineRef','057-LOST-A-ONE'),jsonb_build_object('returnItemId',(select product_b_return_item_id::text from late_fixture),'quantity',2,'sourceLineRef','057-LOST-B-ONE')),'fixture','{}');
insert into late_results select 'LOST_TWO',api.mark_return_lost('00000000-0000-4000-8000-000000000001','057-LOST-TWO','057-RETURN','057-LOST-TWO-EVENT','2026-07-05 09:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',1,'sourceLineRef','057-LOST-A-TWO'),jsonb_build_object('returnItemId',(select product_b_return_item_id::text from late_fixture),'quantity',1,'sourceLineRef','057-LOST-B-TWO')),'fixture','{}');
insert into late_results select 'CLAIM',api.create_tiktok_return_claim('00000000-0000-4000-8000-000000000001','057-CLAIM',(select return_id from late_fixture),'LOST_RETURN',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',1)),'2026-07-06 09:00:00+07');
insert into late_results select 'SUBMIT',api.submit_tiktok_return_claim('00000000-0000-4000-8000-000000000001','057-CLAIM-SUBMIT',(select (result->>'claimId')::uuid from late_results where kind='CLAIM'),'057-EXTERNAL-CLAIM','2026-07-06 10:00:00+07');
insert into late_results select 'RESOLVE',api.resolve_tiktok_return_claim('00000000-0000-4000-8000-000000000001','057-CLAIM-RESOLVE',(select (result->>'claimId')::uuid from late_results where kind='CLAIM'),'APPROVED','2026-07-06 11:00:00+07');
reset role;
create temp table late_before as select jsonb_build_object('lostEvents',(select jsonb_agg(to_jsonb(event) order by event.occurred_at,event.id) from operations.return_events event where event.return_id=(select return_id from late_fixture) and event.event_type_code='LOST'),'lostLines',(select jsonb_agg(to_jsonb(line) order by line.id) from operations.return_event_lines line join operations.return_events event on event.id=line.event_id and event.organization_id=line.organization_id where event.return_id=(select return_id from late_fixture) and event.event_type_code='LOST'),'claim',(select to_jsonb(claim) from operations.return_claims claim where claim.id=(select (result->>'claimId')::uuid from late_results where kind='CLAIM')),'claimEvents',(select jsonb_agg(to_jsonb(event) order by event.occurred_at,event.id) from operations.return_claim_events event where event.claim_id=(select (result->>'claimId')::uuid from late_results where kind='CLAIM')),'stock',jsonb_build_object('transactions',(select count(*) from inventory.stock_transactions),'ledger',(select count(*) from inventory.stock_ledger_entries),'reservations',(select coalesce(jsonb_agg(to_jsonb(row) order by row.id),'[]'::jsonb) from inventory.stock_reservations row where row.organization_id='00000000-0000-4000-8000-000000000001'::uuid),'products',(select coalesce(jsonb_agg(to_jsonb(row) order by row.product_id),'[]'::jsonb) from inventory.stock_product_positions row where row.organization_id='00000000-0000-4000-8000-000000000001'::uuid and row.product_id in ('30000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000002'::uuid)),'batches',(select coalesce(jsonb_agg(to_jsonb(row) order by row.product_id,row.batch_id),'[]'::jsonb) from inventory.stock_batch_balances row where row.organization_id='00000000-0000-4000-8000-000000000001'::uuid and row.product_id in ('30000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000002'::uuid)))) snapshot;
select set_config('request.jwt.claim.sub','720d8ca5-3f95-4a20-8063-d24981ad551d',true); select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claims','{"sub":"720d8ca5-3f95-4a20-8063-d24981ad551d","role":"authenticated"}',true); set local role authenticated;
select throws_ok($$select api.confirm_return_receipt('00000000-0000-4000-8000-000000000001','057-NORMAL-REJECT','057-RETURN','057-NORMAL-REJECT','2026-07-06 12:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',1,'sourceLineRef','057-NORMAL')),'fixture','{}')$$,'P0001','RETURN_RECEIPT_EXCEEDS_PENDING','normal receipt cannot consume gross lost allowance');
insert into late_results select 'LATE',api.confirm_late_return_arrival('00000000-0000-4000-8000-000000000001','057-LATE','057-RETURN','057-LATE-REF','057-LATE-RECEIPT','2026-07-06 12:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',1),jsonb_build_object('returnItemId',(select product_b_return_item_id::text from late_fixture),'quantity',3)),'fixture','{}');
insert into late_results select 'LATE_REPLAY',api.confirm_late_return_arrival('00000000-0000-4000-8000-000000000001','057-LATE','057-RETURN','057-LATE-REF','057-LATE-RECEIPT','2026-07-06 12:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',1),jsonb_build_object('returnItemId',(select product_b_return_item_id::text from late_fixture),'quantity',3)),'fixture','{}');
reset role;

select is((select result->>'status' from late_results where kind='SHIP'),'APPLIED','TikTok shipment posts once before return handling');
select is((select count(*) from operations.return_late_arrivals where return_id=(select return_id from late_fixture)),1::bigint,'one late-arrival header is created');
select is((select coalesce(jsonb_agg(jsonb_build_object('returnItemId',allocation.return_item_id,'lostEventLineId',allocation.lost_event_line_id,'quantity',allocation.quantity) order by allocation.return_item_id,lost_event.occurred_at,lost_event.id,lost_line.line_no,allocation.lost_event_line_id),'[]'::jsonb) from operations.return_late_arrival_lines allocation join operations.return_event_lines lost_line on lost_line.organization_id=allocation.organization_id and lost_line.id=allocation.lost_event_line_id join operations.return_events lost_event on lost_event.organization_id=lost_line.organization_id and lost_event.id=lost_line.event_id where allocation.late_arrival_id=(select (result->>'lateArrivalId')::uuid from late_results where kind='LATE')),(select coalesce(jsonb_agg(jsonb_build_object('returnItemId',lost_line.return_item_id,'lostEventLineId',lost_line.id,'quantity',case lost_line.source_line_ref when '057-LOST-A-ONE' then 1 when '057-LOST-B-ONE' then 2 when '057-LOST-B-TWO' then 1 end) order by lost_line.return_item_id,lost_event.occurred_at,lost_event.id,lost_line.line_no,lost_line.id),'[]'::jsonb) from operations.return_event_lines lost_line join operations.return_events lost_event on lost_event.organization_id=lost_line.organization_id and lost_event.id=lost_line.event_id where lost_event.return_id=(select return_id from late_fixture) and lost_event.event_type_code='LOST' and ((lost_line.return_item_id=(select product_a_return_item_id from late_fixture) and lost_line.source_line_ref='057-LOST-A-ONE') or (lost_line.return_item_id=(select product_b_return_item_id from late_fixture) and lost_line.source_line_ref in ('057-LOST-B-ONE','057-LOST-B-TWO')))),'late arrival stores deterministic allocations across lost lines');
select is((select jsonb_agg(jsonb_build_object('productId',product_id,'grossLost',lost_qty,'lateArrival',late_arrival_qty,'netLost',lost_qty-late_arrival_qty,'received',received_qty) order by product_id) from operations.return_items where return_id=(select return_id from late_fixture)),jsonb_build_array(jsonb_build_object('productId','30000000-0000-4000-8000-000000000001'::uuid,'grossLost',3,'lateArrival',1,'netLost',2,'received',1),jsonb_build_object('productId','30000000-0000-4000-8000-000000000002'::uuid,'grossLost',3,'lateArrival',3,'netLost',0,'received',3)),'gross lost is preserved while correction, net loss, and receipt quantities are exact');
select is((select snapshot->'lostEvents' from late_before),(select jsonb_agg(to_jsonb(event) order by event.occurred_at,event.id) from operations.return_events event where event.return_id=(select return_id from late_fixture) and event.event_type_code='LOST'),'late arrival preserves immutable LOST event history');
select is((select snapshot->'lostLines' from late_before),(select jsonb_agg(to_jsonb(line) order by line.id) from operations.return_event_lines line join operations.return_events event on event.id=line.event_id and event.organization_id=line.organization_id where event.return_id=(select return_id from late_fixture) and event.event_type_code='LOST'),'late arrival preserves immutable LOST line history');
select is((select snapshot->'claim' from late_before),(select to_jsonb(claim) from operations.return_claims claim where claim.id=(select (result->>'claimId')::uuid from late_results where kind='CLAIM')),'late arrival does not mutate claim header or status');
select is((select snapshot->'claimEvents' from late_before),(select jsonb_agg(to_jsonb(event) order by event.occurred_at,event.id) from operations.return_claim_events event where event.claim_id=(select (result->>'claimId')::uuid from late_results where kind='CLAIM')),'late arrival does not mutate claim history');
select is((select jsonb_build_object('claimStatus',claim_status_snapshot,'warning',warning_required) from operations.return_late_arrival_claim_links where late_arrival_id=(select (result->>'lateArrivalId')::uuid from late_results where kind='LATE') and claim_id=(select (result->>'claimId')::uuid from late_results where kind='CLAIM')),jsonb_build_object('claimStatus','RESOLVED','warning',true),'resolved claim is captured as a warning-required late-arrival snapshot without a notification');
select is((select jsonb_build_object('transactions',(select count(*) from inventory.stock_transactions),'ledger',(select count(*) from inventory.stock_ledger_entries),'reservations',(select coalesce(jsonb_agg(to_jsonb(row) order by row.id),'[]'::jsonb) from inventory.stock_reservations row where row.organization_id='00000000-0000-4000-8000-000000000001'::uuid),'products',(select coalesce(jsonb_agg(to_jsonb(row) order by row.product_id),'[]'::jsonb) from inventory.stock_product_positions row where row.organization_id='00000000-0000-4000-8000-000000000001'::uuid and row.product_id in ('30000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000002'::uuid)),'batches',(select coalesce(jsonb_agg(to_jsonb(row) order by row.product_id,row.batch_id),'[]'::jsonb) from inventory.stock_batch_balances row where row.organization_id='00000000-0000-4000-8000-000000000001'::uuid and row.product_id in ('30000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000002'::uuid)))),(select snapshot->'stock' from late_before),'late receipt is stock-neutral by exact JSONB snapshot');
select is((select result from late_results where kind='LATE_REPLAY'),(select result from late_results where kind='LATE'),'late-arrival replay returns the stored response');
select is((select count(*) from operations.return_receipts where receipt_ref='057-LATE-RECEIPT'),1::bigint,'late-arrival replay creates one receipt');
select is((select count(*) from operations.return_late_arrival_claim_links where late_arrival_id=(select (result->>'lateArrivalId')::uuid from late_results where kind='LATE')),1::bigint,'late-arrival replay creates no second claim link');
select throws_ok($$select api.confirm_late_return_arrival('00000000-0000-4000-8000-000000000001','057-LATE','057-RETURN','057-LATE-REF-CHANGED','057-LATE-RECEIPT-CHANGED','2026-07-06 12:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',2)),'fixture','{}')$$,'P0001','IDEMPOTENCY_KEY_REUSED','changed late-arrival payload is rejected');
select throws_ok($$select api.confirm_late_return_arrival('00000000-0000-4000-8000-000000000001','057-OVER','057-RETURN','057-OVER-REF','057-OVER-RECEIPT','2026-07-06 13:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',3)),'fixture','{}')$$,'P0001','RETURN_LATE_ARRIVAL_EXCEEDS_NET_LOST','late arrival cannot exceed outstanding net lost quantity');
select throws_ok($$select api.confirm_late_return_arrival('00000000-0000-4000-8000-000000000001','057-DUP','057-RETURN','057-DUP-REF','057-DUP-RECEIPT','2026-07-06 13:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',1),jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',1)),'fixture','{}')$$,'P0001','RETURN_LATE_ARRIVAL_DUPLICATE_ITEM','late arrival rejects duplicate return items');
select throws_ok($$select api.confirm_late_return_arrival('00000000-0000-4000-8000-000000000001','057-ZERO','057-RETURN','057-ZERO-REF','057-ZERO-RECEIPT','2026-07-06 13:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',0)),'fixture','{}')$$,'P0001','RETURN_LATE_ARRIVAL_LINE_INVALID','late arrival rejects zero quantity');
select throws_ok($$select api.confirm_late_return_arrival('00000000-0000-4000-8000-000000000001','057-NEGATIVE','057-RETURN','057-NEGATIVE-REF','057-NEGATIVE-RECEIPT','2026-07-06 13:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',-1)),'fixture','{}')$$,'P0001','RETURN_LATE_ARRIVAL_LINE_INVALID','late arrival rejects negative quantity');
select throws_ok($$select api.confirm_late_return_arrival('00000000-0000-4000-8000-000000000001','057-FRACTION','057-RETURN','057-FRACTION-REF','057-FRACTION-RECEIPT','2026-07-06 13:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',1.5)),'fixture','{}')$$,'P0001','RETURN_LATE_ARRIVAL_LINE_INVALID','late arrival rejects fractional quantity');
select throws_ok($$select api.confirm_late_return_arrival('00000000-0000-4000-8000-000000000002','057-CROSS-ORG','057-RETURN','057-CROSS-ORG-REF','057-CROSS-ORG-RECEIPT','2026-07-06 13:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',1)),'fixture','{}')$$,'42501','ORGANIZATION_ACCESS_DENIED','late arrival rejects a return item when authenticated Admin targets another organization');
select throws_ok($$select api.confirm_late_return_arrival('00000000-0000-4000-8000-000000000001','057-ATOMIC','057-RETURN','057-ATOMIC-REF','057-ATOMIC-RECEIPT','2026-07-06 13:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select product_a_return_item_id::text from late_fixture),'quantity',1),jsonb_build_object('returnItemId',(select product_b_return_item_id::text from late_fixture),'quantity',1)),'fixture','{}')$$,'P0001','RETURN_LATE_ARRIVAL_EXCEEDS_NET_LOST','invalid second line rolls back the entire late-arrival request');
select is((select count(*) from operations.return_late_arrivals where late_arrival_reference='057-ATOMIC-REF'),0::bigint,'atomic late-arrival failure leaves no header');
select is((select count(*) from operations.return_receipts where receipt_ref='057-ATOMIC-RECEIPT'),0::bigint,'atomic late-arrival failure leaves no receipt');
select is(
  (
    select jsonb_build_object(
      'allocations',
      (
        select count(*)
        from operations.return_late_arrival_lines
        where source_line_ref like '057-ATOMIC-REF:%'
      ),
      'events',
      (
        select count(*)
        from operations.return_events
        where external_event_ref = '057-ATOMIC-REF'
      ),
      'receiptLines',
      (
        select count(*)
        from operations.return_receipt_lines receipt_line
        join operations.return_receipts receipt
          on receipt.organization_id = receipt_line.organization_id
         and receipt.id = receipt_line.receipt_id
        where receipt.receipt_ref = '057-ATOMIC-RECEIPT'
      ),
      'successfulCommands',
      (
        select count(*)
        from inventory.idempotency_commands
        where organization_id =
              '00000000-0000-4000-8000-000000000001'::uuid
          and scope = 'CONFIRM_LATE_RETURN_ARRIVAL'
          and key = '057-ATOMIC'
          and status_code = 'SUCCEEDED'
      ),
      'claimLinks',
      (
        select count(*)
        from operations.return_late_arrival_claim_links claim_link
        join operations.return_late_arrivals arrival
          on arrival.organization_id = claim_link.organization_id
         and arrival.id = claim_link.late_arrival_id
        where arrival.late_arrival_reference = '057-ATOMIC-REF'
      ),
      'itemProjection',
      (
        select jsonb_agg(
          jsonb_build_object(
            'returnItemId', item.id,
            'lateArrival', item.late_arrival_qty,
            'received', item.received_qty
          )
          order by item.id
        )
        from operations.return_items item
        where item.id in (
          (select product_a_return_item_id from late_fixture),
          (select product_b_return_item_id from late_fixture)
        )
      )
    )
  ),
  jsonb_build_object(
    'allocations', 0,
    'events', 0,
    'receiptLines', 0,
    'successfulCommands', 0,
    'claimLinks', 0,
    'itemProjection',
    (
      select jsonb_agg(
        jsonb_build_object(
          'returnItemId', expected.return_item_id,
          'lateArrival', expected.late_arrival_qty,
          'received', expected.received_qty
        )
        order by expected.return_item_id
      )
      from (
        select
          product_a_return_item_id as return_item_id,
          1::bigint as late_arrival_qty,
          1::bigint as received_qty
        from late_fixture

        union all

        select
          product_b_return_item_id,
          3::bigint,
          3::bigint
        from late_fixture
      ) expected
    )
  ),
  'atomic late-arrival failure preserves correction, event, receipt-line, idempotency, claim-link, and item projections'
);

select set_config('request.jwt.claim.sub','720d8ca5-3f95-4a20-8063-d24981ad551d',true); select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claims','{"sub":"720d8ca5-3f95-4a20-8063-d24981ad551d","role":"authenticated"}',true); set local role authenticated;
insert into late_results select 'INSPECT',api.inspect_return('00000000-0000-4000-8000-000000000001','057-INSPECT','057-RETURN','057-INSPECT-REF','2026-07-06 14:00:00+07',jsonb_build_array(jsonb_build_object('receiptLineId',(select receipt_line_id::text from api.return_receipt_lines where receipt_ref='057-LATE-RECEIPT' and product_id='30000000-0000-4000-8000-000000000001'::uuid),'sellableQuantity',1,'damagedQuantity',0,'sourceLineRef','057-INSPECT-A'),jsonb_build_object('receiptLineId',(select receipt_line_id::text from api.return_receipt_lines where receipt_ref='057-LATE-RECEIPT' and product_id='30000000-0000-4000-8000-000000000002'::uuid limit 1),'sellableQuantity',0,'damagedQuantity',2,'sourceLineRef','057-INSPECT-B-ONE'),jsonb_build_object('receiptLineId',(select receipt_line_id::text from api.return_receipt_lines where receipt_ref='057-LATE-RECEIPT' and product_id='30000000-0000-4000-8000-000000000002'::uuid offset 1 limit 1),'sellableQuantity',0,'damagedQuantity',1,'sourceLineRef','057-INSPECT-B-TWO')),'fixture','{}');
insert into late_results select 'INSPECT_REPLAY',api.inspect_return('00000000-0000-4000-8000-000000000001','057-INSPECT','057-RETURN','057-INSPECT-REF','2026-07-06 14:00:00+07',jsonb_build_array(jsonb_build_object('receiptLineId',(select receipt_line_id::text from api.return_receipt_lines where receipt_ref='057-LATE-RECEIPT' and product_id='30000000-0000-4000-8000-000000000001'::uuid),'sellableQuantity',1,'damagedQuantity',0,'sourceLineRef','057-INSPECT-A'),jsonb_build_object('receiptLineId',(select receipt_line_id::text from api.return_receipt_lines where receipt_ref='057-LATE-RECEIPT' and product_id='30000000-0000-4000-8000-000000000002'::uuid limit 1),'sellableQuantity',0,'damagedQuantity',2,'sourceLineRef','057-INSPECT-B-ONE'),jsonb_build_object('receiptLineId',(select receipt_line_id::text from api.return_receipt_lines where receipt_ref='057-LATE-RECEIPT' and product_id='30000000-0000-4000-8000-000000000002'::uuid offset 1 limit 1),'sellableQuantity',0,'damagedQuantity',1,'sourceLineRef','057-INSPECT-B-TWO')),'fixture','{}');
reset role;
select is((select result from late_results where kind='INSPECT_REPLAY'),(select result from late_results where kind='INSPECT'),'late receipt duplicate inspection replays the stored response without a second domain effect');
select is((select result->>'stockEffectCode' from late_results where kind='INSPECT'),'SELLABLE_INBOUND','late receipt SELLABLE inspection uses the existing inbound contract');
select is((select count(*) from inventory.stock_transactions transaction join operations.return_inspections inspection on inspection.transaction_id=transaction.id where inspection.return_id=(select return_id from late_fixture) and transaction.transaction_type_code='RETURN_SELLABLE_INBOUND'),1::bigint,'late receipt SELLABLE creates exactly one inbound transaction');
select is((select count(*) from operations.return_stock_batches batch join operations.return_receipt_lines receipt_line on receipt_line.id=batch.receipt_line_id where receipt_line.receipt_id=(select id from operations.return_receipts where receipt_ref='057-LATE-RECEIPT') and batch.product_id='30000000-0000-4000-8000-000000000001'::uuid),1::bigint,'late receipt SELLABLE preserves receipt-to-new-RETURN-batch provenance');
select is((select count(*) from inventory.stock_ledger_entries entry join operations.return_inspections inspection on inspection.transaction_id=entry.transaction_id where inspection.return_id=(select return_id from late_fixture) and entry.product_id='30000000-0000-4000-8000-000000000002'::uuid),0::bigint,'late receipt DAMAGED creates no ledger movement');
select is((select damaged_qty from api.return_items where return_item_id=(select product_b_return_item_id from late_fixture)),3::bigint,'late receipt DAMAGED quantity remains condition-only audit data');
select is((select count(*) from operations.return_late_arrival_lines allocation join operations.return_receipt_lines receipt_line on receipt_line.organization_id=allocation.organization_id and receipt_line.late_arrival_line_id=allocation.id where allocation.late_arrival_id=(select (result->>'lateArrivalId')::uuid from late_results where kind='LATE') and receipt_line.stock_effect_code='NONE'),3::bigint,'each late-arrival allocation has one typed stock-neutral receipt line');
select is((select jsonb_agg(jsonb_build_object('productId',product_id,'pendingArrival',pending_arrival_qty,'pendingInspection',pending_inspection_qty) order by product_id) from api.return_items where return_id=(select return_id from late_fixture)),jsonb_build_array(jsonb_build_object('productId','30000000-0000-4000-8000-000000000001'::uuid,'pendingArrival',0,'pendingInspection',0),jsonb_build_object('productId','30000000-0000-4000-8000-000000000002'::uuid,'pendingArrival',0,'pendingInspection',0)),'safe return-item projection exposes corrected pending-arrival and pending-inspection quantities');
select is((select count(*) from reconciliation.find_return_late_arrival_consistency_mismatches('00000000-0000-4000-8000-000000000001'::uuid)),0::bigint,'late-arrival append-only correction, receipt linkage, and projection reconciliation are consistent');
select set_config('request.jwt.claim.sub','720d8ca5-3f95-4a20-8063-d24981ad551d',true); select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claims','{"sub":"720d8ca5-3f95-4a20-8063-d24981ad551d","role":"authenticated"}',true); set local role authenticated;
select ok((select count(*) from pg_class view_class join pg_namespace view_schema on view_schema.oid=view_class.relnamespace where view_schema.nspname='api' and view_class.relname in ('return_late_arrivals','return_late_arrival_lines','return_late_arrival_claim_links') and view_class.reloptions @> array['security_invoker=true'])=3 and (select count(*) from api.return_late_arrivals where organization_id='00000000-0000-4000-8000-000000000001'::uuid and late_arrival_id=(select (result->>'lateArrivalId')::uuid from late_results where kind='LATE'))=1 and (select count(*) from api.return_late_arrival_lines where organization_id='00000000-0000-4000-8000-000000000001'::uuid and late_arrival_id=(select (result->>'lateArrivalId')::uuid from late_results where kind='LATE'))=3 and (select count(*) from api.return_late_arrival_claim_links where organization_id='00000000-0000-4000-8000-000000000001'::uuid and late_arrival_id=(select (result->>'lateArrivalId')::uuid from late_results where kind='LATE'))=1,'security-invoker late-arrival views expose the exact current-organization header, allocation, and claim-link rows');
reset role;

select * from finish();

rollback;
