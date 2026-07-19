begin;

create or replace function inventory.preview_manual_outbound_core(
  p_organization_id uuid,
  p_source_ref text,
  p_occurred_at timestamptz,
  p_reason_code text,
  p_lines jsonb,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_lock_basis boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text :=
    coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_source_ref text;
  v_reason_code text;
  v_note text;
  v_metadata jsonb;
  v_reference text;
  v_organization_timezone text;
  v_effective_local_date date;
  v_safety_buffer_days integer := 0;
  v_reason_id uuid;
  v_reason_name text;
  v_reason_requires_note boolean;
  v_channel_id uuid;
  v_total_quantity bigint;
  v_normalized_lines jsonb;
  v_request_payload jsonb;
  v_request_hash text;
  v_source_already_posted boolean;
  v_line record;
  v_batch record;
  v_product_sku text;
  v_product_name text;
  v_product_active boolean;
  v_product_batch_tracked boolean;
  v_product_expiry_tracked boolean;
  v_product_row_version bigint;
  v_product_found boolean;
  v_position_found boolean;
  v_product_sellable bigint;
  v_product_reserved bigint;
  v_product_available bigint;
  v_position_version bigint;
  v_position_last_ledger_seq bigint;
  v_remaining bigint;
  v_allocate bigint;
  v_allocation_no integer;
  v_eligible_total bigint;
  v_batch_basis jsonb;
  v_line_allocations jsonb;
  v_products jsonb := '[]'::jsonb;
  v_allocations jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_basis_products jsonb := '[]'::jsonb;
  v_authoritative_basis jsonb;
  v_basis_hash text;
  v_eligible boolean;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_REQUIRED';
  end if;

  v_source_ref := btrim(coalesce(p_source_ref, ''));

  if v_source_ref = '' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_SOURCE_REQUIRED';
  end if;

  if length(v_source_ref) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_SOURCE_TOO_LONG';
  end if;

  v_reason_code := upper(btrim(coalesce(p_reason_code, '')));

  if v_reason_code = '' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_REASON_REQUIRED';
  end if;

  if length(v_reason_code) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_REASON_TOO_LONG';
  end if;

  if p_occurred_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_OCCURRED_AT_REQUIRED';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_LINES_MUST_BE_ARRAY';
  end if;

  if jsonb_array_length(p_lines) = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_LINES_REQUIRED';
  end if;

  if jsonb_array_length(p_lines) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_LINES_LIMIT_EXCEEDED';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_METADATA_MUST_BE_OBJECT';
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');

  if v_note is not null and length(v_note) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_NOTE_TOO_LONG';
  end if;

  v_reference := nullif(btrim(coalesce(v_metadata ->> 'reference', '')), '');

  if v_reference is not null and length(v_reference) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_REFERENCE_TOO_LONG';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) as item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'productId') is distinct from 'string'
       or (item.value ->> 'productId')
            !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'quantity') is distinct from 'number'
       or (item.value ->> 'quantity') !~ '^[1-9][0-9]{0,8}$'
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 100
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) as item(value)
    group by lower(item.value ->> 'productId')
    having count(*) > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_DUPLICATE_PRODUCT_LINE';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) as item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_DUPLICATE_SOURCE_LINE';
  end if;

  select
    jsonb_agg(
      jsonb_build_object(
        'lineNo', item.ordinality::integer,
        'productId', (item.value ->> 'productId')::uuid,
        'quantity', (item.value ->> 'quantity')::bigint,
        'sourceLineRef', btrim(item.value ->> 'sourceLineRef')
      )
      order by item.ordinality
    ),
    sum((item.value ->> 'quantity')::bigint)
  into v_normalized_lines, v_total_quantity
  from jsonb_array_elements(p_lines) with ordinality as item(value, ordinality);

  if p_lock_basis then
    select organization.timezone
    into v_organization_timezone
    from app.organizations organization
    where organization.id = p_organization_id
      and organization.is_active
    for update;
  else
    select organization.timezone
    into v_organization_timezone
    from app.organizations organization
    where organization.id = p_organization_id
      and organization.is_active;
  end if;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_NOT_FOUND';
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

  if v_actor_user_id is not null
     and (
       not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  v_effective_local_date :=
    (p_occurred_at at time zone v_organization_timezone)::date;

  if p_lock_basis then
    select
      case
        when jsonb_typeof(setting.value) = 'number'
          then (setting.value #>> '{}')::integer
        else null
      end
    into v_safety_buffer_days
    from app.settings setting
    where setting.organization_id = p_organization_id
      and setting.key = 'expiry.safety_buffer_days'
      and setting.effective_from <= p_occurred_at
      and (setting.effective_to is null or setting.effective_to > p_occurred_at)
    order by setting.version desc, setting.effective_from desc
    limit 1
    for update;
  else
    select
      case
        when jsonb_typeof(setting.value) = 'number'
          then (setting.value #>> '{}')::integer
        else null
      end
    into v_safety_buffer_days
    from app.settings setting
    where setting.organization_id = p_organization_id
      and setting.key = 'expiry.safety_buffer_days'
      and setting.effective_from <= p_occurred_at
      and (setting.effective_to is null or setting.effective_to > p_occurred_at)
    order by setting.version desc, setting.effective_from desc
    limit 1;
  end if;

  v_safety_buffer_days := coalesce(v_safety_buffer_days, 0);

  if v_safety_buffer_days < 0 or v_safety_buffer_days > 3650 then
    raise exception using
      errcode = 'P0001',
      message = 'EXPIRY_SAFETY_BUFFER_INVALID';
  end if;

  if p_lock_basis then
    select
      reason.id,
      reason.name,
      reason.requires_note
    into
      v_reason_id,
      v_reason_name,
      v_reason_requires_note
    from catalog.movement_reasons reason
    where reason.code = v_reason_code
      and reason.direction_code = 'OUTBOUND'
      and reason.is_active
      and reason.code in ('OFFLINE_SALE', 'BONUS', 'PROMO', 'SAMPLE')
    for update;
  else
    select
      reason.id,
      reason.name,
      reason.requires_note
    into
      v_reason_id,
      v_reason_name,
      v_reason_requires_note
    from catalog.movement_reasons reason
    where reason.code = v_reason_code
      and reason.direction_code = 'OUTBOUND'
      and reason.is_active
      and reason.code in ('OFFLINE_SALE', 'BONUS', 'PROMO', 'SAMPLE');
  end if;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_REASON_NOT_ALLOWED';
  end if;

  if p_lock_basis then
    select channel.id
    into v_channel_id
    from catalog.channels channel
    where channel.code = 'MANUAL'
      and channel.is_active
    for update;
  else
    select channel.id
    into v_channel_id
    from catalog.channels channel
    where channel.code = 'MANUAL'
      and channel.is_active;
  end if;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_CHANNEL_NOT_CONFIGURED';
  end if;

  if v_reason_requires_note and v_note is null then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'OUTBOUND_NOTE_REQUIRED',
        'scope', 'REQUEST',
        'message', 'Catatan wajib diisi untuk alasan barang keluar ini.'
      )
    );
  end if;

  if v_reason_code in ('BONUS', 'PROMO', 'SAMPLE')
     and v_reference is null then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'OUTBOUND_REASON_REFERENCE_REQUIRED',
        'scope', 'REQUEST',
        'message',
          'Referensi kegiatan, persetujuan, penerima, atau pesanan wajib diisi.'
      )
    );
  end if;

  select exists (
    select 1
    from operations.manual_outbounds outbound
    where outbound.organization_id = p_organization_id
      and outbound.source_ref = v_source_ref
  )
  into v_source_already_posted;

  if v_source_already_posted then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'OUTBOUND_SOURCE_ALREADY_POSTED',
        'scope', 'REQUEST',
        'message', 'Referensi barang keluar ini sudah pernah diposting.'
      )
    );
  end if;

  v_request_payload := jsonb_build_object(
    'organizationId', p_organization_id,
    'sourceRef', v_source_ref,
    'occurredAt', p_occurred_at,
    'reasonCode', v_reason_code,
    'channelCode', 'MANUAL',
    'lines', v_normalized_lines,
    'note', v_note,
    'metadata', v_metadata,
    'schemaVersion', 1
  );

  v_request_hash := encode(
    extensions.digest(
      convert_to(v_request_payload::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  for v_line in
    select
      (line.value ->> 'lineNo')::integer as line_no,
      (line.value ->> 'productId')::uuid as product_id,
      (line.value ->> 'quantity')::bigint as quantity_requested,
      line.value ->> 'sourceLineRef' as source_line_ref
    from jsonb_array_elements(v_normalized_lines) as line(value)
    order by (line.value ->> 'productId')::uuid
  loop
    if p_lock_basis then
      perform pg_advisory_xact_lock(
        hashtextextended(
          p_organization_id::text
            || ':PRODUCT_STOCK:'
            || v_line.product_id::text,
          0::bigint
        )
      );
    end if;

    v_product_sku := null;
    v_product_name := null;
    v_product_active := null;
    v_product_batch_tracked := null;
    v_product_expiry_tracked := null;
    v_product_row_version := null;

    if p_lock_basis then
      select
        product.sku,
        product.name,
        product.is_active,
        product.is_batch_tracked,
        product.is_expiry_tracked,
        product.row_version
      into
        v_product_sku,
        v_product_name,
        v_product_active,
        v_product_batch_tracked,
        v_product_expiry_tracked,
        v_product_row_version
      from catalog.products product
      where product.organization_id = p_organization_id
        and product.id = v_line.product_id
      for update;
    else
      select
        product.sku,
        product.name,
        product.is_active,
        product.is_batch_tracked,
        product.is_expiry_tracked,
        product.row_version
      into
        v_product_sku,
        v_product_name,
        v_product_active,
        v_product_batch_tracked,
        v_product_expiry_tracked,
        v_product_row_version
      from catalog.products product
      where product.organization_id = p_organization_id
        and product.id = v_line.product_id;
    end if;

    v_product_found := found;

    v_product_sellable := 0;
    v_product_reserved := 0;
    v_position_version := null;
    v_position_last_ledger_seq := null;
    v_position_found := false;

    if v_product_found then
      if p_lock_basis then
        select
          position.sellable_qty,
          position.reserved_qty,
          position.version,
          position.last_ledger_seq
        into
          v_product_sellable,
          v_product_reserved,
          v_position_version,
          v_position_last_ledger_seq
        from inventory.stock_product_positions position
        where position.organization_id = p_organization_id
          and position.product_id = v_line.product_id
        for update;
      else
        select
          position.sellable_qty,
          position.reserved_qty,
          position.version,
          position.last_ledger_seq
        into
          v_product_sellable,
          v_product_reserved,
          v_position_version,
          v_position_last_ledger_seq
        from inventory.stock_product_positions position
        where position.organization_id = p_organization_id
          and position.product_id = v_line.product_id;
      end if;

      v_position_found := found;
    end if;

    v_product_sellable := coalesce(v_product_sellable, 0);
    v_product_reserved := coalesce(v_product_reserved, 0);
    v_product_available := v_product_sellable - v_product_reserved;

    if p_lock_basis and v_product_found then
      perform 1
      from inventory.stock_batch_balances balance
      join catalog.product_batches batch
        on batch.organization_id = balance.organization_id
       and batch.product_id = balance.product_id
       and batch.id = balance.batch_id
      where balance.organization_id = p_organization_id
        and balance.product_id = v_line.product_id
      order by
        batch.expiry_date,
        batch.received_first_at asc nulls last,
        batch.batch_code,
        batch.id
      for update of balance, batch;
    end if;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'batchId', batch.id,
          'batchCode', batch.batch_code,
          'expiryDate', batch.expiry_date,
          'receivedFirstAt', batch.received_first_at,
          'statusCode', batch.status_code,
          'blockReason', batch.block_reason,
          'batchRowVersion', batch.row_version,
          'sellableQuantity', balance.sellable_qty,
          'balanceVersion', balance.version,
          'lastLedgerSeq', balance.last_ledger_seq,
          'eligible',
            balance.sellable_qty > 0
            and batch.status_code = 'ACTIVE'
            and batch.expiry_date
              > v_effective_local_date + v_safety_buffer_days
        )
        order by
          batch.expiry_date,
          batch.received_first_at asc nulls last,
          batch.batch_code,
          batch.id
      ),
      '[]'::jsonb
    )
    into v_batch_basis
    from inventory.stock_batch_balances balance
    join catalog.product_batches batch
      on batch.organization_id = balance.organization_id
     and batch.product_id = balance.product_id
     and batch.id = balance.batch_id
    where balance.organization_id = p_organization_id
      and balance.product_id = v_line.product_id;

    select coalesce(sum(balance.sellable_qty), 0)
    into v_eligible_total
    from inventory.stock_batch_balances balance
    join catalog.product_batches batch
      on batch.organization_id = balance.organization_id
     and batch.product_id = balance.product_id
     and batch.id = balance.batch_id
    where balance.organization_id = p_organization_id
      and balance.product_id = v_line.product_id
      and balance.sellable_qty > 0
      and batch.status_code = 'ACTIVE'
      and batch.expiry_date
        > v_effective_local_date + v_safety_buffer_days;

    v_remaining := v_line.quantity_requested;
    v_allocation_no := 0;
    v_line_allocations := '[]'::jsonb;

    if not v_product_found then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'OUTBOUND_PRODUCT_NOT_FOUND',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'productId', v_line.product_id,
          'message', 'Produk tidak ditemukan pada organisasi aktif.'
        )
      );
    else
      if not v_product_active then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'OUTBOUND_PRODUCT_INACTIVE',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'productId', v_line.product_id,
            'productSku', v_product_sku,
            'message', 'Produk tidak aktif dan tidak dapat dikeluarkan.'
          )
        );
      end if;

      if not v_product_batch_tracked then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'OUTBOUND_PRODUCT_NOT_BATCH_TRACKED',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'productId', v_line.product_id,
            'productSku', v_product_sku,
            'message', 'Produk tidak menggunakan pelacakan batch.'
          )
        );
      end if;

      if not v_product_expiry_tracked then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'OUTBOUND_PRODUCT_NOT_EXPIRY_TRACKED',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'productId', v_line.product_id,
            'productSku', v_product_sku,
            'message', 'Produk tidak menggunakan pelacakan kedaluwarsa.'
          )
        );
      end if;

      if not v_position_found then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'INSUFFICIENT_AVAILABLE_STOCK',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'productId', v_line.product_id,
            'productSku', v_product_sku,
            'requestedQuantity', v_line.quantity_requested,
            'availableQuantity', 0,
            'message', 'Posisi stok produk belum tersedia.'
          )
        );
      elsif v_product_available < v_line.quantity_requested then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'INSUFFICIENT_AVAILABLE_STOCK',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'productId', v_line.product_id,
            'productSku', v_product_sku,
            'requestedQuantity', v_line.quantity_requested,
            'sellableQuantity', v_product_sellable,
            'reservedQuantity', v_product_reserved,
            'availableQuantity', v_product_available,
            'message',
              'Stok tersedia setelah reservasi tidak mencukupi.'
          )
        );
      end if;
    end if;

    if v_product_found
       and v_product_active
       and v_product_batch_tracked
       and v_product_expiry_tracked
       and v_position_found
       and v_product_available >= v_line.quantity_requested then
      for v_batch in
        select
          batch.id as batch_id,
          batch.batch_code,
          batch.expiry_date,
          batch.received_first_at,
          balance.sellable_qty,
          balance.version as balance_version
        from inventory.stock_batch_balances balance
        join catalog.product_batches batch
          on batch.organization_id = balance.organization_id
         and batch.product_id = balance.product_id
         and batch.id = balance.batch_id
        where balance.organization_id = p_organization_id
          and balance.product_id = v_line.product_id
          and balance.sellable_qty > 0
          and batch.status_code = 'ACTIVE'
          and batch.expiry_date
            > v_effective_local_date + v_safety_buffer_days
        order by
          batch.expiry_date,
          batch.received_first_at asc nulls last,
          batch.batch_code,
          batch.id
      loop
        exit when v_remaining = 0;

        v_allocate := least(v_remaining, v_batch.sellable_qty);
        v_allocation_no := v_allocation_no + 1;

        v_line_allocations := v_line_allocations || jsonb_build_array(
          jsonb_build_object(
            'lineNo', v_line.line_no,
            'sourceLineRef', v_line.source_line_ref,
            'allocationNo', v_allocation_no,
            'productId', v_line.product_id,
            'productSku', v_product_sku,
            'batchId', v_batch.batch_id,
            'batchCode', v_batch.batch_code,
            'expiryDate', v_batch.expiry_date,
            'receivedFirstAt', v_batch.received_first_at,
            'currentBatchSellable', v_batch.sellable_qty,
            'quantity', v_allocate,
            'resultingBatchSellable',
              v_batch.sellable_qty - v_allocate,
            'batchBalanceVersion', v_batch.balance_version
          )
        );

        v_remaining := v_remaining - v_allocate;
      end loop;

      v_allocations := v_allocations || v_line_allocations;

      if v_remaining > 0 then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'INSUFFICIENT_FEFO_STOCK',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'productId', v_line.product_id,
            'productSku', v_product_sku,
            'requestedQuantity', v_line.quantity_requested,
            'eligibleQuantity', v_eligible_total,
            'shortageQuantity', v_remaining,
            'message',
              'Stok batch yang memenuhi FEFO dan batas kedaluwarsa tidak mencukupi.'
          )
        );
      end if;
    end if;

    v_products := v_products || jsonb_build_array(
      jsonb_build_object(
        'lineNo', v_line.line_no,
        'sourceLineRef', v_line.source_line_ref,
        'productId', v_line.product_id,
        'productSku', v_product_sku,
        'productName', v_product_name,
        'requestedQuantity', v_line.quantity_requested,
        'currentSellable', v_product_sellable,
        'currentReserved', v_product_reserved,
        'currentAvailable', v_product_available,
        'eligibleFefoQuantity', v_eligible_total,
        'allocatedQuantity',
          v_line.quantity_requested - v_remaining,
        'resultingSellable',
          case
            when v_remaining = 0
             and v_product_found
             and v_product_active
             and v_product_batch_tracked
             and v_product_expiry_tracked
             and v_position_found
             and v_product_available >= v_line.quantity_requested
              then v_product_sellable - v_line.quantity_requested
            else null
          end,
        'resultingAvailable',
          case
            when v_remaining = 0
             and v_product_found
             and v_product_active
             and v_product_batch_tracked
             and v_product_expiry_tracked
             and v_position_found
             and v_product_available >= v_line.quantity_requested
              then v_product_available - v_line.quantity_requested
            else null
          end,
        'status',
          case
            when v_remaining = 0
             and v_product_found
             and v_product_active
             and v_product_batch_tracked
             and v_product_expiry_tracked
             and v_position_found
             and v_product_available >= v_line.quantity_requested
              then 'READY'
            else 'BLOCKED'
          end,
        'allocations', v_line_allocations
      )
    );

    v_basis_products := v_basis_products || jsonb_build_array(
      jsonb_build_object(
        'productId', v_line.product_id,
        'exists', v_product_found,
        'sku', v_product_sku,
        'active', v_product_active,
        'batchTracked', v_product_batch_tracked,
        'expiryTracked', v_product_expiry_tracked,
        'productRowVersion', v_product_row_version,
        'positionExists', v_position_found,
        'sellableQuantity', v_product_sellable,
        'reservedQuantity', v_product_reserved,
        'positionVersion', v_position_version,
        'positionLastLedgerSeq', v_position_last_ledger_seq,
        'batches', v_batch_basis
      )
    );
  end loop;

  v_authoritative_basis := jsonb_build_object(
    'organizationId', p_organization_id,
    'organizationTimezone', v_organization_timezone,
    'effectiveLocalDate', v_effective_local_date,
    'expirySafetyBufferDays', v_safety_buffer_days,
    'reasonId', v_reason_id,
    'reasonCode', v_reason_code,
    'reasonRequiresNote', v_reason_requires_note,
    'channelId', v_channel_id,
    'channelCode', 'MANUAL',
    'sourceAlreadyPosted', v_source_already_posted,
    'products', v_basis_products,
    'schemaVersion', 1
  );

  v_basis_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'request', v_request_payload,
          'basis', v_authoritative_basis,
          'schemaVersion', 1
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_eligible := jsonb_array_length(v_blockers) = 0;

  return jsonb_build_object(
    'status', case when v_eligible then 'PREVIEW_READY' else 'BLOCKED' end,
    'eligible', v_eligible,
    'schemaVersion', 1,
    'basisHash', v_basis_hash,
    'requestHash', v_request_hash,
    'organizationId', p_organization_id,
    'sourceRef', v_source_ref,
    'occurredAt', p_occurred_at,
    'effectiveLocalDate', v_effective_local_date,
    'reasonCode', v_reason_code,
    'reasonName', v_reason_name,
    'channelCode', 'MANUAL',
    'note', v_note,
    'reference', v_reference,
    'lineCount', jsonb_array_length(v_normalized_lines),
    'totalRequestedQuantity', v_total_quantity,
    'allocationCount', jsonb_array_length(v_allocations),
    'expirySafetyBufferDays', v_safety_buffer_days,
    'products', v_products,
    'allocations', v_allocations,
    'blockers', v_blockers
  );
end;
$$;

revoke all on function inventory.preview_manual_outbound_core(
  uuid,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  jsonb,
  boolean
) from public, anon, authenticated, service_role;

create or replace function api.preview_manual_outbound(
  p_organization_id uuid,
  p_source_ref text,
  p_occurred_at timestamptz,
  p_reason_code text,
  p_lines jsonb,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
begin
  return inventory.preview_manual_outbound_core(
    p_organization_id,
    p_source_ref,
    p_occurred_at,
    p_reason_code,
    p_lines,
    p_note,
    p_metadata,
    false
  );
end;
$$;

revoke all on function api.preview_manual_outbound(
  uuid,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  jsonb
) from public, anon;

grant execute on function api.preview_manual_outbound(
  uuid,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  jsonb
) to authenticated, service_role;

create or replace function api.post_manual_outbound(
  p_organization_id uuid,
  p_idempotency_key text,
  p_source_ref text,
  p_occurred_at timestamptz,
  p_reason_code text,
  p_lines jsonb,
  p_preview_basis_hash text,
  p_confirmation boolean,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_scope constant text := 'POST_MANUAL_OUTBOUND';
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text :=
    coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_idempotency_key text;
  v_source_ref text;
  v_reason_code text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_preview jsonb;
  v_actual_basis_hash text;
  v_expected_basis_hash text;
begin
  if p_confirmation is distinct from true then
    raise exception using
      errcode = 'P0001',
      message = 'MANUAL_OUTBOUND_CONFIRMATION_REQUIRED';
  end if;

  v_expected_basis_hash :=
    lower(btrim(coalesce(p_preview_basis_hash, '')));

  if v_expected_basis_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = 'P0001',
      message = 'MANUAL_OUTBOUND_PREVIEW_HASH_INVALID';
  end if;

  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_REQUIRED';
  end if;

  perform 1
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_NOT_FOUND';
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

  if v_actor_user_id is not null
     and (
       not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));

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

  v_source_ref := btrim(coalesce(p_source_ref, ''));

  if v_source_ref = '' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_SOURCE_REQUIRED';
  end if;

  if length(v_source_ref) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_SOURCE_TOO_LONG';
  end if;

  v_reason_code := upper(btrim(coalesce(p_reason_code, '')));

  if v_reason_code = '' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_REASON_REQUIRED';
  end if;

  if length(v_reason_code) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_REASON_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_METADATA_MUST_BE_OBJECT';
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');

  if v_note is not null and length(v_note) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_NOTE_TOO_LONG';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'sourceRef', v_source_ref,
          'occurredAt', p_occurred_at,
          'reasonCode', v_reason_code,
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
        || ':MANUAL_OUTBOUND_SOURCE:'
        || v_source_ref,
      0::bigint
    )
  );

  if exists (
    select 1
    from operations.manual_outbounds outbound
    where outbound.organization_id = p_organization_id
      and outbound.source_ref = v_source_ref
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOUND_SOURCE_ALREADY_POSTED';
  end if;

  v_preview := inventory.preview_manual_outbound_core(
    p_organization_id,
    v_source_ref,
    p_occurred_at,
    v_reason_code,
    p_lines,
    v_note,
    v_metadata,
    true
  );

  v_actual_basis_hash := lower(v_preview ->> 'basisHash');

  if v_actual_basis_hash is distinct from v_expected_basis_hash then
    raise exception using
      errcode = 'P0001',
      message = 'STALE_MANUAL_OUTBOUND_PREVIEW';
  end if;

  if coalesce((v_preview ->> 'eligible')::boolean, false) is not true then
    raise exception using
      errcode = 'P0001',
      message = 'MANUAL_OUTBOUND_PREVIEW_BLOCKED';
  end if;

  return api.post_manual_outbound(
    p_organization_id,
    v_idempotency_key,
    v_source_ref,
    p_occurred_at,
    v_reason_code,
    p_lines,
    v_note,
    v_metadata
  );
end;
$$;

revoke all on function api.post_manual_outbound(
  uuid,
  text,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  boolean,
  text,
  jsonb
) from public, anon;

grant execute on function api.post_manual_outbound(
  uuid,
  text,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  boolean,
  text,
  jsonb
) to authenticated, service_role;

revoke execute on function api.post_manual_outbound(
  uuid,
  text,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  jsonb
) from authenticated, service_role;

commit;
