begin;

create or replace function api.post_receipt(
  p_organization_id uuid,
  p_idempotency_key text,
  p_source_ref text,
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
  v_scope constant text := 'POST_RECEIPT';
  v_idempotency_key text;
  v_source_ref text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_organization_timezone text;
  v_effective_local_date date;
  v_reason_id uuid;
  v_channel_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_receipt_id uuid := gen_random_uuid();
  v_transaction_id uuid := gen_random_uuid();
  v_correlation_id uuid := gen_random_uuid();
  v_receipt_no text;
  v_recorded_at timestamptz := clock_timestamp();
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_created_by_role_code text;
  v_jwt_role text := coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_line record;
  v_product_sku text;
  v_product_active boolean;
  v_batch_code text;
  v_batch_expiry_date date;
  v_batch_status text;
  v_batch_kind text;
  v_target_batch_id uuid;
  v_norm_batch_code text;
  v_audit_cmd_id uuid;
  v_audit_id uuid;
  v_new_batch catalog.product_batches%rowtype;
  v_ledger_seq bigint;
  v_total_quantity bigint := 0;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_source_ref := btrim(coalesce(p_source_ref, ''));
  if v_source_ref = '' then
    raise exception using errcode = 'P0001', message = 'RECEIPT_SOURCE_REQUIRED';
  end if;
  if length(v_source_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'RECEIPT_SOURCE_TOO_LONG';
  end if;

  if p_occurred_at is null then
    raise exception using errcode = 'P0001', message = 'RECEIPT_OCCURRED_AT_REQUIRED';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception using errcode = 'P0001', message = 'RECEIPT_LINES_MUST_BE_ARRAY';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    raise exception using errcode = 'P0001', message = 'RECEIPT_LINES_REQUIRED';
  end if;
  if jsonb_array_length(p_lines) > 500 then
    raise exception using errcode = 'P0001', message = 'RECEIPT_LINES_LIMIT_EXCEEDED';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'RECEIPT_METADATA_MUST_BE_OBJECT';
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');
  if v_note is not null and length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'RECEIPT_NOTE_TOO_LONG';
  end if;

  -- Validate line structure
  if exists (
    select 1
    from jsonb_array_elements(p_lines) as item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'productId') is distinct from 'string'
       or (item.value ->> 'productId') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'quantity') is distinct from 'number'
       or (item.value ->> 'quantity') !~ '^[1-9][0-9]{0,8}$'
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 100
       or (
         -- Either batchId must be a valid UUID
         not (
           item.value -> 'batchId' is not null
           and jsonb_typeof(item.value -> 'batchId') = 'string'
           and (item.value ->> 'batchId') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         )
         -- OR batchCode (non-empty string <= 100 chars) AND expiryDate (YYYY-MM-DD string) must be valid
         and not (
           item.value -> 'batchCode' is not null
           and jsonb_typeof(item.value -> 'batchCode') = 'string'
           and btrim(item.value ->> 'batchCode') <> ''
           and length(btrim(item.value ->> 'batchCode')) <= 100
           and item.value -> 'expiryDate' is not null
           and jsonb_typeof(item.value -> 'expiryDate') = 'string'
           and (item.value ->> 'expiryDate') ~ '^\d{4}-\d{2}-\d{2}$'
         )
       )
  ) then
    raise exception using errcode = 'P0001', message = 'RECEIPT_LINE_INVALID';
  end if;

  -- Validate line duplicates (either by batchId or by product_id:normalized_batch_code)
  if exists (
    select 1
    from jsonb_array_elements(p_lines) as item(value)
    group by
      (item.value ->> 'productId'),
      coalesce(
        lower(nullif(btrim(item.value ->> 'batchId'), '')),
        catalog.normalize_master_identifier(coalesce(item.value ->> 'batchCode', ''))
      )
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'RECEIPT_DUPLICATE_BATCH_LINE';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) as item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'RECEIPT_DUPLICATE_SOURCE_LINE';
  end if;

  select organization.timezone
  into v_organization_timezone
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
    v_process_name := 'api.post_receipt';
    v_created_by_role_code := 'SYSTEM_PROCESS';
  end if;

  v_effective_local_date := (p_occurred_at at time zone v_organization_timezone)::date;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'sourceRef', v_source_ref,
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
      p_organization_id::text || ':RECEIPT_SOURCE:' || v_source_ref,
      0::bigint
    )
  );

  if exists (
    select 1
    from operations.receipts receipt
    where receipt.organization_id = p_organization_id
      and receipt.source_ref = v_source_ref
  ) then
    raise exception using errcode = 'P0001', message = 'RECEIPT_SOURCE_ALREADY_POSTED';
  end if;

  select reason.id
  into v_reason_id
  from catalog.movement_reasons reason
  where reason.code = 'MAKLON_RECEIPT'
    and reason.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'RECEIPT_REASON_NOT_CONFIGURED';
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = 'MANUAL'
    and channel.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'RECEIPT_CHANNEL_NOT_CONFIGURED';
  end if;

  v_receipt_no :=
    'RCV-' ||
    to_char(v_effective_local_date, 'YYYYMMDD') ||
    '-' ||
    upper(substr(replace(v_receipt_id::text, '-', ''), 1, 8));

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
    v_command_id,
    p_organization_id,
    v_scope,
    v_idempotency_key,
    v_request_hash,
    'STARTED',
    v_recorded_at,
    null,
    null,
    '{}'::jsonb,
    null,
    null
  );

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
    v_transaction_id,
    p_organization_id,
    v_receipt_no,
    'RECEIPT',
    v_reason_id,
    'MAKLON_RECEIPT',
    v_channel_id,
    'MANUAL',
    'RECEIPT',
    v_receipt_id,
    v_source_ref,
    p_occurred_at,
    v_recorded_at,
    v_effective_local_date,
    v_actor_user_id,
    v_process_name,
    v_created_by_role_code,
    v_correlation_id,
    v_command_id,
    null,
    v_note,
    v_metadata || jsonb_build_object('receiptNo', v_receipt_no),
    1
  );

  insert into operations.receipts (
    id,
    organization_id,
    receipt_no,
    source_ref,
    status_code,
    occurred_at,
    recorded_at,
    actor_user_id,
    process_name,
    transaction_id,
    idempotency_command_id,
    note,
    metadata,
    created_at
  )
  values (
    v_receipt_id,
    p_organization_id,
    v_receipt_no,
    v_source_ref,
    'POSTED',
    p_occurred_at,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    v_transaction_id,
    v_command_id,
    v_note,
    v_metadata,
    v_recorded_at
  );

  for v_line in
    select
      item.ordinality::integer as line_no,
      (item.value ->> 'productId')::uuid as product_id,
      nullif(btrim(item.value ->> 'batchId'), '')::uuid as batch_id,
      nullif(btrim(item.value ->> 'batchCode'), '') as batch_code_input,
      (item.value ->> 'expiryDate')::date as expiry_date_input,
      (item.value ->> 'manufacturedDate')::date as manufactured_date_input,
      (item.value ->> 'quantity')::bigint as quantity_received,
      btrim(item.value ->> 'sourceLineRef') as source_line_ref
    from jsonb_array_elements(p_lines) with ordinality as item(value, ordinality)
    order by coalesce(
      item.value ->> 'batchId',
      item.value ->> 'batchCode'
    )
  loop
    v_product_sku := null;
    v_product_active := null;
    v_batch_code := null;
    v_batch_expiry_date := null;
    v_batch_status := null;
    v_batch_kind := null;
    v_target_batch_id := null;

    if v_line.batch_id is not null then
      -- Mode Existing Batch
      select
        product.sku,
        product.is_active,
        batch.id,
        batch.batch_code,
        batch.expiry_date,
        batch.status_code,
        batch.batch_kind_code
      into
        v_product_sku,
        v_product_active,
        v_target_batch_id,
        v_batch_code,
        v_batch_expiry_date,
        v_batch_status,
        v_batch_kind
      from catalog.products product
      join catalog.product_batches batch
        on batch.organization_id = product.organization_id
       and batch.product_id = product.id
      where product.organization_id = p_organization_id
        and product.id = v_line.product_id
        and batch.id = v_line.batch_id
      for update of product, batch;

      if not found then
        raise exception using errcode = 'P0001', message = 'RECEIPT_LINE_MASTER_NOT_FOUND';
      end if;

      if not v_product_active then
        raise exception using errcode = 'P0001', message = 'RECEIPT_PRODUCT_INACTIVE';
      end if;

      if v_batch_status <> 'ACTIVE' then
        raise exception using errcode = 'P0001', message = 'RECEIPT_BATCH_NOT_ACTIVE';
      end if;

      if v_batch_expiry_date < v_effective_local_date then
        raise exception using errcode = 'P0001', message = 'RECEIPT_BATCH_EXPIRED';
      end if;

      if v_batch_kind <> 'STANDARD' then
        raise exception using errcode = 'P0001', message = 'RECEIPT_BATCH_KIND_INVALID';
      end if;

    else
      -- Mode New Batch inline
      if v_line.batch_code_input is null or v_line.expiry_date_input is null then
        raise exception using errcode = 'P0001', message = 'RECEIPT_LINE_INVALID';
      end if;

      if v_line.manufactured_date_input is not null
         and v_line.manufactured_date_input > v_line.expiry_date_input then
        raise exception using errcode = 'P0001', message = 'INVALID_BATCH_DATE_RANGE';
      end if;

      if v_line.expiry_date_input < v_effective_local_date then
        raise exception using errcode = 'P0001', message = 'RECEIPT_BATCH_EXPIRED';
      end if;

      select product.sku, product.is_active
      into v_product_sku, v_product_active
      from catalog.products product
      where product.organization_id = p_organization_id
        and product.id = v_line.product_id
      for update;

      if not found then
        raise exception using errcode = 'P0001', message = 'RECEIPT_LINE_MASTER_NOT_FOUND';
      end if;

      if not v_product_active then
        raise exception using errcode = 'P0001', message = 'RECEIPT_PRODUCT_INACTIVE';
      end if;

      v_norm_batch_code := catalog.normalize_master_identifier(v_line.batch_code_input);

      perform pg_advisory_xact_lock(
        hashtextextended(
          p_organization_id::text ||
          ':PRODUCT_BATCH:' ||
          v_line.product_id::text ||
          ':' ||
          v_norm_batch_code,
          0::bigint
        )
      );

      select batch.id, batch.batch_code, batch.expiry_date, batch.status_code, batch.batch_kind_code
      into v_target_batch_id, v_batch_code, v_batch_expiry_date, v_batch_status, v_batch_kind
      from catalog.product_batches batch
      where batch.organization_id = p_organization_id
        and batch.product_id = v_line.product_id
        and catalog.normalize_master_identifier(batch.batch_code) = v_norm_batch_code
      for update;

      if found then
        -- Batch existing ditemukan dengan kode yang sama
        if v_batch_status <> 'ACTIVE' then
          raise exception using errcode = 'P0001', message = 'RECEIPT_BATCH_NOT_ACTIVE';
        end if;
        if v_batch_expiry_date < v_effective_local_date then
          raise exception using errcode = 'P0001', message = 'RECEIPT_BATCH_EXPIRED';
        end if;
        if v_batch_kind <> 'STANDARD' then
          raise exception using errcode = 'P0001', message = 'RECEIPT_BATCH_KIND_INVALID';
        end if;
      else
        -- Buat batch baru secara atomik
        v_target_batch_id := gen_random_uuid();
        v_batch_code := v_line.batch_code_input;
        v_batch_expiry_date := v_line.expiry_date_input;

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
          v_target_batch_id,
          p_organization_id,
          v_line.product_id,
          v_batch_code,
          v_line.manufactured_date_input,
          v_batch_expiry_date,
          p_occurred_at,
          'ACTIVE',
          null,
          v_recorded_at,
          v_actor_user_id,
          v_recorded_at,
          v_actor_user_id,
          1,
          'STANDARD'
        )
        returning * into v_new_batch;

        v_audit_cmd_id := gen_random_uuid();
        insert into inventory.idempotency_commands (
          id,
          organization_id,
          scope,
          key,
          request_hash,
          status_code,
          started_at,
          completed_at,
          response_snapshot
        ) values (
          v_audit_cmd_id,
          p_organization_id,
          'BATCH_CREATE_INLINE',
          'batch-inline:' || v_command_id::text || ':' || v_line.line_no::text,
          encode(extensions.digest(convert_to(v_target_batch_id::text, 'UTF8'), 'sha256'), 'hex'),
          'SUCCEEDED',
          v_recorded_at,
          v_recorded_at,
          '{}'::jsonb
        );

        v_audit_id := catalog.record_master_data_audit(
          p_organization_id,
          'BATCH',
          v_target_batch_id,
          'BATCH_CREATE',
          v_audit_cmd_id,
          null,
          catalog.product_batch_master_snapshot(v_new_batch),
          null,
          'Dibuat otomatis dari penerimaan barang masuk',
          v_actor_user_id,
          v_process_name,
          v_recorded_at
        );
      end if;
    end if;

    update catalog.product_batches batch
    set
      received_first_at = p_occurred_at,
      updated_by = coalesce(v_actor_user_id, batch.updated_by)
    where batch.id = v_target_batch_id
      and batch.organization_id = p_organization_id
      and (
        batch.received_first_at is null
        or batch.received_first_at > p_occurred_at
      );

    insert into operations.receipt_lines (
      organization_id,
      receipt_id,
      line_no,
      product_id,
      batch_id,
      quantity_received,
      product_sku_snapshot,
      batch_code_snapshot,
      expiry_date_snapshot,
      source_line_ref,
      created_at
    )
    values (
      p_organization_id,
      v_receipt_id,
      v_line.line_no,
      v_line.product_id,
      v_target_batch_id,
      v_line.quantity_received,
      v_product_sku,
      v_batch_code,
      v_batch_expiry_date,
      v_line.source_line_ref,
      v_recorded_at
    );

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
    )
    values (
      p_organization_id,
      v_transaction_id,
      v_line.line_no,
      v_line.product_id,
      v_target_batch_id,
      v_product_sku,
      v_batch_code,
      v_batch_expiry_date,
      'SELLABLE',
      v_line.quantity_received,
      'EXTERNAL_IN',
      null,
      v_line.source_line_ref,
      p_occurred_at,
      v_recorded_at,
      v_recorded_at
    )
    returning ledger_seq into v_ledger_seq;

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
    )
    values (
      p_organization_id,
      v_target_batch_id,
      v_line.product_id,
      v_line.quantity_received,
      0,
      0,
      v_ledger_seq,
      v_recorded_at,
      1
    )
    on conflict (organization_id, batch_id) do update
    set
      product_id = excluded.product_id,
      sellable_qty = current_batch_balance.sellable_qty + excluded.sellable_qty,
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
    )
    values (
      p_organization_id,
      v_line.product_id,
      v_line.quantity_received,
      0,
      0,
      0,
      v_ledger_seq,
      v_recorded_at,
      1
    )
    on conflict (organization_id, product_id) do update
    set
      sellable_qty = current_product_position.sellable_qty + excluded.sellable_qty,
      last_ledger_seq = greatest(
        current_product_position.last_ledger_seq,
        excluded.last_ledger_seq
      ),
      updated_at = excluded.updated_at,
      version = current_product_position.version + 1;

    v_total_quantity := v_total_quantity + v_line.quantity_received;
  end loop;

  v_response := jsonb_build_object(
    'status', 'POSTED',
    'receiptId', v_receipt_id,
    'receiptNo', v_receipt_no,
    'transactionId', v_transaction_id,
    'transactionNo', v_receipt_no,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'lineCount', jsonb_array_length(p_lines),
    'totalQuantity', v_total_quantity,
    'occurredAt', p_occurred_at,
    'recordedAt', v_recorded_at
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

commit;
