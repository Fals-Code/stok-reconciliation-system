begin;

create or replace function api.create_tiktok_return_claim(
  p_organization_id uuid,
  p_idempotency_key text,
  p_return_id uuid,
  p_claim_type_code text,
  p_items jsonb,
  p_occurred_at timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, operations, inventory, catalog, extensions
as $$
declare
  v_key text := btrim(coalesce(p_idempotency_key, ''));
  v_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_return operations.returns%rowtype;
  v_claim uuid := gen_random_uuid();
  v_command_id uuid := gen_random_uuid();
  v_actor uuid := auth.uid();
  v_item record;
  v_response jsonb;
  v_item_count integer;
  v_distinct_count integer;
  v_locked_count integer;
  v_component_count integer;
  v_committed_qty bigint;
  v_net_lost_qty bigint;
begin
  if p_organization_id is null
     or p_return_id is null
     or v_key = ''
     or length(v_key) > 200
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception using errcode = 'P0001', message = 'RETURN_CLAIM_REQUEST_INVALID';
  end if;

  if v_actor is null
     or not app.is_admin()
     or app.current_organization_id() is distinct from p_organization_id then
    raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  if p_claim_type_code not in (
    'LOST_RETURN', 'PARTIAL_RETURN_MISSING', 'DAMAGED_IN_TRANSIT', 'OTHER_RETURN_EXCEPTION'
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_CLAIM_TYPE_INVALID';
  end if;

  select r.*
  into v_return
  from operations.returns r
  join catalog.channels channel on channel.id = r.channel_id
  where r.organization_id = p_organization_id
    and r.id = p_return_id
    and upper(channel.code) = 'TIKTOK_SHOP'
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'TIKTOK_RETURN_NOT_FOUND';
  end if;

  select count(*), count(distinct value->>'returnItemId')
  into v_item_count, v_distinct_count
  from jsonb_array_elements(p_items);

  if v_item_count <> v_distinct_count then
    raise exception using errcode = 'P0001', message = 'RETURN_CLAIM_DUPLICATE_ITEM';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) requested(value)
    where jsonb_typeof(requested.value) <> 'object'
       or coalesce(requested.value->>'returnItemId', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or coalesce(requested.value->>'quantity', '') !~ '^[1-9][0-9]*$'
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_CLAIM_ITEM_INVALID';
  end if;

  v_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'returnId', p_return_id,
          'claimTypeCode', p_claim_type_code,
          'items', p_items
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':CREATE_TIKTOK_RETURN_CLAIM:' || v_key, 0)
  );

  select *
  into v_existing
  from inventory.idempotency_commands
  where organization_id = p_organization_id
    and scope = 'CREATE_TIKTOK_RETURN_CLAIM'
    and key = v_key
  for update;

  if found then
    if v_existing.request_hash <> v_hash then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REUSED';
    end if;
    return v_existing.response_snapshot;
  end if;

  perform 1
  from jsonb_array_elements(p_items) requested(value)
  join operations.return_items return_item
    on return_item.organization_id = p_organization_id
   and return_item.return_id = p_return_id
   and return_item.id = (requested.value->>'returnItemId')::uuid
  order by return_item.id
  for update of return_item;

  select count(*)
  into v_locked_count
  from jsonb_array_elements(p_items) requested(value)
  join operations.return_items return_item
    on return_item.organization_id = p_organization_id
   and return_item.return_id = p_return_id
   and return_item.id = (requested.value->>'returnItemId')::uuid;

  if v_locked_count <> v_item_count then
    raise exception using
      errcode = 'P0001',
      message = 'RETURN_CLAIM_ITEM_NOT_ELIGIBLE',
      detail = 'One or more requested return items are not eligible for this organization and return.';
  end if;

  /* Locks serialize capacity and provenance validation for every canonical item. */
  for v_item in
    select return_item.*, (requested.value->>'quantity')::bigint requested_qty
    from jsonb_array_elements(p_items) requested(value)
    join operations.return_items return_item
      on return_item.organization_id = p_organization_id
     and return_item.return_id = p_return_id
     and return_item.id = (requested.value->>'returnItemId')::uuid
    order by return_item.id
  loop
    v_net_lost_qty := greatest(v_item.lost_qty - coalesce(v_item.late_arrival_qty, 0), 0);

    select coalesce(sum(claim_item.quantity), 0)::bigint
    into v_committed_qty
    from operations.return_claim_items claim_item
    join operations.return_claims claim
      on claim.organization_id = claim_item.organization_id
     and claim.id = claim_item.claim_id
    where claim_item.organization_id = p_organization_id
      and claim_item.return_item_id = v_item.id
      and claim.status_code <> 'CANCELLED';

    if v_item.requested_qty > greatest(v_net_lost_qty - v_committed_qty, 0) then
      raise exception using
        errcode = 'P0001',
        message = 'RETURN_CLAIM_ITEM_CAPACITY_EXCEEDED',
        detail = 'Requested claim quantity exceeds the remaining claimable lost quantity for a return item.';
    end if;

    /*
     * A normalized component is authoritative through order_item_id.  The
     * count guard prevents an arbitrary component choice for one canonical
     * return item; source_line_ref is only an audit value, never the join key.
     */
    select count(*)
    into v_component_count
    from operations.marketplace_source_line_components component
    where component.organization_id = p_organization_id
      and component.order_item_id = v_item.marketplace_order_item_id
      and component.product_id = v_item.product_id;

    if v_component_count > 1 then
      raise exception using
        errcode = 'P0001',
        message = 'RETURN_CLAIM_PROVENANCE_AMBIGUOUS',
        detail = 'More than one historical source-line component matches a canonical return item.';
    end if;

    if v_component_count = 0 and exists (
      select 1
      from operations.marketplace_order_items order_item
      join operations.marketplace_source_lines source_line
        on source_line.organization_id = order_item.organization_id
       and source_line.order_id = order_item.order_id
      where order_item.organization_id = p_organization_id
        and order_item.id = v_item.marketplace_order_item_id
        and source_line.bundle_recipe_id is not null
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'RETURN_CLAIM_BUNDLE_PROVENANCE_MISSING',
        detail = 'A bundle return item is missing its historical source-line component provenance.';
    end if;
  end loop;

  insert into inventory.idempotency_commands(id, organization_id, scope, key, request_hash, status_code)
  values (v_command_id, p_organization_id, 'CREATE_TIKTOK_RETURN_CLAIM', v_key, v_hash, 'STARTED');

  insert into operations.return_claims(
    id, organization_id, return_id, claim_type_code, claim_basis_code, claim_basis_at,
    window_days_snapshot, timezone_snapshot, deadline_source_code, deadline_at,
    policy_version_snapshot, actor_user_id, idempotency_command_id, request_hash
  )
  values (
    v_claim, p_organization_id, p_return_id, p_claim_type_code, 'RETURN_CREATED_AT', v_return.created_at,
    40, 'Asia/Jakarta', 'INTERNAL_RETURN_CREATED_AT', v_return.created_at + interval '40 days',
    'TIKTOK_RETURN_CREATED_AT_V1', v_actor, v_command_id, v_hash
  );

  for v_item in
    select return_item.*, (requested.value->>'quantity')::bigint requested_qty
    from jsonb_array_elements(p_items) requested(value)
    join operations.return_items return_item
      on return_item.organization_id = p_organization_id
     and return_item.return_id = p_return_id
     and return_item.id = (requested.value->>'returnItemId')::uuid
    order by return_item.id
  loop
    insert into operations.return_claim_items(
      organization_id, claim_id, return_item_id, quantity, eligible_lost_qty_snapshot,
      product_id, product_sku_snapshot, source_line_ref_snapshot, canonical_components_snapshot
    )
    select
      p_organization_id,
      v_claim,
      v_item.id,
      v_item.requested_qty,
      greatest(v_item.lost_qty - coalesce(v_item.late_arrival_qty, 0), 0),
      v_item.product_id,
      v_item.product_sku_snapshot,
      v_item.source_line_ref,
      jsonb_build_array(
        jsonb_build_object(
          'snapshotSchemaVersion', 2,
          'provenanceKind', case
            when component.id is null then 'RETURN_ITEM'
            when source_line.bundle_recipe_id is null then 'SINGLE_PRODUCT_SOURCE'
            else 'HISTORICAL_BUNDLE_SOURCE'
          end,
          'returnItemId', v_item.id,
          'marketplaceOrderItemId', order_item.id,
          'productId', v_item.product_id,
          'productSku', v_item.product_sku_snapshot,
          'sourceLineRef', v_item.source_line_ref,
          'marketplaceSourceLineId', source_line.id,
          'marketplaceSourceLineRef', source_line.source_line_ref,
          'listingId', source_line.listing_id,
          'mappingVersion', source_line.mapping_version,
          'mappingFingerprint', source_line.mapping_fingerprint,
          'singleListingVersionId', source_line.single_listing_version_id,
          'bundleRecipeId', source_line.bundle_recipe_id,
          'recipeComponentId', component.recipe_component_id,
          'componentNo', component.component_no,
          'unitQuantityPerListing', component.unit_quantity_per_listing,
          'listingQuantity', component.listing_quantity,
          'expandedQuantity', component.expanded_quantity
        )
      )
    from operations.marketplace_order_items order_item
    left join operations.marketplace_source_line_components component
      on component.organization_id = order_item.organization_id
     and component.order_item_id = order_item.id
     and component.product_id = v_item.product_id
    left join operations.marketplace_source_lines source_line
      on source_line.organization_id = component.organization_id
     and source_line.id = component.source_line_id
    where order_item.organization_id = p_organization_id
      and order_item.id = v_item.marketplace_order_item_id;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'RETURN_CLAIM_ITEM_NOT_ELIGIBLE',
        detail = 'A requested return item does not have an organization-scoped marketplace order item.';
    end if;
  end loop;

  insert into operations.return_claim_events(
    organization_id, claim_id, event_type_code, occurred_at, actor_user_id,
    idempotency_command_id, snapshot
  )
  values (
    p_organization_id, v_claim, 'CREATED', p_occurred_at, v_actor, v_command_id,
    jsonb_build_object(
      'stockEffectCode', 'NONE',
      'claimBasisCode', 'RETURN_CREATED_AT',
      'deadlineSourceCode', 'INTERNAL_RETURN_CREATED_AT'
    )
  );

  v_response := jsonb_build_object(
    'claimId', v_claim,
    'deadlineAt', v_return.created_at + interval '40 days',
    'stockEffectCode', 'NONE'
  );

  update inventory.idempotency_commands
  set status_code = 'SUCCEEDED',
      completed_at = clock_timestamp(),
      response_snapshot = v_response
  where id = v_command_id;

  return v_response;
end;
$$;

revoke all on function api.create_tiktok_return_claim(uuid,text,uuid,text,jsonb,timestamptz)
  from public, anon;
grant execute on function api.create_tiktok_return_claim(uuid,text,uuid,text,jsonb,timestamptz)
  to authenticated, service_role;

commit;
