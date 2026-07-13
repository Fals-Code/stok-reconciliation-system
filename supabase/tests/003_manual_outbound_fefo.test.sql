begin;

create extension if not exists pgtap with schema extensions;

select plan(61);

-- 1-12: contract and security surface
select has_table('operations'::name, 'manual_outbounds'::name);
select has_table('operations'::name, 'manual_outbound_lines'::name);
select has_table('operations'::name, 'manual_outbound_allocations'::name);
select has_view('api'::name, 'manual_outbounds'::name);
select has_view('api'::name, 'manual_outbound_lines'::name);
select has_view('api'::name, 'manual_outbound_allocations'::name);
select function_returns(
  'api',
  'post_manual_outbound',
  array['uuid', 'text', 'text', 'timestamptz', 'text', 'jsonb', 'text', 'jsonb']::text[],
  'jsonb'
);
select policies_are(
  'operations',
  'manual_outbounds',
  array['manual_outbounds_read_current_org']
);
select policies_are(
  'operations',
  'manual_outbound_lines',
  array['manual_outbound_lines_read_current_org']
);
select policies_are(
  'operations',
  'manual_outbound_allocations',
  array['manual_outbound_allocations_read_current_org']
);
select ok(
  not has_table_privilege('authenticated', 'operations.manual_outbounds', 'INSERT'),
  'authenticated users cannot insert outbound headers directly'
);
select ok(
  not has_table_privilege('authenticated', 'inventory.stock_ledger_entries', 'INSERT'),
  'authenticated users cannot insert ledger entries directly'
);

create temp table manual_outbound_test_result (
  result jsonb not null
) on commit drop;

insert into manual_outbound_test_result (result)
select api.post_manual_outbound(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP-OUTBOUND-001',
  'MANUAL-TEST-001',
  '2026-07-16 11:00:00+07'::timestamptz,
  'OFFLINE_SALE',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '30000000-0000-4000-8000-000000000001',
      'quantity', 8,
      'sourceLineRef', 'LINE-1'
    )
  ),
  'Penjualan offline untuk pengujian FEFO.',
  '{"test": true, "fixture": "manual-outbound-fefo"}'::jsonb
);

-- 13-39: successful posting, FEFO split, snapshots, ledger, and projections
select is(
  (select result ->> 'status' from manual_outbound_test_result),
  'POSTED',
  'outbound response is posted'
);
select is(
  (select result ->> 'lineCount' from manual_outbound_test_result),
  '1',
  'outbound response contains one product line'
);
select is(
  (select result ->> 'allocationCount' from manual_outbound_test_result),
  '2',
  'outbound response contains two batch allocations'
);
select is(
  (select result ->> 'totalQuantity' from manual_outbound_test_result),
  '8',
  'outbound response contains total quantity'
);
select is(
  (select result ->> 'reasonCode' from manual_outbound_test_result),
  'OFFLINE_SALE',
  'outbound response contains the normalized reason code'
);
select is(
  (select result ->> 'expirySafetyBufferDays' from manual_outbound_test_result),
  '0',
  'outbound response snapshots the safety buffer'
);
select is(
  (
    select count(*)
    from operations.manual_outbounds
    where organization_id = '00000000-0000-4000-8000-000000000001'::uuid
      and source_ref = 'MANUAL-TEST-001'
  ),
  1::bigint,
  'one outbound header is persisted'
);
select is(
  (
    select count(*)
    from operations.manual_outbound_lines line
    join operations.manual_outbounds outbound on outbound.id = line.outbound_id
    where outbound.source_ref = 'MANUAL-TEST-001'
  ),
  1::bigint,
  'one outbound product line is persisted'
);
select is(
  (
    select count(*)
    from operations.manual_outbound_allocations allocation
    join operations.manual_outbounds outbound on outbound.id = allocation.outbound_id
    where outbound.source_ref = 'MANUAL-TEST-001'
  ),
  2::bigint,
  'two FEFO allocations are persisted'
);
select is(
  (
    select sum(allocation.quantity_allocated)
    from operations.manual_outbound_allocations allocation
    join operations.manual_outbounds outbound on outbound.id = allocation.outbound_id
    where outbound.source_ref = 'MANUAL-TEST-001'
  ),
  8::numeric,
  'allocation quantity equals requested quantity'
);
select is(
  (
    select allocation.batch_code_snapshot
    from operations.manual_outbound_allocations allocation
    join operations.manual_outbounds outbound on outbound.id = allocation.outbound_id
    where outbound.source_ref = 'MANUAL-TEST-001'
      and allocation.allocation_no = 1
  ),
  'SER-2608-A',
  'first allocation uses the earliest expiry batch'
);
select is(
  (
    select allocation.quantity_allocated
    from operations.manual_outbound_allocations allocation
    join operations.manual_outbounds outbound on outbound.id = allocation.outbound_id
    where outbound.source_ref = 'MANUAL-TEST-001'
      and allocation.allocation_no = 1
  ),
  5::bigint,
  'first FEFO batch is exhausted'
);
select is(
  (
    select allocation.batch_code_snapshot
    from operations.manual_outbound_allocations allocation
    join operations.manual_outbounds outbound on outbound.id = allocation.outbound_id
    where outbound.source_ref = 'MANUAL-TEST-001'
      and allocation.allocation_no = 2
  ),
  'SER-2612-B',
  'second allocation uses the next FEFO batch'
);
select is(
  (
    select allocation.quantity_allocated
    from operations.manual_outbound_allocations allocation
    join operations.manual_outbounds outbound on outbound.id = allocation.outbound_id
    where outbound.source_ref = 'MANUAL-TEST-001'
      and allocation.allocation_no = 2
  ),
  3::bigint,
  'second FEFO batch supplies the remaining quantity'
);
select is(
  (
    select transaction.transaction_type_code
    from inventory.stock_transactions transaction
    where transaction.source_ref_snapshot = 'MANUAL-TEST-001'
  ),
  'MANUAL_OUTBOUND',
  'stock transaction is typed as manual outbound'
);
select is(
  (
    select transaction.reason_code_snapshot
    from inventory.stock_transactions transaction
    where transaction.source_ref_snapshot = 'MANUAL-TEST-001'
  ),
  'OFFLINE_SALE',
  'stock transaction snapshots the reason'
);
select is(
  (
    select transaction.channel_code_snapshot
    from inventory.stock_transactions transaction
    where transaction.source_ref_snapshot = 'MANUAL-TEST-001'
  ),
  'MANUAL',
  'stock transaction snapshots the manual channel'
);
select is(
  (
    select transaction.source_type_code
    from inventory.stock_transactions transaction
    where transaction.source_ref_snapshot = 'MANUAL-TEST-001'
  ),
  'MANUAL_OUTBOUND',
  'stock transaction snapshots the source type'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'MANUAL-TEST-001'
  ),
  2::bigint,
  'two ledger entries represent the split allocation'
);
select is(
  (
    select sum(entry.quantity_delta)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'MANUAL-TEST-001'
  ),
  (-8)::numeric,
  'ledger records the full physical outbound quantity'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'MANUAL-TEST-001'
      and entry.bucket_code = 'SELLABLE'
      and entry.entry_role_code = 'EXTERNAL_OUT'
  ),
  2::bigint,
  'ledger entries use sellable external-out semantics'
);
select is(
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.batch_id = '40000000-0000-4000-8000-000000000001'::uuid
  ),
  0::bigint,
  'earliest expiry batch balance becomes zero'
);
select is(
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.batch_id = '40000000-0000-4000-8000-000000000002'::uuid
  ),
  17::bigint,
  'second batch balance is reduced by the remainder'
);
select is(
  (
    select position.sellable_qty
    from inventory.stock_product_positions position
    where position.product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  17::bigint,
  'product sellable projection is reduced atomically'
);
select is(
  (
    select position.sellable_qty - position.reserved_qty
    from inventory.stock_product_positions position
    where position.product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  17::bigint,
  'product available quantity remains consistent'
);
select is(
  (
    select count(*)
    from operations.manual_outbound_allocations allocation
    join inventory.stock_ledger_entries entry on entry.id = allocation.ledger_entry_id
    join operations.manual_outbounds outbound on outbound.id = allocation.outbound_id
    where outbound.source_ref = 'MANUAL-TEST-001'
      and entry.batch_id = allocation.batch_id
      and -entry.quantity_delta = allocation.quantity_allocated
  ),
  2::bigint,
  'each allocation points to its matching ledger entry'
);
select is(
  (
    select command.status_code
    from inventory.idempotency_commands command
    where command.scope = 'POST_MANUAL_OUTBOUND'
      and command.key = 'PGTAP-OUTBOUND-001'
  ),
  'SUCCEEDED',
  'idempotency command is completed successfully'
);
select is(
  (
    select length(command.request_hash)
    from inventory.idempotency_commands command
    where command.scope = 'POST_MANUAL_OUTBOUND'
      and command.key = 'PGTAP-OUTBOUND-001'
  ),
  64,
  'idempotency command stores a SHA-256 request hash'
);

-- 40-42: replay returns the original response without another stock effect
select is(
  api.post_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-OUTBOUND-001',
    'MANUAL-TEST-001',
    '2026-07-16 11:00:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 8,
        'sourceLineRef', 'LINE-1'
      )
    ),
    'Penjualan offline untuk pengujian FEFO.',
    '{"test": true, "fixture": "manual-outbound-fefo"}'::jsonb
  ),
  (select result from manual_outbound_test_result),
  'idempotent replay returns the original response'
);
select is(
  (
    select count(*)
    from operations.manual_outbounds
    where source_ref = 'MANUAL-TEST-001'
  ),
  1::bigint,
  'idempotent replay creates no second outbound header'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'MANUAL-TEST-001'
  ),
  2::bigint,
  'idempotent replay creates no second ledger effect'
);

-- 43: same key with a different request is rejected
select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-OUTBOUND-001',
      'MANUAL-TEST-001',
      '2026-07-16 11:00:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000001',
          'quantity', 9,
          'sourceLineRef', 'LINE-1'
        )
      ),
      'Penjualan offline untuk pengujian FEFO.',
      '{"test": true, "fixture": "manual-outbound-fefo"}'::jsonb
    )
  $sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'same idempotency key cannot represent different input'
);

-- 44-45: a source reference cannot create a second domain effect
select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-OUTBOUND-SOURCE-DUPLICATE',
      'MANUAL-TEST-001',
      '2026-07-16 11:05:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000003',
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'OUTBOUND_SOURCE_ALREADY_POSTED',
  'same source reference cannot create a second outbound'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_MANUAL_OUTBOUND'
      and key = 'PGTAP-OUTBOUND-SOURCE-DUPLICATE'
  ),
  0::bigint,
  'rejected duplicate source leaves no idempotency record'
);

-- 46-48: insufficient available stock rolls back the whole command
select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-OUTBOUND-INSUFFICIENT',
      'MANUAL-TEST-INSUFFICIENT',
      '2026-07-16 11:10:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000003',
          'quantity', 20,
          'sourceLineRef', 'LINE-1'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'INSUFFICIENT_AVAILABLE_STOCK',
  'outbound above available stock is rejected'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_MANUAL_OUTBOUND'
      and key = 'PGTAP-OUTBOUND-INSUFFICIENT'
  ),
  0::bigint,
  'failed outbound rolls back its idempotency command'
);
select is(
  (
    select count(*)
    from operations.manual_outbounds
    where source_ref = 'MANUAL-TEST-INSUFFICIENT'
  ),
  0::bigint,
  'failed outbound rolls back its header'
);

-- 49-52: safety buffer can make otherwise available stock ineligible
update app.settings
set value = '200'::jsonb
where organization_id = '00000000-0000-4000-8000-000000000001'::uuid
  and key = 'expiry.safety_buffer_days'
  and effective_to is null;

select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-OUTBOUND-SAFETY-BUFFER',
      'MANUAL-TEST-SAFETY-BUFFER',
      '2026-07-16 11:15:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000002',
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'INSUFFICIENT_FEFO_STOCK',
  'safety buffer excludes batches too close to expiry'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_MANUAL_OUTBOUND'
      and key = 'PGTAP-OUTBOUND-SAFETY-BUFFER'
  ),
  0::bigint,
  'safety-buffer failure rolls back its idempotency command'
);
select is(
  (
    select count(*)
    from operations.manual_outbounds
    where source_ref = 'MANUAL-TEST-SAFETY-BUFFER'
  ),
  0::bigint,
  'safety-buffer failure rolls back its header'
);
select is(
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.batch_id = '40000000-0000-4000-8000-000000000003'::uuid
  ),
  15::bigint,
  'safety-buffer failure leaves batch stock unchanged'
);

update app.settings
set value = '0'::jsonb
where organization_id = '00000000-0000-4000-8000-000000000001'::uuid
  and key = 'expiry.safety_buffer_days'
  and effective_to is null;

-- 53-56: posted records and ledger remain immutable and protected
select throws_ok(
  $sql$
    update operations.manual_outbounds
    set note = 'mutated'
    where source_ref = 'MANUAL-TEST-001'
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'posted outbound headers cannot be updated'
);
select throws_ok(
  $sql$
    update operations.manual_outbound_allocations allocation
    set quantity_allocated = allocation.quantity_allocated + 1
    where allocation.outbound_id = (
      select outbound.id
      from operations.manual_outbounds outbound
      where outbound.source_ref = 'MANUAL-TEST-001'
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'posted FEFO allocations cannot be updated'
);
select throws_ok(
  $sql$
    update inventory.stock_ledger_entries
    set source_line_ref = 'mutated'
    where transaction_id = (
      select transaction.id
      from inventory.stock_transactions transaction
      where transaction.source_ref_snapshot = 'MANUAL-TEST-001'
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'outbound ledger entries cannot be updated'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'operations.manual_outbound_allocations',
    'INSERT'
  ),
  'authenticated users cannot insert FEFO allocations directly'
);

-- 57-58: duplicate product lines are rejected before any domain effect
select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-OUTBOUND-DUPLICATE-PRODUCT',
      'MANUAL-TEST-DUPLICATE-PRODUCT',
      '2026-07-16 11:20:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000003',
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        ),
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000003',
          'quantity', 1,
          'sourceLineRef', 'LINE-2'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'OUTBOUND_DUPLICATE_PRODUCT_LINE',
  'one outbound cannot repeat the same product'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_MANUAL_OUTBOUND'
      and key = 'PGTAP-OUTBOUND-DUPLICATE-PRODUCT'
  ),
  0::bigint,
  'duplicate product validation leaves no idempotency record'
);

-- 59-60: an unknown product rejects and rolls back the command
select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-OUTBOUND-UNKNOWN-PRODUCT',
      'MANUAL-TEST-UNKNOWN-PRODUCT',
      '2026-07-16 11:25:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '39999999-9999-4999-8999-999999999999',
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'OUTBOUND_PRODUCT_NOT_FOUND',
  'unknown product rejects the outbound'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_MANUAL_OUTBOUND'
      and key = 'PGTAP-OUTBOUND-UNKNOWN-PRODUCT'
  ),
  0::bigint,
  'unknown product failure rolls back its idempotency command'
);

select * from finish();
rollback;
