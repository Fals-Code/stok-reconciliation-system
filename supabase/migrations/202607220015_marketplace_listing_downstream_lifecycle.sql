begin;

create or replace function operations.assert_marketplace_adapter_access(
  p_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, auth, app
as $$
declare
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

  if v_jwt_role = 'anon'
     or (
       v_jwt_role = 'authenticated'
       and v_actor_user_id is null
     ) then
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

  if v_actor_user_id is not null
     and (
       not app.is_admin()
       or app.current_organization_id()
            is distinct from p_organization_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'ORGANIZATION_ACCESS_DENIED';
  end if;
end;
$$;

revoke all on function operations.assert_marketplace_adapter_access(uuid)
from public, anon, authenticated, service_role;

create or replace function operations.resolve_marketplace_component_selection(
  p_organization_id uuid,
  p_channel_code text,
  p_order_ref text,
  p_lines jsonb,
  p_contract_code text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, catalog, operations
as $$
declare
  v_channel_code text;
  v_order_ref text;
  v_contract_code text;
  v_channel_id uuid;
  v_order_id uuid;
  v_line record;
  v_source_line_id uuid;
  v_source_component_id uuid;
  v_listing_id uuid;
  v_external_listing_code text;
  v_listing_type_code text;
  v_mapping_version integer;
  v_component_no integer;
  v_product_id uuid;
  v_product_sku text;
  v_product_name text;
  v_canonical_source_line_ref text;
  v_expanded_quantity bigint;
  v_quantity bigint;
  v_canonical_lines jsonb := '[]'::jsonb;
  v_selections jsonb := '[]'::jsonb;
  v_total_quantity numeric := 0;
begin
  v_channel_code := upper(btrim(coalesce(p_channel_code, '')));
  v_order_ref := btrim(coalesce(p_order_ref, ''));
  v_contract_code := upper(btrim(coalesce(p_contract_code, '')));

  if v_channel_code = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CHANNEL_REQUIRED';
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

  if v_contract_code not in ('SHIP', 'CANCELLATION', 'RETURN') then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_COMPONENT_CONTRACT_INVALID';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_COMPONENT_LINES_REQUIRED';
  end if;

  if jsonb_array_length(p_lines) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_COMPONENT_LINES_LIMIT_EXCEEDED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(
            item.value -> 'orderSourceLineRef'
          ) is distinct from 'string'
       or btrim(item.value ->> 'orderSourceLineRef') = ''
       or length(
            btrim(item.value ->> 'orderSourceLineRef')
          ) > 90
       or jsonb_typeof(
            item.value -> 'componentNo'
          ) is distinct from 'number'
       or (item.value ->> 'componentNo')
            !~ '^[1-9][0-9]{0,5}$'
       or jsonb_typeof(
            item.value -> 'quantity'
          ) is distinct from 'number'
       or (item.value ->> 'quantity')
            !~ '^[1-9][0-9]{0,8}$'
       or (
         v_contract_code = 'CANCELLATION'
         and (
           jsonb_typeof(
             item.value -> 'phaseCode'
           ) is distinct from 'string'
           or upper(btrim(item.value ->> 'phaseCode'))
                not in ('PRE_SHIPMENT', 'POST_SHIPMENT')
           or jsonb_typeof(
             item.value -> 'cancellationLineRef'
           ) is distinct from 'string'
           or btrim(
             item.value ->> 'cancellationLineRef'
           ) = ''
           or length(
             btrim(
               item.value ->> 'cancellationLineRef'
             )
           ) > 100
         )
       )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_COMPONENT_LINE_INVALID';
  end if;

  if v_contract_code = 'CANCELLATION' then
    if exists (
      select 1
      from jsonb_array_elements(p_lines) item(value)
      group by btrim(
        item.value ->> 'cancellationLineRef'
      )
      having count(*) > 1
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_DUPLICATE_CANCELLATION_LINE_REF';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(p_lines) item(value)
      group by
        btrim(item.value ->> 'orderSourceLineRef'),
        (item.value ->> 'componentNo')::integer,
        upper(btrim(item.value ->> 'phaseCode'))
      having count(*) > 1
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_DUPLICATE_COMPONENT_PHASE';
    end if;
  elsif exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by
      btrim(item.value ->> 'orderSourceLineRef'),
      (item.value ->> 'componentNo')::integer
    having count(*) > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_DUPLICATE_COMPONENT_LINE';
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

  select marketplace_order.id
  into v_order_id
  from operations.marketplace_orders marketplace_order
  where marketplace_order.organization_id = p_organization_id
    and marketplace_order.channel_id = v_channel_id
    and marketplace_order.external_order_ref = v_order_ref;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_ORDER_NOT_FOUND';
  end if;

  for v_line in
    select
      item.ordinality::integer as line_no,
      btrim(
        item.value ->> 'orderSourceLineRef'
      ) as order_source_line_ref,
      (item.value ->> 'componentNo')::integer
        as component_no,
      (item.value ->> 'quantity')::bigint
        as quantity,
      case
        when v_contract_code = 'CANCELLATION'
          then upper(btrim(item.value ->> 'phaseCode'))
        else null
      end as phase_code,
      case
        when v_contract_code = 'CANCELLATION'
          then btrim(
            item.value ->> 'cancellationLineRef'
          )
        else null
      end as cancellation_line_ref
    from jsonb_array_elements(p_lines)
      with ordinality item(value, ordinality)
    order by item.ordinality
  loop
    select
      source_line.id,
      source_component.id,
      source_line.listing_id,
      source_line.external_listing_code_snapshot,
      source_line.listing_type_code_snapshot,
      source_line.mapping_version,
      source_component.component_no,
      source_component.product_id,
      source_component.product_sku_snapshot,
      source_component.product_name_snapshot,
      source_component.canonical_source_line_ref,
      source_component.expanded_quantity
    into
      v_source_line_id,
      v_source_component_id,
      v_listing_id,
      v_external_listing_code,
      v_listing_type_code,
      v_mapping_version,
      v_component_no,
      v_product_id,
      v_product_sku,
      v_product_name,
      v_canonical_source_line_ref,
      v_expanded_quantity
    from operations.marketplace_source_lines source_line
    join operations.marketplace_source_line_components
      source_component
      on source_component.organization_id =
           source_line.organization_id
     and source_component.source_line_id =
           source_line.id
    where source_line.organization_id = p_organization_id
      and source_line.order_id = v_order_id
      and source_line.source_line_ref =
            v_line.order_source_line_ref
      and source_component.component_no =
            v_line.component_no;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_SOURCE_COMPONENT_NOT_FOUND';
    end if;

    v_quantity := v_line.quantity;

    if v_quantity > v_expanded_quantity then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_SOURCE_COMPONENT_QUANTITY_EXCEEDED';
    end if;

    v_total_quantity :=
      v_total_quantity + v_quantity::numeric;

    if v_total_quantity > 9223372036854775807::numeric then
      raise exception using
        errcode = '22003',
        message = 'MARKETPLACE_COMPONENT_TOTAL_OVERFLOW';
    end if;

    if v_contract_code = 'CANCELLATION' then
      v_canonical_lines :=
        v_canonical_lines
        || jsonb_build_array(
          jsonb_build_object(
            'productId', v_product_id,
            'orderItemRef',
              v_canonical_source_line_ref,
            'phaseCode', v_line.phase_code,
            'quantity', v_quantity,
            'sourceLineRef',
              v_line.cancellation_line_ref
          )
        );
    else
      v_canonical_lines :=
        v_canonical_lines
        || jsonb_build_array(
          jsonb_build_object(
            'productId', v_product_id,
            'quantity', v_quantity,
            'sourceLineRef',
              v_canonical_source_line_ref
          )
        );
    end if;

    v_selections :=
      v_selections
      || jsonb_build_array(
        jsonb_build_object(
          'lineNo', v_line.line_no,
          'orderSourceLineRef',
            v_line.order_source_line_ref,
          'sourceLineId', v_source_line_id,
          'sourceComponentId',
            v_source_component_id,
          'listingId', v_listing_id,
          'externalListingCode',
            v_external_listing_code,
          'listingType', v_listing_type_code,
          'mappingVersion', v_mapping_version,
          'componentNo', v_component_no,
          'productId', v_product_id,
          'productSku', v_product_sku,
          'productName', v_product_name,
          'canonicalSourceLineRef',
            v_canonical_source_line_ref,
          'expandedQuantity',
            v_expanded_quantity,
          'quantity', v_quantity,
          'phaseCode', v_line.phase_code,
          'cancellationLineRef',
            v_line.cancellation_line_ref
        )
      );
  end loop;

  return jsonb_build_object(
    'organizationId', p_organization_id,
    'channelId', v_channel_id,
    'channelCode', v_channel_code,
    'orderId', v_order_id,
    'orderRef', v_order_ref,
    'contractCode', v_contract_code,
    'lineCount', jsonb_array_length(v_selections),
    'totalQuantity', v_total_quantity::bigint,
    'canonicalLines', v_canonical_lines,
    'selections', v_selections
  );
end;
$$;

revoke all on function
  operations.resolve_marketplace_component_selection(
    uuid,
    text,
    text,
    jsonb,
    text
  )
from public, anon, authenticated, service_role;

create or replace function api.ship_marketplace_listing_event(
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
  operations,
  api,
  extensions
as $$
declare
  v_source_status text;
  v_raw_payload jsonb;
  v_metadata jsonb;
  v_resolution jsonb;
  v_raw_payload_hash text;
  v_result jsonb;
begin
  perform operations.assert_marketplace_adapter_access(
    p_organization_id
  );

  v_source_status :=
    upper(btrim(coalesce(p_source_status, '')));
  v_raw_payload := coalesce(p_raw_payload, '{}'::jsonb);
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

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

  v_resolution :=
    operations.resolve_marketplace_component_selection(
      p_organization_id,
      p_channel_code,
      p_order_ref,
      p_lines,
      'SHIP'
    );

  if (
    v_resolution ->> 'channelCode' = 'SHOPEE'
    and v_source_status <> 'SHIPPED'
  ) or (
    v_resolution ->> 'channelCode' = 'TIKTOK_SHOP'
    and v_source_status <> 'IN_TRANSIT'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_STATUS_NOT_SHIPPABLE';
  end if;

  v_raw_payload_hash := encode(
    extensions.digest(
      convert_to(v_raw_payload::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_metadata :=
    v_metadata
    || jsonb_build_object(
      'adapterContract',
        'MARKETPLACE_LISTING_SHIP_V1',
      'sourceStatus', v_source_status,
      'receivedAt', p_received_at,
      'rawPayloadHash', v_raw_payload_hash,
      'adapterSchemaVersion', p_schema_version,
      'sourceComponentSelections',
        v_resolution -> 'selections'
    );

  v_result := api.apply_marketplace_event(
    p_organization_id,
    p_idempotency_key,
    v_resolution ->> 'channelCode',
    'SHIP',
    p_event_ref,
    p_order_ref,
    p_occurred_at,
    v_resolution -> 'canonicalLines',
    p_note,
    v_metadata
  );

  return v_result
    || jsonb_build_object(
      'adapterContract',
        'MARKETPLACE_LISTING_SHIP_V1',
      'sourceStatus', v_source_status,
      'receivedAt', p_received_at,
      'rawPayloadHash', v_raw_payload_hash,
      'sourceComponents',
        v_resolution -> 'selections'
    );
end;
$$;

revoke all on function api.ship_marketplace_listing_event(
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

grant execute on function api.ship_marketplace_listing_event(
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

create or replace function api.preview_marketplace_listing_cancellation(
  p_organization_id uuid,
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
  operations,
  api,
  extensions
as $$
declare
  v_source_status text;
  v_raw_payload jsonb;
  v_metadata jsonb;
  v_resolution jsonb;
  v_raw_payload_hash text;
  v_result jsonb;
begin
  perform operations.assert_marketplace_adapter_access(
    p_organization_id
  );

  v_source_status :=
    upper(btrim(coalesce(p_source_status, '')));
  v_raw_payload := coalesce(p_raw_payload, '{}'::jsonb);
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_source_status = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_STATUS_REQUIRED';
  end if;

  if p_occurred_at is null or p_received_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_EVENT_TIME_REQUIRED';
  end if;

  if p_received_at < p_occurred_at then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_RECEIVED_BEFORE_OCCURRED';
  end if;

  if jsonb_typeof(v_raw_payload) is distinct from 'object'
     or jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_ADAPTER_OBJECT_INVALID';
  end if;

  if p_schema_version is null or p_schema_version <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SCHEMA_VERSION_INVALID';
  end if;

  v_resolution :=
    operations.resolve_marketplace_component_selection(
      p_organization_id,
      p_channel_code,
      p_order_ref,
      p_lines,
      'CANCELLATION'
    );

  v_raw_payload_hash := encode(
    extensions.digest(
      convert_to(v_raw_payload::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_metadata :=
    v_metadata
    || jsonb_build_object(
      'adapterContract',
        'MARKETPLACE_LISTING_CANCELLATION_V1',
      'sourceStatus', v_source_status,
      'receivedAt', p_received_at,
      'rawPayloadHash', v_raw_payload_hash,
      'adapterSchemaVersion', p_schema_version,
      'sourceComponentSelections',
        v_resolution -> 'selections'
    );

  v_result := api.preview_marketplace_cancellation(
    p_organization_id,
    v_resolution ->> 'channelCode',
    p_event_ref,
    p_order_ref,
    p_occurred_at,
    v_source_status,
    v_resolution -> 'canonicalLines',
    p_note,
    v_metadata
  );

  return v_result
    || jsonb_build_object(
      'adapterContract',
        'MARKETPLACE_LISTING_CANCELLATION_V1',
      'receivedAt', p_received_at,
      'rawPayloadHash', v_raw_payload_hash,
      'sourceComponents',
        v_resolution -> 'selections'
    );
end;
$$;

revoke all on function
  api.preview_marketplace_listing_cancellation(
    uuid,
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
  )
from public, anon;

grant execute on function
  api.preview_marketplace_listing_cancellation(
    uuid,
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
  )
to authenticated, service_role;

create or replace function api.post_marketplace_listing_cancellation(
  p_organization_id uuid,
  p_idempotency_key text,
  p_channel_code text,
  p_event_ref text,
  p_order_ref text,
  p_source_status text,
  p_occurred_at timestamptz,
  p_received_at timestamptz,
  p_lines jsonb,
  p_preview_basis_hash text,
  p_confirmation boolean,
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
  operations,
  api,
  extensions
as $$
declare
  v_source_status text;
  v_raw_payload jsonb;
  v_metadata jsonb;
  v_resolution jsonb;
  v_raw_payload_hash text;
  v_result jsonb;
begin
  perform operations.assert_marketplace_adapter_access(
    p_organization_id
  );

  v_source_status :=
    upper(btrim(coalesce(p_source_status, '')));
  v_raw_payload := coalesce(p_raw_payload, '{}'::jsonb);
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_source_status = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SOURCE_STATUS_REQUIRED';
  end if;

  if p_occurred_at is null or p_received_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_EVENT_TIME_REQUIRED';
  end if;

  if p_received_at < p_occurred_at then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_RECEIVED_BEFORE_OCCURRED';
  end if;

  if jsonb_typeof(v_raw_payload) is distinct from 'object'
     or jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_ADAPTER_OBJECT_INVALID';
  end if;

  if p_schema_version is null or p_schema_version <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_SCHEMA_VERSION_INVALID';
  end if;

  v_resolution :=
    operations.resolve_marketplace_component_selection(
      p_organization_id,
      p_channel_code,
      p_order_ref,
      p_lines,
      'CANCELLATION'
    );

  v_raw_payload_hash := encode(
    extensions.digest(
      convert_to(v_raw_payload::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_metadata :=
    v_metadata
    || jsonb_build_object(
      'adapterContract',
        'MARKETPLACE_LISTING_CANCELLATION_V1',
      'sourceStatus', v_source_status,
      'receivedAt', p_received_at,
      'rawPayloadHash', v_raw_payload_hash,
      'adapterSchemaVersion', p_schema_version,
      'sourceComponentSelections',
        v_resolution -> 'selections'
    );

  v_result := api.post_marketplace_cancellation(
    p_organization_id,
    p_idempotency_key,
    v_resolution ->> 'channelCode',
    p_event_ref,
    p_order_ref,
    p_occurred_at,
    v_source_status,
    v_resolution -> 'canonicalLines',
    p_preview_basis_hash,
    p_confirmation,
    p_note,
    v_metadata
  );

  return v_result
    || jsonb_build_object(
      'adapterContract',
        'MARKETPLACE_LISTING_CANCELLATION_V1',
      'receivedAt', p_received_at,
      'rawPayloadHash', v_raw_payload_hash,
      'sourceComponents',
        v_resolution -> 'selections'
    );
end;
$$;

revoke all on function
  api.post_marketplace_listing_cancellation(
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
    boolean,
    text,
    jsonb,
    jsonb,
    integer
  )
from public, anon;

grant execute on function
  api.post_marketplace_listing_cancellation(
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
    boolean,
    text,
    jsonb,
    jsonb,
    integer
  )
to authenticated, service_role;

create or replace function api.create_expected_marketplace_listing_return(
  p_organization_id uuid,
  p_idempotency_key text,
  p_channel_code text,
  p_return_ref text,
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
  operations,
  api,
  extensions
as $$
declare
  v_source_status text;
  v_raw_payload jsonb;
  v_metadata jsonb;
  v_resolution jsonb;
  v_raw_payload_hash text;
  v_result jsonb;
begin
  perform operations.assert_marketplace_adapter_access(
    p_organization_id
  );

  v_source_status :=
    upper(btrim(coalesce(p_source_status, '')));
  v_raw_payload := coalesce(p_raw_payload, '{}'::jsonb);
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_source_status = '' then
    raise exception using
      errcode = 'P0001',
      message = 'RETURN_SOURCE_STATUS_REQUIRED';
  end if;

  if p_occurred_at is null or p_received_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'RETURN_EVENT_TIME_REQUIRED';
  end if;

  if p_received_at < p_occurred_at then
    raise exception using
      errcode = 'P0001',
      message = 'RETURN_RECEIVED_BEFORE_OCCURRED';
  end if;

  if jsonb_typeof(v_raw_payload) is distinct from 'object'
     or jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'RETURN_ADAPTER_OBJECT_INVALID';
  end if;

  if p_schema_version is null or p_schema_version <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'RETURN_SCHEMA_VERSION_INVALID';
  end if;

  v_resolution :=
    operations.resolve_marketplace_component_selection(
      p_organization_id,
      p_channel_code,
      p_order_ref,
      p_lines,
      'RETURN'
    );

  v_raw_payload_hash := encode(
    extensions.digest(
      convert_to(v_raw_payload::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_metadata :=
    v_metadata
    || jsonb_build_object(
      'adapterContract',
        'MARKETPLACE_LISTING_EXPECTED_RETURN_V1',
      'sourceStatus', v_source_status,
      'receivedAt', p_received_at,
      'rawPayloadHash', v_raw_payload_hash,
      'adapterSchemaVersion', p_schema_version,
      'sourceComponentSelections',
        v_resolution -> 'selections'
    );

  v_result := api.create_expected_return(
    p_organization_id,
    p_idempotency_key,
    v_resolution ->> 'channelCode',
    p_return_ref,
    p_order_ref,
    p_occurred_at,
    v_resolution -> 'canonicalLines',
    v_source_status,
    p_note,
    v_metadata
  );

  return v_result
    || jsonb_build_object(
      'adapterContract',
        'MARKETPLACE_LISTING_EXPECTED_RETURN_V1',
      'receivedAt', p_received_at,
      'rawPayloadHash', v_raw_payload_hash,
      'sourceComponents',
        v_resolution -> 'selections'
    );
end;
$$;

revoke all on function
  api.create_expected_marketplace_listing_return(
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
  )
from public, anon;

grant execute on function
  api.create_expected_marketplace_listing_return(
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
  )
to authenticated, service_role;

create or replace view api.marketplace_listing_component_lifecycle
with (security_invoker = true)
as
with shipped as (
  select
    event_line.organization_id,
    event_line.order_item_id,
    coalesce(sum(allocation.quantity_allocated), 0)::bigint
      as shipped_quantity
  from operations.marketplace_event_lines event_line
  join operations.marketplace_ship_allocations allocation
    on allocation.organization_id =
         event_line.organization_id
   and allocation.event_line_id = event_line.id
  join operations.marketplace_events marketplace_event
    on marketplace_event.organization_id =
         event_line.organization_id
   and marketplace_event.id = event_line.event_id
  where marketplace_event.event_type_code = 'SHIP'
  group by
    event_line.organization_id,
    event_line.order_item_id
),
cancelled as (
  select
    cancellation_line.organization_id,
    cancellation_line.order_item_id,
    coalesce(
      sum(application.quantity_applied) filter (
        where application.effect_code =
          'PRE_SHIPMENT_RELEASE'
      ),
      0
    )::bigint as pre_shipment_cancelled_quantity,
    coalesce(
      sum(application.quantity_applied) filter (
        where application.effect_code =
          'POST_SHIPMENT_REVERSAL'
      ),
      0
    )::bigint as post_shipment_cancelled_quantity
  from operations.marketplace_cancellation_lines
    cancellation_line
  join operations.marketplace_cancellation_applications
    application
    on application.organization_id =
         cancellation_line.organization_id
   and application.cancellation_line_id =
         cancellation_line.id
  group by
    cancellation_line.organization_id,
    cancellation_line.order_item_id
),
returned as (
  select
    return_item.organization_id,
    return_item.marketplace_order_item_id as order_item_id,
    coalesce(sum(return_item.expected_qty), 0)::bigint
      as return_expected_quantity,
    coalesce(sum(return_item.received_qty), 0)::bigint
      as return_received_quantity,
    coalesce(sum(return_item.sellable_qty), 0)::bigint
      as return_sellable_quantity,
    coalesce(sum(return_item.damaged_qty), 0)::bigint
      as return_damaged_quantity,
    coalesce(sum(return_item.lost_qty), 0)::bigint
      as return_lost_quantity
  from operations.return_items return_item
  group by
    return_item.organization_id,
    return_item.marketplace_order_item_id
)
select
  source_line.organization_id,
  marketplace_order.id as order_id,
  marketplace_order.external_order_ref,
  channel.code as channel_code,
  source_line.id as source_line_id,
  source_line.source_line_ref,
  source_line.listing_id,
  source_line.external_listing_code_snapshot,
  source_line.listing_name_snapshot,
  source_line.listing_type_code_snapshot,
  source_line.listing_quantity,
  source_line.mapping_version,
  source_line.mapping_fingerprint,
  component.id as source_component_id,
  component.component_no,
  component.recipe_component_id,
  component.order_item_id,
  component.product_id,
  component.product_sku_snapshot,
  component.product_name_snapshot,
  component.canonical_source_line_ref,
  component.unit_quantity_per_listing,
  component.expanded_quantity,
  item.reservation_id,
  reservation.reserved_qty,
  reservation.consumed_qty,
  reservation.released_qty,
  reservation.status_code as reservation_status_code,
  coalesce(shipped.shipped_quantity, 0)::bigint
    as shipped_quantity,
  coalesce(
    cancelled.pre_shipment_cancelled_quantity,
    0
  )::bigint as pre_shipment_cancelled_quantity,
  coalesce(
    cancelled.post_shipment_cancelled_quantity,
    0
  )::bigint as post_shipment_cancelled_quantity,
  coalesce(returned.return_expected_quantity, 0)::bigint
    as return_expected_quantity,
  coalesce(returned.return_received_quantity, 0)::bigint
    as return_received_quantity,
  coalesce(returned.return_sellable_quantity, 0)::bigint
    as return_sellable_quantity,
  coalesce(returned.return_damaged_quantity, 0)::bigint
    as return_damaged_quantity,
  coalesce(returned.return_lost_quantity, 0)::bigint
    as return_lost_quantity,
  greatest(
    reservation.reserved_qty
      - reservation.consumed_qty
      - reservation.released_qty,
    0
  )::bigint as open_reserved_quantity,
  greatest(
    coalesce(shipped.shipped_quantity, 0)
      - coalesce(
          cancelled.post_shipment_cancelled_quantity,
          0
        )
      - coalesce(returned.return_expected_quantity, 0),
    0
  )::bigint as remaining_returnable_or_cancellable_quantity
from operations.marketplace_source_lines source_line
join operations.marketplace_source_line_components component
  on component.organization_id = source_line.organization_id
 and component.source_line_id = source_line.id
join operations.marketplace_orders marketplace_order
  on marketplace_order.organization_id =
       source_line.organization_id
 and marketplace_order.id = source_line.order_id
join catalog.channels channel
  on channel.id = marketplace_order.channel_id
join operations.marketplace_order_items item
  on item.organization_id = component.organization_id
 and item.id = component.order_item_id
join inventory.stock_reservations reservation
  on reservation.organization_id = item.organization_id
 and reservation.id = item.reservation_id
left join shipped
  on shipped.organization_id = component.organization_id
 and shipped.order_item_id = component.order_item_id
left join cancelled
  on cancelled.organization_id = component.organization_id
 and cancelled.order_item_id = component.order_item_id
left join returned
  on returned.organization_id = component.organization_id
 and returned.order_item_id = component.order_item_id;

revoke all on api.marketplace_listing_component_lifecycle
from public, anon;

grant select on api.marketplace_listing_component_lifecycle
to authenticated, service_role;

commit;
