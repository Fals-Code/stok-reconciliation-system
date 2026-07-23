begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_column(
  'catalog',
  'bundle_recipes',
  'status_code',
  'bundle recipes expose lifecycle status'
);

select has_column(
  'catalog',
  'bundle_recipes',
  'recipe_fingerprint',
  'bundle recipes persist deterministic fingerprint'
);

select has_column(
  'catalog',
  'bundle_recipes',
  'row_version',
  'bundle recipes support optimistic concurrency'
);

select has_view(
  'api',
  'marketplace_listing_versions',
  'marketplace listing version read model exists'
);

select has_view(
  'api',
  'marketplace_bundle_recipe_components',
  'bundle component read model exists'
);

select function_returns(
  'api',
  'create_marketplace_listing_version_draft',
  array[
    'uuid',
    'text',
    'text',
    'text',
    'text',
    'text',
    'timestamp with time zone',
    'uuid',
    'jsonb',
    'text',
    'jsonb'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'save_marketplace_listing_version_draft',
  array[
    'uuid',
    'uuid',
    'uuid',
    'bigint',
    'text',
    'timestamp with time zone',
    'uuid',
    'jsonb',
    'text',
    'jsonb'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'preview_marketplace_listing_version_activation',
  array['uuid', 'uuid', 'uuid']::text[],
  'jsonb'
);

select function_returns(
  'api',
  'activate_marketplace_listing_version',
  array[
    'uuid',
    'text',
    'uuid',
    'uuid',
    'bigint',
    'text',
    'boolean'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'retire_marketplace_listing_version',
  array[
    'uuid',
    'text',
    'uuid',
    'uuid',
    'bigint',
    'timestamp with time zone',
    'boolean'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'archive_marketplace_listing',
  array[
    'uuid',
    'text',
    'uuid',
    'bigint',
    'boolean'
  ]::text[],
  'jsonb'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'catalog.bundle_recipes',
    'INSERT'
  ),
  'authenticated cannot insert bundle recipes directly'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'catalog.bundle_components',
    'UPDATE'
  ),
  'authenticated cannot update bundle components directly'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.create_marketplace_listing_version_draft(uuid,text,text,text,text,text,timestamp with time zone,uuid,jsonb,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may create listing version drafts'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.activate_marketplace_listing_version(uuid,text,uuid,uuid,bigint,text,boolean)',
    'EXECUTE'
  ),
  'anonymous users cannot activate listing versions'
);

select is(
  (
    select count(*)
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'api'
      and procedure.proname in (
        'create_marketplace_listing_version_draft',
        'save_marketplace_listing_version_draft',
        'preview_marketplace_listing_version_activation',
        'activate_marketplace_listing_version',
        'retire_marketplace_listing_version',
        'archive_marketplace_listing'
      )
      and procedure.prosecdef
  ),
  6::bigint,
  'all Admin listing commands are security definer functions'
);

create temporary table admin_listing_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temporary table admin_stock_before as
select
  (
    select count(*)
    from inventory.stock_reservations
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  )::bigint as reservation_count,
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

insert into admin_listing_results (kind, result)
select
  'BUNDLE_DRAFT_V1',
  api.create_marketplace_listing_version_draft(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-ADMIN-CREATE-BUNDLE-052',
    'SHOPEE',
    'SHP-ADMIN-BUNDLE-052',
    'Admin Bundle 052',
    'BUNDLE',
    '2026-08-01 00:00:00+07'::timestamptz,
    null,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
          '30000000-0000-4000-8000-000000000001',
        'quantity',
          2
      ),
      jsonb_build_object(
        'productId',
          '30000000-0000-4000-8000-000000000002',
        'quantity',
          1
      )
    ),
    'Draft resep bundle Admin.',
    jsonb_build_object('fixture', 'admin-052')
  );

select is(
  (
    select result ->> 'status'
    from admin_listing_results
    where kind = 'BUNDLE_DRAFT_V1'
  ),
  'DRAFT_CREATED',
  'bundle listing draft is created'
);

select is(
  (
    select recipe.status_code
    from catalog.bundle_recipes recipe
    where recipe.id = (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V1'
    )
  ),
  'DRAFT',
  'bundle recipe remains draft before activation'
);

select is(
  (
    select count(*)
    from catalog.bundle_components component
    where component.bundle_recipe_id = (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V1'
    )
  ),
  2::bigint,
  'bundle draft stores both product components'
);

insert into admin_listing_results (kind, result)
select
  'BUNDLE_SAVE_V1',
  api.save_marketplace_listing_version_draft(
    '00000000-0000-4000-8000-000000000001'::uuid,
    (
      select (result ->> 'listingId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V1'
    ),
    (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V1'
    ),
    1,
    'Admin Bundle 052 Revisi',
    '2026-08-01 00:00:00+07'::timestamptz,
    null,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
          '30000000-0000-4000-8000-000000000001',
        'quantity',
          3
      ),
      jsonb_build_object(
        'productId',
          '30000000-0000-4000-8000-000000000002',
        'quantity',
          1
      )
    ),
    'Draft resep bundle direvisi.',
    jsonb_build_object('fixture', 'admin-052-revised')
  );

select is(
  (
    select (result ->> 'versionRowVersion')::bigint
    from admin_listing_results
    where kind = 'BUNDLE_SAVE_V1'
  ),
  2::bigint,
  'draft save increments optimistic row version'
);

select throws_ok(
  $sql$
    select api.save_marketplace_listing_version_draft(
      '00000000-0000-4000-8000-000000000001'::uuid,
      (
        select (result ->> 'listingId')::uuid
        from admin_listing_results
        where kind = 'BUNDLE_DRAFT_V1'
      ),
      (
        select (result ->> 'versionId')::uuid
        from admin_listing_results
        where kind = 'BUNDLE_DRAFT_V1'
      ),
      1,
      'Admin Bundle 052 stale',
      '2026-08-01 00:00:00+07'::timestamptz,
      null,
      jsonb_build_array(
        jsonb_build_object(
          'productId',
            '30000000-0000-4000-8000-000000000001',
          'quantity',
            1
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'STALE_MARKETPLACE_LISTING_VERSION_DRAFT',
  'stale bundle draft update is rejected'
);

insert into admin_listing_results (kind, result)
select
  'BUNDLE_PREVIEW_V1',
  api.preview_marketplace_listing_version_activation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    (
      select (result ->> 'listingId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V1'
    ),
    (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V1'
    )
  );

select is(
  (
    select result ->> 'eligible'
    from admin_listing_results
    where kind = 'BUNDLE_PREVIEW_V1'
  ),
  'true',
  'bundle activation preview is eligible'
);

select is(
  (
    select (result ->> 'componentCount')::bigint
    from admin_listing_results
    where kind = 'BUNDLE_PREVIEW_V1'
  ),
  2::bigint,
  'bundle activation preview includes two components'
);

insert into admin_listing_results (kind, result)
select
  'BUNDLE_ACTIVE_V1',
  api.activate_marketplace_listing_version(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-ADMIN-ACTIVATE-BUNDLE-V1-052',
    (
      select (result ->> 'listingId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V1'
    ),
    (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V1'
    ),
    (
      select (result ->> 'versionRowVersion')::bigint
      from admin_listing_results
      where kind = 'BUNDLE_PREVIEW_V1'
    ),
    (
      select result ->> 'basisHash'
      from admin_listing_results
      where kind = 'BUNDLE_PREVIEW_V1'
    ),
    true
  );

select is(
  (
    select result ->> 'status'
    from admin_listing_results
    where kind = 'BUNDLE_ACTIVE_V1'
  ),
  'ACTIVATED',
  'bundle version activates from exact preview'
);

select ok(
  (
    select recipe.recipe_fingerprint
    from catalog.bundle_recipes recipe
    where recipe.id = (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_ACTIVE_V1'
    )
  ) ~ '^[0-9a-f]{64}$'
  and (
    select recipe.recipe_fingerprint
    from catalog.bundle_recipes recipe
    where recipe.id = (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_ACTIVE_V1'
    )
  ) <> repeat('0', 64),
  'activated bundle stores a non-placeholder fingerprint'
);

insert into admin_listing_results (kind, result)
select
  'BUNDLE_ACTIVE_V1_REPLAY',
  api.activate_marketplace_listing_version(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-ADMIN-ACTIVATE-BUNDLE-V1-052',
    (
      select (result ->> 'listingId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V1'
    ),
    (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V1'
    ),
    (
      select (result ->> 'versionRowVersion')::bigint
      from admin_listing_results
      where kind = 'BUNDLE_PREVIEW_V1'
    ),
    (
      select result ->> 'basisHash'
      from admin_listing_results
      where kind = 'BUNDLE_PREVIEW_V1'
    ),
    true
  );

select is(
  (
    select result ->> 'versionId'
    from admin_listing_results
    where kind = 'BUNDLE_ACTIVE_V1_REPLAY'
  ),
  (
    select result ->> 'versionId'
    from admin_listing_results
    where kind = 'BUNDLE_ACTIVE_V1'
  ),
  'activation replay returns the original version'
);

select throws_ok(
  $sql$
    select api.save_marketplace_listing_version_draft(
      '00000000-0000-4000-8000-000000000001'::uuid,
      (
        select (result ->> 'listingId')::uuid
        from admin_listing_results
        where kind = 'BUNDLE_DRAFT_V1'
      ),
      (
        select (result ->> 'versionId')::uuid
        from admin_listing_results
        where kind = 'BUNDLE_DRAFT_V1'
      ),
      3,
      'Mutasi versi aktif',
      '2026-08-01 00:00:00+07'::timestamptz,
      null,
      jsonb_build_array(
        jsonb_build_object(
          'productId',
            '30000000-0000-4000-8000-000000000003',
          'quantity',
            1
        )
      ),
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'MARKETPLACE_LISTING_VERSION_NOT_DRAFT',
  'activated bundle cannot be edited through draft command'
);

insert into admin_listing_results (kind, result)
select
  'BUNDLE_DRAFT_V2',
  api.create_marketplace_listing_version_draft(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-ADMIN-CREATE-BUNDLE-V2-052',
    'SHOPEE',
    'SHP-ADMIN-BUNDLE-052',
    'Admin Bundle 052 V2',
    'BUNDLE',
    '2026-09-01 00:00:00+07'::timestamptz,
    null,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
          '30000000-0000-4000-8000-000000000001',
        'quantity',
          1
      ),
      jsonb_build_object(
        'productId',
          '30000000-0000-4000-8000-000000000003',
        'quantity',
          1
      )
    ),
    'Versi dua bundle.',
    jsonb_build_object('fixture', 'admin-052-v2')
  );

insert into admin_listing_results (kind, result)
select
  'BUNDLE_PREVIEW_V2',
  api.preview_marketplace_listing_version_activation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    (
      select (result ->> 'listingId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V2'
    ),
    (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V2'
    )
  );

insert into admin_listing_results (kind, result)
select
  'BUNDLE_ACTIVE_V2',
  api.activate_marketplace_listing_version(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-ADMIN-ACTIVATE-BUNDLE-V2-052',
    (
      select (result ->> 'listingId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V2'
    ),
    (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_DRAFT_V2'
    ),
    (
      select (result ->> 'versionRowVersion')::bigint
      from admin_listing_results
      where kind = 'BUNDLE_PREVIEW_V2'
    ),
    (
      select result ->> 'basisHash'
      from admin_listing_results
      where kind = 'BUNDLE_PREVIEW_V2'
    ),
    true
  );

select is(
  (
    select recipe.effective_to
    from catalog.bundle_recipes recipe
    where recipe.id = (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'BUNDLE_ACTIVE_V1'
    )
  ),
  '2026-09-01 00:00:00+07'::timestamptz,
  'new activation closes the previous version at exact boundary'
);

select is(
  (
    select (
      api.preview_marketplace_listing_expansion(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'SHOPEE',
        'SHP-ADMIN-BUNDLE-052',
        1,
        '2026-08-31 23:59:59+07'::timestamptz
      ) ->> 'mappingVersion'
    )::integer
  ),
  1,
  'historical event before boundary keeps bundle version one'
);

select is(
  (
    select (
      api.preview_marketplace_listing_expansion(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'SHOPEE',
        'SHP-ADMIN-BUNDLE-052',
        1,
        '2026-09-01 00:00:00+07'::timestamptz
      ) ->> 'mappingVersion'
    )::integer
  ),
  2,
  'event at boundary uses bundle version two'
);

insert into admin_listing_results (kind, result)
select
  'SINGLE_DRAFT_V1',
  api.create_marketplace_listing_version_draft(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-ADMIN-CREATE-SINGLE-052',
    'SHOPEE',
    'SHP-ADMIN-SINGLE-052',
    'Admin Single 052',
    'SINGLE',
    '2026-08-01 00:00:00+07'::timestamptz,
    '30000000-0000-4000-8000-000000000003'::uuid,
    '[]'::jsonb,
    'Draft single.',
    jsonb_build_object('fixture', 'admin-single-052')
  );

insert into admin_listing_results (kind, result)
select
  'SINGLE_PREVIEW_V1',
  api.preview_marketplace_listing_version_activation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    (
      select (result ->> 'listingId')::uuid
      from admin_listing_results
      where kind = 'SINGLE_DRAFT_V1'
    ),
    (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'SINGLE_DRAFT_V1'
    )
  );

insert into admin_listing_results (kind, result)
select
  'SINGLE_ACTIVE_V1',
  api.activate_marketplace_listing_version(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-ADMIN-ACTIVATE-SINGLE-052',
    (
      select (result ->> 'listingId')::uuid
      from admin_listing_results
      where kind = 'SINGLE_DRAFT_V1'
    ),
    (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'SINGLE_DRAFT_V1'
    ),
    (
      select (result ->> 'versionRowVersion')::bigint
      from admin_listing_results
      where kind = 'SINGLE_PREVIEW_V1'
    ),
    (
      select result ->> 'basisHash'
      from admin_listing_results
      where kind = 'SINGLE_PREVIEW_V1'
    ),
    true
  );

select is(
  (
    select (
      api.preview_marketplace_listing_expansion(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'SHOPEE',
        'SHP-ADMIN-SINGLE-052',
        4,
        '2026-08-02 00:00:00+07'::timestamptz
      ) #>> '{components,0,productSku}'
    )
  ),
  'TNR-HYD-100',
  'single listing activation resolves the selected product'
);

insert into admin_listing_results (kind, result)
select
  'SINGLE_RETIRED_V1',
  api.retire_marketplace_listing_version(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-ADMIN-RETIRE-SINGLE-052',
    (
      select (result ->> 'listingId')::uuid
      from admin_listing_results
      where kind = 'SINGLE_DRAFT_V1'
    ),
    (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'SINGLE_DRAFT_V1'
    ),
    2,
    '2026-10-01 00:00:00+07'::timestamptz,
    true
  );

select is(
  (
    select version.status_code
    from catalog.marketplace_single_listing_versions version
    where version.id = (
      select (result ->> 'versionId')::uuid
      from admin_listing_results
      where kind = 'SINGLE_RETIRED_V1'
    )
  ),
  'RETIRED',
  'single listing version may be retired without deleting history'
);

select is(
  (
    select (
      api.preview_marketplace_listing_expansion(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'SHOPEE',
        'SHP-ADMIN-SINGLE-052',
        1,
        '2026-09-30 23:59:59+07'::timestamptz
      ) ->> 'mappingVersion'
    )::integer
  ),
  1,
  'retired single version remains resolvable inside historical period'
);

select throws_ok(
  $sql$
    select api.preview_marketplace_listing_expansion(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'SHOPEE',
      'SHP-ADMIN-SINGLE-052',
      1,
      '2026-10-01 00:00:00+07'::timestamptz
    )
  $sql$,
  'P0001',
  'MARKETPLACE_LISTING_MAPPING_NOT_FOUND',
  'retired single mapping is unavailable after effective end'
);

insert into admin_listing_results (kind, result)
select
  'SINGLE_ARCHIVED',
  api.archive_marketplace_listing(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-LISTING-ADMIN-ARCHIVE-SINGLE-052',
    (
      select (result ->> 'listingId')::uuid
      from admin_listing_results
      where kind = 'SINGLE_DRAFT_V1'
    ),
    (
      select listing.row_version
      from catalog.marketplace_listings listing
      where listing.id = (
        select (result ->> 'listingId')::uuid
        from admin_listing_results
        where kind = 'SINGLE_DRAFT_V1'
      )
    ),
    true
  );

select throws_ok(
  $sql$
    select api.preview_marketplace_listing_expansion(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'SHOPEE',
      'SHP-ADMIN-SINGLE-052',
      1,
      '2026-09-01 00:00:00+07'::timestamptz
    )
  $sql$,
  'P0001',
  'MARKETPLACE_LISTING_ARCHIVED',
  'archived listing rejects new normalization attempts'
);

select is(
  (
    select
      (select count(*)
       from inventory.stock_reservations
       where organization_id =
         '00000000-0000-4000-8000-000000000001'::uuid)
        || ':'
        || (select count(*)
            from inventory.stock_transactions
            where organization_id =
              '00000000-0000-4000-8000-000000000001'::uuid)
        || ':'
        || (select count(*)
            from inventory.stock_ledger_entries
            where organization_id =
              '00000000-0000-4000-8000-000000000001'::uuid)
  ),
  (
    select
      reservation_count
        || ':'
        || transaction_count
        || ':'
        || ledger_count
    from admin_stock_before
  ),
  'listing and recipe administration remains stock-neutral'
);

select is(
  (
    select count(*)
    from catalog.products product
    where product.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product.sku in (
        'SHP-ADMIN-BUNDLE-052',
        'SHP-ADMIN-SINGLE-052'
      )
  ),
  0::bigint,
  'Admin listing lifecycle never creates stock products'
);

select *
from finish();

rollback;
