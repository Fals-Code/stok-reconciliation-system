begin;

alter table catalog.products
  add column size_ml integer null;

alter table catalog.products
  add constraint ck_products_size_ml check (size_ml is null or size_ml > 0);

create or replace function catalog.generate_sku(
  p_name text,
  p_size_ml integer
)
returns text
language plpgsql
immutable
strict
set search_path = pg_catalog
as $$
declare
  v_normalized_name text;
  v_words text[];
  v_part1 text;
  v_part2 text;
begin
  if p_size_ml <= 0 then
    return null;
  end if;

  v_normalized_name := regexp_replace(
    upper(btrim(p_name)),
    '[[:space:]]+',
    ' ',
    'g'
  );

  if v_normalized_name = '' then
    return null;
  end if;

  v_words := regexp_split_to_array(v_normalized_name, '[[:space:]]+');

  v_part1 := left(
    regexp_replace(coalesce(v_words[1], ''), '[^A-Z0-9]', '', 'g'),
    3
  );

  if array_length(v_words, 1) >= 2 then
    v_part2 := left(
      regexp_replace(coalesce(v_words[2], ''), '[^A-Z0-9]', '', 'g'),
      3
    );
  end if;

  if coalesce(v_part1, '') = '' then
    return null;
  end if;

  if coalesce(v_part2, '') = '' then
    return v_part1 || '-' || p_size_ml::text;
  end if;

  return v_part1 || '-' || v_part2 || '-' || p_size_ml::text;
end;
$$;

revoke all on function catalog.generate_sku(text, integer)
from public, anon, authenticated, service_role;

create or replace function catalog.product_master_snapshot(
  p_product catalog.products
)
returns jsonb
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'productId', p_product.id,
    'organizationId', p_product.organization_id,
    'sku', p_product.sku,
    'name', p_product.name,
    'sizeMl', p_product.size_ml,
    'unitCode', p_product.unit_code,
    'description', p_product.description,
    'isActive', p_product.is_active,
    'isBatchTracked', p_product.is_batch_tracked,
    'isExpiryTracked', p_product.is_expiry_tracked,
    'rowVersion', p_product.row_version,
    'createdAt', p_product.created_at,
    'createdBy', p_product.created_by,
    'updatedAt', p_product.updated_at,
    'updatedBy', p_product.updated_by
  )
$$;

create or replace view api.product_master
with (security_invoker = true)
as
select
  product.id as product_id,
  product.organization_id,
  product.sku,
  product.name,
  product.unit_code,
  product.description,
  product.is_active,
  product.row_version,
  product.created_at,
  product.created_by,
  product.updated_at,
  product.updated_by,
  coalesce(position.sellable_qty, 0)::bigint as sellable_qty,
  coalesce(position.quarantine_qty, 0)::bigint as quarantine_qty,
  coalesce(position.damaged_qty, 0)::bigint as damaged_qty,
  coalesce(position.reserved_qty, 0)::bigint as reserved_qty,
  (
    coalesce(position.sellable_qty, 0)
    - coalesce(position.reserved_qty, 0)
  )::bigint as available_qty,
  coalesce(position.last_ledger_seq, 0)::bigint as last_ledger_seq,
  catalog.product_has_authoritative_history(
    product.organization_id,
    product.id
  ) as has_authoritative_history,
  (
    select count(*)
    from catalog.product_batches batch
    where batch.organization_id = product.organization_id
      and batch.product_id = product.id
  )::bigint as batch_count,
  (
    select count(*)
    from (
      select
        'SINGLE:' || version.listing_id::text as listing_reference
      from catalog.marketplace_single_listing_versions version
      where version.organization_id = product.organization_id
        and version.product_id = product.id
      union
      select
        'BUNDLE:' || listing.id::text
      from catalog.bundle_components component
      join catalog.bundle_recipes recipe
        on recipe.id = component.bundle_recipe_id
      join catalog.marketplace_listings listing
        on listing.organization_id = recipe.organization_id
       and listing.channel_id = recipe.channel_id
       and listing.external_listing_code = recipe.external_listing_sku
      where recipe.organization_id = product.organization_id
        and component.product_id = product.id
    ) reference
  )::bigint as listing_reference_count,
  product.size_ml
from catalog.products product
left join inventory.stock_product_positions position
  on position.organization_id = product.organization_id
 and position.product_id = product.id;


create or replace function api.create_product(
  p_organization_id uuid,
  p_idempotency_key text,
  p_name text,
  p_size_ml integer,
  p_unit_code text default 'UNIT',
  p_description text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, extensions
as $$
declare
  v_scope constant text := 'CREATE_PRODUCT';
  v_sku text;
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_unit_code text := upper(btrim(coalesce(p_unit_code, '')));
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_request_hash text;
  v_caller record;
  v_command record;
  v_product catalog.products%rowtype;
  v_product_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_audit_id uuid;
  v_response jsonb;
begin
  select *
  into v_caller
  from catalog.assert_master_data_caller(
    p_organization_id,
    'api.create_product'
  );

  if v_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_REQUIRED_FIELDS_MISSING';
  end if;

  if p_size_ml is null or p_size_ml <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'INVALID_PRODUCT_SIZE';
  end if;

  v_sku := catalog.generate_sku(v_name, p_size_ml);

  if v_sku is null or v_sku !~ '^[A-Z0-9]{1,3}(-[A-Z0-9]{1,3})?-[1-9][0-9]*$' then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_REQUIRED_FIELDS_MISSING';
  end if;

  if v_unit_code <> 'UNIT' then
    raise exception using
      errcode = 'P0001',
      message = 'UNSUPPORTED_UNIT';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'sku', v_sku,
          'name', v_name,
          'sizeMl', p_size_ml,
          'unitCode', v_unit_code,
          'description', v_description,
          'note', v_note,
          'schemaVersion', 2
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select *
  into v_command
  from catalog.start_master_data_command(
    p_organization_id,
    v_scope,
    p_idempotency_key,
    v_request_hash
  );

  if v_command.is_replay then
    return v_command.response_snapshot;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':PRODUCT_SKU:' || v_sku,
      0::bigint
    )
  );

  if exists (
    select 1
    from catalog.products product
    where product.organization_id = p_organization_id
      and catalog.normalize_master_identifier(product.sku) = v_sku
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'DUPLICATE_SKU';
  end if;

  begin
    insert into catalog.products (
      id,
      organization_id,
      sku,
      name,
      size_ml,
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
    ) values (
      v_product_id,
      p_organization_id,
      v_sku,
      v_name,
      p_size_ml,
      'UNIT',
      null,
      v_description,
      true,
      true,
      true,
      v_recorded_at,
      v_caller.actor_user_id,
      v_recorded_at,
      v_caller.actor_user_id,
      1
    )
    returning * into v_product;
  exception
    when unique_violation then
      raise exception using
        errcode = 'P0001',
        message = 'DUPLICATE_SKU';
  end;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'PRODUCT',
    v_product.id,
    'PRODUCT_CREATE',
    v_command.command_id,
    null,
    catalog.product_master_snapshot(v_product),
    null,
    v_note,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', 'CREATED',
    'productId', v_product.id,
    'sku', v_product.sku,
    'name', v_product.name,
    'sizeMl', v_product.size_ml,
    'unitCode', v_product.unit_code,
    'description', v_product.description,
    'isActive', v_product.is_active,
    'rowVersion', v_product.row_version,
    'auditId', v_audit_id,
    'idempotencyKey', btrim(p_idempotency_key),
    'stockEffect', 'NONE',
    'recordedAt', v_recorded_at
  );

  perform catalog.complete_master_data_command(
    v_command.command_id,
    v_response
  );

  return v_response;
end;
$$;

create or replace function api.update_product(
  p_organization_id uuid,
  p_idempotency_key text,
  p_product_id uuid,
  p_expected_row_version bigint,
  p_name text,
  p_size_ml integer,
  p_unit_code text default 'UNIT',
  p_description text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, extensions
as $$
declare
  v_scope constant text := 'UPDATE_PRODUCT';
  v_sku text;
  v_generated_sku text;
  v_has_history boolean;
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_unit_code text := upper(btrim(coalesce(p_unit_code, '')));
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_request_hash text;
  v_caller record;
  v_command record;
  v_before catalog.products%rowtype;
  v_after catalog.products%rowtype;
  v_recorded_at timestamptz := clock_timestamp();
  v_audit_id uuid;
  v_response jsonb;
begin
  select *
  into v_caller
  from catalog.assert_master_data_caller(
    p_organization_id,
    'api.update_product'
  );

  if p_product_id is null
     or v_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_REQUIRED_FIELDS_MISSING';
  end if;

  if p_size_ml is null or p_size_ml <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'INVALID_PRODUCT_SIZE';
  end if;

  v_generated_sku := catalog.generate_sku(v_name, p_size_ml);

  if v_generated_sku is null or v_generated_sku !~ '^[A-Z0-9]{1,3}(-[A-Z0-9]{1,3})?-[1-9][0-9]*$' then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_REQUIRED_FIELDS_MISSING';
  end if;

  if v_unit_code <> 'UNIT' then
    raise exception using
      errcode = 'P0001',
      message = 'UNSUPPORTED_UNIT';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'productId', p_product_id,
          'expectedRowVersion', p_expected_row_version,
          'generatedSku', v_generated_sku,
          'name', v_name,
          'sizeMl', p_size_ml,
          'unitCode', v_unit_code,
          'description', v_description,
          'note', v_note,
          'schemaVersion', 2
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select *
  into v_command
  from catalog.start_master_data_command(
    p_organization_id,
    v_scope,
    p_idempotency_key,
    v_request_hash
  );

  if v_command.is_replay then
    return v_command.response_snapshot;
  end if;

  select product.*
  into v_before
  from catalog.products product
  where product.organization_id = p_organization_id
    and product.id = p_product_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_NOT_FOUND';
  end if;

  if p_expected_row_version is null
     or v_before.row_version <> p_expected_row_version then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_STALE_VERSION';
  end if;

  v_has_history := catalog.product_has_authoritative_history(
    p_organization_id,
    p_product_id
  );

  if v_has_history then
    if v_before.size_ml is not null
       and p_size_ml is distinct from v_before.size_ml then
      raise exception using
        errcode = 'P0001',
        message = 'TRANSACTED_SKU_CHANGE_FORBIDDEN';
    end if;

    v_sku := v_before.sku;
  else
    v_sku := v_generated_sku;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':PRODUCT_SKU:' || v_sku,
      0::bigint
    )
  );

  if exists (
    select 1
    from catalog.products product
    where product.organization_id = p_organization_id
      and product.id <> p_product_id
      and catalog.normalize_master_identifier(product.sku) = v_sku
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'DUPLICATE_SKU';
  end if;

  begin
    update catalog.products product
    set
      sku = v_sku,
      name = v_name,
      size_ml = p_size_ml,
      unit_code = 'UNIT',
      description = v_description,
      updated_by = v_caller.actor_user_id
    where product.organization_id = p_organization_id
      and product.id = p_product_id
    returning * into v_after;
  exception
    when unique_violation then
      raise exception using
        errcode = 'P0001',
        message = 'DUPLICATE_SKU';
  end;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'PRODUCT',
    v_after.id,
    'PRODUCT_UPDATE',
    v_command.command_id,
    catalog.product_master_snapshot(v_before),
    catalog.product_master_snapshot(v_after),
    null,
    v_note,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', 'UPDATED',
    'productId', v_after.id,
    'sku', v_after.sku,
    'name', v_after.name,
    'sizeMl', v_after.size_ml,
    'unitCode', v_after.unit_code,
    'description', v_after.description,
    'isActive', v_after.is_active,
    'rowVersion', v_after.row_version,
    'auditId', v_audit_id,
    'idempotencyKey', btrim(p_idempotency_key),
    'stockEffect', 'NONE',
    'recordedAt', v_recorded_at
  );

  perform catalog.complete_master_data_command(
    v_command.command_id,
    v_response
  );

  return v_response;
end;
$$;

-- Retire the legacy manual-SKU RPC signatures.
drop function if exists api.create_product(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text
);

drop function if exists api.update_product(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text,
  text,
  text,
  text
);

revoke all on function api.create_product(
  uuid,
  text,
  text,
  integer,
  text,
  text,
  text
) from public, anon, authenticated, service_role;

grant execute on function api.create_product(
  uuid,
  text,
  text,
  integer,
  text,
  text,
  text
) to authenticated, service_role;

revoke all on function api.update_product(
  uuid,
  text,
  uuid,
  bigint,
  text,
  integer,
  text,
  text,
  text
) from public, anon, authenticated, service_role;

grant execute on function api.update_product(
  uuid,
  text,
  uuid,
  bigint,
  text,
  integer,
  text,
  text,
  text
) to authenticated, service_role;

commit;