begin;

create extension if not exists pgtap with schema extensions;

select plan(92);

-- 1-21: return contract and security surface
select has_table('operations'::name, 'returns'::name);
select has_table('operations'::name, 'return_items'::name);
select has_table('operations'::name, 'return_events'::name);
select has_table('operations'::name, 'return_event_lines'::name);
select has_table('operations'::name, 'return_receipts'::name);
select has_table('operations'::name, 'return_receipt_lines'::name);
select has_table('operations'::name, 'return_inspections'::name);
select has_table('operations'::name, 'return_inspection_allocations'::name);
select has_view('api'::name, 'returns'::name);
select has_view('api'::name, 'return_items'::name);
select has_view('api'::name, 'return_events'::name);
select has_view('api'::name, 'return_receipt_lines'::name);
select has_view('api'::name, 'return_inspection_allocations'::name);
select function_returns(
  'api',
  'create_expected_return',
  array[
    'uuid', 'text', 'text', 'text', 'text',
    'timestamptz', 'jsonb', 'text', 'text', 'jsonb'
  ]::text[],
  'jsonb'
);
select function_returns(
  'api',
  'mark_return_lost',
  array[
    'uuid', 'text', 'text', 'text',
    'timestamptz', 'jsonb', 'text', 'jsonb'
  ]::text[],
  'jsonb'
);
select function_returns(
  'api',
  'confirm_return_receipt',
  array[
    'uuid', 'text', 'text', 'text',
    'timestamptz', 'jsonb', 'text', 'jsonb'
  ]::text[],
  'jsonb'
);
select function_returns(
  'api',
  'inspect_return',
  array[
    'uuid', 'text', 'text', 'text',
    'timestamptz', 'jsonb', 'text', 'jsonb'
  ]::text[],
  'jsonb'
);
select policies_are(
  'operations',
  'returns',
  array['returns_read_current_org']
);
select policies_are(
  'operations',
  'return_items',
  array['return_items_read_current_org']
);
select ok(
  not has_table_privilege('authenticated', 'operations.returns', 'INSERT'),
  'authenticated users cannot insert return headers directly'
);
select ok(
  not has_table_privilege('authenticated', 'inventory.stock_ledger_entries', 'INSERT'),
  'authenticated users cannot insert return ledger effects directly'
);

create temp table return_test_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temp table return_stock_snapshots (
  stage text primary key,
  sellable_qty bigint not null,
  quarantine_qty bigint not null,
  damaged_qty bigint not null,
  reserved_qty bigint not null,
  transaction_count bigint not null,
  ledger_count bigint not null
) on commit drop;

-- Arrange a fully shipped marketplace order with one serum line.
insert into return_test_results (kind, result)
select
  'RESERVE_MAIN',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-MKT-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'RET-MKT-EVT-RESERVE-001',
    'RET-ORDER-001',
    '2026-07-17 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 4,
        'sourceLineRef', 'RET-ITEM-SER-001'
      )
    ),
    'Reserve serum for return lifecycle test.',
    '{"test": true, "fixture": "return-lifecycle"}'::jsonb
  );

insert into return_test_results (kind, result)
select
  'SHIP_MAIN',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-MKT-SHIP-001',
    'SHOPEE',
    'SHIP',
    'RET-MKT-EVT-SHIP-001',
    'RET-ORDER-001',
    '2026-07-17 09:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 4,
        'sourceLineRef', 'RET-ITEM-SER-001'
      )
    ),
    'Ship serum for return lifecycle test.',
    '{"test": true, "fixture": "return-lifecycle"}'::jsonb
  );

-- 22-26: shipped fixture is physically posted and fully consumes reservation
select is(
  (select result ->> 'status' from return_test_results where kind = 'RESERVE_MAIN'),
  'APPLIED',
  'main reserve is applied'
);
select is(
  (select result ->> 'status' from return_test_results where kind = 'SHIP_MAIN'),
  'APPLIED',
  'main shipment is applied'
);
select is(
  (
    select count(*)
    from operations.marketplace_ship_allocations allocation
    join operations.marketplace_events event on event.id = allocation.event_id
    where event.external_event_ref = 'RET-MKT-EVT-SHIP-001'
  ),
  1::bigint,
  'main shipment has one FEFO allocation'
);
select is(
  (
    select sellable_qty
    from inventory.stock_product_positions
    where organization_id = '00000000-0000-4000-8000-000000000001'::uuid
      and product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  21::bigint,
  'shipment removes four serum units from sellable stock'
);
select is(
  (
    select reserved_qty
    from inventory.stock_product_positions
    where organization_id = '00000000-0000-4000-8000-000000000001'::uuid
      and product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  0::bigint,
  'shipment consumes the serum reservation'
);

insert into return_stock_snapshots
select
  'POST_SHIP',
  position.sellable_qty,
  position.quarantine_qty,
  position.damaged_qty,
  position.reserved_qty,
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries)
from inventory.stock_product_positions position
where position.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id = '30000000-0000-4000-8000-000000000001'::uuid;

insert into return_test_results (kind, result)
select
  'EXPECTED_MAIN',
  api.create_expected_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-EXPECTED-001',
    'SHOPEE',
    'RET-RETURN-001',
    'RET-ORDER-001',
    '2026-07-17 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 4,
        'sourceLineRef', 'RET-ITEM-SER-001'
      )
    ),
    'RETURN_REQUESTED',
    'Expected marketplace return.',
    '{"test": true, "fixture": "return-lifecycle"}'::jsonb
  );

insert into return_stock_snapshots
select
  'POST_EXPECTED',
  position.sellable_qty,
  position.quarantine_qty,
  position.damaged_qty,
  position.reserved_qty,
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries)
from inventory.stock_product_positions position
where position.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id = '30000000-0000-4000-8000-000000000001'::uuid;

-- 27-40: expected return is informational, idempotent, and quantity-capped
select is(
  (select result ->> 'status' from return_test_results where kind = 'EXPECTED_MAIN'),
  'EXPECTED',
  'expected return response is expected'
);
select is(
  (
    select count(*)
    from operations.returns
    where external_return_ref = 'RET-RETURN-001'
  ),
  1::bigint,
  'one return header is created'
);
select is(
  (
    select expected_qty
    from api.returns
    where external_return_ref = 'RET-RETURN-001'
  ),
  4::numeric,
  'return header aggregates four expected units'
);
select is(
  (
    select count(*)
    from operations.return_events
    where return_id = (
      select id from operations.returns where external_return_ref = 'RET-RETURN-001'
    )
      and event_type_code = 'EXPECTED'
      and transaction_id is null
  ),
  1::bigint,
  'expected event has no stock transaction'
);
select is(
  (select transaction_count from return_stock_snapshots where stage = 'POST_EXPECTED'),
  (select transaction_count from return_stock_snapshots where stage = 'POST_SHIP'),
  'expected return creates no stock transaction'
);
select is(
  (select ledger_count from return_stock_snapshots where stage = 'POST_EXPECTED'),
  (select ledger_count from return_stock_snapshots where stage = 'POST_SHIP'),
  'expected return creates no ledger entry'
);
select is(
  (select sellable_qty from return_stock_snapshots where stage = 'POST_EXPECTED'),
  (select sellable_qty from return_stock_snapshots where stage = 'POST_SHIP'),
  'expected return does not change sellable stock'
);
select is(
  (select quarantine_qty from return_stock_snapshots where stage = 'POST_EXPECTED'),
  (select quarantine_qty from return_stock_snapshots where stage = 'POST_SHIP'),
  'expected return does not change quarantine stock'
);
select is(
  (select damaged_qty from return_stock_snapshots where stage = 'POST_EXPECTED'),
  (select damaged_qty from return_stock_snapshots where stage = 'POST_SHIP'),
  'expected return does not change damaged stock'
);
select is(
  api.create_expected_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-EXPECTED-001',
    'SHOPEE',
    'RET-RETURN-001',
    'RET-ORDER-001',
    '2026-07-17 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 4,
        'sourceLineRef', 'RET-ITEM-SER-001'
      )
    ),
    'RETURN_REQUESTED',
    'Expected marketplace return.',
    '{"test": true, "fixture": "return-lifecycle"}'::jsonb
  ),
  (select result from return_test_results where kind = 'EXPECTED_MAIN'),
  'expected return replay returns original response'
);
select is(
  (
    select count(*)
    from operations.return_events
    where external_event_ref = 'EXPECTED:RET-RETURN-001'
  ),
  1::bigint,
  'expected replay creates no duplicate event'
);
select throws_ok(
  $sql$
    select api.create_expected_return(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-RETURN-EXPECTED-OVER',
      'SHOPEE',
      'RET-RETURN-OVER',
      'RET-ORDER-001',
      '2026-07-17 10:05:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000001',
          'quantity', 1,
          'sourceLineRef', 'RET-ITEM-SER-001'
        )
      ),
      'RETURN_REQUESTED',
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'RETURN_QUANTITY_EXCEEDS_SHIPPED',
  'expected quantity cannot exceed valid shipment quantity'
);
select is(
  (
    select count(*)
    from operations.returns
    where external_return_ref = 'RET-RETURN-OVER'
  ),
  0::bigint,
  'rejected over-return creates no header'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'CREATE_EXPECTED_RETURN'
      and key = 'PGTAP-RETURN-EXPECTED-OVER'
  ),
  0::bigint,
  'rejected over-return rolls back idempotency command'
);

insert into return_test_results (kind, result)
select
  'RECEIPT_MAIN',
  api.confirm_return_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-RECEIPT-001',
    'RET-RETURN-001',
    'RET-RECEIPT-001',
    '2026-07-17 11:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header on return_header.id = item.return_id
          where return_header.external_return_ref = 'RET-RETURN-001'
        ),
        'marketplaceShipAllocationId',
        (
          select allocation.id::text
          from operations.marketplace_ship_allocations allocation
          join operations.marketplace_events event on event.id = allocation.event_id
          where event.external_event_ref = 'RET-MKT-EVT-SHIP-001'
        ),
        'quantity', 3,
        'sourceLineRef', 'RET-RECEIPT-LINE-001'
      )
    ),
    'Physical return received.',
    '{"test": true, "fixture": "return-lifecycle"}'::jsonb
  );

insert into return_stock_snapshots
select
  'POST_RECEIPT',
  position.sellable_qty,
  position.quarantine_qty,
  position.damaged_qty,
  position.reserved_qty,
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries)
from inventory.stock_product_positions position
where position.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id = '30000000-0000-4000-8000-000000000001'::uuid;

-- 41-49: physical receipt records arrival without changing stock
select is(
  (select result ->> 'status' from return_test_results where kind = 'RECEIPT_MAIN'),
  'PARTIALLY_RECEIVED',
  'partial physical receipt derives partially received status'
);
select is(
  (
    select
      line.batch_identity_verified
      and line.source_batch_id = allocation.batch_id
    from api.return_receipt_lines line
    join operations.marketplace_ship_allocations allocation
      on allocation.id = line.marketplace_ship_allocation_id
    where line.receipt_ref = 'RET-RECEIPT-001'
  ),
  true,
  'receipt preserves verified outbound batch provenance'
);
select is(
  (select quarantine_qty from return_stock_snapshots where stage = 'POST_RECEIPT'),
  (select quarantine_qty from return_stock_snapshots where stage = 'POST_EXPECTED'),
  'physical receipt does not create quarantine stock'
);
select is(
  (select sellable_qty from return_stock_snapshots where stage = 'POST_RECEIPT'),
  (select sellable_qty from return_stock_snapshots where stage = 'POST_EXPECTED'),
  'physical receipt does not restore sellable stock'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'RET-RECEIPT-001'
  ),
  0::bigint,
  'physical receipt writes no ledger entry'
);
select is(
  (
    select
      receipt.stock_effect_code || ':' ||
      (receipt.transaction_id is null)::text
    from operations.return_receipts receipt
    where receipt.receipt_ref = 'RET-RECEIPT-001'
  ),
  'NONE:true',
  'physical receipt explicitly records no stock transaction'
);
select is(
  api.confirm_return_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-RECEIPT-001',
    'RET-RETURN-001',
    'RET-RECEIPT-001',
    '2026-07-17 11:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header
            on return_header.id = item.return_id
          where return_header.external_return_ref = 'RET-RETURN-001'
        ),
        'marketplaceShipAllocationId',
        (
          select allocation.id::text
          from operations.marketplace_ship_allocations allocation
          join operations.marketplace_events event
            on event.id = allocation.event_id
          where event.external_event_ref = 'RET-MKT-EVT-SHIP-001'
        ),
        'quantity', 3,
        'sourceLineRef', 'RET-RECEIPT-LINE-001'
      )
    ),
    'Physical return received.',
    '{"test": true, "fixture": "return-lifecycle"}'::jsonb
  ),
  (select result from return_test_results where kind = 'RECEIPT_MAIN'),
  'receipt replay returns original response'
);
select is(
  (
    select count(*)
    from operations.return_receipts
    where receipt_ref = 'RET-RECEIPT-001'
  ),
  1::bigint,
  'receipt replay creates no duplicate receipt'
);
select is(
  (select ledger_count from return_stock_snapshots where stage = 'POST_RECEIPT'),
  (select ledger_count from return_stock_snapshots where stage = 'POST_EXPECTED'),
  'receipt replay leaves ledger count unchanged'
);

insert into return_test_results (kind, result)
select
  'INSPECTION_MAIN',
  api.inspect_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-INSPECT-001',
    'RET-RETURN-001',
    'RET-INSPECTION-001',
    '2026-07-17 12:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'receiptLineId',
        (
          select line.id::text
          from operations.return_receipt_lines line
          join operations.return_receipts receipt on receipt.id = line.receipt_id
          where receipt.receipt_ref = 'RET-RECEIPT-001'
        ),
        'sellableQuantity', 2,
        'damagedQuantity', 1,
        'sourceLineRef', 'RET-INSPECTION-LINE-001'
      )
    ),
    'Inspect returned serum.',
    '{"test": true, "fixture": "return-lifecycle"}'::jsonb
  );

insert into return_stock_snapshots
select
  'POST_INSPECTION',
  position.sellable_qty,
  position.quarantine_qty,
  position.damaged_qty,
  position.reserved_qty,
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries)
from inventory.stock_product_positions position
where position.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id = '30000000-0000-4000-8000-000000000001'::uuid;

-- 50-61: inspection posts only sellable quantity into a new return batch
select is(
  (select result ->> 'status' from return_test_results where kind = 'INSPECTION_MAIN'),
  'PARTIALLY_INSPECTED',
  'inspection with pending arrival derives partially inspected status'
);
select is(
  (
    select (result ->> 'allocationCount')::bigint
    from return_test_results
    where kind = 'INSPECTION_MAIN'
  ),
  2::bigint,
  'mixed inspection records sellable and damaged condition allocations'
);
select is(
  (
    select sum(entry.quantity_delta)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'RET-INSPECTION-001'
  ),
  2::numeric,
  'inspection ledger contains only sellable inbound quantity'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'RET-INSPECTION-001'
  ),
  1::bigint,
  'mixed inspection writes one sellable inbound ledger entry'
);
select is(
  (select quarantine_qty from return_stock_snapshots where stage = 'POST_INSPECTION'),
  (select quarantine_qty from return_stock_snapshots where stage = 'POST_RECEIPT'),
  'inspection does not create or consume quarantine stock'
);
select is(
  (select sellable_qty from return_stock_snapshots where stage = 'POST_INSPECTION'),
  (select sellable_qty + 2 from return_stock_snapshots where stage = 'POST_RECEIPT'),
  'inspection adds only sellable quantity to stock'
);
select is(
  (select damaged_qty from return_stock_snapshots where stage = 'POST_INSPECTION'),
  (select damaged_qty from return_stock_snapshots where stage = 'POST_RECEIPT'),
  'damaged return remains audit data without damaged stock'
);
select is(
  (
    select pending_inspection_qty
    from api.return_items
    where return_id = (
      select id
      from operations.returns
      where external_return_ref = 'RET-RETURN-001'
    )
  ),
  0::bigint,
  'main return item has no received quantity pending inspection'
);
select is(
  api.inspect_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-INSPECT-001',
    'RET-RETURN-001',
    'RET-INSPECTION-001',
    '2026-07-17 12:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'receiptLineId',
        (
          select line.id::text
          from operations.return_receipt_lines line
          join operations.return_receipts receipt
            on receipt.id = line.receipt_id
          where receipt.receipt_ref = 'RET-RECEIPT-001'
        ),
        'sellableQuantity', 2,
        'damagedQuantity', 1,
        'sourceLineRef', 'RET-INSPECTION-LINE-001'
      )
    ),
    'Inspect returned serum.',
    '{"test": true, "fixture": "return-lifecycle"}'::jsonb
  ),
  (select result from return_test_results where kind = 'INSPECTION_MAIN'),
  'inspection replay returns original response'
);
select is(
  (
    select count(*)
    from operations.return_inspections
    where inspection_ref = 'RET-INSPECTION-001'
  ),
  1::bigint,
  'inspection replay creates no duplicate inspection'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'RET-INSPECTION-001'
  ),
  1::bigint,
  'inspection replay creates no duplicate sellable ledger entry'
);
select is(
  (
    select count(*)
    from operations.return_stock_batches provenance
    join catalog.product_batches return_batch
      on return_batch.organization_id = provenance.organization_id
     and return_batch.product_id = provenance.product_id
     and return_batch.id = provenance.batch_id
    join inventory.stock_batch_balances balance
      on balance.organization_id = provenance.organization_id
     and balance.batch_id = provenance.batch_id
    where provenance.return_id = (
      select id
      from operations.returns
      where external_return_ref = 'RET-RETURN-001'
    )
      and return_batch.batch_kind_code = 'RETURN'
      and return_batch.id <> provenance.source_batch_id
      and balance.sellable_qty = 2
  ),
  1::bigint,
  'sellable return uses one new return-marked batch'
);

insert into return_test_results (kind, result)
select
  'LOST_MAIN',
  api.mark_return_lost(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-LOST-001',
    'RET-RETURN-001',
    'RET-LOST-001',
    '2026-07-17 13:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header on return_header.id = item.return_id
          where return_header.external_return_ref = 'RET-RETURN-001'
        ),
        'quantity', 1,
        'sourceLineRef', 'RET-LOST-LINE-001'
      )
    ),
    'One expected unit was lost in transit.',
    '{"test": true, "fixture": "return-lifecycle"}'::jsonb
  );

insert into return_stock_snapshots
select
  'POST_LOST',
  position.sellable_qty,
  position.quarantine_qty,
  position.damaged_qty,
  position.reserved_qty,
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries)
from inventory.stock_product_positions position
where position.organization_id = '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id = '30000000-0000-4000-8000-000000000001'::uuid;

-- 62-76: lost closes accounting without stock movement
select is(
  (select result ->> 'status' from return_test_results where kind = 'LOST_MAIN'),
  'COMPLETED_MIXED',
  'lost remainder completes the mixed return'
);
select is(
  (select expected_qty from api.returns where external_return_ref = 'RET-RETURN-001'),
  4::numeric,
  'final return keeps four expected units'
);
select is(
  (select received_qty from api.returns where external_return_ref = 'RET-RETURN-001'),
  3::numeric,
  'final return records three physically received units'
);
select is(
  (select sellable_qty from api.returns where external_return_ref = 'RET-RETURN-001'),
  2::numeric,
  'final return records two sellable units'
);
select is(
  (select damaged_qty from api.returns where external_return_ref = 'RET-RETURN-001'),
  1::numeric,
  'final return records one damaged unit'
);
select is(
  (select lost_qty from api.returns where external_return_ref = 'RET-RETURN-001'),
  1::numeric,
  'final return records one lost unit'
);
select is(
  (select pending_arrival_qty from api.returns where external_return_ref = 'RET-RETURN-001'),
  0::numeric,
  'final return has no pending arrival'
);
select is(
  (select pending_inspection_qty from api.returns where external_return_ref = 'RET-RETURN-001'),
  0::numeric,
  'final return has no pending inspection'
);
select is(
  (select outcome_code from api.returns where external_return_ref = 'RET-RETURN-001'),
  'MIXED',
  'final return outcome is mixed'
);
select is(
  (
    select count(*)
    from operations.return_events
    where external_event_ref = 'RET-LOST-001'
      and event_type_code = 'LOST'
      and transaction_id is null
  ),
  1::bigint,
  'lost event has no stock transaction'
);
select is(
  (select ledger_count from return_stock_snapshots where stage = 'POST_LOST'),
  (select ledger_count from return_stock_snapshots where stage = 'POST_INSPECTION'),
  'lost event creates no ledger movement'
);
select is(
  api.mark_return_lost(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-LOST-001',
    'RET-RETURN-001',
    'RET-LOST-001',
    '2026-07-17 13:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header on return_header.id = item.return_id
          where return_header.external_return_ref = 'RET-RETURN-001'
        ),
        'quantity', 1,
        'sourceLineRef', 'RET-LOST-LINE-001'
      )
    ),
    'One expected unit was lost in transit.',
    '{"test": true, "fixture": "return-lifecycle"}'::jsonb
  ),
  (select result from return_test_results where kind = 'LOST_MAIN'),
  'lost replay returns original response'
);
select is(
  (
    select count(*)
    from operations.return_events
    where external_event_ref = 'RET-LOST-001'
  ),
  1::bigint,
  'lost replay creates no duplicate event'
);
select is(
  (
    select
      expected_qty =
      pending_arrival_qty + pending_inspection_qty + sellable_qty + damaged_qty + lost_qty
    from api.returns
    where external_return_ref = 'RET-RETURN-001'
  ),
  true,
  'final return satisfies quantity accounting invariant'
);
select throws_ok(
  $sql$
    update operations.return_events
    set note = 'mutated'
    where external_event_ref = 'RET-LOST-001'
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'return events are append-only'
);

-- Arrange a second shipped order for an unidentified physical return batch.
insert into return_test_results (kind, result)
select
  'RESERVE_UNKNOWN',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-MKT-RESERVE-UNKNOWN',
    'SHOPEE',
    'RESERVE',
    'RET-MKT-EVT-RESERVE-UNKNOWN',
    'RET-ORDER-UNKNOWN',
    '2026-07-18 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 2,
        'sourceLineRef', 'RET-ITEM-SER-UNKNOWN'
      )
    ),
    null,
    '{"test": true, "fixture": "return-unidentified"}'::jsonb
  );

insert into return_test_results (kind, result)
select
  'SHIP_UNKNOWN',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-MKT-SHIP-UNKNOWN',
    'SHOPEE',
    'SHIP',
    'RET-MKT-EVT-SHIP-UNKNOWN',
    'RET-ORDER-UNKNOWN',
    '2026-07-18 09:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 2,
        'sourceLineRef', 'RET-ITEM-SER-UNKNOWN'
      )
    ),
    null,
    '{"test": true, "fixture": "return-unidentified"}'::jsonb
  );

insert into return_test_results (kind, result)
select
  'EXPECTED_UNKNOWN',
  api.create_expected_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-EXPECTED-UNKNOWN',
    'SHOPEE',
    'RET-RETURN-UNKNOWN',
    'RET-ORDER-UNKNOWN',
    '2026-07-18 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 1,
        'sourceLineRef', 'RET-ITEM-SER-UNKNOWN'
      )
    ),
    'RETURN_REQUESTED',
    null,
    '{"test": true, "fixture": "return-unidentified"}'::jsonb
  );

insert into return_test_results (kind, result)
select
  'RECEIPT_UNKNOWN',
  api.confirm_return_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-RECEIPT-UNKNOWN',
    'RET-RETURN-UNKNOWN',
    'RET-RECEIPT-UNKNOWN',
    '2026-07-18 11:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header on return_header.id = item.return_id
          where return_header.external_return_ref = 'RET-RETURN-UNKNOWN'
        ),
        'quantity', 1,
        'sourceLineRef', 'RET-RECEIPT-LINE-UNKNOWN'
      )
    ),
    'Batch identity unavailable at physical receipt.',
    '{"test": true, "fixture": "return-unidentified"}'::jsonb
  );

-- 77-92: unidentified receipt stays stock-neutral and cannot become sellable
select is(
  (select result ->> 'status' from return_test_results where kind = 'RESERVE_UNKNOWN'),
  'APPLIED',
  'unknown-batch fixture reserve is applied'
);
select is(
  (select result ->> 'status' from return_test_results where kind = 'SHIP_UNKNOWN'),
  'APPLIED',
  'unknown-batch fixture shipment is applied'
);
select is(
  (select result ->> 'status' from return_test_results where kind = 'EXPECTED_UNKNOWN'),
  'EXPECTED',
  'unknown-batch expected return is created'
);
select is(
  (select result ->> 'status' from return_test_results where kind = 'RECEIPT_UNKNOWN'),
  'RECEIVED_PENDING_INSPECTION',
  'fully received unknown batch awaits inspection'
);
select is(
  (
    select batch_identity_verified
    from api.return_receipt_lines
    where receipt_ref = 'RET-RECEIPT-UNKNOWN'
  ),
  false,
  'receipt without shipment allocation is not batch verified'
);
select is(
  (
    select batch_id is null
    from api.return_receipt_lines
    where receipt_ref = 'RET-RECEIPT-UNKNOWN'
  ),
  true,
  'unidentified receipt does not fabricate a destination batch'
);
select is(
  (
    select
      line.stock_effect_code || ':' ||
      (line.ledger_entry_id is null)::text
    from api.return_receipt_lines line
    where line.receipt_ref = 'RET-RECEIPT-UNKNOWN'
  ),
  'NONE:true',
  'unidentified receipt records arrival without stock effect'
);
select throws_ok(
  $sql$
    select api.inspect_return(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-RETURN-INSPECT-UNKNOWN-SELLABLE',
      'RET-RETURN-UNKNOWN',
      'RET-INSPECTION-UNKNOWN-SELLABLE',
      '2026-07-18 12:00:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'receiptLineId',
          (
            select line.id::text
            from operations.return_receipt_lines line
            join operations.return_receipts receipt
              on receipt.id = line.receipt_id
            where receipt.receipt_ref = 'RET-RECEIPT-UNKNOWN'
          ),
          'sellableQuantity', 1,
          'damagedQuantity', 0,
          'sourceLineRef', 'RET-INSPECTION-LINE-UNKNOWN-SELLABLE'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'RETURN_BATCH_IDENTITY_REQUIRED_FOR_SELLABLE',
  'unidentified return cannot become sellable'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'INSPECT_RETURN'
      and key = 'PGTAP-RETURN-INSPECT-UNKNOWN-SELLABLE'
  ),
  0::bigint,
  'failed sellable inspection rolls back idempotency command'
);
select is(
  (
    select count(*)
    from operations.return_stock_batches provenance
    where provenance.receipt_line_id = (
      select line.id
      from operations.return_receipt_lines line
      join operations.return_receipts receipt
        on receipt.id = line.receipt_id
      where receipt.receipt_ref = 'RET-RECEIPT-UNKNOWN'
    )
  ),
  0::bigint,
  'failed unidentified sellable inspection creates no return batch'
);

insert into return_test_results (kind, result)
select
  'INSPECTION_UNKNOWN_DAMAGED',
  api.inspect_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RETURN-INSPECT-UNKNOWN-DAMAGED',
    'RET-RETURN-UNKNOWN',
    'RET-INSPECTION-UNKNOWN-DAMAGED',
    '2026-07-18 12:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'receiptLineId',
        (
          select line.id::text
          from operations.return_receipt_lines line
          join operations.return_receipts receipt
            on receipt.id = line.receipt_id
          where receipt.receipt_ref = 'RET-RECEIPT-UNKNOWN'
        ),
        'sellableQuantity', 0,
        'damagedQuantity', 1,
        'sourceLineRef', 'RET-INSPECTION-LINE-UNKNOWN-DAMAGED'
      )
    ),
    'Classify unidentified return as damaged.',
    '{"test": true, "fixture": "return-unidentified"}'::jsonb
  );

select is(
  (select result ->> 'status' from return_test_results where kind = 'INSPECTION_UNKNOWN_DAMAGED'),
  'COMPLETED_DAMAGED',
  'unidentified return may complete as damaged'
);
select is(
  (select damaged_qty from api.returns where external_return_ref = 'RET-RETURN-UNKNOWN'),
  1::numeric,
  'unknown-batch return records one damaged unit'
);
select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.source_ref_snapshot in (
      'RET-RECEIPT-UNKNOWN',
      'RET-INSPECTION-UNKNOWN-DAMAGED'
    )
  ),
  0::bigint,
  'unknown receipt and damaged inspection create no stock transaction'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot in (
      'RET-RECEIPT-UNKNOWN',
      'RET-INSPECTION-UNKNOWN-DAMAGED'
    )
  ),
  0::bigint,
  'unknown receipt and damaged inspection create no ledger entry'
);
select is(
  (
    select
      allocation.condition_code || ':' ||
      allocation.stock_effect_code || ':' ||
      (allocation.destination_bucket_code is null)::text
    from api.return_inspection_allocations allocation
    where allocation.inspection_ref =
      'RET-INSPECTION-UNKNOWN-DAMAGED'
  ),
  'DAMAGED:NONE:true',
  'damaged inspection remains condition data without stock destination'
);
select is(
  (
    select
      expected_qty =
      pending_arrival_qty +
      pending_inspection_qty +
      sellable_qty +
      damaged_qty +
      lost_qty
    from api.returns
    where external_return_ref = 'RET-RETURN-UNKNOWN'
  ),
  true,
  'unknown-batch return satisfies quantity accounting invariant'
);

select * from finish();

rollback;
