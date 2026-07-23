begin;

create table catalog.marketplace_listings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  channel_id uuid not null references catalog.channels(id) on delete restrict,
  external_listing_code text not null,
  display_name text not null,
  listing_type_code text not null,
  status_code text not null default 'ACTIVE',
  created_at timestamptz not null default clock_timestamp(),
  created_by uuid null references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid null references auth.users(id) on delete set null,
  row_version bigint not null default 1,
  constraint uq_marketplace_listings_org_id unique (organization_id, id),
  constraint uq_marketplace_listings_identity unique (
    organization_id,
    channel_id,
    external_listing_code
  ),
  constraint ck_marketplace_listings_code_nonblank
    check (btrim(external_listing_code) <> ''),
  constraint ck_marketplace_listings_code_length
    check (length(external_listing_code) <= 200),
  constraint ck_marketplace_listings_name_nonblank
    check (btrim(display_name) <> ''),
  constraint ck_marketplace_listings_name_length
    check (length(display_name) <= 300),
  constraint ck_marketplace_listings_type
    check (listing_type_code in ('SINGLE', 'BUNDLE')),
  constraint ck_marketplace_listings_status
    check (status_code in ('ACTIVE', 'ARCHIVED')),
  constraint ck_marketplace_listings_row_version_positive
    check (row_version > 0)
);

create index idx_marketplace_listings_lookup
on catalog.marketplace_listings (
  organization_id,
  channel_id,
  status_code,
  external_listing_code,
  id
);

create table catalog.marketplace_single_listing_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  listing_id uuid not null,
  version integer not null,
  product_id uuid not null,
  status_code text not null default 'DRAFT',
  effective_from timestamptz not null,
  effective_to timestamptz null,
  mapping_fingerprint text not null default repeat('0', 64),
  activated_at timestamptz null,
  activated_by uuid null references auth.users(id) on delete set null,
  retired_at timestamptz null,
  retired_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  created_by uuid null references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid null references auth.users(id) on delete set null,
  row_version bigint not null default 1,
  schema_version integer not null default 1,
  constraint uq_marketplace_single_listing_versions_org_id
    unique (organization_id, id),
  constraint fk_marketplace_single_listing_versions_listing
    foreign key (organization_id, listing_id)
    references catalog.marketplace_listings (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_single_listing_versions_product
    foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,
  constraint uq_marketplace_single_listing_versions_version
    unique (listing_id, version),
  constraint ck_marketplace_single_listing_versions_version_positive
    check (version > 0),
  constraint ck_marketplace_single_listing_versions_status
    check (status_code in ('DRAFT', 'ACTIVE', 'RETIRED')),
  constraint ck_marketplace_single_listing_versions_effective_range
    check (effective_to is null or effective_to > effective_from),
  constraint ck_marketplace_single_listing_versions_fingerprint
    check (mapping_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint ck_marketplace_single_listing_versions_activation_shape
    check (
      (
        status_code = 'DRAFT'
        and activated_at is null
        and activated_by is null
        and retired_at is null
        and retired_by is null
      )
      or (
        status_code = 'ACTIVE'
        and activated_at is not null
        and retired_at is null
        and retired_by is null
      )
      or (
        status_code = 'RETIRED'
        and activated_at is not null
        and effective_to is not null
        and retired_at is not null
      )
    ),
  constraint ck_marketplace_single_listing_versions_row_version_positive
    check (row_version > 0),
  constraint ck_marketplace_single_listing_versions_schema_version_positive
    check (schema_version > 0)
);

create unique index uidx_marketplace_single_listing_versions_open_active
on catalog.marketplace_single_listing_versions (listing_id)
where status_code = 'ACTIVE' and effective_to is null;

create index idx_marketplace_single_listing_versions_effective
on catalog.marketplace_single_listing_versions (
  organization_id,
  listing_id,
  status_code,
  effective_from desc,
  version desc,
  id
);

create or replace function catalog.validate_marketplace_listing_channel()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog
as $$
declare
  v_is_marketplace boolean;
  v_is_active boolean;
begin
  new.external_listing_code := btrim(new.external_listing_code);
  new.display_name := btrim(new.display_name);

  select channel.is_marketplace, channel.is_active
  into v_is_marketplace, v_is_active
  from catalog.channels channel
  where channel.id = new.channel_id;

  if not found or not v_is_marketplace or not v_is_active then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_CHANNEL_NOT_ALLOWED';
  end if;

  return new;
end;
$$;

create trigger trg_marketplace_listings_validate_channel
before insert or update of channel_id
on catalog.marketplace_listings
for each row execute function catalog.validate_marketplace_listing_channel();

create or replace function catalog.protect_marketplace_listing_identity()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.organization_id is distinct from old.organization_id
     or new.channel_id is distinct from old.channel_id
     or new.external_listing_code is distinct from old.external_listing_code
     or new.listing_type_code is distinct from old.listing_type_code then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_IDENTITY_IMMUTABLE';
  end if;

  return new;
end;
$$;

create trigger trg_marketplace_listings_protect_identity
before update
on catalog.marketplace_listings
for each row execute function catalog.protect_marketplace_listing_identity();

create trigger trg_marketplace_listings_touch_mutable
before update on catalog.marketplace_listings
for each row execute function app.touch_mutable_row();

create or replace function catalog.validate_single_listing_version()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog
as $$
declare
  v_listing_type text;
  v_listing_status text;
  v_product_active boolean;
begin
  select listing.listing_type_code, listing.status_code
  into v_listing_type, v_listing_status
  from catalog.marketplace_listings listing
  where listing.organization_id = new.organization_id
    and listing.id = new.listing_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_NOT_FOUND';
  end if;

  if v_listing_type <> 'SINGLE' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SINGLE_VERSION_LISTING_TYPE_INVALID';
  end if;

  if v_listing_status <> 'ACTIVE' and new.status_code = 'ACTIVE' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_ARCHIVED';
  end if;

  select product.is_active
  into v_product_active
  from catalog.products product
  where product.organization_id = new.organization_id
    and product.id = new.product_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_PRODUCT_NOT_FOUND';
  end if;

  if new.status_code = 'ACTIVE' and not v_product_active then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_PRODUCT_INACTIVE';
  end if;

  new.mapping_fingerprint := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', new.organization_id,
          'listingId', new.listing_id,
          'version', new.version,
          'productId', new.product_id,
          'schemaVersion', new.schema_version
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  return new;
end;
$$;

create trigger trg_marketplace_single_listing_versions_validate
before insert or update
on catalog.marketplace_single_listing_versions
for each row execute function catalog.validate_single_listing_version();

create trigger trg_marketplace_single_listing_versions_touch_mutable
before update on catalog.marketplace_single_listing_versions
for each row execute function app.touch_mutable_row();

create or replace function catalog.protect_marketplace_single_version_history()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    if old.status_code <> 'DRAFT' then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_VERSION_IMMUTABLE';
    end if;

    return old;
  end if;

  if old.status_code = 'DRAFT' then
    return new;
  end if;

  if old.status_code = 'ACTIVE'
     and new.status_code = 'RETIRED'
     and new.organization_id is not distinct from old.organization_id
     and new.listing_id is not distinct from old.listing_id
     and new.version is not distinct from old.version
     and new.product_id is not distinct from old.product_id
     and new.effective_from is not distinct from old.effective_from
     and new.mapping_fingerprint is not distinct from old.mapping_fingerprint
     and new.activated_at is not distinct from old.activated_at
     and new.activated_by is not distinct from old.activated_by
     and new.created_at is not distinct from old.created_at
     and new.created_by is not distinct from old.created_by
     and new.schema_version is not distinct from old.schema_version
     and new.effective_to is not null
     and new.retired_at is not null then
    return new;
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'MARKETPLACE_LISTING_VERSION_IMMUTABLE';
end;
$$;

create trigger trg_marketplace_single_listing_versions_protect_history
before update or delete
on catalog.marketplace_single_listing_versions
for each row execute function catalog.protect_marketplace_single_version_history();

create or replace function catalog.reject_marketplace_single_version_overlap()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog
as $$
begin
  if new.status_code = 'ACTIVE'
     and exists (
       select 1
       from catalog.marketplace_single_listing_versions existing
       where existing.organization_id = new.organization_id
         and existing.listing_id = new.listing_id
         and existing.id <> new.id
         and existing.status_code = 'ACTIVE'
         and tstzrange(
           existing.effective_from,
           existing.effective_to,
           '[)'
         ) && tstzrange(
           new.effective_from,
           new.effective_to,
           '[)'
         )
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_VERSION_OVERLAP';
  end if;

  return new;
end;
$$;

create trigger trg_marketplace_single_listing_versions_reject_overlap
before insert or update
on catalog.marketplace_single_listing_versions
for each row execute function catalog.reject_marketplace_single_version_overlap();

create or replace function catalog.sync_bundle_recipe_marketplace_listing()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog
as $$
declare
  v_listing catalog.marketplace_listings%rowtype;
begin
  select listing.*
  into v_listing
  from catalog.marketplace_listings listing
  where listing.organization_id = new.organization_id
    and listing.channel_id = new.channel_id
    and listing.external_listing_code = new.external_listing_sku
  for update;

  if found then
    if v_listing.listing_type_code <> 'BUNDLE' then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_TYPE_CONFLICT';
    end if;

    update catalog.marketplace_listings listing
    set
      display_name = new.external_listing_name,
      updated_by = new.created_by
    where listing.id = v_listing.id
      and listing.display_name is distinct from new.external_listing_name;

    return new;
  end if;

  insert into catalog.marketplace_listings (
    organization_id,
    channel_id,
    external_listing_code,
    display_name,
    listing_type_code,
    status_code,
    created_by,
    updated_by
  ) values (
    new.organization_id,
    new.channel_id,
    new.external_listing_sku,
    new.external_listing_name,
    'BUNDLE',
    'ACTIVE',
    new.created_by,
    new.created_by
  );

  return new;
end;
$$;

create trigger trg_bundle_recipes_sync_marketplace_listing
after insert or update of
  organization_id,
  channel_id,
  external_listing_sku,
  external_listing_name
on catalog.bundle_recipes
for each row execute function catalog.sync_bundle_recipe_marketplace_listing();

insert into catalog.marketplace_listings (
  organization_id,
  channel_id,
  external_listing_code,
  display_name,
  listing_type_code,
  status_code,
  created_by,
  updated_by
)
select distinct on (
  recipe.organization_id,
  recipe.channel_id,
  recipe.external_listing_sku
)
  recipe.organization_id,
  recipe.channel_id,
  recipe.external_listing_sku,
  recipe.external_listing_name,
  'BUNDLE',
  'ACTIVE',
  recipe.created_by,
  recipe.created_by
from catalog.bundle_recipes recipe
order by
  recipe.organization_id,
  recipe.channel_id,
  recipe.external_listing_sku,
  recipe.version desc,
  recipe.effective_from desc,
  recipe.id
on conflict (
  organization_id,
  channel_id,
  external_listing_code
) do update
set
  display_name = excluded.display_name,
  updated_by = excluded.updated_by;

alter table catalog.marketplace_listings enable row level security;
alter table catalog.marketplace_single_listing_versions enable row level security;

create policy marketplace_listings_read_current_org
on catalog.marketplace_listings
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy marketplace_single_listing_versions_read_current_org
on catalog.marketplace_single_listing_versions
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on catalog.marketplace_listings,
              catalog.marketplace_single_listing_versions
from public, anon, authenticated;

grant select on catalog.marketplace_listings,
                catalog.marketplace_single_listing_versions
to authenticated, service_role;

create or replace view api.marketplace_listing_catalog
with (security_invoker = true)
as
select
  listing.id as listing_id,
  listing.organization_id,
  channel.code as channel_code,
  listing.external_listing_code,
  listing.display_name,
  listing.listing_type_code,
  listing.status_code,
  coalesce(single_version.version, bundle_recipe.version) as current_version,
  coalesce(single_version.effective_from, bundle_recipe.effective_from) as effective_from,
  coalesce(single_version.effective_to, bundle_recipe.effective_to) as effective_to,
  single_version.product_id,
  bundle_recipe.id as bundle_recipe_id,
  single_version.mapping_fingerprint,
  listing.created_at,
  listing.updated_at,
  listing.row_version
from catalog.marketplace_listings listing
join catalog.channels channel
  on channel.id = listing.channel_id
left join lateral (
  select version.*
  from catalog.marketplace_single_listing_versions version
  where version.organization_id = listing.organization_id
    and version.listing_id = listing.id
    and version.status_code = 'ACTIVE'
    and version.effective_from <= clock_timestamp()
    and (
      version.effective_to is null
      or version.effective_to > clock_timestamp()
    )
  order by version.version desc, version.effective_from desc, version.id
  limit 1
) single_version
  on listing.listing_type_code = 'SINGLE'
left join lateral (
  select recipe.*
  from catalog.bundle_recipes recipe
  where recipe.organization_id = listing.organization_id
    and recipe.channel_id = listing.channel_id
    and recipe.external_listing_sku = listing.external_listing_code
    and recipe.is_active
    and recipe.effective_from <= clock_timestamp()
    and (
      recipe.effective_to is null
      or recipe.effective_to > clock_timestamp()
    )
  order by recipe.version desc, recipe.effective_from desc, recipe.id
  limit 1
) bundle_recipe
  on listing.listing_type_code = 'BUNDLE';

revoke all on api.marketplace_listing_catalog from public, anon;
grant select on api.marketplace_listing_catalog to authenticated, service_role;

create or replace function api.preview_marketplace_listing_expansion(
  p_organization_id uuid,
  p_channel_code text,
  p_external_listing_code text,
  p_listing_quantity bigint,
  p_occurred_at timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, auth, app, catalog, extensions
as $$
declare
  v_channel_code text;
  v_external_listing_code text;
  v_channel_id uuid;
  v_listing catalog.marketplace_listings%rowtype;
  v_single_version catalog.marketplace_single_listing_versions%rowtype;
  v_bundle_recipe catalog.bundle_recipes%rowtype;
  v_match_count bigint;
  v_components jsonb;
  v_component_count bigint;
  v_total_numeric numeric;
  v_fingerprint text;
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text := coalesce(
    auth.jwt() ->> 'role',
    current_setting('request.jwt.claim.role', true)
  );
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_REQUIRED';
  end if;

  v_channel_code := upper(btrim(coalesce(p_channel_code, '')));
  v_external_listing_code := btrim(coalesce(p_external_listing_code, ''));

  if v_channel_code = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CHANNEL_REQUIRED';
  end if;

  if v_external_listing_code = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_CODE_REQUIRED';
  end if;

  if length(v_external_listing_code) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_CODE_TOO_LONG';
  end if;

  if p_listing_quantity is null or p_listing_quantity <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_QUANTITY_INVALID';
  end if;

  if p_listing_quantity > 1000000000 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_QUANTITY_TOO_LARGE';
  end if;

  if p_occurred_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_OCCURRED_AT_REQUIRED';
  end if;

  if v_jwt_role = 'anon'
     or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using
      errcode = '42501',
      message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using
      errcode = '42501',
      message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id then
      raise exception using
        errcode = '42501',
        message = 'ORGANIZATION_ACCESS_DENIED';
    end if;
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = v_channel_code
    and channel.is_marketplace
    and channel.is_active;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CHANNEL_NOT_ALLOWED';
  end if;

  select listing.*
  into v_listing
  from catalog.marketplace_listings listing
  where listing.organization_id = p_organization_id
    and listing.channel_id = v_channel_id
    and listing.external_listing_code = v_external_listing_code;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_NOT_FOUND';
  end if;

  if v_listing.status_code <> 'ACTIVE' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_ARCHIVED';
  end if;

  if v_listing.listing_type_code = 'SINGLE' then
    select count(*)
    into v_match_count
    from catalog.marketplace_single_listing_versions version
    where version.organization_id = p_organization_id
      and version.listing_id = v_listing.id
      and version.status_code = 'ACTIVE'
      and version.effective_from <= p_occurred_at
      and (
        version.effective_to is null
        or version.effective_to > p_occurred_at
      );

    if v_match_count = 0 then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_MAPPING_NOT_FOUND';
    end if;

    if v_match_count > 1 then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_MAPPING_AMBIGUOUS';
    end if;

    select version.*
    into strict v_single_version
    from catalog.marketplace_single_listing_versions version
    where version.organization_id = p_organization_id
      and version.listing_id = v_listing.id
      and version.status_code = 'ACTIVE'
      and version.effective_from <= p_occurred_at
      and (
        version.effective_to is null
        or version.effective_to > p_occurred_at
      );

    select jsonb_build_array(
      jsonb_build_object(
        'componentLineNo', 1,
        'productId', product.id,
        'productSku', product.sku,
        'productName', product.name,
        'unitQuantityPerListing', 1,
        'listingQuantity', p_listing_quantity,
        'expandedQuantity', p_listing_quantity
      )
    )
    into v_components
    from catalog.products product
    where product.organization_id = p_organization_id
      and product.id = v_single_version.product_id
      and product.is_active;

    if v_components is null then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_PRODUCT_INACTIVE';
    end if;

    return jsonb_build_object(
      'listingId', v_listing.id,
      'channelCode', v_channel_code,
      'externalListingCode', v_listing.external_listing_code,
      'listingName', v_listing.display_name,
      'listingType', v_listing.listing_type_code,
      'listingQuantity', p_listing_quantity,
      'mappingVersion', v_single_version.version,
      'bundleRecipeId', null,
      'bundleRecipeVersion', null,
      'mappingFingerprint', v_single_version.mapping_fingerprint,
      'totalUnitQuantity', p_listing_quantity,
      'components', v_components,
      'stockEffect', 'NONE'
    );
  end if;

  select count(*)
  into v_match_count
  from catalog.bundle_recipes recipe
  where recipe.organization_id = p_organization_id
    and recipe.channel_id = v_channel_id
    and recipe.external_listing_sku = v_external_listing_code
    and recipe.is_active
    and recipe.effective_from <= p_occurred_at
    and (
      recipe.effective_to is null
      or recipe.effective_to > p_occurred_at
    );

  if v_match_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_RECIPE_NOT_FOUND';
  end if;

  if v_match_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_RECIPE_AMBIGUOUS';
  end if;

  select recipe.*
  into strict v_bundle_recipe
  from catalog.bundle_recipes recipe
  where recipe.organization_id = p_organization_id
    and recipe.channel_id = v_channel_id
    and recipe.external_listing_sku = v_external_listing_code
    and recipe.is_active
    and recipe.effective_from <= p_occurred_at
    and (
      recipe.effective_to is null
      or recipe.effective_to > p_occurred_at
    );

  if exists (
    select 1
    from catalog.bundle_components component
    join catalog.products product
      on product.id = component.product_id
    where component.bundle_recipe_id = v_bundle_recipe.id
      and (
        product.organization_id <> p_organization_id
        or not product.is_active
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENT_INVALID';
  end if;

  select
    jsonb_agg(
      jsonb_build_object(
        'componentLineNo', component.line_no,
        'productId', product.id,
        'productSku', product.sku,
        'productName', product.name,
        'unitQuantityPerListing', component.component_qty,
        'listingQuantity', p_listing_quantity,
        'expandedQuantity', component.component_qty * p_listing_quantity
      )
      order by component.line_no, product.sku, product.id
    ),
    count(*),
    sum(component.component_qty::numeric * p_listing_quantity::numeric)
  into v_components, v_component_count, v_total_numeric
  from catalog.bundle_components component
  join catalog.products product
    on product.id = component.product_id
   and product.organization_id = p_organization_id
   and product.is_active
  where component.bundle_recipe_id = v_bundle_recipe.id;

  if v_component_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENTS_REQUIRED';
  end if;

  if v_total_numeric > 9223372036854775807::numeric then
    raise exception using
      errcode = '22003',
      message = 'MARKETPLACE_BUNDLE_EXPANSION_OVERFLOW';
  end if;

  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'recipeId', v_bundle_recipe.id,
          'version', v_bundle_recipe.version,
          'components',
            jsonb_agg(
              jsonb_build_object(
                'lineNo', component.line_no,
                'productId', component.product_id,
                'componentQuantity', component.component_qty
              )
              order by component.line_no, component.product_id
            ),
          'schemaVersion', 1
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_fingerprint
  from catalog.bundle_components component
  where component.bundle_recipe_id = v_bundle_recipe.id;

  return jsonb_build_object(
    'listingId', v_listing.id,
    'channelCode', v_channel_code,
    'externalListingCode', v_listing.external_listing_code,
    'listingName', v_listing.display_name,
    'listingType', v_listing.listing_type_code,
    'listingQuantity', p_listing_quantity,
    'mappingVersion', v_bundle_recipe.version,
    'bundleRecipeId', v_bundle_recipe.id,
    'bundleRecipeVersion', v_bundle_recipe.version,
    'mappingFingerprint', v_fingerprint,
    'totalUnitQuantity', v_total_numeric::bigint,
    'components', v_components,
    'stockEffect', 'NONE'
  );
end;
$$;

revoke all on function api.preview_marketplace_listing_expansion(
  uuid,
  text,
  text,
  bigint,
  timestamptz
) from public, anon;

grant execute on function api.preview_marketplace_listing_expansion(
  uuid,
  text,
  text,
  bigint,
  timestamptz
) to authenticated, service_role;

commit;
