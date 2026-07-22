begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_table(
  'operations',
  'marketplace_normalization_events',
  'marketplace normalization event header exists'
);

select has_table(
  'operations',
  'marketplace_source_lines',
  'marketplace source line snapshot exists'
);

select has_table(
  'operations',
  'marketplace_source_line_components',
  'marketplace expanded component snapshot exists'
);

select has_view(
  'api',
  'marketplace_listing_normalizations',
  'marketplace listing normalization read model exists'
);

select function_returns(
  'api',
  'reserve_marketplace_listing_event',
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

select policies_are(
  'operations',
  'marketplace_normalization_events',
  array['marketplace_normalization_events_read_current_org']
);

select policies_are(
  'operations',
  'marketplace_source_lines',
  array['marketplace_source_lines_read_current_org']
);

select policies_are(
  'operations',
  'marketplace_source_line_components',
  array['marketplace_source_line_components_read_current_org']
);

select ok(
  not has_table_privilege(
    'authenticated',
    'operations.marketplace_normalization_events',
    'INSERT'
  ),
  'authenticated cannot insert normalization headers directly'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'operations.marketplace_source_lines',
    'INSERT'
  ),
  'authenticated cannot insert source lines directly'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'operations.marketplace_source_line_components',
    'INSERT'
  ),
  'authenticated cannot insert component snapshots directly'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.reserve_marketplace_listing_event(uuid,text,text,text,text,text,timestamp with time zone,timestamp with time zone,jsonb,text,jsonb,jsonb,integer)',
    'EXECUTE'
  ),
  'authenticated Admin may call normalized reserve command'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.reserve_marketplace_listing_event(uuid,text,text,text,text,text,timestamp with time zone,timestamp with time zone,jsonb,text,jsonb,jsonb,integer)',
    'EXECUTE'
  ),
  'anonymous users cannot call normalized reserve command'
);

select is(
  (
    select count(*)
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('api', 'operations')
      and procedure.proname in (
        'reserve_marketplace_listing_event',
        'resolve_marketplace_listing_expansion'
      )
      and procedure.prosecdef
      and procedure.proconfig @> array[
        'search_path=pg_catalog, auth, app, catalog, inventory, operations, api, extensions'
      ]::text[]
  ),
  1::bigint,
  'normalized reserve command has a fixed complete search_path'
);

select is(
  (
    select count(*)
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'operations'
      and procedure.proname =
        'resolve_marketplace_listing_expansion'
      and procedure.prosecdef
      and procedure.proconfig @> array[
        'search_path=pg_catalog, catalog, operations, extensions'
      ]::text[]
  ),
  1::bigint,
  'internal listing resolver has a fixed search_path'
);

insert into catalog.marketplace_listings (
  id,
  organization_id,
  channel_id,
  external_listing_code,
  display_name,
  listing_type_code,
  status_code,
  created_at,
  updated_at,
  row_version
)
select
  '50000000-0000-4000-8000-000000000050'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  channel.id,
  'SHP-SINGLE-SERUM-050',
  'Single Serum Listing',
  'SINGLE',
  'ACTIVE',
  '2026-07-22 08:00:00+07'::timestamptz,
  '2026-07-22 08:00:00+07'::timestamptz,
  1
from catalog.channels channel
where channel.code = 'SHOPEE';

insert into catalog.marketplace_single_listing_versions (
  id,
  organization_id,
  listing_id,
  version,
  product_id,
  status_code,
  effective_from,
  effective_to,
  activated_at,
  created_at,
  updated_at,
  row_version,
  schema_version
) values (
  '50100000-0000-4000-8000-000000000050'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '50000000-0000-4000-8000-000000000050'::uuid,
  1,
  '30000000-0000-4000-8000-000000000001'::uuid,
  'ACTIVE',
  '2026-07-01 00:00:00+07'::timestamptz,
  null,
  '2026-07-01 00:00:00+07'::timestamptz,
  '2026-07-22 08:00:00+07'::timestamptz,
  '2026-07-22 08:00:00+07'::timestamptz,
  1,
  1
);

create temporary table normalization_before as
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
  )::bigint as ledger_count,
  (
    select reserved_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  )::bigint as serum_reserved,
  (
    select reserved_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000002'::uuid
  )::bigint as cleanser_reserved;

create temporary table normalization_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

insert into normalization_results (kind, result)
select
  'SINGLE',
  api.reserve_marketplace_listing_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-NORMALIZE-SINGLE-050',
    'SHOPEE',
    'SHP-EVT-NORMALIZE-SINGLE-050',
    'SHP-ORDER-NORMALIZE-SINGLE-050',
    'READY_TO_SHIP',
    '2026-07-22 09:00:00+07'::timestamptz,
    '2026-07-22 09:00:05+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'sourceLineRef', 'SRC-SINGLE-1',
        'externalListingCode', 'SHP-SINGLE-SERUM-050',
        'listingQuantity', 2,
        'sourceTitle', 'Serum marketplace',
        'sourceSku', 'EXT-SERUM-050',
        'rawLinePayload', jsonb_build_object('lineId', 'single-1')
      )
    ),
    'Normalized single listing fixture.',
    jsonb_build_object('event', 'single'),
    jsonb_build_object('fixture', 'normalization-050'),
    1
  );

select is(
  (
    select result ->> 'status'
    from normalization_results
    where kind = 'SINGLE'
  ),
  'APPLIED',
  'single listing normalized reserve is applied'
);

select is(
  (
    select (result ->> 'canonicalLineCount')::integer
    from normalization_results
    where kind = 'SINGLE'
  ),
  1,
  'single listing expands to one canonical line'
);

select is(
  (
    select (result ->> 'totalUnitQuantity')::bigint
    from normalization_results
    where kind = 'SINGLE'
  ),
  2::bigint,
  'single listing preserves ordered quantity'
);

select is(
  (
    select count(*)
    from operations.marketplace_source_lines source_line
    where source_line.order_id = (
      select (result ->> 'orderId')::uuid
      from normalization_results
      where kind = 'SINGLE'
    )
      and source_line.listing_type_code_snapshot = 'SINGLE'
      and source_line.listing_quantity = 2
      and source_line.single_listing_version_id =
        '50100000-0000-4000-8000-000000000050'::uuid
  ),
  1::bigint,
  'single source line stores exact mapping version snapshot'
);

select is(
  (
    select count(*)
    from operations.marketplace_source_line_components component
    join operations.marketplace_source_lines source_line
      on source_line.id = component.source_line_id
    where source_line.order_id = (
      select (result ->> 'orderId')::uuid
      from normalization_results
      where kind = 'SINGLE'
    )
      and component.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
      and component.unit_quantity_per_listing = 1
      and component.listing_quantity = 2
      and component.expanded_quantity = 2
      and component.canonical_source_line_ref =
        'SRC-SINGLE-1#C001'
  ),
  1::bigint,
  'single expansion snapshot links source line to canonical order item'
);

insert into normalization_results (kind, result)
select
  'BUNDLE',
  api.reserve_marketplace_listing_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-NORMALIZE-BUNDLE-050',
    'SHOPEE',
    'SHP-EVT-NORMALIZE-BUNDLE-050',
    'SHP-ORDER-NORMALIZE-BUNDLE-050',
    'READY_TO_SHIP',
    '2026-07-22 09:10:00+07'::timestamptz,
    '2026-07-22 09:10:06+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'sourceLineRef', 'SRC-BUNDLE-1',
        'externalListingCode', 'SHP-BND-GLOW-01',
        'listingQuantity', 2,
        'sourceTitle', 'Glow Starter Bundle',
        'sourceSku', 'SHP-BND-GLOW-01',
        'sourceStatus', 'READY_TO_SHIP',
        'rawLinePayload', jsonb_build_object('lineId', 'bundle-1')
      )
    ),
    'Normalized bundle fixture.',
    jsonb_build_object('event', 'bundle'),
    jsonb_build_object('fixture', 'normalization-050'),
    1
  );

select is(
  (
    select (result ->> 'canonicalLineCount')::integer
    from normalization_results
    where kind = 'BUNDLE'
  ),
  2,
  'bundle expands to two canonical product lines'
);

select is(
  (
    select (result ->> 'totalUnitQuantity')::bigint
    from normalization_results
    where kind = 'BUNDLE'
  ),
  6::bigint,
  'bundle listing quantity multiplies component quantities exactly'
);

select is(
  (
    select count(*)
    from operations.marketplace_source_line_components component
    join operations.marketplace_source_lines source_line
      on source_line.id = component.source_line_id
    where source_line.order_id = (
      select (result ->> 'orderId')::uuid
      from normalization_results
      where kind = 'BUNDLE'
    )
      and source_line.listing_type_code_snapshot = 'BUNDLE'
      and source_line.bundle_recipe_id =
        '50000000-0000-4000-8000-000000000001'::uuid
      and component.recipe_component_id is not null
  ),
  2::bigint,
  'bundle snapshot preserves recipe and both recipe component identities'
);

select is(
  (
    select string_agg(
      component.product_sku_snapshot
        || ':'
        || component.expanded_quantity::text,
      ','
      order by component.component_no
    )
    from operations.marketplace_source_line_components component
    join operations.marketplace_source_lines source_line
      on source_line.id = component.source_line_id
    where source_line.order_id = (
      select (result ->> 'orderId')::uuid
      from normalization_results
      where kind = 'BUNDLE'
    )
  ),
  'SER-NIA-30:4,CLN-GEN-100:2',
  'bundle component order and expanded quantities are deterministic'
);

select is(
  (
    select count(*)
    from operations.marketplace_order_items item
    where item.order_id = (
      select (result ->> 'orderId')::uuid
      from normalization_results
      where kind = 'BUNDLE'
    )
  ),
  2::bigint,
  'bundle creates only canonical product order items'
);

select is(
  (
    select count(*)
    from inventory.stock_reservations reservation
    where reservation.order_id = (
      select (result ->> 'orderId')::uuid
      from normalization_results
      where kind = 'BUNDLE'
    )
  ),
  2::bigint,
  'bundle creates one reservation per canonical product component'
);

select is(
  (
    select position.reserved_qty
    from inventory.stock_product_positions position
    where position.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select serum_reserved + 6
    from normalization_before
  ),
  'single and bundle reserves update serum projection exactly'
);

select is(
  (
    select position.reserved_qty
    from inventory.stock_product_positions position
    where position.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id =
        '30000000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select cleanser_reserved + 2
    from normalization_before
  ),
  'bundle reserve updates cleanser projection exactly'
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
    from normalization_before
  ),
  'normalized reserve creates no physical stock transaction'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select ledger_count
    from normalization_before
  ),
  'normalized reserve creates no ledger movement'
);

insert into normalization_results (kind, result)
select
  'BUNDLE_REPLAY',
  api.reserve_marketplace_listing_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-NORMALIZE-BUNDLE-050',
    'SHOPEE',
    'SHP-EVT-NORMALIZE-BUNDLE-050',
    'SHP-ORDER-NORMALIZE-BUNDLE-050',
    'READY_TO_SHIP',
    '2026-07-22 09:10:00+07'::timestamptz,
    '2026-07-22 09:10:06+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'sourceLineRef', 'SRC-BUNDLE-1',
        'externalListingCode', 'SHP-BND-GLOW-01',
        'listingQuantity', 2,
        'sourceTitle', 'Glow Starter Bundle',
        'sourceSku', 'SHP-BND-GLOW-01',
        'sourceStatus', 'READY_TO_SHIP',
        'rawLinePayload', jsonb_build_object('lineId', 'bundle-1')
      )
    ),
    'Normalized bundle fixture.',
    jsonb_build_object('event', 'bundle'),
    jsonb_build_object('fixture', 'normalization-050'),
    1
  );

select is(
  (
    select result ->> 'normalizationEventId'
    from normalization_results
    where kind = 'BUNDLE_REPLAY'
  ),
  (
    select result ->> 'normalizationEventId'
    from normalization_results
    where kind = 'BUNDLE'
  ),
  'duplicate normalized event returns original response'
);

select is(
  (
    select count(*)
    from operations.marketplace_normalization_events normalization
    where normalization.external_event_ref_snapshot =
      'SHP-EVT-NORMALIZE-BUNDLE-050'
  ),
  1::bigint,
  'duplicate replay creates no second normalization header'
);

select throws_ok(
  $sql$
    select api.reserve_marketplace_listing_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-NORMALIZE-BUNDLE-050',
      'SHOPEE',
      'SHP-EVT-NORMALIZE-BUNDLE-050',
      'SHP-ORDER-NORMALIZE-BUNDLE-050',
      'READY_TO_SHIP',
      '2026-07-22 09:10:00+07'::timestamptz,
      '2026-07-22 09:10:06+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'sourceLineRef', 'SRC-BUNDLE-1',
          'externalListingCode', 'SHP-BND-GLOW-01',
          'listingQuantity', 3
        )
      ),
      'Normalized bundle fixture.',
      jsonb_build_object('event', 'bundle'),
      jsonb_build_object('fixture', 'normalization-050'),
      1
    )
  $sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'changed payload under the same normalized command is rejected'
);

create temporary table failure_before as
select
  (
    select count(*)
    from operations.marketplace_orders
  )::bigint as order_count,
  (
    select count(*)
    from operations.marketplace_events
  )::bigint as event_count,
  (
    select count(*)
    from operations.marketplace_normalization_events
  )::bigint as normalization_count,
  (
    select sum(reserved_qty)
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  )::bigint as reserved_total;

select throws_ok(
  $sql$
    select api.reserve_marketplace_listing_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-NORMALIZE-MISSING-050',
      'SHOPEE',
      'SHP-EVT-NORMALIZE-MISSING-050',
      'SHP-ORDER-NORMALIZE-MISSING-050',
      'READY_TO_SHIP',
      '2026-07-22 09:20:00+07'::timestamptz,
      '2026-07-22 09:20:01+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'sourceLineRef', 'SRC-MISSING-1',
          'externalListingCode', 'SHP-MISSING-050',
          'listingQuantity', 1
        )
      ),
      null,
      '{}'::jsonb,
      '{}'::jsonb,
      1
    )
  $sql$,
  'P0001',
  'MARKETPLACE_LISTING_NOT_FOUND',
  'missing mapping is rejected before reservation'
);

select throws_ok(
  $sql$
    select api.reserve_marketplace_listing_event(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-NORMALIZE-INSUFFICIENT-050',
      'SHOPEE',
      'SHP-EVT-NORMALIZE-INSUFFICIENT-050',
      'SHP-ORDER-NORMALIZE-INSUFFICIENT-050',
      'READY_TO_SHIP',
      '2026-07-22 09:30:00+07'::timestamptz,
      '2026-07-22 09:30:01+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'sourceLineRef', 'SRC-INSUFFICIENT-1',
          'externalListingCode', 'SHP-BND-GLOW-01',
          'listingQuantity', 20
        )
      ),
      null,
      '{}'::jsonb,
      '{}'::jsonb,
      1
    )
  $sql$,
  'P0001',
  'INSUFFICIENT_AVAILABLE_STOCK',
  'one insufficient bundle component rolls back the whole normalized reserve'
);

select is(
  (
    select
      (select count(*) from operations.marketplace_orders)
        || ':'
        || (select count(*) from operations.marketplace_events)
        || ':'
        || (
          select count(*)
          from operations.marketplace_normalization_events
        )
        || ':'
        || (
          select sum(reserved_qty)
          from inventory.stock_product_positions
          where organization_id =
            '00000000-0000-4000-8000-000000000001'::uuid
        )
  ),
  (
    select
      order_count
        || ':'
        || event_count
        || ':'
        || normalization_count
        || ':'
        || reserved_total
    from failure_before
  ),
  'failed normalized events leave orders, events, snapshots, and reservations unchanged'
);

select throws_ok(
  $sql$
    update catalog.bundle_components
    set component_qty = component_qty + 1
    where id =
      '51000000-0000-4000-8000-000000000001'::uuid
  $sql$,
  'P0001',
  'MARKETPLACE_BUNDLE_RECIPE_IN_USE',
  'a used bundle component snapshot cannot be rewritten'
);

select throws_ok(
  $sql$
    insert into catalog.bundle_components (
      bundle_recipe_id,
      product_id,
      component_qty,
      line_no
    ) values (
      '50000000-0000-4000-8000-000000000001'::uuid,
      '30000000-0000-4000-8000-000000000003'::uuid,
      1,
      3
    )
  $sql$,
  'P0001',
  'MARKETPLACE_BUNDLE_RECIPE_IN_USE',
  'a used bundle recipe cannot receive another component'
);

select throws_ok(
  $sql$
    update operations.marketplace_source_lines
    set source_title_snapshot = 'mutated'
    where order_id = (
      select (result ->> 'orderId')::uuid
      from normalization_results
      where kind = 'BUNDLE'
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'marketplace source line snapshots are immutable'
);

select is(
  (
    select count(*)
    from api.marketplace_listing_normalizations normalization
    where normalization.external_order_ref_snapshot =
      'SHP-ORDER-NORMALIZE-BUNDLE-050'
      and normalization.listing_type_code_snapshot = 'BUNDLE'
  ),
  2::bigint,
  'read model exposes both canonical bundle components'
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
  'bundle listing never becomes a stock product'
);

select *
from finish();

rollback;
