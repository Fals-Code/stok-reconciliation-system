begin;

alter table catalog.bundle_recipes
add constraint uq_bundle_recipes_org_id unique (organization_id, id);

create table operations.marketplace_normalization_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  marketplace_event_id uuid not null,
  order_id uuid not null,
  channel_id uuid not null references catalog.channels(id) on delete restrict,
  external_event_ref_snapshot text not null,
  external_order_ref_snapshot text not null,
  source_status_snapshot text not null,
  occurred_at timestamptz not null,
  received_at timestamptz not null,
  raw_payload jsonb not null default '{}'::jsonb,
  raw_payload_hash text not null,
  normalization_schema_version integer not null default 1,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_marketplace_normalization_events_org_id
    unique (organization_id, id),
  constraint fk_marketplace_normalization_events_event
    foreign key (organization_id, marketplace_event_id)
    references operations.marketplace_events (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_normalization_events_order
    foreign key (organization_id, order_id)
    references operations.marketplace_orders (organization_id, id)
    on delete restrict,
  constraint uq_marketplace_normalization_events_marketplace_event
    unique (marketplace_event_id),
  constraint uq_marketplace_normalization_events_idempotency
    unique (idempotency_command_id),
  constraint ck_marketplace_normalization_events_event_ref_nonblank
    check (btrim(external_event_ref_snapshot) <> ''),
  constraint ck_marketplace_normalization_events_order_ref_nonblank
    check (btrim(external_order_ref_snapshot) <> ''),
  constraint ck_marketplace_normalization_events_status_nonblank
    check (btrim(source_status_snapshot) <> ''),
  constraint ck_marketplace_normalization_events_received_after_occurred
    check (received_at >= occurred_at),
  constraint ck_marketplace_normalization_events_payload_object
    check (jsonb_typeof(raw_payload) = 'object'),
  constraint ck_marketplace_normalization_events_payload_hash
    check (raw_payload_hash ~ '^[0-9a-f]{64}$'),
  constraint ck_marketplace_normalization_events_schema_version_positive
    check (normalization_schema_version > 0),
  constraint ck_marketplace_normalization_events_actor_xor_process
    check ((actor_user_id is not null) <> (process_name is not null)),
  constraint ck_marketplace_normalization_events_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),
  constraint ck_marketplace_normalization_events_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create table operations.marketplace_source_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  normalization_event_id uuid not null,
  order_id uuid not null,
  line_no integer not null,
  source_line_ref text not null,
  listing_id uuid not null,
  external_listing_code_snapshot text not null,
  listing_name_snapshot text not null,
  listing_type_code_snapshot text not null,
  listing_quantity bigint not null,
  mapping_version integer not null,
  single_listing_version_id uuid null,
  bundle_recipe_id uuid null,
  mapping_fingerprint text not null,
  source_title_snapshot text null,
  source_sku_snapshot text null,
  source_status_snapshot text not null,
  raw_line_payload jsonb not null default '{}'::jsonb,
  raw_line_hash text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_marketplace_source_lines_org_id
    unique (organization_id, id),
  constraint fk_marketplace_source_lines_normalization
    foreign key (organization_id, normalization_event_id)
    references operations.marketplace_normalization_events (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_source_lines_order
    foreign key (organization_id, order_id)
    references operations.marketplace_orders (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_source_lines_listing
    foreign key (organization_id, listing_id)
    references catalog.marketplace_listings (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_source_lines_single_version
    foreign key (organization_id, single_listing_version_id)
    references catalog.marketplace_single_listing_versions (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_source_lines_bundle_recipe
    foreign key (organization_id, bundle_recipe_id)
    references catalog.bundle_recipes (organization_id, id)
    on delete restrict,
  constraint uq_marketplace_source_lines_line
    unique (normalization_event_id, line_no),
  constraint uq_marketplace_source_lines_ref
    unique (normalization_event_id, source_line_ref),
  constraint uq_marketplace_source_lines_order_ref
    unique (order_id, source_line_ref),
  constraint ck_marketplace_source_lines_line_positive
    check (line_no > 0),
  constraint ck_marketplace_source_lines_ref_nonblank
    check (btrim(source_line_ref) <> ''),
  constraint ck_marketplace_source_lines_listing_code_nonblank
    check (btrim(external_listing_code_snapshot) <> ''),
  constraint ck_marketplace_source_lines_listing_name_nonblank
    check (btrim(listing_name_snapshot) <> ''),
  constraint ck_marketplace_source_lines_listing_type
    check (listing_type_code_snapshot in ('SINGLE', 'BUNDLE')),
  constraint ck_marketplace_source_lines_quantity_positive
    check (listing_quantity > 0),
  constraint ck_marketplace_source_lines_mapping_version_positive
    check (mapping_version > 0),
  constraint ck_marketplace_source_lines_mapping_xor
    check (
      (
        listing_type_code_snapshot = 'SINGLE'
        and single_listing_version_id is not null
        and bundle_recipe_id is null
      )
      or (
        listing_type_code_snapshot = 'BUNDLE'
        and single_listing_version_id is null
        and bundle_recipe_id is not null
      )
    ),
  constraint ck_marketplace_source_lines_fingerprint
    check (mapping_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint ck_marketplace_source_lines_title_nonblank
    check (
      source_title_snapshot is null
      or btrim(source_title_snapshot) <> ''
    ),
  constraint ck_marketplace_source_lines_sku_nonblank
    check (
      source_sku_snapshot is null
      or btrim(source_sku_snapshot) <> ''
    ),
  constraint ck_marketplace_source_lines_status_nonblank
    check (btrim(source_status_snapshot) <> ''),
  constraint ck_marketplace_source_lines_payload_object
    check (jsonb_typeof(raw_line_payload) = 'object'),
  constraint ck_marketplace_source_lines_raw_hash
    check (raw_line_hash ~ '^[0-9a-f]{64}$')
);

create table operations.marketplace_source_line_components (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  source_line_id uuid not null,
  component_no integer not null,
  recipe_component_id uuid null
    references catalog.bundle_components(id) on delete restrict,
  order_item_id uuid not null,
  reserve_event_line_id uuid not null,
  product_id uuid not null,
  canonical_source_line_ref text not null,
  product_sku_snapshot text not null,
  product_name_snapshot text not null,
  unit_quantity_per_listing bigint not null,
  listing_quantity bigint not null,
  expanded_quantity bigint not null,
  mapping_fingerprint text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_marketplace_source_line_components_org_id
    unique (organization_id, id),
  constraint fk_marketplace_source_line_components_source
    foreign key (organization_id, source_line_id)
    references operations.marketplace_source_lines (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_source_line_components_order_item
    foreign key (organization_id, order_item_id)
    references operations.marketplace_order_items (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_source_line_components_event_line
    foreign key (organization_id, reserve_event_line_id)
    references operations.marketplace_event_lines (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_source_line_components_product
    foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,
  constraint uq_marketplace_source_line_components_line
    unique (source_line_id, component_no),
  constraint uq_marketplace_source_line_components_order_item
    unique (order_item_id),
  constraint uq_marketplace_source_line_components_event_line
    unique (reserve_event_line_id),
  constraint uq_marketplace_source_line_components_ref
    unique (source_line_id, canonical_source_line_ref),
  constraint ck_marketplace_source_line_components_no_positive
    check (component_no > 0),
  constraint ck_marketplace_source_line_components_ref_nonblank
    check (btrim(canonical_source_line_ref) <> ''),
  constraint ck_marketplace_source_line_components_sku_nonblank
    check (btrim(product_sku_snapshot) <> ''),
  constraint ck_marketplace_source_line_components_name_nonblank
    check (btrim(product_name_snapshot) <> ''),
  constraint ck_marketplace_source_line_components_unit_positive
    check (unit_quantity_per_listing > 0),
  constraint ck_marketplace_source_line_components_listing_positive
    check (listing_quantity > 0),
  constraint ck_marketplace_source_line_components_expanded_positive
    check (expanded_quantity > 0),
  constraint ck_marketplace_source_line_components_quantity_math
    check (
      expanded_quantity::numeric =
        unit_quantity_per_listing::numeric * listing_quantity::numeric
    ),
  constraint ck_marketplace_source_line_components_fingerprint
    check (mapping_fingerprint ~ '^[0-9a-f]{64}$')
);

create or replace function operations.validate_marketplace_source_line_snapshot()
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
    and listing.id = new.listing_id;

  if not found
     or v_listing.external_listing_code
          is distinct from new.external_listing_code_snapshot
     or v_listing.display_name
          is distinct from new.listing_name_snapshot
     or v_listing.listing_type_code
          is distinct from new.listing_type_code_snapshot then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_LISTING_SNAPSHOT_INVALID';
  end if;

  if new.listing_type_code_snapshot = 'SINGLE' then
    if not exists (
      select 1
      from catalog.marketplace_single_listing_versions version
      where version.organization_id = new.organization_id
        and version.id = new.single_listing_version_id
        and version.listing_id = new.listing_id
        and version.version = new.mapping_version
        and version.mapping_fingerprint =
          new.mapping_fingerprint
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_SOURCE_SINGLE_MAPPING_INVALID';
    end if;
  else
    if not exists (
      select 1
      from catalog.bundle_recipes recipe
      where recipe.organization_id = new.organization_id
        and recipe.id = new.bundle_recipe_id
        and recipe.channel_id = v_listing.channel_id
        and recipe.external_listing_sku =
          new.external_listing_code_snapshot
        and recipe.version = new.mapping_version
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_SOURCE_BUNDLE_MAPPING_INVALID';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_marketplace_source_lines_validate
before insert
on operations.marketplace_source_lines
for each row execute function operations.validate_marketplace_source_line_snapshot();

create or replace function operations.validate_marketplace_source_component_snapshot()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog, operations
as $$
declare
  v_source_line operations.marketplace_source_lines%rowtype;
begin
  select source_line.*
  into v_source_line
  from operations.marketplace_source_lines source_line
  where source_line.organization_id = new.organization_id
    and source_line.id = new.source_line_id;

  if not found
     or new.listing_quantity
          is distinct from v_source_line.listing_quantity
     or new.mapping_fingerprint
          is distinct from v_source_line.mapping_fingerprint then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_COMPONENT_BASIS_INVALID';
  end if;

  if v_source_line.listing_type_code_snapshot = 'SINGLE' then
    if new.recipe_component_id is not null
       or new.component_no <> 1
       or new.unit_quantity_per_listing <> 1 then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_SINGLE_COMPONENT_SNAPSHOT_INVALID';
    end if;
  else
    if new.recipe_component_id is null
       or not exists (
         select 1
         from catalog.bundle_components component
         where component.id = new.recipe_component_id
           and component.bundle_recipe_id =
             v_source_line.bundle_recipe_id
           and component.product_id = new.product_id
           and component.line_no = new.component_no
           and component.component_qty =
             new.unit_quantity_per_listing
       ) then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_BUNDLE_COMPONENT_SNAPSHOT_INVALID';
    end if;
  end if;

  if not exists (
    select 1
    from operations.marketplace_order_items item
    where item.organization_id = new.organization_id
      and item.id = new.order_item_id
      and item.order_id = v_source_line.order_id
      and item.product_id = new.product_id
      and item.external_item_ref =
        new.canonical_source_line_ref
      and item.quantity_ordered = new.expanded_quantity
      and item.product_sku_snapshot =
        new.product_sku_snapshot
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_ORDER_ITEM_LINK_INVALID';
  end if;

  if not exists (
    select 1
    from operations.marketplace_event_lines event_line
    where event_line.organization_id = new.organization_id
      and event_line.id = new.reserve_event_line_id
      and event_line.order_item_id = new.order_item_id
      and event_line.product_id = new.product_id
      and event_line.quantity = new.expanded_quantity
      and event_line.source_line_ref =
        new.canonical_source_line_ref
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_EVENT_LINE_LINK_INVALID';
  end if;

  return new;
end;
$$;

create trigger trg_marketplace_source_line_components_validate
before insert
on operations.marketplace_source_line_components
for each row execute function operations.validate_marketplace_source_component_snapshot();

create index idx_marketplace_normalization_events_order
on operations.marketplace_normalization_events (
  organization_id,
  order_id,
  occurred_at,
  id
);

create index idx_marketplace_source_lines_listing
on operations.marketplace_source_lines (
  organization_id,
  listing_id,
  created_at,
  id
);

create index idx_marketplace_source_line_components_product
on operations.marketplace_source_line_components (
  organization_id,
  product_id,
  source_line_id,
  component_no
);

create trigger trg_marketplace_normalization_events_immutable
before update or delete
on operations.marketplace_normalization_events
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_marketplace_source_lines_immutable
before update or delete
on operations.marketplace_source_lines
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_marketplace_source_line_components_immutable
before update or delete
on operations.marketplace_source_line_components
for each row execute function inventory.reject_immutable_mutation();

alter table operations.marketplace_normalization_events enable row level security;
alter table operations.marketplace_source_lines enable row level security;
alter table operations.marketplace_source_line_components enable row level security;

create policy marketplace_normalization_events_read_current_org
on operations.marketplace_normalization_events
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy marketplace_source_lines_read_current_org
on operations.marketplace_source_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy marketplace_source_line_components_read_current_org
on operations.marketplace_source_line_components
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on operations.marketplace_normalization_events,
              operations.marketplace_source_lines,
              operations.marketplace_source_line_components
from public, anon, authenticated;

grant select on operations.marketplace_normalization_events,
                operations.marketplace_source_lines,
                operations.marketplace_source_line_components
to authenticated, service_role;

create or replace function catalog.protect_used_bundle_recipe()
returns trigger
language plpgsql
set search_path = pg_catalog, operations
as $$
begin
  if tg_op = 'DELETE' then
    if exists (
      select 1
      from operations.marketplace_source_lines source_line
      where source_line.bundle_recipe_id = old.id
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_BUNDLE_RECIPE_IN_USE';
    end if;

    return old;
  end if;

  if new is not distinct from old then
    return new;
  end if;

  if exists (
    select 1
    from operations.marketplace_source_lines source_line
    where source_line.bundle_recipe_id = old.id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_RECIPE_IN_USE';
  end if;

  return new;
end;
$$;

create trigger trg_bundle_recipes_protect_used
before update or delete
on catalog.bundle_recipes
for each row execute function catalog.protect_used_bundle_recipe();

create or replace function catalog.protect_used_bundle_component()
returns trigger
language plpgsql
set search_path = pg_catalog, operations
as $$
declare
  v_recipe_id uuid;
begin
  v_recipe_id := case
    when tg_op = 'DELETE' then old.bundle_recipe_id
    else new.bundle_recipe_id
  end;

  if tg_op = 'UPDATE' and new is not distinct from old then
    return new;
  end if;

  if exists (
    select 1
    from operations.marketplace_source_lines source_line
    where source_line.bundle_recipe_id = v_recipe_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_RECIPE_IN_USE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create trigger trg_bundle_components_protect_used
before insert or update or delete
on catalog.bundle_components
for each row execute function catalog.protect_used_bundle_component();

create or replace function operations.resolve_marketplace_listing_expansion(
  p_organization_id uuid,
  p_channel_code text,
  p_external_listing_code text,
  p_listing_quantity bigint,
  p_occurred_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, catalog, operations, extensions
as $$
declare
  v_channel_code text;
  v_external_listing_code text;
  v_channel_id uuid;
  v_listing catalog.marketplace_listings%rowtype;
  v_single_version catalog.marketplace_single_listing_versions%rowtype;
  v_bundle_recipe catalog.bundle_recipes%rowtype;
  v_match_count bigint;
  v_component_count bigint;
  v_components jsonb;
  v_total_numeric numeric;
  v_fingerprint text;
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
      )
    for share;

    select jsonb_build_array(
      jsonb_build_object(
        'componentNo', 1,
        'recipeComponentId', null,
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
      'channelId', v_channel_id,
      'channelCode', v_channel_code,
      'externalListingCode', v_listing.external_listing_code,
      'listingName', v_listing.display_name,
      'listingType', v_listing.listing_type_code,
      'listingQuantity', p_listing_quantity,
      'mappingVersion', v_single_version.version,
      'singleListingVersionId', v_single_version.id,
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
    )
  for share;

  if exists (
    select 1
    from catalog.bundle_components component
    left join catalog.products product
      on product.id = component.product_id
     and product.organization_id = p_organization_id
    where component.bundle_recipe_id = v_bundle_recipe.id
      and (
        product.id is null
        or not product.is_active
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENT_INVALID';
  end if;

  if exists (
    select 1
    from catalog.bundle_components component
    where component.bundle_recipe_id = v_bundle_recipe.id
      and component.component_qty::numeric
            * p_listing_quantity::numeric
          > 9223372036854775807::numeric
  ) then
    raise exception using
      errcode = '22003',
      message = 'MARKETPLACE_BUNDLE_EXPANSION_OVERFLOW';
  end if;

  select
    jsonb_agg(
      jsonb_build_object(
        'componentNo', component.line_no,
        'recipeComponentId', component.id,
        'productId', product.id,
        'productSku', product.sku,
        'productName', product.name,
        'unitQuantityPerListing', component.component_qty,
        'listingQuantity', p_listing_quantity,
        'expandedQuantity',
          (
            component.component_qty::numeric
              * p_listing_quantity::numeric
          )::bigint
      )
      order by component.line_no, product.sku, product.id
    ),
    count(*),
    sum(
      component.component_qty::numeric
        * p_listing_quantity::numeric
    )
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
    'channelId', v_channel_id,
    'channelCode', v_channel_code,
    'externalListingCode', v_listing.external_listing_code,
    'listingName', v_listing.display_name,
    'listingType', v_listing.listing_type_code,
    'listingQuantity', p_listing_quantity,
    'mappingVersion', v_bundle_recipe.version,
    'singleListingVersionId', null,
    'bundleRecipeId', v_bundle_recipe.id,
    'bundleRecipeVersion', v_bundle_recipe.version,
    'mappingFingerprint', v_fingerprint,
    'totalUnitQuantity', v_total_numeric::bigint,
    'components', v_components,
    'stockEffect', 'NONE'
  );
end;
$$;

revoke all on function operations.resolve_marketplace_listing_expansion(
  uuid,
  text,
  text,
  bigint,
  timestamptz
) from public, anon, authenticated;

create or replace function api.preview_marketplace_listing_expansion(
  p_organization_id uuid,
  p_channel_code text,
  p_external_listing_code text,
  p_listing_quantity bigint,
  p_occurred_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, operations
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text := coalesce(
    auth.jwt() ->> 'role',
    current_setting('request.jwt.claim.role', true)
  );
begin
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

  return operations.resolve_marketplace_listing_expansion(
    p_organization_id,
    p_channel_code,
    p_external_listing_code,
    p_listing_quantity,
    p_occurred_at
  );
end;
$$;

create or replace function api.reserve_marketplace_listing_event(
  p_organization_id uuid,
  p_idempotency_key text,
  p_channel_code text,
  p_event_ref text,
  p_order_ref text,
  p_source_status text,
  p_occurred_at timestamptz,
  p_received_at timestamptz,
  p_lines jsonb,
  p_note text default null,
  p_raw_payload jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb,
  p_schema_version integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations,
  api,
  extensions
as $$
declare
  v_scope constant text := 'RESERVE_MARKETPLACE_LISTING_EVENT';
  v_idempotency_key text;
  v_channel_code text;
  v_event_ref text;
  v_order_ref text;
  v_source_status text;
  v_note text;
  v_raw_payload jsonb;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_command_id uuid := gen_random_uuid();
  v_channel_id uuid;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text := coalesce(
    auth.jwt() ->> 'role',
    current_setting('request.jwt.claim.role', true)
  );
  v_recorded_at timestamptz := clock_timestamp();
  v_raw_payload_hash text;
  v_inner_idempotency_key text;
  v_source_line record;
  v_expansion jsonb;
  v_component jsonb;
  v_component_no integer;
  v_canonical_ref text;
  v_canonical_lines jsonb := '[]'::jsonb;
  v_source_snapshots jsonb := '[]'::jsonb;
  v_canonical_line_count integer := 0;
  v_total_unit_quantity numeric := 0;
  v_domain_result jsonb;
  v_event_id uuid;
  v_order_id uuid;
  v_normalization_event_id uuid := gen_random_uuid();
  v_source_line_id uuid;
  v_order_item_id uuid;
  v_event_line_id uuid;
  v_persisted_lines jsonb := '[]'::jsonb;
  v_persisted_components jsonb;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  v_channel_code := upper(btrim(coalesce(p_channel_code, '')));
  v_event_ref := btrim(coalesce(p_event_ref, ''));
  v_order_ref := btrim(coalesce(p_order_ref, ''));
  v_source_status := upper(btrim(coalesce(p_source_status, '')));
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  v_raw_payload := coalesce(p_raw_payload, '{}'::jsonb);
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_idempotency_key = '' then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  if length(v_idempotency_key) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  if v_channel_code = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CHANNEL_REQUIRED';
  end if;

  if v_event_ref = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_EVENT_REF_REQUIRED';
  end if;

  if length(v_event_ref) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_EVENT_REF_TOO_LONG';
  end if;

  if v_order_ref = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_ORDER_REF_REQUIRED';
  end if;

  if length(v_order_ref) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_ORDER_REF_TOO_LONG';
  end if;

  if v_source_status = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_STATUS_REQUIRED';
  end if;

  if length(v_source_status) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_STATUS_TOO_LONG';
  end if;

  if p_occurred_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_OCCURRED_AT_REQUIRED';
  end if;

  if p_received_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_RECEIVED_AT_REQUIRED';
  end if;

  if p_received_at < p_occurred_at then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_RECEIVED_BEFORE_OCCURRED';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_LINES_REQUIRED';
  end if;

  if jsonb_array_length(p_lines) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_LINES_LIMIT_EXCEEDED';
  end if;

  if jsonb_typeof(v_raw_payload) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_RAW_PAYLOAD_MUST_BE_OBJECT';
  end if;

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_METADATA_MUST_BE_OBJECT';
  end if;

  if p_schema_version is null or p_schema_version <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SCHEMA_VERSION_INVALID';
  end if;

  if v_note is not null and length(v_note) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_NOTE_TOO_LONG';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 90
       or jsonb_typeof(item.value -> 'externalListingCode') is distinct from 'string'
       or btrim(item.value ->> 'externalListingCode') = ''
       or length(btrim(item.value ->> 'externalListingCode')) > 200
       or jsonb_typeof(item.value -> 'listingQuantity') is distinct from 'number'
       or (item.value ->> 'listingQuantity') !~ '^[1-9][0-9]{0,8}$'
       or (
         item.value ? 'sourceTitle'
         and (
           jsonb_typeof(item.value -> 'sourceTitle') is distinct from 'string'
           or btrim(item.value ->> 'sourceTitle') = ''
           or length(btrim(item.value ->> 'sourceTitle')) > 300
         )
       )
       or (
         item.value ? 'sourceSku'
         and (
           jsonb_typeof(item.value -> 'sourceSku') is distinct from 'string'
           or btrim(item.value ->> 'sourceSku') = ''
           or length(btrim(item.value ->> 'sourceSku')) > 200
         )
       )
       or (
         item.value ? 'sourceStatus'
         and (
           jsonb_typeof(item.value -> 'sourceStatus') is distinct from 'string'
           or btrim(item.value ->> 'sourceStatus') = ''
           or length(btrim(item.value ->> 'sourceStatus')) > 100
         )
       )
       or (
         item.value ? 'rawLinePayload'
         and jsonb_typeof(item.value -> 'rawLinePayload') is distinct from 'object'
       )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_DUPLICATE_SOURCE_LINE';
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

    v_process_name := null;
  else
    v_process_name := 'api.reserve_marketplace_listing_event';
  end if;

  if not exists (
    select 1
    from app.organizations organization
    where organization.id = p_organization_id
      and organization.is_active
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_NOT_FOUND';
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

  v_raw_payload_hash := encode(
    extensions.digest(
      convert_to(v_raw_payload::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'channelCode', v_channel_code,
          'eventRef', v_event_ref,
          'orderRef', v_order_ref,
          'sourceStatus', v_source_status,
          'occurredAt', p_occurred_at,
          'receivedAt', p_received_at,
          'lines', p_lines,
          'note', v_note,
          'rawPayload', v_raw_payload,
          'metadata', v_metadata,
          'schemaVersion', p_schema_version
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
        || ':'
        || v_scope
        || ':'
        || v_idempotency_key,
      0::bigint
    )
  );

  select command.*
  into v_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id
    and command.scope = v_scope
    and command.key = v_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> v_request_hash then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_KEY_REUSED';
    end if;

    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot;
    end if;

    if v_existing.status_code = 'STARTED' then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  insert into inventory.idempotency_commands (
    id,
    organization_id,
    scope,
    key,
    request_hash,
    status_code,
    started_at,
    response_snapshot
  ) values (
    v_command_id,
    p_organization_id,
    v_scope,
    v_idempotency_key,
    v_request_hash,
    'STARTED',
    v_recorded_at,
    '{}'::jsonb
  );

  for v_source_line in
    select
      item.ordinality::integer as line_no,
      btrim(item.value ->> 'sourceLineRef') as source_line_ref,
      btrim(item.value ->> 'externalListingCode') as external_listing_code,
      (item.value ->> 'listingQuantity')::bigint as listing_quantity,
      nullif(btrim(coalesce(item.value ->> 'sourceTitle', '')), '') as source_title,
      nullif(btrim(coalesce(item.value ->> 'sourceSku', '')), '') as source_sku,
      upper(
        coalesce(
          nullif(btrim(coalesce(item.value ->> 'sourceStatus', '')), ''),
          v_source_status
        )
      ) as source_status,
      coalesce(item.value -> 'rawLinePayload', '{}'::jsonb) as raw_line_payload
    from jsonb_array_elements(p_lines)
      with ordinality item(value, ordinality)
    order by item.ordinality
  loop
    v_expansion := operations.resolve_marketplace_listing_expansion(
      p_organization_id,
      v_channel_code,
      v_source_line.external_listing_code,
      v_source_line.listing_quantity,
      p_occurred_at
    );

    v_persisted_components := '[]'::jsonb;

    for v_component in
      select component.value
      from jsonb_array_elements(v_expansion -> 'components')
        component(value)
      order by (component.value ->> 'componentNo')::integer
    loop
      v_component_no :=
        (v_component ->> 'componentNo')::integer;
      v_canonical_ref :=
        v_source_line.source_line_ref
          || '#C'
          || lpad(v_component_no::text, 3, '0');

      v_canonical_line_count := v_canonical_line_count + 1;

      if v_canonical_line_count > 200 then
        raise exception using
          errcode = 'P0001',
          message = 'MARKETPLACE_CANONICAL_LINES_LIMIT_EXCEEDED';
      end if;

      v_total_unit_quantity :=
        v_total_unit_quantity
        + (v_component ->> 'expandedQuantity')::numeric;

      if v_total_unit_quantity > 9223372036854775807::numeric then
        raise exception using
          errcode = '22003',
          message = 'MARKETPLACE_CANONICAL_QUANTITY_OVERFLOW';
      end if;

      v_canonical_lines :=
        v_canonical_lines
        || jsonb_build_array(
          jsonb_build_object(
            'productId', v_component ->> 'productId',
            'quantity',
              (v_component ->> 'expandedQuantity')::bigint,
            'sourceLineRef', v_canonical_ref
          )
        );

      v_persisted_components :=
        v_persisted_components
        || jsonb_build_array(
          v_component
          || jsonb_build_object(
            'canonicalSourceLineRef', v_canonical_ref
          )
        );
    end loop;

    v_source_snapshots :=
      v_source_snapshots
      || jsonb_build_array(
        jsonb_build_object(
          'lineNo', v_source_line.line_no,
          'sourceLineRef', v_source_line.source_line_ref,
          'externalListingCode',
            v_source_line.external_listing_code,
          'listingQuantity', v_source_line.listing_quantity,
          'sourceTitle', v_source_line.source_title,
          'sourceSku', v_source_line.source_sku,
          'sourceStatus', v_source_line.source_status,
          'rawLinePayload', v_source_line.raw_line_payload,
          'rawLineHash',
            encode(
              extensions.digest(
                convert_to(
                  v_source_line.raw_line_payload::text,
                  'UTF8'
                ),
                'sha256'
              ),
              'hex'
            ),
          'expansion',
            v_expansion
            || jsonb_build_object(
              'components',
              v_persisted_components
            )
        )
      );
  end loop;

  v_inner_idempotency_key :=
    'normalized-reserve:'
    || encode(
      extensions.digest(
        convert_to(
          p_organization_id::text
            || ':'
            || v_scope
            || ':'
            || v_idempotency_key,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );

  v_domain_result := api.apply_marketplace_event(
    p_organization_id,
    v_inner_idempotency_key,
    v_channel_code,
    'RESERVE',
    v_event_ref,
    v_order_ref,
    p_occurred_at,
    v_canonical_lines,
    v_note,
    v_metadata
      || jsonb_build_object(
        'adapterContract', 'MARKETPLACE_LISTING_EVENT_V1',
        'sourceStatus', v_source_status,
        'receivedAt', p_received_at,
        'rawPayloadHash', v_raw_payload_hash,
        'normalizationSchemaVersion', p_schema_version
      )
  );

  v_event_id := (v_domain_result ->> 'eventId')::uuid;
  v_order_id := (v_domain_result ->> 'orderId')::uuid;

  insert into operations.marketplace_normalization_events (
    id,
    organization_id,
    marketplace_event_id,
    order_id,
    channel_id,
    external_event_ref_snapshot,
    external_order_ref_snapshot,
    source_status_snapshot,
    occurred_at,
    received_at,
    raw_payload,
    raw_payload_hash,
    normalization_schema_version,
    idempotency_command_id,
    actor_user_id,
    process_name,
    metadata,
    created_at
  ) values (
    v_normalization_event_id,
    p_organization_id,
    v_event_id,
    v_order_id,
    v_channel_id,
    v_event_ref,
    v_order_ref,
    v_source_status,
    p_occurred_at,
    p_received_at,
    v_raw_payload,
    v_raw_payload_hash,
    p_schema_version,
    v_command_id,
    v_actor_user_id,
    v_process_name,
    v_metadata,
    v_recorded_at
  );

  for v_source_line in
    select source.value
    from jsonb_array_elements(v_source_snapshots)
      source(value)
    order by (source.value ->> 'lineNo')::integer
  loop
    v_source_line_id := gen_random_uuid();

    insert into operations.marketplace_source_lines (
      id,
      organization_id,
      normalization_event_id,
      order_id,
      line_no,
      source_line_ref,
      listing_id,
      external_listing_code_snapshot,
      listing_name_snapshot,
      listing_type_code_snapshot,
      listing_quantity,
      mapping_version,
      single_listing_version_id,
      bundle_recipe_id,
      mapping_fingerprint,
      source_title_snapshot,
      source_sku_snapshot,
      source_status_snapshot,
      raw_line_payload,
      raw_line_hash,
      created_at
    ) values (
      v_source_line_id,
      p_organization_id,
      v_normalization_event_id,
      v_order_id,
      (v_source_line.value ->> 'lineNo')::integer,
      v_source_line.value ->> 'sourceLineRef',
      (
        v_source_line.value
          -> 'expansion'
          ->> 'listingId'
      )::uuid,
      v_source_line.value ->> 'externalListingCode',
      v_source_line.value
        -> 'expansion'
        ->> 'listingName',
      v_source_line.value
        -> 'expansion'
        ->> 'listingType',
      (v_source_line.value ->> 'listingQuantity')::bigint,
      (
        v_source_line.value
          -> 'expansion'
          ->> 'mappingVersion'
      )::integer,
      nullif(
        v_source_line.value
          -> 'expansion'
          ->> 'singleListingVersionId',
        ''
      )::uuid,
      nullif(
        v_source_line.value
          -> 'expansion'
          ->> 'bundleRecipeId',
        ''
      )::uuid,
      v_source_line.value
        -> 'expansion'
        ->> 'mappingFingerprint',
      nullif(v_source_line.value ->> 'sourceTitle', ''),
      nullif(v_source_line.value ->> 'sourceSku', ''),
      v_source_line.value ->> 'sourceStatus',
      v_source_line.value -> 'rawLinePayload',
      v_source_line.value ->> 'rawLineHash',
      v_recorded_at
    );

    v_persisted_components := '[]'::jsonb;

    for v_component in
      select component.value
      from jsonb_array_elements(
        v_source_line.value
          -> 'expansion'
          -> 'components'
      ) component(value)
      order by (component.value ->> 'componentNo')::integer
    loop
      select item.id
      into strict v_order_item_id
      from operations.marketplace_order_items item
      where item.organization_id = p_organization_id
        and item.order_id = v_order_id
        and item.external_item_ref =
          v_component ->> 'canonicalSourceLineRef'
        and item.product_id =
          (v_component ->> 'productId')::uuid;

      select event_line.id
      into strict v_event_line_id
      from operations.marketplace_event_lines event_line
      where event_line.organization_id = p_organization_id
        and event_line.event_id = v_event_id
        and event_line.order_item_id = v_order_item_id
        and event_line.source_line_ref =
          v_component ->> 'canonicalSourceLineRef';

      insert into operations.marketplace_source_line_components (
        organization_id,
        source_line_id,
        component_no,
        recipe_component_id,
        order_item_id,
        reserve_event_line_id,
        product_id,
        canonical_source_line_ref,
        product_sku_snapshot,
        product_name_snapshot,
        unit_quantity_per_listing,
        listing_quantity,
        expanded_quantity,
        mapping_fingerprint,
        created_at
      ) values (
        p_organization_id,
        v_source_line_id,
        (v_component ->> 'componentNo')::integer,
        nullif(
          v_component ->> 'recipeComponentId',
          ''
        )::uuid,
        v_order_item_id,
        v_event_line_id,
        (v_component ->> 'productId')::uuid,
        v_component ->> 'canonicalSourceLineRef',
        v_component ->> 'productSku',
        v_component ->> 'productName',
        (v_component ->> 'unitQuantityPerListing')::bigint,
        (v_component ->> 'listingQuantity')::bigint,
        (v_component ->> 'expandedQuantity')::bigint,
        v_source_line.value
          -> 'expansion'
          ->> 'mappingFingerprint',
        v_recorded_at
      );

      v_persisted_components :=
        v_persisted_components
        || jsonb_build_array(
          jsonb_build_object(
            'componentNo',
              (v_component ->> 'componentNo')::integer,
            'orderItemId', v_order_item_id,
            'eventLineId', v_event_line_id,
            'productId', v_component ->> 'productId',
            'productSku', v_component ->> 'productSku',
            'unitQuantityPerListing',
              (v_component ->> 'unitQuantityPerListing')::bigint,
            'listingQuantity',
              (v_component ->> 'listingQuantity')::bigint,
            'expandedQuantity',
              (v_component ->> 'expandedQuantity')::bigint,
            'canonicalSourceLineRef',
              v_component ->> 'canonicalSourceLineRef'
          )
        );
    end loop;

    v_persisted_lines :=
      v_persisted_lines
      || jsonb_build_array(
        jsonb_build_object(
          'sourceLineId', v_source_line_id,
          'lineNo',
            (v_source_line.value ->> 'lineNo')::integer,
          'sourceLineRef',
            v_source_line.value ->> 'sourceLineRef',
          'listingId',
            v_source_line.value
              -> 'expansion'
              ->> 'listingId',
          'externalListingCode',
            v_source_line.value ->> 'externalListingCode',
          'listingName',
            v_source_line.value
              -> 'expansion'
              ->> 'listingName',
          'listingType',
            v_source_line.value
              -> 'expansion'
              ->> 'listingType',
          'listingQuantity',
            (v_source_line.value ->> 'listingQuantity')::bigint,
          'mappingVersion',
            (
              v_source_line.value
                -> 'expansion'
                ->> 'mappingVersion'
            )::integer,
          'mappingFingerprint',
            v_source_line.value
              -> 'expansion'
              ->> 'mappingFingerprint',
          'components', v_persisted_components
        )
      );
  end loop;

  v_response := jsonb_build_object(
    'status', 'APPLIED',
    'normalizationEventId', v_normalization_event_id,
    'eventId', v_event_id,
    'eventRef', v_event_ref,
    'orderId', v_order_id,
    'orderRef', v_order_ref,
    'channelCode', v_channel_code,
    'sourceStatus', v_source_status,
    'sourceLineCount', jsonb_array_length(v_source_snapshots),
    'canonicalLineCount', v_canonical_line_count,
    'totalUnitQuantity', v_total_unit_quantity::bigint,
    'occurredAt', p_occurred_at,
    'receivedAt', p_received_at,
    'rawPayloadHash', v_raw_payload_hash,
    'normalizationSchemaVersion', p_schema_version,
    'sourceLines', v_persisted_lines,
    'reservation', v_domain_result
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    result_transaction_id = null,
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

revoke all on function api.reserve_marketplace_listing_event(
  uuid,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  jsonb,
  text,
  jsonb,
  jsonb,
  integer
) from public, anon;

grant execute on function api.reserve_marketplace_listing_event(
  uuid,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  jsonb,
  text,
  jsonb,
  jsonb,
  integer
) to authenticated, service_role;

create or replace view api.marketplace_listing_normalizations
with (security_invoker = true)
as
select
  normalization.id as normalization_event_id,
  normalization.organization_id,
  normalization.marketplace_event_id,
  normalization.order_id,
  channel.code as channel_code,
  normalization.external_event_ref_snapshot,
  normalization.external_order_ref_snapshot,
  normalization.source_status_snapshot as event_source_status,
  normalization.occurred_at,
  normalization.received_at,
  normalization.raw_payload_hash,
  normalization.normalization_schema_version,
  normalization.actor_user_id,
  normalization.process_name,
  normalization.metadata,
  source_line.id as source_line_id,
  source_line.line_no as source_line_no,
  source_line.source_line_ref,
  source_line.listing_id,
  source_line.external_listing_code_snapshot,
  source_line.listing_name_snapshot,
  source_line.listing_type_code_snapshot,
  source_line.listing_quantity,
  source_line.mapping_version,
  source_line.single_listing_version_id,
  source_line.bundle_recipe_id,
  source_line.mapping_fingerprint,
  source_line.source_title_snapshot,
  source_line.source_sku_snapshot,
  source_line.source_status_snapshot as line_source_status,
  source_line.raw_line_hash,
  component.id as source_component_id,
  component.component_no,
  component.recipe_component_id,
  component.order_item_id,
  component.reserve_event_line_id,
  component.product_id,
  component.canonical_source_line_ref,
  component.product_sku_snapshot,
  component.product_name_snapshot,
  component.unit_quantity_per_listing,
  component.expanded_quantity,
  item.reservation_id,
  reservation.reserved_qty,
  reservation.consumed_qty,
  reservation.released_qty,
  reservation.status_code as reservation_status_code,
  normalization.created_at
from operations.marketplace_normalization_events normalization
join catalog.channels channel
  on channel.id = normalization.channel_id
join operations.marketplace_source_lines source_line
  on source_line.organization_id = normalization.organization_id
 and source_line.normalization_event_id = normalization.id
join operations.marketplace_source_line_components component
  on component.organization_id = source_line.organization_id
 and component.source_line_id = source_line.id
join operations.marketplace_order_items item
  on item.organization_id = component.organization_id
 and item.id = component.order_item_id
join inventory.stock_reservations reservation
  on reservation.organization_id = item.organization_id
 and reservation.id = item.reservation_id;

revoke all on api.marketplace_listing_normalizations
from public, anon;

grant select on api.marketplace_listing_normalizations
to authenticated, service_role;

commit;
