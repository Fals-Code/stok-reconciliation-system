begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select function_returns(
  'api',
  'ship_marketplace_listing_event',
  array[
    'uuid',
    'text',
    'text',
    'text',
    'text',
    'text',
    'timestamp with time zone',
    'timestamp with time zone',
    'jsonb',
    'text',
    'jsonb',
    'jsonb',
    'integer'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'preview_marketplace_listing_cancellation',
  array[
    'uuid',
    'text',
    'text',
    'text',
    'text',
    'timestamp with time zone',
    'timestamp with time zone',
    'jsonb',
    'text',
    'jsonb',
    'jsonb',
    'integer'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'post_marketplace_listing_cancellation',
  array[
    'uuid',
    'text',
    'text',
    'text',
    'text',
    'text',
    'timestamp with time zone',
    'timestamp with time zone',
    'jsonb',
    'text',
    'boolean',
    'text',
    'jsonb',
    'jsonb',
    'integer'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'create_expected_marketplace_listing_return',
  array[
    'uuid',
    'text',
    'text',
    'text',
    'text',
    'text',
    'timestamp with time zone',
    'timestamp with time zone',
    'jsonb',
    'text',
    'jsonb',
    'jsonb',
    'integer'
  ]::text[],
  'jsonb'
);

select has_view(
  'api',
  'marketplace_listing_component_lifecycle',
  'listing component lifecycle read model exists'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'operations.resolve_marketplace_component_selection(uuid,text,text,jsonb,text)',
    'EXECUTE'
  ),
  'authenticated cannot call internal component resolver'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.ship_marketplace_listing_event(uuid,text,text,text,text,text,timestamp with time zone,timestamp with time zone,jsonb,text,jsonb,jsonb,integer)',
    'EXECUTE'
  ),
  'authenticated Admin may call normalized ship command'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.ship_marketplace_listing_event(uuid,text,text,text,text,text,timestamp with time zone,timestamp with time zone,jsonb,text,jsonb,jsonb,integer)',
    'EXECUTE'
  ),
  'anonymous users cannot call normalized ship command'
);

select is(
  (
    select count(*)
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'api'
      and procedure.proname in (
        'ship_marketplace_listing_event',
        'preview_marketplace_listing_cancellation',
        'post_marketplace_listing_cancellation',
        'create_expected_marketplace_listing_return'
      )
      and procedure.prosecdef
      and procedure.proconfig @> array[
        'search_path=pg_catalog, operations, api, extensions'
      ]::text[]
  ),
  4::bigint,
  'all public downstream wrappers have fixed search_path'
);

create temporary table downstream_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

insert into downstream_results (kind, result)
select
  'RESERVE',
  api.reserve_marketplace_listing_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-RESERVE-051',
    'SHOPEE',
    'SHP-EVT-LISTING-RESERVE-051',
    'SHP-ORDER-LISTING-051',
    'READY_TO_SHIP',
    '2026-07-22 10:00:00+07'::timestamptz,
    '2026-07-22 10:00:01+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'sourceLineRef', 'SRC-BUNDLE-051',
        'externalListingCode', 'SHP-BND-GLOW-01',
        'listingQuantity', 2,
        'sourceTitle', 'Glow Starter Bundle',
        'sourceSku', 'SHP-BND-GLOW-01',
        'rawLinePayload',
          jsonb_build_object('lineId', 'bundle-051')
      )
    ),
    'Reserve bundle for downstream lifecycle.',
    jsonb_build_object('event', 'reserve-051'),
    jsonb_build_object('fixture', 'downstream-051'),
    1
  );

create temporary table downstream_before as
select
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  )::bigint as transaction_count,
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  )::bigint as ledger_count;

select throws_ok(
  $sql$
    select api.ship_marketplace_listing_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-LISTING-SHIP-WRONG-STATUS-051',
      'SHOPEE',
      'SHP-EVT-LISTING-SHIP-WRONG-051',
      'SHP-ORDER-LISTING-051',
      'READY_TO_SHIP',
      '2026-07-22 10:05:00+07'::timestamptz,
      '2026-07-22 10:05:01+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'orderSourceLineRef', 'SRC-BUNDLE-051',
          'componentNo', 1,
          'quantity', 1
        )
      ),
      null,
      '{}'::jsonb,
      '{}'::jsonb,
      1
    )
  $sql$,
  'P0001',
  'MARKETPLACE_SOURCE_STATUS_NOT_SHIPPABLE',
  'Shopee stock cannot move before SHIPPED'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select transaction_count
    from downstream_before
  ),
  'blocked source status creates no stock transaction'
);

insert into downstream_results (kind, result)
select
  'SHIP',
  api.ship_marketplace_listing_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-SHIP-051',
    'SHOPEE',
    'SHP-EVT-LISTING-SHIP-051',
    'SHP-ORDER-LISTING-051',
    'SHIPPED',
    '2026-07-22 10:10:00+07'::timestamptz,
    '2026-07-22 10:10:02+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'orderSourceLineRef', 'SRC-BUNDLE-051',
        'componentNo', 1,
        'quantity', 2
      ),
      jsonb_build_object(
        'orderSourceLineRef', 'SRC-BUNDLE-051',
        'componentNo', 2,
        'quantity', 1
      )
    ),
    'Ship selected bundle components.',
    jsonb_build_object('event', 'ship-051'),
    jsonb_build_object('fixture', 'downstream-051'),
    1
  );

select is(
  (
    select result ->> 'status'
    from downstream_results
    where kind = 'SHIP'
  ),
  'APPLIED',
  'normalized component shipment is applied'
);

select is(
  (
    select (result ->> 'totalQuantity')::bigint
    from downstream_results
    where kind = 'SHIP'
  ),
  3::bigint,
  'shipment totals canonical component quantities'
);

select is(
  (
    select jsonb_array_length(result -> 'sourceComponents')
    from downstream_results
    where kind = 'SHIP'
  ),
  2,
  'shipment response exposes both source component selections'
);

select is(
  (
    select count(*)
    from operations.marketplace_event_lines event_line
    join operations.marketplace_source_line_components component
      on component.organization_id =
           event_line.organization_id
     and component.order_item_id =
           event_line.order_item_id
     and component.product_id = event_line.product_id
     and component.canonical_source_line_ref =
           event_line.source_line_ref
    where event_line.event_id = (
      select (result ->> 'eventId')::uuid
      from downstream_results
      where kind = 'SHIP'
    )
  ),
  2::bigint,
  'shipment event lines preserve exact canonical component linkage'
);

select is(
  (
    select coalesce(sum(entry.quantity_delta), 0)::bigint
    from inventory.stock_ledger_entries entry
    where entry.transaction_id = (
      select (result ->> 'transactionId')::uuid
      from downstream_results
      where kind = 'SHIP'
    )
  ),
  -3::bigint,
  'shipment ledger records only expanded unit products'
);

insert into downstream_results (kind, result)
select
  'SHIP_REPLAY',
  api.ship_marketplace_listing_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-SHIP-051',
    'SHOPEE',
    'SHP-EVT-LISTING-SHIP-051',
    'SHP-ORDER-LISTING-051',
    'SHIPPED',
    '2026-07-22 10:10:00+07'::timestamptz,
    '2026-07-22 10:10:02+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'orderSourceLineRef', 'SRC-BUNDLE-051',
        'componentNo', 1,
        'quantity', 2
      ),
      jsonb_build_object(
        'orderSourceLineRef', 'SRC-BUNDLE-051',
        'componentNo', 2,
        'quantity', 1
      )
    ),
    'Ship selected bundle components.',
    jsonb_build_object('event', 'ship-051'),
    jsonb_build_object('fixture', 'downstream-051'),
    1
  );

select is(
  (
    select result ->> 'eventId'
    from downstream_results
    where kind = 'SHIP_REPLAY'
  ),
  (
    select result ->> 'eventId'
    from downstream_results
    where kind = 'SHIP'
  ),
  'shipment replay returns the original event'
);

select throws_ok(
  $sql$
    select api.ship_marketplace_listing_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-LISTING-SHIP-051',
      'SHOPEE',
      'SHP-EVT-LISTING-SHIP-051',
      'SHP-ORDER-LISTING-051',
      'SHIPPED',
      '2026-07-22 10:10:00+07'::timestamptz,
      '2026-07-22 10:10:02+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'orderSourceLineRef', 'SRC-BUNDLE-051',
          'componentNo', 1,
          'quantity', 1
        )
      ),
      'Ship selected bundle components.',
      jsonb_build_object('event', 'ship-051'),
      jsonb_build_object('fixture', 'downstream-051'),
      1
    )
  $sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'changed component shipment payload conflicts with the same key'
);

insert into downstream_results (kind, result)
select
  'CANCEL_PREVIEW',
  api.preview_marketplace_listing_cancellation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'SHOPEE',
    'SHP-EVT-LISTING-CANCEL-051',
    'SHP-ORDER-LISTING-051',
    'CANCELLED_MIXED',
    '2026-07-22 10:20:00+07'::timestamptz,
    '2026-07-22 10:20:01+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'orderSourceLineRef', 'SRC-BUNDLE-051',
        'componentNo', 1,
        'phaseCode', 'PRE_SHIPMENT',
        'quantity', 1,
        'cancellationLineRef', 'CANCEL-051-PRE'
      ),
      jsonb_build_object(
        'orderSourceLineRef', 'SRC-BUNDLE-051',
        'componentNo', 1,
        'phaseCode', 'POST_SHIPMENT',
        'quantity', 1,
        'cancellationLineRef', 'CANCEL-051-POST'
      )
    ),
    'Cancel one open and one shipped serum.',
    jsonb_build_object('event', 'cancel-051'),
    jsonb_build_object('fixture', 'downstream-051'),
    1
  );

select is(
  (
    select result ->> 'eligible'
    from downstream_results
    where kind = 'CANCEL_PREVIEW'
  ),
  'true',
  'normalized mixed cancellation is eligible'
);

select is(
  (
    select (result ->> 'preShipmentQuantity')::bigint
    from downstream_results
    where kind = 'CANCEL_PREVIEW'
  ),
  1::bigint,
  'preview resolves one pre-shipment unit'
);

select is(
  (
    select (result ->> 'postShipmentQuantity')::bigint
    from downstream_results
    where kind = 'CANCEL_PREVIEW'
  ),
  1::bigint,
  'preview resolves one post-shipment unit'
);

insert into downstream_results (kind, result)
select
  'CANCEL_POST',
  api.post_marketplace_listing_cancellation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-CANCEL-POST-051',
    'SHOPEE',
    'SHP-EVT-LISTING-CANCEL-051',
    'SHP-ORDER-LISTING-051',
    'CANCELLED_MIXED',
    '2026-07-22 10:20:00+07'::timestamptz,
    '2026-07-22 10:20:01+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'orderSourceLineRef', 'SRC-BUNDLE-051',
        'componentNo', 1,
        'phaseCode', 'PRE_SHIPMENT',
        'quantity', 1,
        'cancellationLineRef', 'CANCEL-051-PRE'
      ),
      jsonb_build_object(
        'orderSourceLineRef', 'SRC-BUNDLE-051',
        'componentNo', 1,
        'phaseCode', 'POST_SHIPMENT',
        'quantity', 1,
        'cancellationLineRef', 'CANCEL-051-POST'
      )
    ),
    (
      select result ->> 'basisHash'
      from downstream_results
      where kind = 'CANCEL_PREVIEW'
    ),
    true,
    'Cancel one open and one shipped serum.',
    jsonb_build_object('event', 'cancel-051'),
    jsonb_build_object('fixture', 'downstream-051'),
    1
  );

select is(
  (
    select result ->> 'status'
    from downstream_results
    where kind = 'CANCEL_POST'
  ),
  'POSTED',
  'normalized cancellation posts through canonical lifecycle'
);

select is(
  (
    select count(*)
    from operations.marketplace_cancellation_applications application
    join operations.marketplace_cancellation_lines cancellation_line
      on cancellation_line.id =
           application.cancellation_line_id
    join operations.marketplace_cancellations cancellation
      on cancellation.id = cancellation_line.cancellation_id
    where cancellation.external_event_ref =
      'SHP-EVT-LISTING-CANCEL-051'
      and application.effect_code = 'PRE_SHIPMENT_RELEASE'
      and application.quantity_applied = 1
  ),
  1::bigint,
  'pre-shipment component cancellation releases its reservation'
);

select is(
  (
    select count(*)
    from operations.marketplace_cancellation_applications application
    join operations.marketplace_cancellation_lines cancellation_line
      on cancellation_line.id =
           application.cancellation_line_id
    join operations.marketplace_cancellations cancellation
      on cancellation.id = cancellation_line.cancellation_id
    where cancellation.external_event_ref =
      'SHP-EVT-LISTING-CANCEL-051'
      and application.effect_code = 'POST_SHIPMENT_REVERSAL'
      and application.quantity_applied = 1
  ),
  1::bigint,
  'post-shipment component cancellation uses exact reversal'
);

select is(
  (
    select coalesce(sum(entry.quantity_delta), 0)::bigint
    from inventory.stock_ledger_entries entry
    where entry.transaction_id = (
      select (
        result -> 'reversalTransactions' -> 0
          ->> 'reversalTransactionId'
      )::uuid
      from downstream_results
      where kind = 'CANCEL_POST'
    )
  ),
  1::bigint,
  'post-shipment cancellation restores one exact unit'
);

insert into downstream_results (kind, result)
select
  'EXPECTED_RETURN',
  api.create_expected_marketplace_listing_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-RETURN-051',
    'SHOPEE',
    'SHP-RETURN-LISTING-051',
    'SHP-ORDER-LISTING-051',
    'RETURN_EXPECTED',
    '2026-07-22 10:30:00+07'::timestamptz,
    '2026-07-22 10:30:01+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'orderSourceLineRef', 'SRC-BUNDLE-051',
        'componentNo', 1,
        'quantity', 1
      )
    ),
    'Expect the remaining shipped serum.',
    jsonb_build_object('event', 'return-051'),
    jsonb_build_object('fixture', 'downstream-051'),
    1
  );

select is(
  (
    select result ->> 'status'
    from downstream_results
    where kind = 'EXPECTED_RETURN'
  ),
  'EXPECTED',
  'expected return is created for the exact bundle component'
);

select is(
  (
    select count(*)
    from operations.return_items return_item
    join operations.marketplace_source_line_components component
      on component.organization_id =
           return_item.organization_id
     and component.order_item_id =
           return_item.marketplace_order_item_id
     and component.product_id = return_item.product_id
    where return_item.return_id = (
      select (result ->> 'returnId')::uuid
      from downstream_results
      where kind = 'EXPECTED_RETURN'
    )
      and component.component_no = 1
      and return_item.expected_qty = 1
  ),
  1::bigint,
  'return item retains source component order-item linkage'
);

insert into downstream_results (kind, result)
select
  'OVERLAP_PREVIEW',
  api.preview_marketplace_listing_cancellation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'SHOPEE',
    'SHP-EVT-LISTING-CANCEL-OVERLAP-051',
    'SHP-ORDER-LISTING-051',
    'CANCELLED_AFTER_SHIPMENT',
    '2026-07-22 10:40:00+07'::timestamptz,
    '2026-07-22 10:40:01+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'orderSourceLineRef', 'SRC-BUNDLE-051',
        'componentNo', 1,
        'phaseCode', 'POST_SHIPMENT',
        'quantity', 1,
        'cancellationLineRef', 'CANCEL-051-OVERLAP'
      )
    ),
    'Attempt to reuse expected-return quantity.',
    jsonb_build_object('event', 'overlap-051'),
    jsonb_build_object('fixture', 'downstream-051'),
    1
  );

select is(
  (
    select result ->> 'eligible'
    from downstream_results
    where kind = 'OVERLAP_PREVIEW'
  ),
  'false',
  'expected return blocks overlapping component cancellation'
);

select ok(
  (
    select result -> 'blockers'
    from downstream_results
    where kind = 'OVERLAP_PREVIEW'
  ) @> '[{"code":"MARKETPLACE_CANCELLATION_EXCEEDS_SHIPPED_REMAINING"}]'::jsonb,
  'overlap uses shipped component remainder blocker'
);

select is(
  (
    select
      shipped_quantity::text
        || ':'
        || pre_shipment_cancelled_quantity::text
        || ':'
        || post_shipment_cancelled_quantity::text
        || ':'
        || return_expected_quantity::text
    from api.marketplace_listing_component_lifecycle
    where external_order_ref = 'SHP-ORDER-LISTING-051'
      and source_line_ref = 'SRC-BUNDLE-051'
      and component_no = 1
  ),
  '2:1:1:1',
  'component lifecycle read model traces ship, cancellation, and return'
);

create temporary table missing_component_before as
select
  (
    select count(*)
    from operations.marketplace_events
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  )::bigint as event_count,
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  )::bigint as transaction_count;

select throws_ok(
  $sql$
    select api.ship_marketplace_listing_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-LISTING-SHIP-MISSING-051',
      'SHOPEE',
      'SHP-EVT-LISTING-SHIP-MISSING-051',
      'SHP-ORDER-LISTING-051',
      'SHIPPED',
      '2026-07-22 10:50:00+07'::timestamptz,
      '2026-07-22 10:50:01+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'orderSourceLineRef', 'SRC-BUNDLE-051',
          'componentNo', 99,
          'quantity', 1
        )
      ),
      null,
      '{}'::jsonb,
      '{}'::jsonb,
      1
    )
  $sql$,
  'P0001',
  'MARKETPLACE_SOURCE_COMPONENT_NOT_FOUND',
  'missing source component is rejected before stock effect'
);

select is(
  (
    select
      (select count(*)
       from operations.marketplace_events
       where organization_id =
         '00000000-0000-4000-8000-000000000001'::uuid)
        || ':'
        || (select count(*)
            from inventory.stock_transactions
            where organization_id =
              '00000000-0000-4000-8000-000000000001'::uuid)
  ),
  (
    select
      event_count || ':' || transaction_count
    from missing_component_before
  ),
  'missing component leaves marketplace events and stock unchanged'
);

select is(
  (
    select count(*)
    from catalog.products product
    where product.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product.sku in (
        'BND-GLOW-01',
        'SHP-BND-GLOW-01',
        'TTS-BND-GLOW-01'
      )
  ),
  0::bigint,
  'downstream lifecycle never creates bundle stock'
);

select *
from finish();

rollback;
