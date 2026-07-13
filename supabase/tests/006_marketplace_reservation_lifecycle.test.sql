begin;

create extension if not exists pgtap with schema extensions;

select plan(80);

-- 1-18: contract and security surface
select has_table('operations'::name, 'marketplace_orders'::name);
select has_table('operations'::name, 'marketplace_order_items'::name);
select has_table('operations'::name, 'marketplace_events'::name);
select has_table('operations'::name, 'marketplace_event_lines'::name);
select has_table('operations'::name, 'marketplace_ship_allocations'::name);
select has_view('api'::name, 'marketplace_orders'::name);
select has_view('api'::name, 'marketplace_reservations'::name);
select has_view('api'::name, 'marketplace_events'::name);
select has_view('api'::name, 'marketplace_ship_allocations'::name);
select function_returns(
  'api',
  'apply_marketplace_event',
  array[
    'uuid',
    'text',
    'text',
    'text',
    'text',
    'text',
    'timestamptz',
    'jsonb',
    'text',
    'jsonb'
  ]::text[],
  'jsonb'
);
select policies_are(
  'operations',
  'marketplace_orders',
  array['marketplace_orders_read_current_org']
);
select policies_are(
  'operations',
  'marketplace_order_items',
  array['marketplace_order_items_read_current_org']
);
select policies_are(
  'operations',
  'marketplace_events',
  array['marketplace_events_read_current_org']
);
select policies_are(
  'operations',
  'marketplace_event_lines',
  array['marketplace_event_lines_read_current_org']
);
select policies_are(
  'operations',
  'marketplace_ship_allocations',
  array['marketplace_ship_allocations_read_current_org']
);
select ok(
  not has_table_privilege('authenticated', 'operations.marketplace_orders', 'INSERT'),
  'authenticated users cannot insert marketplace orders directly'
);
select ok(
  not has_table_privilege('authenticated', 'inventory.stock_reservations', 'UPDATE'),
  'authenticated users cannot update reservations directly'
);
select ok(
  not has_table_privilege('authenticated', 'inventory.stock_ledger_entries', 'INSERT'),
  'authenticated users cannot insert marketplace ledger effects directly'
);

create temp table marketplace_test_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

insert into marketplace_test_results (kind, result)
select
  'RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-MKT-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'SHP-EVT-RESERVE-001',
    'SHP-ORDER-001',
    '2026-07-16 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 8,
        'sourceLineRef', 'ITEM-SER'
      ),
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000003',
        'quantity', 2,
        'sourceLineRef', 'ITEM-TNR'
      )
    ),
    'Reserve Shopee order for lifecycle test.',
    '{"test": true, "fixture": "marketplace-reservation"}'::jsonb
  );

-- 19-34: reserve affects only reservation projections
select is(
  (select result ->> 'status' from marketplace_test_results where kind = 'RESERVE'),
  'APPLIED',
  'reserve response is applied'
);
select is(
  (select result ->> 'eventType' from marketplace_test_results where kind = 'RESERVE'),
  'RESERVE',
  'reserve response snapshots event type'
);
select is(
  (select result ->> 'allocationCount' from marketplace_test_results where kind = 'RESERVE'),
  '0',
  'reserve creates no physical allocation'
);
select is(
  (
    select count(*)
    from operations.marketplace_orders
    where external_order_ref = 'SHP-ORDER-001'
  ),
  1::bigint,
  'one marketplace order is persisted'
);
select is(
  (
    select count(*)
    from operations.marketplace_order_items item
    join operations.marketplace_orders marketplace_order on marketplace_order.id = item.order_id
    where marketplace_order.external_order_ref = 'SHP-ORDER-001'
  ),
  2::bigint,
  'two canonical order items are persisted'
);
select is(
  (
    select count(*)
    from inventory.stock_reservations reservation
    join operations.marketplace_order_items item on item.reservation_id = reservation.id
    join operations.marketplace_orders marketplace_order on marketplace_order.id = item.order_id
    where marketplace_order.external_order_ref = 'SHP-ORDER-001'
  ),
  2::bigint,
  'two stock reservations are persisted'
);
select is(
  (
    select sum(reservation.reserved_qty)
    from inventory.stock_reservations reservation
    join operations.marketplace_order_items item on item.reservation_id = reservation.id
    join operations.marketplace_orders marketplace_order on marketplace_order.id = item.order_id
    where marketplace_order.external_order_ref = 'SHP-ORDER-001'
  ),
  10::numeric,
  'reservation quantity equals canonical order quantity'
);
select is(
  (
    select reserved_qty
    from inventory.stock_product_positions
    where product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  8::bigint,
  'serum reserved projection increases by eight'
);
select is(
  (
    select sellable_qty - reserved_qty
    from inventory.stock_product_positions
    where product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  17::bigint,
  'serum available decreases without physical outbound'
);
select is(
  (
    select reserved_qty
    from inventory.stock_product_positions
    where product_id = '30000000-0000-4000-8000-000000000003'::uuid
  ),
  2::bigint,
  'toner reserved projection increases by two'
);
select is(
  (
    select sellable_qty - reserved_qty
    from inventory.stock_product_positions
    where product_id = '30000000-0000-4000-8000-000000000003'::uuid
  ),
  10::bigint,
  'toner available decreases without physical outbound'
);
select is(
  (
    select count(*)
    from inventory.stock_transactions
    where source_ref_snapshot = 'SHP-ORDER-001'
  ),
  0::bigint,
  'reserve creates no stock transaction'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'SHP-ORDER-001'
  ),
  0::bigint,
  'reserve creates no physical ledger entry'
);
select is(
  (
    select status_code
    from operations.marketplace_orders
    where external_order_ref = 'SHP-ORDER-001'
  ),
  'RESERVED',
  'order status is reserved'
);
select is(
  (
    select count(*)
    from operations.marketplace_events
    where external_event_ref = 'SHP-EVT-RESERVE-001'
      and event_type_code = 'RESERVE'
  ),
  1::bigint,
  'reserve event is persisted once'
);
select is(
  (
    select status_code
    from inventory.idempotency_commands
    where scope = 'APPLY_MARKETPLACE_EVENT'
      and key = 'PGTAP-MKT-RESERVE-001'
  ),
  'SUCCEEDED',
  'reserve idempotency command succeeds'
);

-- 35-39: replay and available-stock protection
select is(
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-MKT-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'SHP-EVT-RESERVE-001',
    'SHP-ORDER-001',
    '2026-07-16 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 8,
        'sourceLineRef', 'ITEM-SER'
      ),
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000003',
        'quantity', 2,
        'sourceLineRef', 'ITEM-TNR'
      )
    ),
    'Reserve Shopee order for lifecycle test.',
    '{"test": true, "fixture": "marketplace-reservation"}'::jsonb
  ),
  (select result from marketplace_test_results where kind = 'RESERVE'),
  'reserve replay returns the original response'
);
select is(
  (
    select count(*)
    from operations.marketplace_events
    where external_event_ref = 'SHP-EVT-RESERVE-001'
  ),
  1::bigint,
  'reserve replay creates no duplicate event'
);
select is(
  (
    select reserved_qty
    from inventory.stock_product_positions
    where product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  8::bigint,
  'reserve replay creates no second projection effect'
);
select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MANUAL-AFTER-RESERVE',
      'MANUAL-AFTER-RESERVE',
      '2026-07-16 09:05:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000001',
          'quantity', 18,
          'sourceLineRef', 'LINE-1'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'INSUFFICIENT_AVAILABLE_STOCK',
  'manual outbound cannot spend marketplace-reserved stock'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_MANUAL_OUTBOUND'
      and key = 'PGTAP-MANUAL-AFTER-RESERVE'
  ),
  0::bigint,
  'failed manual outbound rolls back its idempotency command'
);

insert into marketplace_test_results (kind, result)
select
  'RELEASE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-MKT-RELEASE-001',
    'SHOPEE',
    'RELEASE',
    'SHP-EVT-RELEASE-001',
    'SHP-ORDER-001',
    '2026-07-16 09:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000003',
        'quantity', 2,
        'sourceLineRef', 'ITEM-TNR'
      )
    ),
    'Cancel toner line before shipment.',
    '{"test": true}'::jsonb
  );

-- 40-46: release returns available stock without ledger movement
select is(
  (select result ->> 'status' from marketplace_test_results where kind = 'RELEASE'),
  'APPLIED',
  'release response is applied'
);
select is(
  (
    select reservation.status_code
    from inventory.stock_reservations reservation
    join operations.marketplace_order_items item on item.reservation_id = reservation.id
    where item.external_item_ref = 'ITEM-TNR'
  ),
  'RELEASED',
  'fully released item closes its reservation'
);
select is(
  (
    select reserved_qty
    from inventory.stock_product_positions
    where product_id = '30000000-0000-4000-8000-000000000003'::uuid
  ),
  0::bigint,
  'release removes toner reserved projection'
);
select is(
  (
    select sellable_qty
    from inventory.stock_product_positions
    where product_id = '30000000-0000-4000-8000-000000000003'::uuid
  ),
  12::bigint,
  'release leaves toner physical sellable stock unchanged'
);
select is(
  (
    select status_code
    from operations.marketplace_orders
    where external_order_ref = 'SHP-ORDER-001'
  ),
  'PARTIALLY_CLOSED',
  'order remains open while another reservation is active'
);
select ok(
  (
    select transaction_id is null
    from operations.marketplace_events
    where external_event_ref = 'SHP-EVT-RELEASE-001'
  ),
  'release event has no stock transaction'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'SHP-ORDER-001'
  ),
  0::bigint,
  'release creates no physical ledger entry'
);

insert into marketplace_test_results (kind, result)
select
  'SHIP',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-MKT-SHIP-001',
    'SHOPEE',
    'SHIP',
    'SHP-EVT-SHIP-001',
    'SHP-ORDER-001',
    '2026-07-16 09:20:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 8,
        'sourceLineRef', 'ITEM-SER'
      )
    ),
    'Shopee SHIPPED physical outbound.',
    '{"test": true, "rawStatus": "SHIPPED"}'::jsonb
  );

-- 47-64: shipment consumes reservation and posts FEFO ledger
select is(
  (select result ->> 'status' from marketplace_test_results where kind = 'SHIP'),
  'APPLIED',
  'ship response is applied'
);
select is(
  (select result ->> 'allocationCount' from marketplace_test_results where kind = 'SHIP'),
  '2',
  'ship response contains two FEFO allocations'
);
select is(
  (
    select transaction_type_code
    from inventory.stock_transactions
    where source_ref_snapshot = 'SHP-ORDER-001'
  ),
  'MARKETPLACE_OUTBOUND',
  'shipment creates a marketplace outbound transaction'
);
select is(
  (
    select channel_code_snapshot
    from inventory.stock_transactions
    where source_ref_snapshot = 'SHP-ORDER-001'
  ),
  'SHOPEE',
  'shipment snapshots the marketplace channel'
);
select is(
  (
    select reason_code_snapshot
    from inventory.stock_transactions
    where source_ref_snapshot = 'SHP-ORDER-001'
  ),
  'MARKETPLACE_SALE',
  'shipment snapshots marketplace sale reason'
);
select is(
  (
    select count(*)
    from operations.marketplace_ship_allocations allocation
    join operations.marketplace_events marketplace_event on marketplace_event.id = allocation.event_id
    where marketplace_event.external_event_ref = 'SHP-EVT-SHIP-001'
  ),
  2::bigint,
  'two FEFO allocations are persisted'
);
select is(
  (
    select batch_code_snapshot
    from operations.marketplace_ship_allocations allocation
    join operations.marketplace_events marketplace_event on marketplace_event.id = allocation.event_id
    where marketplace_event.external_event_ref = 'SHP-EVT-SHIP-001'
      and allocation.allocation_no = 1
  ),
  'SER-2608-A',
  'shipment uses earliest expiry batch first'
);
select is(
  (
    select quantity_allocated
    from operations.marketplace_ship_allocations allocation
    join operations.marketplace_events marketplace_event on marketplace_event.id = allocation.event_id
    where marketplace_event.external_event_ref = 'SHP-EVT-SHIP-001'
      and allocation.allocation_no = 1
  ),
  5::bigint,
  'shipment exhausts five units from first FEFO batch'
);
select is(
  (
    select batch_code_snapshot
    from operations.marketplace_ship_allocations allocation
    join operations.marketplace_events marketplace_event on marketplace_event.id = allocation.event_id
    where marketplace_event.external_event_ref = 'SHP-EVT-SHIP-001'
      and allocation.allocation_no = 2
  ),
  'SER-2612-B',
  'shipment continues to second FEFO batch'
);
select is(
  (
    select quantity_allocated
    from operations.marketplace_ship_allocations allocation
    join operations.marketplace_events marketplace_event on marketplace_event.id = allocation.event_id
    where marketplace_event.external_event_ref = 'SHP-EVT-SHIP-001'
      and allocation.allocation_no = 2
  ),
  3::bigint,
  'shipment takes remaining three units from second batch'
);
select is(
  (
    select sum(entry.quantity_delta)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'SHP-ORDER-001'
  ),
  (-8)::numeric,
  'shipment ledger records eight physical units out'
);
select is(
  (
    select sellable_qty
    from inventory.stock_product_positions
    where product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  17::bigint,
  'shipment reduces serum physical sellable projection'
);
select is(
  (
    select reserved_qty
    from inventory.stock_product_positions
    where product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  0::bigint,
  'shipment consumes serum reservation projection'
);
select is(
  (
    select reservation.status_code
    from inventory.stock_reservations reservation
    join operations.marketplace_order_items item on item.reservation_id = reservation.id
    where item.external_item_ref = 'ITEM-SER'
  ),
  'CONSUMED',
  'shipped item closes as consumed'
);
select is(
  (
    select status_code
    from operations.marketplace_orders
    where external_order_ref = 'SHP-ORDER-001'
  ),
  'CLOSED_MIXED',
  'mixed shipped and released order closes distinctly'
);
select is(
  (
    select open_qty
    from api.marketplace_orders
    where external_order_ref = 'SHP-ORDER-001'
  ),
  0::numeric,
  'marketplace order view reports no open reservation'
);
select is(
  (
    select released_qty
    from api.marketplace_orders
    where external_order_ref = 'SHP-ORDER-001'
  ),
  2::numeric,
  'marketplace order view reports released quantity'
);
select is(
  (
    select shipped_qty
    from api.marketplace_orders
    where external_order_ref = 'SHP-ORDER-001'
  ),
  8::numeric,
  'marketplace order view reports shipped quantity'
);

-- 65-67: ship replay creates no second physical effect
select is(
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-MKT-SHIP-001',
    'SHOPEE',
    'SHIP',
    'SHP-EVT-SHIP-001',
    'SHP-ORDER-001',
    '2026-07-16 09:20:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 8,
        'sourceLineRef', 'ITEM-SER'
      )
    ),
    'Shopee SHIPPED physical outbound.',
    '{"test": true, "rawStatus": "SHIPPED"}'::jsonb
  ),
  (select result from marketplace_test_results where kind = 'SHIP'),
  'ship replay returns the original response'
);
select is(
  (
    select count(*)
    from operations.marketplace_events
    where external_event_ref = 'SHP-EVT-SHIP-001'
  ),
  1::bigint,
  'ship replay creates no duplicate event'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot = 'SHP-ORDER-001'
  ),
  2::bigint,
  'ship replay creates no second ledger effect'
);

-- 68-73: invalid and conflicting events roll back atomically
select throws_ok(
  $sql$
    select api.apply_marketplace_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MKT-SHIP-001',
      'SHOPEE',
      'SHIP',
      'SHP-EVT-SHIP-001',
      'SHP-ORDER-001',
      '2026-07-16 09:20:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000001',
          'quantity', 7,
          'sourceLineRef', 'ITEM-SER'
        )
      ),
      'Shopee SHIPPED physical outbound.',
      '{"test": true, "rawStatus": "SHIPPED"}'::jsonb
    )
  $sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'same idempotency key cannot represent different shipment input'
);
select throws_ok(
  $sql$
    select api.apply_marketplace_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MKT-DUPLICATE-EVENT',
      'SHOPEE',
      'RELEASE',
      'SHP-EVT-RESERVE-001',
      'SHP-ORDER-001',
      '2026-07-16 09:30:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000001',
          'quantity', 1,
          'sourceLineRef', 'ITEM-SER'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'MARKETPLACE_EVENT_ALREADY_APPLIED',
  'same external marketplace event cannot be applied twice'
);
select throws_ok(
  $sql$
    select api.apply_marketplace_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MKT-OVER-RESERVE',
      'TIKTOK_SHOP',
      'RESERVE',
      'TTS-EVT-OVER-RESERVE',
      'TTS-ORDER-OVER-RESERVE',
      '2026-07-16 10:00:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000002',
          'quantity', 999,
          'sourceLineRef', 'ITEM-CLN'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'INSUFFICIENT_AVAILABLE_STOCK',
  'reservation above available stock is rejected'
);
select is(
  (
    select count(*)
    from operations.marketplace_orders
    where external_order_ref = 'TTS-ORDER-OVER-RESERVE'
  ),
  0::bigint,
  'failed reservation rolls back its order header'
);
select throws_ok(
  $sql$
    select api.apply_marketplace_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MKT-OVER-RELEASE',
      'SHOPEE',
      'RELEASE',
      'SHP-EVT-OVER-RELEASE',
      'SHP-ORDER-001',
      '2026-07-16 10:10:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000003',
          'quantity', 1,
          'sourceLineRef', 'ITEM-TNR'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'MARKETPLACE_RESERVATION_EXCEEDED',
  'release cannot exceed the remaining reservation'
);
select throws_ok(
  $sql$
    select api.apply_marketplace_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MKT-INVALID-CHANNEL',
      'MANUAL',
      'RESERVE',
      'MANUAL-EVT-001',
      'MANUAL-ORDER-001',
      '2026-07-16 10:20:00+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId', '30000000-0000-4000-8000-000000000002',
          'quantity', 1,
          'sourceLineRef', 'ITEM-1'
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'MARKETPLACE_CHANNEL_NOT_ALLOWED',
  'non-marketplace channel cannot create marketplace reservations'
);

-- 74-80: immutability and final audit invariants
select throws_ok(
  $sql$
    update operations.marketplace_events
    set note = 'mutated'
    where external_event_ref = 'SHP-EVT-SHIP-001'
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'applied marketplace events are immutable'
);
select throws_ok(
  $sql$
    update operations.marketplace_ship_allocations allocation
    set quantity_allocated = allocation.quantity_allocated + 1
    where allocation.event_id = (
      select marketplace_event.id
      from operations.marketplace_events marketplace_event
      where marketplace_event.external_event_ref = 'SHP-EVT-SHIP-001'
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'marketplace FEFO allocations are immutable'
);
select is(
  (
    select count(*)
    from inventory.stock_reservations reservation
    join operations.marketplace_order_items item on item.reservation_id = reservation.id
    join operations.marketplace_orders marketplace_order on marketplace_order.id = item.order_id
    where marketplace_order.external_order_ref = 'SHP-ORDER-001'
      and reservation.consumed_qty + reservation.released_qty = reservation.reserved_qty
  ),
  2::bigint,
  'all closed order reservations balance exactly'
);
select is(
  (
    select sellable_qty - reserved_qty
    from inventory.stock_product_positions
    where product_id = '30000000-0000-4000-8000-000000000001'::uuid
  ),
  17::bigint,
  'serum available remains physically and logically consistent'
);
select ok(
  (
    select result_transaction_id is null
    from inventory.idempotency_commands
    where scope = 'APPLY_MARKETPLACE_EVENT'
      and key = 'PGTAP-MKT-RESERVE-001'
  ),
  'reserve idempotency result has no physical transaction'
);
select ok(
  (
    select result_transaction_id is not null
    from inventory.idempotency_commands
    where scope = 'APPLY_MARKETPLACE_EVENT'
      and key = 'PGTAP-MKT-SHIP-001'
  ),
  'ship idempotency result points to physical transaction'
);
select is(
  (
    select count(*)
    from operations.marketplace_events
    where (
      event_type_code = 'SHIP'
      and transaction_id is not null
    ) or (
      event_type_code in ('RESERVE', 'RELEASE')
      and transaction_id is null
    )
  ),
  3::bigint,
  'all applied events obey the physical transaction rule'
);

select * from finish();
rollback;
