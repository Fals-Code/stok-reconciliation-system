begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_trigger(
  'inventory',
  'stock_ledger_entries',
  'trg_stock_ledger_entries_master_guardrails',
  'new stock entries enforce Product and Batch guardrails'
);
select has_trigger(
  'operations',
  'opening_balance_cutover_lines',
  'trg_opening_balance_lines_master_guardrails',
  'opening balance draft lines enforce master guardrails'
);
select matches(
  coalesce(
    (
      select array_to_string(procedure.proconfig, ',')
      from pg_proc procedure
      where procedure.oid =
        'inventory.enforce_new_stock_master_guardrails()'::regprocedure
    ),
    ''
  ),
  '^search_path=pg_catalog, catalog, inventory$',
  'stock master guardrail has a fixed search_path'
);
select ok(
  not has_function_privilege(
    'public',
    'inventory.enforce_new_stock_master_guardrails()',
    'EXECUTE'
  ),
  'PUBLIC cannot execute the stock master guardrail function'
);
select ok(
  not has_function_privilege(
    'public',
    'operations.enforce_opening_balance_line_master_guardrails()',
    'EXECUTE'
  ),
  'PUBLIC cannot execute the opening balance guardrail function'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'inventory.enforce_new_stock_master_guardrails()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'inventory.enforce_new_stock_master_guardrails()',
    'EXECUTE'
  ),
  'API roles cannot execute the stock master guardrail helper'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'operations.enforce_opening_balance_line_master_guardrails()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'operations.enforce_opening_balance_line_master_guardrails()',
    'EXECUTE'
  ),
  'API roles cannot execute the opening balance guardrail helper'
);
select ok(
  not has_function_privilege(
    'public',
    'operations.resolve_stocktake_scope(uuid,jsonb,date,bigint)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'operations.resolve_stocktake_scope(uuid,jsonb,date,bigint)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'operations.resolve_stocktake_scope(uuid,jsonb,date,bigint)',
    'EXECUTE'
  ),
  'stocktake resolver remains internal after replacement'
);

insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active,
  created_at
) values (
  '00000000-0000-4000-8000-000000000054',
  'PGTAP_GUARD_054',
  'pgTAP Integration Guardrails 054',
  'Asia/Jakarta',
  true,
  '2026-07-23 08:00:00+07'
);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000',
  '95400000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'pgtap.guardrails.054@glowlab.invalid',
  '2026-07-23 08:00:00+07',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-23 08:00:00+07',
  '2026-07-23 08:00:00+07',
  false,
  false
);

insert into app.user_profiles (
  user_id,
  organization_id,
  display_name,
  employee_code,
  role_code,
  is_active
) values (
  '95400000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000054',
  'pgTAP Guardrails Admin',
  'PGTAP-GUARD-054',
  'ADMIN',
  true
);

create temp table guardrail_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update on guardrail_results to authenticated;

select set_config(
  'request.jwt.claim.sub',
  '95400000-0000-4000-8000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '95400000-0000-4000-8000-000000000001',
    'role', 'authenticated',
    'email', 'pgtap.guardrails.054@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

insert into guardrail_results
select
  'PRODUCT_MAIN',
  api.create_product(
    '00000000-0000-4000-8000-000000000054',
    '054-PRODUCT-MAIN',
    'GUARD MAIN 054',
    'Guardrail Main Product',
    'UNIT',
    null,
    'Cross-domain fixture'
  );

insert into guardrail_results
select
  'PRODUCT_OTHER',
  api.create_product(
    '00000000-0000-4000-8000-000000000054',
    '054-PRODUCT-OTHER',
    'GUARD OTHER 054',
    'Guardrail Other Product',
    'UNIT',
    null,
    'Cross-domain fixture'
  );

insert into guardrail_results
select
  'BATCH_STANDARD',
  api.create_product_batch(
    '00000000-0000-4000-8000-000000000054',
    '054-BATCH-STANDARD',
    (
      select (result ->> 'productId')::uuid
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    ),
    'GUARD LOT 054',
    '2027-12-31',
    '2026-01-01',
    null,
    'STANDARD',
    'Cross-domain fixture'
  );

insert into guardrail_results
select
  'BATCH_EXPIRED',
  api.create_product_batch(
    '00000000-0000-4000-8000-000000000054',
    '054-BATCH-EXPIRED',
    (
      select (result ->> 'productId')::uuid
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    ),
    'GUARD EXPIRED 054',
    '2026-01-01',
    null,
    null,
    'STANDARD',
    'Expired cross-domain fixture'
  );

insert into guardrail_results
select
  'RECEIPT',
  api.post_receipt(
    '00000000-0000-4000-8000-000000000054',
    '054-RECEIPT-STANDARD',
    'RCV-GUARD-054',
    '2026-07-23 09:00:00+07',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
          (
            select result ->> 'productId'
            from guardrail_results
            where kind = 'PRODUCT_MAIN'
          ),
        'batchId',
          (
            select result ->> 'batchId'
            from guardrail_results
            where kind = 'BATCH_STANDARD'
          ),
        'quantity', 10,
        'sourceLineRef', 'LINE-1'
      )
    ),
    'Receipt used by integration guardrails.',
    '{"fixture":"guardrails-054"}'::jsonb
  );

insert into guardrail_results
select
  'RECEIPT_REPLAY',
  api.post_receipt(
    '00000000-0000-4000-8000-000000000054',
    '054-RECEIPT-STANDARD',
    'RCV-GUARD-054',
    '2026-07-23 09:00:00+07',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
          (
            select result ->> 'productId'
            from guardrail_results
            where kind = 'PRODUCT_MAIN'
          ),
        'batchId',
          (
            select result ->> 'batchId'
            from guardrail_results
            where kind = 'BATCH_STANDARD'
          ),
        'quantity', 10,
        'sourceLineRef', 'LINE-1'
      )
    ),
    'Receipt used by integration guardrails.',
    '{"fixture":"guardrails-054"}'::jsonb
  );

select is(
  (
    select result ->> 'transactionId'
    from guardrail_results
    where kind = 'RECEIPT_REPLAY'
  ),
  (
    select result ->> 'transactionId'
    from guardrail_results
    where kind = 'RECEIPT'
  ),
  'duplicate Receipt command returns the original transaction'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    where entry.transaction_id = (
      select (result ->> 'transactionId')::uuid
      from guardrail_results
      where kind = 'RECEIPT'
    )
  ),
  1::bigint,
  'duplicate Receipt command does not duplicate ledger effect'
);

select throws_ok(
  format(
    $sql$
      select api.post_receipt(
        '00000000-0000-4000-8000-000000000001',
        '054-RECEIPT-CROSS-ORG',
        'RCV-CROSS-ORG-054',
        '2026-07-23 09:02:00+07',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', %L,
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )),
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    ),
    (
      select result ->> 'batchId'
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    )
  ),
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'Receipt organization isolation cannot be bypassed with foreign identifiers'
);

select throws_ok(
  format(
    $sql$
      select api.post_receipt(
        '00000000-0000-4000-8000-000000000054',
        '054-RECEIPT-WRONG-PRODUCT',
        'RCV-WRONG-PRODUCT-054',
        '2026-07-23 09:05:00+07',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', %L,
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )),
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_OTHER'
    ),
    (
      select result ->> 'batchId'
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    )
  ),
  'P0001',
  'RECEIPT_LINE_MASTER_NOT_FOUND',
  'Receipt rejects a Batch linked to another Product'
);
select is(
  (
    select count(*)
    from inventory.idempotency_commands command
    where command.organization_id =
          '00000000-0000-4000-8000-000000000054'
      and command.key = '054-RECEIPT-WRONG-PRODUCT'
  ),
  0::bigint,
  'failed Receipt rolls back its idempotency row atomically'
);

insert into guardrail_results
select
  'BATCH_BLOCKED',
  api.block_product_batch(
    '00000000-0000-4000-8000-000000000054',
    '054-BATCH-BLOCK',
    (
      select (result ->> 'batchId')::uuid
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    ),
    (
      select batch.row_version
      from catalog.product_batches batch
      where batch.id = (
        select (result ->> 'batchId')::uuid
        from guardrail_results
        where kind = 'BATCH_STANDARD'
      )
    ),
    'Quality hold',
    null
  );

select throws_ok(
  format(
    $sql$
      select api.post_receipt(
        '00000000-0000-4000-8000-000000000054',
        '054-RECEIPT-BLOCKED',
        'RCV-BLOCKED-054',
        '2026-07-23 09:10:00+07',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', %L,
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )),
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    ),
    (
      select result ->> 'batchId'
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    )
  ),
  'P0001',
  'RECEIPT_BATCH_NOT_ACTIVE',
  'Receipt explicitly rejects a BLOCKED Batch'
);
select isnt(
  (
    select master.is_fefo_eligible
    from api.product_batch_master master
    where master.batch_id = (
      select (result ->> 'batchId')::uuid
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    )
  ),
  true,
  'BLOCKED Batch is excluded from FEFO'
);
select isnt(
  (
    select master.is_fefo_eligible
    from api.product_batch_master master
    where master.batch_id = (
      select (result ->> 'batchId')::uuid
      from guardrail_results
      where kind = 'BATCH_EXPIRED'
    )
  ),
  true,
  'effectively expired Batch is excluded from FEFO'
);

insert into guardrail_results
select
  'BATCH_UNBLOCKED',
  api.unblock_product_batch(
    '00000000-0000-4000-8000-000000000054',
    '054-BATCH-UNBLOCK',
    (
      select (result ->> 'batchId')::uuid
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    ),
    (
      select batch.row_version
      from catalog.product_batches batch
      where batch.id = (
        select (result ->> 'batchId')::uuid
        from guardrail_results
        where kind = 'BATCH_STANDARD'
      )
    ),
    'Quality released',
    null
  );

reset role;

insert into catalog.product_batches (
  id,
  organization_id,
  product_id,
  batch_code,
  manufactured_date,
  expiry_date,
  received_first_at,
  status_code,
  block_reason,
  created_at,
  updated_at,
  row_version,
  batch_kind_code
)
select
  '95420000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000054',
  (result ->> 'productId')::uuid,
  'RETURN DOMAIN FIXTURE 054',
  null,
  '2027-12-31',
  '2026-07-23 09:15:00+07',
  'ACTIVE',
  null,
  '2026-07-23 09:15:00+07',
  '2026-07-23 09:15:00+07',
  1,
  'RETURN'
from guardrail_results
where kind = 'PRODUCT_MAIN';

insert into catalog.product_batches (
  id,
  organization_id,
  product_id,
  batch_code,
  manufactured_date,
  expiry_date,
  received_first_at,
  status_code,
  block_reason,
  created_at,
  updated_at,
  row_version,
  batch_kind_code
)
select
  '95420000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000054',
  (result ->> 'productId')::uuid,
  'UNIDENTIFIED RETURN FIXTURE 054',
  null,
  '2027-12-31',
  '2026-07-23 09:15:00+07',
  'BLOCKED',
  'UNIDENTIFIED_RETURN_BATCH',
  '2026-07-23 09:15:00+07',
  '2026-07-23 09:15:00+07',
  1,
  'UNIDENTIFIED_RETURN'
from guardrail_results
where kind = 'PRODUCT_MAIN';

set local role authenticated;

select throws_ok(
  format(
    $sql$
      select api.post_receipt(
        '00000000-0000-4000-8000-000000000054',
        '054-RECEIPT-RETURN-KIND',
        'RCV-RETURN-KIND-054',
        '2026-07-23 09:20:00+07',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', '95420000-0000-4000-8000-000000000001',
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )),
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    )
  ),
  'P0001',
  'RECEIPT_BATCH_KIND_INVALID',
  'normal Receipt rejects a return-domain Batch'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    where entry.batch_id =
          '95420000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'rejected return-kind Receipt leaves no ledger effect'
);

insert into guardrail_results
select
  'OPENING_CREATED',
  api.create_opening_balance_cutover(
    '00000000-0000-4000-8000-000000000054',
    'OB-GUARD-054',
    '2026-07-23 10:00:00+07',
    'LEGACY-GUARD-054',
    'Opening balance integration guardrail fixture.',
    '{"fixture":"guardrails-054"}'::jsonb
  );

select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000054',
        %L::uuid,
        1,
        '2026-07-23 10:00:00+07',
        'LEGACY-GUARD-054',
        'Expired quarantine must fail.',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', %L,
          'bucketCode', 'QUARANTINE',
          'quantity', 1,
          'sourceLineRef', 'EXPIRED-Q'
        )),
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'cutoverId'
      from guardrail_results
      where kind = 'OPENING_CREATED'
    ),
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    ),
    (
      select result ->> 'batchId'
      from guardrail_results
      where kind = 'BATCH_EXPIRED'
    )
  ),
  'P0001',
  'OPENING_BALANCE_BATCH_EXPIRED',
  'Opening Balance rejects an effectively expired Batch in QUARANTINE'
);
select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000054',
        %L::uuid,
        1,
        '2026-07-23 10:00:00+07',
        'LEGACY-GUARD-054',
        'Return Batch must fail.',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', '95420000-0000-4000-8000-000000000001',
          'bucketCode', 'QUARANTINE',
          'quantity', 1,
          'sourceLineRef', 'RETURN-Q'
        )),
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'cutoverId'
      from guardrail_results
      where kind = 'OPENING_CREATED'
    ),
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    )
  ),
  'P0001',
  'OPENING_BALANCE_RETURN_BATCH_FORBIDDEN',
  'Opening Balance rejects a normal RETURN Batch'
);

select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000054',
        %L::uuid,
        1,
        '2026-07-23 10:00:00+07',
        'LEGACY-GUARD-054',
        'Unidentified Batch cannot be a verified normal balance.',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', '95420000-0000-4000-8000-000000000002',
          'bucketCode', 'SELLABLE',
          'quantity', 1,
          'batchIdentityVerified', true,
          'sourceLineRef', 'UNIDENTIFIED-SELLABLE'
        )),
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'cutoverId'
      from guardrail_results
      where kind = 'OPENING_CREATED'
    ),
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    )
  ),
  'P0001',
  'OPENING_BALANCE_UNIDENTIFIED_BATCH_SCOPE_INVALID',
  'Opening Balance draft rejects UNIDENTIFIED_RETURN as a normal balance'
);

insert into guardrail_results
select
  'OPENING_UNIDENTIFIED',
  api.save_opening_balance_cutover_draft(
    '00000000-0000-4000-8000-000000000054',
    (
      select (result ->> 'cutoverId')::uuid
      from guardrail_results
      where kind = 'OPENING_CREATED'
    ),
    1,
    '2026-07-23 10:00:00+07',
    'LEGACY-GUARD-054',
    'Explicit unidentified quarantine exception.',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
          (
            select result ->> 'productId'
            from guardrail_results
            where kind = 'PRODUCT_MAIN'
          ),
        'batchId', '95420000-0000-4000-8000-000000000002',
        'bucketCode', 'QUARANTINE',
        'quantity', 1,
        'batchIdentityVerified', false,
        'exceptionReference', 'UNKNOWN-GUARD-054',
        'sourceLineRef', 'UNKNOWN-Q'
      )
    ),
    '{"fixture":"guardrails-054"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from guardrail_results
    where kind = 'OPENING_UNIDENTIFIED'
  ),
  'DRAFT',
  'Opening Balance preserves the explicit unidentified QUARANTINE exception'
);

insert into guardrail_results
select
  'LISTING_BUNDLE_DRAFT',
  api.create_marketplace_listing_version_draft(
    '00000000-0000-4000-8000-000000000054',
    '054-LISTING-BUNDLE-DRAFT',
    'SHOPEE',
    'SHP-GUARD-BUNDLE-054',
    'Guardrail Bundle 054',
    'BUNDLE',
    '2026-08-01 00:00:00+07',
    null,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
          (
            select result ->> 'productId'
            from guardrail_results
            where kind = 'PRODUCT_MAIN'
          ),
        'quantity', 1
      ),
      jsonb_build_object(
        'productId',
          (
            select result ->> 'productId'
            from guardrail_results
            where kind = 'PRODUCT_OTHER'
          ),
        'quantity', 1
      )
    ),
    'Bundle activation guardrail.',
    '{"fixture":"guardrails-054"}'::jsonb
  );

insert into guardrail_results
select
  'PRODUCT_OTHER_ARCHIVED',
  api.archive_product(
    '00000000-0000-4000-8000-000000000054',
    '054-PRODUCT-OTHER-ARCHIVE',
    (
      select (result ->> 'productId')::uuid
      from guardrail_results
      where kind = 'PRODUCT_OTHER'
    ),
    1,
    'Inactive bundle component fixture'
  );

insert into guardrail_results
select
  'LISTING_BUNDLE_PREVIEW',
  api.preview_marketplace_listing_version_activation(
    '00000000-0000-4000-8000-000000000054',
    (
      select (result ->> 'listingId')::uuid
      from guardrail_results
      where kind = 'LISTING_BUNDLE_DRAFT'
    ),
    (
      select (result ->> 'versionId')::uuid
      from guardrail_results
      where kind = 'LISTING_BUNDLE_DRAFT'
    )
  );

select ok(
  (
    select result -> 'blockers'
           @> '[{"code":"MARKETPLACE_BUNDLE_COMPONENT_INACTIVE"}]'::jsonb
    from guardrail_results
    where kind = 'LISTING_BUNDLE_PREVIEW'
  ),
  'bundle activation preview rejects an inactive Product component'
);
select throws_ok(
  format(
    $sql$
      select api.activate_marketplace_listing_version(
        '00000000-0000-4000-8000-000000000054',
        '054-LISTING-BUNDLE-ACTIVATE',
        %L::uuid,
        %L::uuid,
        %s,
        %L,
        true
      )
    $sql$,
    (
      select result ->> 'listingId'
      from guardrail_results
      where kind = 'LISTING_BUNDLE_DRAFT'
    ),
    (
      select result ->> 'versionId'
      from guardrail_results
      where kind = 'LISTING_BUNDLE_DRAFT'
    ),
    (
      select result ->> 'versionRowVersion'
      from guardrail_results
      where kind = 'LISTING_BUNDLE_PREVIEW'
    ),
    (
      select result ->> 'basisHash'
      from guardrail_results
      where kind = 'LISTING_BUNDLE_PREVIEW'
    )
  ),
  'P0001',
  'MARKETPLACE_BUNDLE_COMPONENT_INACTIVE',
  'bundle activation command rejects an inactive Product component'
);
select is(
  (
    select count(*)
    from catalog.bundle_components component
    where component.bundle_recipe_id = (
      select (result ->> 'versionId')::uuid
      from guardrail_results
      where kind = 'LISTING_BUNDLE_DRAFT'
    )
  ),
  2::bigint,
  'inactive Product does not erase the historical recipe components'
);

insert into guardrail_results
select
  'BATCH_ARCHIVED',
  api.archive_product_batch(
    '00000000-0000-4000-8000-000000000054',
    '054-BATCH-ARCHIVE',
    (
      select (result ->> 'batchId')::uuid
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    ),
    (
      select batch.row_version
      from catalog.product_batches batch
      where batch.id = (
        select (result ->> 'batchId')::uuid
        from guardrail_results
        where kind = 'BATCH_STANDARD'
      )
    ),
    'Archived stocktake and reversal fixture',
    null
  );

reset role;

set local role authenticated;

select throws_ok(
  format(
    $sql$
      select api.post_receipt(
        '00000000-0000-4000-8000-000000000054',
        '054-RECEIPT-ARCHIVED',
        'RCV-ARCHIVED-054',
        '2026-07-23 10:35:00+07',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', %L,
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )),
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    ),
    (
      select result ->> 'batchId'
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    )
  ),
  'P0001',
  'RECEIPT_BATCH_NOT_ACTIVE',
  'Receipt rejects an archived Batch at the trusted command boundary'
);
select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000054',
        %L::uuid,
        %s,
        '2026-07-23 10:36:00+07',
        'LEGACY-GUARD-054',
        'Archived Batch must fail.',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', %L,
          'bucketCode', 'QUARANTINE',
          'quantity', 1,
          'sourceLineRef', 'ARCHIVED-BATCH'
        )),
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'cutoverId'
      from guardrail_results
      where kind = 'OPENING_CREATED'
    ),
    (
      select cutover.row_version
      from operations.opening_balance_cutovers cutover
      where cutover.id = (
        select (result ->> 'cutoverId')::uuid
        from guardrail_results
        where kind = 'OPENING_CREATED'
      )
    ),
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    ),
    (
      select result ->> 'batchId'
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    )
  ),
  'P0001',
  'OPENING_BALANCE_BATCH_ARCHIVED',
  'Opening Balance draft rejects an archived Batch'
);

reset role;

select is(
  (
    select count(*)
    from operations.resolve_stocktake_scope(
      '00000000-0000-4000-8000-000000000054',
      jsonb_build_object(
        'mode', 'BATCHES',
        'batchIds', jsonb_build_array(
          (
            select result ->> 'batchId'
            from guardrail_results
            where kind = 'BATCH_STANDARD'
          )
        ),
        'bucketCodes', jsonb_build_array('SELLABLE'),
        'includeInactiveWithBalance', true,
        'includeBlockedBatches', false,
        'includeExpiredBatches', false,
        'includeZeroSystemBalance', false
      ),
      '2026-07-23',
      (
        select max(entry.ledger_seq)
        from inventory.stock_ledger_entries entry
        where entry.organization_id =
              '00000000-0000-4000-8000-000000000054'
      )
    )
    where system_qty_at_snapshot = 10
  ),
  1::bigint,
  'Stocktake can include an archived Batch with physical balance'
);
select is(
  (
    select count(*)
    from operations.resolve_stocktake_scope(
      '00000000-0000-4000-8000-000000000054',
      jsonb_build_object(
        'mode', 'BATCHES',
        'batchIds', jsonb_build_array(
          (
            select result ->> 'batchId'
            from guardrail_results
            where kind = 'BATCH_STANDARD'
          )
        ),
        'bucketCodes', jsonb_build_array('SELLABLE'),
        'includeInactiveWithBalance', false,
        'includeBlockedBatches', true,
        'includeExpiredBatches', true,
        'includeZeroSystemBalance', true
      ),
      '2026-07-23',
      (
        select max(entry.ledger_seq)
        from inventory.stock_ledger_entries entry
        where entry.organization_id =
              '00000000-0000-4000-8000-000000000054'
      )
    )
  ),
  0::bigint,
  'blocked inclusion no longer leaks archived Batch into Stocktake scope'
);

set local role authenticated;

insert into guardrail_results
select
  'REVERSAL_PREVIEW',
  api.preview_stock_transaction_reversal(
    '00000000-0000-4000-8000-000000000054',
    (
      select (result ->> 'transactionId')::uuid
      from guardrail_results
      where kind = 'RECEIPT'
    )
  );

insert into guardrail_results
select
  'REVERSAL',
  api.reverse_stock_transaction(
    '00000000-0000-4000-8000-000000000054',
    '054-REVERSE-ARCHIVED-MASTER',
    (
      select (result ->> 'transactionId')::uuid
      from guardrail_results
      where kind = 'RECEIPT'
    ),
    (
      select result ->> 'basisHash'
      from guardrail_results
      where kind = 'REVERSAL_PREVIEW'
    ),
    true,
    'Historical receipt reversal after Batch archival.',
    '{"fixture":"guardrails-054"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from guardrail_results
    where kind = 'REVERSAL'
  ),
  'REVERSED',
  'historical transaction remains exactly reversible after Batch archival'
);
select is(
  (
    select count(*)
    from api.product_batch_master master
    where master.batch_id = (
      select (result ->> 'batchId')::uuid
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    )
      and master.lifecycle_status_code = 'ARCHIVED'
      and master.has_authoritative_history
  ),
  1::bigint,
  'archived Batch remains readable with authoritative history'
);
select is(
  (
    select count(*)
    from inventory.stock_batch_balances balance
    full join (
      select
        entry.organization_id,
        entry.batch_id,
        coalesce(sum(entry.quantity_delta)
          filter (where entry.bucket_code = 'SELLABLE'), 0)::bigint
          as sellable_qty,
        coalesce(sum(entry.quantity_delta)
          filter (where entry.bucket_code = 'QUARANTINE'), 0)::bigint
          as quarantine_qty,
        coalesce(sum(entry.quantity_delta)
          filter (where entry.bucket_code = 'DAMAGED'), 0)::bigint
          as damaged_qty
      from inventory.stock_ledger_entries entry
      where entry.organization_id =
            '00000000-0000-4000-8000-000000000054'
      group by entry.organization_id, entry.batch_id
    ) ledger
      on ledger.organization_id = balance.organization_id
     and ledger.batch_id = balance.batch_id
    where coalesce(balance.organization_id, ledger.organization_id) =
          '00000000-0000-4000-8000-000000000054'
      and (
        balance.batch_id is null
        or ledger.batch_id is null
        or balance.sellable_qty <> ledger.sellable_qty
        or balance.quarantine_qty <> ledger.quarantine_qty
        or balance.damaged_qty <> ledger.damaged_qty
      )
  ),
  0::bigint,
  'Batch projection remains consistent with the append-only ledger'
);

reset role;

select is(
  (
    select count(*)
    from operations.resolve_stocktake_scope(
      '00000000-0000-4000-8000-000000000054',
      jsonb_build_object(
        'mode', 'BATCHES',
        'batchIds', jsonb_build_array(
          (
            select result ->> 'batchId'
            from guardrail_results
            where kind = 'BATCH_STANDARD'
          )
        ),
        'bucketCodes', jsonb_build_array('SELLABLE'),
        'includeInactiveWithBalance', true,
        'includeBlockedBatches', true,
        'includeExpiredBatches', true,
        'includeZeroSystemBalance', true
      ),
      '2026-07-23',
      (
        select max(entry.ledger_seq)
        from inventory.stock_ledger_entries entry
        where entry.organization_id =
              '00000000-0000-4000-8000-000000000054'
      )
    )
  ),
  0::bigint,
  'archived zero-balance Batch is excluded from a new Stocktake scope'
);

set local role authenticated;

insert into guardrail_results
select
  'PRODUCT_MAIN_ARCHIVED',
  api.archive_product(
    '00000000-0000-4000-8000-000000000054',
    '054-PRODUCT-MAIN-ARCHIVE',
    (
      select (result ->> 'productId')::uuid
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    ),
    1,
    'Inactive transaction and return allocation fixture'
  );

select throws_ok(
  format(
    $sql$
      select api.post_receipt(
        '00000000-0000-4000-8000-000000000054',
        '054-RECEIPT-INACTIVE',
        'RCV-INACTIVE-054',
        '2026-07-23 11:00:00+07',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', %L,
          'quantity', 1,
          'sourceLineRef', 'LINE-1'
        )),
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    ),
    (
      select result ->> 'batchId'
      from guardrail_results
      where kind = 'BATCH_STANDARD'
    )
  ),
  'P0001',
  'RECEIPT_PRODUCT_INACTIVE',
  'inactive Product is rejected for a new Receipt'
);
select throws_ok(
  format(
    $sql$
      select api.save_opening_balance_cutover_draft(
        '00000000-0000-4000-8000-000000000054',
        %L::uuid,
        %s,
        '2026-07-23 11:05:00+07',
        'LEGACY-GUARD-054',
        'Inactive Product must fail.',
        jsonb_build_array(jsonb_build_object(
          'productId', %L,
          'batchId', '95420000-0000-4000-8000-000000000002',
          'bucketCode', 'QUARANTINE',
          'quantity', 1,
          'batchIdentityVerified', false,
          'exceptionReference', 'UNKNOWN-GUARD-054',
          'sourceLineRef', 'INACTIVE-PRODUCT'
        )),
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'cutoverId'
      from guardrail_results
      where kind = 'OPENING_CREATED'
    ),
    (
      select cutover.row_version
      from operations.opening_balance_cutovers cutover
      where cutover.id = (
        select (result ->> 'cutoverId')::uuid
        from guardrail_results
        where kind = 'OPENING_CREATED'
      )
    ),
    (
      select result ->> 'productId'
      from guardrail_results
      where kind = 'PRODUCT_MAIN'
    )
  ),
  'P0001',
  'OPENING_BALANCE_PRODUCT_INACTIVE',
  'Opening Balance draft rejects an inactive Product'
);
select isnt(
  (
    select master.is_fefo_eligible
    from api.product_batch_master master
    where master.batch_id =
          '95420000-0000-4000-8000-000000000001'
  ),
  true,
  'return-domain stock under an archived Product is not allocatable'
);
select is(
  (
    select count(*)
    from api.product_batch_master master
    where master.batch_id =
          '95420000-0000-4000-8000-000000000001'
      and not master.product_is_active
      and master.batch_kind_code = 'RETURN'
  ),
  1::bigint,
  'return-domain Batch under an archived Product remains historically readable'
);

reset role;

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);

insert into guardrail_results
select
  'HISTORICAL_RETURN_RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001',
    '054-HISTORICAL-RETURN-RESERVE',
    'SHOPEE',
    'RESERVE',
    '054-HISTORICAL-RETURN-RESERVE-EVENT',
    '054-HISTORICAL-RETURN-ORDER',
    '2026-07-23 12:00:00+07',
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 1,
        'sourceLineRef', 'HISTORICAL-RETURN-LINE-1'
      )
    ),
    'Reserve historical return fixture.',
    '{"fixture":"guardrails-054"}'::jsonb
  );

insert into guardrail_results
select
  'HISTORICAL_RETURN_SHIP',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001',
    '054-HISTORICAL-RETURN-SHIP',
    'SHOPEE',
    'SHIP',
    '054-HISTORICAL-RETURN-SHIP-EVENT',
    '054-HISTORICAL-RETURN-ORDER',
    '2026-07-23 12:05:00+07',
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 1,
        'sourceLineRef', 'HISTORICAL-RETURN-LINE-1'
      )
    ),
    'Ship historical return fixture.',
    '{"fixture":"guardrails-054"}'::jsonb
  );

insert into guardrail_results
select
  'HISTORICAL_RETURN_EXPECTED',
  api.create_expected_return(
    '00000000-0000-4000-8000-000000000001',
    '054-HISTORICAL-RETURN-EXPECTED',
    'SHOPEE',
    '054-HISTORICAL-RETURN',
    '054-HISTORICAL-RETURN-ORDER',
    '2026-07-23 12:10:00+07',
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 1,
        'sourceLineRef', 'HISTORICAL-RETURN-LINE-1'
      )
    ),
    'RETURN_REQUESTED',
    'Historical return before Product archival.',
    '{"fixture":"guardrails-054"}'::jsonb
  );

insert into guardrail_results
select
  'HISTORICAL_RETURN_RECEIPT',
  api.confirm_return_receipt(
    '00000000-0000-4000-8000-000000000001',
    '054-HISTORICAL-RETURN-RECEIPT',
    '054-HISTORICAL-RETURN',
    '054-HISTORICAL-RETURN-RECEIPT-REF',
    '2026-07-23 12:15:00+07',
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
          (
            select item.id::text
            from operations.return_items item
            join operations.returns return_header
              on return_header.id = item.return_id
            where return_header.external_return_ref =
                  '054-HISTORICAL-RETURN'
          ),
        'marketplaceShipAllocationId',
          (
            select allocation.id::text
            from operations.marketplace_ship_allocations allocation
            join operations.marketplace_events event
              on event.id = allocation.event_id
            where event.external_event_ref =
                  '054-HISTORICAL-RETURN-SHIP-EVENT'
          ),
        'quantity', 1,
        'sourceLineRef', 'HISTORICAL-RETURN-RECEIPT-LINE-1'
      )
    ),
    'Physical return received before Product archival.',
    '{"fixture":"guardrails-054"}'::jsonb
  );

insert into guardrail_results
select
  'HISTORICAL_RETURN_PRODUCT_ARCHIVED',
  api.archive_product(
    '00000000-0000-4000-8000-000000000001',
    '054-HISTORICAL-RETURN-PRODUCT-ARCHIVE',
    '30000000-0000-4000-8000-000000000001',
    (
      select product.row_version
      from catalog.products product
      where product.id =
            '30000000-0000-4000-8000-000000000001'
    ),
    'Archive after the historical sale and physical return.'
  );

insert into guardrail_results
select
  'HISTORICAL_RETURN_INSPECTION',
  api.inspect_return(
    '00000000-0000-4000-8000-000000000001',
    '054-HISTORICAL-RETURN-INSPECTION',
    '054-HISTORICAL-RETURN',
    '054-HISTORICAL-RETURN-INSPECTION-REF',
    '2026-07-23 12:20:00+07',
    jsonb_build_array(
      jsonb_build_object(
        'receiptLineId',
          (
            select line.id::text
            from operations.return_receipt_lines line
            join operations.return_receipts receipt
              on receipt.id = line.receipt_id
            where receipt.receipt_ref =
                  '054-HISTORICAL-RETURN-RECEIPT-REF'
          ),
        'sellableQuantity', 1,
        'damagedQuantity', 0,
        'sourceLineRef', 'HISTORICAL-RETURN-INSPECTION-LINE-1'
      )
    ),
    'Complete historical return after Product archival.',
    '{"fixture":"guardrails-054"}'::jsonb
  );

select is(
  (
    select result ->> 'stockEffectCode'
    from guardrail_results
    where kind = 'HISTORICAL_RETURN_INSPECTION'
  ),
  'SELLABLE_INBOUND',
  'historical sellable return completes after Product archival'
);
select is(
  (
    select count(*)
    from operations.return_inspection_allocations allocation
    join catalog.product_batches batch
      on batch.id = allocation.return_batch_id
    where allocation.inspection_id = (
      select inspection.id
      from operations.return_inspections inspection
      where inspection.inspection_ref =
            '054-HISTORICAL-RETURN-INSPECTION-REF'
    )
      and allocation.condition_code = 'SELLABLE'
      and batch.batch_kind_code = 'RETURN'
      and batch.id <> (
        select receipt_line.source_batch_id
        from operations.return_receipt_lines receipt_line
        join operations.return_receipts receipt
          on receipt.id = receipt_line.receipt_id
        where receipt.receipt_ref =
              '054-HISTORICAL-RETURN-RECEIPT-REF'
      )
  ),
  1::bigint,
  'historical sellable return uses a new RETURN Batch, not the source Batch'
);
select is(
  (
    select count(*)
    from api.product_batch_master master
    join operations.return_inspection_allocations allocation
      on allocation.return_batch_id = master.batch_id
    join operations.return_inspections inspection
      on inspection.id = allocation.inspection_id
    where inspection.inspection_ref =
          '054-HISTORICAL-RETURN-INSPECTION-REF'
      and not master.product_is_active
      and not master.is_fefo_eligible
      and master.sellable_qty = 1
  ),
  1::bigint,
  'return stock for archived Product stays readable but non-allocatable'
);

select * from finish();
rollback;
