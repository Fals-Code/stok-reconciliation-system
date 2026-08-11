begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

select has_view(
  'api',
  'marketplace_ship_allocation_context',
  'shipment allocation context read view exists'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'allocation_id',
  'allocation identity is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'organization_id',
  'organization scope is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'event_id',
  'shipment event identity is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'event_line_id',
  'shipment event line identity is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'order_item_id',
  'exact marketplace order item identity is exposed'
);
select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'allocation_no',
  'stable shipment allocation order is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'product_id',
  'product identity is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'batch_id',
  'source batch identity is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'quantity_allocated',
  'shipment allocation quantity is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'product_sku_snapshot',
  'product SKU snapshot is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'batch_code_snapshot',
  'source batch code snapshot is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'expiry_date_snapshot',
  'source expiry snapshot is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'received_first_at_snapshot',
  'source receive-time snapshot is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'source_line_ref',
  'immutable shipment source line reference is exposed'
);

select has_column(
  'api',
  'marketplace_ship_allocation_context',
  'created_at',
  'allocation creation time is exposed'
);

select ok(
  (
    select reloptions @> array[
      'security_invoker=true',
      'security_barrier=true'
    ]
    from pg_class
    where oid = 'api.marketplace_ship_allocation_context'::regclass
  ),
  'allocation context is an invoker security-barrier view'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'operations.marketplace_ship_allocations'::regclass
  ),
  'shipment allocations retain RLS'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'operations.marketplace_event_lines'::regclass
  ),
  'marketplace event lines retain RLS'
);

select ok(
  position(
    'event_line.order_item_id'
    in pg_get_viewdef(
      'api.marketplace_ship_allocation_context'::regclass,
      true
    )
  ) > 0,
  'view derives order item identity from the immutable event line'
);

select ok(
  position(
    'event_line.id = allocation.event_line_id'
    in pg_get_viewdef(
      'api.marketplace_ship_allocation_context'::regclass,
      true
    )
  ) > 0,
  'view joins allocation to its exact event line'
);

select ok(
  has_table_privilege(
    'authenticated',
    'api.marketplace_ship_allocation_context',
    'SELECT'
  ),
  'authenticated users may read shipment allocation context'
);

select ok(
  has_table_privilege(
    'service_role',
    'api.marketplace_ship_allocation_context',
    'SELECT'
  ),
  'service role may read shipment allocation context'
);

select ok(
  not has_table_privilege(
    'anon',
    'api.marketplace_ship_allocation_context',
    'SELECT'
  ),
  'anonymous users cannot read shipment allocation context'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'api.marketplace_ship_allocation_context',
    'INSERT'
  ),
  'allocation context has no authenticated insert path'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'api.marketplace_ship_allocation_context',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'api.marketplace_ship_allocation_context',
    'DELETE'
  ),
  'allocation context has no authenticated update or delete path'
);

select * from finish();

rollback;