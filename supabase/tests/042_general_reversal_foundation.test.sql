begin;

create extension if not exists pgtap with schema extensions;

select plan(59);

-- 1-14: schema, security, and function contract
select has_table(
  'inventory'::name,
  'stock_reversal_applications'::name
);

select has_view(
  'api'::name,
  'stock_reversal_applications'::name
);

select function_returns(
  'api',
  'preview_stock_transaction_reversal',
  array['uuid', 'uuid']::text[],
  'jsonb'
);

select function_returns(
  'api',
  'reverse_stock_transaction',
  array[
    'uuid',
    'text',
    'uuid',
    'text',
    'boolean',
    'text',
    'jsonb'
  ]::text[],
  'jsonb'
);

select has_trigger(
  'inventory'::name,
  'stock_reversal_applications'::name,
  'trg_stock_reversal_applications_validate'::name,
  'reversal applications validate their transaction and entry linkage'
);

select has_trigger(
  'inventory'::name,
  'stock_reversal_applications'::name,
  'trg_stock_reversal_applications_immutable'::name,
  'reversal applications are immutable'
);

select policies_are(
  'inventory',
  'stock_reversal_applications',
  array['stock_reversal_applications_read_current_org']
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.preview_stock_transaction_reversal(uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated Admin may preview a stock transaction reversal'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.reverse_stock_transaction(uuid,text,uuid,text,boolean,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may commit a stock transaction reversal'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.preview_stock_transaction_reversal(uuid,uuid)',
    'EXECUTE'
  ),
  'anonymous users cannot preview a reversal'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.reverse_stock_transaction(uuid,text,uuid,text,boolean,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot commit a reversal'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'inventory.stock_reversal_applications',
    'INSERT'
  ),
  'authenticated users cannot insert reversal applications directly'
);

select matches(
  coalesce(
    (
      select array_to_string(proc.proconfig, ',')
      from pg_proc proc
      where proc.oid =
        'api.reverse_stock_transaction(uuid,text,uuid,text,boolean,text,jsonb)'::regprocedure
    ),
    ''
  ),
  '^search_path=pg_catalog, auth, app, catalog, inventory, operations, extensions$',
  'reversal command has a fixed search_path'
);

select matches(
  coalesce(
    (
      select array_to_string(proc.proconfig, ',')
      from pg_proc proc
      where proc.oid =
        'api.preview_stock_transaction_reversal(uuid,uuid)'::regprocedure
    ),
    ''
  ),
  '^search_path=pg_catalog, auth, app, catalog, inventory, operations, extensions$',
  'reversal preview has a fixed search_path'
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
)
values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94000000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.reversal@glowlab.invalid',
  '2026-07-18 08:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-18 08:00:00+07'::timestamptz,
  '2026-07-18 08:00:00+07'::timestamptz,
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
  '94000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Reversal Admin',
  'PGTAP-REVERSAL',
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
  '00000000-0000-4000-8000-000000000003'::uuid,
  'PGTAP_REVERSAL_OTHER',
  'pgTAP Reversal Other Organization',
  'Asia/Jakarta',
  true,
  '2026-07-18 08:00:00+07'::timestamptz,
  null
);

create temp table reversal_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update
on reversal_results
to authenticated;

create temp table receipt_baseline (
  batch_sellable bigint not null,
  product_sellable bigint not null
) on commit drop;

insert into receipt_baseline
select
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
      and balance.batch_id =
          '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select position.sellable_qty
    from inventory.stock_product_positions position
    where position.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id =
          '30000000-0000-4000-8000-000000000001'::uuid
  );

grant select on receipt_baseline to authenticated;

select set_config(
  'request.jwt.claim.sub',
  '94000000-0000-4000-8000-000000000001',
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
    'sub', '94000000-0000-4000-8000-000000000001',
    'role', 'authenticated',
    'email', 'pgtap.reversal@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

insert into reversal_results (kind, result)
select
  'RECEIPT_POST',
  api.post_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-REVERSAL-RECEIPT-POST-001',
    'PGTAP-REVERSAL-RECEIPT-001',
    '2026-07-18 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'batchId', '40000000-0000-4000-8000-000000000001',
        'quantity', 4,
        'sourceLineRef', 'LINE-1'
      )
    ),
    'Receipt created for reversal coverage.',
    '{"fixture":"general-reversal-receipt"}'::jsonb
  );

insert into reversal_results (kind, result)
select
  'RECEIPT_PREVIEW',
  api.preview_stock_transaction_reversal(
    '00000000-0000-4000-8000-000000000001'::uuid,
    (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    )
  );

reset role;

-- 15-19: preview is eligible and stock-neutral
select ok(
  (
    select (result ->> 'eligible')::boolean
    from reversal_results
    where kind = 'RECEIPT_PREVIEW'
  ),
  'receipt reversal preview is eligible'
);

select is(
  (
    select result ->> 'status'
    from reversal_results
    where kind = 'RECEIPT_PREVIEW'
  ),
  'PREVIEW_READY',
  'eligible receipt preview returns PREVIEW_READY'
);

select is(
  (
    select result ->> 'lineCount'
    from reversal_results
    where kind = 'RECEIPT_PREVIEW'
  ),
  '1',
  'receipt preview contains one ledger line'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.reversal_of_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    )
  ),
  0::bigint,
  'preview creates no reversal transaction'
);

select is(
  (
    select count(*)
    from inventory.stock_reversal_applications application
    where application.original_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    )
  ),
  0::bigint,
  'preview creates no reversal application'
);

set local role authenticated;

insert into reversal_results (kind, result)
select
  'RECEIPT_REVERSAL',
  api.reverse_stock_transaction(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-REVERSAL-RECEIPT-COMMIT-001',
    (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    ),
    (
      select result ->> 'basisHash'
      from reversal_results
      where kind = 'RECEIPT_PREVIEW'
    ),
    true,
    'Koreksi penerimaan duplikat untuk pengujian.',
    '{"fixture":"general-reversal-receipt"}'::jsonb
  );

reset role;

-- 20-27: successful receipt reversal
select is(
  (
    select result ->> 'status'
    from reversal_results
    where kind = 'RECEIPT_REVERSAL'
  ),
  'REVERSED',
  'receipt reversal command succeeds'
);

select is(
  (
    select transaction.reversal_of_transaction_id::text
    from inventory.stock_transactions transaction
    where transaction.id = (
      select (result ->> 'reversalTransactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_REVERSAL'
    )
  ),
  (
    select result ->> 'transactionId'
    from reversal_results
    where kind = 'RECEIPT_POST'
  ),
  'reversal transaction links the original receipt transaction'
);

select is(
  (
    select count(*)
    from inventory.stock_reversal_applications application
    join inventory.stock_ledger_entries original_entry
      on original_entry.id = application.original_entry_id
    join inventory.stock_ledger_entries reversal_entry
      on reversal_entry.id = application.reversal_entry_id
    where application.original_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    )
      and reversal_entry.quantity_delta = -original_entry.quantity_delta
      and reversal_entry.product_id = original_entry.product_id
      and reversal_entry.batch_id = original_entry.batch_id
      and reversal_entry.bucket_code = original_entry.bucket_code
      and application.quantity_applied = abs(original_entry.quantity_delta)
  ),
  1::bigint,
  'receipt reversal entry is the exact opposite of its original entry'
);

select is(
  (
    select count(*)
    from inventory.stock_reversal_applications application
    where application.original_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    )
  ),
  1::bigint,
  'one immutable application links the receipt entries'
);

select is(
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
      and balance.batch_id =
          '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select batch_sellable
    from receipt_baseline
  ),
  'receipt reversal restores the original batch projection'
);

select is(
  (
    select position.sellable_qty
    from inventory.stock_product_positions position
    where position.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id =
          '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select product_sellable
    from receipt_baseline
  ),
  'receipt reversal restores the original product projection'
);

select is(
  (
    select transaction.transaction_type_code
    from inventory.stock_transactions transaction
    where transaction.id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    )
  ),
  'RECEIPT',
  'the original receipt transaction remains unchanged'
);

select throws_ok(
  $sql$
    update inventory.stock_reversal_applications
    set quantity_applied = quantity_applied + 1
    where original_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'reversal applications cannot be updated'
);

set local role authenticated;

insert into reversal_results (kind, result)
select
  'RECEIPT_REVERSAL_REPLAY',
  api.reverse_stock_transaction(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-REVERSAL-RECEIPT-COMMIT-001',
    (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    ),
    (
      select result ->> 'basisHash'
      from reversal_results
      where kind = 'RECEIPT_PREVIEW'
    ),
    true,
    'Koreksi penerimaan duplikat untuk pengujian.',
    '{"fixture":"general-reversal-receipt"}'::jsonb
  );

reset role;

-- 28-32: idempotency and double-reversal protection
select is(
  (
    select result
    from reversal_results
    where kind = 'RECEIPT_REVERSAL_REPLAY'
  ),
  (
    select result
    from reversal_results
    where kind = 'RECEIPT_REVERSAL'
  ),
  'identical reversal replay returns the stored response'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.reversal_of_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    )
  ),
  1::bigint,
  'idempotent replay creates one reversal transaction'
);

set local role authenticated;

select throws_ok(
  $sql$
    select api.reverse_stock_transaction(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-REVERSAL-RECEIPT-COMMIT-001',
      (
        select (result ->> 'transactionId')::uuid
        from reversal_results
        where kind = 'RECEIPT_POST'
      ),
      (
        select result ->> 'basisHash'
        from reversal_results
        where kind = 'RECEIPT_PREVIEW'
      ),
      true,
      'Payload berbeda harus ditolak.',
      '{"fixture":"general-reversal-receipt"}'::jsonb
    )
  $sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'an idempotency key cannot be reused for another reversal payload'
);

insert into reversal_results (kind, result)
select
  'RECEIPT_PREVIEW_AFTER_REVERSAL',
  api.preview_stock_transaction_reversal(
    '00000000-0000-4000-8000-000000000001'::uuid,
    (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RECEIPT_POST'
    )
  );

reset role;

select ok(
  not (
    select (result ->> 'eligible')::boolean
    from reversal_results
    where kind = 'RECEIPT_PREVIEW_AFTER_REVERSAL'
  ),
  'a fully reversed transaction cannot be previewed as eligible again'
);

select ok(
  (
    select result -> 'blockers'
           @> '[{"code":"ORIGINAL_TRANSACTION_ALREADY_REVERSED"}]'::jsonb
    from reversal_results
    where kind = 'RECEIPT_PREVIEW_AFTER_REVERSAL'
  ),
  'double reversal preview exposes the already-reversed blocker'
);

create temp table manual_baseline (
  first_batch_sellable bigint not null,
  second_batch_sellable bigint not null,
  product_sellable bigint not null
) on commit drop;

insert into manual_baseline
select
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.batch_id =
          '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.batch_id =
          '40000000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select position.sellable_qty
    from inventory.stock_product_positions position
    where position.product_id =
          '30000000-0000-4000-8000-000000000001'::uuid
  );

grant select on manual_baseline to authenticated;

set local role authenticated;

insert into reversal_results (kind, result)
select
  'MANUAL_POST',
  api.post_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-REVERSAL-MANUAL-POST-001',
    'PGTAP-REVERSAL-MANUAL-001',
    '2026-07-18 10:00:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 8,
        'sourceLineRef', 'LINE-1'
      )
    ),
    'Manual outbound for reversal coverage.',
    '{"fixture":"general-reversal-manual"}'::jsonb
  );

insert into reversal_results (kind, result)
select
  'MANUAL_PREVIEW',
  api.preview_stock_transaction_reversal(
    '00000000-0000-4000-8000-000000000001'::uuid,
    (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'MANUAL_POST'
    )
  );

insert into reversal_results (kind, result)
select
  'MANUAL_REVERSAL',
  api.reverse_stock_transaction(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-REVERSAL-MANUAL-COMMIT-001',
    (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'MANUAL_POST'
    ),
    (
      select result ->> 'basisHash'
      from reversal_results
      where kind = 'MANUAL_PREVIEW'
    ),
    true,
    'Koreksi outbound manual untuk pengujian.',
    '{"fixture":"general-reversal-manual"}'::jsonb
  );

reset role;

-- 33-42: exact-batch manual outbound reversal
select is(
  (
    select result ->> 'allocationCount'
    from reversal_results
    where kind = 'MANUAL_POST'
  ),
  '2',
  'manual outbound fixture uses two deterministic FEFO batches'
);

select ok(
  (
    select (result ->> 'eligible')::boolean
    from reversal_results
    where kind = 'MANUAL_PREVIEW'
  ),
  'manual outbound reversal preview is eligible'
);

select is(
  (
    select result ->> 'status'
    from reversal_results
    where kind = 'MANUAL_REVERSAL'
  ),
  'REVERSED',
  'manual outbound reversal succeeds'
);

select is(
  (
    select count(*)
    from inventory.stock_reversal_applications application
    join operations.manual_outbound_allocations allocation
      on allocation.ledger_entry_id = application.original_entry_id
    join inventory.stock_ledger_entries reversal_entry
      on reversal_entry.id = application.reversal_entry_id
    where application.original_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'MANUAL_POST'
    )
      and reversal_entry.batch_id = allocation.batch_id
      and reversal_entry.quantity_delta = allocation.quantity_allocated
      and application.quantity_applied = allocation.quantity_allocated
  ),
  2::bigint,
  'manual reversal restores the exact original FEFO allocations'
);

select is(
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.batch_id =
          '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select first_batch_sellable
    from manual_baseline
  ),
  'manual reversal restores the first FEFO batch'
);

select is(
  (
    select balance.sellable_qty
    from inventory.stock_batch_balances balance
    where balance.batch_id =
          '40000000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select second_batch_sellable
    from manual_baseline
  ),
  'manual reversal restores the second FEFO batch'
);

select is(
  (
    select position.sellable_qty
    from inventory.stock_product_positions position
    where position.product_id =
          '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select product_sellable
    from manual_baseline
  ),
  'manual reversal restores the product projection'
);

select is(
  (
    select count(*)
    from operations.manual_outbounds outbound
    where outbound.source_ref = 'PGTAP-REVERSAL-MANUAL-001'
  ),
  1::bigint,
  'reversal does not create or mutate a second manual outbound document'
);

select is(
  (
    select count(*)
    from inventory.stock_reversal_applications application
    where application.original_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'MANUAL_POST'
    )
  ),
  2::bigint,
  'manual split outbound has one application per original ledger entry'
);

select is(
  (
    select transaction.actor_user_id
    from inventory.stock_transactions transaction
    where transaction.id = (
      select (result ->> 'reversalTransactionId')::uuid
      from reversal_results
      where kind = 'MANUAL_REVERSAL'
    )
  ),
  '94000000-0000-4000-8000-000000000001'::uuid,
  'reversal records the authenticated Admin actor'
);

set local role authenticated;

insert into reversal_results (kind, result)
select
  'DEPENDENT_RECEIPT_POST',
  api.post_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-REVERSAL-DEPENDENT-RECEIPT-POST-001',
    'PGTAP-REVERSAL-DEPENDENT-RECEIPT-001',
    '2026-07-18 11:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000002',
        'batchId', '40000000-0000-4000-8000-000000000003',
        'quantity', 3,
        'sourceLineRef', 'LINE-1'
      )
    ),
    'Dependent receipt fixture.',
    '{"fixture":"dependent-receipt"}'::jsonb
  );

insert into reversal_results (kind, result)
select
  'DEPENDENT_OUTBOUND_POST',
  api.post_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-REVERSAL-DEPENDENT-OUTBOUND-POST-001',
    'PGTAP-REVERSAL-DEPENDENT-OUTBOUND-001',
    '2026-07-18 11:05:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000002',
        'quantity', 17,
        'sourceLineRef', 'LINE-1'
      )
    ),
    'Consume stock after the receipt.',
    '{"fixture":"dependent-outbound"}'::jsonb
  );

insert into reversal_results (kind, result)
select
  'DEPENDENT_RECEIPT_PREVIEW',
  api.preview_stock_transaction_reversal(
    '00000000-0000-4000-8000-000000000001'::uuid,
    (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'DEPENDENT_RECEIPT_POST'
    )
  );

reset role;

-- 43-46: dependent stock blocks receipt reversal
select ok(
  not (
    select (result ->> 'eligible')::boolean
    from reversal_results
    where kind = 'DEPENDENT_RECEIPT_PREVIEW'
  ),
  'receipt reversal is blocked after its units have been consumed'
);

select ok(
  (
    select result -> 'blockers'
           @> '[{"code":"REVERSAL_NEGATIVE_BUCKET"}]'::jsonb
    from reversal_results
    where kind = 'DEPENDENT_RECEIPT_PREVIEW'
  ),
  'dependent receipt preview reports a negative-bucket blocker'
);

set local role authenticated;

select throws_ok(
  $sql$
    select api.reverse_stock_transaction(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-REVERSAL-DEPENDENT-RECEIPT-COMMIT-001',
      (
        select (result ->> 'transactionId')::uuid
        from reversal_results
        where kind = 'DEPENDENT_RECEIPT_POST'
      ),
      (
        select result ->> 'basisHash'
        from reversal_results
        where kind = 'DEPENDENT_RECEIPT_PREVIEW'
      ),
      true,
      'Pembalikan yang membuat saldo negatif harus ditolak.',
      '{"fixture":"dependent-receipt"}'::jsonb
    )
  $sql$,
  'P0001',
  'REVERSAL_NEGATIVE_BUCKET',
  'commit rejects a receipt reversal that would make stock negative'
);

reset role;

select is(
  (
    select count(*)
    from inventory.idempotency_commands command
    where command.scope = 'REVERSE_STOCK_TRANSACTION'
      and command.key =
          'PGTAP-REVERSAL-DEPENDENT-RECEIPT-COMMIT-001'
  ),
  0::bigint,
  'blocked reversal leaves no idempotency record'
);

set local role authenticated;

insert into reversal_results (kind, result)
select
  'STALE_RECEIPT_POST',
  api.post_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-REVERSAL-STALE-RECEIPT-POST-001',
    'PGTAP-REVERSAL-STALE-RECEIPT-001',
    '2026-07-18 12:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'batchId', '40000000-0000-4000-8000-000000000002',
        'quantity', 2,
        'sourceLineRef', 'LINE-1'
      )
    ),
    'Stale preview receipt fixture.',
    '{"fixture":"stale-preview"}'::jsonb
  );

insert into reversal_results (kind, result)
select
  'STALE_RECEIPT_PREVIEW',
  api.preview_stock_transaction_reversal(
    '00000000-0000-4000-8000-000000000001'::uuid,
    (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'STALE_RECEIPT_POST'
    )
  );

insert into reversal_results (kind, result)
select
  'STALE_INTERVENING_OUTBOUND',
  api.post_manual_outbound(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-REVERSAL-STALE-OUTBOUND-POST-001',
    'PGTAP-REVERSAL-STALE-OUTBOUND-001',
    '2026-07-18 12:05:00+07'::timestamptz,
    'OFFLINE_SALE',
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000001',
        'quantity', 1,
        'sourceLineRef', 'LINE-1'
      )
    ),
    'Change the preview basis.',
    '{"fixture":"stale-preview"}'::jsonb
  );

select throws_ok(
  $sql$
    select api.reverse_stock_transaction(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-REVERSAL-STALE-COMMIT-001',
      (
        select (result ->> 'transactionId')::uuid
        from reversal_results
        where kind = 'STALE_RECEIPT_POST'
      ),
      (
        select result ->> 'basisHash'
        from reversal_results
        where kind = 'STALE_RECEIPT_PREVIEW'
      ),
      true,
      'Stale preview must not be committed.',
      '{"fixture":"stale-preview"}'::jsonb
    )
  $sql$,
  'P0001',
  'STALE_REVERSAL_PREVIEW',
  'commit rejects a stale reversal preview'
);

reset role;

-- 47-50: stale preview rolls back without effects
select is(
  (
    select count(*)
    from inventory.idempotency_commands command
    where command.scope = 'REVERSE_STOCK_TRANSACTION'
      and command.key = 'PGTAP-REVERSAL-STALE-COMMIT-001'
  ),
  0::bigint,
  'stale preview rejection leaves no idempotency record'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.reversal_of_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'STALE_RECEIPT_POST'
    )
  ),
  0::bigint,
  'stale preview rejection creates no reversal transaction'
);

select is(
  (
    select count(*)
    from inventory.stock_reversal_applications application
    where application.original_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'STALE_RECEIPT_POST'
    )
  ),
  0::bigint,
  'stale preview rejection creates no application rows'
);

set local role authenticated;

insert into reversal_results (kind, result)
select
  'RESERVED_RECEIPT_POST',
  api.post_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-REVERSAL-RESERVED-RECEIPT-POST-001',
    'PGTAP-REVERSAL-RESERVED-RECEIPT-001',
    '2026-07-18 13:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId', '30000000-0000-4000-8000-000000000003',
        'batchId', '40000000-0000-4000-8000-000000000004',
        'quantity', 2,
        'sourceLineRef', 'LINE-1'
      )
    ),
    'Reserved conflict receipt fixture.',
    '{"fixture":"reserved-conflict"}'::jsonb
  );

reset role;

update inventory.stock_product_positions position
set
  reserved_qty = position.sellable_qty,
  version = position.version + 1,
  updated_at = clock_timestamp()
where position.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
      '30000000-0000-4000-8000-000000000003'::uuid;

set local role authenticated;

insert into reversal_results (kind, result)
select
  'RESERVED_RECEIPT_PREVIEW',
  api.preview_stock_transaction_reversal(
    '00000000-0000-4000-8000-000000000001'::uuid,
    (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'RESERVED_RECEIPT_POST'
    )
  );

reset role;

-- 51-52: active reservations block sellable reduction
select ok(
  not (
    select (result ->> 'eligible')::boolean
    from reversal_results
    where kind = 'RESERVED_RECEIPT_PREVIEW'
  ),
  'receipt reversal is blocked when sellable would fall below reserved'
);

select ok(
  (
    select result -> 'blockers'
           @> '[{"code":"REVERSAL_RESERVED_CONFLICT"}]'::jsonb
    from reversal_results
    where kind = 'RESERVED_RECEIPT_PREVIEW'
  ),
  'reserved conflict is explicit in the preview'
);

update inventory.stock_product_positions position
set
  reserved_qty = 0,
  version = position.version + 1,
  updated_at = clock_timestamp()
where position.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
      '30000000-0000-4000-8000-000000000003'::uuid;

-- 53-54: organization isolation
set local role authenticated;

select throws_ok(
  $sql$
    select api.preview_stock_transaction_reversal(
      '00000000-0000-4000-8000-000000000003'::uuid,
      (
        select (result ->> 'transactionId')::uuid
        from reversal_results
        where kind = 'MANUAL_POST'
      )
    )
  $sql$,
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'Admin cannot preview a transaction for another organization'
);

select throws_ok(
  $sql$
    select api.reverse_stock_transaction(
      '00000000-0000-4000-8000-000000000003'::uuid,
      'PGTAP-REVERSAL-CROSS-ORG-001',
      (
        select (result ->> 'transactionId')::uuid
        from reversal_results
        where kind = 'MANUAL_POST'
      ),
      repeat('a', 64),
      true,
      'Cross organization reversal must fail.',
      '{}'::jsonb
    )
  $sql$,
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'Admin cannot commit a reversal for another organization'
);

reset role;

-- 55-58: integrity linkage, projection consistency, and immutability
select is(
  (
    select count(*)
    from inventory.stock_reversal_applications application
    join inventory.stock_ledger_entries original_entry
      on original_entry.id = application.original_entry_id
    join inventory.stock_ledger_entries reversal_entry
      on reversal_entry.id = application.reversal_entry_id
    join inventory.stock_transactions reversal_transaction
      on reversal_transaction.id = application.reversal_transaction_id
    where application.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
      and reversal_transaction.reversal_of_transaction_id =
          application.original_transaction_id
      and reversal_entry.transaction_id =
          application.reversal_transaction_id
      and original_entry.transaction_id =
          application.original_transaction_id
      and reversal_entry.quantity_delta =
          -original_entry.quantity_delta
  ),
  (
    select count(*)
    from inventory.stock_reversal_applications application
    where application.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
  ),
  'every application has valid original and reversing linkage'
);

select is(
  (
    select count(*)
    from inventory.stock_batch_balances balance
    join (
      select
        entry.organization_id,
        entry.product_id,
        entry.batch_id,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'SELLABLE'
          ),
          0
        )::bigint as sellable_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'QUARANTINE'
          ),
          0
        )::bigint as quarantine_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'DAMAGED'
          ),
          0
        )::bigint as damaged_qty
      from inventory.stock_ledger_entries entry
      where entry.organization_id =
            '00000000-0000-4000-8000-000000000001'::uuid
      group by
        entry.organization_id,
        entry.product_id,
        entry.batch_id
    ) ledger
      on ledger.organization_id = balance.organization_id
     and ledger.product_id = balance.product_id
     and ledger.batch_id = balance.batch_id
    where balance.sellable_qty <> ledger.sellable_qty
       or balance.quarantine_qty <> ledger.quarantine_qty
       or balance.damaged_qty <> ledger.damaged_qty
  ),
  0::bigint,
  'batch projections remain consistent with the ledger'
);

select is(
  (
    select count(*)
    from inventory.stock_product_positions position
    join (
      select
        entry.organization_id,
        entry.product_id,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'SELLABLE'
          ),
          0
        )::bigint as sellable_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'QUARANTINE'
          ),
          0
        )::bigint as quarantine_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'DAMAGED'
          ),
          0
        )::bigint as damaged_qty
      from inventory.stock_ledger_entries entry
      where entry.organization_id =
            '00000000-0000-4000-8000-000000000001'::uuid
      group by entry.organization_id, entry.product_id
    ) ledger
      on ledger.organization_id = position.organization_id
     and ledger.product_id = position.product_id
    where position.sellable_qty <> ledger.sellable_qty
       or position.quarantine_qty <> ledger.quarantine_qty
       or position.damaged_qty <> ledger.damaged_qty
  ),
  0::bigint,
  'product projections remain consistent with the ledger'
);

select throws_ok(
  $sql$
    delete from inventory.stock_reversal_applications
    where original_transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'MANUAL_POST'
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'reversal applications cannot be deleted'
);

-- Create a structurally valid second reversing entry, then prove that applying
-- beyond the original quantity is rejected. This fixture is intentionally last
-- because the direct ledger insert is not accompanied by projection mutation.
insert into inventory.idempotency_commands (
  id,
  organization_id,
  scope,
  key,
  request_hash,
  status_code,
  started_at,
  completed_at,
  result_transaction_id,
  response_snapshot,
  error_code,
  expires_at
)
values (
  '95000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP_FAKE_REVERSAL',
  'PGTAP-FAKE-REVERSAL-001',
  repeat('f', 64),
  'STARTED',
  '2026-07-18 15:00:00+07'::timestamptz,
  null,
  null,
  '{}'::jsonb,
  null,
  null
);

insert into inventory.stock_transactions (
  id,
  organization_id,
  transaction_no,
  transaction_type_code,
  reason_id,
  reason_code_snapshot,
  channel_id,
  channel_code_snapshot,
  source_type_code,
  source_id,
  source_ref_snapshot,
  occurred_at,
  recorded_at,
  effective_local_date,
  actor_user_id,
  process_name,
  created_by_role_code,
  correlation_id,
  idempotency_command_id,
  reversal_of_transaction_id,
  note,
  metadata,
  schema_version
)
select
  '96000000-0000-4000-8000-000000000001'::uuid,
  original.organization_id,
  'REV-PGTAP-OVER-001',
  'REVERSAL',
  reason.id,
  'REVERSAL',
  channel.id,
  'MANUAL',
  'STOCK_TRANSACTION_REVERSAL',
  original.id,
  original.transaction_no,
  '2026-07-18 15:00:00+07'::timestamptz,
  '2026-07-18 15:00:00+07'::timestamptz,
  '2026-07-18'::date,
  '94000000-0000-4000-8000-000000000001'::uuid,
  null,
  'ADMIN',
  '97000000-0000-4000-8000-000000000001'::uuid,
  '95000000-0000-4000-8000-000000000001'::uuid,
  original.id,
  'Over-application validation fixture.',
  '{"fixture":"over-application"}'::jsonb,
  1
from inventory.stock_transactions original
join catalog.movement_reasons reason
  on reason.code = 'REVERSAL'
 and reason.is_active
join catalog.channels channel
  on channel.code = 'MANUAL'
 and channel.is_active
where original.id = (
  select (result ->> 'transactionId')::uuid
  from reversal_results
  where kind = 'MANUAL_POST'
);

insert into inventory.stock_ledger_entries (
  id,
  organization_id,
  transaction_id,
  line_no,
  product_id,
  batch_id,
  product_sku_snapshot,
  batch_code_snapshot,
  expiry_date_snapshot,
  bucket_code,
  quantity_delta,
  entry_role_code,
  pair_no,
  source_line_ref,
  occurred_at,
  recorded_at,
  created_at
)
select
  '98000000-0000-4000-8000-000000000001'::uuid,
  original_entry.organization_id,
  '96000000-0000-4000-8000-000000000001'::uuid,
  1,
  original_entry.product_id,
  original_entry.batch_id,
  original_entry.product_sku_snapshot,
  original_entry.batch_code_snapshot,
  original_entry.expiry_date_snapshot,
  original_entry.bucket_code,
  1,
  'REVERSAL',
  original_entry.pair_no,
  original_entry.id::text,
  '2026-07-18 15:00:00+07'::timestamptz,
  '2026-07-18 15:00:00+07'::timestamptz,
  '2026-07-18 15:00:00+07'::timestamptz
from inventory.stock_ledger_entries original_entry
where original_entry.transaction_id = (
  select (result ->> 'transactionId')::uuid
  from reversal_results
  where kind = 'MANUAL_POST'
)
order by original_entry.ledger_seq
limit 1;

-- 59: over-application protection
select throws_ok(
  $sql$
    insert into inventory.stock_reversal_applications (
      organization_id,
      original_transaction_id,
      reversal_transaction_id,
      original_entry_id,
      reversal_entry_id,
      quantity_applied,
      created_at
    )
    select
      original_entry.organization_id,
      original_entry.transaction_id,
      '96000000-0000-4000-8000-000000000001'::uuid,
      original_entry.id,
      '98000000-0000-4000-8000-000000000001'::uuid,
      1,
      '2026-07-18 15:00:00+07'::timestamptz
    from inventory.stock_ledger_entries original_entry
    where original_entry.transaction_id = (
      select (result ->> 'transactionId')::uuid
      from reversal_results
      where kind = 'MANUAL_POST'
    )
    order by original_entry.ledger_seq
    limit 1
  $sql$,
  'P0001',
  'REVERSAL_APPLICATION_OVER_APPLIED',
  'reversal applications cannot exceed the original entry quantity'
);

select * from finish();

rollback;
