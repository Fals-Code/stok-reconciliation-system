begin;
create extension if not exists pgtap with schema extensions;
select plan(38);

-- Seed data dasar: Organizations, Users, User Profiles
insert into app.organizations (id, code, name, timezone, is_active, created_at) values
('00000000-0000-4000-8000-000000000072', 'ORG_PROMO_72', 'Org Promo 72', 'Asia/Jakarta', true, '2026-08-13 08:00:00+07'),
('00000000-0000-4000-8000-000000000073', 'ORG_PROMO_73', 'Org Promo 73', 'Asia/Jakarta', true, '2026-08-13 08:00:00+07');

insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous) values
('00000000-0000-0000-0000-000000000000', '97000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'admin72@glowlab.invalid', '2026-08-13 08:00:00+07', '{"provider":"email","providers":["email"]}'::jsonb, '{}', '2026-08-13 08:00:00+07', '2026-08-13 08:00:00+07', false, false),
('00000000-0000-0000-0000-000000000000', '97000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'admin73@glowlab.invalid', '2026-08-13 08:00:00+07', '{"provider":"email","providers":["email"]}'::jsonb, '{}', '2026-08-13 08:00:00+07', '2026-08-13 08:00:00+07', false, false);

insert into app.user_profiles (user_id, organization_id, display_name, employee_code, role_code, is_active) values
('97000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000072', 'Admin Promo 72', 'EMP-72', 'ADMIN', true),
('97000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000073', 'Admin Promo 73', 'EMP-73', 'ADMIN', true);

-- Seed data katalog & inventori
insert into catalog.products (id, organization_id, sku, name, is_active, is_batch_tracked, is_expiry_tracked, created_at, updated_at) values
('72000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000072', 'PROD-72-A', 'Product 72 A', true, true, true, '2026-08-13 08:00:00+07', '2026-08-13 08:00:00+07');

insert into catalog.product_batches (id, organization_id, product_id, batch_code, expiry_date, status_code, received_first_at, created_at, updated_at) values
('72000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000072', '72000000-0000-4000-8000-000000000001', 'BATCH-72-A-1', '2026-12-31', 'ACTIVE', '2026-08-13 08:00:00+07', '2026-08-13 08:00:00+07', '2026-08-13 08:00:00+07');

insert into inventory.idempotency_commands (
  id, organization_id, scope, key, request_hash, status_code, started_at, completed_at, response_snapshot
) values (
  '72000000-0000-4000-8000-000000000006',
  '00000000-0000-4000-8000-000000000072',
  'RECEIPT',
  'seed-key-1',
  'e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0',
  'SUCCEEDED',
  '2026-08-13 08:00:00+07'::timestamptz,
  '2026-08-13 08:00:00+07'::timestamptz,
  '{}'::jsonb
);

insert into inventory.stock_transactions (
  id, organization_id, transaction_no, transaction_type_code,
  reason_id, reason_code_snapshot, channel_id, channel_code_snapshot,
  source_type_code, source_ref_snapshot, created_by_role_code,
  idempotency_command_id, actor_user_id,
  occurred_at, recorded_at, effective_local_date, schema_version
) values (
  '72000000-0000-4000-8000-000000000000',
  '00000000-0000-4000-8000-000000000072',
  'SEED-TRX-1',
  'RECEIPT',
  (select id from catalog.movement_reasons where code = 'MAKLON_RECEIPT' and direction_code = 'INBOUND' limit 1),
  'MAKLON_RECEIPT',
  (select id from catalog.channels where code = 'MANUAL' limit 1),
  'MANUAL',
  'RECEIPT',
  'seed-ref-1',
  'ADMIN',
  '72000000-0000-4000-8000-000000000006',
  '97000000-0000-4000-8000-000000000003',
  '2026-08-13 08:00:00+07'::timestamptz,
  '2026-08-13 08:00:00+07'::timestamptz,
  '2026-08-13',
  1
);

insert into inventory.stock_ledger_entries (
  id, organization_id, transaction_id, line_no, product_id, batch_id,
  product_sku_snapshot, batch_code_snapshot, expiry_date_snapshot,
  bucket_code, quantity_delta, entry_role_code, pair_no, source_line_ref,
  occurred_at, recorded_at, created_at
)
values (
  '72000000-0000-4000-8000-000000000005',
  '00000000-0000-4000-8000-000000000072',
  '72000000-0000-4000-8000-000000000000',
  1,
  '72000000-0000-4000-8000-000000000001',
  '72000000-0000-4000-8000-000000000002',
  'PROD-72-A',
  'BATCH-72-A-1',
  '2026-12-31',
  'SELLABLE',
  100,
  'EXTERNAL_IN',
  null,
  'seed-line-1',
  '2026-08-13 08:00:00+07'::timestamptz,
  '2026-08-13 08:00:00+07'::timestamptz,
  '2026-08-13 08:00:00+07'::timestamptz
);

insert into inventory.stock_product_positions (organization_id, product_id, sellable_qty, reserved_qty, version, last_ledger_seq, updated_at) values
('00000000-0000-4000-8000-000000000072', '72000000-0000-4000-8000-000000000001', 100, 0, 1, (select ledger_seq from inventory.stock_ledger_entries where id = '72000000-0000-4000-8000-000000000005'), '2026-08-13 08:00:00+07');

insert into inventory.stock_batch_balances (organization_id, product_id, batch_id, sellable_qty, version, last_ledger_seq, updated_at) values
('00000000-0000-4000-8000-000000000072', '72000000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000002', 100, 1, (select ledger_seq from inventory.stock_ledger_entries where id = '72000000-0000-4000-8000-000000000005'), '2026-08-13 08:00:00+07');

-- Seed Promo references
insert into catalog.promo_references (id, organization_id, code, name, description, is_active, created_at, updated_at, row_version) values
('72000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000072', 'PROMO72A', 'Promo 72 Active', 'Promo Aktif', true, '2026-08-13 08:00:00+07', '2026-08-13 08:00:00+07', 1),
('72000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000072', 'PROMO72I', 'Promo 72 Inactive', 'Promo Tidak Aktif', false, '2026-08-13 08:00:00+07', '2026-08-13 08:00:00+07', 1),
('73000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000073', 'PROMO73A', 'Promo 73 Active', 'Promo Aktif', true, '2026-08-13 08:00:00+07', '2026-08-13 08:00:00+07', 1);

-- Temp tables untuk hasil pengujian
create temp table results_preview (kind text primary key, res jsonb not null) on commit drop;
create temp table results_post (kind text primary key, res jsonb not null) on commit drop;
create temp table baseline_stock (phase text primary key, snapshot jsonb not null) on commit drop;

grant select, insert, update on results_preview, results_post, baseline_stock to authenticated;

-- Stock domain baseline
insert into baseline_stock values (
  'ZERO',
  jsonb_build_object(
    'tx', (select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4000-8000-000000000072'),
    'ledger', (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4000-8000-000000000072'),
    'positions', (select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4000-8000-000000000072'),
    'balances', (select count(*) from inventory.stock_batch_balances where organization_id = '00000000-0000-4000-8000-000000000072'),
    'reservations', (select count(*) from inventory.stock_reservations where organization_id = '00000000-0000-4000-8000-000000000072'),
    'manual_outbounds', (select count(*) from operations.manual_outbounds where organization_id = '00000000-0000-4000-8000-000000000072')
  )
);

-- Set JWT & Local Role ke Admin 72
select set_config('request.jwt.claim.sub', '97000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', '97000000-0000-4000-8000-000000000003', 'role', 'authenticated', 'email', 'admin72@glowlab.invalid')::text, true);
set local role authenticated;


-- 1. CONTRACT VERIFICATION
select has_function('inventory', 'preview_manual_outbound_core', array['uuid', 'text', 'timestamptz', 'text', 'jsonb', 'text', 'jsonb', 'boolean']::text[], 'preview_manual_outbound_core function exists');
select has_function('api', 'post_manual_outbound', array['uuid', 'text', 'text', 'timestamptz', 'text', 'jsonb', 'text', 'jsonb']::text[], 'api.post_manual_outbound internal function exists');

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'inventory'
      and p.proname = 'preview_manual_outbound_core'
      and p.prosecdef
  ),
  1::bigint,
  'preview_manual_outbound_core is SECURITY DEFINER'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'api'
      and p.proname = 'post_manual_outbound'
      and p.proconfig is not null
      and p.proconfig[1] like 'search_path=%'
  ),
  2::bigint, -- both signatures have fixed search_path
  'post_manual_outbound has fixed search_path'
);

-- PUBLIC EXECUTE check on post_manual_outbound (8 params)
select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where n.nspname = 'api'
      and p.proname = 'post_manual_outbound'
      and a.grantee = 0
      and a.privilege_type = 'EXECUTE'
  ),
  0::bigint,
  'PUBLIC has no EXECUTE on api.post_manual_outbound'
);


-- 2. PREVIEW TESTS
-- Skenario: Active Promo Code Accepted
insert into results_preview select 'ACTIVE_PROMO', api.preview_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'ref-active-promo-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'PROMO',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 10,
      'sourceLineRef', 'line-1'
    )
  ),
  'Catatan manual outbound',
  jsonb_build_object('reference', 'promo72a')
);

select is(
  (select res->>'status' from results_preview where kind = 'ACTIVE_PROMO'),
  'PREVIEW_READY',
  'Active promo code returns PREVIEW_READY'
);

select is(
  (select res->'promoReference'->>'id' from results_preview where kind = 'ACTIVE_PROMO'),
  '72000000-0000-4000-8000-000000000003',
  'Preview returns exact canonical promo reference ID'
);

select is(
  (select res->'promoReference'->>'code' from results_preview where kind = 'ACTIVE_PROMO'),
  'PROMO72A',
  'Preview returns normalized canonical promo reference code'
);

select is(
  (select res->'promoReference'->>'name' from results_preview where kind = 'ACTIVE_PROMO'),
  'Promo 72 Active',
  'Preview returns canonical promo reference name'
);

-- Skenario: Unknown Promo Code Blocked
insert into results_preview select 'UNKNOWN_PROMO', api.preview_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'ref-unknown-promo-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'PROMO',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 10,
      'sourceLineRef', 'line-1'
    )
  ),
  'Catatan manual outbound',
  jsonb_build_object('reference', 'PROMO_UNKNOWN')
);

select is(
  (select res->>'status' from results_preview where kind = 'UNKNOWN_PROMO'),
  'BLOCKED',
  'Unknown promo code is BLOCKED'
);

select is(
  (select res->'blockers'->0->>'code' from results_preview where kind = 'UNKNOWN_PROMO'),
  'OUTBOUND_PROMO_REFERENCE_INVALID',
  'Blocker code is OUTBOUND_PROMO_REFERENCE_INVALID for unknown promo'
);

-- Skenario: Inactive Promo Code Blocked
insert into results_preview select 'INACTIVE_PROMO', api.preview_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'ref-inactive-promo-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'PROMO',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 10,
      'sourceLineRef', 'line-1'
    )
  ),
  'Catatan manual outbound',
  jsonb_build_object('reference', 'promo72i')
);

select is(
  (select res->>'status' from results_preview where kind = 'INACTIVE_PROMO'),
  'BLOCKED',
  'Inactive promo code is BLOCKED'
);

select is(
  (select res->'blockers'->0->>'code' from results_preview where kind = 'INACTIVE_PROMO'),
  'OUTBOUND_PROMO_REFERENCE_INVALID',
  'Blocker code is OUTBOUND_PROMO_REFERENCE_INVALID for inactive promo'
);

-- Skenario: Cross-org Promo Code Blocked
insert into results_preview select 'CROSS_ORG_PROMO', api.preview_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'ref-cross-promo-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'PROMO',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 10,
      'sourceLineRef', 'line-1'
    )
  ),
  'Catatan manual outbound',
  jsonb_build_object('reference', 'promo73a') -- belongs to Org 73
);

select is(
  (select res->>'status' from results_preview where kind = 'CROSS_ORG_PROMO'),
  'BLOCKED',
  'Cross-org promo code is BLOCKED'
);

select is(
  (select res->'blockers'->0->>'code' from results_preview where kind = 'CROSS_ORG_PROMO'),
  'OUTBOUND_PROMO_REFERENCE_INVALID',
  'Blocker code is OUTBOUND_PROMO_REFERENCE_INVALID for cross-org promo'
);

-- Skenario: Missing Promo Reference Blocked
insert into results_preview select 'MISSING_REF', api.preview_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'ref-missing-promo-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'PROMO',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 10,
      'sourceLineRef', 'line-1'
    )
  ),
  'Catatan manual outbound',
  '{}'::jsonb
);

select is(
  (select res->>'status' from results_preview where kind = 'MISSING_REF'),
  'BLOCKED',
  'Missing reference is BLOCKED'
);

select is(
  (select res->'blockers'->0->>'code' from results_preview where kind = 'MISSING_REF'),
  'OUTBOUND_REASON_REFERENCE_REQUIRED',
  'Blocker is OUTBOUND_REASON_REFERENCE_REQUIRED when reference field is absent'
);

-- Preview stock neutrality verification
select is(
  (select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4000-8000-000000000072'),
  (select (snapshot->>'tx')::bigint from baseline_stock where phase = 'ZERO'),
  'Preview did not write any stock transaction records'
);

select is(
  (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4000-8000-000000000072'),
  (select (snapshot->>'ledger')::bigint from baseline_stock where phase = 'ZERO'),
  'Preview did not write any stock ledger entry records'
);


-- 3. POST & PERSISTENCE TESTS
-- Skenario: Valid Promo Post
insert into results_post select 'POST_PROMO_OK', api.post_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'idemp-promo-post-1',
  'ref-active-promo-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'PROMO',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 10,
      'sourceLineRef', 'line-1'
    )
  ),
  (select res->>'basisHash' from results_preview where kind = 'ACTIVE_PROMO'), -- wait, let's select the basis hash directly
  true,
  'Catatan manual outbound',
  jsonb_build_object('reference', 'promo72a')
);

select is(
  (select res->>'status' from results_post where kind = 'POST_PROMO_OK'),
  'POSTED',
  'Valid active promo post succeeded'
);

-- Verify database-enrichment metadata in manual_outbounds
select is(
  (
    select metadata->'promoReference'->>'id'
    from operations.manual_outbounds
    where organization_id = '00000000-0000-4000-8000-000000000072'
      and source_ref = 'ref-active-promo-1'
  ),
  '72000000-0000-4000-8000-000000000003',
  'Posted manual outbound metadata contains canonical Promo ID'
);

select is(
  (
    select metadata->'promoReference'->>'code'
    from operations.manual_outbounds
    where organization_id = '00000000-0000-4000-8000-000000000072'
      and source_ref = 'ref-active-promo-1'
  ),
  'PROMO72A',
  'Posted manual outbound metadata contains canonical Promo Code'
);

select is(
  (
    select metadata->'promoReference'->>'name'
    from operations.manual_outbounds
    where organization_id = '00000000-0000-4000-8000-000000000072'
      and source_ref = 'ref-active-promo-1'
  ),
  'Promo 72 Active',
  'Posted manual outbound metadata contains canonical Promo Name'
);

-- Verify database-enrichment metadata in stock_transactions
select is(
  (
    select metadata->'promoReference'->>'id'
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000072'
      and source_ref_snapshot = 'ref-active-promo-1'
  ),
  '72000000-0000-4000-8000-000000000003',
  'Posted stock transaction metadata contains canonical Promo ID'
);


-- 4. IDEMPOTENCY & REPLAY TESTS
-- Same payload replay should succeed
insert into results_post select 'POST_PROMO_REPLAY', api.post_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'idemp-promo-post-1',
  'ref-active-promo-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'PROMO',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 10,
      'sourceLineRef', 'line-1'
    )
  ),
  (select res->>'basisHash' from results_preview where kind = 'ACTIVE_PROMO'),
  true,
  'Catatan manual outbound',
  jsonb_build_object('reference', 'promo72a')
);

select is(
  (select res->>'outboundId' from results_post where kind = 'POST_PROMO_REPLAY'),
  (select res->>'outboundId' from results_post where kind = 'POST_PROMO_OK'),
  'Idempotent replay returns the exact same outbound ID'
);

-- Replay after Promo master deactivated should still succeed (since the transaction was already posted)
select api.archive_promo_reference(
  '00000000-0000-4000-8000-000000000072',
  'key-archive-71-a',
  '72000000-0000-4000-8000-000000000003',
  1,
  'Archive dari test 071'
);

insert into results_post select 'POST_PROMO_REPLAY_INACTIVE', api.post_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'idemp-promo-post-1',
  'ref-active-promo-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'PROMO',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 10,
      'sourceLineRef', 'line-1'
    )
  ),
  (select res->>'basisHash' from results_preview where kind = 'ACTIVE_PROMO'),
  true,
  'Catatan manual outbound',
  jsonb_build_object('reference', 'promo72a')
);

select is(
  (select res->>'outboundId' from results_post where kind = 'POST_PROMO_REPLAY_INACTIVE'),
  (select res->>'outboundId' from results_post where kind = 'POST_PROMO_OK'),
  'Replay succeeds even if Promo master becomes inactive after posting'
);

-- Replay with different payload throws IDEMPOTENCY_KEY_REUSED
select throws_ok(
  $sql$select api.post_manual_outbound(
    '00000000-0000-4000-8000-000000000072',
    'idemp-promo-post-1',
    'ref-active-promo-1',
    '2026-08-13 10:00:00+07'::timestamptz,
    'PROMO',
    jsonb_build_array(
      jsonb_build_object(
        'productId', '72000000-0000-4000-8000-000000000001',
        'quantity', 20, -- changed quantity
        'sourceLineRef', 'line-1'
      )
    ),
    'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0',
    true,
    'Catatan post promo',
    jsonb_build_object('reference', 'promo72a')
  )$sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'Reusing idempotency key with different payload is rejected'
);

-- Reactivate Promo 72 Active for subsequent stale/concurrency tests
select api.reactivate_promo_reference(
  '00000000-0000-4000-8000-000000000072',
  'key-reactivate-71-a',
  '72000000-0000-4000-8000-000000000003',
  2,
  'Reactivate dari test 071'
);


-- 5. STALE PREVIEW / MUTATION TESTS
-- Skenario: Rename master changes basis -> Post old basis rejected
insert into results_preview select 'ACTIVE_PROMO_STALE_1', api.preview_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'ref-stale-promo-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'PROMO',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 5,
      'sourceLineRef', 'line-1'
    )
  ),
  'Catatan manual outbound',
  jsonb_build_object('reference', 'promo72a')
);

-- Rename promo reference
select api.update_promo_reference(
  '00000000-0000-4000-8000-000000000072',
  'key-update-71-a',
  '72000000-0000-4000-8000-000000000003',
  3,
  'Promo 72 Active Renamed',
  'Deskripsi ter-update di 071',
  'Catatan update 071'
);

-- Posting using old basis hash should fail with STALE_MANUAL_OUTBOUND_PREVIEW
select throws_ok(
  format(
    $sql$select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000072',
      'idemp-stale-promo-1',
      'ref-stale-promo-1',
      '2026-08-13 10:00:00+07'::timestamptz,
      'PROMO',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '72000000-0000-4000-8000-000000000001',
          'quantity', 5,
          'sourceLineRef', 'line-1'
        )
      ),
      '%s', -- old basis hash
      true,
      'Catatan post promo',
      jsonb_build_object('reference', 'promo72a')
    )$sql$,
    (select res->>'basisHash' from results_preview where kind = 'ACTIVE_PROMO_STALE_1')
  ),
  'P0001',
  'STALE_MANUAL_OUTBOUND_PREVIEW',
  'Post using basis before Promo rename is rejected with STALE_MANUAL_OUTBOUND_PREVIEW'
);


-- Skenario: Deactivate master changes basis -> Post old basis rejected
insert into results_preview select 'ACTIVE_PROMO_STALE_2', api.preview_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'ref-stale-promo-2',
  '2026-08-13 10:00:00+07'::timestamptz,
  'PROMO',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 5,
      'sourceLineRef', 'line-1'
    )
  ),
  'Catatan manual outbound',
  jsonb_build_object('reference', 'promo72a')
);

-- Deactivate promo reference
select api.archive_promo_reference(
  '00000000-0000-4000-8000-000000000072',
  'key-archive-71-b',
  '72000000-0000-4000-8000-000000000003',
  4,
  'Archive dari test 071 stale 2'
);

-- Posting using old basis hash should fail
select throws_ok(
  format(
    $sql$select api.post_manual_outbound(
      '00000000-0000-4000-8000-000000000072',
      'idemp-stale-promo-2',
      'ref-stale-promo-2',
      '2026-08-13 10:00:00+07'::timestamptz,
      'PROMO',
      jsonb_build_array(
        jsonb_build_object(
          'productId', '72000000-0000-4000-8000-000000000001',
          'quantity', 5,
          'sourceLineRef', 'line-1'
        )
      ),
      '%s', -- old basis hash
      true,
      'Catatan post promo',
      jsonb_build_object('reference', 'promo72a')
    )$sql$,
    (select res->>'basisHash' from results_preview where kind = 'ACTIVE_PROMO_STALE_2')
  ),
  'P0001',
  'STALE_MANUAL_OUTBOUND_PREVIEW',
  'Post using basis before Promo deactivation is rejected with STALE_MANUAL_OUTBOUND_PREVIEW'
);


-- 6. REVERSAL TEST
select has_function('api', 'reverse_stock_transaction', array['uuid', 'text', 'uuid', 'text', 'boolean', 'text', 'jsonb']::text[], 'reverse_stock_transaction exists');

-- We perform the preview of reversal
insert into results_preview select 'REVERSAL_PREVIEW', api.preview_stock_transaction_reversal(
  '00000000-0000-4000-8000-000000000072',
  (select (res->>'transactionId')::uuid from results_post where kind = 'POST_PROMO_OK')
);

select is(
  (select res->>'status' from results_preview where kind = 'REVERSAL_PREVIEW'),
  'PREVIEW_READY',
  'Preview of reversal succeeded'
);

-- We perform the reversal of our successful outbound transaction 'POST_PROMO_OK'
insert into results_post select 'REVERSAL_OK', api.reverse_stock_transaction(
  '00000000-0000-4000-8000-000000000072',
  'idemp-reversal-1',
  (select (res->>'transactionId')::uuid from results_post where kind = 'POST_PROMO_OK'),
  (select res->>'basisHash' from results_preview where kind = 'REVERSAL_PREVIEW'),
  true,
  'Reversal outbound promo',
  '{}'::jsonb
);

select is(
  (select res->>'status' from results_post where kind = 'REVERSAL_OK'),
  'REVERSED',
  'Reversal of promo outbound succeeded'
);

-- Reversal links to original transaction
select is(
  (
    select reversal_of_transaction_id
    from inventory.stock_transactions
    where organization_id = '00000000-0000-4000-8000-000000000072'
      and id = (select (res->>'reversalTransactionId')::uuid from results_post where kind = 'REVERSAL_OK')
  ),
  (select (res->>'transactionId')::uuid from results_post where kind = 'POST_PROMO_OK'),
  'Reversal transaction links to original transaction'
);

-- Original Promo transaction metadata remains unchanged/readable
select is(
  (
    select metadata->'promoReference'->>'id'
    from inventory.stock_transactions
    where id = (select (res->>'transactionId')::uuid from results_post where kind = 'POST_PROMO_OK')
  ),
  '72000000-0000-4000-8000-000000000003',
  'Original transaction metadata remains unchanged and readable'
);

-- Original promoReference snapshot is still exact after reversal
select is(
  (
    select metadata->'promoReference'->>'code'
    from inventory.stock_transactions
    where id = (select (res->>'transactionId')::uuid from results_post where kind = 'POST_PROMO_OK')
  ),
  'PROMO72A',
  'Original promoReference snapshot is still exact after reversal'
);

-- Reversal produces only expected reversal ledger effect
select is(
  (
    select sum(quantity_delta)::bigint
    from inventory.stock_ledger_entries
    where transaction_id = (select (res->>'reversalTransactionId')::uuid from results_post where kind = 'REVERSAL_OK')
  ),
  10::bigint,
  'Reversal produces only expected reversal ledger effect (+10)'
);


-- 7. COMPATIBILITY TESTS
-- BONUS with existing generic reference still works
insert into results_preview select 'BONUS_OK', api.preview_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'ref-bonus-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'BONUS',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 5,
      'sourceLineRef', 'line-1'
    )
  ),
  'Bonus outbound text reference',
  jsonb_build_object('reference', 'GENERIC_BONUS_TEXT_123')
);

select is(
  (select res->>'status' from results_preview where kind = 'BONUS_OK'),
  'PREVIEW_READY',
  'BONUS with generic text reference is accepted in preview'
);

insert into results_post select 'POST_BONUS_OK', api.post_manual_outbound(
  '00000000-0000-4000-8000-000000000072',
  'idemp-bonus-post-1',
  'ref-bonus-1',
  '2026-08-13 10:00:00+07'::timestamptz,
  'BONUS',
  jsonb_build_array(
    jsonb_build_object(
      'productId', '72000000-0000-4000-8000-000000000001',
      'quantity', 5,
      'sourceLineRef', 'line-1'
    )
  ),
  (select res->>'basisHash' from results_preview where kind = 'BONUS_OK'),
  true,
  'Bonus outbound text reference',
  jsonb_build_object('reference', 'GENERIC_BONUS_TEXT_123')
);

select is(
  (select res->>'status' from results_post where kind = 'POST_BONUS_OK'),
  'POSTED',
  'BONUS post with generic text reference succeeds'
);

-- Finish pgTAP tests
select * from finish();
rollback;
