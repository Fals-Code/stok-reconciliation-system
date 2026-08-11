begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into app.organizations(id,code,name,timezone,is_active,created_at) values
('00000000-0000-4000-8000-000000000068','PGTAP_INLINE_068','pgTAP Inline 068','Asia/Jakarta',true,'2026-08-10 08:00:00+07');

insert into auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous) values
('00000000-0000-0000-0000-000000000000','96800000-0000-4000-8000-000000000001','authenticated','authenticated','pgtap.inline.068@glowlab.invalid','2026-08-10 08:00:00+07','{"provider":"email","providers":["email"]}'::jsonb,'{}','2026-08-10 08:00:00+07','2026-08-10 08:00:00+07',false,false);

insert into app.user_profiles(user_id,organization_id,display_name,employee_code,role_code,is_active) values
('96800000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000068','pgTAP Inline Admin','PGTAP-INLINE-068','ADMIN',true);

select set_config('request.jwt.claim.sub','96800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims',jsonb_build_object('sub','96800000-0000-4000-8000-000000000001','role','authenticated','email','pgtap.inline.068@glowlab.invalid')::text,true);
set local role authenticated;

-- Create fixture Product and retain its authoritative generated identity
create temp table inline_product_result(result jsonb not null) on commit drop;
do $fixture$
declare
  v_result jsonb;
begin
  if exists (select 1 from information_schema.columns where table_schema = 'catalog' and table_name = 'products' and column_name = 'size_ml') then
    execute 'select api.create_product($1,$2,$3,$4,$5,$6,$7)'
      into v_result using '00000000-0000-4000-8000-000000000068'::uuid, '068-P1', 'Inline Test Product', 1000, 'UNIT', null::text, null::text;
  else
    execute 'select api.create_product($1,$2,$3,$4,$5,$6,$7)'
      into v_result using '00000000-0000-4000-8000-000000000068'::uuid, '068-P1', 'SKU INLINE 068', 'Inline Test Product', 'UNIT', null::text, null::text;
  end if;
  insert into inline_product_result values (v_result);
end
$fixture$;

create temp table inline_results(kind text primary key, result jsonb not null) on commit drop;

-- Test 1: Post receipt with NEW batch inline
insert into inline_results select 'RCV_NEW_BATCH', api.post_receipt(
  '00000000-0000-4000-8000-000000000068',
  '068-KEY-1',
  'REF-INLINE-1',
  '2026-08-10 10:00:00+07',
  jsonb_build_array(
    jsonb_build_object(
      'productId', (select (result->>'productId')::uuid from inline_product_result limit 1),
      'batchCode', 'BATCH-INLINE-001',
      'expiryDate', '2028-12-31',
      'manufacturedDate', '2026-08-01',
      'quantity', 25,
      'sourceLineRef', 'LINE-1'
    )
  ),
  'Testing inline batch creation'
);

select is((select result->>'status' from inline_results where kind='RCV_NEW_BATCH'), 'POSTED', 'Receipt with new inline batch posted successfully');
select is((select count(*) from catalog.product_batches where organization_id='00000000-0000-4000-8000-000000000068' and batch_code='BATCH-INLINE-001'), 1::bigint, 'New batch was created in catalog.product_batches');
select is((select sellable_qty from inventory.stock_product_positions where organization_id='00000000-0000-4000-8000-000000000068'), 25::bigint, 'Stock position updated to 25 units');

-- Test 2: Failure after first inline batch insert rolls back the whole Receipt
create temp table inline_rollback_baseline on commit drop as
select
  (select count(*) from operations.receipts where organization_id='00000000-0000-4000-8000-000000000068') as receipt_count,
  (select count(*) from inventory.stock_transactions where organization_id='00000000-0000-4000-8000-000000000068') as transaction_count,
  (select count(*) from inventory.stock_ledger_entries where organization_id='00000000-0000-4000-8000-000000000068') as ledger_count,
  (select sellable_qty from inventory.stock_product_positions where organization_id='00000000-0000-4000-8000-000000000068' and product_id=(select (result->>'productId')::uuid from inline_product_result limit 1)) as sellable_qty;

select throws_ok(
  $sql$
    select api.post_receipt(
      '00000000-0000-4000-8000-000000000068',
      '068-KEY-FAIL',
      'REF-INLINE-FAIL',
      '2026-08-10 11:00:00+07',
      jsonb_build_array(
        jsonb_build_object(
          'productId', (select (result->>'productId')::uuid from inline_product_result limit 1),
          'batchCode', 'AA-ROLLBACK-FIRST',
          'expiryDate', '2028-12-31',
          'quantity', 10,
          'sourceLineRef', 'LINE-FIRST'
        ),
        jsonb_build_object(
          'productId', '00000000-0000-4000-8000-000000000999',
          'batchCode', 'ZZ-ROLLBACK-FAIL',
          'expiryDate', '2028-12-31',
          'quantity', 1,
          'sourceLineRef', 'LINE-FAIL'
        )
      )
    )
  $sql$,
  'P0001',
  'RECEIPT_LINE_MASTER_NOT_FOUND',
  'Failure after creating the first inline batch rolls back the entire Receipt'
);

select is((select count(*) from catalog.product_batches where organization_id='00000000-0000-4000-8000-000000000068' and batch_code='AA-ROLLBACK-FIRST'), 0::bigint, 'Inline batch created before the later failure is rolled back');
select is((select count(*) from operations.receipts where organization_id='00000000-0000-4000-8000-000000000068'), (select receipt_count from inline_rollback_baseline), 'Failed Receipt leaves no Receipt header');
select is((select count(*) from inventory.stock_transactions where organization_id='00000000-0000-4000-8000-000000000068'), (select transaction_count from inline_rollback_baseline), 'Failed Receipt leaves no stock transaction');
select is((select count(*) from inventory.stock_ledger_entries where organization_id='00000000-0000-4000-8000-000000000068'), (select ledger_count from inline_rollback_baseline), 'Failed Receipt leaves no ledger entry');
select is((select sellable_qty from inventory.stock_product_positions where organization_id='00000000-0000-4000-8000-000000000068' and product_id=(select (result->>'productId')::uuid from inline_product_result limit 1)), (select sellable_qty from inline_rollback_baseline), 'Failed Receipt leaves product projection unchanged');

-- Test 3: Invalid Manufactured Date > Expiry Date
select throws_ok(
  $sql$
    select api.post_receipt(
      '00000000-0000-4000-8000-000000000068',
      '068-KEY-BAD-DATE',
      'REF-INLINE-BAD-DATE',
      '2026-08-10 11:00:00+07',
      jsonb_build_array(
        jsonb_build_object(
          'productId', (select (result->>'productId')::uuid from inline_product_result limit 1),
          'batchCode', 'BATCH-BAD-DATES',
          'expiryDate', '2027-01-01',
          'manufacturedDate', '2027-06-01', -- Manufactured after expiry
          'quantity', 10,
          'sourceLineRef', 'LINE-BAD-DATE'
        )
      )
    )
  $sql$,
  'P0001',
  'INVALID_BATCH_DATE_RANGE',
  'Manufactured date > Expiry date is rejected'
);

rollback;
