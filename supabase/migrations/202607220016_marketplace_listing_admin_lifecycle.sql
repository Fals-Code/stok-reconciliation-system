begin;

alter table catalog.bundle_recipes
  add column status_code text,
  add column recipe_fingerprint text,
  add column activated_at timestamptz null,
  add column activated_by uuid null references auth.users(id) on delete set null,
  add column retired_at timestamptz null,
  add column retired_by uuid null references auth.users(id) on delete set null,
  add column updated_at timestamptz,
  add column updated_by uuid null references auth.users(id) on delete set null,
  add column row_version bigint,
  add column note text null,
  add column metadata jsonb,
  add column schema_version integer;

alter table catalog.marketplace_single_listing_versions
  add column note text null,
  add column metadata jsonb not null default '{}'::jsonb;

create or replace function catalog.bundle_recipe_fingerprint(
  p_bundle_recipe_id uuid
)
returns text
language plpgsql
stable
set search_path = pg_catalog, catalog, extensions
as $$
declare
  v_recipe catalog.bundle_recipes%rowtype;
  v_components jsonb;
begin
  select recipe.*
  into v_recipe
  from catalog.bundle_recipes recipe
  where recipe.id = p_bundle_recipe_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_RECIPE_NOT_FOUND';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'lineNo', component.line_no,
        'productId', component.product_id,
        'componentQuantity', component.component_qty
      )
      order by component.line_no, component.product_id
    ),
    '[]'::jsonb
  )
  into v_components
  from catalog.bundle_components component
  where component.bundle_recipe_id = p_bundle_recipe_id;

  return encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'recipeId', v_recipe.id,
          'version', v_recipe.version,
          'components', v_components,
          'schemaVersion', coalesce(v_recipe.schema_version, 1)
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
end;
$$;

update catalog.bundle_recipes recipe
set
  status_code = case
    when recipe.is_active then 'ACTIVE'
    else 'RETIRED'
  end,
  activated_at = recipe.created_at,
  activated_by = recipe.created_by,
  retired_at = case
    when recipe.is_active then null
    else coalesce(
      recipe.effective_to,
      greatest(
        recipe.effective_from + interval '1 microsecond',
        recipe.created_at
      )
    )
  end,
  retired_by = case
    when recipe.is_active then null
    else recipe.created_by
  end,
  effective_to = case
    when recipe.is_active then recipe.effective_to
    else coalesce(
      recipe.effective_to,
      greatest(
        recipe.effective_from + interval '1 microsecond',
        recipe.created_at
      )
    )
  end,
  updated_at = recipe.created_at,
  updated_by = recipe.created_by,
  row_version = 1,
  metadata = '{}'::jsonb,
  schema_version = 1;

update catalog.bundle_recipes recipe
set recipe_fingerprint =
  catalog.bundle_recipe_fingerprint(recipe.id);

alter table catalog.bundle_recipes
  alter column status_code set default 'ACTIVE',
  alter column status_code set not null,
  alter column recipe_fingerprint set default repeat('0', 64),
  alter column recipe_fingerprint set not null,
  alter column updated_at set default clock_timestamp(),
  alter column updated_at set not null,
  alter column row_version set default 1,
  alter column row_version set not null,
  alter column metadata set default '{}'::jsonb,
  alter column metadata set not null,
  alter column schema_version set default 1,
  alter column schema_version set not null;

alter table catalog.bundle_recipes
  add constraint ck_bundle_recipes_status
    check (status_code in ('DRAFT', 'ACTIVE', 'RETIRED')),
  add constraint ck_bundle_recipes_fingerprint
    check (recipe_fingerprint ~ '^[0-9a-f]{64}$'),
  add constraint ck_bundle_recipes_row_version_positive
    check (row_version > 0),
  add constraint ck_bundle_recipes_note_nonblank
    check (note is null or btrim(note) <> ''),
  add constraint ck_bundle_recipes_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  add constraint ck_bundle_recipes_schema_version_positive
    check (schema_version > 0),
  add constraint ck_bundle_recipes_lifecycle_shape
    check (
      (
        status_code = 'DRAFT'
        and not is_active
        and activated_at is null
        and activated_by is null
        and retired_at is null
        and retired_by is null
      )
      or (
        status_code = 'ACTIVE'
        and is_active
        and activated_at is not null
        and retired_at is null
        and retired_by is null
      )
      or (
        status_code = 'RETIRED'
        and is_active
        and activated_at is not null
        and effective_to is not null
        and retired_at is not null
      )
    );

alter table catalog.marketplace_single_listing_versions
  add constraint ck_marketplace_single_listing_versions_note_nonblank
    check (note is null or btrim(note) <> ''),
  add constraint ck_marketplace_single_listing_versions_metadata_object
    check (jsonb_typeof(metadata) = 'object');

create or replace function catalog.normalize_bundle_recipe_lifecycle()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog
as $$
begin
  new.external_listing_sku := btrim(new.external_listing_sku);
  new.external_listing_name := btrim(new.external_listing_name);
  new.note := nullif(btrim(coalesce(new.note, '')), '');
  new.metadata := coalesce(new.metadata, '{}'::jsonb);
  new.status_code := upper(btrim(coalesce(new.status_code, 'ACTIVE')));
  new.schema_version := coalesce(new.schema_version, 1);
  new.row_version := coalesce(new.row_version, 1);
  new.updated_at := coalesce(new.updated_at, new.created_at, clock_timestamp());

  if jsonb_typeof(new.metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_METADATA_MUST_BE_OBJECT';
  end if;

  if new.status_code = 'DRAFT' then
    new.is_active := false;
    new.activated_at := null;
    new.activated_by := null;
    new.retired_at := null;
    new.retired_by := null;
    new.recipe_fingerprint := repeat('0', 64);
  elsif new.status_code = 'ACTIVE' then
    new.is_active := true;
    new.activated_at := coalesce(
      new.activated_at,
      new.created_at,
      clock_timestamp()
    );
    new.retired_at := null;
    new.retired_by := null;
  elsif new.status_code = 'RETIRED' then
    new.is_active := true;

    if new.activated_at is null
       or new.retired_at is null
       or new.effective_to is null then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_BUNDLE_RECIPE_RETIREMENT_INVALID';
    end if;
  else
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_RECIPE_STATUS_INVALID';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_bundle_recipes_normalize_lifecycle
on catalog.bundle_recipes;

create trigger trg_bundle_recipes_normalize_lifecycle
before insert or update
on catalog.bundle_recipes
for each row execute function catalog.normalize_bundle_recipe_lifecycle();

drop trigger if exists trg_bundle_recipes_touch_mutable
on catalog.bundle_recipes;

create trigger trg_bundle_recipes_touch_mutable
before update
on catalog.bundle_recipes
for each row execute function app.touch_mutable_row();

create or replace function catalog.protect_marketplace_single_version_history()
returns trigger
language plpgsql
set search_path = pg_catalog, operations
as $$
declare
  v_used boolean;
begin
  select exists (
    select 1
    from operations.marketplace_source_lines source_line
    where source_line.single_listing_version_id = old.id
  )
  into v_used;

  if tg_op = 'DELETE' then
    if old.status_code = 'DRAFT' and not v_used then
      return old;
    end if;

    raise exception using
      errcode = 'P0001',
      message = case
        when v_used then 'MARKETPLACE_LISTING_VERSION_IN_USE'
        else 'MARKETPLACE_LISTING_VERSION_IMMUTABLE'
      end;
  end if;

  if new is not distinct from old then
    return new;
  end if;

  if new.organization_id is distinct from old.organization_id
     or new.listing_id is distinct from old.listing_id
     or new.version is distinct from old.version
     or new.created_at is distinct from old.created_at
     or new.created_by is distinct from old.created_by
     or new.schema_version is distinct from old.schema_version then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_VERSION_IDENTITY_IMMUTABLE';
  end if;

  if old.status_code = 'DRAFT'
     and new.status_code in ('DRAFT', 'ACTIVE') then
    return new;
  end if;

  if old.status_code = 'ACTIVE'
     and new.product_id is not distinct from old.product_id
     and new.effective_from is not distinct from old.effective_from
     and new.mapping_fingerprint is not distinct from old.mapping_fingerprint
     and new.activated_at is not distinct from old.activated_at
     and new.activated_by is not distinct from old.activated_by
     and new.note is not distinct from old.note
     and new.metadata is not distinct from old.metadata
     and (
       (
         new.status_code = 'ACTIVE'
         and old.effective_to is null
         and new.effective_to is not null
         and new.retired_at is null
         and new.retired_by is null
       )
       or (
         new.status_code = 'RETIRED'
         and new.effective_to is not null
         and new.retired_at is not null
       )
     ) then
    return new;
  end if;

  raise exception using
    errcode = 'P0001',
    message = case
      when v_used then 'MARKETPLACE_LISTING_VERSION_IN_USE'
      else 'MARKETPLACE_LISTING_VERSION_IMMUTABLE'
    end;
end;
$$;

create or replace function catalog.reject_marketplace_single_version_overlap()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog
as $$
begin
  if new.status_code in ('ACTIVE', 'RETIRED')
     and exists (
       select 1
       from catalog.marketplace_single_listing_versions existing
       where existing.organization_id = new.organization_id
         and existing.listing_id = new.listing_id
         and existing.id <> new.id
         and existing.status_code in ('ACTIVE', 'RETIRED')
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

create or replace function catalog.protect_used_bundle_recipe()
returns trigger
language plpgsql
set search_path = pg_catalog, operations
as $$
declare
  v_used boolean;
begin
  select exists (
    select 1
    from operations.marketplace_source_lines source_line
    where source_line.bundle_recipe_id = old.id
  )
  into v_used;

  if tg_op = 'DELETE' then
    if old.status_code = 'DRAFT' and not v_used then
      return old;
    end if;

    raise exception using
      errcode = 'P0001',
      message = case
        when v_used then 'MARKETPLACE_BUNDLE_RECIPE_IN_USE'
        else 'MARKETPLACE_BUNDLE_RECIPE_IMMUTABLE'
      end;
  end if;

  if new is not distinct from old then
    return new;
  end if;

  if new.organization_id is distinct from old.organization_id
     or new.channel_id is distinct from old.channel_id
     or new.external_listing_sku is distinct from old.external_listing_sku
     or new.version is distinct from old.version
     or new.created_at is distinct from old.created_at
     or new.created_by is distinct from old.created_by
     or new.schema_version is distinct from old.schema_version then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_RECIPE_IDENTITY_IMMUTABLE';
  end if;

  if old.status_code = 'DRAFT'
     and new.status_code in ('DRAFT', 'ACTIVE') then
    return new;
  end if;

  if old.status_code = 'ACTIVE'
     and new.external_listing_name
           is not distinct from old.external_listing_name
     and new.effective_from is not distinct from old.effective_from
     and new.recipe_fingerprint
           is not distinct from old.recipe_fingerprint
     and new.activated_at is not distinct from old.activated_at
     and new.activated_by is not distinct from old.activated_by
     and new.note is not distinct from old.note
     and new.metadata is not distinct from old.metadata
     and (
       (
         new.status_code = 'ACTIVE'
         and old.effective_to is null
         and new.effective_to is not null
         and new.retired_at is null
         and new.retired_by is null
       )
       or (
         new.status_code = 'RETIRED'
         and new.effective_to is not null
         and new.retired_at is not null
       )
     ) then
    return new;
  end if;

  raise exception using
    errcode = 'P0001',
    message = case
      when v_used then 'MARKETPLACE_BUNDLE_RECIPE_IN_USE'
      else 'MARKETPLACE_BUNDLE_RECIPE_IMMUTABLE'
    end;
end;
$$;

create or replace function catalog.protect_used_bundle_component()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog, operations
as $$
declare
  v_recipe_id uuid;
  v_status_code text;
  v_fingerprint text;
  v_used boolean;
begin
  v_recipe_id := case
    when tg_op = 'DELETE' then old.bundle_recipe_id
    else new.bundle_recipe_id
  end;

  if tg_op = 'UPDATE' and new is not distinct from old then
    return new;
  end if;

  select recipe.status_code, recipe.recipe_fingerprint
  into v_status_code, v_fingerprint
  from catalog.bundle_recipes recipe
  where recipe.id = v_recipe_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_RECIPE_NOT_FOUND';
  end if;

  select exists (
    select 1
    from operations.marketplace_source_lines source_line
    where source_line.bundle_recipe_id = v_recipe_id
  )
  into v_used;

  if v_used then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_RECIPE_IN_USE';
  end if;

  if v_status_code = 'DRAFT' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if session_user in ('postgres', 'supabase_admin')
     and v_status_code = 'ACTIVE'
     and v_fingerprint = repeat('0', 64) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'MARKETPLACE_BUNDLE_RECIPE_NOT_DRAFT';
end;
$$;

create or replace function catalog.reject_bundle_recipe_overlap()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog
as $$
begin
  if new.status_code in ('ACTIVE', 'RETIRED')
     and exists (
       select 1
       from catalog.bundle_recipes existing
       where existing.organization_id = new.organization_id
         and existing.channel_id = new.channel_id
         and existing.external_listing_sku =
               new.external_listing_sku
         and existing.id <> new.id
         and existing.status_code in ('ACTIVE', 'RETIRED')
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
      message = 'MARKETPLACE_BUNDLE_RECIPE_OVERLAP';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_bundle_recipes_reject_overlap
on catalog.bundle_recipes;

create trigger trg_bundle_recipes_reject_overlap
before insert or update
on catalog.bundle_recipes
for each row execute function catalog.reject_bundle_recipe_overlap();

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
      updated_by = coalesce(new.updated_by, new.created_by)
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
    coalesce(new.updated_by, new.created_by)
  );

  return new;
end;
$$;

create or replace function operations.validate_marketplace_admin_components(
  p_organization_id uuid,
  p_components jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, catalog
as $$
declare
  v_components jsonb := coalesce(p_components, '[]'::jsonb);
  v_normalized jsonb;
begin
  if jsonb_typeof(v_components) is distinct from 'array' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENTS_MUST_BE_ARRAY';
  end if;

  if jsonb_array_length(v_components) = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENTS_REQUIRED';
  end if;

  if jsonb_array_length(v_components) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENTS_LIMIT_EXCEEDED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_components) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'productId')
            is distinct from 'string'
       or (item.value ->> 'productId')
            !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'quantity')
            is distinct from 'number'
       or (item.value ->> 'quantity') !~ '^[1-9][0-9]{0,8}$'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENT_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_components) item(value)
    group by (item.value ->> 'productId')::uuid
    having count(*) > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENT_DUPLICATE_PRODUCT';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_components) item(value)
    left join catalog.products product
      on product.organization_id = p_organization_id
     and product.id = (item.value ->> 'productId')::uuid
    where product.id is null
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENT_PRODUCT_NOT_FOUND';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'lineNo', item.ordinality::integer,
      'productId', (item.value ->> 'productId')::uuid,
      'quantity', (item.value ->> 'quantity')::bigint
    )
    order by item.ordinality
  )
  into v_normalized
  from jsonb_array_elements(v_components)
    with ordinality item(value, ordinality);

  return v_normalized;
end;
$$;

revoke all on function operations.validate_marketplace_admin_components(
  uuid,
  jsonb
) from public, anon, authenticated, service_role;

create or replace function operations.preview_marketplace_listing_activation_core(
  p_organization_id uuid,
  p_listing_id uuid,
  p_version_id uuid,
  p_lock_basis boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  catalog,
  operations,
  extensions
as $$
declare
  v_listing catalog.marketplace_listings%rowtype;
  v_listing_type text;
  v_status_code text;
  v_version integer;
  v_effective_from timestamptz;
  v_row_version bigint;
  v_product_id uuid;
  v_product_sku text;
  v_product_name text;
  v_product_active boolean;
  v_recipe_fingerprint text;
  v_components jsonb := '[]'::jsonb;
  v_component_count bigint := 0;
  v_inactive_component_count bigint := 0;
  v_current_version_id uuid;
  v_current_version integer;
  v_current_row_version bigint;
  v_current_effective_from timestamptz;
  v_blockers jsonb := '[]'::jsonb;
  v_basis jsonb;
  v_basis_hash text;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_listing_id is null or p_version_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_VERSION_REQUIRED';
  end if;

  if p_lock_basis then
    select listing.*
    into v_listing
    from catalog.marketplace_listings listing
    where listing.organization_id = p_organization_id
      and listing.id = p_listing_id
    for update;
  else
    select listing.*
    into v_listing
    from catalog.marketplace_listings listing
    where listing.organization_id = p_organization_id
      and listing.id = p_listing_id;
  end if;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_NOT_FOUND';
  end if;

  v_listing_type := v_listing.listing_type_code;

  if v_listing.status_code <> 'ACTIVE' then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'MARKETPLACE_LISTING_ARCHIVED',
        'scope', 'LISTING',
        'message', 'Listing marketplace sudah diarsipkan.'
      )
    );
  end if;

  if v_listing_type = 'SINGLE' then
    if p_lock_basis then
      select
        version.status_code,
        version.version,
        version.effective_from,
        version.row_version,
        version.product_id,
        product.sku,
        product.name,
        product.is_active,
        version.mapping_fingerprint
      into
        v_status_code,
        v_version,
        v_effective_from,
        v_row_version,
        v_product_id,
        v_product_sku,
        v_product_name,
        v_product_active,
        v_recipe_fingerprint
      from catalog.marketplace_single_listing_versions version
      join catalog.products product
        on product.organization_id = version.organization_id
       and product.id = version.product_id
      where version.organization_id = p_organization_id
        and version.listing_id = p_listing_id
        and version.id = p_version_id
      for update of version;
    else
      select
        version.status_code,
        version.version,
        version.effective_from,
        version.row_version,
        version.product_id,
        product.sku,
        product.name,
        product.is_active,
        version.mapping_fingerprint
      into
        v_status_code,
        v_version,
        v_effective_from,
        v_row_version,
        v_product_id,
        v_product_sku,
        v_product_name,
        v_product_active,
        v_recipe_fingerprint
      from catalog.marketplace_single_listing_versions version
      join catalog.products product
        on product.organization_id = version.organization_id
       and product.id = version.product_id
      where version.organization_id = p_organization_id
        and version.listing_id = p_listing_id
        and version.id = p_version_id;
    end if;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_VERSION_NOT_FOUND';
    end if;

    if v_status_code <> 'DRAFT' then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'MARKETPLACE_LISTING_VERSION_NOT_DRAFT',
          'scope', 'VERSION',
          'message', 'Versi mapping bukan draft.'
        )
      );
    end if;

    if not v_product_active then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'MARKETPLACE_LISTING_PRODUCT_INACTIVE',
          'scope', 'COMPONENT',
          'message', 'Produk mapping sedang tidak aktif.'
        )
      );
    end if;

    v_components := jsonb_build_array(
      jsonb_build_object(
        'lineNo', 1,
        'productId', v_product_id,
        'productSku', v_product_sku,
        'productName', v_product_name,
        'quantity', 1,
        'active', v_product_active
      )
    );
    v_component_count := 1;

    select
      existing.id,
      existing.version,
      existing.row_version,
      existing.effective_from
    into
      v_current_version_id,
      v_current_version,
      v_current_row_version,
      v_current_effective_from
    from catalog.marketplace_single_listing_versions existing
    where existing.organization_id = p_organization_id
      and existing.listing_id = p_listing_id
      and existing.id <> p_version_id
      and existing.status_code = 'ACTIVE'
      and existing.effective_to is null
    order by existing.version desc, existing.id
    limit 1
    for update;

    if v_current_version_id is not null
       and v_current_effective_from >= v_effective_from then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'MARKETPLACE_LISTING_ACTIVATION_TIME_STALE',
          'scope', 'VERSION',
          'message', 'Waktu efektif versi baru harus setelah versi aktif.'
        )
      );
    end if;

    if exists (
      select 1
      from catalog.marketplace_single_listing_versions existing
      where existing.organization_id = p_organization_id
        and existing.listing_id = p_listing_id
        and existing.id <> p_version_id
        and existing.id is distinct from v_current_version_id
        and existing.status_code in ('ACTIVE', 'RETIRED')
        and (
          existing.effective_to is null
          or existing.effective_to > v_effective_from
        )
    ) then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'MARKETPLACE_LISTING_VERSION_OVERLAP',
          'scope', 'VERSION',
          'message', 'Periode mapping bertumpang tindih.'
        )
      );
    end if;
  else
    if p_lock_basis then
      select
        recipe.status_code,
        recipe.version,
        recipe.effective_from,
        recipe.row_version,
        recipe.recipe_fingerprint
      into
        v_status_code,
        v_version,
        v_effective_from,
        v_row_version,
        v_recipe_fingerprint
      from catalog.bundle_recipes recipe
      where recipe.organization_id = p_organization_id
        and recipe.id = p_version_id
        and recipe.channel_id = v_listing.channel_id
        and recipe.external_listing_sku =
              v_listing.external_listing_code
      for update;
    else
      select
        recipe.status_code,
        recipe.version,
        recipe.effective_from,
        recipe.row_version,
        recipe.recipe_fingerprint
      into
        v_status_code,
        v_version,
        v_effective_from,
        v_row_version,
        v_recipe_fingerprint
      from catalog.bundle_recipes recipe
      where recipe.organization_id = p_organization_id
        and recipe.id = p_version_id
        and recipe.channel_id = v_listing.channel_id
        and recipe.external_listing_sku =
              v_listing.external_listing_code;
    end if;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_VERSION_NOT_FOUND';
    end if;

    if v_status_code <> 'DRAFT' then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'MARKETPLACE_LISTING_VERSION_NOT_DRAFT',
          'scope', 'VERSION',
          'message', 'Versi resep bukan draft.'
        )
      );
    end if;

    select
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'lineNo', component.line_no,
            'productId', product.id,
            'productSku', product.sku,
            'productName', product.name,
            'quantity', component.component_qty,
            'active', product.is_active
          )
          order by component.line_no, product.id
        ),
        '[]'::jsonb
      ),
      count(*),
      count(*) filter (where not product.is_active)
    into
      v_components,
      v_component_count,
      v_inactive_component_count
    from catalog.bundle_components component
    join catalog.products product
      on product.id = component.product_id
     and product.organization_id = p_organization_id
    where component.bundle_recipe_id = p_version_id;

    if v_component_count = 0 then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'MARKETPLACE_BUNDLE_COMPONENTS_REQUIRED',
          'scope', 'COMPONENT',
          'message', 'Resep bundle belum memiliki komponen.'
        )
      );
    end if;

    if v_inactive_component_count > 0 then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'MARKETPLACE_BUNDLE_COMPONENT_INACTIVE',
          'scope', 'COMPONENT',
          'message', 'Salah satu produk komponen tidak aktif.'
        )
      );
    end if;

    v_recipe_fingerprint :=
      catalog.bundle_recipe_fingerprint(p_version_id);

    select
      existing.id,
      existing.version,
      existing.row_version,
      existing.effective_from
    into
      v_current_version_id,
      v_current_version,
      v_current_row_version,
      v_current_effective_from
    from catalog.bundle_recipes existing
    where existing.organization_id = p_organization_id
      and existing.channel_id = v_listing.channel_id
      and existing.external_listing_sku =
            v_listing.external_listing_code
      and existing.id <> p_version_id
      and existing.status_code = 'ACTIVE'
      and existing.effective_to is null
    order by existing.version desc, existing.id
    limit 1
    for update;

    if v_current_version_id is not null
       and v_current_effective_from >= v_effective_from then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'MARKETPLACE_LISTING_ACTIVATION_TIME_STALE',
          'scope', 'VERSION',
          'message', 'Waktu efektif versi baru harus setelah versi aktif.'
        )
      );
    end if;

    if exists (
      select 1
      from catalog.bundle_recipes existing
      where existing.organization_id = p_organization_id
        and existing.channel_id = v_listing.channel_id
        and existing.external_listing_sku =
              v_listing.external_listing_code
        and existing.id <> p_version_id
        and existing.id is distinct from v_current_version_id
        and existing.status_code in ('ACTIVE', 'RETIRED')
        and (
          existing.effective_to is null
          or existing.effective_to > v_effective_from
        )
    ) then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'MARKETPLACE_BUNDLE_RECIPE_OVERLAP',
          'scope', 'VERSION',
          'message', 'Periode resep bertumpang tindih.'
        )
      );
    end if;
  end if;

  v_basis := jsonb_build_object(
    'organizationId', p_organization_id,
    'listingId', p_listing_id,
    'listingRowVersion', v_listing.row_version,
    'listingType', v_listing_type,
    'versionId', p_version_id,
    'version', v_version,
    'versionRowVersion', v_row_version,
    'effectiveFrom', v_effective_from,
    'mappingFingerprint', v_recipe_fingerprint,
    'components', v_components,
    'currentOpenVersionId', v_current_version_id,
    'currentOpenVersion', v_current_version,
    'currentOpenRowVersion', v_current_row_version,
    'currentOpenEffectiveFrom', v_current_effective_from,
    'schemaVersion', 1
  );

  v_basis_hash := encode(
    extensions.digest(
      convert_to(v_basis::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  return jsonb_build_object(
    'status',
      case
        when jsonb_array_length(v_blockers) = 0
          then 'PREVIEW_READY'
        else 'BLOCKED'
      end,
    'eligible', jsonb_array_length(v_blockers) = 0,
    'basisHash', v_basis_hash,
    'listingId', p_listing_id,
    'listingType', v_listing_type,
    'listingRowVersion', v_listing.row_version,
    'versionId', p_version_id,
    'version', v_version,
    'versionRowVersion', v_row_version,
    'effectiveFrom', v_effective_from,
    'mappingFingerprint', v_recipe_fingerprint,
    'componentCount', v_component_count,
    'components', v_components,
    'currentOpenVersionId', v_current_version_id,
    'currentOpenVersion', v_current_version,
    'currentOpenRowVersion', v_current_row_version,
    'blockers', v_blockers
  );
end;
$$;

revoke all on function
  operations.preview_marketplace_listing_activation_core(
    uuid,
    uuid,
    uuid,
    boolean
  )
from public, anon, authenticated, service_role;

create or replace function api.create_marketplace_listing_version_draft(
  p_organization_id uuid,
  p_idempotency_key text,
  p_channel_code text,
  p_external_listing_code text,
  p_display_name text,
  p_listing_type_code text,
  p_effective_from timestamptz,
  p_product_id uuid default null,
  p_components jsonb default '[]'::jsonb,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
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
  extensions
as $$
declare
  v_scope constant text :=
    'CREATE_MARKETPLACE_LISTING_VERSION_DRAFT';
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_idempotency_key text;
  v_channel_code text;
  v_external_listing_code text;
  v_display_name text;
  v_listing_type_code text;
  v_note text;
  v_metadata jsonb;
  v_components jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_command_id uuid := gen_random_uuid();
  v_channel_id uuid;
  v_listing catalog.marketplace_listings%rowtype;
  v_listing_id uuid;
  v_version_id uuid := gen_random_uuid();
  v_version integer;
  v_recorded_at timestamptz := clock_timestamp();
  v_line record;
  v_response jsonb;
begin
  perform operations.assert_marketplace_adapter_access(
    p_organization_id
  );

  v_process_name := case
    when v_actor_user_id is null
      then 'api.create_marketplace_listing_version_draft'
    else null
  end;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  v_channel_code := upper(btrim(coalesce(p_channel_code, '')));
  v_external_listing_code :=
    btrim(coalesce(p_external_listing_code, ''));
  v_display_name := btrim(coalesce(p_display_name, ''));
  v_listing_type_code :=
    upper(btrim(coalesce(p_listing_type_code, '')));
  v_note := nullif(btrim(coalesce(p_note, '')), '');
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

  if v_external_listing_code = ''
     or length(v_external_listing_code) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_CODE_INVALID';
  end if;

  if v_display_name = '' or length(v_display_name) > 300 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_NAME_INVALID';
  end if;

  if v_listing_type_code not in ('SINGLE', 'BUNDLE') then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_TYPE_INVALID';
  end if;

  if p_effective_from is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_EFFECTIVE_FROM_REQUIRED';
  end if;

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_METADATA_MUST_BE_OBJECT';
  end if;

  if v_listing_type_code = 'SINGLE' then
    if p_product_id is null then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_SINGLE_PRODUCT_REQUIRED';
    end if;

    if jsonb_typeof(coalesce(p_components, '[]'::jsonb))
         is distinct from 'array'
       or jsonb_array_length(coalesce(p_components, '[]'::jsonb)) <> 0 then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_SINGLE_COMPONENTS_NOT_ALLOWED';
    end if;

    if not exists (
      select 1
      from catalog.products product
      where product.organization_id = p_organization_id
        and product.id = p_product_id
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_PRODUCT_NOT_FOUND';
    end if;

    v_components := '[]'::jsonb;
  else
    if p_product_id is not null then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_BUNDLE_PRODUCT_NOT_ALLOWED';
    end if;

    v_components :=
      operations.validate_marketplace_admin_components(
        p_organization_id,
        p_components
      );
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
      message = 'MARKETPLACE_LISTING_CHANNEL_NOT_ALLOWED';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'channelCode', v_channel_code,
          'externalListingCode', v_external_listing_code,
          'displayName', v_display_name,
          'listingType', v_listing_type_code,
          'effectiveFrom', p_effective_from,
          'productId', p_product_id,
          'components', v_components,
          'note', v_note,
          'metadata', v_metadata,
          'schemaVersion', 1
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

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
        || ':MARKETPLACE_LISTING_IDENTITY:'
        || v_channel_id::text
        || ':'
        || v_external_listing_code,
      0::bigint
    )
  );

  select listing.*
  into v_listing
  from catalog.marketplace_listings listing
  where listing.organization_id = p_organization_id
    and listing.channel_id = v_channel_id
    and listing.external_listing_code = v_external_listing_code
  for update;

  if found then
    if v_listing.listing_type_code <> v_listing_type_code then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_TYPE_CONFLICT';
    end if;

    if v_listing.status_code <> 'ACTIVE' then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_ARCHIVED';
    end if;

    v_listing_id := v_listing.id;

    update catalog.marketplace_listings listing
    set
      display_name = v_display_name,
      updated_by = v_actor_user_id
    where listing.organization_id = p_organization_id
      and listing.id = v_listing_id
      and listing.display_name is distinct from v_display_name;
  else
    v_listing_id := gen_random_uuid();

    insert into catalog.marketplace_listings (
      id,
      organization_id,
      channel_id,
      external_listing_code,
      display_name,
      listing_type_code,
      status_code,
      created_by,
      updated_by
    ) values (
      v_listing_id,
      p_organization_id,
      v_channel_id,
      v_external_listing_code,
      v_display_name,
      v_listing_type_code,
      'ACTIVE',
      v_actor_user_id,
      v_actor_user_id
    );
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
        || ':MARKETPLACE_LISTING_VERSION:'
        || v_listing_id::text,
      0::bigint
    )
  );

  if v_listing_type_code = 'SINGLE' then
    select coalesce(max(version.version), 0) + 1
    into v_version
    from catalog.marketplace_single_listing_versions version
    where version.organization_id = p_organization_id
      and version.listing_id = v_listing_id;

    insert into catalog.marketplace_single_listing_versions (
      id,
      organization_id,
      listing_id,
      version,
      product_id,
      status_code,
      effective_from,
      effective_to,
      activated_at,
      activated_by,
      retired_at,
      retired_by,
      created_by,
      updated_by,
      row_version,
      schema_version,
      note,
      metadata
    ) values (
      v_version_id,
      p_organization_id,
      v_listing_id,
      v_version,
      p_product_id,
      'DRAFT',
      p_effective_from,
      null,
      null,
      null,
      null,
      null,
      v_actor_user_id,
      v_actor_user_id,
      1,
      1,
      v_note,
      v_metadata
    );
  else
    select coalesce(max(recipe.version), 0) + 1
    into v_version
    from catalog.bundle_recipes recipe
    where recipe.organization_id = p_organization_id
      and recipe.channel_id = v_channel_id
      and recipe.external_listing_sku = v_external_listing_code;

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
      status_code,
      recipe_fingerprint,
      activated_at,
      activated_by,
      retired_at,
      retired_by,
      updated_by,
      row_version,
      note,
      metadata,
      schema_version
    ) values (
      v_version_id,
      p_organization_id,
      v_channel_id,
      v_external_listing_code,
      v_display_name,
      v_version,
      p_effective_from,
      null,
      false,
      v_actor_user_id,
      'DRAFT',
      repeat('0', 64),
      null,
      null,
      null,
      null,
      v_actor_user_id,
      1,
      v_note,
      v_metadata,
      1
    );

    for v_line in
      select
        (item.value ->> 'lineNo')::integer as line_no,
        (item.value ->> 'productId')::uuid as product_id,
        (item.value ->> 'quantity')::bigint as quantity
      from jsonb_array_elements(v_components) item(value)
      order by (item.value ->> 'lineNo')::integer
    loop
      insert into catalog.bundle_components (
        bundle_recipe_id,
        product_id,
        component_qty,
        line_no
      ) values (
        v_version_id,
        v_line.product_id,
        v_line.quantity,
        v_line.line_no
      );
    end loop;
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

  v_response := jsonb_build_object(
    'status', 'DRAFT_CREATED',
    'listingId', v_listing_id,
    'listingType', v_listing_type_code,
    'channelCode', v_channel_code,
    'externalListingCode', v_external_listing_code,
    'displayName', v_display_name,
    'versionId', v_version_id,
    'version', v_version,
    'versionRowVersion', 1,
    'effectiveFrom', p_effective_from,
    'componentCount',
      case
        when v_listing_type_code = 'SINGLE' then 1
        else jsonb_array_length(v_components)
      end,
    'actorUserId', v_actor_user_id,
    'processName', v_process_name,
    'createdAt', v_recorded_at
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

create or replace function api.save_marketplace_listing_version_draft(
  p_organization_id uuid,
  p_listing_id uuid,
  p_version_id uuid,
  p_expected_row_version bigint,
  p_display_name text,
  p_effective_from timestamptz,
  p_product_id uuid default null,
  p_components jsonb default '[]'::jsonb,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  operations
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_listing catalog.marketplace_listings%rowtype;
  v_display_name text;
  v_note text;
  v_metadata jsonb;
  v_components jsonb;
  v_status_code text;
  v_row_version bigint;
  v_line record;
begin
  perform operations.assert_marketplace_adapter_access(
    p_organization_id
  );

  if p_listing_id is null or p_version_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_VERSION_REQUIRED';
  end if;

  if p_expected_row_version is null
     or p_expected_row_version <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_ROW_VERSION_INVALID';
  end if;

  v_display_name := btrim(coalesce(p_display_name, ''));
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_display_name = '' or length(v_display_name) > 300 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_NAME_INVALID';
  end if;

  if p_effective_from is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_EFFECTIVE_FROM_REQUIRED';
  end if;

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_METADATA_MUST_BE_OBJECT';
  end if;

  select listing.*
  into v_listing
  from catalog.marketplace_listings listing
  where listing.organization_id = p_organization_id
    and listing.id = p_listing_id
  for update;

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
    if p_product_id is null then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_SINGLE_PRODUCT_REQUIRED';
    end if;

    if jsonb_typeof(coalesce(p_components, '[]'::jsonb))
         is distinct from 'array'
       or jsonb_array_length(coalesce(p_components, '[]'::jsonb)) <> 0 then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_SINGLE_COMPONENTS_NOT_ALLOWED';
    end if;

    update catalog.marketplace_single_listing_versions version
    set
      product_id = p_product_id,
      effective_from = p_effective_from,
      note = v_note,
      metadata = v_metadata,
      updated_by = v_actor_user_id
    where version.organization_id = p_organization_id
      and version.listing_id = p_listing_id
      and version.id = p_version_id
      and version.status_code = 'DRAFT'
      and version.row_version = p_expected_row_version
    returning version.status_code, version.row_version
    into v_status_code, v_row_version;

    if not found then
      if exists (
        select 1
        from catalog.marketplace_single_listing_versions version
        where version.organization_id = p_organization_id
          and version.listing_id = p_listing_id
          and version.id = p_version_id
          and version.status_code <> 'DRAFT'
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'MARKETPLACE_LISTING_VERSION_NOT_DRAFT';
      end if;

      raise exception using
        errcode = 'P0001',
        message = 'STALE_MARKETPLACE_LISTING_VERSION_DRAFT';
    end if;

    v_components := '[]'::jsonb;
  else
    if p_product_id is not null then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_BUNDLE_PRODUCT_NOT_ALLOWED';
    end if;

    v_components :=
      operations.validate_marketplace_admin_components(
        p_organization_id,
        p_components
      );

    update catalog.bundle_recipes recipe
    set
      external_listing_name = v_display_name,
      effective_from = p_effective_from,
      note = v_note,
      metadata = v_metadata,
      updated_by = v_actor_user_id
    where recipe.organization_id = p_organization_id
      and recipe.id = p_version_id
      and recipe.status_code = 'DRAFT'
      and recipe.row_version = p_expected_row_version
    returning recipe.status_code, recipe.row_version
    into v_status_code, v_row_version;

    if not found then
      if exists (
        select 1
        from catalog.bundle_recipes recipe
        where recipe.organization_id = p_organization_id
          and recipe.id = p_version_id
          and recipe.status_code <> 'DRAFT'
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'MARKETPLACE_LISTING_VERSION_NOT_DRAFT';
      end if;

      raise exception using
        errcode = 'P0001',
        message = 'STALE_MARKETPLACE_LISTING_VERSION_DRAFT';
    end if;

    delete from catalog.bundle_components component
    where component.bundle_recipe_id = p_version_id;

    for v_line in
      select
        (item.value ->> 'lineNo')::integer as line_no,
        (item.value ->> 'productId')::uuid as product_id,
        (item.value ->> 'quantity')::bigint as quantity
      from jsonb_array_elements(v_components) item(value)
      order by (item.value ->> 'lineNo')::integer
    loop
      insert into catalog.bundle_components (
        bundle_recipe_id,
        product_id,
        component_qty,
        line_no
      ) values (
        p_version_id,
        v_line.product_id,
        v_line.quantity,
        v_line.line_no
      );
    end loop;
  end if;

  update catalog.marketplace_listings listing
  set
    display_name = v_display_name,
    updated_by = v_actor_user_id
  where listing.organization_id = p_organization_id
    and listing.id = p_listing_id
    and listing.display_name is distinct from v_display_name;

  return jsonb_build_object(
    'status', 'DRAFT_SAVED',
    'listingId', p_listing_id,
    'listingType', v_listing.listing_type_code,
    'versionId', p_version_id,
    'versionRowVersion', v_row_version,
    'displayName', v_display_name,
    'effectiveFrom', p_effective_from,
    'componentCount',
      case
        when v_listing.listing_type_code = 'SINGLE' then 1
        else jsonb_array_length(v_components)
      end
  );
end;
$$;

create or replace function api.preview_marketplace_listing_version_activation(
  p_organization_id uuid,
  p_listing_id uuid,
  p_version_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  operations
as $$
begin
  perform operations.assert_marketplace_adapter_access(
    p_organization_id
  );

  return operations.preview_marketplace_listing_activation_core(
    p_organization_id,
    p_listing_id,
    p_version_id,
    false
  );
end;
$$;

create or replace function api.activate_marketplace_listing_version(
  p_organization_id uuid,
  p_idempotency_key text,
  p_listing_id uuid,
  p_version_id uuid,
  p_expected_row_version bigint,
  p_preview_basis_hash text,
  p_confirmation boolean
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
  extensions
as $$
declare
  v_scope constant text := 'ACTIVATE_MARKETPLACE_LISTING_VERSION';
  v_actor_user_id uuid := auth.uid();
  v_idempotency_key text;
  v_expected_basis_hash text;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_command_id uuid := gen_random_uuid();
  v_preview jsonb;
  v_listing_type text;
  v_effective_from timestamptz;
  v_current_version_id uuid;
  v_fingerprint text;
  v_recorded_at timestamptz := clock_timestamp();
  v_response jsonb;
begin
  perform operations.assert_marketplace_adapter_access(
    p_organization_id
  );

  if p_confirmation is distinct from true then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_ACTIVATION_CONFIRMATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  v_expected_basis_hash :=
    lower(btrim(coalesce(p_preview_basis_hash, '')));

  if v_idempotency_key = '' then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  if v_expected_basis_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_PREVIEW_HASH_INVALID';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'listingId', p_listing_id,
          'versionId', p_version_id,
          'expectedRowVersion', p_expected_row_version,
          'previewBasisHash', v_expected_basis_hash,
          'confirmation', true,
          'schemaVersion', 1
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

  v_preview :=
    operations.preview_marketplace_listing_activation_core(
      p_organization_id,
      p_listing_id,
      p_version_id,
      true
    );

  if (v_preview ->> 'versionRowVersion')::bigint
       is distinct from p_expected_row_version then
    raise exception using
      errcode = 'P0001',
      message = 'STALE_MARKETPLACE_LISTING_VERSION_DRAFT';
  end if;

  if lower(v_preview ->> 'basisHash')
       is distinct from v_expected_basis_hash then
    raise exception using
      errcode = 'P0001',
      message = 'STALE_MARKETPLACE_LISTING_ACTIVATION_PREVIEW';
  end if;

  if coalesce((v_preview ->> 'eligible')::boolean, false)
       is not true then
    raise exception using
      errcode = 'P0001',
      message = coalesce(
        v_preview #>> '{blockers,0,code}',
        'MARKETPLACE_LISTING_ACTIVATION_BLOCKED'
      );
  end if;

  v_listing_type := v_preview ->> 'listingType';
  v_effective_from :=
    (v_preview ->> 'effectiveFrom')::timestamptz;
  v_current_version_id :=
    nullif(v_preview ->> 'currentOpenVersionId', '')::uuid;
  v_fingerprint := v_preview ->> 'mappingFingerprint';

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

  if v_current_version_id is not null then
    if v_listing_type = 'SINGLE' then
      update catalog.marketplace_single_listing_versions version
      set
        effective_to = v_effective_from,
        updated_by = v_actor_user_id
      where version.organization_id = p_organization_id
        and version.id = v_current_version_id
        and version.status_code = 'ACTIVE'
        and version.effective_to is null;
    else
      update catalog.bundle_recipes recipe
      set
        effective_to = v_effective_from,
        updated_by = v_actor_user_id
      where recipe.organization_id = p_organization_id
        and recipe.id = v_current_version_id
        and recipe.status_code = 'ACTIVE'
        and recipe.effective_to is null;
    end if;
  end if;

  if v_listing_type = 'SINGLE' then
    update catalog.marketplace_single_listing_versions version
    set
      status_code = 'ACTIVE',
      activated_at = v_recorded_at,
      activated_by = v_actor_user_id,
      updated_by = v_actor_user_id
    where version.organization_id = p_organization_id
      and version.listing_id = p_listing_id
      and version.id = p_version_id
      and version.status_code = 'DRAFT'
      and version.row_version = p_expected_row_version;
  else
    update catalog.bundle_recipes recipe
    set
      status_code = 'ACTIVE',
      is_active = true,
      recipe_fingerprint = v_fingerprint,
      activated_at = v_recorded_at,
      activated_by = v_actor_user_id,
      updated_by = v_actor_user_id
    where recipe.organization_id = p_organization_id
      and recipe.id = p_version_id
      and recipe.status_code = 'DRAFT'
      and recipe.row_version = p_expected_row_version;
  end if;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'STALE_MARKETPLACE_LISTING_VERSION_DRAFT';
  end if;

  v_response := jsonb_build_object(
    'status', 'ACTIVATED',
    'listingId', p_listing_id,
    'listingType', v_listing_type,
    'versionId', p_version_id,
    'version', (v_preview ->> 'version')::integer,
    'effectiveFrom', v_effective_from,
    'mappingFingerprint', v_fingerprint,
    'closedVersionId', v_current_version_id,
    'previewBasisHash', v_expected_basis_hash,
    'activatedAt', v_recorded_at
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

create or replace function api.retire_marketplace_listing_version(
  p_organization_id uuid,
  p_idempotency_key text,
  p_listing_id uuid,
  p_version_id uuid,
  p_expected_row_version bigint,
  p_effective_to timestamptz,
  p_confirmation boolean
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
  extensions
as $$
declare
  v_scope constant text := 'RETIRE_MARKETPLACE_LISTING_VERSION';
  v_actor_user_id uuid := auth.uid();
  v_idempotency_key text;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_command_id uuid := gen_random_uuid();
  v_listing catalog.marketplace_listings%rowtype;
  v_effective_from timestamptz;
  v_recorded_at timestamptz := clock_timestamp();
  v_response jsonb;
begin
  perform operations.assert_marketplace_adapter_access(
    p_organization_id
  );

  if p_confirmation is distinct from true then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_RETIREMENT_CONFIRMATION_REQUIRED';
  end if;

  if p_effective_to is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_RETIREMENT_TIME_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));

  if v_idempotency_key = '' then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'listingId', p_listing_id,
          'versionId', p_version_id,
          'expectedRowVersion', p_expected_row_version,
          'effectiveTo', p_effective_to,
          'confirmation', true,
          'schemaVersion', 1
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

  select listing.*
  into v_listing
  from catalog.marketplace_listings listing
  where listing.organization_id = p_organization_id
    and listing.id = p_listing_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_NOT_FOUND';
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

  if v_listing.listing_type_code = 'SINGLE' then
    select version.effective_from
    into v_effective_from
    from catalog.marketplace_single_listing_versions version
    where version.organization_id = p_organization_id
      and version.listing_id = p_listing_id
      and version.id = p_version_id
      and version.status_code = 'ACTIVE'
      and version.row_version = p_expected_row_version
    for update;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'STALE_MARKETPLACE_LISTING_ACTIVE_VERSION';
    end if;

    if p_effective_to <= v_effective_from then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_RETIREMENT_TIME_INVALID';
    end if;

    update catalog.marketplace_single_listing_versions version
    set
      status_code = 'RETIRED',
      effective_to = p_effective_to,
      retired_at = v_recorded_at,
      retired_by = v_actor_user_id,
      updated_by = v_actor_user_id
    where version.organization_id = p_organization_id
      and version.id = p_version_id;
  else
    select recipe.effective_from
    into v_effective_from
    from catalog.bundle_recipes recipe
    where recipe.organization_id = p_organization_id
      and recipe.id = p_version_id
      and recipe.status_code = 'ACTIVE'
      and recipe.row_version = p_expected_row_version
    for update;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'STALE_MARKETPLACE_LISTING_ACTIVE_VERSION';
    end if;

    if p_effective_to <= v_effective_from then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_LISTING_RETIREMENT_TIME_INVALID';
    end if;

    update catalog.bundle_recipes recipe
    set
      status_code = 'RETIRED',
      is_active = true,
      effective_to = p_effective_to,
      retired_at = v_recorded_at,
      retired_by = v_actor_user_id,
      updated_by = v_actor_user_id
    where recipe.organization_id = p_organization_id
      and recipe.id = p_version_id;
  end if;

  v_response := jsonb_build_object(
    'status', 'RETIRED',
    'listingId', p_listing_id,
    'listingType', v_listing.listing_type_code,
    'versionId', p_version_id,
    'effectiveTo', p_effective_to,
    'retiredAt', v_recorded_at
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

create or replace function api.archive_marketplace_listing(
  p_organization_id uuid,
  p_idempotency_key text,
  p_listing_id uuid,
  p_expected_row_version bigint,
  p_confirmation boolean
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
  extensions
as $$
declare
  v_scope constant text := 'ARCHIVE_MARKETPLACE_LISTING';
  v_actor_user_id uuid := auth.uid();
  v_idempotency_key text;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_command_id uuid := gen_random_uuid();
  v_listing catalog.marketplace_listings%rowtype;
  v_recorded_at timestamptz := clock_timestamp();
  v_response jsonb;
begin
  perform operations.assert_marketplace_adapter_access(
    p_organization_id
  );

  if p_confirmation is distinct from true then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_ARCHIVE_CONFIRMATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));

  if v_idempotency_key = '' then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'listingId', p_listing_id,
          'expectedRowVersion', p_expected_row_version,
          'confirmation', true,
          'schemaVersion', 1
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

  select listing.*
  into v_listing
  from catalog.marketplace_listings listing
  where listing.organization_id = p_organization_id
    and listing.id = p_listing_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_NOT_FOUND';
  end if;

  if v_listing.row_version <> p_expected_row_version then
    raise exception using
      errcode = 'P0001',
      message = 'STALE_MARKETPLACE_LISTING';
  end if;

  if v_listing.status_code <> 'ACTIVE' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_LISTING_ALREADY_ARCHIVED';
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

  update catalog.marketplace_listings listing
  set
    status_code = 'ARCHIVED',
    updated_by = v_actor_user_id
  where listing.organization_id = p_organization_id
    and listing.id = p_listing_id;

  v_response := jsonb_build_object(
    'status', 'ARCHIVED',
    'listingId', p_listing_id,
    'externalListingCode', v_listing.external_listing_code,
    'archivedAt', v_recorded_at
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

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
  v_active_component_count bigint;
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
  v_external_listing_code :=
    btrim(coalesce(p_external_listing_code, ''));

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
      message = 'MARKETPLACE_LISTING_CHANNEL_NOT_ALLOWED';
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
      and version.status_code in ('ACTIVE', 'RETIRED')
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
    into v_single_version
    from catalog.marketplace_single_listing_versions version
    where version.organization_id = p_organization_id
      and version.listing_id = v_listing.id
      and version.status_code in ('ACTIVE', 'RETIRED')
      and version.effective_from <= p_occurred_at
      and (
        version.effective_to is null
        or version.effective_to > p_occurred_at
      );

    select jsonb_build_array(
      jsonb_build_object(
        'componentNo', 1,
        'productId', product.id,
        'productSku', product.sku,
        'productName', product.name,
        'unitQuantityPerListing', 1,
        'listingQuantity', p_listing_quantity,
        'expandedQuantity', p_listing_quantity,
        'recipeComponentId', null
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
      'mappingFingerprint',
        v_single_version.mapping_fingerprint,
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
    and recipe.status_code in ('ACTIVE', 'RETIRED')
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
  into v_bundle_recipe
  from catalog.bundle_recipes recipe
  where recipe.organization_id = p_organization_id
    and recipe.channel_id = v_channel_id
    and recipe.external_listing_sku = v_external_listing_code
    and recipe.status_code in ('ACTIVE', 'RETIRED')
    and recipe.is_active
    and recipe.effective_from <= p_occurred_at
    and (
      recipe.effective_to is null
      or recipe.effective_to > p_occurred_at
    );

  select
    count(*),
    count(*) filter (where product.is_active),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'componentNo', component.line_no,
          'productId', product.id,
          'productSku', product.sku,
          'productName', product.name,
          'unitQuantityPerListing', component.component_qty,
          'listingQuantity', p_listing_quantity,
          'expandedQuantity',
            component.component_qty::numeric
              * p_listing_quantity::numeric,
          'recipeComponentId', component.id
        )
        order by component.line_no, product.sku, product.id
      ),
      '[]'::jsonb
    ),
    coalesce(
      sum(
        component.component_qty::numeric
          * p_listing_quantity::numeric
      ),
      0
    )
  into
    v_component_count,
    v_active_component_count,
    v_components,
    v_total_numeric
  from catalog.bundle_components component
  join catalog.products product
    on product.id = component.product_id
   and product.organization_id = p_organization_id
  where component.bundle_recipe_id = v_bundle_recipe.id;

  if v_component_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENTS_REQUIRED';
  end if;

  if v_active_component_count <> v_component_count then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_BUNDLE_COMPONENT_INACTIVE';
  end if;

  if v_total_numeric > 9223372036854775807::numeric then
    raise exception using
      errcode = '22003',
      message = 'MARKETPLACE_BUNDLE_EXPANSION_OVERFLOW';
  end if;

  v_fingerprint := case
    when v_bundle_recipe.recipe_fingerprint =
           repeat('0', 64)
      then catalog.bundle_recipe_fingerprint(v_bundle_recipe.id)
    else v_bundle_recipe.recipe_fingerprint
  end;

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
  coalesce(single_version.version, bundle_recipe.version)
    as current_version,
  coalesce(
    single_version.effective_from,
    bundle_recipe.effective_from
  ) as effective_from,
  coalesce(
    single_version.effective_to,
    bundle_recipe.effective_to
  ) as effective_to,
  single_version.product_id,
  bundle_recipe.id as bundle_recipe_id,
  coalesce(
    single_version.mapping_fingerprint,
    bundle_recipe.recipe_fingerprint
  ) as mapping_fingerprint,
  listing.created_at,
  listing.updated_at,
  listing.row_version,
  coalesce(
    single_version.status_code,
    bundle_recipe.status_code
  ) as current_mapping_status_code,
  case
    when listing.status_code = 'ARCHIVED' then 'ARCHIVED'
    when single_version.id is not null
      or bundle_recipe.id is not null then 'PUBLISHED'
    when draft_summary.draft_count > 0 then 'DRAFT_ONLY'
    else 'MISSING'
  end as mapping_readiness_code,
  coalesce(draft_summary.draft_count, 0)::bigint
    as draft_version_count
from catalog.marketplace_listings listing
join catalog.channels channel
  on channel.id = listing.channel_id
left join lateral (
  select version.*
  from catalog.marketplace_single_listing_versions version
  where version.organization_id = listing.organization_id
    and version.listing_id = listing.id
    and version.status_code in ('ACTIVE', 'RETIRED')
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
    and recipe.external_listing_sku =
          listing.external_listing_code
    and recipe.status_code in ('ACTIVE', 'RETIRED')
    and recipe.is_active
    and recipe.effective_from <= clock_timestamp()
    and (
      recipe.effective_to is null
      or recipe.effective_to > clock_timestamp()
    )
  order by recipe.version desc, recipe.effective_from desc, recipe.id
  limit 1
) bundle_recipe
  on listing.listing_type_code = 'BUNDLE'
left join lateral (
  select count(*)::bigint as draft_count
  from (
    select version.id
    from catalog.marketplace_single_listing_versions version
    where listing.listing_type_code = 'SINGLE'
      and version.organization_id = listing.organization_id
      and version.listing_id = listing.id
      and version.status_code = 'DRAFT'
    union all
    select recipe.id
    from catalog.bundle_recipes recipe
    where listing.listing_type_code = 'BUNDLE'
      and recipe.organization_id = listing.organization_id
      and recipe.channel_id = listing.channel_id
      and recipe.external_listing_sku =
            listing.external_listing_code
      and recipe.status_code = 'DRAFT'
  ) draft
) draft_summary on true;

create or replace view api.marketplace_listing_versions
with (security_invoker = true)
as
select
  listing.organization_id,
  listing.id as listing_id,
  channel.code as channel_code,
  listing.external_listing_code,
  listing.display_name,
  listing.listing_type_code,
  version.id as version_id,
  version.version,
  version.status_code,
  version.effective_from,
  version.effective_to,
  version.product_id,
  null::uuid as bundle_recipe_id,
  version.mapping_fingerprint,
  1::bigint as component_count,
  version.row_version,
  version.note,
  version.metadata,
  version.activated_at,
  version.activated_by,
  version.retired_at,
  version.retired_by,
  version.created_at,
  version.created_by,
  version.updated_at,
  version.updated_by
from catalog.marketplace_listings listing
join catalog.channels channel
  on channel.id = listing.channel_id
join catalog.marketplace_single_listing_versions version
  on listing.listing_type_code = 'SINGLE'
 and version.organization_id = listing.organization_id
 and version.listing_id = listing.id
union all
select
  listing.organization_id,
  listing.id as listing_id,
  channel.code as channel_code,
  listing.external_listing_code,
  listing.display_name,
  listing.listing_type_code,
  recipe.id as version_id,
  recipe.version,
  recipe.status_code,
  recipe.effective_from,
  recipe.effective_to,
  null::uuid as product_id,
  recipe.id as bundle_recipe_id,
  recipe.recipe_fingerprint as mapping_fingerprint,
  (
    select count(*)
    from catalog.bundle_components component
    where component.bundle_recipe_id = recipe.id
  )::bigint as component_count,
  recipe.row_version,
  recipe.note,
  recipe.metadata,
  recipe.activated_at,
  recipe.activated_by,
  recipe.retired_at,
  recipe.retired_by,
  recipe.created_at,
  recipe.created_by,
  recipe.updated_at,
  recipe.updated_by
from catalog.marketplace_listings listing
join catalog.channels channel
  on channel.id = listing.channel_id
join catalog.bundle_recipes recipe
  on listing.listing_type_code = 'BUNDLE'
 and recipe.organization_id = listing.organization_id
 and recipe.channel_id = listing.channel_id
 and recipe.external_listing_sku =
       listing.external_listing_code;

create or replace view api.marketplace_bundle_recipe_components
with (security_invoker = true)
as
select
  recipe.organization_id,
  listing.id as listing_id,
  recipe.id as version_id,
  recipe.version,
  recipe.status_code,
  component.id as component_id,
  component.line_no,
  component.product_id,
  product.sku as product_sku,
  product.name as product_name,
  product.is_active as product_is_active,
  component.component_qty
from catalog.bundle_recipes recipe
join catalog.marketplace_listings listing
  on listing.organization_id = recipe.organization_id
 and listing.channel_id = recipe.channel_id
 and listing.external_listing_code =
       recipe.external_listing_sku
 and listing.listing_type_code = 'BUNDLE'
join catalog.bundle_components component
  on component.bundle_recipe_id = recipe.id
join catalog.products product
  on product.organization_id = recipe.organization_id
 and product.id = component.product_id;

revoke all on catalog.bundle_recipes,
              catalog.bundle_components
from public, anon, authenticated;

grant select on catalog.bundle_recipes,
                catalog.bundle_components
to authenticated, service_role;

revoke all on function api.create_marketplace_listing_version_draft(
  uuid,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  uuid,
  jsonb,
  text,
  jsonb
) from public, anon;

grant execute on function api.create_marketplace_listing_version_draft(
  uuid,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  uuid,
  jsonb,
  text,
  jsonb
) to authenticated, service_role;

revoke all on function api.save_marketplace_listing_version_draft(
  uuid,
  uuid,
  uuid,
  bigint,
  text,
  timestamptz,
  uuid,
  jsonb,
  text,
  jsonb
) from public, anon;

grant execute on function api.save_marketplace_listing_version_draft(
  uuid,
  uuid,
  uuid,
  bigint,
  text,
  timestamptz,
  uuid,
  jsonb,
  text,
  jsonb
) to authenticated, service_role;

revoke all on function api.preview_marketplace_listing_version_activation(
  uuid,
  uuid,
  uuid
) from public, anon;

grant execute on function api.preview_marketplace_listing_version_activation(
  uuid,
  uuid,
  uuid
) to authenticated, service_role;

revoke all on function api.activate_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  text,
  boolean
) from public, anon;

grant execute on function api.activate_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  text,
  boolean
) to authenticated, service_role;

revoke all on function api.retire_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz,
  boolean
) from public, anon;

grant execute on function api.retire_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz,
  boolean
) to authenticated, service_role;

revoke all on function api.archive_marketplace_listing(
  uuid,
  text,
  uuid,
  bigint,
  boolean
) from public, anon;

grant execute on function api.archive_marketplace_listing(
  uuid,
  text,
  uuid,
  bigint,
  boolean
) to authenticated, service_role;

revoke all on api.marketplace_listing_catalog,
              api.marketplace_listing_versions,
              api.marketplace_bundle_recipe_components
from public, anon;

grant select on api.marketplace_listing_catalog,
                api.marketplace_listing_versions,
                api.marketplace_bundle_recipe_components
to authenticated, service_role;

comment on function api.create_marketplace_listing_version_draft(
  uuid,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  uuid,
  jsonb,
  text,
  jsonb
)
is 'Creates an idempotent SINGLE or BUNDLE marketplace listing version draft without stock effect.';

comment on function api.activate_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  text,
  boolean
)
is 'Activates one exact listing version from an authoritative preview, closing the previous open version at the new effective boundary.';

commit;
