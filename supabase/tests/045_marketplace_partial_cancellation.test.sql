begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

-- Contract and security surface.
select has_table('operations', 'marketplace_cancellations', 'cancellation header table exists');
select has_table('operations', 'marketplace_cancellation_lines', 'cancellation line table exists');
select has_table('operations', 'marketplace_cancellation_applications', 'cancellation application table exists');
select has_view('api', 'marketplace_cancellations', 'cancellation header view exists');
select has_view('api', 'marketplace_cancellation_lines', 'cancellation line view exists');
select has_view('api', 'marketplace_cancellation_applications', 'cancellation application view exists');
select has_view('api', 'marketplace_cancellation_candidates', 'cancellation candidate view exists');
select has_trigger(
  'operations',
  'return_items',
  'trg_return_items_marketplace_cancellation_overlap',
  'return items guard against cancellation overlap'
);

select function_returns(
  'inventory',
  'preview_marketplace_cancellation_core',
  array[
    'uuid', 'text', 'text', 'text', 'timestamptz',
    'text', 'jsonb', 'text', 'jsonb', 'boolean'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'preview_marketplace_cancellation',
  array[
    'uuid', 'text', 'text', 'text', 'timestamptz',
    'text', 'jsonb', 'text', 'jsonb'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'post_marketplace_cancellation',
  array[
    'uuid', 'text', 'text', 'text', 'text', 'timestamptz',
    'text', 'jsonb', 'text', 'boolean', 'text', 'jsonb'
  ]::text[],
  'jsonb'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.preview_marketplace_cancellation(uuid,text,text,text,timestamptz,text,jsonb,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot preview marketplace cancellation'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.preview_marketplace_cancellation(uuid,text,text,text,timestamptz,text,jsonb,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may preview marketplace cancellation'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.post_marketplace_cancellation(uuid,text,text,text,text,timestamptz,text,jsonb,text,boolean,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot post marketplace cancellation'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.post_marketplace_cancellation(uuid,text,text,text,text,timestamptz,text,jsonb,text,boolean,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may post marketplace cancellation'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'inventory.preview_marketplace_cancellation_core(uuid,text,text,text,timestamptz,text,jsonb,text,jsonb,boolean)',
    'EXECUTE'
  ),
  'authenticated role cannot execute internal cancellation preview core'
);

select ok(
  not has_table_privilege('authenticated', 'operations.marketplace_cancellations', 'INSERT'),
  'authenticated role cannot insert cancellation headers directly'
);
select ok(
  not has_table_privilege('authenticated', 'operations.marketplace_cancellation_lines', 'INSERT'),
  'authenticated role cannot insert cancellation lines directly'
);
select ok(
  not has_table_privilege('authenticated', 'operations.marketplace_cancellation_applications', 'INSERT'),
  'authenticated role cannot insert cancellation applications directly'
);

select ok(
  (
    select class.relrowsecurity
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'marketplace_cancellations'
  ),
  'cancellation headers have RLS enabled'
);
select ok(
  (
    select class.relrowsecurity
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'marketplace_cancellation_lines'
  ),
  'cancellation lines have RLS enabled'
);
select ok(
  (
    select class.relrowsecurity
    from pg_catalog.pg_class class
    join pg_catalog.pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'marketplace_cancellation_applications'
  ),
  'cancellation applications have RLS enabled'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    cross join lateral unnest(procedure.proconfig) config(value)
    where namespace.nspname = 'api'
      and procedure.proname = 'post_marketplace_cancellation'
      and procedure.pronargs = 12
      and config.value =
        'search_path=pg_catalog, auth, app, catalog, inventory, operations, extensions'
  ),
  'cancellation posting has a fixed search_path'
);

select ok(
  (
    select pg_get_constraintdef(constraint_record.oid, true)
    from pg_catalog.pg_constraint constraint_record
    where constraint_record.conrelid = 'operations.marketplace_events'::regclass
      and constraint_record.conname = 'ck_marketplace_events_type'
  ) like '%CANCEL%',
  'marketplace event type constraint includes CANCEL'
);

-- Isolated organizations and Admin identity.
insert into app.organizations (
  id, code, name, timezone, is_active, created_at, created_by
) values
  (
    '00000000-0000-4000-8000-000000000040'::uuid,
    'PGTAP_MKT_CANCEL',
    'pgTAP Marketplace Cancellation',
    'Asia/Jakarta',
    true,
    '2026-07-20 08:00:00+07'::timestamptz,
    null
  ),
  (
    '00000000-0000-4000-8000-000000000041'::uuid,
    'PGTAP_MKT_CANCEL_OTHER',
    'pgTAP Marketplace Cancellation Other',
    'Asia/Jakarta',
    true,
    '2026-07-20 08:00:00+07'::timestamptz,
    null
  );

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  '98000000-0000-4000-8000-000000000040'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.marketplace.cancellation@glowlab.invalid',
  '2026-07-20 08:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-20 08:00:00+07'::timestamptz,
  '2026-07-20 08:00:00+07'::timestamptz,
  false,
  false
);

insert into app.user_profiles (
  user_id, organization_id, display_name, employee_code, role_code, is_active
) values (
  '98000000-0000-4000-8000-000000000040'::uuid,
  '00000000-0000-4000-8000-000000000040'::uuid,
  'pgTAP Marketplace Cancellation Admin',
  'PGTAP-MKT-CANCEL',
  'ADMIN',
  true
);

insert into catalog.products (
  id, organization_id, sku, name, unit_code,
  is_batch_tracked, is_expiry_tracked, is_active, created_at, row_version
) values
  (
    '40000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    'MCC-SPLIT', 'Cancellation Split Fixture', 'UNIT',
    true, true, true, '2026-07-01 08:00:00+07'::timestamptz, 1
  ),
  (
    '40000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    'MCC-PRE', 'Cancellation Pre Fixture', 'UNIT',
    true, true, true, '2026-07-01 08:00:00+07'::timestamptz, 1
  ),
  (
    '40000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    'MCC-MULTI', 'Cancellation Multi Shipment Fixture', 'UNIT',
    true, true, true, '2026-07-01 08:00:00+07'::timestamptz, 1
  ),
  (
    '40000000-0000-4000-8000-000000000004'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    'MCC-RETURN', 'Cancellation Return Conflict Fixture', 'UNIT',
    true, true, true, '2026-07-01 08:00:00+07'::timestamptz, 1
  ),
  (
    '40000000-0000-4000-8000-000000000005'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    'MCC-ATOMIC', 'Cancellation Atomic Fixture', 'UNIT',
    true, true, true, '2026-07-01 08:00:00+07'::timestamptz, 1
  );

insert into catalog.product_batches (
  id, organization_id, product_id, batch_code, manufactured_date,
  expiry_date, received_first_at, status_code, block_reason,
  created_at, updated_at, row_version, batch_kind_code
) values
  (
    '50000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    '40000000-0000-4000-8000-000000000001'::uuid,
    'MCC-SPLIT-A', '2026-01-01'::date, '2027-01-31'::date,
    null, 'ACTIVE', null,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz, 1, 'STANDARD'
  ),
  (
    '50000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    '40000000-0000-4000-8000-000000000001'::uuid,
    'MCC-SPLIT-B', '2026-01-01'::date, '2027-06-30'::date,
    null, 'ACTIVE', null,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz, 1, 'STANDARD'
  ),
  (
    '50000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    '40000000-0000-4000-8000-000000000002'::uuid,
    'MCC-PRE-A', '2026-01-01'::date, '2027-12-31'::date,
    null, 'ACTIVE', null,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz, 1, 'STANDARD'
  ),
  (
    '50000000-0000-4000-8000-000000000004'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    '40000000-0000-4000-8000-000000000003'::uuid,
    'MCC-MULTI-A', '2026-01-01'::date, '2027-12-31'::date,
    null, 'ACTIVE', null,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz, 1, 'STANDARD'
  ),
  (
    '50000000-0000-4000-8000-000000000005'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    '40000000-0000-4000-8000-000000000004'::uuid,
    'MCC-RETURN-A', '2026-01-01'::date, '2027-12-31'::date,
    null, 'ACTIVE', null,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz, 1, 'STANDARD'
  ),
  (
    '50000000-0000-4000-8000-000000000006'::uuid,
    '00000000-0000-4000-8000-000000000040'::uuid,
    '40000000-0000-4000-8000-000000000005'::uuid,
    'MCC-ATOMIC-A', '2026-01-01'::date, '2027-12-31'::date,
    null, 'ACTIVE', null,
    '2026-07-01 08:00:00+07'::timestamptz,
    '2026-07-01 08:00:00+07'::timestamptz, 1, 'STANDARD'
  );

-- Build ledger-backed fixture stock through the supported receipt command.
select api.post_receipt(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-RECEIPT-001',
  'PGTAP-MCC-RECEIPT-001',
  '2026-07-01 09:00:00+07'::timestamptz,
  jsonb_build_array(
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000001',
      'batchId', '50000000-0000-4000-8000-000000000001',
      'quantity', 5,
      'sourceLineRef', 'SPLIT-A'
    ),
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000001',
      'batchId', '50000000-0000-4000-8000-000000000002',
      'quantity', 10,
      'sourceLineRef', 'SPLIT-B'
    ),
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000002',
      'batchId', '50000000-0000-4000-8000-000000000003',
      'quantity', 10,
      'sourceLineRef', 'PRE-A'
    ),
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000003',
      'batchId', '50000000-0000-4000-8000-000000000004',
      'quantity', 12,
      'sourceLineRef', 'MULTI-A'
    ),
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000004',
      'batchId', '50000000-0000-4000-8000-000000000005',
      'quantity', 6,
      'sourceLineRef', 'RETURN-A'
    ),
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000005',
      'batchId', '50000000-0000-4000-8000-000000000006',
      'quantity', 6,
      'sourceLineRef', 'ATOMIC-A'
    )
  ),
  'Fixture stock for marketplace cancellation tests.',
  '{"test":true}'::jsonb
);

create temp table marketplace_cancellation_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update on marketplace_cancellation_results to authenticated;

select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-4000-8000-000000000040',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98000000-0000-4000-8000-000000000040',
    'role', 'authenticated',
    'email', 'pgtap.marketplace.cancellation@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

-- Create canonical orders and shipments.
insert into marketplace_cancellation_results (kind, result)
select 'RESERVE_PRE', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-RESERVE-PRE', 'SHOPEE', 'RESERVE',
  'PGTAP-MCC-EVT-RESERVE-PRE', 'PGTAP-MCC-ORDER-PRE',
  '2026-07-20 09:00:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000002',
    'quantity', 6,
    'sourceLineRef', 'ITEM-PRE'
  )),
  'Reserve pre-shipment fixture.', '{"test":true}'::jsonb
);

insert into marketplace_cancellation_results (kind, result)
select 'RESERVE_SPLIT', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-RESERVE-SPLIT', 'SHOPEE', 'RESERVE',
  'PGTAP-MCC-EVT-RESERVE-SPLIT', 'PGTAP-MCC-ORDER-SPLIT',
  '2026-07-20 09:01:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000001',
    'quantity', 8,
    'sourceLineRef', 'ITEM-SPLIT'
  )),
  'Reserve split-batch fixture.', '{"test":true}'::jsonb
);

insert into marketplace_cancellation_results (kind, result)
select 'SHIP_SPLIT', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-SHIP-SPLIT', 'SHOPEE', 'SHIP',
  'PGTAP-MCC-EVT-SHIP-SPLIT', 'PGTAP-MCC-ORDER-SPLIT',
  '2026-07-20 09:02:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000001',
    'quantity', 8,
    'sourceLineRef', 'ITEM-SPLIT'
  )),
  'Ship split-batch fixture.', '{"test":true}'::jsonb
);

insert into marketplace_cancellation_results (kind, result)
select 'RESERVE_MULTI', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-RESERVE-MULTI', 'TIKTOK_SHOP', 'RESERVE',
  'PGTAP-MCC-EVT-RESERVE-MULTI', 'PGTAP-MCC-ORDER-MULTI',
  '2026-07-20 09:03:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000003',
    'quantity', 8,
    'sourceLineRef', 'ITEM-MULTI'
  )),
  'Reserve multi-shipment fixture.', '{"test":true}'::jsonb
);

insert into marketplace_cancellation_results (kind, result)
select 'SHIP_MULTI_1', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-SHIP-MULTI-1', 'TIKTOK_SHOP', 'SHIP',
  'PGTAP-MCC-EVT-SHIP-MULTI-1', 'PGTAP-MCC-ORDER-MULTI',
  '2026-07-20 09:04:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000003',
    'quantity', 3,
    'sourceLineRef', 'ITEM-MULTI'
  )),
  'First multi shipment.', '{"test":true}'::jsonb
);

insert into marketplace_cancellation_results (kind, result)
select 'SHIP_MULTI_2', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-SHIP-MULTI-2', 'TIKTOK_SHOP', 'SHIP',
  'PGTAP-MCC-EVT-SHIP-MULTI-2', 'PGTAP-MCC-ORDER-MULTI',
  '2026-07-20 09:05:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000003',
    'quantity', 3,
    'sourceLineRef', 'ITEM-MULTI'
  )),
  'Second multi shipment.', '{"test":true}'::jsonb
);

insert into marketplace_cancellation_results (kind, result)
select 'RESERVE_RETURN', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-RESERVE-RETURN', 'SHOPEE', 'RESERVE',
  'PGTAP-MCC-EVT-RESERVE-RETURN', 'PGTAP-MCC-ORDER-RETURN',
  '2026-07-20 09:06:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000004',
    'quantity', 4,
    'sourceLineRef', 'ITEM-RETURN'
  )),
  'Reserve return-conflict fixture.', '{"test":true}'::jsonb
);

insert into marketplace_cancellation_results (kind, result)
select 'SHIP_RETURN', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-SHIP-RETURN', 'SHOPEE', 'SHIP',
  'PGTAP-MCC-EVT-SHIP-RETURN', 'PGTAP-MCC-ORDER-RETURN',
  '2026-07-20 09:07:00+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000004',
    'quantity', 4,
    'sourceLineRef', 'ITEM-RETURN'
  )),
  'Ship return-conflict fixture.', '{"test":true}'::jsonb
);

insert into marketplace_cancellation_results (kind, result)
select 'RESERVE_ATOMIC', api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-RESERVE-ATOMIC', 'SHOPEE', 'RESERVE',
  'PGTAP-MCC-EVT-RESERVE-ATOMIC', 'PGTAP-MCC-ORDER-ATOMIC',
  '2026-07-20 09:08:00+07'::timestamptz,
  jsonb_build_array(
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000002',
      'quantity', 2,
      'sourceLineRef', 'ITEM-ATOMIC-PRE'
    ),
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000005',
      'quantity', 3,
      'sourceLineRef', 'ITEM-ATOMIC-FAIL'
    )
  ),
  'Reserve atomic rollback fixture.', '{"test":true}'::jsonb
);

-- Pre-shipment preview is authoritative and stock-neutral.
insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_PRE', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-PRE-1', 'PGTAP-MCC-ORDER-PRE',
  '2026-07-20 10:00:00+07'::timestamptz,
  'CANCELLED',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000002',
    'orderItemRef', 'ITEM-PRE',
    'phaseCode', 'PRE_SHIPMENT',
    'quantity', 2,
    'sourceLineRef', 'CANCEL-PRE-1'
  )),
  null,
  '{"test":true}'::jsonb
);

select is(
  (select result ->> 'eligible' from marketplace_cancellation_results where kind = 'PREVIEW_PRE'),
  'true',
  'pre-shipment cancellation preview is eligible'
);
select is(
  (select result ->> 'postShipmentQuantity' from marketplace_cancellation_results where kind = 'PREVIEW_PRE'),
  '0',
  'pre-shipment preview has no post-shipment quantity'
);
select is(
  (select result #>> '{lines,0,applications,0,effectCode}' from marketplace_cancellation_results where kind = 'PREVIEW_PRE'),
  'PRE_SHIPMENT_RELEASE',
  'pre-shipment preview identifies reservation release effect'
);
select is(
  (select released_qty::text from api.marketplace_reservations where external_order_ref = 'PGTAP-MCC-ORDER-PRE'),
  '0',
  'preview does not release reservation'
);
select is(
  (select count(*)::text from operations.marketplace_cancellations where external_event_ref = 'PGTAP-MCC-CANCEL-PRE-1'),
  '0',
  'preview creates no cancellation header'
);
select is(
  (select count(*)::text from inventory.stock_transactions where source_ref_snapshot = 'PGTAP-MCC-CANCEL-PRE-1'),
  '0',
  'preview creates no stock transaction'
);

insert into marketplace_cancellation_results (kind, result)
select 'POST_PRE', api.post_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-POST-PRE-1',
  'SHOPEE', 'PGTAP-MCC-CANCEL-PRE-1', 'PGTAP-MCC-ORDER-PRE',
  '2026-07-20 10:00:00+07'::timestamptz,
  'CANCELLED',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000002',
    'orderItemRef', 'ITEM-PRE',
    'phaseCode', 'PRE_SHIPMENT',
    'quantity', 2,
    'sourceLineRef', 'CANCEL-PRE-1'
  )),
  (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_PRE'),
  false,
  null,
  '{"test":true}'::jsonb
);

select is(
  (select result ->> 'status' from marketplace_cancellation_results where kind = 'POST_PRE'),
  'POSTED',
  'pre-shipment cancellation posts without stock confirmation'
);
select is(
  (select released_qty::text from api.marketplace_reservations where external_order_ref = 'PGTAP-MCC-ORDER-PRE'),
  '2',
  'pre-shipment cancellation increments released quantity'
);
select is(
  (select open_qty::text from api.marketplace_reservations where external_order_ref = 'PGTAP-MCC-ORDER-PRE'),
  '4',
  'pre-shipment cancellation leaves the expected open reservation'
);
select is(
  (select reserved_qty::text from inventory.stock_product_positions where product_id = '40000000-0000-4000-8000-000000000002'::uuid),
  '6',
  'pre-shipment cancellation updates product reserved projection only'
);
select is(
  (select count(*)::text from inventory.stock_transactions where source_type_code = 'MARKETPLACE_CANCELLATION' and source_ref_snapshot = 'PGTAP-MCC-CANCEL-PRE-1'),
  '0',
  'pre-shipment cancellation creates no reversal transaction'
);
select is(
  (select count(*)::text from inventory.stock_ledger_entries entry join inventory.stock_transactions transaction on transaction.id = entry.transaction_id where transaction.source_ref_snapshot = 'PGTAP-MCC-CANCEL-PRE-1'),
  '0',
  'pre-shipment cancellation creates no ledger effect'
);
select is(
  (select transaction_id::text from api.marketplace_events where external_event_ref = 'PGTAP-MCC-CANCEL-PRE-1'),
  null::text,
  'canonical cancellation event remains stock-transaction neutral'
);
select is(
  (select effect_code from api.marketplace_cancellation_applications where external_event_ref = 'PGTAP-MCC-CANCEL-PRE-1'),
  'PRE_SHIPMENT_RELEASE',
  'pre-shipment release application is persisted'
);

select is(
  api.post_marketplace_cancellation(
    '00000000-0000-4000-8000-000000000040'::uuid,
    'PGTAP-MCC-POST-PRE-1',
    'SHOPEE', 'PGTAP-MCC-CANCEL-PRE-1', 'PGTAP-MCC-ORDER-PRE',
    '2026-07-20 10:00:00+07'::timestamptz,
    'CANCELLED',
    jsonb_build_array(jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000002',
      'orderItemRef', 'ITEM-PRE',
      'phaseCode', 'PRE_SHIPMENT',
      'quantity', 2,
      'sourceLineRef', 'CANCEL-PRE-1'
    )),
    (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_PRE'),
    false,
    null,
    '{"test":true}'::jsonb
  ),
  (select result from marketplace_cancellation_results where kind = 'POST_PRE'),
  'identical pre-shipment replay returns original response'
);

select throws_ok(
  $sql$
    select api.post_marketplace_cancellation(
      '00000000-0000-4000-8000-000000000040'::uuid,
      'PGTAP-MCC-POST-PRE-1',
      'SHOPEE', 'PGTAP-MCC-CANCEL-PRE-CHANGED', 'PGTAP-MCC-ORDER-PRE',
      '2026-07-20 10:00:00+07'::timestamptz,
      'CANCELLED',
      jsonb_build_array(jsonb_build_object(
        'productId', '40000000-0000-4000-8000-000000000002',
        'orderItemRef', 'ITEM-PRE',
        'phaseCode', 'PRE_SHIPMENT',
        'quantity', 1,
        'sourceLineRef', 'CANCEL-PRE-CHANGED'
      )),
      repeat('0', 64), false, null, '{"test":true}'::jsonb
    )
  $sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'changed payload under the same cancellation key is rejected'
);


insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_DUPLICATE_EVENT', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-PRE-1', 'PGTAP-MCC-ORDER-PRE',
  '2026-07-20 10:00:30+07'::timestamptz,
  'CANCELLED',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000002',
    'orderItemRef', 'ITEM-PRE',
    'phaseCode', 'PRE_SHIPMENT',
    'quantity', 1,
    'sourceLineRef', 'CANCEL-PRE-DUPLICATE'
  )),
  null,
  '{"test":true}'::jsonb
);
select ok(
  (select result -> 'blockers' from marketplace_cancellation_results where kind = 'PREVIEW_DUPLICATE_EVENT') @>
    '[{"code":"MARKETPLACE_CANCELLATION_EVENT_ALREADY_APPLIED"}]'::jsonb,
  'same external cancellation event is blocked under a different command key'
);

-- Explicit phase is mandatory; the domain never guesses mixed state.
select throws_ok(
  $sql$
    select api.preview_marketplace_cancellation(
      '00000000-0000-4000-8000-000000000040'::uuid,
      'SHOPEE', 'PGTAP-MCC-CANCEL-NO-PHASE', 'PGTAP-MCC-ORDER-PRE',
      '2026-07-20 10:00:40+07'::timestamptz,
      'CANCELLED',
      jsonb_build_array(jsonb_build_object(
        'productId', '40000000-0000-4000-8000-000000000002',
        'orderItemRef', 'ITEM-PRE',
        'quantity', 1,
        'sourceLineRef', 'CANCEL-NO-PHASE'
      )),
      null,
      '{"test":true}'::jsonb
    )
  $sql$,
  'P0001',
  'MARKETPLACE_CANCELLATION_LINE_INVALID',
  'cancellation line without explicit phase is rejected'
);

-- Split-batch post-shipment preview unwinds latest allocated units first.
insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_SPLIT_1', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-SPLIT-1', 'PGTAP-MCC-ORDER-SPLIT',
  '2026-07-20 10:01:00+07'::timestamptz,
  'CANCELLED_AFTER_SHIPMENT',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000001',
    'orderItemRef', 'ITEM-SPLIT',
    'phaseCode', 'POST_SHIPMENT',
    'quantity', 4,
    'sourceLineRef', 'CANCEL-SPLIT-1'
  )),
  'Marketplace membatalkan empat unit setelah shipment.',
  '{"test":true}'::jsonb
);

select is(
  (select result ->> 'eligible' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_1'),
  'true',
  'post-shipment split-batch preview is eligible'
);
select is(
  (select jsonb_array_length(result #> '{lines,0,applications}')::text from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_1'),
  '2',
  'post-shipment preview selects two exact allocations'
);
select is(
  (select result #>> '{lines,0,applications,0,batchCode}' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_1'),
  'MCC-SPLIT-B',
  'LIFO unwind restores the latest shipment ledger batch first'
);
select is(
  (select result #>> '{lines,0,applications,0,quantity}' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_1'),
  '3',
  'latest split allocation contributes three units'
);
select is(
  (select result #>> '{lines,0,applications,1,batchCode}' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_1'),
  'MCC-SPLIT-A',
  'remaining cancellation quantity uses the earlier shipment allocation'
);
select is(
  (select result #>> '{lines,0,applications,1,quantity}' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_1'),
  '1',
  'earlier split allocation contributes one unit'
);
select is(
  (select sellable_qty::text from inventory.stock_product_positions where product_id = '40000000-0000-4000-8000-000000000001'::uuid),
  '7',
  'post-shipment preview does not restore product stock'
);
select is(
  (select count(*)::text from operations.marketplace_cancellations where external_event_ref = 'PGTAP-MCC-CANCEL-SPLIT-1'),
  '0',
  'post-shipment preview creates no cancellation document'
);

select throws_ok(
  $sql$
    select api.post_marketplace_cancellation(
      '00000000-0000-4000-8000-000000000040'::uuid,
      'PGTAP-MCC-POST-SPLIT-NOCONFIRM',
      'SHOPEE', 'PGTAP-MCC-CANCEL-SPLIT-NOCONFIRM', 'PGTAP-MCC-ORDER-SPLIT',
      '2026-07-20 10:01:00+07'::timestamptz,
      'CANCELLED_AFTER_SHIPMENT',
      jsonb_build_array(jsonb_build_object(
        'productId', '40000000-0000-4000-8000-000000000001',
        'orderItemRef', 'ITEM-SPLIT',
        'phaseCode', 'POST_SHIPMENT',
        'quantity', 4,
        'sourceLineRef', 'CANCEL-SPLIT-NOCONFIRM'
      )),
      (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_1'),
      false,
      'Konfirmasi sengaja tidak diberikan.',
      '{"test":true}'::jsonb
    )
  $sql$,
  'P0001',
  'STALE_MARKETPLACE_CANCELLATION_PREVIEW',
  'different event identity cannot reuse another preview basis'
);

select throws_ok(
  $sql$
    select api.post_marketplace_cancellation(
      '00000000-0000-4000-8000-000000000040'::uuid,
      'PGTAP-MCC-POST-SPLIT-1-NOCONFIRM',
      'SHOPEE', 'PGTAP-MCC-CANCEL-SPLIT-1', 'PGTAP-MCC-ORDER-SPLIT',
      '2026-07-20 10:01:00+07'::timestamptz,
      'CANCELLED_AFTER_SHIPMENT',
      jsonb_build_array(jsonb_build_object(
        'productId', '40000000-0000-4000-8000-000000000001',
        'orderItemRef', 'ITEM-SPLIT',
        'phaseCode', 'POST_SHIPMENT',
        'quantity', 4,
        'sourceLineRef', 'CANCEL-SPLIT-1'
      )),
      (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_1'),
      false,
      'Marketplace membatalkan empat unit setelah shipment.',
      '{"test":true}'::jsonb
    )
  $sql$,
  'P0001',
  'MARKETPLACE_CANCELLATION_CONFIRMATION_REQUIRED',
  'post-shipment cancellation requires explicit confirmation'
);
select is(
  (select count(*)::text from operations.marketplace_cancellations where external_event_ref = 'PGTAP-MCC-CANCEL-SPLIT-1'),
  '0',
  'failed confirmation writes no cancellation effect'
);

insert into marketplace_cancellation_results (kind, result)
select 'POST_SPLIT_1', api.post_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-POST-SPLIT-1',
  'SHOPEE', 'PGTAP-MCC-CANCEL-SPLIT-1', 'PGTAP-MCC-ORDER-SPLIT',
  '2026-07-20 10:01:00+07'::timestamptz,
  'CANCELLED_AFTER_SHIPMENT',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000001',
    'orderItemRef', 'ITEM-SPLIT',
    'phaseCode', 'POST_SHIPMENT',
    'quantity', 4,
    'sourceLineRef', 'CANCEL-SPLIT-1'
  )),
  (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_1'),
  true,
  'Marketplace membatalkan empat unit setelah shipment.',
  '{"test":true}'::jsonb
);

select is(
  (select result ->> 'reversalTransactionCount' from marketplace_cancellation_results where kind = 'POST_SPLIT_1'),
  '1',
  'one original shipment transaction creates one reversal transaction'
);
select is(
  (select count(*)::text from inventory.stock_transactions where source_type_code = 'MARKETPLACE_CANCELLATION' and source_ref_snapshot = 'PGTAP-MCC-CANCEL-SPLIT-1'),
  '1',
  'post-shipment cancellation persists one linked reversal transaction'
);
select is(
  (select sum(entry.quantity_delta)::text from inventory.stock_ledger_entries entry join inventory.stock_transactions transaction on transaction.id = entry.transaction_id where transaction.source_type_code = 'MARKETPLACE_CANCELLATION' and transaction.source_ref_snapshot = 'PGTAP-MCC-CANCEL-SPLIT-1'),
  '4',
  'post-shipment cancellation restores four units through ledger'
);
select is(
  (select sellable_qty::text from inventory.stock_batch_balances where batch_id = '50000000-0000-4000-8000-000000000001'::uuid),
  '1',
  'earlier FEFO batch receives exactly one restored unit'
);
select is(
  (select sellable_qty::text from inventory.stock_batch_balances where batch_id = '50000000-0000-4000-8000-000000000002'::uuid),
  '10',
  'later FEFO batch receives exactly three restored units'
);
select is(
  (select sellable_qty::text from inventory.stock_product_positions where product_id = '40000000-0000-4000-8000-000000000001'::uuid),
  '11',
  'product projection matches exact restored quantity'
);
select is(
  (select count(*)::text from inventory.stock_reversal_applications application join operations.marketplace_cancellation_applications cancellation_application on cancellation_application.stock_reversal_application_id = application.id join operations.marketplace_cancellation_lines cancellation_line on cancellation_line.id = cancellation_application.cancellation_line_id join operations.marketplace_cancellations cancellation on cancellation.id = cancellation_line.cancellation_id where cancellation.external_event_ref = 'PGTAP-MCC-CANCEL-SPLIT-1'),
  '2',
  'exact original-entry reversal mappings are persisted'
);
select is(
  (select count(*)::text from operations.marketplace_ship_allocations allocation join operations.marketplace_events event on event.id = allocation.event_id where event.external_event_ref = 'PGTAP-MCC-CANCEL-SPLIT-1'),
  '0',
  'cancellation does not rerun FEFO or create shipment allocations'
);
select is(
  (select count(*)::text from operations.return_events where external_event_ref = 'PGTAP-MCC-CANCEL-SPLIT-1'),
  '0',
  'cancellation does not manufacture a return event'
);
select is(
  (select transaction_id::text from api.marketplace_events where external_event_ref = 'PGTAP-MCC-CANCEL-SPLIT-1'),
  null::text,
  'canonical CANCEL event stays separate from reversal transactions'
);

select is(
  api.post_marketplace_cancellation(
    '00000000-0000-4000-8000-000000000040'::uuid,
    'PGTAP-MCC-POST-SPLIT-1',
    'SHOPEE', 'PGTAP-MCC-CANCEL-SPLIT-1', 'PGTAP-MCC-ORDER-SPLIT',
    '2026-07-20 10:01:00+07'::timestamptz,
    'CANCELLED_AFTER_SHIPMENT',
    jsonb_build_array(jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000001',
      'orderItemRef', 'ITEM-SPLIT',
      'phaseCode', 'POST_SHIPMENT',
      'quantity', 4,
      'sourceLineRef', 'CANCEL-SPLIT-1'
    )),
    (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_1'),
    true,
    'Marketplace membatalkan empat unit setelah shipment.',
    '{"test":true}'::jsonb
  ),
  (select result from marketplace_cancellation_results where kind = 'POST_SPLIT_1'),
  'post-shipment replay creates no second domain effect'
);

-- A later partial cancellation continues from remaining original allocations.
insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_SPLIT_2', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-SPLIT-2', 'PGTAP-MCC-ORDER-SPLIT',
  '2026-07-20 10:02:00+07'::timestamptz,
  'CANCELLED_AFTER_SHIPMENT',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000001',
    'orderItemRef', 'ITEM-SPLIT',
    'phaseCode', 'POST_SHIPMENT',
    'quantity', 2,
    'sourceLineRef', 'CANCEL-SPLIT-2'
  )),
  'Pembatalan parsial lanjutan.',
  '{"test":true}'::jsonb
);

select is(
  (select result #>> '{lines,0,applications,0,batchCode}' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_2'),
  'MCC-SPLIT-A',
  'second partial cancellation resumes from the remaining original batch'
);
select is(
  (select result #>> '{lines,0,applications,0,quantity}' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_2'),
  '2',
  'second partial cancellation restores only requested quantity'
);

insert into marketplace_cancellation_results (kind, result)
select 'POST_SPLIT_2', api.post_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-POST-SPLIT-2',
  'SHOPEE', 'PGTAP-MCC-CANCEL-SPLIT-2', 'PGTAP-MCC-ORDER-SPLIT',
  '2026-07-20 10:02:00+07'::timestamptz,
  'CANCELLED_AFTER_SHIPMENT',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000001',
    'orderItemRef', 'ITEM-SPLIT',
    'phaseCode', 'POST_SHIPMENT',
    'quantity', 2,
    'sourceLineRef', 'CANCEL-SPLIT-2'
  )),
  (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_2'),
  true,
  'Pembatalan parsial lanjutan.',
  '{"test":true}'::jsonb
);

select is(
  (select sellable_qty::text from inventory.stock_batch_balances where batch_id = '50000000-0000-4000-8000-000000000001'::uuid),
  '3',
  'second partial cancellation restores two more units to original batch'
);
select is(
  (select post_shipment_cancelled_qty::text from api.marketplace_cancellation_candidates where external_order_ref = 'PGTAP-MCC-ORDER-SPLIT'),
  '6',
  'candidate view totals repeated partial post-shipment cancellations'
);
select is(
  (select remaining_post_cancellable_qty::text from api.marketplace_cancellation_candidates where external_order_ref = 'PGTAP-MCC-ORDER-SPLIT'),
  '2',
  'candidate view reports remaining shipped quantity'
);
select is(
  (select count(distinct reversal_transaction_id)::text from inventory.stock_reversal_applications application where application.original_transaction_id = (select (result ->> 'transactionId')::uuid from marketplace_cancellation_results where kind = 'SHIP_SPLIT')),
  '2',
  'one original shipment can receive multiple bounded partial reversal transactions'
);

insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_SPLIT_OVER', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-SPLIT-OVER', 'PGTAP-MCC-ORDER-SPLIT',
  '2026-07-20 10:03:00+07'::timestamptz,
  'CANCELLED_AFTER_SHIPMENT',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000001',
    'orderItemRef', 'ITEM-SPLIT',
    'phaseCode', 'POST_SHIPMENT',
    'quantity', 3,
    'sourceLineRef', 'CANCEL-SPLIT-OVER'
  )),
  'Melebihi sisa shipment.',
  '{"test":true}'::jsonb
);
select is(
  (select result ->> 'eligible' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_OVER'),
  'false',
  'over-cancellation preview is blocked'
);
select is(
  (select result #>> '{blockers,0,code}' from marketplace_cancellation_results where kind = 'PREVIEW_SPLIT_OVER'),
  'MARKETPLACE_CANCELLATION_EXCEEDS_SHIPPED_REMAINING',
  'over-cancellation returns the shipped-remaining blocker'
);

-- Expected return created after cancellation may use only remaining shipment.
select throws_ok(
  $sql$
    select api.create_expected_return(
      '00000000-0000-4000-8000-000000000040'::uuid,
      'PGTAP-MCC-RETURN-AFTER-CANCEL-BLOCKED',
      'SHOPEE',
      'PGTAP-MCC-RETURN-AFTER-CANCEL-BLOCKED',
      'PGTAP-MCC-ORDER-SPLIT',
      '2026-07-20 10:03:30+07'::timestamptz,
      jsonb_build_array(
        jsonb_build_object(
          'productId',
          '40000000-0000-4000-8000-000000000001',
          'quantity',
          3,
          'sourceLineRef',
          'ITEM-SPLIT'
        )
      ),
      'RETURN_EXPECTED',
      'Melebihi shipment yang tersisa setelah cancellation.',
      '{"test":true}'::jsonb
    )
  $sql$,
  'P0001',
  'RETURN_QUANTITY_EXCEEDS_SHIPPED',
  'expected return cannot reuse shipment quantity already reversed by cancellation'
);

select is(
  (
    select count(*)::text
    from operations.returns
    where external_return_ref =
      'PGTAP-MCC-RETURN-AFTER-CANCEL-BLOCKED'
  ),
  '0',
  'blocked return overlap rolls back its return header'
);

select is(
  (
    select count(*)::text
    from inventory.idempotency_commands
    where scope = 'CREATE_EXPECTED_RETURN'
      and key = 'PGTAP-MCC-RETURN-AFTER-CANCEL-BLOCKED'
  ),
  '0',
  'blocked return overlap leaves no idempotency command'
);

insert into marketplace_cancellation_results (kind, result)
select
  'EXPECTED_AFTER_CANCEL',
  api.create_expected_return(
    '00000000-0000-4000-8000-000000000040'::uuid,
    'PGTAP-MCC-RETURN-AFTER-CANCEL-VALID',
    'SHOPEE',
    'PGTAP-MCC-RETURN-AFTER-CANCEL-VALID',
    'PGTAP-MCC-ORDER-SPLIT',
    '2026-07-20 10:03:31+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '40000000-0000-4000-8000-000000000001',
        'quantity',
        2,
        'sourceLineRef',
        'ITEM-SPLIT'
      )
    ),
    'RETURN_EXPECTED',
    'Memakai tepat shipment yang tersisa.',
    '{"test":true}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from marketplace_cancellation_results
    where kind = 'EXPECTED_AFTER_CANCEL'
  ),
  'EXPECTED',
  'expected return may use the exact shipment remainder'
);

select is(
  (
    select return_expected_qty::text
    from api.marketplace_cancellation_candidates
    where external_order_ref = 'PGTAP-MCC-ORDER-SPLIT'
  ),
  '2',
  'candidate exposes the accepted return quantity'
);

select is(
  (
    select remaining_post_cancellable_qty::text
    from api.marketplace_cancellation_candidates
    where external_order_ref = 'PGTAP-MCC-ORDER-SPLIT'
  ),
  '0',
  'accepted return consumes the remaining post-shipment quantity'
);

-- One external cancellation spanning two shipment transactions creates two reversals.
insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_MULTI', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'TIKTOK_SHOP', 'PGTAP-MCC-CANCEL-MULTI-1', 'PGTAP-MCC-ORDER-MULTI',
  '2026-07-20 10:04:00+07'::timestamptz,
  'CANCELLED_AFTER_SHIPMENT',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000003',
    'orderItemRef', 'ITEM-MULTI',
    'phaseCode', 'POST_SHIPMENT',
    'quantity', 4,
    'sourceLineRef', 'CANCEL-MULTI-1'
  )),
  'Pembatalan menyentuh dua shipment.',
  '{"test":true}'::jsonb
);
select is(
  (select jsonb_array_length(result #> '{lines,0,applications}')::text from marketplace_cancellation_results where kind = 'PREVIEW_MULTI'),
  '2',
  'multi-shipment preview selects two original shipment applications'
);
select isnt(
  (select result #>> '{lines,0,applications,0,originalTransactionId}' from marketplace_cancellation_results where kind = 'PREVIEW_MULTI'),
  (select result #>> '{lines,0,applications,1,originalTransactionId}' from marketplace_cancellation_results where kind = 'PREVIEW_MULTI'),
  'multi-shipment preview preserves distinct original transaction identities'
);

insert into marketplace_cancellation_results (kind, result)
select 'POST_MULTI', api.post_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-POST-MULTI-1',
  'TIKTOK_SHOP', 'PGTAP-MCC-CANCEL-MULTI-1', 'PGTAP-MCC-ORDER-MULTI',
  '2026-07-20 10:04:00+07'::timestamptz,
  'CANCELLED_AFTER_SHIPMENT',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000003',
    'orderItemRef', 'ITEM-MULTI',
    'phaseCode', 'POST_SHIPMENT',
    'quantity', 4,
    'sourceLineRef', 'CANCEL-MULTI-1'
  )),
  (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_MULTI'),
  true,
  'Pembatalan menyentuh dua shipment.',
  '{"test":true}'::jsonb
);

select is(
  (select result ->> 'reversalTransactionCount' from marketplace_cancellation_results where kind = 'POST_MULTI'),
  '2',
  'one cancellation creates one reversal per affected original shipment transaction'
);
select is(
  (select count(*)::text from operations.marketplace_events where external_event_ref = 'PGTAP-MCC-CANCEL-MULTI-1' and event_type_code = 'CANCEL'),
  '1',
  'multi-shipment cancellation still persists one canonical CANCEL event'
);
select is(
  (select count(*)::text from inventory.stock_transactions where source_type_code = 'MARKETPLACE_CANCELLATION' and source_ref_snapshot = 'PGTAP-MCC-CANCEL-MULTI-1'),
  '2',
  'multi-shipment cancellation persists two exact reversal transactions'
);
select is(
  (select sum(entry.quantity_delta)::text from inventory.stock_ledger_entries entry join inventory.stock_transactions transaction on transaction.id = entry.transaction_id where transaction.source_type_code = 'MARKETPLACE_CANCELLATION' and transaction.source_ref_snapshot = 'PGTAP-MCC-CANCEL-MULTI-1'),
  '4',
  'multi-shipment cancellation restores only the requested four units'
);
select is(
  (select sellable_qty::text from inventory.stock_product_positions where product_id = '40000000-0000-4000-8000-000000000003'::uuid),
  '10',
  'multi-shipment restoration updates the product projection exactly'
);
select is(
  (select result ->> 'singleReversalTransactionId' from marketplace_cancellation_results where kind = 'POST_MULTI'),
  null::text,
  'multi-shipment parent response does not pretend one reversal represents all effects'
);

-- Explicit mixed phases are allowed only when each line states its phase.
insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_MIXED', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'TIKTOK_SHOP', 'PGTAP-MCC-CANCEL-MIXED-1', 'PGTAP-MCC-ORDER-MULTI',
  '2026-07-20 10:05:00+07'::timestamptz,
  'CANCELLED_MIXED',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000003',
      'orderItemRef', 'ITEM-MULTI',
      'phaseCode', 'PRE_SHIPMENT',
      'quantity', 1,
      'sourceLineRef', 'CANCEL-MIXED-PRE'
    ),
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000003',
      'orderItemRef', 'ITEM-MULTI',
      'phaseCode', 'POST_SHIPMENT',
      'quantity', 1,
      'sourceLineRef', 'CANCEL-MIXED-POST'
    )
  ),
  'Pembatalan eksplisit untuk reservasi dan shipment.',
  '{"test":true}'::jsonb
);
select is(
  (select result ->> 'eligible' from marketplace_cancellation_results where kind = 'PREVIEW_MIXED'),
  'true',
  'explicit pre/post lines make mixed cancellation unambiguous'
);
select is(
  (select result ->> 'preShipmentQuantity' from marketplace_cancellation_results where kind = 'PREVIEW_MIXED'),
  '1',
  'mixed preview reports pre-shipment quantity'
);
select is(
  (select result ->> 'postShipmentQuantity' from marketplace_cancellation_results where kind = 'PREVIEW_MIXED'),
  '1',
  'mixed preview reports post-shipment quantity'
);

insert into marketplace_cancellation_results (kind, result)
select 'POST_MIXED', api.post_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-POST-MIXED-1',
  'TIKTOK_SHOP', 'PGTAP-MCC-CANCEL-MIXED-1', 'PGTAP-MCC-ORDER-MULTI',
  '2026-07-20 10:05:00+07'::timestamptz,
  'CANCELLED_MIXED',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000003',
      'orderItemRef', 'ITEM-MULTI',
      'phaseCode', 'PRE_SHIPMENT',
      'quantity', 1,
      'sourceLineRef', 'CANCEL-MIXED-PRE'
    ),
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000003',
      'orderItemRef', 'ITEM-MULTI',
      'phaseCode', 'POST_SHIPMENT',
      'quantity', 1,
      'sourceLineRef', 'CANCEL-MIXED-POST'
    )
  ),
  (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_MIXED'),
  true,
  'Pembatalan eksplisit untuk reservasi dan shipment.',
  '{"test":true}'::jsonb
);
select is(
  (select pre_shipment_cancelled_qty::text from api.marketplace_cancellation_candidates where external_order_ref = 'PGTAP-MCC-ORDER-MULTI'),
  '1',
  'mixed cancellation records pre-shipment release separately'
);
select is(
  (select post_shipment_cancelled_qty::text from api.marketplace_cancellation_candidates where external_order_ref = 'PGTAP-MCC-ORDER-MULTI'),
  '5',
  'mixed cancellation totals post-shipment reversals separately'
);
select is(
  (select open_reserved_qty::text from api.marketplace_cancellation_candidates where external_order_ref = 'PGTAP-MCC-ORDER-MULTI'),
  '1',
  'mixed cancellation leaves the expected open reservation'
);
select is(
  (select remaining_post_cancellable_qty::text from api.marketplace_cancellation_candidates where external_order_ref = 'PGTAP-MCC-ORDER-MULTI'),
  '1',
  'mixed cancellation leaves the expected shipped quantity cancellable'
);
select is(
  (select cancellation_status_code from api.marketplace_cancellation_candidates where external_order_ref = 'PGTAP-MCC-ORDER-MULTI'),
  'MIXED',
  'candidate view exposes mixed cancellation state without rewriting shipment history'
);

-- Return overlap blocks post-shipment cancellation.
reset role;

insert into operations.returns (
  id, organization_id, channel_id, marketplace_order_id,
  external_return_ref, source_status_code, status_code, outcome_code,
  expected_at, closed_at, actor_user_id, process_name,
  metadata, created_at, updated_at
) values (
  '60000000-0000-4000-8000-000000000040'::uuid,
  '00000000-0000-4000-8000-000000000040'::uuid,
  (select id from catalog.channels where code = 'SHOPEE'),
  (select order_id from api.marketplace_orders where external_order_ref = 'PGTAP-MCC-ORDER-RETURN'),
  'PGTAP-MCC-RETURN-1',
  'RETURN_EXPECTED',
  'EXPECTED',
  null,
  '2026-07-20 10:06:00+07'::timestamptz,
  null,
  null,
  'pgtap.marketplace_cancellation',
  '{"test":true}'::jsonb,
  '2026-07-20 10:06:00+07'::timestamptz,
  '2026-07-20 10:06:00+07'::timestamptz
);

insert into operations.return_items (
  id, organization_id, return_id, line_no,
  marketplace_order_item_id, product_id, expected_qty,
  received_qty, sellable_qty, damaged_qty, lost_qty,
  product_sku_snapshot, source_line_ref, created_at, updated_at
) values (
  '61000000-0000-4000-8000-000000000040'::uuid,
  '00000000-0000-4000-8000-000000000040'::uuid,
  '60000000-0000-4000-8000-000000000040'::uuid,
  1,
  (select order_item_id from api.marketplace_reservations where external_order_ref = 'PGTAP-MCC-ORDER-RETURN'),
  '40000000-0000-4000-8000-000000000004'::uuid,
  1, 0, 0, 0, 0,
  'MCC-RETURN',
  'RETURN-LINE-1',
  '2026-07-20 10:06:00+07'::timestamptz,
  '2026-07-20 10:06:00+07'::timestamptz
);

set local role authenticated;

insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_RETURN_CONFLICT', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-RETURN-1', 'PGTAP-MCC-ORDER-RETURN',
  '2026-07-20 10:07:00+07'::timestamptz,
  'CANCELLED_AFTER_SHIPMENT',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000004',
    'orderItemRef', 'ITEM-RETURN',
    'phaseCode', 'POST_SHIPMENT',
    'quantity', 1,
    'sourceLineRef', 'CANCEL-RETURN-1'
  )),
  'Tidak boleh tumpang tindih dengan retur.',
  '{"test":true}'::jsonb
);
select is(
  (select result ->> 'eligible' from marketplace_cancellation_results where kind = 'PREVIEW_RETURN_CONFLICT'),
  'false',
  'post-shipment cancellation is blocked when a return exists'
);
select ok(
  (select result -> 'blockers' from marketplace_cancellation_results where kind = 'PREVIEW_RETURN_CONFLICT') @>
    '[{"code":"MARKETPLACE_CANCELLATION_RETURN_CONFLICT"}]'::jsonb,
  'return conflict blocker is explicit'
);
select is(
  (select remaining_post_cancellable_qty::text from api.marketplace_cancellation_candidates where external_order_ref = 'PGTAP-MCC-ORDER-RETURN'),
  '3',
  'candidate view excludes return-expected quantity from post cancellable quantity'
);

-- Illegal time ordering is rejected.
insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_BEFORE_ORDER', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-BEFORE-ORDER', 'PGTAP-MCC-ORDER-PRE',
  '2026-07-20 08:59:00+07'::timestamptz,
  'CANCELLED',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000002',
    'orderItemRef', 'ITEM-PRE',
    'phaseCode', 'PRE_SHIPMENT',
    'quantity', 1,
    'sourceLineRef', 'CANCEL-BEFORE-ORDER'
  )),
  null,
  '{"test":true}'::jsonb
);
select ok(
  (select result -> 'blockers' from marketplace_cancellation_results where kind = 'PREVIEW_BEFORE_ORDER') @>
    '[{"code":"MARKETPLACE_CANCELLATION_BEFORE_ORDER"}]'::jsonb,
  'cancellation before order time is blocked'
);

insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_BEFORE_SHIPMENT', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-BEFORE-SHIP', 'PGTAP-MCC-ORDER-SPLIT',
  '2026-07-20 09:01:30+07'::timestamptz,
  'CANCELLED_AFTER_SHIPMENT',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000001',
    'orderItemRef', 'ITEM-SPLIT',
    'phaseCode', 'POST_SHIPMENT',
    'quantity', 1,
    'sourceLineRef', 'CANCEL-BEFORE-SHIP'
  )),
  'Event datang sebelum shipment.',
  '{"test":true}'::jsonb
);
select ok(
  (select result -> 'blockers' from marketplace_cancellation_results where kind = 'PREVIEW_BEFORE_SHIPMENT') @>
    '[{"code":"MARKETPLACE_CANCELLATION_BEFORE_SHIPMENT"}]'::jsonb,
  'post-shipment cancellation before shipment time is blocked'
);

-- Multi-line invalid input is rejected without applying the valid line.
insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_ATOMIC_BLOCKED', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-ATOMIC', 'PGTAP-MCC-ORDER-ATOMIC',
  '2026-07-20 10:08:00+07'::timestamptz,
  'CANCELLED',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000002',
      'orderItemRef', 'ITEM-ATOMIC-PRE',
      'phaseCode', 'PRE_SHIPMENT',
      'quantity', 1,
      'sourceLineRef', 'CANCEL-ATOMIC-VALID'
    ),
    jsonb_build_object(
      'productId', '40000000-0000-4000-8000-000000000005',
      'orderItemRef', 'ITEM-ATOMIC-FAIL',
      'phaseCode', 'PRE_SHIPMENT',
      'quantity', 4,
      'sourceLineRef', 'CANCEL-ATOMIC-INVALID'
    )
  ),
  null,
  '{"test":true}'::jsonb
);
select is(
  (select result ->> 'eligible' from marketplace_cancellation_results where kind = 'PREVIEW_ATOMIC_BLOCKED'),
  'false',
  'one invalid line blocks the whole cancellation preview'
);
select throws_ok(
  $sql$
    select api.post_marketplace_cancellation(
      '00000000-0000-4000-8000-000000000040'::uuid,
      'PGTAP-MCC-POST-ATOMIC',
      'SHOPEE', 'PGTAP-MCC-CANCEL-ATOMIC', 'PGTAP-MCC-ORDER-ATOMIC',
      '2026-07-20 10:08:00+07'::timestamptz,
      'CANCELLED',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '40000000-0000-4000-8000-000000000002',
          'orderItemRef', 'ITEM-ATOMIC-PRE',
          'phaseCode', 'PRE_SHIPMENT',
          'quantity', 1,
          'sourceLineRef', 'CANCEL-ATOMIC-VALID'
        ),
        jsonb_build_object(
          'productId', '40000000-0000-4000-8000-000000000005',
          'orderItemRef', 'ITEM-ATOMIC-FAIL',
          'phaseCode', 'PRE_SHIPMENT',
          'quantity', 4,
          'sourceLineRef', 'CANCEL-ATOMIC-INVALID'
        )
      ),
      (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_ATOMIC_BLOCKED'),
      false, null, '{"test":true}'::jsonb
    )
  $sql$,
  'P0001',
  'MARKETPLACE_CANCELLATION_EXCEEDS_OPEN_RESERVATION',
  'blocked multi-line cancellation posts no partial effect'
);
select is(
  (select released_qty::text from api.marketplace_reservations where external_order_ref = 'PGTAP-MCC-ORDER-ATOMIC' and external_item_ref = 'ITEM-ATOMIC-PRE'),
  '0',
  'valid line remains untouched when another line blocks the command'
);
select is(
  (select count(*)::text from operations.marketplace_events where external_event_ref = 'PGTAP-MCC-CANCEL-ATOMIC'),
  '0',
  'blocked multi-line command creates no event'
);

insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_ATOMIC_ONE_ITEM', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-ATOMIC-ONE', 'PGTAP-MCC-ORDER-ATOMIC',
  '2026-07-20 10:08:30+07'::timestamptz,
  'CANCELLED',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000002',
    'orderItemRef', 'ITEM-ATOMIC-PRE',
    'phaseCode', 'PRE_SHIPMENT',
    'quantity', 1,
    'sourceLineRef', 'CANCEL-ATOMIC-ONE'
  )),
  null,
  '{"test":true}'::jsonb
);
insert into marketplace_cancellation_results (kind, result)
select 'POST_ATOMIC_ONE_ITEM', api.post_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-POST-ATOMIC-ONE',
  'SHOPEE', 'PGTAP-MCC-CANCEL-ATOMIC-ONE', 'PGTAP-MCC-ORDER-ATOMIC',
  '2026-07-20 10:08:30+07'::timestamptz,
  'CANCELLED',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000002',
    'orderItemRef', 'ITEM-ATOMIC-PRE',
    'phaseCode', 'PRE_SHIPMENT',
    'quantity', 1,
    'sourceLineRef', 'CANCEL-ATOMIC-ONE'
  )),
  (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_ATOMIC_ONE_ITEM'),
  false,
  null,
  '{"test":true}'::jsonb
);
select is(
  (select released_qty::text from api.marketplace_reservations where external_order_ref = 'PGTAP-MCC-ORDER-ATOMIC' and external_item_ref = 'ITEM-ATOMIC-PRE'),
  '1',
  'one item inside a multi-item order may be cancelled independently'
);
select is(
  (select released_qty::text from api.marketplace_reservations where external_order_ref = 'PGTAP-MCC-ORDER-ATOMIC' and external_item_ref = 'ITEM-ATOMIC-FAIL'),
  '0',
  'cancelling one item does not alter the sibling item'
);

-- A state change after preview invalidates the old basis.
insert into marketplace_cancellation_results (kind, result)
select 'PREVIEW_STALE', api.preview_marketplace_cancellation(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'SHOPEE', 'PGTAP-MCC-CANCEL-STALE', 'PGTAP-MCC-ORDER-ATOMIC',
  '2026-07-20 10:09:00+07'::timestamptz,
  'CANCELLED',
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000002',
    'orderItemRef', 'ITEM-ATOMIC-PRE',
    'phaseCode', 'PRE_SHIPMENT',
    'quantity', 1,
    'sourceLineRef', 'CANCEL-STALE'
  )),
  null,
  '{"test":true}'::jsonb
);

select api.apply_marketplace_event(
  '00000000-0000-4000-8000-000000000040'::uuid,
  'PGTAP-MCC-RELEASE-STALE', 'SHOPEE', 'RELEASE',
  'PGTAP-MCC-EVT-RELEASE-STALE', 'PGTAP-MCC-ORDER-ATOMIC',
  '2026-07-20 10:09:30+07'::timestamptz,
  jsonb_build_array(jsonb_build_object(
    'productId', '40000000-0000-4000-8000-000000000002',
    'quantity', 1,
    'sourceLineRef', 'ITEM-ATOMIC-PRE'
  )),
  'Mutate basis after preview.', '{"test":true}'::jsonb
);

select throws_ok(
  $sql$
    select api.post_marketplace_cancellation(
      '00000000-0000-4000-8000-000000000040'::uuid,
      'PGTAP-MCC-POST-STALE',
      'SHOPEE', 'PGTAP-MCC-CANCEL-STALE', 'PGTAP-MCC-ORDER-ATOMIC',
      '2026-07-20 10:09:00+07'::timestamptz,
      'CANCELLED',
      jsonb_build_array(jsonb_build_object(
        'productId', '40000000-0000-4000-8000-000000000002',
        'orderItemRef', 'ITEM-ATOMIC-PRE',
        'phaseCode', 'PRE_SHIPMENT',
        'quantity', 1,
        'sourceLineRef', 'CANCEL-STALE'
      )),
      (select result ->> 'basisHash' from marketplace_cancellation_results where kind = 'PREVIEW_STALE'),
      false, null, '{"test":true}'::jsonb
    )
  $sql$,
  'P0001',
  'STALE_MARKETPLACE_CANCELLATION_PREVIEW',
  'state change after preview rejects the stale cancellation commit'
);
select is(
  (select count(*)::text from operations.marketplace_events where external_event_ref = 'PGTAP-MCC-CANCEL-STALE'),
  '0',
  'stale cancellation creates no event'
);

-- Tenant isolation.
select throws_ok(
  $sql$
    select api.preview_marketplace_cancellation(
      '00000000-0000-4000-8000-000000000041'::uuid,
      'SHOPEE', 'PGTAP-MCC-CROSS-ORG', 'PGTAP-MCC-ORDER-PRE',
      '2026-07-20 10:10:00+07'::timestamptz,
      'CANCELLED',
      jsonb_build_array(jsonb_build_object(
        'productId', '40000000-0000-4000-8000-000000000002',
        'orderItemRef', 'ITEM-PRE',
        'phaseCode', 'PRE_SHIPMENT',
        'quantity', 1,
        'sourceLineRef', 'CROSS-ORG'
      )),
      null, '{"test":true}'::jsonb
    )
  $sql$,
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'authenticated Admin cannot preview another organization cancellation'
);

-- Read models and immutable audit history.
select is(
  (select cancellation_status_code from api.marketplace_orders where external_order_ref = 'PGTAP-MCC-ORDER-SPLIT'),
  'POST_SHIPMENT',
  'order read model exposes post-shipment cancellation state'
);
select is(
  (select shipped_qty::text from api.marketplace_orders where external_order_ref = 'PGTAP-MCC-ORDER-SPLIT'),
  '8',
  'historical shipped quantity remains unchanged after cancellation reversal'
);
select is(
  (select count(*)::text from api.marketplace_cancellation_lines where external_event_ref = 'PGTAP-MCC-CANCEL-MIXED-1'),
  '2',
  'cancellation line view preserves explicit per-phase lines'
);
select is(
  (select count(*)::text from api.marketplace_cancellation_applications where external_event_ref = 'PGTAP-MCC-CANCEL-MULTI-1'),
  '2',
  'application view exposes both original shipment reversal links'
);

reset role;

select throws_ok(
  $sql$
    insert into operations.marketplace_cancellation_applications (
      organization_id,
      cancellation_line_id,
      application_no,
      effect_code,
      quantity_applied,
      reservation_id,
      marketplace_ship_allocation_id,
      stock_reversal_application_id,
      created_at
    )
    select
      cancellation_line.organization_id,
      cancellation_line.id,
      2,
      'PRE_SHIPMENT_RELEASE',
      1,
      cancellation_line.reservation_id,
      null,
      null,
      clock_timestamp()
    from operations.marketplace_cancellation_lines cancellation_line
    join operations.marketplace_cancellations cancellation
      on cancellation.id = cancellation_line.cancellation_id
    where cancellation.external_event_ref = 'PGTAP-MCC-CANCEL-PRE-1'
  $sql$,
  'P0001',
  'MARKETPLACE_CANCELLATION_APPLICATION_OVER_APPLIED',
  'application trigger prevents cancellation quantity over-application'
);

select throws_ok(
  $sql$
    update operations.marketplace_cancellations
    set note = 'mutated'
    where external_event_ref = 'PGTAP-MCC-CANCEL-SPLIT-1'
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'posted cancellation headers are immutable'
);
select throws_ok(
  $sql$
    update operations.marketplace_cancellation_lines
    set quantity_cancelled = quantity_cancelled + 1
    where cancellation_id = (
      select id from operations.marketplace_cancellations
      where external_event_ref = 'PGTAP-MCC-CANCEL-SPLIT-1'
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'posted cancellation lines are immutable'
);
select throws_ok(
  $sql$
    delete from operations.marketplace_cancellation_applications
    where cancellation_line_id = (
      select id from operations.marketplace_cancellation_lines
      where cancellation_id = (
        select id from operations.marketplace_cancellations
        where external_event_ref = 'PGTAP-MCC-CANCEL-SPLIT-1'
      )
      limit 1
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'cancellation applications are immutable'
);
select throws_ok(
  $sql$
    update operations.marketplace_ship_allocations
    set quantity_allocated = quantity_allocated + 1
    where event_id = (
      select event_id from api.marketplace_events
      where external_event_ref = 'PGTAP-MCC-EVT-SHIP-SPLIT'
    )
  $sql$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'original shipment allocations remain immutable'
);

-- Final ledger/projection consistency.
select is(
  (
    select count(*)::text
    from (
      select
        balance.product_id,
        balance.batch_id
      from inventory.stock_batch_balances balance
      left join lateral (
        select
          coalesce(sum(entry.quantity_delta) filter (where entry.bucket_code = 'SELLABLE'), 0)::bigint as sellable_qty,
          coalesce(sum(entry.quantity_delta) filter (where entry.bucket_code = 'QUARANTINE'), 0)::bigint as quarantine_qty,
          coalesce(sum(entry.quantity_delta) filter (where entry.bucket_code = 'DAMAGED'), 0)::bigint as damaged_qty
        from inventory.stock_ledger_entries entry
        where entry.organization_id = balance.organization_id
          and entry.product_id = balance.product_id
          and entry.batch_id = balance.batch_id
      ) ledger on true
      where balance.organization_id = '00000000-0000-4000-8000-000000000040'::uuid
        and (
          balance.sellable_qty <> ledger.sellable_qty
          or balance.quarantine_qty <> ledger.quarantine_qty
          or balance.damaged_qty <> ledger.damaged_qty
        )
    ) mismatch
  ),
  '0',
  'all cancellation batch projections remain equal to ledger totals'
);
select is(
  (
    select count(*)::text
    from (
      select position.product_id
      from inventory.stock_product_positions position
      left join lateral (
        select
          coalesce(sum(entry.quantity_delta) filter (where entry.bucket_code = 'SELLABLE'), 0)::bigint as sellable_qty,
          coalesce(sum(entry.quantity_delta) filter (where entry.bucket_code = 'QUARANTINE'), 0)::bigint as quarantine_qty,
          coalesce(sum(entry.quantity_delta) filter (where entry.bucket_code = 'DAMAGED'), 0)::bigint as damaged_qty
        from inventory.stock_ledger_entries entry
        where entry.organization_id = position.organization_id
          and entry.product_id = position.product_id
      ) ledger on true
      where position.organization_id = '00000000-0000-4000-8000-000000000040'::uuid
        and (
          position.sellable_qty <> ledger.sellable_qty
          or position.quarantine_qty <> ledger.quarantine_qty
          or position.damaged_qty <> ledger.damaged_qty
        )
    ) mismatch
  ),
  '0',
  'all cancellation product projections remain equal to ledger totals'
);
select is(
  (
    select count(*)::text
    from inventory.stock_product_positions position
    where position.organization_id = '00000000-0000-4000-8000-000000000040'::uuid
      and position.reserved_qty > position.sellable_qty
  ),
  '0',
  'cancellation never leaves reserved quantity above sellable stock'
);
select is(
  (
    select count(*)::text
    from inventory.stock_reversal_applications application
    join inventory.stock_ledger_entries original_entry
      on original_entry.id = application.original_entry_id
    join inventory.stock_ledger_entries reversal_entry
      on reversal_entry.id = application.reversal_entry_id
    where application.organization_id = '00000000-0000-4000-8000-000000000040'::uuid
      and (
        original_entry.product_id <> reversal_entry.product_id
        or original_entry.batch_id <> reversal_entry.batch_id
        or original_entry.bucket_code <> reversal_entry.bucket_code
        or original_entry.quantity_delta >= 0
        or application.quantity_applied <= 0
        or application.quantity_applied > abs(original_entry.quantity_delta)
        or (
          select coalesce(sum(other_application.quantity_applied), 0)
          from inventory.stock_reversal_applications other_application
          where other_application.original_entry_id =
            application.original_entry_id
        ) > abs(original_entry.quantity_delta)
        or reversal_entry.quantity_delta <> application.quantity_applied
      )
  ),
  '0',
  'every cancellation reversal restores the exact original stock identity'
);

reset role;
select * from finish();
rollback;
