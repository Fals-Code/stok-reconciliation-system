begin;

create table operations.stock_disposals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  disposal_no text not null,
  source_ref text not null,
  reason_id uuid not null references catalog.movement_reasons(id) on delete restrict,
  reason_code_snapshot text not null,
  channel_id uuid not null references catalog.channels(id) on delete restrict,
  channel_code_snapshot text not null,
  status_code text not null default 'POSTED',
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default clock_timestamp(),
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  transaction_id uuid not null references inventory.stock_transactions(id) on delete restrict,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  total_quantity bigint not null,
  reference_text text not null,
  note text not null,
  request_hash text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint uq_stock_disposals_org_id unique (organization_id, id),
  constraint uq_stock_disposals_org_no unique (organization_id, disposal_no),
  constraint uq_stock_disposals_org_source unique (organization_id, source_ref),
  constraint uq_stock_disposals_transaction unique (transaction_id),
  constraint uq_stock_disposals_idempotency unique (idempotency_command_id),
  constraint ck_stock_disposals_no_nonblank check (btrim(disposal_no) <> ''),
  constraint ck_stock_disposals_source_nonblank check (btrim(source_ref) <> ''),
  constraint ck_stock_disposals_reason check (
    reason_code_snapshot in ('DAMAGED_DISPOSAL', 'EXPIRED_DISPOSAL')
  ),
  constraint ck_stock_disposals_channel check (channel_code_snapshot = 'MANUAL'),
  constraint ck_stock_disposals_status check (status_code = 'POSTED'),
  constraint ck_stock_disposals_actor_xor_process
    check ((actor_user_id is not null) <> (process_name is not null)),
  constraint ck_stock_disposals_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),
  constraint ck_stock_disposals_total_positive check (total_quantity > 0),
  constraint ck_stock_disposals_reference_nonblank check (btrim(reference_text) <> ''),
  constraint ck_stock_disposals_note_nonblank check (btrim(note) <> ''),
  constraint ck_stock_disposals_request_hash
    check (request_hash ~ '^[0-9a-f]{64}$'),
  constraint ck_stock_disposals_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create table operations.stock_disposal_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  disposal_id uuid not null,
  line_no integer not null,
  product_id uuid not null,
  batch_id uuid not null,
  ledger_entry_id uuid not null
    references inventory.stock_ledger_entries(id) on delete restrict,
  source_bucket_code text not null,
  quantity_disposed bigint not null,
  product_sku_snapshot text not null,
  product_name_snapshot text not null,
  batch_code_snapshot text not null,
  expiry_date_snapshot date not null,
  batch_status_code_snapshot text not null,
  source_line_ref text not null,
  bucket_before_qty bigint not null,
  bucket_after_qty bigint not null,
  created_at timestamptz not null default now(),
  constraint uq_stock_disposal_lines_org_id unique (organization_id, id),
  constraint fk_stock_disposal_lines_disposal
    foreign key (organization_id, disposal_id)
    references operations.stock_disposals (organization_id, id)
    on delete restrict,
  constraint fk_stock_disposal_lines_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches (organization_id, product_id, id)
    on delete restrict,
  constraint uq_stock_disposal_lines_line unique (disposal_id, line_no),
  constraint uq_stock_disposal_lines_source unique (disposal_id, source_line_ref),
  constraint uq_stock_disposal_lines_identity unique (
    disposal_id,
    product_id,
    batch_id,
    source_bucket_code
  ),
  constraint uq_stock_disposal_lines_ledger unique (ledger_entry_id),
  constraint ck_stock_disposal_lines_line_positive check (line_no > 0),
  constraint ck_stock_disposal_lines_bucket check (
    source_bucket_code in ('SELLABLE', 'QUARANTINE', 'DAMAGED')
  ),
  constraint ck_stock_disposal_lines_quantity_positive check (quantity_disposed > 0),
  constraint ck_stock_disposal_lines_sku_nonblank check (btrim(product_sku_snapshot) <> ''),
  constraint ck_stock_disposal_lines_product_name_nonblank
    check (btrim(product_name_snapshot) <> ''),
  constraint ck_stock_disposal_lines_batch_nonblank check (btrim(batch_code_snapshot) <> ''),
  constraint ck_stock_disposal_lines_status check (
    batch_status_code_snapshot in ('ACTIVE', 'BLOCKED', 'EXPIRED', 'ARCHIVED')
  ),
  constraint ck_stock_disposal_lines_source_nonblank check (btrim(source_line_ref) <> ''),
  constraint ck_stock_disposal_lines_before_nonnegative check (bucket_before_qty >= 0),
  constraint ck_stock_disposal_lines_after_nonnegative check (bucket_after_qty >= 0),
  constraint ck_stock_disposal_lines_balance_math check (
    bucket_after_qty = bucket_before_qty - quantity_disposed
  )
);

create index idx_stock_disposals_org_occurred
on operations.stock_disposals (organization_id, occurred_at desc, id);

create index idx_stock_disposal_lines_batch
on operations.stock_disposal_lines (
  organization_id,
  batch_id,
  source_bucket_code,
  disposal_id,
  line_no
);

create trigger trg_stock_disposals_immutable
before update or delete on operations.stock_disposals
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_stock_disposal_lines_immutable
before update or delete on operations.stock_disposal_lines
for each row execute function inventory.reject_immutable_mutation();

alter table operations.stock_disposals enable row level security;
alter table operations.stock_disposal_lines enable row level security;

create policy stock_disposals_read_current_org
on operations.stock_disposals
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stock_disposal_lines_read_current_org
on operations.stock_disposal_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on operations.stock_disposals,
              operations.stock_disposal_lines
from public, anon, authenticated;

grant select on operations.stock_disposals,
                operations.stock_disposal_lines
to authenticated, service_role;

create or replace function inventory.preview_stock_disposal_core(
  p_organization_id uuid,
  p_source_ref text,
  p_occurred_at timestamptz,
  p_reason_code text,
  p_lines jsonb,
  p_reference_text text,
  p_note text,
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
  v_reference_text text;
  v_note text;
  v_metadata jsonb;
  v_organization_timezone text;
  v_effective_local_date date;
  v_reason_id uuid;
  v_reason_name text;
  v_reason_requires_note boolean;
  v_channel_id uuid;
  v_normalized_lines jsonb;
  v_total_quantity bigint;
  v_request_payload jsonb;
  v_request_hash text;
  v_source_already_posted boolean;
  v_lines jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_basis jsonb;
  v_basis_hash text;
  v_eligible boolean;
  v_line record;
  v_product_found boolean;
  v_product_sku text;
  v_product_name text;
  v_product_active boolean;
  v_product_row_version bigint;
  v_batch_found boolean;
  v_batch_code text;
  v_batch_expiry date;
  v_batch_status text;
  v_batch_block_reason text;
  v_batch_row_version bigint;
  v_balance_found boolean;
  v_batch_sellable bigint;
  v_batch_quarantine bigint;
  v_batch_damaged bigint;
  v_balance_version bigint;
  v_balance_last_ledger_seq bigint;
  v_position_found boolean;
  v_product_sellable bigint;
  v_product_quarantine bigint;
  v_product_damaged bigint;
  v_product_reserved bigint;
  v_position_version bigint;
  v_position_last_ledger_seq bigint;
  v_requested_product_sellable bigint;
  v_requested_product_quarantine bigint;
  v_requested_product_damaged bigint;
  v_current_bucket_qty bigint;
  v_resulting_bucket_qty bigint;
  v_resulting_product_sellable bigint;
  v_resulting_product_quarantine bigint;
  v_resulting_product_damaged bigint;
  v_line_blockers jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  v_source_ref := btrim(coalesce(p_source_ref, ''));
  if v_source_ref = '' then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_SOURCE_REQUIRED';
  end if;
  if length(v_source_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_SOURCE_TOO_LONG';
  end if;

  if p_occurred_at is null then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_OCCURRED_AT_REQUIRED';
  end if;

  v_reason_code := upper(btrim(coalesce(p_reason_code, '')));
  if v_reason_code not in ('DAMAGED_DISPOSAL', 'EXPIRED_DISPOSAL') then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_REASON_NOT_ALLOWED';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_LINES_MUST_BE_ARRAY';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_LINES_REQUIRED';
  end if;
  if jsonb_array_length(p_lines) > 200 then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_LINES_LIMIT_EXCEEDED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'productId') is distinct from 'string'
       or (item.value ->> 'productId') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'batchId') is distinct from 'string'
       or (item.value ->> 'batchId') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'sourceBucketCode') is distinct from 'string'
       or upper(btrim(item.value ->> 'sourceBucketCode')) not in (
            'SELLABLE', 'QUARANTINE', 'DAMAGED'
          )
       or jsonb_typeof(item.value -> 'quantity') is distinct from 'number'
       or (item.value ->> 'quantity') !~ '^[1-9][0-9]{0,8}$'
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 100
  ) then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by
      lower(item.value ->> 'productId'),
      lower(item.value ->> 'batchId'),
      upper(btrim(item.value ->> 'sourceBucketCode'))
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_DUPLICATE_BATCH_BUCKET_LINE';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_DUPLICATE_SOURCE_LINE';
  end if;

  select
    jsonb_agg(
      jsonb_build_object(
        'lineNo', item.ordinality::integer,
        'productId', lower(item.value ->> 'productId'),
        'batchId', lower(item.value ->> 'batchId'),
        'sourceBucketCode', upper(btrim(item.value ->> 'sourceBucketCode')),
        'quantity', (item.value ->> 'quantity')::bigint,
        'sourceLineRef', btrim(item.value ->> 'sourceLineRef')
      )
      order by item.ordinality
    ),
    sum((item.value ->> 'quantity')::bigint)::bigint
  into v_normalized_lines, v_total_quantity
  from jsonb_array_elements(p_lines) with ordinality item(value, ordinality);

  v_reference_text := nullif(btrim(coalesce(p_reference_text, '')), '');
  if v_reference_text is null then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_REFERENCE_REQUIRED';
  end if;
  if length(v_reference_text) > 500 then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_REFERENCE_TOO_LONG';
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');
  if v_note is null then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_NOTE_REQUIRED';
  end if;
  if length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_NOTE_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_METADATA_MUST_BE_OBJECT';
  end if;

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

  if v_actor_user_id is not null
     and (
       not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id
     ) then
    raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  v_effective_local_date :=
    (p_occurred_at at time zone v_organization_timezone)::date;

  if p_lock_basis then
    select reason.id, reason.name, reason.requires_note
    into v_reason_id, v_reason_name, v_reason_requires_note
    from catalog.movement_reasons reason
    where reason.code = v_reason_code
      and reason.direction_code = 'OUTBOUND'
      and reason.is_active
    for update;
  else
    select reason.id, reason.name, reason.requires_note
    into v_reason_id, v_reason_name, v_reason_requires_note
    from catalog.movement_reasons reason
    where reason.code = v_reason_code
      and reason.direction_code = 'OUTBOUND'
      and reason.is_active;
  end if;

  if not found then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_REASON_NOT_CONFIGURED';
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
    raise exception using errcode = 'P0001', message = 'DISPOSAL_CHANNEL_NOT_CONFIGURED';
  end if;

  select exists (
    select 1
    from operations.stock_disposals disposal
    where disposal.organization_id = p_organization_id
      and disposal.source_ref = v_source_ref
  )
  into v_source_already_posted;

  if v_source_already_posted then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'DISPOSAL_SOURCE_ALREADY_POSTED',
        'scope', 'REQUEST',
        'message', 'Referensi pemusnahan sudah pernah diposting.'
      )
    );
  end if;

  v_request_payload := jsonb_build_object(
    'organizationId', p_organization_id,
    'sourceRef', v_source_ref,
    'occurredAt', p_occurred_at,
    'reasonCode', v_reason_code,
    'lines', v_normalized_lines,
    'referenceText', v_reference_text,
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
      (line.value ->> 'batchId')::uuid as batch_id,
      line.value ->> 'sourceBucketCode' as source_bucket_code,
      (line.value ->> 'quantity')::bigint as quantity_requested,
      line.value ->> 'sourceLineRef' as source_line_ref
    from jsonb_array_elements(v_normalized_lines) line(value)
    order by
      (line.value ->> 'productId')::uuid,
      (line.value ->> 'batchId')::uuid,
      line.value ->> 'sourceBucketCode',
      (line.value ->> 'lineNo')::integer
  loop
    if p_lock_basis then
      perform pg_advisory_xact_lock(
        hashtextextended(
          p_organization_id::text || ':PRODUCT_STOCK:' || v_line.product_id::text,
          0::bigint
        )
      );
    end if;

    v_line_blockers := '[]'::jsonb;
    v_product_found := false;
    v_product_sku := null;
    v_product_name := null;
    v_product_active := null;
    v_product_row_version := null;

    if p_lock_basis then
      select product.sku, product.name, product.is_active, product.row_version
      into v_product_sku, v_product_name, v_product_active, v_product_row_version
      from catalog.products product
      where product.organization_id = p_organization_id
        and product.id = v_line.product_id
      for update;
    else
      select product.sku, product.name, product.is_active, product.row_version
      into v_product_sku, v_product_name, v_product_active, v_product_row_version
      from catalog.products product
      where product.organization_id = p_organization_id
        and product.id = v_line.product_id;
    end if;

    v_product_found := found;

    if not v_product_found then
      v_line_blockers := v_line_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'DISPOSAL_PRODUCT_NOT_FOUND',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Produk pada baris pemusnahan tidak ditemukan.'
        )
      );
    elsif not v_product_active then
      v_line_blockers := v_line_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'DISPOSAL_PRODUCT_INACTIVE',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Produk tidak aktif dan harus diperiksa sebelum pemusnahan.'
        )
      );
    end if;

    v_batch_found := false;
    v_batch_code := null;
    v_batch_expiry := null;
    v_batch_status := null;
    v_batch_block_reason := null;
    v_batch_row_version := null;

    if v_product_found then
      if p_lock_basis then
        select
          batch.batch_code,
          batch.expiry_date,
          batch.status_code,
          batch.block_reason,
          batch.row_version
        into
          v_batch_code,
          v_batch_expiry,
          v_batch_status,
          v_batch_block_reason,
          v_batch_row_version
        from catalog.product_batches batch
        where batch.organization_id = p_organization_id
          and batch.product_id = v_line.product_id
          and batch.id = v_line.batch_id
        for update;
      else
        select
          batch.batch_code,
          batch.expiry_date,
          batch.status_code,
          batch.block_reason,
          batch.row_version
        into
          v_batch_code,
          v_batch_expiry,
          v_batch_status,
          v_batch_block_reason,
          v_batch_row_version
        from catalog.product_batches batch
        where batch.organization_id = p_organization_id
          and batch.product_id = v_line.product_id
          and batch.id = v_line.batch_id;
      end if;

      v_batch_found := found;
    end if;

    if v_product_found and not v_batch_found then
      v_line_blockers := v_line_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'DISPOSAL_BATCH_NOT_FOUND',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Batch pada baris pemusnahan tidak ditemukan untuk produk ini.'
        )
      );
    elsif v_batch_found and v_batch_status = 'ARCHIVED' then
      v_line_blockers := v_line_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'DISPOSAL_BATCH_ARCHIVED',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Batch arsip harus diperiksa atau dipulihkan sebelum pemusnahan.'
        )
      );
    end if;

    v_balance_found := false;
    v_batch_sellable := 0;
    v_batch_quarantine := 0;
    v_batch_damaged := 0;
    v_balance_version := 0;
    v_balance_last_ledger_seq := 0;

    if v_batch_found then
      if p_lock_basis then
        select
          balance.sellable_qty,
          balance.quarantine_qty,
          balance.damaged_qty,
          balance.version,
          balance.last_ledger_seq
        into
          v_batch_sellable,
          v_batch_quarantine,
          v_batch_damaged,
          v_balance_version,
          v_balance_last_ledger_seq
        from inventory.stock_batch_balances balance
        where balance.organization_id = p_organization_id
          and balance.product_id = v_line.product_id
          and balance.batch_id = v_line.batch_id
        for update;
      else
        select
          balance.sellable_qty,
          balance.quarantine_qty,
          balance.damaged_qty,
          balance.version,
          balance.last_ledger_seq
        into
          v_batch_sellable,
          v_batch_quarantine,
          v_batch_damaged,
          v_balance_version,
          v_balance_last_ledger_seq
        from inventory.stock_batch_balances balance
        where balance.organization_id = p_organization_id
          and balance.product_id = v_line.product_id
          and balance.batch_id = v_line.batch_id;
      end if;

      v_balance_found := found;
    end if;

    if not v_balance_found then
      v_batch_sellable := 0;
      v_batch_quarantine := 0;
      v_batch_damaged := 0;
      v_balance_version := 0;
      v_balance_last_ledger_seq := 0;
    end if;

    v_position_found := false;
    v_product_sellable := 0;
    v_product_quarantine := 0;
    v_product_damaged := 0;
    v_product_reserved := 0;
    v_position_version := 0;
    v_position_last_ledger_seq := 0;

    if v_product_found then
      if p_lock_basis then
        select
          position.sellable_qty,
          position.quarantine_qty,
          position.damaged_qty,
          position.reserved_qty,
          position.version,
          position.last_ledger_seq
        into
          v_product_sellable,
          v_product_quarantine,
          v_product_damaged,
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
          position.quarantine_qty,
          position.damaged_qty,
          position.reserved_qty,
          position.version,
          position.last_ledger_seq
        into
          v_product_sellable,
          v_product_quarantine,
          v_product_damaged,
          v_product_reserved,
          v_position_version,
          v_position_last_ledger_seq
        from inventory.stock_product_positions position
        where position.organization_id = p_organization_id
          and position.product_id = v_line.product_id;
      end if;

      v_position_found := found;
    end if;

    if not v_position_found then
      v_product_sellable := 0;
      v_product_quarantine := 0;
      v_product_damaged := 0;
      v_product_reserved := 0;
      v_position_version := 0;
      v_position_last_ledger_seq := 0;
    end if;

    select
      coalesce(sum((item.value ->> 'quantity')::bigint) filter (
        where item.value ->> 'sourceBucketCode' = 'SELLABLE'
      ), 0)::bigint,
      coalesce(sum((item.value ->> 'quantity')::bigint) filter (
        where item.value ->> 'sourceBucketCode' = 'QUARANTINE'
      ), 0)::bigint,
      coalesce(sum((item.value ->> 'quantity')::bigint) filter (
        where item.value ->> 'sourceBucketCode' = 'DAMAGED'
      ), 0)::bigint
    into
      v_requested_product_sellable,
      v_requested_product_quarantine,
      v_requested_product_damaged
    from jsonb_array_elements(v_normalized_lines) item(value)
    where (item.value ->> 'productId')::uuid = v_line.product_id;

    v_current_bucket_qty :=
      case v_line.source_bucket_code
        when 'SELLABLE' then v_batch_sellable
        when 'QUARANTINE' then v_batch_quarantine
        when 'DAMAGED' then v_batch_damaged
      end;

    v_resulting_bucket_qty := v_current_bucket_qty - v_line.quantity_requested;
    v_resulting_product_sellable :=
      v_product_sellable - v_requested_product_sellable;
    v_resulting_product_quarantine :=
      v_product_quarantine - v_requested_product_quarantine;
    v_resulting_product_damaged :=
      v_product_damaged - v_requested_product_damaged;

    if v_reason_code = 'DAMAGED_DISPOSAL'
       and v_line.source_bucket_code <> 'DAMAGED' then
      v_line_blockers := v_line_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'INVALID_DAMAGED_DISPOSAL_SOURCE',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Pemusnahan barang rusak hanya boleh mengambil bucket DAMAGED.'
        )
      );
    end if;

    if v_reason_code = 'EXPIRED_DISPOSAL'
       and v_batch_found
       and not (v_batch_expiry < v_effective_local_date) then
      v_line_blockers := v_line_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'INVALID_EXPIRED_DISPOSAL_SOURCE',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Batch belum melewati tanggal kedaluwarsa lokal.'
        )
      );
    end if;

    if v_line.quantity_requested > v_current_bucket_qty then
      v_line_blockers := v_line_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'DISPOSAL_EXCEEDS_BALANCE',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Kuantitas pemusnahan melebihi saldo bucket batch.'
        )
      );
    end if;

    if v_line.source_bucket_code = 'SELLABLE'
       and v_resulting_product_sellable < v_product_reserved then
      v_line_blockers := v_line_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'DISPOSAL_RESERVED_CONFLICT',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Pemusnahan akan membuat reserved melebihi sellable.'
        )
      );
    end if;

    if v_resulting_product_quarantine < 0
       or v_resulting_product_damaged < 0 then
      v_line_blockers := v_line_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'DISPOSAL_PRODUCT_BUCKET_NEGATIVE',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Pemusnahan akan membuat saldo bucket produk negatif.'
        )
      );
    end if;

    v_blockers := v_blockers || v_line_blockers;

    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'lineNo', v_line.line_no,
        'sourceLineRef', v_line.source_line_ref,
        'productId', v_line.product_id,
        'productSku', v_product_sku,
        'productName', v_product_name,
        'productActive', v_product_active,
        'productRowVersion', v_product_row_version,
        'batchId', v_line.batch_id,
        'batchCode', v_batch_code,
        'expiryDate', v_batch_expiry,
        'batchStatusCode', v_batch_status,
        'batchBlockReason', v_batch_block_reason,
        'batchRowVersion', v_batch_row_version,
        'sourceBucketCode', v_line.source_bucket_code,
        'quantityRequested', v_line.quantity_requested,
        'currentBatchSellableQty', v_batch_sellable,
        'currentBatchQuarantineQty', v_batch_quarantine,
        'currentBatchDamagedQty', v_batch_damaged,
        'currentBatchBucketQty', v_current_bucket_qty,
        'resultingBatchBucketQty', v_resulting_bucket_qty,
        'batchBalanceVersion', v_balance_version,
        'batchLastLedgerSeq', v_balance_last_ledger_seq,
        'currentProductSellableQty', v_product_sellable,
        'currentProductQuarantineQty', v_product_quarantine,
        'currentProductDamagedQty', v_product_damaged,
        'currentProductReservedQty', v_product_reserved,
        'currentProductAvailableQty', v_product_sellable - v_product_reserved,
        'currentProductOnHandQty',
          v_product_sellable + v_product_quarantine + v_product_damaged,
        'resultingProductSellableQty', v_resulting_product_sellable,
        'resultingProductQuarantineQty', v_resulting_product_quarantine,
        'resultingProductDamagedQty', v_resulting_product_damaged,
        'resultingProductAvailableQty',
          v_resulting_product_sellable - v_product_reserved,
        'resultingProductOnHandQty',
          v_resulting_product_sellable
          + v_resulting_product_quarantine
          + v_resulting_product_damaged,
        'productPositionVersion', v_position_version,
        'productLastLedgerSeq', v_position_last_ledger_seq,
        'lineEligible', jsonb_array_length(v_line_blockers) = 0,
        'blockers', v_line_blockers
      )
    );
  end loop;

  v_basis := jsonb_build_object(
    'schemaVersion', 1,
    'organizationId', p_organization_id,
    'organizationTimezone', v_organization_timezone,
    'sourceRef', v_source_ref,
    'sourceAlreadyPosted', v_source_already_posted,
    'occurredAt', p_occurred_at,
    'effectiveLocalDate', v_effective_local_date,
    'reasonId', v_reason_id,
    'reasonCode', v_reason_code,
    'reasonRequiresNote', v_reason_requires_note,
    'channelId', v_channel_id,
    'channelCode', 'MANUAL',
    'referenceText', v_reference_text,
    'note', v_note,
    'requestHash', v_request_hash,
    'lines', v_lines
  );

  v_basis_hash := encode(
    extensions.digest(
      convert_to(v_basis::text, 'UTF8'),
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
    'organizationTimezone', v_organization_timezone,
    'sourceRef', v_source_ref,
    'occurredAt', p_occurred_at,
    'effectiveLocalDate', v_effective_local_date,
    'reasonCode', v_reason_code,
    'reasonName', v_reason_name,
    'channelCode', 'MANUAL',
    'referenceText', v_reference_text,
    'note', v_note,
    'lineCount', jsonb_array_length(v_normalized_lines),
    'totalRequestedQuantity', v_total_quantity,
    'lines', v_lines,
    'blockers', v_blockers
  );
end;
$$;

revoke all on function inventory.preview_stock_disposal_core(
  uuid,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  text,
  jsonb,
  boolean
) from public, anon, authenticated, service_role;

create or replace function api.preview_stock_disposal(
  p_organization_id uuid,
  p_source_ref text,
  p_occurred_at timestamptz,
  p_reason_code text,
  p_lines jsonb,
  p_reference_text text,
  p_note text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
begin
  return inventory.preview_stock_disposal_core(
    p_organization_id,
    p_source_ref,
    p_occurred_at,
    p_reason_code,
    p_lines,
    p_reference_text,
    p_note,
    p_metadata,
    false
  );
end;
$$;

revoke all on function api.preview_stock_disposal(
  uuid,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  text,
  jsonb
) from public, anon;

grant execute on function api.preview_stock_disposal(
  uuid,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  text,
  jsonb
) to authenticated, service_role;

create or replace function api.post_stock_disposal(
  p_organization_id uuid,
  p_idempotency_key text,
  p_source_ref text,
  p_occurred_at timestamptz,
  p_reason_code text,
  p_lines jsonb,
  p_preview_basis_hash text,
  p_confirmation boolean,
  p_reference_text text,
  p_note text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_scope constant text := 'POST_STOCK_DISPOSAL';
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text :=
    coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_idempotency_key text;
  v_expected_basis_hash text;
  v_source_ref text;
  v_reason_code text;
  v_reference_text text;
  v_note text;
  v_metadata jsonb;
  v_command_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_preview jsonb;
  v_actual_basis_hash text;
  v_request_hash text;
  v_organization_timezone text;
  v_effective_local_date date;
  v_reason_id uuid;
  v_channel_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_disposal_id uuid := gen_random_uuid();
  v_transaction_id uuid := gen_random_uuid();
  v_correlation_id uuid := gen_random_uuid();
  v_disposal_no text;
  v_recorded_at timestamptz := clock_timestamp();
  v_process_name text;
  v_created_by_role_code text;
  v_total_quantity bigint;
  v_line record;
  v_disposal_line_id uuid;
  v_ledger_entry_id uuid;
  v_ledger_seq bigint;
  v_last_product_ledger_seq bigint;
  v_result_lines jsonb := '[]'::jsonb;
  v_response jsonb;
begin
  if not coalesce(p_confirmation, false) then
    raise exception using errcode = 'P0001', message = 'STOCK_DISPOSAL_CONFIRMATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_expected_basis_hash := lower(btrim(coalesce(p_preview_basis_hash, '')));
  if v_expected_basis_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = 'P0001', message = 'STOCK_DISPOSAL_PREVIEW_HASH_INVALID';
  end if;

  v_source_ref := btrim(coalesce(p_source_ref, ''));
  v_reason_code := upper(btrim(coalesce(p_reason_code, '')));
  v_reference_text := nullif(btrim(coalesce(p_reference_text, '')), '');
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_jwt_role = 'anon'
     or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null
     and (
       not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id
     ) then
    raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  v_command_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'idempotencyKey', v_idempotency_key,
          'sourceRef', v_source_ref,
          'occurredAt', p_occurred_at,
          'reasonCode', v_reason_code,
          'lines', p_lines,
          'previewBasisHash', v_expected_basis_hash,
          'confirmation', true,
          'referenceText', v_reference_text,
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
    if v_existing.request_hash <> v_command_request_hash then
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
      p_organization_id::text || ':STOCK_DISPOSAL_SOURCE:' || v_source_ref,
      0::bigint
    )
  );

  v_preview := inventory.preview_stock_disposal_core(
    p_organization_id,
    v_source_ref,
    p_occurred_at,
    v_reason_code,
    p_lines,
    v_reference_text,
    v_note,
    v_metadata,
    true
  );

  v_actual_basis_hash := lower(v_preview ->> 'basisHash');
  if v_actual_basis_hash is distinct from v_expected_basis_hash then
    raise exception using errcode = 'P0001', message = 'STALE_STOCK_DISPOSAL_PREVIEW';
  end if;

  if not coalesce((v_preview ->> 'eligible')::boolean, false) then
    raise exception using
      errcode = 'P0001',
      message = coalesce(
        v_preview #>> '{blockers,0,code}',
        'STOCK_DISPOSAL_PREVIEW_BLOCKED'
      );
  end if;

  v_request_hash := v_preview ->> 'requestHash';
  v_organization_timezone := v_preview ->> 'organizationTimezone';
  v_effective_local_date := (v_preview ->> 'effectiveLocalDate')::date;
  v_total_quantity := (v_preview ->> 'totalRequestedQuantity')::bigint;

  select reason.id
  into v_reason_id
  from catalog.movement_reasons reason
  where reason.code = v_reason_code
    and reason.direction_code = 'OUTBOUND'
    and reason.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_REASON_NOT_CONFIGURED';
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = 'MANUAL'
    and channel.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_CHANNEL_NOT_CONFIGURED';
  end if;

  if v_actor_user_id is not null then
    v_process_name := null;
    v_created_by_role_code := 'ADMIN';
  else
    v_process_name := 'api.post_stock_disposal';
    v_created_by_role_code := 'SYSTEM_PROCESS';
  end if;

  v_disposal_no :=
    'DSP-' ||
    to_char(v_effective_local_date, 'YYYYMMDD') ||
    '-' ||
    upper(substr(replace(v_disposal_id::text, '-', ''), 1, 8));

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
  ) values (
    v_command_id,
    p_organization_id,
    v_scope,
    v_idempotency_key,
    v_command_request_hash,
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
  ) values (
    v_transaction_id,
    p_organization_id,
    v_disposal_no,
    'DISPOSAL',
    v_reason_id,
    v_reason_code,
    v_channel_id,
    'MANUAL',
    'STOCK_DISPOSAL',
    v_disposal_id,
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
    v_metadata || jsonb_build_object(
      'disposalNo', v_disposal_no,
      'reasonCode', v_reason_code,
      'referenceText', v_reference_text,
      'previewBasisHash', v_expected_basis_hash,
      'requestHash', v_request_hash
    ),
    1
  );

  insert into operations.stock_disposals (
    id,
    organization_id,
    disposal_no,
    source_ref,
    reason_id,
    reason_code_snapshot,
    channel_id,
    channel_code_snapshot,
    status_code,
    occurred_at,
    recorded_at,
    actor_user_id,
    process_name,
    transaction_id,
    idempotency_command_id,
    total_quantity,
    reference_text,
    note,
    request_hash,
    metadata,
    created_at
  ) values (
    v_disposal_id,
    p_organization_id,
    v_disposal_no,
    v_source_ref,
    v_reason_id,
    v_reason_code,
    v_channel_id,
    'MANUAL',
    'POSTED',
    p_occurred_at,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    v_transaction_id,
    v_command_id,
    v_total_quantity,
    v_reference_text,
    v_note,
    v_request_hash,
    v_metadata,
    v_recorded_at
  );

  for v_line in
    select
      (line.value ->> 'lineNo')::integer as line_no,
      (line.value ->> 'productId')::uuid as product_id,
      line.value ->> 'productSku' as product_sku,
      line.value ->> 'productName' as product_name,
      (line.value ->> 'batchId')::uuid as batch_id,
      line.value ->> 'batchCode' as batch_code,
      (line.value ->> 'expiryDate')::date as expiry_date,
      line.value ->> 'batchStatusCode' as batch_status_code,
      line.value ->> 'sourceBucketCode' as source_bucket_code,
      (line.value ->> 'quantityRequested')::bigint as quantity_requested,
      line.value ->> 'sourceLineRef' as source_line_ref,
      (line.value ->> 'currentBatchBucketQty')::bigint as bucket_before_qty,
      (line.value ->> 'resultingBatchBucketQty')::bigint as bucket_after_qty
    from jsonb_array_elements(v_preview -> 'lines') line(value)
    order by (line.value ->> 'lineNo')::integer
  loop
    v_disposal_line_id := gen_random_uuid();
    v_ledger_entry_id := gen_random_uuid();

    insert into inventory.stock_ledger_entries (
      id,
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
      v_ledger_entry_id,
      p_organization_id,
      v_transaction_id,
      v_line.line_no,
      v_line.product_id,
      v_line.batch_id,
      v_line.product_sku,
      v_line.batch_code,
      v_line.expiry_date,
      v_line.source_bucket_code,
      -v_line.quantity_requested,
      'EXTERNAL_OUT',
      null,
      v_line.source_line_ref,
      p_occurred_at,
      v_recorded_at,
      v_recorded_at
    )
    returning ledger_seq into v_ledger_seq;

    update inventory.stock_batch_balances balance
    set
      sellable_qty = balance.sellable_qty -
        case when v_line.source_bucket_code = 'SELLABLE'
          then v_line.quantity_requested else 0 end,
      quarantine_qty = balance.quarantine_qty -
        case when v_line.source_bucket_code = 'QUARANTINE'
          then v_line.quantity_requested else 0 end,
      damaged_qty = balance.damaged_qty -
        case when v_line.source_bucket_code = 'DAMAGED'
          then v_line.quantity_requested else 0 end,
      last_ledger_seq = greatest(balance.last_ledger_seq, v_ledger_seq),
      updated_at = v_recorded_at,
      version = balance.version + 1
    where balance.organization_id = p_organization_id
      and balance.product_id = v_line.product_id
      and balance.batch_id = v_line.batch_id
      and (
        case v_line.source_bucket_code
          when 'SELLABLE' then balance.sellable_qty
          when 'QUARANTINE' then balance.quarantine_qty
          when 'DAMAGED' then balance.damaged_qty
        end
      ) >= v_line.quantity_requested;

    if not found then
      raise exception using errcode = 'P0001', message = 'DISPOSAL_EXCEEDS_BALANCE';
    end if;

    update inventory.stock_product_positions position
    set
      sellable_qty = position.sellable_qty -
        case when v_line.source_bucket_code = 'SELLABLE'
          then v_line.quantity_requested else 0 end,
      quarantine_qty = position.quarantine_qty -
        case when v_line.source_bucket_code = 'QUARANTINE'
          then v_line.quantity_requested else 0 end,
      damaged_qty = position.damaged_qty -
        case when v_line.source_bucket_code = 'DAMAGED'
          then v_line.quantity_requested else 0 end,
      last_ledger_seq = greatest(position.last_ledger_seq, v_ledger_seq),
      updated_at = v_recorded_at,
      version = position.version + 1
    where position.organization_id = p_organization_id
      and position.product_id = v_line.product_id
      and position.sellable_qty -
          case when v_line.source_bucket_code = 'SELLABLE'
            then v_line.quantity_requested else 0 end
          >= position.reserved_qty
      and position.quarantine_qty -
          case when v_line.source_bucket_code = 'QUARANTINE'
            then v_line.quantity_requested else 0 end
          >= 0
      and position.damaged_qty -
          case when v_line.source_bucket_code = 'DAMAGED'
            then v_line.quantity_requested else 0 end
          >= 0;

    if not found then
      raise exception using errcode = 'P0001', message = 'DISPOSAL_PRODUCT_POSITION_CONFLICT';
    end if;

    insert into operations.stock_disposal_lines (
      id,
      organization_id,
      disposal_id,
      line_no,
      product_id,
      batch_id,
      ledger_entry_id,
      source_bucket_code,
      quantity_disposed,
      product_sku_snapshot,
      product_name_snapshot,
      batch_code_snapshot,
      expiry_date_snapshot,
      batch_status_code_snapshot,
      source_line_ref,
      bucket_before_qty,
      bucket_after_qty,
      created_at
    ) values (
      v_disposal_line_id,
      p_organization_id,
      v_disposal_id,
      v_line.line_no,
      v_line.product_id,
      v_line.batch_id,
      v_ledger_entry_id,
      v_line.source_bucket_code,
      v_line.quantity_requested,
      v_line.product_sku,
      v_line.product_name,
      v_line.batch_code,
      v_line.expiry_date,
      v_line.batch_status_code,
      v_line.source_line_ref,
      v_line.bucket_before_qty,
      v_line.bucket_after_qty,
      v_recorded_at
    );

    v_result_lines := v_result_lines || jsonb_build_array(
      jsonb_build_object(
        'lineNo', v_line.line_no,
        'disposalLineId', v_disposal_line_id,
        'ledgerEntryId', v_ledger_entry_id,
        'ledgerSeq', v_ledger_seq,
        'productId', v_line.product_id,
        'productSku', v_line.product_sku,
        'batchId', v_line.batch_id,
        'batchCode', v_line.batch_code,
        'expiryDate', v_line.expiry_date,
        'sourceBucketCode', v_line.source_bucket_code,
        'quantity', v_line.quantity_requested,
        'bucketBeforeQty', v_line.bucket_before_qty,
        'bucketAfterQty', v_line.bucket_after_qty,
        'sourceLineRef', v_line.source_line_ref
      )
    );
  end loop;

  if exists (
    with affected as (
      select distinct line.product_id, line.batch_id
      from operations.stock_disposal_lines line
      where line.disposal_id = v_disposal_id
    ),
    ledger as (
      select
        affected.product_id,
        affected.batch_id,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'SELLABLE'
        ), 0)::bigint as sellable_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'QUARANTINE'
        ), 0)::bigint as quarantine_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'DAMAGED'
        ), 0)::bigint as damaged_qty
      from affected
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = p_organization_id
       and entry.product_id = affected.product_id
       and entry.batch_id = affected.batch_id
      group by affected.product_id, affected.batch_id
    )
    select 1
    from ledger
    join inventory.stock_batch_balances balance
      on balance.organization_id = p_organization_id
     and balance.product_id = ledger.product_id
     and balance.batch_id = ledger.batch_id
    where balance.sellable_qty <> ledger.sellable_qty
       or balance.quarantine_qty <> ledger.quarantine_qty
       or balance.damaged_qty <> ledger.damaged_qty
  ) then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_PROJECTION_DRIFT';
  end if;

  if exists (
    with affected as (
      select distinct line.product_id
      from operations.stock_disposal_lines line
      where line.disposal_id = v_disposal_id
    ),
    ledger as (
      select
        affected.product_id,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'SELLABLE'
        ), 0)::bigint as sellable_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'QUARANTINE'
        ), 0)::bigint as quarantine_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'DAMAGED'
        ), 0)::bigint as damaged_qty
      from affected
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = p_organization_id
       and entry.product_id = affected.product_id
      group by affected.product_id
    )
    select 1
    from ledger
    join inventory.stock_product_positions position
      on position.organization_id = p_organization_id
     and position.product_id = ledger.product_id
    where position.sellable_qty <> ledger.sellable_qty
       or position.quarantine_qty <> ledger.quarantine_qty
       or position.damaged_qty <> ledger.damaged_qty
  ) then
    raise exception using errcode = 'P0001', message = 'DISPOSAL_PROJECTION_DRIFT';
  end if;

  v_response := jsonb_build_object(
    'status', 'POSTED',
    'disposalId', v_disposal_id,
    'disposalNo', v_disposal_no,
    'transactionId', v_transaction_id,
    'transactionNo', v_disposal_no,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'previewBasisHash', v_expected_basis_hash,
    'sourceRef', v_source_ref,
    'reasonCode', v_reason_code,
    'channelCode', 'MANUAL',
    'referenceText', v_reference_text,
    'lineCount', jsonb_array_length(v_result_lines),
    'totalQuantity', v_total_quantity,
    'occurredAt', p_occurred_at,
    'recordedAt', v_recorded_at,
    'lines', v_result_lines
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

revoke all on function api.post_stock_disposal(
  uuid,
  text,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  boolean,
  text,
  text,
  jsonb
) from public, anon;

grant execute on function api.post_stock_disposal(
  uuid,
  text,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  boolean,
  text,
  text,
  jsonb
) to authenticated, service_role;

create or replace view api.stock_disposals
with (security_invoker = true, security_barrier = true)
as
select
  disposal.id as disposal_id,
  disposal.organization_id,
  disposal.disposal_no,
  disposal.source_ref,
  disposal.reason_code_snapshot,
  disposal.channel_code_snapshot,
  disposal.status_code,
  disposal.occurred_at,
  disposal.recorded_at,
  disposal.actor_user_id,
  disposal.process_name,
  disposal.transaction_id,
  disposal.total_quantity,
  disposal.reference_text,
  disposal.note,
  disposal.request_hash,
  disposal.metadata,
  disposal.created_at
from operations.stock_disposals disposal;

create or replace view api.stock_disposal_lines
with (security_invoker = true, security_barrier = true)
as
select
  line.id as disposal_line_id,
  line.organization_id,
  line.disposal_id,
  line.line_no,
  line.product_id,
  line.batch_id,
  line.ledger_entry_id,
  line.source_bucket_code,
  line.quantity_disposed,
  line.product_sku_snapshot,
  line.product_name_snapshot,
  line.batch_code_snapshot,
  line.expiry_date_snapshot,
  line.batch_status_code_snapshot,
  line.source_line_ref,
  line.bucket_before_qty,
  line.bucket_after_qty,
  line.created_at
from operations.stock_disposal_lines line;

create or replace view api.stock_disposal_candidates
with (security_invoker = true, security_barrier = true)
as
select
  batch.organization_id,
  batch.product_id,
  product.sku as product_sku,
  product.name as product_name,
  product.is_active as product_is_active,
  batch.id as batch_id,
  batch.batch_code,
  batch.expiry_date,
  batch.status_code as batch_status_code,
  batch.block_reason,
  batch.row_version as batch_row_version,
  coalesce(balance.sellable_qty, 0)::bigint as sellable_qty,
  coalesce(balance.quarantine_qty, 0)::bigint as quarantine_qty,
  coalesce(balance.damaged_qty, 0)::bigint as damaged_qty,
  (
    coalesce(balance.sellable_qty, 0)
    + coalesce(balance.quarantine_qty, 0)
    + coalesce(balance.damaged_qty, 0)
  )::bigint as physical_qty,
  coalesce(position.reserved_qty, 0)::bigint as reserved_qty,
  ((clock_timestamp() at time zone organization.timezone)::date) as local_date,
  (
    batch.expiry_date
    < (clock_timestamp() at time zone organization.timezone)::date
  ) as is_expired,
  (
    batch.expiry_date
    - (clock_timestamp() at time zone organization.timezone)::date
  )::integer as days_to_expiry,
  coalesce(balance.last_ledger_seq, 0)::bigint as last_ledger_seq,
  coalesce(balance.version, 0)::bigint as balance_version
from catalog.product_batches batch
join catalog.products product
  on product.organization_id = batch.organization_id
 and product.id = batch.product_id
join app.organizations organization
  on organization.id = batch.organization_id
left join inventory.stock_batch_balances balance
  on balance.organization_id = batch.organization_id
 and balance.product_id = batch.product_id
 and balance.batch_id = batch.id
left join inventory.stock_product_positions position
  on position.organization_id = batch.organization_id
 and position.product_id = batch.product_id
where (
  coalesce(balance.sellable_qty, 0)
  + coalesce(balance.quarantine_qty, 0)
  + coalesce(balance.damaged_qty, 0)
) > 0;

grant select on api.stock_disposals,
                api.stock_disposal_lines,
                api.stock_disposal_candidates
to authenticated, service_role;

-- Keep the proven generic reversal implementation intact. Rename it as the
-- base implementation, then place a narrow compatibility wrapper at the
-- original function name that removes only the unsupported-type blocker for
-- DISPOSAL. Existing API callers continue to resolve the original name.
alter function inventory.build_stock_transaction_reversal_preview(uuid, uuid)
rename to build_stock_transaction_reversal_preview_base;

revoke all
on function inventory.build_stock_transaction_reversal_preview_base(uuid, uuid)
from public, anon, authenticated, service_role;

create or replace function inventory.build_stock_transaction_reversal_preview(
  p_organization_id uuid,
  p_original_transaction_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
declare
  v_original_type text;
  v_preview jsonb;
  v_filtered_blockers jsonb;
  v_eligible boolean;
begin
  select transaction.transaction_type_code
  into v_original_type
  from inventory.stock_transactions transaction
  where transaction.organization_id = p_organization_id
    and transaction.id = p_original_transaction_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'ORIGINAL_TRANSACTION_NOT_FOUND';
  end if;

  v_preview := inventory.build_stock_transaction_reversal_preview_base(
    p_organization_id,
    p_original_transaction_id
  );

  if v_original_type = 'DISPOSAL' then
    select coalesce(jsonb_agg(blocker.value), '[]'::jsonb)
    into v_filtered_blockers
    from jsonb_array_elements(v_preview -> 'blockers') blocker(value)
    where blocker.value ->> 'code' <> 'REVERSAL_TRANSACTION_TYPE_NOT_SUPPORTED';

    v_eligible := jsonb_array_length(v_filtered_blockers) = 0;

    v_preview := jsonb_set(
      v_preview,
      '{blockers}',
      v_filtered_blockers,
      true
    );
    v_preview := jsonb_set(
      v_preview,
      '{eligible}',
      to_jsonb(v_eligible),
      true
    );
    v_preview := jsonb_set(
      v_preview,
      '{status}',
      to_jsonb(
        case when v_eligible then 'PREVIEW_READY' else 'BLOCKED' end::text
      ),
      true
    );
  end if;

  return v_preview;
end;
$$;

revoke all
on function inventory.build_stock_transaction_reversal_preview(uuid, uuid)
from public, anon, authenticated, service_role;

comment on function inventory.build_stock_transaction_reversal_preview(uuid, uuid)
is 'General reversal preview with exact-batch, exact-bucket DISPOSAL support.';

comment on table operations.stock_disposals
is 'Immutable posted damaged or expired stock disposal headers.';

comment on table operations.stock_disposal_lines
is 'Immutable exact batch and source-bucket disposal lines linked one-to-one to ledger entries.';

commit;
