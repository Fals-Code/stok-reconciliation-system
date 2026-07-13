begin;

create or replace function api.create_expected_return(
  p_organization_id uuid,
  p_idempotency_key text,
  p_channel_code text,
  p_return_ref text,
  p_order_ref text,
  p_occurred_at timestamptz,
  p_lines jsonb,
  p_source_status text default null,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_scope constant text := 'CREATE_EXPECTED_RETURN';
  v_idempotency_key text;
  v_channel_code text;
  v_return_ref text;
  v_order_ref text;
  v_source_status text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_timezone text;
  v_channel_id uuid;
  v_order_id uuid;
  v_return_id uuid := gen_random_uuid();
  v_event_id uuid := gen_random_uuid();
  v_command_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text := coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_line record;
  v_order_item_id uuid;
  v_product_sku text;
  v_shipped_qty bigint;
  v_already_expected bigint;
  v_return_item_id uuid;
  v_total_quantity bigint := 0;
  v_line_results jsonb := '[]'::jsonb;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  v_channel_code := upper(btrim(coalesce(p_channel_code, '')));
  v_return_ref := btrim(coalesce(p_return_ref, ''));
  v_order_ref := btrim(coalesce(p_order_ref, ''));
  v_source_status := nullif(btrim(coalesce(p_source_status, '')), '');
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;
  if v_channel_code = '' then
    raise exception using errcode = 'P0001', message = 'RETURN_CHANNEL_REQUIRED';
  end if;
  if v_return_ref = '' then
    raise exception using errcode = 'P0001', message = 'RETURN_REF_REQUIRED';
  end if;
  if length(v_return_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'RETURN_REF_TOO_LONG';
  end if;
  if v_order_ref = '' then
    raise exception using errcode = 'P0001', message = 'RETURN_ORDER_REF_REQUIRED';
  end if;
  if length(v_order_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'RETURN_ORDER_REF_TOO_LONG';
  end if;
  if p_occurred_at is null then
    raise exception using errcode = 'P0001', message = 'RETURN_OCCURRED_AT_REQUIRED';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) = 0 then
    raise exception using errcode = 'P0001', message = 'RETURN_LINES_REQUIRED';
  end if;
  if jsonb_array_length(p_lines) > 200 then
    raise exception using errcode = 'P0001', message = 'RETURN_LINES_LIMIT_EXCEEDED';
  end if;
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'RETURN_METADATA_MUST_BE_OBJECT';
  end if;
  if v_source_status is not null and length(v_source_status) > 100 then
    raise exception using errcode = 'P0001', message = 'RETURN_SOURCE_STATUS_TOO_LONG';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'RETURN_NOTE_TOO_LONG';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'productId') is distinct from 'string'
       or (item.value ->> 'productId') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'quantity') is distinct from 'number'
       or (item.value ->> 'quantity') !~ '^[1-9][0-9]{0,8}$'
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 100
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_DUPLICATE_SOURCE_LINE';
  end if;

  select organization.timezone
  into v_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_NOT_FOUND';
  end if;

  if v_jwt_role = 'anon'
     or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id then
      raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
    end if;
    v_process_name := null;
  else
    v_process_name := 'api.create_expected_return';
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = v_channel_code
    and channel.is_marketplace
    and channel.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'RETURN_CHANNEL_NOT_ALLOWED';
  end if;

  select marketplace_order.id
  into v_order_id
  from operations.marketplace_orders marketplace_order
  where marketplace_order.organization_id = p_organization_id
    and marketplace_order.channel_id = v_channel_id
    and marketplace_order.external_order_ref = v_order_ref
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'RETURN_ORDER_NOT_FOUND';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'channelCode', v_channel_code,
          'returnRef', v_return_ref,
          'orderRef', v_order_ref,
          'occurredAt', p_occurred_at,
          'lines', p_lines,
          'sourceStatus', v_source_status,
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
      p_organization_id::text || ':' || v_scope || ':' || v_idempotency_key,
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
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REUSED';
    end if;
    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot;
    end if;
    if v_existing.status_code = 'STARTED' then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':RETURN_REF:' || v_channel_code || ':' || v_return_ref,
      0::bigint
    )
  );

  if exists (
    select 1
    from operations.returns return_header
    where return_header.organization_id = p_organization_id
      and return_header.channel_id = v_channel_id
      and return_header.external_return_ref = v_return_ref
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_ALREADY_EXISTS';
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

  insert into operations.returns (
    id,
    organization_id,
    channel_id,
    marketplace_order_id,
    external_return_ref,
    source_status_code,
    status_code,
    outcome_code,
    expected_at,
    closed_at,
    actor_user_id,
    process_name,
    metadata,
    created_at,
    updated_at
  ) values (
    v_return_id,
    p_organization_id,
    v_channel_id,
    v_order_id,
    v_return_ref,
    v_source_status,
    'EXPECTED',
    null,
    p_occurred_at,
    null,
    v_actor_user_id,
    v_process_name,
    v_metadata,
    v_recorded_at,
    v_recorded_at
  );

  insert into operations.return_events (
    id,
    organization_id,
    return_id,
    external_event_ref,
    event_type_code,
    occurred_at,
    recorded_at,
    actor_user_id,
    process_name,
    transaction_id,
    idempotency_command_id,
    note,
    metadata,
    created_at
  ) values (
    v_event_id,
    p_organization_id,
    v_return_id,
    'EXPECTED:' || v_return_ref,
    'EXPECTED',
    p_occurred_at,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    null,
    v_command_id,
    v_note,
    v_metadata,
    v_recorded_at
  );

  for v_line in
    select
      item.ordinality::integer as line_no,
      (item.value ->> 'productId')::uuid as product_id,
      (item.value ->> 'quantity')::bigint as quantity,
      btrim(item.value ->> 'sourceLineRef') as source_line_ref
    from jsonb_array_elements(p_lines) with ordinality item(value, ordinality)
    order by (item.value ->> 'productId')::uuid, btrim(item.value ->> 'sourceLineRef')
  loop
    select marketplace_item.id, marketplace_item.product_sku_snapshot
    into v_order_item_id, v_product_sku
    from operations.marketplace_order_items marketplace_item
    where marketplace_item.organization_id = p_organization_id
      and marketplace_item.order_id = v_order_id
      and marketplace_item.product_id = v_line.product_id
      and marketplace_item.external_item_ref = v_line.source_line_ref;

    if not found then
      raise exception using errcode = 'P0001', message = 'RETURN_ORDER_ITEM_NOT_FOUND';
    end if;

    perform pg_advisory_xact_lock(
      hashtextextended(
        p_organization_id::text || ':RETURNABLE_ORDER_ITEM:' || v_order_item_id::text,
        0::bigint
      )
    );

    select coalesce(sum(allocation.quantity_allocated), 0)
    into v_shipped_qty
    from operations.marketplace_ship_allocations allocation
    join operations.marketplace_event_lines event_line
      on event_line.organization_id = allocation.organization_id
     and event_line.id = allocation.event_line_id
    where allocation.organization_id = p_organization_id
      and event_line.order_item_id = v_order_item_id;

    select coalesce(sum(return_item.expected_qty), 0)
    into v_already_expected
    from operations.return_items return_item
    where return_item.organization_id = p_organization_id
      and return_item.marketplace_order_item_id = v_order_item_id;

    if v_shipped_qty <= 0 then
      raise exception using errcode = 'P0001', message = 'RETURN_ITEM_NOT_SHIPPED';
    end if;

    if v_already_expected + v_line.quantity > v_shipped_qty then
      raise exception using errcode = 'P0001', message = 'RETURN_QUANTITY_EXCEEDS_SHIPPED';
    end if;

    v_return_item_id := gen_random_uuid();

    insert into operations.return_items (
      id,
      organization_id,
      return_id,
      line_no,
      marketplace_order_item_id,
      product_id,
      expected_qty,
      received_qty,
      sellable_qty,
      damaged_qty,
      lost_qty,
      product_sku_snapshot,
      source_line_ref,
      created_at,
      updated_at
    ) values (
      v_return_item_id,
      p_organization_id,
      v_return_id,
      v_line.line_no,
      v_order_item_id,
      v_line.product_id,
      v_line.quantity,
      0,
      0,
      0,
      0,
      v_product_sku,
      v_line.source_line_ref,
      v_recorded_at,
      v_recorded_at
    );

    insert into operations.return_event_lines (
      organization_id,
      event_id,
      return_item_id,
      line_no,
      quantity,
      outcome_code,
      source_line_ref,
      created_at
    ) values (
      p_organization_id,
      v_event_id,
      v_return_item_id,
      v_line.line_no,
      v_line.quantity,
      'EXPECTED',
      v_line.source_line_ref,
      v_recorded_at
    );

    v_total_quantity := v_total_quantity + v_line.quantity;
    v_line_results := v_line_results || jsonb_build_array(
      jsonb_build_object(
        'returnItemId', v_return_item_id,
        'marketplaceOrderItemId', v_order_item_id,
        'productId', v_line.product_id,
        'productSku', v_product_sku,
        'quantity', v_line.quantity,
        'sourceLineRef', v_line.source_line_ref
      )
    );
  end loop;

  perform operations.refresh_return_status(p_organization_id, v_return_id);

  v_response := jsonb_build_object(
    'status', 'EXPECTED',
    'returnId', v_return_id,
    'returnRef', v_return_ref,
    'orderId', v_order_id,
    'orderRef', v_order_ref,
    'channelCode', v_channel_code,
    'eventId', v_event_id,
    'lineCount', jsonb_array_length(p_lines),
    'totalQuantity', v_total_quantity,
    'occurredAt', p_occurred_at,
    'recordedAt', v_recorded_at,
    'lines', v_line_results
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

create or replace function api.mark_return_lost(
  p_organization_id uuid,
  p_idempotency_key text,
  p_return_ref text,
  p_event_ref text,
  p_occurred_at timestamptz,
  p_lines jsonb,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, inventory, operations, extensions
as $$
declare
  v_scope constant text := 'MARK_RETURN_LOST';
  v_idempotency_key text;
  v_return_ref text;
  v_event_ref text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_return_id uuid;
  v_event_id uuid := gen_random_uuid();
  v_command_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text := coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_line record;
  v_return_item operations.return_items%rowtype;
  v_pending_arrival bigint;
  v_total_quantity bigint := 0;
  v_status text;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  v_return_ref := btrim(coalesce(p_return_ref, ''));
  v_event_ref := btrim(coalesce(p_event_ref, ''));
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if v_return_ref = '' then
    raise exception using errcode = 'P0001', message = 'RETURN_REF_REQUIRED';
  end if;
  if v_event_ref = '' then
    raise exception using errcode = 'P0001', message = 'RETURN_EVENT_REF_REQUIRED';
  end if;
  if length(v_event_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'RETURN_EVENT_REF_TOO_LONG';
  end if;
  if p_occurred_at is null then
    raise exception using errcode = 'P0001', message = 'RETURN_OCCURRED_AT_REQUIRED';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) = 0 then
    raise exception using errcode = 'P0001', message = 'RETURN_LINES_REQUIRED';
  end if;
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'RETURN_METADATA_MUST_BE_OBJECT';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'RETURN_NOTE_TOO_LONG';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'returnItemId') is distinct from 'string'
       or (item.value ->> 'returnItemId') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'quantity') is distinct from 'number'
       or (item.value ->> 'quantity') !~ '^[1-9][0-9]{0,8}$'
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 100
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by lower(item.value ->> 'returnItemId')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_DUPLICATE_ITEM_LINE';
  end if;

  if v_jwt_role = 'anon'
     or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id then
      raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
    end if;
    v_process_name := null;
  else
    v_process_name := 'api.mark_return_lost';
  end if;

  select return_header.id
  into v_return_id
  from operations.returns return_header
  where return_header.organization_id = p_organization_id
    and return_header.external_return_ref = v_return_ref
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'RETURN_NOT_FOUND';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'returnRef', v_return_ref,
          'eventRef', v_event_ref,
          'occurredAt', p_occurred_at,
          'lines', p_lines,
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
      p_organization_id::text || ':' || v_scope || ':' || v_idempotency_key,
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
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REUSED';
    end if;
    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot;
    end if;
    if v_existing.status_code = 'STARTED' then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':RETURN_EVENT:' || v_event_ref,
      0::bigint
    )
  );

  if exists (
    select 1
    from operations.return_events event
    where event.organization_id = p_organization_id
      and event.external_event_ref = v_event_ref
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_EVENT_ALREADY_APPLIED';
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

  insert into operations.return_events (
    id,
    organization_id,
    return_id,
    external_event_ref,
    event_type_code,
    occurred_at,
    recorded_at,
    actor_user_id,
    process_name,
    transaction_id,
    idempotency_command_id,
    note,
    metadata,
    created_at
  ) values (
    v_event_id,
    p_organization_id,
    v_return_id,
    v_event_ref,
    'LOST',
    p_occurred_at,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    null,
    v_command_id,
    v_note,
    v_metadata,
    v_recorded_at
  );

  for v_line in
    select
      item.ordinality::integer as line_no,
      (item.value ->> 'returnItemId')::uuid as return_item_id,
      (item.value ->> 'quantity')::bigint as quantity,
      btrim(item.value ->> 'sourceLineRef') as source_line_ref
    from jsonb_array_elements(p_lines) with ordinality item(value, ordinality)
    order by (item.value ->> 'returnItemId')::uuid
  loop
    select item.*
    into v_return_item
    from operations.return_items item
    where item.organization_id = p_organization_id
      and item.return_id = v_return_id
      and item.id = v_line.return_item_id
    for update;

    if not found then
      raise exception using errcode = 'P0001', message = 'RETURN_ITEM_NOT_FOUND';
    end if;

    v_pending_arrival :=
      v_return_item.expected_qty -
      v_return_item.received_qty -
      v_return_item.lost_qty;

    if v_line.quantity > v_pending_arrival then
      raise exception using errcode = 'P0001', message = 'RETURN_LOST_EXCEEDS_PENDING';
    end if;

    insert into operations.return_event_lines (
      organization_id,
      event_id,
      return_item_id,
      line_no,
      quantity,
      outcome_code,
      source_line_ref,
      created_at
    ) values (
      p_organization_id,
      v_event_id,
      v_line.return_item_id,
      v_line.line_no,
      v_line.quantity,
      'LOST',
      v_line.source_line_ref,
      v_recorded_at
    );

    update operations.return_items item
    set lost_qty = item.lost_qty + v_line.quantity
    where item.id = v_line.return_item_id;

    v_total_quantity := v_total_quantity + v_line.quantity;
  end loop;

  perform operations.refresh_return_status(p_organization_id, v_return_id);

  select return_header.status_code
  into v_status
  from operations.returns return_header
  where return_header.id = v_return_id;

  v_response := jsonb_build_object(
    'status', v_status,
    'returnId', v_return_id,
    'returnRef', v_return_ref,
    'eventId', v_event_id,
    'eventRef', v_event_ref,
    'eventType', 'LOST',
    'lineCount', jsonb_array_length(p_lines),
    'totalQuantity', v_total_quantity,
    'occurredAt', p_occurred_at,
    'recordedAt', v_recorded_at
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

grant usage on schema api to authenticated, service_role;

revoke all on function api.create_expected_return(
  uuid,
  text,
  text,
  text,
  text,
  timestamptz,
  jsonb,
  text,
  text,
  jsonb
) from public, anon;

grant execute on function api.create_expected_return(
  uuid,
  text,
  text,
  text,
  text,
  timestamptz,
  jsonb,
  text,
  text,
  jsonb
) to authenticated, service_role;

revoke all on function api.mark_return_lost(
  uuid,
  text,
  text,
  text,
  timestamptz,
  jsonb,
  text,
  jsonb
) from public, anon;

grant execute on function api.mark_return_lost(
  uuid,
  text,
  text,
  text,
  timestamptz,
  jsonb,
  text,
  jsonb
) to authenticated, service_role;

commit;
