begin;

create table operations.manual_outbounds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  outbound_no text not null,
  source_ref text not null,
  reason_id uuid not null references catalog.movement_reasons(id) on delete restrict,
  reason_code_snapshot text not null,
  status_code text not null default 'POSTED',
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default clock_timestamp(),
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  transaction_id uuid not null references inventory.stock_transactions(id) on delete restrict,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  total_quantity bigint not null,
  note text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint uq_manual_outbounds_org_id unique (organization_id, id),
  constraint uq_manual_outbounds_org_no unique (organization_id, outbound_no),
  constraint uq_manual_outbounds_org_source unique (organization_id, source_ref),
  constraint uq_manual_outbounds_transaction unique (transaction_id),
  constraint uq_manual_outbounds_idempotency unique (idempotency_command_id),
  constraint ck_manual_outbounds_no_nonblank check (btrim(outbound_no) <> ''),
  constraint ck_manual_outbounds_source_nonblank check (btrim(source_ref) <> ''),
  constraint ck_manual_outbounds_reason_nonblank check (btrim(reason_code_snapshot) <> ''),
  constraint ck_manual_outbounds_status check (status_code = 'POSTED'),
  constraint ck_manual_outbounds_actor_xor_process
    check ((actor_user_id is not null) <> (process_name is not null)),
  constraint ck_manual_outbounds_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),
  constraint ck_manual_outbounds_total_positive check (total_quantity > 0),
  constraint ck_manual_outbounds_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create table operations.manual_outbound_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  outbound_id uuid not null,
  line_no integer not null,
  product_id uuid not null,
  quantity_requested bigint not null,
  product_sku_snapshot text not null,
  source_line_ref text not null,
  created_at timestamptz not null default now(),
  constraint uq_manual_outbound_lines_org_id unique (organization_id, id),
  constraint fk_manual_outbound_lines_outbound
    foreign key (organization_id, outbound_id)
    references operations.manual_outbounds (organization_id, id)
    on delete restrict,
  constraint fk_manual_outbound_lines_product
    foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,
  constraint uq_manual_outbound_lines_line unique (outbound_id, line_no),
  constraint uq_manual_outbound_lines_product unique (outbound_id, product_id),
  constraint uq_manual_outbound_lines_source unique (outbound_id, source_line_ref),
  constraint ck_manual_outbound_lines_line_positive check (line_no > 0),
  constraint ck_manual_outbound_lines_quantity_positive check (quantity_requested > 0),
  constraint ck_manual_outbound_lines_sku_nonblank check (btrim(product_sku_snapshot) <> ''),
  constraint ck_manual_outbound_lines_source_nonblank check (btrim(source_line_ref) <> '')
);

create table operations.manual_outbound_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  outbound_id uuid not null,
  outbound_line_id uuid not null,
  allocation_no integer not null,
  ledger_entry_id uuid not null references inventory.stock_ledger_entries(id) on delete restrict,
  product_id uuid not null,
  batch_id uuid not null,
  quantity_allocated bigint not null,
  product_sku_snapshot text not null,
  batch_code_snapshot text not null,
  expiry_date_snapshot date not null,
  received_first_at_snapshot timestamptz null,
  source_line_ref text not null,
  created_at timestamptz not null default now(),
  constraint fk_manual_outbound_allocations_outbound
    foreign key (organization_id, outbound_id)
    references operations.manual_outbounds (organization_id, id)
    on delete restrict,
  constraint fk_manual_outbound_allocations_line
    foreign key (organization_id, outbound_line_id)
    references operations.manual_outbound_lines (organization_id, id)
    on delete restrict,
  constraint fk_manual_outbound_allocations_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches (organization_id, product_id, id)
    on delete restrict,
  constraint uq_manual_outbound_allocations_line_no
    unique (outbound_line_id, allocation_no),
  constraint uq_manual_outbound_allocations_ledger unique (ledger_entry_id),
  constraint ck_manual_outbound_allocations_no_positive check (allocation_no > 0),
  constraint ck_manual_outbound_allocations_quantity_positive check (quantity_allocated > 0),
  constraint ck_manual_outbound_allocations_sku_nonblank check (btrim(product_sku_snapshot) <> ''),
  constraint ck_manual_outbound_allocations_batch_nonblank check (btrim(batch_code_snapshot) <> ''),
  constraint ck_manual_outbound_allocations_source_nonblank check (btrim(source_line_ref) <> '')
);

create index idx_manual_outbounds_org_occurred
on operations.manual_outbounds (organization_id, occurred_at desc, id);

create index idx_manual_outbound_lines_product
on operations.manual_outbound_lines (organization_id, product_id, outbound_id, line_no);

create index idx_manual_outbound_allocations_batch
on operations.manual_outbound_allocations (
  organization_id,
  batch_id,
  outbound_id,
  outbound_line_id,
  allocation_no
);

create trigger trg_manual_outbounds_immutable
before update or delete on operations.manual_outbounds
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_manual_outbound_lines_immutable
before update or delete on operations.manual_outbound_lines
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_manual_outbound_allocations_immutable
before update or delete on operations.manual_outbound_allocations
for each row execute function inventory.reject_immutable_mutation();

alter table operations.manual_outbounds enable row level security;
alter table operations.manual_outbound_lines enable row level security;
alter table operations.manual_outbound_allocations enable row level security;

create policy manual_outbounds_read_current_org
on operations.manual_outbounds
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy manual_outbound_lines_read_current_org
on operations.manual_outbound_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy manual_outbound_allocations_read_current_org
on operations.manual_outbound_allocations
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on operations.manual_outbounds,
              operations.manual_outbound_lines,
              operations.manual_outbound_allocations
from anon, authenticated;

grant select on operations.manual_outbounds,
                operations.manual_outbound_lines,
                operations.manual_outbound_allocations
to authenticated, service_role;

create or replace function api.post_manual_outbound(
  p_organization_id uuid,
  p_idempotency_key text,
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
declare
  v_scope constant text := 'POST_MANUAL_OUTBOUND';
  v_idempotency_key text;
  v_source_ref text;
  v_reason_code text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_organization_timezone text;
  v_effective_local_date date;
  v_safety_buffer_days integer := 0;
  v_reason_id uuid;
  v_channel_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_outbound_id uuid := gen_random_uuid();
  v_transaction_id uuid := gen_random_uuid();
  v_correlation_id uuid := gen_random_uuid();
  v_outbound_no text;
  v_recorded_at timestamptz := clock_timestamp();
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_created_by_role_code text;
  v_jwt_role text := coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_total_quantity bigint;
  v_line record;
  v_outbound_line_id uuid;
  v_product_sku text;
  v_product_active boolean;
  v_product_sellable bigint;
  v_product_reserved bigint;
  v_remaining bigint;
  v_batch record;
  v_allocate bigint;
  v_allocation_no integer;
  v_ledger_line_no integer := 0;
  v_ledger_entry_id uuid;
  v_ledger_seq bigint;
  v_last_product_ledger_seq bigint;
  v_allocations jsonb := '[]'::jsonb;
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
    raise exception using errcode = 'P0001', message = 'OUTBOUND_SOURCE_REQUIRED';
  end if;
  if length(v_source_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_SOURCE_TOO_LONG';
  end if;

  v_reason_code := upper(btrim(coalesce(p_reason_code, '')));
  if v_reason_code = '' then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_REASON_REQUIRED';
  end if;
  if length(v_reason_code) > 100 then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_REASON_TOO_LONG';
  end if;

  if p_occurred_at is null then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_OCCURRED_AT_REQUIRED';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_LINES_MUST_BE_ARRAY';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_LINES_REQUIRED';
  end if;
  if jsonb_array_length(p_lines) > 200 then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_LINES_LIMIT_EXCEEDED';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_METADATA_MUST_BE_OBJECT';
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');
  if v_note is not null and length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_NOTE_TOO_LONG';
  end if;

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
  ) then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) as item(value)
    group by lower(item.value ->> 'productId')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_DUPLICATE_PRODUCT_LINE';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) as item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_DUPLICATE_SOURCE_LINE';
  end if;

  select sum((item.value ->> 'quantity')::bigint)
  into v_total_quantity
  from jsonb_array_elements(p_lines) as item(value);

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
    v_process_name := 'api.post_manual_outbound';
    v_created_by_role_code := 'SYSTEM_PROCESS';
  end if;

  v_effective_local_date := (p_occurred_at at time zone v_organization_timezone)::date;

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

  v_safety_buffer_days := coalesce(v_safety_buffer_days, 0);
  if v_safety_buffer_days < 0 or v_safety_buffer_days > 3650 then
    raise exception using errcode = 'P0001', message = 'EXPIRY_SAFETY_BUFFER_INVALID';
  end if;

  select reason.id
  into v_reason_id
  from catalog.movement_reasons reason
  where reason.code = v_reason_code
    and reason.direction_code = 'OUTBOUND'
    and reason.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_REASON_NOT_ALLOWED';
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = 'MANUAL'
    and channel.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_CHANNEL_NOT_CONFIGURED';
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
      p_organization_id::text || ':MANUAL_OUTBOUND_SOURCE:' || v_source_ref,
      0::bigint
    )
  );

  if exists (
    select 1
    from operations.manual_outbounds outbound
    where outbound.organization_id = p_organization_id
      and outbound.source_ref = v_source_ref
  ) then
    raise exception using errcode = 'P0001', message = 'OUTBOUND_SOURCE_ALREADY_POSTED';
  end if;

  v_outbound_no :=
    'OUT-' ||
    to_char(v_effective_local_date, 'YYYYMMDD') ||
    '-' ||
    upper(substr(replace(v_outbound_id::text, '-', ''), 1, 8));

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
    v_outbound_no,
    'MANUAL_OUTBOUND',
    v_reason_id,
    v_reason_code,
    v_channel_id,
    'MANUAL',
    'MANUAL_OUTBOUND',
    v_outbound_id,
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
      'outboundNo', v_outbound_no,
      'reasonCode', v_reason_code,
      'expirySafetyBufferDays', v_safety_buffer_days
    ),
    1
  );

  insert into operations.manual_outbounds (
    id,
    organization_id,
    outbound_no,
    source_ref,
    reason_id,
    reason_code_snapshot,
    status_code,
    occurred_at,
    recorded_at,
    actor_user_id,
    process_name,
    transaction_id,
    idempotency_command_id,
    total_quantity,
    note,
    metadata,
    created_at
  )
  values (
    v_outbound_id,
    p_organization_id,
    v_outbound_no,
    v_source_ref,
    v_reason_id,
    v_reason_code,
    'POSTED',
    p_occurred_at,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    v_transaction_id,
    v_command_id,
    v_total_quantity,
    v_note,
    v_metadata,
    v_recorded_at
  );

  for v_line in
    select
      item.ordinality::integer as line_no,
      (item.value ->> 'productId')::uuid as product_id,
      (item.value ->> 'quantity')::bigint as quantity_requested,
      btrim(item.value ->> 'sourceLineRef') as source_line_ref
    from jsonb_array_elements(p_lines) with ordinality as item(value, ordinality)
    order by (item.value ->> 'productId')::uuid
  loop
    perform pg_advisory_xact_lock(
      hashtextextended(
        p_organization_id::text || ':PRODUCT_STOCK:' || v_line.product_id::text,
        0::bigint
      )
    );

    v_product_sku := null;
    v_product_active := null;

    select product.sku, product.is_active
    into v_product_sku, v_product_active
    from catalog.products product
    where product.organization_id = p_organization_id
      and product.id = v_line.product_id
    for update;

    if not found then
      raise exception using errcode = 'P0001', message = 'OUTBOUND_PRODUCT_NOT_FOUND';
    end if;

    if not v_product_active then
      raise exception using errcode = 'P0001', message = 'OUTBOUND_PRODUCT_INACTIVE';
    end if;

    v_product_sellable := null;
    v_product_reserved := null;

    select position.sellable_qty, position.reserved_qty
    into v_product_sellable, v_product_reserved
    from inventory.stock_product_positions position
    where position.organization_id = p_organization_id
      and position.product_id = v_line.product_id
    for update;

    if not found
       or v_product_sellable - v_product_reserved < v_line.quantity_requested then
      raise exception using errcode = 'P0001', message = 'INSUFFICIENT_AVAILABLE_STOCK';
    end if;

    v_outbound_line_id := gen_random_uuid();

    insert into operations.manual_outbound_lines (
      id,
      organization_id,
      outbound_id,
      line_no,
      product_id,
      quantity_requested,
      product_sku_snapshot,
      source_line_ref,
      created_at
    )
    values (
      v_outbound_line_id,
      p_organization_id,
      v_outbound_id,
      v_line.line_no,
      v_line.product_id,
      v_line.quantity_requested,
      v_product_sku,
      v_line.source_line_ref,
      v_recorded_at
    );

    v_remaining := v_line.quantity_requested;
    v_allocation_no := 0;
    v_last_product_ledger_seq := null;

    for v_batch in
      select
        batch.id as batch_id,
        batch.batch_code,
        batch.expiry_date,
        batch.received_first_at,
        balance.sellable_qty
      from inventory.stock_batch_balances balance
      join catalog.product_batches batch
        on batch.organization_id = balance.organization_id
       and batch.product_id = balance.product_id
       and batch.id = balance.batch_id
      where balance.organization_id = p_organization_id
        and balance.product_id = v_line.product_id
        and balance.sellable_qty > 0
        and batch.status_code = 'ACTIVE'
        and batch.expiry_date > v_effective_local_date + v_safety_buffer_days
      order by
        batch.expiry_date,
        batch.received_first_at asc nulls last,
        batch.batch_code,
        batch.id
      for update of balance
    loop
      exit when v_remaining = 0;

      v_allocate := least(v_remaining, v_batch.sellable_qty);
      v_allocation_no := v_allocation_no + 1;
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
      )
      values (
        p_organization_id,
        v_transaction_id,
        v_ledger_line_no,
        v_line.product_id,
        v_batch.batch_id,
        v_product_sku,
        v_batch.batch_code,
        v_batch.expiry_date,
        'SELLABLE',
        -v_allocate,
        'EXTERNAL_OUT',
        null,
        v_line.source_line_ref || ':' || v_allocation_no::text,
        p_occurred_at,
        v_recorded_at,
        v_recorded_at
      )
      returning id, ledger_seq into v_ledger_entry_id, v_ledger_seq;

      update inventory.stock_batch_balances balance
      set
        sellable_qty = balance.sellable_qty - v_allocate,
        last_ledger_seq = greatest(balance.last_ledger_seq, v_ledger_seq),
        updated_at = v_recorded_at,
        version = balance.version + 1
      where balance.organization_id = p_organization_id
        and balance.batch_id = v_batch.batch_id;

      insert into operations.manual_outbound_allocations (
        organization_id,
        outbound_id,
        outbound_line_id,
        allocation_no,
        ledger_entry_id,
        product_id,
        batch_id,
        quantity_allocated,
        product_sku_snapshot,
        batch_code_snapshot,
        expiry_date_snapshot,
        received_first_at_snapshot,
        source_line_ref,
        created_at
      )
      values (
        p_organization_id,
        v_outbound_id,
        v_outbound_line_id,
        v_allocation_no,
        v_ledger_entry_id,
        v_line.product_id,
        v_batch.batch_id,
        v_allocate,
        v_product_sku,
        v_batch.batch_code,
        v_batch.expiry_date,
        v_batch.received_first_at,
        v_line.source_line_ref,
        v_recorded_at
      );

      v_allocations := v_allocations || jsonb_build_array(
        jsonb_build_object(
          'lineNo', v_line.line_no,
          'sourceLineRef', v_line.source_line_ref,
          'allocationNo', v_allocation_no,
          'productId', v_line.product_id,
          'productSku', v_product_sku,
          'batchId', v_batch.batch_id,
          'batchCode', v_batch.batch_code,
          'expiryDate', v_batch.expiry_date,
          'quantity', v_allocate,
          'ledgerSeq', v_ledger_seq
        )
      );

      v_last_product_ledger_seq := v_ledger_seq;
      v_remaining := v_remaining - v_allocate;
    end loop;

    if v_remaining > 0 then
      raise exception using errcode = 'P0001', message = 'INSUFFICIENT_FEFO_STOCK';
    end if;

    update inventory.stock_product_positions position
    set
      sellable_qty = position.sellable_qty - v_line.quantity_requested,
      last_ledger_seq = greatest(position.last_ledger_seq, v_last_product_ledger_seq),
      updated_at = v_recorded_at,
      version = position.version + 1
    where position.organization_id = p_organization_id
      and position.product_id = v_line.product_id;
  end loop;

  v_response := jsonb_build_object(
    'status', 'POSTED',
    'outboundId', v_outbound_id,
    'outboundNo', v_outbound_no,
    'transactionId', v_transaction_id,
    'transactionNo', v_outbound_no,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'reasonCode', v_reason_code,
    'lineCount', jsonb_array_length(p_lines),
    'allocationCount', jsonb_array_length(v_allocations),
    'totalQuantity', v_total_quantity,
    'expirySafetyBufferDays', v_safety_buffer_days,
    'occurredAt', p_occurred_at,
    'recordedAt', v_recorded_at,
    'allocations', v_allocations
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

revoke all on function api.post_manual_outbound(
  uuid,
  text,
  text,
  timestamptz,
  text,
  jsonb,
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
  jsonb
) to authenticated, service_role;

create or replace view api.manual_outbounds
with (security_invoker = true)
as
select
  outbound.id as outbound_id,
  outbound.organization_id,
  outbound.outbound_no,
  outbound.source_ref,
  outbound.reason_code_snapshot,
  outbound.status_code,
  outbound.occurred_at,
  outbound.recorded_at,
  outbound.actor_user_id,
  outbound.process_name,
  outbound.transaction_id,
  outbound.total_quantity,
  outbound.note,
  outbound.metadata,
  outbound.created_at
from operations.manual_outbounds outbound;

create or replace view api.manual_outbound_lines
with (security_invoker = true)
as
select
  line.id as outbound_line_id,
  line.organization_id,
  line.outbound_id,
  line.line_no,
  line.product_id,
  line.quantity_requested,
  line.product_sku_snapshot,
  line.source_line_ref,
  line.created_at
from operations.manual_outbound_lines line;

create or replace view api.manual_outbound_allocations
with (security_invoker = true)
as
select
  allocation.id as allocation_id,
  allocation.organization_id,
  allocation.outbound_id,
  allocation.outbound_line_id,
  allocation.allocation_no,
  allocation.ledger_entry_id,
  allocation.product_id,
  allocation.batch_id,
  allocation.quantity_allocated,
  allocation.product_sku_snapshot,
  allocation.batch_code_snapshot,
  allocation.expiry_date_snapshot,
  allocation.received_first_at_snapshot,
  allocation.source_line_ref,
  allocation.created_at
from operations.manual_outbound_allocations allocation;

revoke all on api.manual_outbounds,
              api.manual_outbound_lines,
              api.manual_outbound_allocations
from anon;

grant select on api.manual_outbounds,
                api.manual_outbound_lines,
                api.manual_outbound_allocations
to authenticated, service_role;

commit;
