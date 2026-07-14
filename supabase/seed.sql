-- ============================================================================
-- File: seed.sql
-- Project: Sistem Rekonsiliasi Stok
-- Version: 1.0.0
-- Last updated: 2026-07-13
-- Target: Supabase local / test / staging / isolated demo environment
-- Timezone: Asia/Jakarta
-- Application role model: ADMIN only
--
-- Place this file at:
--   supabase/seed.sql
--
-- Supabase executes seed files after all migrations during:
--   supabase start
--   supabase db reset
--
-- IMPORTANT:
-- 1. This file contains data insertions and verification only.
-- 2. This file MUST NOT be used as a production catalog or initial-balance
--    import mechanism.
-- 3. Production opening balances must be posted through the approved domain
--    import/cutover flow and reconciliation.
-- 4. Auth users are intentionally not inserted directly into auth.users.
--    Create demo.admin@glowlab.invalid through the trusted Supabase Auth Admin
--    API. If that user already exists when this seed runs, its Admin profile is
--    attached automatically.
-- 5. The seed contains no prices or monetary values.
-- ============================================================================

begin;

set local time zone 'Asia/Jakarta';
set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- ----------------------------------------------------------------------------
-- 0. Safety guard
-- ----------------------------------------------------------------------------

do $guard$
declare
  v_environment text :=
    lower(coalesce(current_setting('app.environment', true), 'local'));
begin
  if v_environment in ('production', 'prod') then
    raise exception
      'SEED_PRODUCTION_FORBIDDEN: seed.sql is only for local/test/staging/demo';
  end if;
end
$guard$;

-- ----------------------------------------------------------------------------
-- 1. Deterministic identifiers
-- ----------------------------------------------------------------------------
--
-- Organization
--   00000000-0000-4000-8000-000000000001  GlowLab Demo
--
-- Channels
--   10000000-0000-4000-8000-000000000001  MANUAL
--   10000000-0000-4000-8000-000000000002  SHOPEE
--   10000000-0000-4000-8000-000000000003  TIKTOK_SHOP
--   10000000-0000-4000-8000-000000000004  IMPORT
--   10000000-0000-4000-8000-000000000005  SIMULATOR
--   10000000-0000-4000-8000-000000000006  SYSTEM
--
-- Products
--   30000000-0000-4000-8000-000000000001  SER-NIA-30
--   30000000-0000-4000-8000-000000000002  CLN-GEN-100
--   30000000-0000-4000-8000-000000000003  TNR-HYD-100
--
-- The bundle listing BND-GLOW-01 is intentionally NOT inserted as stock.
-- It exists only as a channel recipe.

-- ----------------------------------------------------------------------------
-- 2. Organization
-- ----------------------------------------------------------------------------

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
  '00000000-0000-4000-8000-000000000001'::uuid,
  'GLOWLAB_DEMO',
  'GlowLab Demo',
  'Asia/Jakarta',
  true,
  '2026-07-15 07:00:00+07'::timestamptz,
  null
)
on conflict (code) do update
set
  name = excluded.name,
  timezone = excluded.timezone,
  is_active = excluded.is_active;

-- ----------------------------------------------------------------------------
-- 3. Optional compatibility seed for legacy app.roles
--    Latest design uses app.user_profiles.role_code = ADMIN and does not need
--    a runtime role-assignment model. This block only supports older migrations.
-- ----------------------------------------------------------------------------

do $legacy_roles$
begin
  if to_regclass('app.roles') is not null then
    execute $sql$
      insert into app.roles (
        id,
        code,
        name,
        description,
        is_system,
        is_active
      )
      values (
        '90000000-0000-4000-8000-000000000001'::uuid,
        'ADMIN',
        'Admin',
        'Satu-satunya role aplikasi fase 1.',
        true,
        true
      )
      on conflict (code) do update
      set
        name = excluded.name,
        description = excluded.description,
        is_system = excluded.is_system,
        is_active = excluded.is_active
    $sql$;
  end if;
end
$legacy_roles$;

-- ----------------------------------------------------------------------------
-- 4. Channels
-- ----------------------------------------------------------------------------

insert into catalog.channels (
  id,
  code,
  name,
  is_marketplace,
  is_active
)
values
  (
    '10000000-0000-4000-8000-000000000001'::uuid,
    'MANUAL',
    'Manual',
    false,
    true
  ),
  (
    '10000000-0000-4000-8000-000000000002'::uuid,
    'SHOPEE',
    'Shopee',
    true,
    true
  ),
  (
    '10000000-0000-4000-8000-000000000003'::uuid,
    'TIKTOK_SHOP',
    'TikTok Shop',
    true,
    true
  ),
  (
    '10000000-0000-4000-8000-000000000004'::uuid,
    'IMPORT',
    'Import',
    false,
    true
  ),
  (
    '10000000-0000-4000-8000-000000000005'::uuid,
    'SIMULATOR',
    'Marketplace Simulator',
    false,
    true
  ),
  (
    '10000000-0000-4000-8000-000000000006'::uuid,
    'SYSTEM',
    'System Process',
    false,
    true
  )
on conflict (code) do update
set
  name = excluded.name,
  is_marketplace = excluded.is_marketplace,
  is_active = excluded.is_active;

-- ----------------------------------------------------------------------------
-- 5. Movement reasons
-- ----------------------------------------------------------------------------

insert into catalog.movement_reasons (
  id,
  code,
  name,
  direction_code,
  requires_note,
  is_system,
  is_active
)
values
  (
    '20000000-0000-4000-8000-000000000001'::uuid,
    'INITIAL_BALANCE',
    'Saldo Awal',
    'ADJUSTMENT',
    true,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000002'::uuid,
    'MAKLON_RECEIPT',
    'Penerimaan dari Maklon',
    'INBOUND',
    false,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000003'::uuid,
    'MARKETPLACE_SALE',
    'Penjualan Marketplace',
    'OUTBOUND',
    false,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000004'::uuid,
    'OFFLINE_SALE',
    'Penjualan Offline',
    'OUTBOUND',
    false,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000005'::uuid,
    'BONUS',
    'Bonus',
    'OUTBOUND',
    true,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000006'::uuid,
    'PROMO',
    'Promo',
    'OUTBOUND',
    true,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000007'::uuid,
    'SAMPLE',
    'Sampel',
    'OUTBOUND',
    true,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000008'::uuid,
    'RETURN_RECEIVED',
    'Retur Diterima Fisik',
    'INBOUND',
    false,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000009'::uuid,
    'RETURN_SELLABLE',
    'Retur Layak Jual',
    'TRANSFER',
    false,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000010'::uuid,
    'RETURN_DAMAGED',
    'Retur Rusak',
    'TRANSFER',
    false,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000011'::uuid,
    'DAMAGED_FOUND',
    'Barang Rusak Ditemukan',
    'TRANSFER',
    true,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000012'::uuid,
    'EXPIRED_DISPOSAL',
    'Pemusnahan Barang Kedaluwarsa',
    'OUTBOUND',
    true,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000013'::uuid,
    'DAMAGED_DISPOSAL',
    'Pemusnahan Barang Rusak',
    'OUTBOUND',
    true,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000014'::uuid,
    'STOCKTAKE_GAIN',
    'Penambahan Hasil Stok Opname',
    'ADJUSTMENT',
    true,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000015'::uuid,
    'STOCKTAKE_LOSS',
    'Pengurangan Hasil Stok Opname',
    'ADJUSTMENT',
    true,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000018'::uuid,
    'STOCKTAKE_ADJUSTMENT',
    'Koreksi Hasil Stok Opname',
    'ADJUSTMENT',
    true,
    true,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000016'::uuid,
    'REVERSAL',
    'Pembalikan Transaksi',
    'ADJUSTMENT',
    true,
    true,
    true
  )
on conflict (code) do update
set
  name = excluded.name,
  direction_code = excluded.direction_code,
  requires_note = excluded.requires_note,
  is_system = excluded.is_system,
  is_active = excluded.is_active;

-- ----------------------------------------------------------------------------
-- 6. Organization settings
-- ----------------------------------------------------------------------------

with seed_settings (
  id,
  key,
  value,
  version,
  effective_from
) as (
  values
    (
      '60000000-0000-4000-8000-000000000001'::uuid,
      'expiry.warning_days',
      '[90, 60, 30, 0]'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000002'::uuid,
      'expiry.safety_buffer_days',
      '0'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000003'::uuid,
      'claim.tiktok.deadline_days',
      '40'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000004'::uuid,
      'claim.reminder_days',
      '[14, 7, 3, 1, 0]'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000005'::uuid,
      'stocktake.default_mode',
      '"FROZEN"'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000006'::uuid,
      'stocktake.default_visibility',
      '"BLIND"'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000007'::uuid,
      'return.inspection.sla_hours',
      '{"warning": 24, "high": 48, "critical": 72}'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000008'::uuid,
      'reconciliation.daily_hour',
      '2'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000009'::uuid,
      'demo.clock.fixed_at',
      '"2026-07-15T10:00:00+07:00"'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000010'::uuid,
      'simulator.demo',
      '{
        "enabled": true,
        "seedValue": 20260715,
        "maxEventsPerRun": 50,
        "presets": [
          "DEMO_SHOPEE_RESERVATION_TO_SHIPPED",
          "DEMO_TIKTOK_RESERVATION_TO_IN_TRANSIT",
          "DEMO_CANCEL_PRE_SHIPMENT",
          "DEMO_CANCEL_POST_SHIPMENT",
          "DEMO_BUNDLE_SHIPMENT",
          "DEMO_RETURN_MIXED_INSPECTION",
          "DEMO_RETURN_LOST_AND_CLAIM",
          "DEMO_DUPLICATE_EVENT",
          "DEMO_REJECT_RETURN_OVER_OUTBOUND",
          "DEMO_DAILY_RECONCILIATION"
        ]
      }'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000011'::uuid,
      'marketplace.listing_mappings.demo',
      '{
        "SHOPEE": {
          "SHP-SER-NIA-30": {"type": "PRODUCT", "sku": "SER-NIA-30"},
          "SHP-BND-GLOW-01": {"type": "BUNDLE", "listingSku": "BND-GLOW-01"}
        },
        "TIKTOK_SHOP": {
          "TTS-SER-NIA-30": {"type": "PRODUCT", "sku": "SER-NIA-30"},
          "TTS-BND-GLOW-01": {"type": "BUNDLE", "listingSku": "BND-GLOW-01"}
        }
      }'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    )
)
update app.settings as target
set
  value = seed_settings.value,
  version = seed_settings.version,
  effective_from = seed_settings.effective_from
from seed_settings
where
  target.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and target.key = seed_settings.key
  and target.effective_to is null;

with seed_settings (
  id,
  key,
  value,
  version,
  effective_from
) as (
  values
    (
      '60000000-0000-4000-8000-000000000001'::uuid,
      'expiry.warning_days',
      '[90, 60, 30, 0]'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000002'::uuid,
      'expiry.safety_buffer_days',
      '0'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000003'::uuid,
      'claim.tiktok.deadline_days',
      '40'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000004'::uuid,
      'claim.reminder_days',
      '[14, 7, 3, 1, 0]'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000005'::uuid,
      'stocktake.default_mode',
      '"FROZEN"'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000006'::uuid,
      'stocktake.default_visibility',
      '"BLIND"'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000007'::uuid,
      'return.inspection.sla_hours',
      '{"warning": 24, "high": 48, "critical": 72}'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000008'::uuid,
      'reconciliation.daily_hour',
      '2'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000009'::uuid,
      'demo.clock.fixed_at',
      '"2026-07-15T10:00:00+07:00"'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000010'::uuid,
      'simulator.demo',
      '{
        "enabled": true,
        "seedValue": 20260715,
        "maxEventsPerRun": 50,
        "presets": [
          "DEMO_SHOPEE_RESERVATION_TO_SHIPPED",
          "DEMO_TIKTOK_RESERVATION_TO_IN_TRANSIT",
          "DEMO_CANCEL_PRE_SHIPMENT",
          "DEMO_CANCEL_POST_SHIPMENT",
          "DEMO_BUNDLE_SHIPMENT",
          "DEMO_RETURN_MIXED_INSPECTION",
          "DEMO_RETURN_LOST_AND_CLAIM",
          "DEMO_DUPLICATE_EVENT",
          "DEMO_REJECT_RETURN_OVER_OUTBOUND",
          "DEMO_DAILY_RECONCILIATION"
        ]
      }'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    ),
    (
      '60000000-0000-4000-8000-000000000011'::uuid,
      'marketplace.listing_mappings.demo',
      '{
        "SHOPEE": {
          "SHP-SER-NIA-30": {"type": "PRODUCT", "sku": "SER-NIA-30"},
          "SHP-BND-GLOW-01": {"type": "BUNDLE", "listingSku": "BND-GLOW-01"}
        },
        "TIKTOK_SHOP": {
          "TTS-SER-NIA-30": {"type": "PRODUCT", "sku": "SER-NIA-30"},
          "TTS-BND-GLOW-01": {"type": "BUNDLE", "listingSku": "BND-GLOW-01"}
        }
      }'::jsonb,
      1,
      '2026-07-15 00:00:00+07'::timestamptz
    )
)
insert into app.settings (
  id,
  organization_id,
  key,
  value,
  version,
  effective_from,
  effective_to,
  created_by,
  created_at
)
select
  seed_settings.id,
  '00000000-0000-4000-8000-000000000001'::uuid,
  seed_settings.key,
  seed_settings.value,
  seed_settings.version,
  seed_settings.effective_from,
  null,
  null,
  '2026-07-15 07:00:00+07'::timestamptz
from seed_settings
where not exists (
  select 1
  from app.settings existing
  where
    existing.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
    and existing.key = seed_settings.key
    and existing.effective_to is null
);

-- ----------------------------------------------------------------------------
-- 7. Products
-- ----------------------------------------------------------------------------

insert into catalog.products (
  id,
  organization_id,
  sku,
  name,
  unit_code,
  barcode,
  description,
  is_batch_tracked,
  is_expiry_tracked,
  is_active,
  created_at,
  created_by,
  updated_at,
  updated_by,
  row_version
)
values
  (
    '30000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,
    'SER-NIA-30',
    'Serum Niacinamide 30 ml',
    'UNIT',
    '8990000000011',
    'Produk demo untuk FEFO, retur, klaim, dan stok opname.',
    true,
    true,
    true,
    '2026-07-15 07:00:00+07'::timestamptz,
    null,
    '2026-07-15 07:00:00+07'::timestamptz,
    null,
    1
  ),
  (
    '30000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,
    'CLN-GEN-100',
    'Gentle Cleanser 100 ml',
    'UNIT',
    '8990000000028',
    'Komponen bundle demo.',
    true,
    true,
    true,
    '2026-07-15 07:00:00+07'::timestamptz,
    null,
    '2026-07-15 07:00:00+07'::timestamptz,
    null,
    1
  ),
  (
    '30000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,
    'TNR-HYD-100',
    'Hydrating Toner 100 ml',
    'UNIT',
    '8990000000035',
    'Produk pembanding demo.',
    true,
    true,
    true,
    '2026-07-15 07:00:00+07'::timestamptz,
    null,
    '2026-07-15 07:00:00+07'::timestamptz,
    null,
    1
  )
on conflict (organization_id, sku) do update
set
  name = excluded.name,
  unit_code = excluded.unit_code,
  barcode = excluded.barcode,
  description = excluded.description,
  is_batch_tracked = excluded.is_batch_tracked,
  is_expiry_tracked = excluded.is_expiry_tracked,
  is_active = excluded.is_active,
  updated_at = excluded.updated_at,
  updated_by = excluded.updated_by,
  row_version = catalog.products.row_version + 1;

-- ----------------------------------------------------------------------------
-- 8. Product batches
-- ----------------------------------------------------------------------------

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
  created_by,
  updated_at,
  updated_by,
  row_version
)
select
  '40000000-0000-4000-8000-000000000001'::uuid,
  p.organization_id,
  p.id,
  'SER-2608-A',
  '2026-02-01'::date,
  '2026-08-01'::date,
  '2026-06-01 09:00:00+07'::timestamptz,
  'ACTIVE',
  null,
  '2026-06-01 09:00:00+07'::timestamptz,
  null,
  '2026-07-15 07:00:00+07'::timestamptz,
  null,
  1
from catalog.products p
where
  p.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and p.sku = 'SER-NIA-30'
on conflict (organization_id, product_id, batch_code) do update
set
  manufactured_date = excluded.manufactured_date,
  expiry_date = excluded.expiry_date,
  received_first_at = excluded.received_first_at,
  status_code = excluded.status_code,
  block_reason = excluded.block_reason,
  updated_at = excluded.updated_at,
  row_version = catalog.product_batches.row_version + 1;

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
  created_by,
  updated_at,
  updated_by,
  row_version
)
select
  '40000000-0000-4000-8000-000000000002'::uuid,
  p.organization_id,
  p.id,
  'SER-2612-B',
  '2026-05-01'::date,
  '2026-12-31'::date,
  '2026-06-15 09:00:00+07'::timestamptz,
  'ACTIVE',
  null,
  '2026-06-15 09:00:00+07'::timestamptz,
  null,
  '2026-07-15 07:00:00+07'::timestamptz,
  null,
  1
from catalog.products p
where
  p.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and p.sku = 'SER-NIA-30'
on conflict (organization_id, product_id, batch_code) do update
set
  manufactured_date = excluded.manufactured_date,
  expiry_date = excluded.expiry_date,
  received_first_at = excluded.received_first_at,
  status_code = excluded.status_code,
  block_reason = excluded.block_reason,
  updated_at = excluded.updated_at,
  row_version = catalog.product_batches.row_version + 1;

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
  created_by,
  updated_at,
  updated_by,
  row_version
)
select
  '40000000-0000-4000-8000-000000000003'::uuid,
  p.organization_id,
  p.id,
  'CLN-2611-A',
  '2026-04-01'::date,
  '2026-11-30'::date,
  '2026-06-10 09:00:00+07'::timestamptz,
  'ACTIVE',
  null,
  '2026-06-10 09:00:00+07'::timestamptz,
  null,
  '2026-07-15 07:00:00+07'::timestamptz,
  null,
  1
from catalog.products p
where
  p.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and p.sku = 'CLN-GEN-100'
on conflict (organization_id, product_id, batch_code) do update
set
  manufactured_date = excluded.manufactured_date,
  expiry_date = excluded.expiry_date,
  received_first_at = excluded.received_first_at,
  status_code = excluded.status_code,
  block_reason = excluded.block_reason,
  updated_at = excluded.updated_at,
  row_version = catalog.product_batches.row_version + 1;

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
  created_by,
  updated_at,
  updated_by,
  row_version
)
select
  '40000000-0000-4000-8000-000000000004'::uuid,
  p.organization_id,
  p.id,
  'TNR-2610-A',
  '2026-03-01'::date,
  '2026-10-31'::date,
  '2026-06-05 09:00:00+07'::timestamptz,
  'ACTIVE',
  null,
  '2026-06-05 09:00:00+07'::timestamptz,
  null,
  '2026-07-15 07:00:00+07'::timestamptz,
  null,
  1
from catalog.products p
where
  p.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and p.sku = 'TNR-HYD-100'
on conflict (organization_id, product_id, batch_code) do update
set
  manufactured_date = excluded.manufactured_date,
  expiry_date = excluded.expiry_date,
  received_first_at = excluded.received_first_at,
  status_code = excluded.status_code,
  block_reason = excluded.block_reason,
  updated_at = excluded.updated_at,
  row_version = catalog.product_batches.row_version + 1;

-- ----------------------------------------------------------------------------
-- 9. Bundle recipes
-- ----------------------------------------------------------------------------
--
-- BND-GLOW-01:
--   2 x SER-NIA-30
--   1 x CLN-GEN-100
--
-- There is deliberately no stock row for BND-GLOW-01.

update catalog.bundle_recipes as recipe
set
  external_listing_name = 'Glow Starter Bundle',
  version = 1,
  effective_from = '2026-07-15 00:00:00+07'::timestamptz,
  is_active = true
from catalog.channels channel
where
  recipe.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and recipe.channel_id = channel.id
  and channel.code = 'SHOPEE'
  and recipe.external_listing_sku = 'SHP-BND-GLOW-01'
  and recipe.effective_to is null;

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
  created_by,
  created_at
)
select
  '50000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  channel.id,
  'SHP-BND-GLOW-01',
  'Glow Starter Bundle',
  1,
  '2026-07-15 00:00:00+07'::timestamptz,
  null,
  true,
  null,
  '2026-07-15 07:00:00+07'::timestamptz
from catalog.channels channel
where
  channel.code = 'SHOPEE'
  and not exists (
    select 1
    from catalog.bundle_recipes existing
    where
      existing.organization_id =
        '00000000-0000-4000-8000-000000000001'::uuid
      and existing.channel_id = channel.id
      and existing.external_listing_sku = 'SHP-BND-GLOW-01'
      and existing.effective_to is null
      and existing.is_active
  );

update catalog.bundle_recipes as recipe
set
  external_listing_name = 'Glow Starter Bundle',
  version = 1,
  effective_from = '2026-07-15 00:00:00+07'::timestamptz,
  is_active = true
from catalog.channels channel
where
  recipe.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and recipe.channel_id = channel.id
  and channel.code = 'TIKTOK_SHOP'
  and recipe.external_listing_sku = 'TTS-BND-GLOW-01'
  and recipe.effective_to is null;

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
  created_by,
  created_at
)
select
  '50000000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  channel.id,
  'TTS-BND-GLOW-01',
  'Glow Starter Bundle',
  1,
  '2026-07-15 00:00:00+07'::timestamptz,
  null,
  true,
  null,
  '2026-07-15 07:00:00+07'::timestamptz
from catalog.channels channel
where
  channel.code = 'TIKTOK_SHOP'
  and not exists (
    select 1
    from catalog.bundle_recipes existing
    where
      existing.organization_id =
        '00000000-0000-4000-8000-000000000001'::uuid
      and existing.channel_id = channel.id
      and existing.external_listing_sku = 'TTS-BND-GLOW-01'
      and existing.effective_to is null
      and existing.is_active
  );

insert into catalog.bundle_components (
  id,
  bundle_recipe_id,
  product_id,
  component_qty,
  line_no
)
select
  '51000000-0000-4000-8000-000000000001'::uuid,
  recipe.id,
  product.id,
  2,
  1
from catalog.bundle_recipes recipe
join catalog.channels channel
  on channel.id = recipe.channel_id
join catalog.products product
  on product.organization_id = recipe.organization_id
 and product.sku = 'SER-NIA-30'
where
  recipe.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and channel.code = 'SHOPEE'
  and recipe.external_listing_sku = 'SHP-BND-GLOW-01'
  and recipe.effective_to is null
  and recipe.is_active
on conflict (bundle_recipe_id, product_id) do update
set
  component_qty = excluded.component_qty,
  line_no = excluded.line_no;

insert into catalog.bundle_components (
  id,
  bundle_recipe_id,
  product_id,
  component_qty,
  line_no
)
select
  '51000000-0000-4000-8000-000000000002'::uuid,
  recipe.id,
  product.id,
  1,
  2
from catalog.bundle_recipes recipe
join catalog.channels channel
  on channel.id = recipe.channel_id
join catalog.products product
  on product.organization_id = recipe.organization_id
 and product.sku = 'CLN-GEN-100'
where
  recipe.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and channel.code = 'SHOPEE'
  and recipe.external_listing_sku = 'SHP-BND-GLOW-01'
  and recipe.effective_to is null
  and recipe.is_active
on conflict (bundle_recipe_id, product_id) do update
set
  component_qty = excluded.component_qty,
  line_no = excluded.line_no;

insert into catalog.bundle_components (
  id,
  bundle_recipe_id,
  product_id,
  component_qty,
  line_no
)
select
  '51000000-0000-4000-8000-000000000003'::uuid,
  recipe.id,
  product.id,
  2,
  1
from catalog.bundle_recipes recipe
join catalog.channels channel
  on channel.id = recipe.channel_id
join catalog.products product
  on product.organization_id = recipe.organization_id
 and product.sku = 'SER-NIA-30'
where
  recipe.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and channel.code = 'TIKTOK_SHOP'
  and recipe.external_listing_sku = 'TTS-BND-GLOW-01'
  and recipe.effective_to is null
  and recipe.is_active
on conflict (bundle_recipe_id, product_id) do update
set
  component_qty = excluded.component_qty,
  line_no = excluded.line_no;

insert into catalog.bundle_components (
  id,
  bundle_recipe_id,
  product_id,
  component_qty,
  line_no
)
select
  '51000000-0000-4000-8000-000000000004'::uuid,
  recipe.id,
  product.id,
  1,
  2
from catalog.bundle_recipes recipe
join catalog.channels channel
  on channel.id = recipe.channel_id
join catalog.products product
  on product.organization_id = recipe.organization_id
 and product.sku = 'CLN-GEN-100'
where
  recipe.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and channel.code = 'TIKTOK_SHOP'
  and recipe.external_listing_sku = 'TTS-BND-GLOW-01'
  and recipe.effective_to is null
  and recipe.is_active
on conflict (bundle_recipe_id, product_id) do update
set
  component_qty = excluded.component_qty,
  line_no = excluded.line_no;

-- ----------------------------------------------------------------------------
-- 10. Notification rules
-- ----------------------------------------------------------------------------
--
-- No notification instances are seeded. Instances must be created by the rule
-- engine from actual source conditions.
--
-- This block supports both:
--   - the latest rule schema from 12-notification-rules.md; and
--   - the earlier compact schema from 05-database-schema.md.

do $notification_rules$
begin
  if to_regclass('notification.rules') is null then
    raise notice
      'notification.rules does not exist; notification rules were skipped';
    return;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where
      table_schema = 'notification'
      and table_name = 'rules'
      and column_name = 'version'
  ) then
    execute $sql$
      insert into notification.rules (
        id,
        organization_id,
        code,
        version,
        category_code,
        trigger_mode_code,
        entity_type_code,
        severity_strategy_code,
        stage_strategy_code,
        condition_strategy_code,
        resolution_strategy_code,
        template_version,
        action_code,
        config,
        is_active,
        effective_from,
        effective_to,
        created_by,
        created_at,
        updated_by,
        updated_at
      )
      values
        (
          '80000000-0000-4000-8000-000000000001'::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'EXPIRY_RISK',
          '1.0.0',
          'EXPIRY',
          'SCHEDULED',
          'PRODUCT_BATCH',
          'DYNAMIC',
          'EXPIRY_STAGE',
          'EXPIRY_BALANCE_AND_DATE',
          'EXPIRY_CONDITION_CLEARED',
          '1.0.0',
          'OPEN_BATCH_EXPIRY_DETAIL',
          '{
            "thresholdDays": [90, 60, 30, 0],
            "timezone": "Asia/Jakarta",
            "approachingBuckets": ["SELLABLE", "QUARANTINE"],
            "expiredBuckets": ["SELLABLE", "QUARANTINE", "DAMAGED"],
            "reminderCooldownHours": 24
          }'::jsonb,
          true,
          '2026-07-15 00:00:00+07'::timestamptz,
          null,
          null,
          '2026-07-15 07:00:00+07'::timestamptz,
          null,
          '2026-07-15 07:00:00+07'::timestamptz
        ),
        (
          '80000000-0000-4000-8000-000000000002'::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'RETURN_PENDING_INSPECTION',
          '1.0.0',
          'RETURN',
          'HYBRID',
          'RETURN',
          'DYNAMIC',
          'RETURN_INSPECTION_SLA',
          'RETURN_RECEIVED_UNINSPECTED',
          'RETURN_INSPECTION_COMPLETED',
          '1.0.0',
          'OPEN_RETURN_DETAIL',
          '{
            "warningAfterHours": 24,
            "highAfterHours": 48,
            "criticalAfterHours": 72,
            "reminderCooldownHours": 24
          }'::jsonb,
          true,
          '2026-07-15 00:00:00+07'::timestamptz,
          null,
          null,
          '2026-07-15 07:00:00+07'::timestamptz,
          null,
          '2026-07-15 07:00:00+07'::timestamptz
        ),
        (
          '80000000-0000-4000-8000-000000000003'::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'CLAIM_DEADLINE',
          '1.0.0',
          'CLAIM',
          'HYBRID',
          'CLAIM',
          'DYNAMIC',
          'CLAIM_DEADLINE_STAGE',
          'CLAIM_ELIGIBLE_AND_OPEN',
          'CLAIM_SUBMITTED_OR_RESOLVED',
          '1.0.0',
          'OPEN_CLAIM_DETAIL',
          '{
            "thresholdDays": [14, 7, 3, 1, 0],
            "timezone": "Asia/Jakarta",
            "reminderCooldownHours": 12
          }'::jsonb,
          true,
          '2026-07-15 00:00:00+07'::timestamptz,
          null,
          null,
          '2026-07-15 07:00:00+07'::timestamptz,
          null,
          '2026-07-15 07:00:00+07'::timestamptz
        ),
        (
          '80000000-0000-4000-8000-000000000004'::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'RECONCILIATION_ISSUE_HIGH',
          '1.0.0',
          'RECONCILIATION',
          'EVENT_DRIVEN',
          'RECONCILIATION_ISSUE',
          'SOURCE',
          'ISSUE_STATUS',
          'ISSUE_HIGH_OPEN',
          'ISSUE_RESOLVED_OR_DISMISSED',
          '1.0.0',
          'OPEN_RECONCILIATION_ISSUE',
          '{"sourceSeverity": "HIGH"}'::jsonb,
          true,
          '2026-07-15 00:00:00+07'::timestamptz,
          null,
          null,
          '2026-07-15 07:00:00+07'::timestamptz,
          null,
          '2026-07-15 07:00:00+07'::timestamptz
        ),
        (
          '80000000-0000-4000-8000-000000000005'::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'RECONCILIATION_ISSUE_CRITICAL',
          '1.0.0',
          'RECONCILIATION',
          'EVENT_DRIVEN',
          'RECONCILIATION_ISSUE',
          'SOURCE',
          'ISSUE_STATUS',
          'ISSUE_CRITICAL_OPEN',
          'ISSUE_RESOLVED_OR_DISMISSED',
          '1.0.0',
          'OPEN_RECONCILIATION_ISSUE',
          '{"sourceSeverity": "CRITICAL"}'::jsonb,
          true,
          '2026-07-15 00:00:00+07'::timestamptz,
          null,
          null,
          '2026-07-15 07:00:00+07'::timestamptz,
          null,
          '2026-07-15 07:00:00+07'::timestamptz
        )
      on conflict (organization_id, code, version) do update
      set
        category_code = excluded.category_code,
        trigger_mode_code = excluded.trigger_mode_code,
        entity_type_code = excluded.entity_type_code,
        severity_strategy_code = excluded.severity_strategy_code,
        stage_strategy_code = excluded.stage_strategy_code,
        condition_strategy_code = excluded.condition_strategy_code,
        resolution_strategy_code = excluded.resolution_strategy_code,
        template_version = excluded.template_version,
        action_code = excluded.action_code,
        config = excluded.config,
        is_active = excluded.is_active,
        effective_from = excluded.effective_from,
        effective_to = excluded.effective_to,
        updated_at = excluded.updated_at
    $sql$;
  else
    execute $sql$
      insert into notification.rules (
        id,
        organization_id,
        code,
        event_type_code,
        severity_code,
        config,
        is_active,
        created_at,
        updated_at
      )
      values
        (
          '80000000-0000-4000-8000-000000000001'::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'EXPIRY_RISK',
          'SCHEDULED',
          'WARNING',
          '{
            "thresholdDays": [90, 60, 30, 0],
            "timezone": "Asia/Jakarta"
          }'::jsonb,
          true,
          '2026-07-15 07:00:00+07'::timestamptz,
          '2026-07-15 07:00:00+07'::timestamptz
        ),
        (
          '80000000-0000-4000-8000-000000000002'::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'RETURN_PENDING_INSPECTION',
          'HYBRID',
          'WARNING',
          '{
            "warningAfterHours": 24,
            "highAfterHours": 48,
            "criticalAfterHours": 72
          }'::jsonb,
          true,
          '2026-07-15 07:00:00+07'::timestamptz,
          '2026-07-15 07:00:00+07'::timestamptz
        ),
        (
          '80000000-0000-4000-8000-000000000003'::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'CLAIM_DEADLINE',
          'HYBRID',
          'WARNING',
          '{"thresholdDays": [14, 7, 3, 1, 0]}'::jsonb,
          true,
          '2026-07-15 07:00:00+07'::timestamptz,
          '2026-07-15 07:00:00+07'::timestamptz
        ),
        (
          '80000000-0000-4000-8000-000000000004'::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'RECONCILIATION_ISSUE_HIGH',
          'EVENT_DRIVEN',
          'HIGH',
          '{"sourceSeverity": "HIGH"}'::jsonb,
          true,
          '2026-07-15 07:00:00+07'::timestamptz,
          '2026-07-15 07:00:00+07'::timestamptz
        ),
        (
          '80000000-0000-4000-8000-000000000005'::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'RECONCILIATION_ISSUE_CRITICAL',
          'EVENT_DRIVEN',
          'CRITICAL',
          '{"sourceSeverity": "CRITICAL"}'::jsonb,
          true,
          '2026-07-15 07:00:00+07'::timestamptz,
          '2026-07-15 07:00:00+07'::timestamptz
        )
      on conflict (id) do update
      set
        code = excluded.code,
        event_type_code = excluded.event_type_code,
        severity_code = excluded.severity_code,
        config = excluded.config,
        is_active = excluded.is_active,
        updated_at = excluded.updated_at
    $sql$;
  end if;
end
$notification_rules$;

-- ----------------------------------------------------------------------------
-- 11. Initial stock through ledger
-- ----------------------------------------------------------------------------
--
-- Initial demo balance:
--   SER-2608-A  SELLABLE  +5
--   SER-2612-B  SELLABLE +20
--   CLN-2611-A  SELLABLE +15
--   TNR-2610-A  SELLABLE +12
--
-- The transaction is deterministic and idempotent. No stock is written to the
-- product or batch master.

do $initial_balance$
declare
  v_org_id uuid :=
    '00000000-0000-4000-8000-000000000001'::uuid;
  v_command_id uuid;
  v_transaction_id uuid;
  v_reason_id uuid;
  v_channel_id uuid;
begin
  select id
  into strict v_reason_id
  from catalog.movement_reasons
  where code = 'INITIAL_BALANCE';

  select id
  into strict v_channel_id
  from catalog.channels
  where code = 'SYSTEM';

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
    '71000000-0000-4000-8000-000000000001'::uuid,
    v_org_id,
    'SEED_INITIAL_BALANCE',
    'GLOWLAB_DEMO_V1',
    '066cffb1c2b36e4a6283a67f7d1c71a189fbf7cacdded8990775df88e40fd420',
    'STARTED',
    '2026-07-15 08:00:00+07'::timestamptz,
    null,
    null,
    '{}'::jsonb,
    null,
    null
  )
  on conflict (organization_id, scope, key) do nothing;

  select id
  into strict v_command_id
  from inventory.idempotency_commands
  where
    organization_id = v_org_id
    and scope = 'SEED_INITIAL_BALANCE'
    and key = 'GLOWLAB_DEMO_V1';

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
  values (
    '70000000-0000-4000-8000-000000000001'::uuid,
    v_org_id,
    'SEED-IB-000001',
    'INITIAL_BALANCE',
    v_reason_id,
    'INITIAL_BALANCE',
    v_channel_id,
    'SYSTEM',
    'SEED',
    null,
    'SEED-INITIAL-BALANCE-V1',
    '2026-07-15 08:00:00+07'::timestamptz,
    '2026-07-15 08:00:00+07'::timestamptz,
    '2026-07-15'::date,
    null,
    'seed.sql',
    'SYSTEM_PROCESS',
    '73000000-0000-4000-8000-000000000001'::uuid,
    v_command_id,
    null,
    'Saldo awal sintetis untuk local, test, staging, dan demo.',
    '{
      "seedVersion": "1.0.0",
      "isDemoData": true,
      "sourceDocument": "15-demo-script.md"
    }'::jsonb,
    1
  )
  on conflict (organization_id, transaction_no) do nothing;

  select id
  into strict v_transaction_id
  from inventory.stock_transactions
  where
    organization_id = v_org_id
    and transaction_no = 'SEED-IB-000001';

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
    '72000000-0000-4000-8000-000000000001'::uuid,
    v_org_id,
    v_transaction_id,
    1,
    product.id,
    batch.id,
    product.sku,
    batch.batch_code,
    batch.expiry_date,
    'SELLABLE',
    5,
    'ADJUSTMENT',
    null,
    'INITIAL-1',
    '2026-07-15 08:00:00+07'::timestamptz,
    '2026-07-15 08:00:00+07'::timestamptz,
    '2026-07-15 08:00:00+07'::timestamptz
  from catalog.products product
  join catalog.product_batches batch
    on batch.organization_id = product.organization_id
   and batch.product_id = product.id
   and batch.batch_code = 'SER-2608-A'
  where
    product.organization_id = v_org_id
    and product.sku = 'SER-NIA-30'
  on conflict (transaction_id, line_no) do nothing;

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
    '72000000-0000-4000-8000-000000000002'::uuid,
    v_org_id,
    v_transaction_id,
    2,
    product.id,
    batch.id,
    product.sku,
    batch.batch_code,
    batch.expiry_date,
    'SELLABLE',
    20,
    'ADJUSTMENT',
    null,
    'INITIAL-2',
    '2026-07-15 08:00:00+07'::timestamptz,
    '2026-07-15 08:00:00+07'::timestamptz,
    '2026-07-15 08:00:00+07'::timestamptz
  from catalog.products product
  join catalog.product_batches batch
    on batch.organization_id = product.organization_id
   and batch.product_id = product.id
   and batch.batch_code = 'SER-2612-B'
  where
    product.organization_id = v_org_id
    and product.sku = 'SER-NIA-30'
  on conflict (transaction_id, line_no) do nothing;

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
    '72000000-0000-4000-8000-000000000003'::uuid,
    v_org_id,
    v_transaction_id,
    3,
    product.id,
    batch.id,
    product.sku,
    batch.batch_code,
    batch.expiry_date,
    'SELLABLE',
    15,
    'ADJUSTMENT',
    null,
    'INITIAL-3',
    '2026-07-15 08:00:00+07'::timestamptz,
    '2026-07-15 08:00:00+07'::timestamptz,
    '2026-07-15 08:00:00+07'::timestamptz
  from catalog.products product
  join catalog.product_batches batch
    on batch.organization_id = product.organization_id
   and batch.product_id = product.id
   and batch.batch_code = 'CLN-2611-A'
  where
    product.organization_id = v_org_id
    and product.sku = 'CLN-GEN-100'
  on conflict (transaction_id, line_no) do nothing;

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
    '72000000-0000-4000-8000-000000000004'::uuid,
    v_org_id,
    v_transaction_id,
    4,
    product.id,
    batch.id,
    product.sku,
    batch.batch_code,
    batch.expiry_date,
    'SELLABLE',
    12,
    'ADJUSTMENT',
    null,
    'INITIAL-4',
    '2026-07-15 08:00:00+07'::timestamptz,
    '2026-07-15 08:00:00+07'::timestamptz,
    '2026-07-15 08:00:00+07'::timestamptz
  from catalog.products product
  join catalog.product_batches batch
    on batch.organization_id = product.organization_id
   and batch.product_id = product.id
   and batch.batch_code = 'TNR-2610-A'
  where
    product.organization_id = v_org_id
    and product.sku = 'TNR-HYD-100'
  on conflict (transaction_id, line_no) do nothing;

  update inventory.idempotency_commands
  set
    status_code = 'SUCCEEDED',
    completed_at = '2026-07-15 08:00:00+07'::timestamptz,
    result_transaction_id = v_transaction_id,
    response_snapshot = jsonb_build_object(
      'transactionId',
      v_transaction_id,
      'transactionNo',
      'SEED-IB-000001',
      'source',
      'seed.sql'
    ),
    error_code = null
  where id = v_command_id;
end
$initial_balance$;

-- ----------------------------------------------------------------------------
-- 12. Rebuild projections from ledger
-- ----------------------------------------------------------------------------
--
-- This keeps the seed idempotent. If the seed is accidentally re-run on a
-- non-empty demo database, the baseline ledger is not duplicated and the
-- projection is rebuilt from all existing ledger entries.

with ledger_by_batch as (
  select
    entry.organization_id,
    entry.batch_id,
    entry.product_id,
    coalesce(
      sum(entry.quantity_delta)
        filter (where entry.bucket_code = 'SELLABLE'),
      0
    )::bigint as sellable_qty,
    coalesce(
      sum(entry.quantity_delta)
        filter (where entry.bucket_code = 'QUARANTINE'),
      0
    )::bigint as quarantine_qty,
    coalesce(
      sum(entry.quantity_delta)
        filter (where entry.bucket_code = 'DAMAGED'),
      0
    )::bigint as damaged_qty,
    max(entry.ledger_seq)::bigint as last_ledger_seq
  from inventory.stock_ledger_entries entry
  where
    entry.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  group by
    entry.organization_id,
    entry.batch_id,
    entry.product_id
)
insert into inventory.stock_batch_balances (
  organization_id,
  batch_id,
  product_id,
  sellable_qty,
  quarantine_qty,
  damaged_qty,
  last_ledger_seq,
  updated_at,
  version
)
select
  organization_id,
  batch_id,
  product_id,
  sellable_qty,
  quarantine_qty,
  damaged_qty,
  last_ledger_seq,
  clock_timestamp(),
  1
from ledger_by_batch
on conflict (organization_id, batch_id) do update
set
  product_id = excluded.product_id,
  sellable_qty = excluded.sellable_qty,
  quarantine_qty = excluded.quarantine_qty,
  damaged_qty = excluded.damaged_qty,
  last_ledger_seq = excluded.last_ledger_seq,
  updated_at = excluded.updated_at,
  version = inventory.stock_batch_balances.version + 1;

with ledger_by_product as (
  select
    entry.organization_id,
    entry.product_id,
    coalesce(
      sum(entry.quantity_delta)
        filter (where entry.bucket_code = 'SELLABLE'),
      0
    )::bigint as sellable_qty,
    coalesce(
      sum(entry.quantity_delta)
        filter (where entry.bucket_code = 'QUARANTINE'),
      0
    )::bigint as quarantine_qty,
    coalesce(
      sum(entry.quantity_delta)
        filter (where entry.bucket_code = 'DAMAGED'),
      0
    )::bigint as damaged_qty,
    max(entry.ledger_seq)::bigint as last_ledger_seq
  from inventory.stock_ledger_entries entry
  where
    entry.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  group by
    entry.organization_id,
    entry.product_id
),
active_reservations as (
  select
    reservation.organization_id,
    reservation.product_id,
    coalesce(
      sum(
        reservation.reserved_qty
        - reservation.consumed_qty
        - reservation.released_qty
      ),
      0
    )::bigint as reserved_qty
  from inventory.stock_reservations reservation
  where
    reservation.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
    and reservation.status_code in ('ACTIVE', 'PARTIALLY_CONSUMED')
  group by
    reservation.organization_id,
    reservation.product_id
)
insert into inventory.stock_product_positions (
  organization_id,
  product_id,
  sellable_qty,
  quarantine_qty,
  damaged_qty,
  reserved_qty,
  last_ledger_seq,
  updated_at,
  version
)
select
  ledger.organization_id,
  ledger.product_id,
  ledger.sellable_qty,
  ledger.quarantine_qty,
  ledger.damaged_qty,
  coalesce(reservation.reserved_qty, 0),
  ledger.last_ledger_seq,
  clock_timestamp(),
  1
from ledger_by_product ledger
left join active_reservations reservation
  on reservation.organization_id = ledger.organization_id
 and reservation.product_id = ledger.product_id
on conflict (organization_id, product_id) do update
set
  sellable_qty = excluded.sellable_qty,
  quarantine_qty = excluded.quarantine_qty,
  damaged_qty = excluded.damaged_qty,
  reserved_qty = excluded.reserved_qty,
  last_ledger_seq = excluded.last_ledger_seq,
  updated_at = excluded.updated_at,
  version = inventory.stock_product_positions.version + 1;

-- ----------------------------------------------------------------------------
-- 13. Private Storage buckets
-- ----------------------------------------------------------------------------

do $storage_seed$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage.buckets does not exist; bucket seed was skipped';
    return;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where
      table_schema = 'storage'
      and table_name = 'buckets'
      and column_name = 'allowed_mime_types'
  ) then
    execute $sql$
      insert into storage.buckets (
        id,
        name,
        public,
        file_size_limit,
        allowed_mime_types
      )
      values
        (
          'evidence',
          'evidence',
          false,
          10485760,
          array[
            'image/jpeg',
            'image/png',
            'application/pdf'
          ]::text[]
        ),
        (
          'imports',
          'imports',
          false,
          20971520,
          array[
            'text/csv',
            'application/vnd.ms-excel'
          ]::text[]
        ),
        (
          'exports',
          'exports',
          false,
          20971520,
          array[
            'text/csv',
            'application/pdf'
          ]::text[]
        )
      on conflict (id) do update
      set
        name = excluded.name,
        public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types
    $sql$;
  else
    execute $sql$
      insert into storage.buckets (
        id,
        name,
        public,
        file_size_limit
      )
      values
        ('evidence', 'evidence', false, 10485760),
        ('imports', 'imports', false, 20971520),
        ('exports', 'exports', false, 20971520)
      on conflict (id) do update
      set
        name = excluded.name,
        public = excluded.public,
        file_size_limit = excluded.file_size_limit
    $sql$;
  end if;
end
$storage_seed$;

-- ----------------------------------------------------------------------------
-- 14. Attach application profile when Auth user already exists
-- ----------------------------------------------------------------------------
--
-- Create the Auth user through a trusted server using:
--   supabase.auth.admin.createUser(...)
-- or:
--   supabase.auth.admin.inviteUserByEmail(...)
--
-- Suggested demo email:
--   demo.admin@glowlab.invalid
--
-- This seed intentionally avoids direct inserts into Supabase-managed Auth
-- internals, whose implementation is not the application schema contract.

do $demo_profile$
declare
  v_user_id uuid;
begin
  select id
  into v_user_id
  from auth.users
  where email = 'demo.admin@glowlab.invalid'
  order by created_at
  limit 1;

  if v_user_id is null then
    raise notice
      'Demo Auth user is absent. Create demo.admin@glowlab.invalid via the trusted Auth Admin API.';
    return;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where
      table_schema = 'app'
      and table_name = 'user_profiles'
      and column_name = 'role_code'
  ) then
    execute format(
      $sql$
        insert into app.user_profiles (
          user_id,
          organization_id,
          display_name,
          employee_code,
          role_code,
          is_active,
          created_at,
          updated_at
        )
        values (
          %L::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'Demo Admin',
          'DEMO-ADMIN',
          'ADMIN',
          true,
          '2026-07-15 07:00:00+07'::timestamptz,
          '2026-07-15 07:00:00+07'::timestamptz
        )
        on conflict (user_id) do update
        set
          organization_id = excluded.organization_id,
          display_name = excluded.display_name,
          employee_code = excluded.employee_code,
          role_code = 'ADMIN',
          is_active = true,
          updated_at = excluded.updated_at
      $sql$,
      v_user_id
    );
  else
    execute format(
      $sql$
        insert into app.user_profiles (
          user_id,
          organization_id,
          display_name,
          employee_code,
          is_active,
          created_at,
          updated_at
        )
        values (
          %L::uuid,
          '00000000-0000-4000-8000-000000000001'::uuid,
          'Demo Admin',
          'DEMO-ADMIN',
          true,
          '2026-07-15 07:00:00+07'::timestamptz,
          '2026-07-15 07:00:00+07'::timestamptz
        )
        on conflict (user_id) do update
        set
          organization_id = excluded.organization_id,
          display_name = excluded.display_name,
          employee_code = excluded.employee_code,
          is_active = true,
          updated_at = excluded.updated_at
      $sql$,
      v_user_id
    );

    if
      to_regclass('app.roles') is not null
      and to_regclass('app.user_role_assignments') is not null
    then
      execute format(
        $sql$
          insert into app.user_role_assignments (
            id,
            user_id,
            role_id,
            assigned_at,
            assigned_by,
            revoked_at
          )
          values (
            '90000000-0000-4000-8000-000000000002'::uuid,
            %L::uuid,
            '90000000-0000-4000-8000-000000000001'::uuid,
            '2026-07-15 07:00:00+07'::timestamptz,
            %L::uuid,
            null
          )
          on conflict do nothing
        $sql$,
        v_user_id,
        v_user_id
      );
    end if;
  end if;
end
$demo_profile$;

-- ----------------------------------------------------------------------------
-- 15. Verification
-- ----------------------------------------------------------------------------

do $verify_seed$
declare
  v_org_id uuid :=
    '00000000-0000-4000-8000-000000000001'::uuid;
  v_reason_count integer;
  v_channel_count integer;
  v_product_count integer;
  v_batch_count integer;
  v_serum_sellable bigint;
  v_cleanser_sellable bigint;
  v_toner_sellable bigint;
  v_projection_mismatch_count integer;
  v_negative_count integer;
  v_bundle_product_count integer;
  v_recipe_count integer;
begin
  select count(*)
  into v_reason_count
  from catalog.movement_reasons
  where code in (
    'INITIAL_BALANCE',
    'MAKLON_RECEIPT',
    'MARKETPLACE_SALE',
    'OFFLINE_SALE',
    'BONUS',
    'PROMO',
    'SAMPLE',
    'RETURN_RECEIVED',
    'RETURN_SELLABLE',
    'RETURN_DAMAGED',
    'DAMAGED_FOUND',
    'EXPIRED_DISPOSAL',
    'DAMAGED_DISPOSAL',
    'STOCKTAKE_GAIN',
    'STOCKTAKE_LOSS',
    'STOCKTAKE_ADJUSTMENT',
    'REVERSAL'
  );

  if v_reason_count <> 17 then
    raise exception
      'SEED_VERIFY_REASON_COUNT: expected 17, got %',
      v_reason_count;
  end if;

  select count(*)
  into v_channel_count
  from catalog.channels
  where code in (
    'MANUAL',
    'SHOPEE',
    'TIKTOK_SHOP',
    'IMPORT',
    'SIMULATOR',
    'SYSTEM'
  );

  if v_channel_count <> 6 then
    raise exception
      'SEED_VERIFY_CHANNEL_COUNT: expected 6, got %',
      v_channel_count;
  end if;

  select count(*)
  into v_product_count
  from catalog.products
  where
    organization_id = v_org_id
    and sku in ('SER-NIA-30', 'CLN-GEN-100', 'TNR-HYD-100');

  if v_product_count <> 3 then
    raise exception
      'SEED_VERIFY_PRODUCT_COUNT: expected 3, got %',
      v_product_count;
  end if;

  select count(*)
  into v_batch_count
  from catalog.product_batches
  where
    organization_id = v_org_id
    and batch_code in (
      'SER-2608-A',
      'SER-2612-B',
      'CLN-2611-A',
      'TNR-2610-A'
    );

  if v_batch_count <> 4 then
    raise exception
      'SEED_VERIFY_BATCH_COUNT: expected 4, got %',
      v_batch_count;
  end if;

  select count(*)
  into v_bundle_product_count
  from catalog.products
  where
    organization_id = v_org_id
    and sku in (
      'BND-GLOW-01',
      'SHP-BND-GLOW-01',
      'TTS-BND-GLOW-01'
    );

  if v_bundle_product_count <> 0 then
    raise exception
      'SEED_VERIFY_BUNDLE_STOCK_ENTITY: bundle must not be a stock product';
  end if;

  select count(*)
  into v_recipe_count
  from catalog.bundle_recipes recipe
  join catalog.channels channel
    on channel.id = recipe.channel_id
  where
    recipe.organization_id = v_org_id
    and recipe.effective_to is null
    and recipe.is_active
    and (
      (
        channel.code = 'SHOPEE'
        and recipe.external_listing_sku = 'SHP-BND-GLOW-01'
      )
      or
      (
        channel.code = 'TIKTOK_SHOP'
        and recipe.external_listing_sku = 'TTS-BND-GLOW-01'
      )
    );

  if v_recipe_count <> 2 then
    raise exception
      'SEED_VERIFY_BUNDLE_RECIPES: expected 2, got %',
      v_recipe_count;
  end if;

  select position.sellable_qty
  into strict v_serum_sellable
  from inventory.stock_product_positions position
  join catalog.products product
    on product.organization_id = position.organization_id
   and product.id = position.product_id
  where
    position.organization_id = v_org_id
    and product.sku = 'SER-NIA-30';

  select position.sellable_qty
  into strict v_cleanser_sellable
  from inventory.stock_product_positions position
  join catalog.products product
    on product.organization_id = position.organization_id
   and product.id = position.product_id
  where
    position.organization_id = v_org_id
    and product.sku = 'CLN-GEN-100';

  select position.sellable_qty
  into strict v_toner_sellable
  from inventory.stock_product_positions position
  join catalog.products product
    on product.organization_id = position.organization_id
   and product.id = position.product_id
  where
    position.organization_id = v_org_id
    and product.sku = 'TNR-HYD-100';

  if v_serum_sellable <> 25 then
    raise exception
      'SEED_VERIFY_SERUM_BALANCE: expected 25, got %',
      v_serum_sellable;
  end if;

  if v_cleanser_sellable <> 15 then
    raise exception
      'SEED_VERIFY_CLEANSER_BALANCE: expected 15, got %',
      v_cleanser_sellable;
  end if;

  if v_toner_sellable <> 12 then
    raise exception
      'SEED_VERIFY_TONER_BALANCE: expected 12, got %',
      v_toner_sellable;
  end if;

  with ledger_balance as (
    select
      entry.organization_id,
      entry.batch_id,
      coalesce(
        sum(entry.quantity_delta)
          filter (where entry.bucket_code = 'SELLABLE'),
        0
      )::bigint as sellable_qty,
      coalesce(
        sum(entry.quantity_delta)
          filter (where entry.bucket_code = 'QUARANTINE'),
        0
      )::bigint as quarantine_qty,
      coalesce(
        sum(entry.quantity_delta)
          filter (where entry.bucket_code = 'DAMAGED'),
        0
      )::bigint as damaged_qty
    from inventory.stock_ledger_entries entry
    where entry.organization_id = v_org_id
    group by
      entry.organization_id,
      entry.batch_id
  )
  select count(*)
  into v_projection_mismatch_count
  from ledger_balance ledger
  join inventory.stock_batch_balances projection
    on projection.organization_id = ledger.organization_id
   and projection.batch_id = ledger.batch_id
  where
    projection.sellable_qty <> ledger.sellable_qty
    or projection.quarantine_qty <> ledger.quarantine_qty
    or projection.damaged_qty <> ledger.damaged_qty;

  if v_projection_mismatch_count <> 0 then
    raise exception
      'SEED_VERIFY_LEDGER_PROJECTION_MISMATCH: % batch rows',
      v_projection_mismatch_count;
  end if;

  select count(*)
  into v_negative_count
  from inventory.stock_batch_balances
  where
    organization_id = v_org_id
    and (
      sellable_qty < 0
      or quarantine_qty < 0
      or damaged_qty < 0
    );

  if v_negative_count <> 0 then
    raise exception
      'SEED_VERIFY_NEGATIVE_BALANCE: % rows',
      v_negative_count;
  end if;

  raise notice
    'Seed verified: Serum=%, Cleanser=%, Toner=%',
    v_serum_sellable,
    v_cleanser_sellable,
    v_toner_sellable;
end
$verify_seed$;

commit;

-- ============================================================================
-- Expected post-seed state
-- ============================================================================
--
-- Organization:
--   GLOWLAB_DEMO
--
-- Physical products:
--   SER-NIA-30
--   CLN-GEN-100
--   TNR-HYD-100
--
-- Initial sellable:
--   Serum   = 25
--   Cleanser = 15
--   Toner   = 12
--
-- Bundle:
--   Shopee  SHP-BND-GLOW-01 -> 2 Serum + 1 Cleanser
--   TikTok  TTS-BND-GLOW-01 -> 2 Serum + 1 Cleanser
--   No bundle stock row
--
-- Run:
--   supabase db reset
--   supabase test db
--
-- Auth bootstrap:
--   Create demo.admin@glowlab.invalid through the trusted Auth Admin API.
--   Do not place a service-role key in browser code merely because login setup
--   feels inconvenient. The database will survive; the security model might not.
-- ============================================================================
