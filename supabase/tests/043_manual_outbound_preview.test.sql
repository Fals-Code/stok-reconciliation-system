begin;

create extension if not exists pgtap with schema extensions;

select plan(65);

-- Contract and privilege surface.
select function_returns(
  'inventory',
  'preview_manual_outbound_core',
  array[
    'uuid', 'text', 'timestamptz', 'text',
    'jsonb', 'text', 'jsonb', 'boolean'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'preview_manual_outbound',
  array[
    'uuid', 'text', 'timestamptz', 'text',
    'jsonb', 'text', 'jsonb'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'post_manual_outbound',
  array[
    'uuid', 'text', 'text', 'timestamptz', 'text',
    'jsonb', 'text', 'boolean', 'text', 'jsonb'
  ]::text[],
  'jsonb'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.preview_manual_outbound(uuid,text,timestamptz,text,jsonb,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot preview manual outbound'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.preview_manual_outbound(uuid,text,timestamptz,text,jsonb,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may preview manual outbound'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.post_manual_outbound(uuid,text,text,timestamptz,text,jsonb,text,boolean,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot call confirmed manual outbound posting'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.post_manual_outbound(uuid,text,text,timestamptz,text,jsonb,text,boolean,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may call confirmed manual outbound posting'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'api.post_manual_outbound(uuid,text,text,timestamptz,text,jsonb,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated role cannot bypass preview through the legacy signature'
);

select ok(
  not has_function_privilege(
    'service_role',
    'api.post_manual_outbound(uuid,text,text,timestamptz,text,jsonb,text,jsonb)',
    'EXECUTE'
  ),
  'service role cannot bypass preview through the legacy signature'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'inventory.preview_manual_outbound_core(uuid,text,timestamptz,text,jsonb,text,jsonb,boolean)',
    'EXECUTE'
  ),
  'authenticated role cannot execute the internal preview core'
);

-- Authenticated Admin fixture.
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
)
values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  '99000000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.manual.outbound.preview@glowlab.invalid',
  '2026-07-18 14:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-18 14:00:00+07'::timestamptz,
  '2026-07-18 14:00:00+07'::timestamptz,
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
)
values (
  '99000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Manual Outbound Preview Admin',
  'PGTAP-MAN-PREVIEW',
  'ADMIN',
  true
);

insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active,
  created_at,
  created_by
)
values (
  '00000000-0000-4000-8000-000000000009'::uuid,
  'PGTAP_MANUAL_PREVIEW_OTHER',
  'pgTAP Manual Preview Other Organization',
  'Asia/Jakarta',
  true,
  '2026-07-18 14:00:00+07'::timestamptz,
  null
);

create temp table manual_outbound_preview_baseline (
  transaction_count bigint not null,
  ledger_count bigint not null,
  outbound_count bigint not null,
  idempotency_count bigint not null,
  ser_product_sellable bigint not null,
  ser_product_reserved bigint not null,
  ser_batch_1_sellable bigint not null,
  ser_batch_2_sellable bigint not null,
  cln_product_sellable bigint not null,
  cln_batch_sellable bigint not null
) on commit drop;

insert into manual_outbound_preview_baseline
select
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select count(*)
    from operations.manual_outbounds
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select count(*)
    from inventory.idempotency_commands
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select sellable_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select reserved_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select sellable_qty
    from inventory.stock_batch_balances
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select sellable_qty
    from inventory.stock_batch_balances
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and batch_id =
        '40000000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select sellable_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select sellable_qty
    from inventory.stock_batch_balances
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and batch_id =
        '40000000-0000-4000-8000-000000000003'::uuid
  );

create temp table manual_outbound_preview_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select on manual_outbound_preview_baseline to authenticated;
grant select, insert, update on manual_outbound_preview_results to authenticated;

select set_config(
  'request.jwt.claim.sub',
  '99000000-0000-4000-8000-000000000001',
  true
);

select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '99000000-0000-4000-8000-000000000001',
    'role',
    'authenticated',
    'email',
    'pgtap.manual.outbound.preview@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

-- Stock-neutral previews.
insert into manual_outbound_preview_results (kind, result)
select
  'SPLIT',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-SPLIT-001',
    '2026-07-18 14:10:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        8,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Preview split FEFO.',
    '{"test":true,"reference":"OFFLINE-PREVIEW-001"}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'SPLIT_REPEAT',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-SPLIT-001',
    '2026-07-18 14:10:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        8,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Preview split FEFO.',
    '{"test":true,"reference":"OFFLINE-PREVIEW-001"}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'ONE_BATCH',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-ONE-BATCH-001',
    '2026-07-18 14:11:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000003',
        'quantity',
        1,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Preview satu batch.',
    '{"test":true,"reference":"OFFLINE-ONE-001"}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'MULTI_PRODUCT',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-MULTI-001',
    '2026-07-18 14:12:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        2,
        'sourceLineRef',
        'LINE-1'
      ),
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000002',
        'quantity',
        3,
        'sourceLineRef',
        'LINE-2'
      )
    ),
    'Preview multi produk.',
    '{"test":true,"reference":"OFFLINE-MULTI-001"}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'BONUS_NO_REFERENCE',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-BONUS-NO-REF-001',
    '2026-07-18 14:13:00+07'::timestamptz,
    'BONUS',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000003',
        'quantity',
        1,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Bonus dengan catatan tetapi tanpa referensi.',
    '{"test":true}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'BONUS_NO_NOTE',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-BONUS-NO-NOTE-001',
    '2026-07-18 14:14:00+07'::timestamptz,
    'BONUS',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000003',
        'quantity',
        1,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    null,
    '{"test":true,"reference":"CAMPAIGN-BONUS-001"}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'BONUS_READY',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-BONUS-READY-001',
    '2026-07-18 14:15:00+07'::timestamptz,
    'BONUS',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000003',
        'quantity',
        1,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Bonus campaign fixture.',
    '{"test":true,"reference":"CAMPAIGN-BONUS-001"}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'INSUFFICIENT_AVAILABLE',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-INSUFFICIENT-001',
    '2026-07-18 14:16:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000003',
        'quantity',
        999,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Preview stok tidak cukup.',
    '{"test":true,"reference":"OFFLINE-INSUFFICIENT-001"}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'UNKNOWN_PRODUCT',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-UNKNOWN-001',
    '2026-07-18 14:17:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '39999999-9999-4999-8999-999999999999',
        'quantity',
        1,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Preview produk tidak dikenal.',
    '{"test":true,"reference":"OFFLINE-UNKNOWN-001"}'::jsonb
  );

select throws_ok(
  $sql$
    select api.preview_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'MANUAL-PREVIEW-DUPLICATE-PRODUCT-001',
      '2026-07-18 14:18:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000003',
          'quantity',
          1,
          'sourceLineRef',
          'LINE-1'
        ),
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000003',
          'quantity',
          1,
          'sourceLineRef',
          'LINE-2'
        )
      ),
      'Duplicate product fixture.',
      '{"test":true,"reference":"OFFLINE-DUPLICATE-001"}'::jsonb
    )
  $sql$,
  'P0001',
  'OUTBOUND_DUPLICATE_PRODUCT_LINE',
  'preview rejects duplicate product lines'
);

select throws_ok(
  $sql$
    select api.preview_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'MANUAL-PREVIEW-INVALID-QUANTITY-001',
      '2026-07-18 14:19:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000003',
          'quantity',
          0,
          'sourceLineRef',
          'LINE-1'
        )
      ),
      'Invalid quantity fixture.',
      '{"test":true,"reference":"OFFLINE-INVALID-001"}'::jsonb
    )
  $sql$,
  'P0001',
  'OUTBOUND_LINE_INVALID',
  'preview rejects a non-positive quantity'
);

select throws_ok(
  $sql$
    select api.preview_manual_outbound(
      '00000000-0000-4000-8000-000000000009'::uuid,
      'MANUAL-PREVIEW-CROSS-ORG-001',
      '2026-07-18 14:20:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000003',
          'quantity',
          1,
          'sourceLineRef',
          'LINE-1'
        )
      ),
      'Cross organization fixture.',
      '{"test":true,"reference":"OFFLINE-CROSS-ORG-001"}'::jsonb
    )
  $sql$,
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'authenticated Admin cannot preview another organization'
);

select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MANUAL-PREVIEW-CONFIRMATION-001',
      'MANUAL-PREVIEW-CONFIRMATION-001',
      '2026-07-18 14:21:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000003',
          'quantity',
          1,
          'sourceLineRef',
          'LINE-1'
        )
      ),
      repeat('a', 64),
      false,
      'Confirmation fixture.',
      '{"test":true,"reference":"OFFLINE-CONFIRM-001"}'::jsonb
    )
  $sql$,
  'P0001',
  'MANUAL_OUTBOUND_CONFIRMATION_REQUIRED',
  'posting requires explicit final confirmation'
);

select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MANUAL-PREVIEW-HASH-001',
      'MANUAL-PREVIEW-HASH-001',
      '2026-07-18 14:22:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000003',
          'quantity',
          1,
          'sourceLineRef',
          'LINE-1'
        )
      ),
      'invalid-hash',
      true,
      'Hash fixture.',
      '{"test":true,"reference":"OFFLINE-HASH-001"}'::jsonb
    )
  $sql$,
  'P0001',
  'MANUAL_OUTBOUND_PREVIEW_HASH_INVALID',
  'posting requires a SHA-256 preview basis hash'
);

reset role;

-- Preview response and stock-neutrality assertions.
select is(
  (
    select result ->> 'status'
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  'PREVIEW_READY',
  'split FEFO preview is ready'
);

select is(
  (
    select result ->> 'eligible'
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  'true',
  'split FEFO preview is eligible'
);

select is(
  (
    select length(result ->> 'basisHash')
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  64,
  'preview returns a SHA-256 basis hash'
);

select is(
  (
    select result ->> 'allocationCount'
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  '2',
  'split preview creates two FEFO allocations'
);

select is(
  (
    select result -> 'allocations' -> 0 ->> 'batchCode'
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  'SER-2608-A',
  'split preview chooses the earliest expiry batch first'
);

select is(
  (
    select result -> 'allocations' -> 0 ->> 'quantity'
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  (
    select ser_batch_1_sellable::text
    from manual_outbound_preview_baseline
  ),
  'first preview allocation exhausts the earliest FEFO batch'
);

select is(
  (
    select result -> 'allocations' -> 1 ->> 'batchCode'
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  'SER-2612-B',
  'split preview continues into the next FEFO batch'
);

select is(
  (
    select result -> 'products' -> 0 ->> 'currentSellable'
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  (
    select ser_product_sellable::text
    from manual_outbound_preview_baseline
  ),
  'preview reports authoritative current product sellable stock'
);

select is(
  (
    select result -> 'products' -> 0 ->> 'resultingSellable'
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  (
    select (ser_product_sellable - 8)::text
    from manual_outbound_preview_baseline
  ),
  'preview reports resulting product sellable stock'
);

select is(
  (
    select result -> 'products' -> 0 ->> 'currentReserved'
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  (
    select ser_product_reserved::text
    from manual_outbound_preview_baseline
  ),
  'preview preserves and reports product reservations'
);

select is(
  (
    select result ->> 'basisHash'
    from manual_outbound_preview_results
    where kind = 'SPLIT'
  ),
  (
    select result ->> 'basisHash'
    from manual_outbound_preview_results
    where kind = 'SPLIT_REPEAT'
  ),
  'unchanged request and stock basis produce a stable hash'
);

select is(
  (
    select result ->> 'allocationCount'
    from manual_outbound_preview_results
    where kind = 'ONE_BATCH'
  ),
  '1',
  'single-batch request previews one allocation'
);

select is(
  (
    select result ->> 'lineCount'
    from manual_outbound_preview_results
    where kind = 'MULTI_PRODUCT'
  ),
  '2',
  'multi-product preview retains both product lines'
);

select is(
  (
    select result ->> 'totalRequestedQuantity'
    from manual_outbound_preview_results
    where kind = 'MULTI_PRODUCT'
  ),
  '5',
  'multi-product preview totals all requested quantities'
);

select is(
  (
    select result ->> 'status'
    from manual_outbound_preview_results
    where kind = 'BONUS_NO_REFERENCE'
  ),
  'BLOCKED',
  'bonus preview without a reference is blocked'
);

select ok(
  exists (
    select 1
    from manual_outbound_preview_results result_row
    cross join lateral
      jsonb_array_elements(result_row.result -> 'blockers') blocker
    where result_row.kind = 'BONUS_NO_REFERENCE'
      and blocker ->> 'code' =
        'OUTBOUND_REASON_REFERENCE_REQUIRED'
  ),
  'bonus preview exposes a structured missing-reference blocker'
);

select ok(
  exists (
    select 1
    from manual_outbound_preview_results result_row
    cross join lateral
      jsonb_array_elements(result_row.result -> 'blockers') blocker
    where result_row.kind = 'BONUS_NO_NOTE'
      and blocker ->> 'code' = 'OUTBOUND_NOTE_REQUIRED'
  ),
  'configured reason note requirement is enforced during preview'
);

select is(
  (
    select result ->> 'status'
    from manual_outbound_preview_results
    where kind = 'BONUS_READY'
  ),
  'PREVIEW_READY',
  'bonus with note and reference is previewable'
);

select ok(
  exists (
    select 1
    from manual_outbound_preview_results result_row
    cross join lateral
      jsonb_array_elements(result_row.result -> 'blockers') blocker
    where result_row.kind = 'INSUFFICIENT_AVAILABLE'
      and blocker ->> 'code' = 'INSUFFICIENT_AVAILABLE_STOCK'
  ),
  'insufficient available stock is returned as a structured blocker'
);

select ok(
  exists (
    select 1
    from manual_outbound_preview_results result_row
    cross join lateral
      jsonb_array_elements(result_row.result -> 'blockers') blocker
    where result_row.kind = 'UNKNOWN_PRODUCT'
      and blocker ->> 'code' = 'OUTBOUND_PRODUCT_NOT_FOUND'
  ),
  'unknown product is returned as a structured blocker'
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
    from manual_outbound_preview_baseline
  ),
  'preview creates no stock transaction'
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
    from manual_outbound_preview_baseline
  ),
  'preview creates no ledger entry'
);

select is(
  (
    select count(*)
    from operations.manual_outbounds
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select outbound_count
    from manual_outbound_preview_baseline
  ),
  'preview creates no outbound document'
);

select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select idempotency_count
    from manual_outbound_preview_baseline
  ),
  'preview creates no idempotency command'
);

select is(
  (
    select sellable_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select ser_product_sellable
    from manual_outbound_preview_baseline
  ),
  'preview does not change the product projection'
);

select is(
  (
    select sellable_qty
    from inventory.stock_batch_balances
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select ser_batch_1_sellable
    from manual_outbound_preview_baseline
  ),
  'preview does not change the batch projection'
);

-- Blocked batch and safety-buffer exclusions.
update catalog.product_batches
set status_code = 'BLOCKED',
    block_reason = 'PGTAP preview exclusion'
where id = '40000000-0000-4000-8000-000000000001'::uuid;

set local role authenticated;

insert into manual_outbound_preview_results (kind, result)
select
  'BLOCKED_BATCH_EXCLUDED',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-BLOCKED-BATCH-001',
    '2026-07-18 14:30:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        8,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Blocked batch exclusion fixture.',
    '{"test":true,"reference":"OFFLINE-BLOCKED-001"}'::jsonb
  );

reset role;

update catalog.product_batches
set status_code = 'ACTIVE',
    block_reason = null
where id = '40000000-0000-4000-8000-000000000001'::uuid;

select is(
  (
    select result -> 'allocations' -> 0 ->> 'batchCode'
    from manual_outbound_preview_results
    where kind = 'BLOCKED_BATCH_EXCLUDED'
  ),
  'SER-2612-B',
  'blocked batch is excluded from FEFO preview'
);

select ok(
  not exists (
    select 1
    from manual_outbound_preview_results result_row
    cross join lateral
      jsonb_array_elements(result_row.result -> 'allocations') allocation
    where result_row.kind = 'BLOCKED_BATCH_EXCLUDED'
      and allocation ->> 'batchCode' = 'SER-2608-A'
  ),
  'blocked batch never appears in preview allocations'
);

update app.settings
set value = '200'::jsonb
where organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and key = 'expiry.safety_buffer_days'
  and effective_to is null;

set local role authenticated;

insert into manual_outbound_preview_results (kind, result)
select
  'SAFETY_BUFFER_BLOCKED',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-SAFETY-BUFFER-001',
    '2026-07-18 14:31:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000002',
        'quantity',
        1,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Safety buffer preview fixture.',
    '{"test":true,"reference":"OFFLINE-SAFETY-001"}'::jsonb
  );

reset role;

update app.settings
set value = '0'::jsonb
where organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and key = 'expiry.safety_buffer_days'
  and effective_to is null;

select ok(
  exists (
    select 1
    from manual_outbound_preview_results result_row
    cross join lateral
      jsonb_array_elements(result_row.result -> 'blockers') blocker
    where result_row.kind = 'SAFETY_BUFFER_BLOCKED'
      and blocker ->> 'code' = 'INSUFFICIENT_FEFO_STOCK'
  ),
  'expiry safety buffer can block otherwise sellable stock'
);

-- Exact-hash commit and idempotency.
set local role authenticated;

-- Refresh preview after the preceding batch-status and safety-buffer
-- mutation tests changed the authoritative basis.
update manual_outbound_preview_results
set result = api.preview_manual_outbound(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'MANUAL-PREVIEW-SPLIT-001',
  '2026-07-18 14:10:00+07'::timestamptz,
  'OFFLINE_SALE',
  jsonb_build_array(
    jsonb_build_object(
      'productId',
      '30000000-0000-4000-8000-000000000001',
      'quantity',
      8,
      'sourceLineRef',
      'LINE-1'
    )
  ),
  'Preview split FEFO.',
  '{"test":true,"reference":"OFFLINE-PREVIEW-001"}'::jsonb
)
where kind = 'SPLIT';

insert into manual_outbound_preview_results (kind, result)
select
  'POSTED',
  api.post_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-MANUAL-PREVIEW-POST-001',
    'MANUAL-PREVIEW-SPLIT-001',
    '2026-07-18 14:10:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        8,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    (
      select result ->> 'basisHash'
      from manual_outbound_preview_results
      where kind = 'SPLIT'
    ),
    true,
    'Preview split FEFO.',
    '{"test":true,"reference":"OFFLINE-PREVIEW-001"}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'REPLAY',
  api.post_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-MANUAL-PREVIEW-POST-001',
    'MANUAL-PREVIEW-SPLIT-001',
    '2026-07-18 14:10:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        8,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    (
      select result ->> 'basisHash'
      from manual_outbound_preview_results
      where kind = 'SPLIT'
    ),
    true,
    'Preview split FEFO.',
    '{"test":true,"reference":"OFFLINE-PREVIEW-001"}'::jsonb
  );

select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MANUAL-PREVIEW-POST-001',
      'MANUAL-PREVIEW-SPLIT-001',
      '2026-07-18 14:10:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000001',
          'quantity',
          9,
          'sourceLineRef',
          'LINE-1'
        )
      ),
      (
        select result ->> 'basisHash'
        from manual_outbound_preview_results
        where kind = 'SPLIT'
      ),
      true,
      'Preview split FEFO.',
      '{"test":true,"reference":"OFFLINE-PREVIEW-001"}'::jsonb
    )
  $sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'same idempotency key cannot represent a different payload'
);

select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MANUAL-PREVIEW-DUPLICATE-SOURCE-001',
      'MANUAL-PREVIEW-SPLIT-001',
      '2026-07-18 14:10:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000001',
          'quantity',
          8,
          'sourceLineRef',
          'LINE-1'
        )
      ),
      (
        select result ->> 'basisHash'
        from manual_outbound_preview_results
        where kind = 'SPLIT'
      ),
      true,
      'Preview split FEFO.',
      '{"test":true,"reference":"OFFLINE-PREVIEW-001"}'::jsonb
    )
  $sql$,
  'P0001',
  'OUTBOUND_SOURCE_ALREADY_POSTED',
  'duplicate source reference cannot create another outbound'
);

reset role;

select is(
  (
    select result ->> 'status'
    from manual_outbound_preview_results
    where kind = 'POSTED'
  ),
  'POSTED',
  'exact preview hash commits successfully'
);

select is(
  (
    select result
    from manual_outbound_preview_results
    where kind = 'REPLAY'
  ),
  (
    select result
    from manual_outbound_preview_results
    where kind = 'POSTED'
  ),
  'idempotent replay returns the original response despite changed stock'
);

select is(
  (
    select count(*)
    from operations.manual_outbounds
    where source_ref = 'MANUAL-PREVIEW-SPLIT-001'
  ),
  1::bigint,
  'confirmed posting creates one outbound header'
);

select is(
  (
    select count(*)
    from operations.manual_outbound_allocations allocation
    join operations.manual_outbounds outbound
      on outbound.id = allocation.outbound_id
    where outbound.source_ref = 'MANUAL-PREVIEW-SPLIT-001'
  ),
  2::bigint,
  'confirmed posting persists the split FEFO allocations'
);

select is(
  (
    select sum(allocation.quantity_allocated)
    from operations.manual_outbound_allocations allocation
    join operations.manual_outbounds outbound
      on outbound.id = allocation.outbound_id
    where outbound.source_ref = 'MANUAL-PREVIEW-SPLIT-001'
  ),
  8::numeric,
  'persisted allocation quantity equals the request'
);

select is(
  (
    select sum(entry.quantity_delta)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot =
      'MANUAL-PREVIEW-SPLIT-001'
  ),
  (-8)::numeric,
  'confirmed posting creates the exact outbound ledger effect'
);

select is(
  (
    select sellable_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select ser_product_sellable - 8
    from manual_outbound_preview_baseline
  ),
  'product projection matches the committed quantity'
);

select is(
  (
    select sellable_qty
    from inventory.stock_batch_balances
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  0::bigint,
  'earliest FEFO batch is exhausted by commit'
);

select is(
  (
    select sellable_qty
    from inventory.stock_batch_balances
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and batch_id =
        '40000000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select ser_batch_2_sellable - (8 - ser_batch_1_sellable)
    from manual_outbound_preview_baseline
  ),
  'second FEFO batch supplies only the remainder'
);

select is(
  (
    select jsonb_agg(
      jsonb_build_object(
        'batchId', allocation ->> 'batchId',
        'quantity', (allocation ->> 'quantity')::bigint
      )
      order by (allocation ->> 'allocationNo')::integer
    )
    from manual_outbound_preview_results result_row
    cross join lateral
      jsonb_array_elements(result_row.result -> 'allocations') allocation
    where result_row.kind = 'SPLIT'
  ),
  (
    select jsonb_agg(
      jsonb_build_object(
        'batchId', allocation ->> 'batchId',
        'quantity', (allocation ->> 'quantity')::bigint
      )
      order by (allocation ->> 'allocationNo')::integer
    )
    from manual_outbound_preview_results result_row
    cross join lateral
      jsonb_array_elements(result_row.result -> 'allocations') allocation
    where result_row.kind = 'POSTED'
  ),
  'successful commit persists the exact preview allocation'
);

select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_MANUAL_OUTBOUND'
      and key = 'PGTAP-MANUAL-PREVIEW-POST-001'
  ),
  1::bigint,
  'replay preserves one idempotency command'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot =
      'MANUAL-PREVIEW-SPLIT-001'
  ),
  2::bigint,
  'replay creates no second ledger effect'
);

-- Stale preview rejection after a real concurrent stock command.
set local role authenticated;

insert into manual_outbound_preview_results (kind, result)
select
  'STALE_TARGET',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-STALE-TARGET-001',
    '2026-07-18 14:40:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000002',
        'quantity',
        1,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Stale target fixture.',
    '{"test":true,"reference":"OFFLINE-STALE-TARGET-001"}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'STALE_MUTATOR_PREVIEW',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-STALE-MUTATOR-001',
    '2026-07-18 14:41:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000002',
        'quantity',
        1,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    'Stale mutator fixture.',
    '{"test":true,"reference":"OFFLINE-STALE-MUTATOR-001"}'::jsonb
  );

insert into manual_outbound_preview_results (kind, result)
select
  'STALE_MUTATOR_POST',
  api.post_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-MANUAL-PREVIEW-STALE-MUTATOR-001',
    'MANUAL-PREVIEW-STALE-MUTATOR-001',
    '2026-07-18 14:41:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000002',
        'quantity',
        1,
        'sourceLineRef',
        'LINE-1'
      )
    ),
    (
      select result ->> 'basisHash'
      from manual_outbound_preview_results
      where kind = 'STALE_MUTATOR_PREVIEW'
    ),
    true,
    'Stale mutator fixture.',
    '{"test":true,"reference":"OFFLINE-STALE-MUTATOR-001"}'::jsonb
  );

select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MANUAL-PREVIEW-STALE-TARGET-001',
      'MANUAL-PREVIEW-STALE-TARGET-001',
      '2026-07-18 14:40:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000002',
          'quantity',
          1,
          'sourceLineRef',
          'LINE-1'
        )
      ),
      (
        select result ->> 'basisHash'
        from manual_outbound_preview_results
        where kind = 'STALE_TARGET'
      ),
      true,
      'Stale target fixture.',
      '{"test":true,"reference":"OFFLINE-STALE-TARGET-001"}'::jsonb
    )
  $sql$,
  'P0001',
  'STALE_MANUAL_OUTBOUND_PREVIEW',
  'commit rejects a preview after authoritative stock basis changes'
);

reset role;

select is(
  (
    select count(*)
    from operations.manual_outbounds
    where source_ref = 'MANUAL-PREVIEW-STALE-TARGET-001'
  ),
  0::bigint,
  'stale rejection creates no outbound header'
);

select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_MANUAL_OUTBOUND'
      and key = 'PGTAP-MANUAL-PREVIEW-STALE-TARGET-001'
  ),
  0::bigint,
  'stale rejection creates no idempotency success'
);

-- Blocked multi-product confirmation remains atomic.
set local role authenticated;

insert into manual_outbound_preview_results (kind, result)
select
  'BLOCKED_MULTI',
  api.preview_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL-PREVIEW-BLOCKED-MULTI-001',
    '2026-07-18 14:50:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000002',
        'quantity',
        1,
        'sourceLineRef',
        'LINE-1'
      ),
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000003',
        'quantity',
        999,
        'sourceLineRef',
        'LINE-2'
      )
    ),
    'Blocked multi-product fixture.',
    '{"test":true,"reference":"OFFLINE-BLOCKED-MULTI-001"}'::jsonb
  );

select throws_ok(
  $sql$
    select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-MANUAL-PREVIEW-BLOCKED-MULTI-001',
      'MANUAL-PREVIEW-BLOCKED-MULTI-001',
      '2026-07-18 14:50:00+07'::timestamptz,
      'OFFLINE_SALE',
      jsonb_build_array(
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000002',
          'quantity',
          1,
          'sourceLineRef',
          'LINE-1'
        ),
        jsonb_build_object(
          'productId',
          '30000000-0000-4000-8000-000000000003',
          'quantity',
          999,
          'sourceLineRef',
          'LINE-2'
        )
      ),
      (
        select result ->> 'basisHash'
        from manual_outbound_preview_results
        where kind = 'BLOCKED_MULTI'
      ),
      true,
      'Blocked multi-product fixture.',
      '{"test":true,"reference":"OFFLINE-BLOCKED-MULTI-001"}'::jsonb
    )
  $sql$,
  'P0001',
  'MANUAL_OUTBOUND_PREVIEW_BLOCKED',
  'blocked multi-product preview cannot be committed'
);

reset role;

select is(
  (
    select count(*)
    from operations.manual_outbounds
    where source_ref = 'MANUAL-PREVIEW-BLOCKED-MULTI-001'
  ),
  0::bigint,
  'blocked multi-product command creates no header'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    join inventory.stock_transactions transaction
      on transaction.id = entry.transaction_id
    where transaction.source_ref_snapshot =
      'MANUAL-PREVIEW-BLOCKED-MULTI-001'
  ),
  0::bigint,
  'blocked multi-product command creates no partial ledger effect'
);

select is(
  (
    select count(*)
    from inventory.idempotency_commands
    where scope = 'POST_MANUAL_OUTBOUND'
      and key = 'PGTAP-MANUAL-PREVIEW-BLOCKED-MULTI-001'
  ),
  0::bigint,
  'blocked multi-product command creates no idempotency success'
);

select * from finish();

rollback;
