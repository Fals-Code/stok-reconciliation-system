begin;

create extension if not exists pgtap with schema extensions;

select plan(44);

-- 1-8: contract and security surface
select has_schema('operations');
select has_table('operations'::name, 'receipts'::name);
select has_table('operations'::name, 'receipt_lines'::name);
select has_view('api'::name, 'receipts'::name);
select has_view('api'::name, 'receipt_lines'::name);
select function_returns(
  'api',
  'post_receipt',
  array['uuid', 'text', 'text', 'timestamptz', 'jsonb', 'text', 'jsonb']::text[],
  'jsonb'
);
select policies_are(
  'operations',
  'receipts',
  array['receipts_read_current_org']
);
select policies_are(
  'operations',
  'receipt_lines',
  array['receipt_lines_read_current_org']
);

create temp table receipt_test_result (
  result jsonb not null
) on commit drop;

insert into receipt_test_result (result)
select api.post_receipt(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-RECEIPT-001',
  'MAKLON-TEST-001',
  '2026-07-16 10:00:00+07'::timestamptz,
  jsonb_build_array(
    jsonb_build_object(
      'productId', '30000000-0000-4000-8000-000000000001',
      'batchId', '40000000-0000-4000-8000-000000000001',
      'quantity', 7,
      'sourceLineRef', 'LINE-1'
    ),
    jsonb_build_object(
      'productId', '30000000-0000-4000-8000-000000000002',
      'batchId', '40000000-0000-4000-8000-000000000003',
      'quantity', 3,
      'sourceLineRef', 'LINE-2'
    )
  ),
  'Penerimaan maklon untuk pgTAP.',
  '{"test": true, "fixture": "receipt-posting"}'::jsonb
);

-- 9-29: successful posting and snapshots
select is(
  (select result ->> 'status' from receipt_test_result),
  'POSTED',
  'receipt response is posted'
);
select is(
  (select result ->> 'lineCount' from receipt_test_result),
  '2',
  'receipt response contains two lines'
);
select is(
  (select result ->> 'totalQuantity' from receipt_test_result),
  '10',
  'receipt response contains total quantity'
);
select is(
  (
    select count(*)
    from operations.receipts
    where organization_id = '00000000-0000-4000-8000-000000000001'::uuid
      and source_ref = 'MAKLON-TEST-001'
  ),
  1::bigint,
  'one receipt header is stored'
);
select is(
  (
    select count(*)
    from operations.receipt_lines line
    join operations.receipts receipt on receipt.id = line.receipt_id
    where receipt.source_ref = 'MAKLON-TEST-001'
  ),
  2::bigint,
  'two receipt lines are stored'
);
select is(
  (
    select transaction.transaction_type_code
    from inventory.stock_transactions transaction
    where transaction.source_ref_snapshot = 'MAKLON-TEST-001'
  ),
  'RECEIPT',
  'receipt creates a receipt stock transaction'
);
select is(
  (
    select transaction.reason_code_snapshot
    from inventory.stock_transactions transaction
    where transaction.source_ref_snapshot = 'MAKLON-TEST-001'
  ),
  'MAKLON_RECEIPT',
  'receipt snapshots the maklon reason'
);
select is(
  (
    select transaction.channel_code_snapshot
    from inventory.stock_transactions transaction
    where transaction.source_ref_snapshot = 'MAKLON-TEST-001'
  ),
  'MANUAL',
  'receipt snapshots the manual channel'
);
select is(
  (
    select transaction.source_id::text
    from inventory.stock_transactions transaction
    where transaction.source_ref_snapshot = 'MAKLON-TEST-001'
  ),
  (
    select receipt.id::text
    from operations.receipts receipt
    where receipt.source_ref = 'MAKLON-TEST-001'
  ),
  'transaction source points to the receipt'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'MAKLON-TEST-001'
  ),
  2::bigint,
  'receipt creates two ledger entries'
);
select is(
  (
    select sum(entry.quantity_delta)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'MAKLON-TEST-001'
  ),
  10::numeric,
  'ledger quantity equals receipt quantity'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'MAKLON-TEST-001'
      and entry.bucket_code = 'SELLABLE'
  ),
  2::bigint,
  'all receipt entries increase sellable stock'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'MAKLON-TEST-001'
      and entry.entry_role_code = 'EXTERNAL_IN'
  ),
  2::bigint,
  'all receipt entries are external inbound'
);
select is(
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
      and balance.batch_id = '40000000-0000-4000-8000-000000000001'::uuid
  ),
  12::bigint,
  'serum batch balance increases from 5 to 12'
);
select is(
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
      and balance.batch_id = '40000000-0000-4000-8000-000000000003'::uuid
  ),
  18::bigint,
  'cleanser batch balance increases from 15 to 18'
);
select is(
  (
    select position.sellable_qty
    from inventory.stock_product_positions position
    where position.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  32::bigint,
  'serum product position increases from 25 to 32'
);
select is(
  (
    select position.sellable_qty
    from inventory.stock_product_positions position
    where position.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id = '30000000-0000-4000-8000-000000000002'::uuid
  ),
  18::bigint,
  'cleanser product position increases from 15 to 18'
);
select is(
  (
    select count(*)
    from operations.receipt_lines line
    join catalog.products product
      on product.id = line.product_id
     and product.organization_id = line.organization_id
    join catalog.product_batches batch
      on batch.id = line.batch_id
     and batch.organization_id = line.organization_id
     and batch.product_id = line.product_id
    where line.receipt_id = (
      select receipt.id
      from operations.receipts receipt
      where receipt.source_ref = 'MAKLON-TEST-001'
    )
      and line.product_sku_snapshot = product.sku
      and line.batch_code_snapshot = batch.batch_code
      and line.expiry_date_snapshot = batch.expiry_date
  ),
  2::bigint,
  'receipt lines preserve master-data snapshots'
);
select is(
  (
    select command.status_code
    from inventory.idempotency_commands command
    where command.scope = 'POST_RECEIPT'
      and command.key = 'PGTAP-RECEIPT-001'
  ),
  'SUCCEEDED',
  'idempotency command succeeds'
);
select is(
  (
    select command.result_transaction_id::text
    from inventory.idempotency_commands command
    where command.scope = 'POST_RECEIPT'
      and command.key = 'PGTAP-RECEIPT-001'
  ),
  (select result ->> 'transactionId' from receipt_test_result),
  'idempotency result points to the stock transaction'
);
select is(
  (
    select receipt.transaction_id::text
    from operations.receipts receipt
    where receipt.source_ref = 'MAKLON-TEST-001'
  ),
  (select result ->> 'transactionId' from receipt_test_result),
  'receipt points to the response transaction'
);

create temp table receipt_duplicate_result (
  result jsonb not null
) on commit drop;

insert into receipt_duplicate_result (result)
select api.post_receipt(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-RECEIPT-001',
  'MAKLON-TEST-001',
  '2026-07-16 10:00:00+07'::timestamptz,
  jsonb_build_array(
    jsonb_build_object(
      'productId', '30000000-0000-4000-8000-000000000001',
      'batchId', '40000000-0000-4000-8000-000000000001',
      'quantity', 7,
      'sourceLineRef', 'LINE-1'
    ),
    jsonb_build_object(
      'productId', '30000000-0000-4000-8000-000000000002',
      'batchId', '40000000-0000-4000-8000-000000000003',
      'quantity', 3,
      'sourceLineRef', 'LINE-2'
    )
  ),
  'Penerimaan maklon untuk pgTAP.',
  '{"test": true, "fixture": "receipt-posting"}'::jsonb
);

-- 30-33: idempotent replay
select is(
  (select result from receipt_duplicate_result),
  (select result from receipt_test_result),
  'same idempotency key and hash returns the stored response'
);
select is(
  (
    select count(*)
    from operations.receipts
    where source_ref = 'MAKLON-TEST-001'
  ),
  1::bigint,
  'idempotent replay does not duplicate the receipt'
);
select is(
  (
    select count(*)
    from inventory.stock_transactions
    where source_ref_snapshot = 'MAKLON-TEST-001'
  ),
  1::bigint,
  'idempotent replay does not duplicate the transaction'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'MAKLON-TEST-001'
  ),
  2::bigint,
  'idempotent replay does not duplicate ledger entries'
);

-- 34: same key with a different hash is rejected
select throws_ok(
  $sql$
    select api.post_receipt(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-RECEIPT-001',
      'MAKLON-TEST-001',
      '2026-07-16 10:00:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000001',
          'batchId', '40000000-0000-4000-8000-000000000001',
          'quantity', 8,
          'sourceLineRef', 'LINE-1'
        )
      ),
      'Penerimaan maklon untuk pgTAP.',
      '{"test": true, "fixture": "receipt-posting"}'::jsonb
    )
  $sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'same idempotency key cannot be reused for a different request'
);

-- 35-36: source reference is a second duplicate barrier
select throws_ok(
  $sql$
    select api.post_receipt(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-RECEIPT-SOURCE-DUPLICATE',
      'MAKLON-TEST-001',
      '2026-07-16 10:00:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000003',
          'batchId', '40000000-0000-4000-8000-000000000004',
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'RECEIPT_SOURCE_ALREADY_POSTED',
  'same source reference cannot create a second receipt'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_RECEIPT'
      and key = 'PGTAP-RECEIPT-SOURCE-DUPLICATE'
  ),
  0::bigint,
  'rejected duplicate source leaves no idempotency record'
);

-- 37-39: any line failure rolls back the entire command
select throws_ok(
  $sql$
    select api.post_receipt(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-RECEIPT-INVALID-MASTER',
      'MAKLON-TEST-INVALID-MASTER',
      '2026-07-16 10:00:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000001',
          'batchId', '49999999-9999-4999-8999-999999999999',
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'RECEIPT_LINE_MASTER_NOT_FOUND',
  'unknown batch rejects the receipt'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_RECEIPT'
      and key = 'PGTAP-RECEIPT-INVALID-MASTER'
  ),
  0::bigint,
  'failed receipt rolls back its idempotency command'
);
select is(
  (
    select count(*)
    from operations.receipts
    where source_ref = 'MAKLON-TEST-INVALID-MASTER'
  ),
  0::bigint,
  'failed receipt rolls back its receipt header'
);

-- 40-42: posted records are immutable and direct ledger insertion is forbidden
select throws_ok(
  $sql$
    update operations.receipts
    set note = 'mutated'
    where source_ref = 'MAKLON-TEST-001'
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'posted receipts cannot be updated'
);
select throws_ok(
  $sql$
    update inventory.stock_ledger_entries
    set source_line_ref = 'mutated'
    where transaction_id = (
      select transaction.id
      from inventory.stock_transactions transaction
      where transaction.source_ref_snapshot = 'MAKLON-TEST-001'
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'receipt ledger entries cannot be updated'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'inventory.stock_ledger_entries',
    'INSERT'
  ),
  'authenticated users cannot insert ledger entries directly'
);

-- 43-44: duplicate batch lines are rejected before any domain effect
select throws_ok(
  $sql$
    select api.post_receipt(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-RECEIPT-DUPLICATE-BATCH',
      'MAKLON-TEST-DUPLICATE-BATCH',
      '2026-07-16 10:00:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000001',
          'batchId', '40000000-0000-4000-8000-000000000001',
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        ),
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000001',
          'batchId', '40000000-0000-4000-8000-000000000001',
          'quantity', 2,
          'sourceLineRef', 'LINE-2'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'RECEIPT_DUPLICATE_BATCH_LINE',
  'one receipt cannot repeat the same batch'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_RECEIPT'
      and key = 'PGTAP-RECEIPT-DUPLICATE-BATCH'
  ),
  0::bigint,
  'duplicate batch validation leaves no idempotency record'
);

select * from finish();
rollback;
