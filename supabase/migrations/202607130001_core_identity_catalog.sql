begin;

create extension if not exists pgcrypto with schema extensions;

create schema if not exists app;
create schema if not exists catalog;
create schema if not exists inventory;
create schema if not exists notification;
create schema if not exists api;

revoke all on schema app, catalog, inventory, notification, api from public;

create or replace function app.touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create or replace function app.touch_mutable_row()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  new.row_version := old.row_version + 1;
  return new;
end;
$$;

create table app.organizations (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  timezone text not null default 'Asia/Jakarta',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid null references auth.users(id) on delete set null,
  constraint uq_organizations_code unique (code),
  constraint ck_organizations_code_nonblank check (btrim(code) <> ''),
  constraint ck_organizations_name_nonblank check (btrim(name) <> ''),
  constraint ck_organizations_timezone_nonblank check (btrim(timezone) <> '')
);

create table app.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references app.organizations(id) on delete restrict,
  display_name text not null,
  employee_code text null,
  role_code text not null default 'ADMIN',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_user_profiles_display_name_nonblank check (btrim(display_name) <> ''),
  constraint ck_user_profiles_employee_code_nonblank check (
    employee_code is null or btrim(employee_code) <> ''
  ),
  constraint ck_user_profiles_role_code check (role_code = 'ADMIN')
);

create unique index uidx_user_profiles_employee_code
on app.user_profiles (organization_id, employee_code)
where employee_code is not null;

create index idx_user_profiles_organization
on app.user_profiles (organization_id, is_active, user_id);

create trigger trg_user_profiles_touch_updated_at
before update on app.user_profiles
for each row execute function app.touch_updated_at();

create table app.settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete cascade,
  key text not null,
  value jsonb not null,
  version integer not null default 1,
  effective_from timestamptz not null default now(),
  effective_to timestamptz null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint ck_settings_key_nonblank check (btrim(key) <> ''),
  constraint ck_settings_version_positive check (version > 0),
  constraint ck_settings_effective_range check (
    effective_to is null or effective_to > effective_from
  ),
  constraint uq_settings_version unique (organization_id, key, version)
);

create unique index uidx_settings_active
on app.settings (organization_id, key)
where effective_to is null;

create index idx_settings_lookup
on app.settings (organization_id, key, effective_from desc);

create table catalog.channels (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  is_marketplace boolean not null default false,
  is_active boolean not null default true,
  constraint uq_channels_code unique (code),
  constraint ck_channels_code_nonblank check (btrim(code) <> ''),
  constraint ck_channels_name_nonblank check (btrim(name) <> '')
);

create table catalog.movement_reasons (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  direction_code text not null,
  requires_note boolean not null default false,
  is_system boolean not null default false,
  is_active boolean not null default true,
  constraint uq_movement_reasons_code unique (code),
  constraint ck_movement_reasons_code_nonblank check (btrim(code) <> ''),
  constraint ck_movement_reasons_name_nonblank check (btrim(name) <> ''),
  constraint ck_movement_reasons_direction check (
    direction_code in ('INBOUND', 'OUTBOUND', 'TRANSFER', 'ADJUSTMENT')
  )
);

create table catalog.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  sku text not null,
  name text not null,
  unit_code text not null default 'UNIT',
  barcode text null,
  description text null,
  is_batch_tracked boolean not null default true,
  is_expiry_tracked boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid null references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid null references auth.users(id) on delete set null,
  row_version bigint not null default 1,
  constraint uq_products_org_sku unique (organization_id, sku),
  constraint uq_products_org_id unique (organization_id, id),
  constraint ck_products_sku_nonblank check (btrim(sku) <> ''),
  constraint ck_products_name_nonblank check (btrim(name) <> ''),
  constraint ck_products_unit check (unit_code = 'UNIT'),
  constraint ck_products_batch_tracking check (is_batch_tracked),
  constraint ck_products_expiry_tracking check (is_expiry_tracked),
  constraint ck_products_row_version_positive check (row_version > 0)
);

create unique index uidx_products_barcode
on catalog.products (organization_id, barcode)
where barcode is not null;

create index idx_products_active_name
on catalog.products (organization_id, is_active, name, id);

create trigger trg_products_touch_mutable
before update on catalog.products
for each row execute function app.touch_mutable_row();

create table catalog.product_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  product_id uuid not null,
  batch_code text not null,
  manufactured_date date null,
  expiry_date date not null,
  received_first_at timestamptz null,
  status_code text not null default 'ACTIVE',
  block_reason text null,
  created_at timestamptz not null default now(),
  created_by uuid null references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid null references auth.users(id) on delete set null,
  row_version bigint not null default 1,
  constraint fk_product_batches_product
    foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,
  constraint uq_product_batches_org_product_code
    unique (organization_id, product_id, batch_code),
  constraint uq_product_batches_org_product_id
    unique (organization_id, product_id, id),
  constraint ck_product_batches_code_nonblank check (btrim(batch_code) <> ''),
  constraint ck_product_batches_dates check (
    manufactured_date is null or manufactured_date <= expiry_date
  ),
  constraint ck_product_batches_status check (
    status_code in ('ACTIVE', 'BLOCKED', 'EXPIRED', 'ARCHIVED')
  ),
  constraint ck_product_batches_block_reason check (
    status_code <> 'BLOCKED' or (block_reason is not null and btrim(block_reason) <> '')
  ),
  constraint ck_product_batches_row_version_positive check (row_version > 0)
);

create index idx_product_batches_fefo
on catalog.product_batches (
  organization_id,
  product_id,
  expiry_date,
  received_first_at,
  batch_code,
  id
)
where status_code = 'ACTIVE';

create trigger trg_product_batches_touch_mutable
before update on catalog.product_batches
for each row execute function app.touch_mutable_row();

create table catalog.bundle_recipes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  channel_id uuid not null references catalog.channels(id) on delete restrict,
  external_listing_sku text not null,
  external_listing_name text not null,
  version integer not null default 1,
  effective_from timestamptz not null default now(),
  effective_to timestamptz null,
  is_active boolean not null default true,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint ck_bundle_recipes_sku_nonblank check (btrim(external_listing_sku) <> ''),
  constraint ck_bundle_recipes_name_nonblank check (btrim(external_listing_name) <> ''),
  constraint ck_bundle_recipes_version_positive check (version > 0),
  constraint ck_bundle_recipes_effective_range check (
    effective_to is null or effective_to > effective_from
  ),
  constraint uq_bundle_recipes_version unique (
    organization_id,
    channel_id,
    external_listing_sku,
    version
  )
);

create unique index uidx_bundle_recipes_active
on catalog.bundle_recipes (organization_id, channel_id, external_listing_sku)
where effective_to is null and is_active;

create table catalog.bundle_components (
  id uuid primary key default gen_random_uuid(),
  bundle_recipe_id uuid not null references catalog.bundle_recipes(id) on delete cascade,
  product_id uuid not null references catalog.products(id) on delete restrict,
  component_qty bigint not null,
  line_no integer not null,
  constraint uq_bundle_components_product unique (bundle_recipe_id, product_id),
  constraint uq_bundle_components_line unique (bundle_recipe_id, line_no),
  constraint ck_bundle_components_qty_positive check (component_qty > 0),
  constraint ck_bundle_components_line_positive check (line_no > 0)
);

commit;
