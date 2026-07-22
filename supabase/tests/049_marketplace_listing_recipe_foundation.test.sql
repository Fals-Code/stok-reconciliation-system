begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_table(
  'catalog',
  'marketplace_listings',
  'marketplace listing registry exists'
);

select has_table(
  'catalog',
  'marketplace_single_listing_versions',
  'single-listing version table exists'
);

select has_view(
  'api',
  'marketplace_listing_catalog',
  'marketplace listing catalog view exists'
);

select function_returns(
  'api',
  'preview_marketplace_listing_expansion',
  array['uuid', 'text', 'text', 'bigint', 'timestamptz']::text[],
  'jsonb'
);

select policies_are(
  'catalog',
  'marketplace_listings',
  array['marketplace_listings_read_current_org']
);

select policies_are(
  'catalog',
  'marketplace_single_listing_versions',
  array['marketplace_single_listing_versions_read_current_org']
);

select ok(
  not has_table_privilege(
    'authenticated',
    'catalog.marketplace_listings',
    'INSERT'
  ),
  'authenticated cannot insert marketplace listings directly'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'catalog.marketplace_single_listing_versions',
    'INSERT'
  ),
  'authenticated cannot insert single-listing versions directly'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.preview_marketplace_listing_expansion(uuid,text,text,bigint,timestamptz)',
    'EXECUTE'
  ),
  'authenticated Admin may preview listing expansion'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.preview_marketplace_listing_expansion(uuid,text,text,bigint,timestamptz)',
    'EXECUTE'
  ),
  'anonymous users cannot preview listing expansion'
);

insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active,
  created_at
) values (
  '00000000-0000-4000-8000-000000000049'::uuid,
  'PGTAP_LISTING_049',
  'pgTAP Marketplace Listing Foundation',
  'Asia/Jakarta',
  true,
  '2026-07-22 08:00:00+07'::timestamptz
);

insert into catalog.products (
  id,
  organization_id,
  sku,
  name,
  unit_code,
  is_batch_tracked,
  is_expiry_tracked,
  is_active,
  created_at,
  updated_at,
  row_version
) values
  (
    '49000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000049'::uuid,
    'LST-SERUM',
    'Listing Serum Fixture',
    'UNIT',
    true,
    true,
    true,
    '2026-07-22 08:00:00+07'::timestamptz,
    '2026-07-22 08:00:00+07'::timestamptz,
    1
  ),
  (
    '49000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000049'::uuid,
    'LST-CLEANSER',
    'Listing Cleanser Fixture',
    'UNIT',
    true,
    true,
    true,
    '2026-07-22 08:00:00+07'::timestamptz,
    '2026-07-22 08:00:00+07'::timestamptz,
    1
  ),
  (
    '49000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000049'::uuid,
    'LST-INACTIVE',
    'Inactive Listing Fixture',
    'UNIT',
    true,
    true,
    false,
    '2026-07-22 08:00:00+07'::timestamptz,
    '2026-07-22 08:00:00+07'::timestamptz,
    1
  );

insert into catalog.bundle_recipes (
  id,
  organization_id,
  channel_id,
  external_listing_sku,
  external_listing_name,
  version,
  effective_from,
  effective_to,
  is_active,
  created_at
)
select
  '49100000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000049'::uuid,
  channel.id,
  'SHP-LISTING-BUNDLE-049',
  'Bundle Listing Fixture',
  1,
  '2026-07-01 00:00:00+07'::timestamptz,
  null,
  true,
  '2026-07-22 08:00:00+07'::timestamptz
from catalog.channels channel
where channel.code = 'SHOPEE';

insert into catalog.bundle_components (
  id,
  bundle_recipe_id,
  product_id,
  component_qty,
  line_no
) values
  (
    '49200000-0000-4000-8000-000000000001'::uuid,
    '49100000-0000-4000-8000-000000000001'::uuid,
    '49000000-0000-4000-8000-000000000001'::uuid,
    2,
    1
  ),
  (
    '49200000-0000-4000-8000-000000000002'::uuid,
    '49100000-0000-4000-8000-000000000001'::uuid,
    '49000000-0000-4000-8000-000000000002'::uuid,
    1,
    2
  );

select is(
  (
    select count(*)
    from catalog.marketplace_listings listing
    join catalog.channels channel on channel.id = listing.channel_id
    where listing.organization_id =
      '00000000-0000-4000-8000-000000000049'::uuid
      and channel.code = 'SHOPEE'
      and listing.external_listing_code = 'SHP-LISTING-BUNDLE-049'
      and listing.listing_type_code = 'BUNDLE'
  ),
  1::bigint,
  'bundle recipe automatically registers one marketplace listing'
);

create temp table listing_preview_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

insert into listing_preview_results (kind, result)
select
  'BUNDLE',
  api.preview_marketplace_listing_expansion(
    '00000000-0000-4000-8000-000000000049'::uuid,
    'SHOPEE',
    'SHP-LISTING-BUNDLE-049',
    3,
    '2026-07-22 09:00:00+07'::timestamptz
  );

insert into listing_preview_results (kind, result)
select
  'BUNDLE_ONE',
  api.preview_marketplace_listing_expansion(
    '00000000-0000-4000-8000-000000000049'::uuid,
    'SHOPEE',
    'SHP-LISTING-BUNDLE-049',
    1,
    '2026-07-22 09:00:00+07'::timestamptz
  );

select is(
  (
    select result ->> 'listingType'
    from listing_preview_results
    where kind = 'BUNDLE'
  ),
  'BUNDLE',
  'bundle preview identifies bundle listing type'
);

select is(
  (
    select (result ->> 'totalUnitQuantity')::bigint
    from listing_preview_results
    where kind = 'BUNDLE'
  ),
  9::bigint,
  'bundle quantity expands to exact total unit quantity'
);

select is(
  (
    select (component ->> 'expandedQuantity')::bigint
    from listing_preview_results result
    cross join lateral jsonb_array_elements(result.result -> 'components')
      component
    where result.kind = 'BUNDLE'
      and component ->> 'productSku' = 'LST-SERUM'
  ),
  6::bigint,
  'bundle multiplier expands serum quantity deterministically'
);

select is(
  (
    select (component ->> 'expandedQuantity')::bigint
    from listing_preview_results result
    cross join lateral jsonb_array_elements(result.result -> 'components')
      component
    where result.kind = 'BUNDLE'
      and component ->> 'productSku' = 'LST-CLEANSER'
  ),
  3::bigint,
  'bundle multiplier expands cleanser quantity deterministically'
);

select is(
  (
    select result ->> 'stockEffect'
    from listing_preview_results
    where kind = 'BUNDLE'
  ),
  'NONE',
  'bundle preview is stock-neutral'
);

select is(
  (
    select result ->> 'mappingFingerprint'
    from listing_preview_results
    where kind = 'BUNDLE'
  ),
  (
    select result ->> 'mappingFingerprint'
    from listing_preview_results
    where kind = 'BUNDLE_ONE'
  ),
  'bundle mapping fingerprint is independent of ordered quantity'
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
  '49300000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000049'::uuid,
  channel.id,
  'SHP-LISTING-SINGLE-049',
  'Single Listing Fixture',
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
  '49400000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000049'::uuid,
  '49300000-0000-4000-8000-000000000001'::uuid,
  1,
  '49000000-0000-4000-8000-000000000001'::uuid,
  'ACTIVE',
  '2026-07-01 00:00:00+07'::timestamptz,
  null,
  '2026-07-01 00:00:00+07'::timestamptz,
  '2026-07-22 08:00:00+07'::timestamptz,
  '2026-07-22 08:00:00+07'::timestamptz,
  1,
  1
);

select throws_ok(
  $sql$
    update catalog.marketplace_single_listing_versions
    set product_id =
      '49000000-0000-4000-8000-000000000002'::uuid
    where id =
      '49400000-0000-4000-8000-000000000001'::uuid
  $sql$,
  'P0001',
  'MARKETPLACE_LISTING_VERSION_IMMUTABLE',
  'activated single-listing mapping cannot change product identity'
);

select throws_ok(
  $sql$
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
      '49400000-0000-4000-8000-000000000002'::uuid,
      '00000000-0000-4000-8000-000000000049'::uuid,
      '49300000-0000-4000-8000-000000000001'::uuid,
      2,
      '49000000-0000-4000-8000-000000000002'::uuid,
      'ACTIVE',
      '2026-07-15 00:00:00+07'::timestamptz,
      '2026-08-01 00:00:00+07'::timestamptz,
      '2026-07-15 00:00:00+07'::timestamptz,
      '2026-07-22 08:00:00+07'::timestamptz,
      '2026-07-22 08:00:00+07'::timestamptz,
      1,
      1
    )
  $sql$,
  'P0001',
  'MARKETPLACE_LISTING_VERSION_OVERLAP',
  'overlapping active single-listing versions are rejected'
);

insert into listing_preview_results (kind, result)
select
  'SINGLE',
  api.preview_marketplace_listing_expansion(
    '00000000-0000-4000-8000-000000000049'::uuid,
    'SHOPEE',
    'SHP-LISTING-SINGLE-049',
    4,
    '2026-07-22 09:00:00+07'::timestamptz
  );

select is(
  (
    select result ->> 'listingType'
    from listing_preview_results
    where kind = 'SINGLE'
  ),
  'SINGLE',
  'single preview identifies single listing type'
);

select is(
  (
    select (result ->> 'totalUnitQuantity')::bigint
    from listing_preview_results
    where kind = 'SINGLE'
  ),
  4::bigint,
  'single listing preserves listing quantity'
);

select is(
  (
    select (component ->> 'expandedQuantity')::bigint
    from listing_preview_results result
    cross join lateral jsonb_array_elements(result.result -> 'components')
      component
    where result.kind = 'SINGLE'
  ),
  4::bigint,
  'single listing produces one canonical product component'
);

select ok(
  (
    select result ->> 'mappingFingerprint'
    from listing_preview_results
    where kind = 'SINGLE'
  ) ~ '^[0-9a-f]{64}$',
  'single listing preview returns a deterministic mapping fingerprint'
);

select is(
  (
    select count(*)
    from inventory.stock_reservations reservation
    where reservation.organization_id =
      '00000000-0000-4000-8000-000000000049'::uuid
  ),
  0::bigint,
  'listing previews create no reservations'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.organization_id =
      '00000000-0000-4000-8000-000000000049'::uuid
  ),
  0::bigint,
  'listing previews create no stock transactions'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    where entry.organization_id =
      '00000000-0000-4000-8000-000000000049'::uuid
  ),
  0::bigint,
  'listing previews create no ledger effects'
);

select throws_ok(
  $sql$
    select api.preview_marketplace_listing_expansion(
      '00000000-0000-4000-8000-000000000049'::uuid,
      'SHOPEE',
      'SHP-LISTING-MISSING-049',
      1,
      '2026-07-22 09:00:00+07'::timestamptz
    )
  $sql$,
  'P0001',
  'MARKETPLACE_LISTING_NOT_FOUND',
  'missing listing is rejected without guessing a product'
);

select throws_ok(
  $sql$
    select api.preview_marketplace_listing_expansion(
      '00000000-0000-4000-8000-000000000049'::uuid,
      'SHOPEE',
      'SHP-LISTING-SINGLE-049',
      0,
      '2026-07-22 09:00:00+07'::timestamptz
    )
  $sql$,
  'P0001',
  'MARKETPLACE_LISTING_QUANTITY_INVALID',
  'zero listing quantity is rejected'
);

select throws_ok(
  $sql$
    insert into catalog.marketplace_listings (
      organization_id,
      channel_id,
      external_listing_code,
      display_name,
      listing_type_code,
      status_code
    )
    select
      '00000000-0000-4000-8000-000000000049'::uuid,
      channel.id,
      'MANUAL-LISTING-049',
      'Invalid Manual Listing',
      'SINGLE',
      'ACTIVE'
    from catalog.channels channel
    where channel.code = 'MANUAL'
  $sql$,
  'P0001',
  'MARKETPLACE_LISTING_CHANNEL_NOT_ALLOWED',
  'non-marketplace channel cannot own a marketplace listing'
);

select *
from finish();

rollback;
