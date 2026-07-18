begin;

create or replace function api.confirm_return_receipt(
  p_organization_id uuid,
  p_idempotency_key text,
  p_return_ref text,
  p_receipt_ref text,
  p_occurred_at timestamptz,
  p_lines jsonb,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_scope constant text := 'CONFIRM_RETURN_RECEIPT';
  v_idempotency_key text;
  v_return_ref text;
  v_receipt_ref text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_return_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_event_id uuid := gen_random_uuid();
  v_receipt_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text := coalesce(
    auth.jwt() ->> 'role',
    current_setting('request.jwt.claim.role', true)
  );
  v_line record;
  v_return_item operations.return_items%rowtype;
  v_pending_arrival bigint;
  v_ship_allocation_id uuid;
  v_ship_allocation_qty bigint;
  v_ship_allocation_received bigint;
  v_source_batch_id uuid;
  v_source_batch_code text;
  v_source_expiry date;
  v_batch_identity_verified boolean;
  v_event_line_id uuid;
  v_receipt_line_id uuid;
  v_total_quantity bigint := 0;
  v_line_results jsonb := '[]'::jsonb;
  v_status text;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  v_return_ref := btrim(coalesce(p_return_ref, ''));
  v_receipt_ref := btrim(coalesce(p_receipt_ref, ''));
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if v_return_ref = '' then
    raise exception using errcode = 'P0001', message = 'RETURN_REF_REQUIRED';
  end if;
  if v_receipt_ref = '' then
    raise exception using errcode = 'P0001', message = 'RETURN_RECEIPT_REF_REQUIRED';
  end if;
  if length(v_receipt_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'RETURN_RECEIPT_REF_TOO_LONG';
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
  if v_note is not null and length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'RETURN_NOTE_TOO_LONG';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'returnItemId') is distinct from 'string'
       or (item.value ->> 'returnItemId')
            !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'quantity') is distinct from 'number'
       or (item.value ->> 'quantity') !~ '^[1-9][0-9]{0,8}$'
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 100
       or (
         item.value ? 'marketplaceShipAllocationId'
         and jsonb_typeof(item.value -> 'marketplaceShipAllocationId')
               not in ('string', 'null')
       )
       or (
         jsonb_typeof(item.value -> 'marketplaceShipAllocationId') = 'string'
         and (item.value ->> 'marketplaceShipAllocationId')
               !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       )
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_RECEIPT_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_DUPLICATE_SOURCE_LINE';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value -> 'marketplaceShipAllocationId') = 'string'
    group by lower(item.value ->> 'marketplaceShipAllocationId')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_DUPLICATE_SHIP_ALLOCATION';
  end if;

  perform 1
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
    v_process_name := 'api.confirm_return_receipt';
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
          'receiptRef', v_receipt_ref,
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
      p_organization_id::text || ':RETURN_RECEIPT_REF:' || v_receipt_ref,
      0::bigint
    )
  );

  if exists (
    select 1
    from operations.return_receipts receipt
    where receipt.organization_id = p_organization_id
      and receipt.receipt_ref = v_receipt_ref
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_RECEIPT_ALREADY_POSTED';
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
    v_receipt_ref,
    'RECEIPT',
    p_occurred_at,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    null,
    v_command_id,
    v_note,
    v_metadata || jsonb_build_object('stockEffectCode', 'NONE'),
    v_recorded_at
  );

  insert into operations.return_receipts (
    id,
    organization_id,
    return_id,
    event_id,
    receipt_ref,
    occurred_at,
    transaction_id,
    created_at,
    stock_effect_code
  ) values (
    v_receipt_id,
    p_organization_id,
    v_return_id,
    v_event_id,
    v_receipt_ref,
    p_occurred_at,
    null,
    v_recorded_at,
    'NONE'
  );

  for v_line in
    select
      item.ordinality::integer as line_no,
      (item.value ->> 'returnItemId')::uuid as return_item_id,
      (item.value ->> 'quantity')::bigint as quantity,
      btrim(item.value ->> 'sourceLineRef') as source_line_ref,
      case
        when jsonb_typeof(item.value -> 'marketplaceShipAllocationId') = 'string'
          then (item.value ->> 'marketplaceShipAllocationId')::uuid
        else null
      end as marketplace_ship_allocation_id
    from jsonb_array_elements(p_lines) with ordinality item(value, ordinality)
    order by (item.value ->> 'returnItemId')::uuid, item.ordinality
  loop
    select return_item.*
    into v_return_item
    from operations.return_items return_item
    where return_item.organization_id = p_organization_id
      and return_item.return_id = v_return_id
      and return_item.id = v_line.return_item_id
    for update;

    if not found then
      raise exception using errcode = 'P0001', message = 'RETURN_ITEM_NOT_FOUND';
    end if;

    v_pending_arrival :=
      v_return_item.expected_qty -
      v_return_item.received_qty -
      v_return_item.lost_qty;

    if v_line.quantity > v_pending_arrival then
      raise exception using errcode = 'P0001', message = 'RETURN_RECEIPT_EXCEEDS_PENDING';
    end if;

    v_ship_allocation_id := v_line.marketplace_ship_allocation_id;
    v_batch_identity_verified := false;
    v_source_batch_id := null;
    v_source_batch_code := null;
    v_source_expiry := null;

    if v_ship_allocation_id is not null then
      perform pg_advisory_xact_lock(
        hashtextextended(
          p_organization_id::text ||
          ':RETURN_SHIP_ALLOCATION:' ||
          v_ship_allocation_id::text,
          0::bigint
        )
      );

      select
        allocation.quantity_allocated,
        allocation.batch_id,
        allocation.batch_code_snapshot,
        allocation.expiry_date_snapshot
      into
        v_ship_allocation_qty,
        v_source_batch_id,
        v_source_batch_code,
        v_source_expiry
      from operations.marketplace_ship_allocations allocation
      join operations.marketplace_event_lines event_line
        on event_line.organization_id = allocation.organization_id
       and event_line.id = allocation.event_line_id
      join catalog.product_batches batch
        on batch.organization_id = allocation.organization_id
       and batch.product_id = allocation.product_id
       and batch.id = allocation.batch_id
      where allocation.organization_id = p_organization_id
        and allocation.id = v_ship_allocation_id
        and allocation.product_id = v_return_item.product_id
        and event_line.order_item_id = v_return_item.marketplace_order_item_id;

      if not found then
        raise exception using errcode = 'P0001', message = 'RETURN_SHIP_ALLOCATION_NOT_FOUND';
      end if;

      select coalesce(sum(receipt_line.quantity_received), 0)
      into v_ship_allocation_received
      from operations.return_receipt_lines receipt_line
      where receipt_line.organization_id = p_organization_id
        and receipt_line.marketplace_ship_allocation_id = v_ship_allocation_id;

      if v_ship_allocation_received + v_line.quantity > v_ship_allocation_qty then
        raise exception using errcode = 'P0001', message = 'RETURN_RECEIPT_EXCEEDS_SHIP_ALLOCATION';
      end if;

      v_batch_identity_verified := true;
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
      'RECEIVED',
      v_line.source_line_ref,
      v_recorded_at
    )
    returning id into v_event_line_id;

    v_receipt_line_id := gen_random_uuid();

    insert into operations.return_receipt_lines (
      id,
      organization_id,
      receipt_id,
      event_line_id,
      return_item_id,
      marketplace_ship_allocation_id,
      line_no,
      product_id,
      batch_id,
      quantity_received,
      batch_identity_verified,
      product_sku_snapshot,
      batch_code_snapshot,
      expiry_date_snapshot,
      source_line_ref,
      ledger_entry_id,
      created_at,
      stock_effect_code,
      source_batch_id,
      source_batch_code_snapshot,
      source_expiry_date_snapshot
    ) values (
      v_receipt_line_id,
      p_organization_id,
      v_receipt_id,
      v_event_line_id,
      v_line.return_item_id,
      v_ship_allocation_id,
      v_line.line_no,
      v_return_item.product_id,
      null,
      v_line.quantity,
      v_batch_identity_verified,
      v_return_item.product_sku_snapshot,
      null,
      null,
      v_line.source_line_ref,
      null,
      v_recorded_at,
      'NONE',
      v_source_batch_id,
      v_source_batch_code,
      v_source_expiry
    );

    update operations.return_items return_item
    set received_qty = return_item.received_qty + v_line.quantity
    where return_item.id = v_line.return_item_id;

    v_total_quantity := v_total_quantity + v_line.quantity;

    v_line_results := v_line_results || jsonb_build_array(
      jsonb_build_object(
        'receiptLineId', v_receipt_line_id,
        'returnItemId', v_line.return_item_id,
        'productId', v_return_item.product_id,
        'sourceBatchId', v_source_batch_id,
        'sourceBatchCode', v_source_batch_code,
        'sourceExpiryDate', v_source_expiry,
        'batchIdentityVerified', v_batch_identity_verified,
        'stockEffectCode', 'NONE',
        'quantity', v_line.quantity,
        'sourceLineRef', v_line.source_line_ref
      )
    );
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
    'receiptId', v_receipt_id,
    'receiptRef', v_receipt_ref,
    'eventId', v_event_id,
    'transactionId', null,
    'transactionNo', null,
    'stockEffectCode', 'NONE',
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
    result_transaction_id = null,
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

create or replace function api.inspect_return(
  p_organization_id uuid,
  p_idempotency_key text,
  p_return_ref text,
  p_inspection_ref text,
  p_occurred_at timestamptz,
  p_lines jsonb,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_scope constant text := 'INSPECT_RETURN';
  v_idempotency_key text;
  v_return_ref text;
  v_inspection_ref text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_timezone text;
  v_effective_local_date date;
  v_return_id uuid;
  v_channel_id uuid;
  v_channel_code text;
  v_reason_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_event_id uuid := gen_random_uuid();
  v_inspection_id uuid := gen_random_uuid();
  v_transaction_id uuid;
  v_transaction_no text;
  v_recorded_at timestamptz := clock_timestamp();
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_created_by_role_code text;
  v_jwt_role text := coalesce(
    auth.jwt() ->> 'role',
    current_setting('request.jwt.claim.role', true)
  );
  v_has_sellable boolean;
  v_stock_effect_code text;
  v_line record;
  v_receipt_line operations.return_receipt_lines%rowtype;
  v_already_inspected bigint;
  v_requested bigint;
  v_remaining bigint;
  v_event_line_id uuid;
  v_allocation_no integer := 0;
  v_ledger_line_no integer := 0;
  v_destination_ledger_id uuid;
  v_ledger_seq bigint;
  v_return_batch_id uuid;
  v_return_batch_code text;
  v_return_batch_expiry date;
  v_return_batch_status text;
  v_return_batch_kind text;
  v_total_quantity bigint := 0;
  v_total_sellable bigint := 0;
  v_total_damaged bigint := 0;
  v_line_results jsonb := '[]'::jsonb;
  v_status text;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  v_return_ref := btrim(coalesce(p_return_ref, ''));
  v_inspection_ref := btrim(coalesce(p_inspection_ref, ''));
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if v_return_ref = '' then
    raise exception using errcode = 'P0001', message = 'RETURN_REF_REQUIRED';
  end if;
  if v_inspection_ref = '' then
    raise exception using errcode = 'P0001', message = 'RETURN_INSPECTION_REF_REQUIRED';
  end if;
  if length(v_inspection_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'RETURN_INSPECTION_REF_TOO_LONG';
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
  if v_note is not null and length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'RETURN_NOTE_TOO_LONG';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'receiptLineId') is distinct from 'string'
       or (item.value ->> 'receiptLineId')
            !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'sellableQuantity') is distinct from 'number'
       or (item.value ->> 'sellableQuantity') !~ '^[0-9]{1,9}$'
       or jsonb_typeof(item.value -> 'damagedQuantity') is distinct from 'number'
       or (item.value ->> 'damagedQuantity') !~ '^[0-9]{1,9}$'
       or (
         (item.value ->> 'sellableQuantity')::bigint +
         (item.value ->> 'damagedQuantity')::bigint
       ) <= 0
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 100
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_INSPECTION_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by lower(item.value ->> 'receiptLineId')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_DUPLICATE_RECEIPT_LINE';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_DUPLICATE_SOURCE_LINE';
  end if;

  select exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where (item.value ->> 'sellableQuantity')::bigint > 0
  )
  into v_has_sellable;

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
    v_created_by_role_code := 'ADMIN';
  else
    v_process_name := 'api.inspect_return';
    v_created_by_role_code := 'SYSTEM_PROCESS';
  end if;

  select
    return_header.id,
    return_header.channel_id,
    channel.code
  into
    v_return_id,
    v_channel_id,
    v_channel_code
  from operations.returns return_header
  join catalog.channels channel
    on channel.id = return_header.channel_id
  where return_header.organization_id = p_organization_id
    and return_header.external_return_ref = v_return_ref
  for update of return_header;

  if not found then
    raise exception using errcode = 'P0001', message = 'RETURN_NOT_FOUND';
  end if;

  if v_has_sellable then
    select reason.id
    into v_reason_id
    from catalog.movement_reasons reason
    where reason.code = 'RETURN_SELLABLE'
      and reason.direction_code = 'INBOUND'
      and reason.is_active;

    if not found then
      raise exception using errcode = 'P0001', message = 'RETURN_SELLABLE_REASON_NOT_CONFIGURED';
    end if;
  end if;

  v_effective_local_date := (p_occurred_at at time zone v_timezone)::date;
  v_stock_effect_code :=
    case when v_has_sellable then 'SELLABLE_INBOUND' else 'NONE' end;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'returnRef', v_return_ref,
          'inspectionRef', v_inspection_ref,
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
      p_organization_id::text || ':RETURN_INSPECTION_REF:' || v_inspection_ref,
      0::bigint
    )
  );

  if exists (
    select 1
    from operations.return_inspections inspection
    where inspection.organization_id = p_organization_id
      and inspection.inspection_ref = v_inspection_ref
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_INSPECTION_ALREADY_POSTED';
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

  if v_has_sellable then
    v_transaction_id := gen_random_uuid();
    v_transaction_no :=
      'RTS-' ||
      to_char(v_effective_local_date, 'YYYYMMDD') ||
      '-' ||
      upper(substr(replace(v_inspection_id::text, '-', ''), 1, 8));

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
      note,
      metadata,
      schema_version
    ) values (
      v_transaction_id,
      p_organization_id,
      v_transaction_no,
      'RETURN_SELLABLE_INBOUND',
      v_reason_id,
      'RETURN_SELLABLE',
      v_channel_id,
      v_channel_code,
      'RETURN',
      v_return_id,
      v_inspection_ref,
      p_occurred_at,
      v_recorded_at,
      v_effective_local_date,
      v_actor_user_id,
      v_process_name,
      v_created_by_role_code,
      gen_random_uuid(),
      v_command_id,
      v_note,
      v_metadata || jsonb_build_object(
        'returnRef', v_return_ref,
        'stockEffectCode', v_stock_effect_code
      ),
      2
    );
  end if;

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
    v_inspection_ref,
    'INSPECTION',
    p_occurred_at,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    v_transaction_id,
    v_command_id,
    v_note,
    v_metadata || jsonb_build_object('stockEffectCode', v_stock_effect_code),
    v_recorded_at
  );

  insert into operations.return_inspections (
    id,
    organization_id,
    return_id,
    event_id,
    inspection_ref,
    occurred_at,
    transaction_id,
    created_at,
    stock_effect_code
  ) values (
    v_inspection_id,
    p_organization_id,
    v_return_id,
    v_event_id,
    v_inspection_ref,
    p_occurred_at,
    v_transaction_id,
    v_recorded_at,
    v_stock_effect_code
  );

  for v_line in
    select
      item.ordinality::integer as line_no,
      (item.value ->> 'receiptLineId')::uuid as receipt_line_id,
      (item.value ->> 'sellableQuantity')::bigint as sellable_quantity,
      (item.value ->> 'damagedQuantity')::bigint as damaged_quantity,
      btrim(item.value ->> 'sourceLineRef') as source_line_ref
    from jsonb_array_elements(p_lines) with ordinality item(value, ordinality)
    order by (item.value ->> 'receiptLineId')::uuid
  loop
    v_return_batch_id := null;
    v_return_batch_code := null;
    v_return_batch_expiry := null;
    v_return_batch_status := null;
    v_return_batch_kind := null;
    v_destination_ledger_id := null;

    perform pg_advisory_xact_lock(
      hashtextextended(
        p_organization_id::text ||
        ':RETURN_RECEIPT_LINE:' ||
        v_line.receipt_line_id::text,
        0::bigint
      )
    );

    select receipt_line.*
    into v_receipt_line
    from operations.return_receipt_lines receipt_line
    join operations.return_items return_item
      on return_item.organization_id = receipt_line.organization_id
     and return_item.id = receipt_line.return_item_id
    where receipt_line.organization_id = p_organization_id
      and receipt_line.id = v_line.receipt_line_id
      and return_item.return_id = v_return_id
    for update of receipt_line;

    if not found then
      raise exception using errcode = 'P0001', message = 'RETURN_RECEIPT_LINE_NOT_FOUND';
    end if;

    select coalesce(sum(allocation.quantity_allocated), 0)
    into v_already_inspected
    from operations.return_inspection_allocations allocation
    where allocation.organization_id = p_organization_id
      and allocation.receipt_line_id = v_line.receipt_line_id;

    v_requested := v_line.sellable_quantity + v_line.damaged_quantity;
    v_remaining := v_receipt_line.quantity_received - v_already_inspected;

    if v_requested > v_remaining then
      raise exception using errcode = 'P0001', message = 'RETURN_INSPECTION_EXCEEDS_RECEIVED';
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
      v_receipt_line.return_item_id,
      v_line.line_no,
      v_requested,
      case
        when v_line.sellable_quantity > 0
         and v_line.damaged_quantity > 0 then 'MIXED'
        when v_line.sellable_quantity > 0 then 'SELLABLE'
        else 'DAMAGED'
      end,
      v_line.source_line_ref,
      v_recorded_at
    )
    returning id into v_event_line_id;

    if v_line.sellable_quantity > 0 then
      if not v_receipt_line.batch_identity_verified
         or v_receipt_line.source_batch_id is null
         or v_receipt_line.source_batch_code_snapshot is null
         or v_receipt_line.source_expiry_date_snapshot is null then
        raise exception using
          errcode = 'P0001',
          message = 'RETURN_BATCH_IDENTITY_REQUIRED_FOR_SELLABLE';
      end if;

      if v_receipt_line.source_expiry_date_snapshot < v_effective_local_date then
        raise exception using
          errcode = 'P0001',
          message = 'RETURN_SOURCE_BATCH_EXPIRED_FOR_SELLABLE';
      end if;

      select
        provenance.batch_id,
        batch.batch_code,
        batch.expiry_date,
        batch.status_code,
        batch.batch_kind_code
      into
        v_return_batch_id,
        v_return_batch_code,
        v_return_batch_expiry,
        v_return_batch_status,
        v_return_batch_kind
      from operations.return_stock_batches provenance
      join catalog.product_batches batch
        on batch.organization_id = provenance.organization_id
       and batch.product_id = provenance.product_id
       and batch.id = provenance.batch_id
      where provenance.organization_id = p_organization_id
        and provenance.receipt_line_id = v_line.receipt_line_id
      for update of batch;

      if not found then
        v_return_batch_id := gen_random_uuid();
        v_return_batch_code :=
          'RET-' ||
          upper(replace(v_receipt_line.id::text, '-', ''));
        v_return_batch_expiry :=
          v_receipt_line.source_expiry_date_snapshot;
        v_return_batch_status := 'ACTIVE';
        v_return_batch_kind := 'RETURN';

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
          row_version,
          batch_kind_code
        ) values (
          v_return_batch_id,
          p_organization_id,
          v_receipt_line.product_id,
          v_return_batch_code,
          null,
          v_return_batch_expiry,
          p_occurred_at,
          'ACTIVE',
          null,
          v_recorded_at,
          v_actor_user_id,
          v_recorded_at,
          v_actor_user_id,
          1,
          'RETURN'
        );

        insert into operations.return_stock_batches (
          organization_id,
          return_id,
          return_item_id,
          receipt_line_id,
          created_from_inspection_id,
          product_id,
          batch_id,
          source_batch_id,
          source_batch_code_snapshot,
          source_expiry_date_snapshot,
          created_at
        ) values (
          p_organization_id,
          v_return_id,
          v_receipt_line.return_item_id,
          v_line.receipt_line_id,
          v_inspection_id,
          v_receipt_line.product_id,
          v_return_batch_id,
          v_receipt_line.source_batch_id,
          v_receipt_line.source_batch_code_snapshot,
          v_receipt_line.source_expiry_date_snapshot,
          v_recorded_at
        );
      else
        if v_return_batch_kind <> 'RETURN' then
          raise exception using
            errcode = 'P0001',
            message = 'RETURN_BATCH_KIND_INVALID';
        end if;
        if v_return_batch_status <> 'ACTIVE' then
          raise exception using
            errcode = 'P0001',
            message = 'RETURN_BATCH_NOT_ACTIVE_FOR_SELLABLE';
        end if;
        if v_return_batch_expiry < v_effective_local_date then
          raise exception using
            errcode = 'P0001',
            message = 'RETURN_BATCH_EXPIRED_FOR_SELLABLE';
        end if;
      end if;

      v_ledger_line_no := v_ledger_line_no + 1;

      insert into inventory.stock_ledger_entries (
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
      ) values (
        p_organization_id,
        v_transaction_id,
        v_ledger_line_no,
        v_receipt_line.product_id,
        v_return_batch_id,
        v_receipt_line.product_sku_snapshot,
        v_return_batch_code,
        v_return_batch_expiry,
        'SELLABLE',
        v_line.sellable_quantity,
        'EXTERNAL_IN',
        null,
        v_line.source_line_ref || ':SELLABLE',
        p_occurred_at,
        v_recorded_at,
        v_recorded_at
      )
      returning id, ledger_seq
      into v_destination_ledger_id, v_ledger_seq;

      v_allocation_no := v_allocation_no + 1;

      insert into operations.return_inspection_allocations (
        organization_id,
        inspection_id,
        event_line_id,
        receipt_line_id,
        allocation_no,
        destination_bucket_code,
        quantity_allocated,
        pair_no,
        source_ledger_entry_id,
        destination_ledger_entry_id,
        created_at,
        condition_code,
        stock_effect_code,
        return_batch_id
      ) values (
        p_organization_id,
        v_inspection_id,
        v_event_line_id,
        v_line.receipt_line_id,
        v_allocation_no,
        'SELLABLE',
        v_line.sellable_quantity,
        null,
        null,
        v_destination_ledger_id,
        v_recorded_at,
        'SELLABLE',
        'SELLABLE_INBOUND',
        v_return_batch_id
      );

      insert into inventory.stock_batch_balances as current_batch_balance (
        organization_id,
        batch_id,
        product_id,
        sellable_qty,
        quarantine_qty,
        damaged_qty,
        last_ledger_seq,
        updated_at,
        version
      ) values (
        p_organization_id,
        v_return_batch_id,
        v_receipt_line.product_id,
        v_line.sellable_quantity,
        0,
        0,
        v_ledger_seq,
        v_recorded_at,
        1
      )
      on conflict (organization_id, batch_id) do update
      set
        product_id = excluded.product_id,
        sellable_qty =
          current_batch_balance.sellable_qty +
          excluded.sellable_qty,
        last_ledger_seq = greatest(
          current_batch_balance.last_ledger_seq,
          excluded.last_ledger_seq
        ),
        updated_at = excluded.updated_at,
        version = current_batch_balance.version + 1;

      insert into inventory.stock_product_positions as current_product_position (
        organization_id,
        product_id,
        sellable_qty,
        quarantine_qty,
        damaged_qty,
        reserved_qty,
        last_ledger_seq,
        updated_at,
        version
      ) values (
        p_organization_id,
        v_receipt_line.product_id,
        v_line.sellable_quantity,
        0,
        0,
        0,
        v_ledger_seq,
        v_recorded_at,
        1
      )
      on conflict (organization_id, product_id) do update
      set
        sellable_qty =
          current_product_position.sellable_qty +
          excluded.sellable_qty,
        last_ledger_seq = greatest(
          current_product_position.last_ledger_seq,
          excluded.last_ledger_seq
        ),
        updated_at = excluded.updated_at,
        version = current_product_position.version + 1;
    end if;

    if v_line.damaged_quantity > 0 then
      v_allocation_no := v_allocation_no + 1;

      insert into operations.return_inspection_allocations (
        organization_id,
        inspection_id,
        event_line_id,
        receipt_line_id,
        allocation_no,
        destination_bucket_code,
        quantity_allocated,
        pair_no,
        source_ledger_entry_id,
        destination_ledger_entry_id,
        created_at,
        condition_code,
        stock_effect_code,
        return_batch_id
      ) values (
        p_organization_id,
        v_inspection_id,
        v_event_line_id,
        v_line.receipt_line_id,
        v_allocation_no,
        null,
        v_line.damaged_quantity,
        null,
        null,
        null,
        v_recorded_at,
        'DAMAGED',
        'NONE',
        null
      );
    end if;

    update operations.return_items return_item
    set
      sellable_qty =
        return_item.sellable_qty +
        v_line.sellable_quantity,
      damaged_qty =
        return_item.damaged_qty +
        v_line.damaged_quantity
    where return_item.id = v_receipt_line.return_item_id;

    v_total_quantity := v_total_quantity + v_requested;
    v_total_sellable :=
      v_total_sellable + v_line.sellable_quantity;
    v_total_damaged :=
      v_total_damaged + v_line.damaged_quantity;

    v_line_results := v_line_results || jsonb_build_array(
      jsonb_build_object(
        'receiptLineId', v_line.receipt_line_id,
        'returnItemId', v_receipt_line.return_item_id,
        'sellableQuantity', v_line.sellable_quantity,
        'damagedQuantity', v_line.damaged_quantity,
        'returnBatchId', v_return_batch_id,
        'returnBatchCode', v_return_batch_code,
        'stockEffectCode',
          case
            when v_line.sellable_quantity > 0
              then 'SELLABLE_INBOUND'
            else 'NONE'
          end,
        'sourceLineRef', v_line.source_line_ref
      )
    );
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
    'inspectionId', v_inspection_id,
    'inspectionRef', v_inspection_ref,
    'eventId', v_event_id,
    'transactionId', v_transaction_id,
    'transactionNo', v_transaction_no,
    'stockEffectCode', v_stock_effect_code,
    'lineCount', jsonb_array_length(p_lines),
    'allocationCount', v_allocation_no,
    'totalQuantity', v_total_quantity,
    'sellableQuantity', v_total_sellable,
    'damagedQuantity', v_total_damaged,
    'occurredAt', p_occurred_at,
    'recordedAt', v_recorded_at,
    'lines', v_line_results
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    result_transaction_id = v_transaction_id,
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

create or replace view api.return_receipt_lines
with (security_invoker = true)
as
select
  line.id as receipt_line_id,
  line.organization_id,
  receipt.return_id,
  line.receipt_id,
  receipt.receipt_ref,
  line.return_item_id,
  line.marketplace_ship_allocation_id,
  line.line_no,
  line.product_id,
  line.batch_id,
  line.quantity_received,
  line.batch_identity_verified,
  line.product_sku_snapshot,
  line.batch_code_snapshot,
  line.expiry_date_snapshot,
  line.source_line_ref,
  line.ledger_entry_id,
  receipt.occurred_at,
  line.created_at,
  line.stock_effect_code,
  line.source_batch_id,
  line.source_batch_code_snapshot,
  line.source_expiry_date_snapshot
from operations.return_receipt_lines line
join operations.return_receipts receipt
  on receipt.organization_id = line.organization_id
 and receipt.id = line.receipt_id;

create or replace view api.return_inspection_allocations
with (security_invoker = true)
as
select
  allocation.id as inspection_allocation_id,
  allocation.organization_id,
  inspection.return_id,
  allocation.inspection_id,
  inspection.inspection_ref,
  allocation.receipt_line_id,
  allocation.allocation_no,
  allocation.destination_bucket_code,
  allocation.quantity_allocated,
  allocation.pair_no,
  allocation.source_ledger_entry_id,
  allocation.destination_ledger_entry_id,
  inspection.occurred_at,
  allocation.created_at,
  allocation.condition_code,
  allocation.stock_effect_code,
  allocation.return_batch_id
from operations.return_inspection_allocations allocation
join operations.return_inspections inspection
  on inspection.organization_id = allocation.organization_id
 and inspection.id = allocation.inspection_id;

revoke all on function api.confirm_return_receipt(
  uuid,
  text,
  text,
  text,
  timestamptz,
  jsonb,
  text,
  jsonb
) from public, anon;

grant execute on function api.confirm_return_receipt(
  uuid,
  text,
  text,
  text,
  timestamptz,
  jsonb,
  text,
  jsonb
) to authenticated, service_role;

revoke all on function api.inspect_return(
  uuid,
  text,
  text,
  text,
  timestamptz,
  jsonb,
  text,
  jsonb
) from public, anon;

grant execute on function api.inspect_return(
  uuid,
  text,
  text,
  text,
  timestamptz,
  jsonb,
  text,
  jsonb
) to authenticated, service_role;

revoke all on api.return_receipt_lines,
              api.return_inspection_allocations
from anon;

grant select on api.return_receipt_lines,
                api.return_inspection_allocations
to authenticated, service_role;

commit;
