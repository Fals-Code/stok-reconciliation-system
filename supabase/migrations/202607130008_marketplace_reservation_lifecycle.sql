begin;

alter table inventory.stock_reservations
  drop constraint ck_stock_reservations_status,
  drop constraint ck_stock_reservations_closed_state;

alter table inventory.stock_reservations
  add constraint ck_stock_reservations_status check (
    status_code in (
      'ACTIVE',
      'PARTIALLY_CONSUMED',
      'PARTIALLY_RELEASED',
      'PARTIALLY_CLOSED',
      'CONSUMED',
      'RELEASED',
      'CLOSED_MIXED'
    )
  ),
  add constraint ck_stock_reservations_closed_state check (
    (
      status_code in (
        'ACTIVE',
        'PARTIALLY_CONSUMED',
        'PARTIALLY_RELEASED',
        'PARTIALLY_CLOSED'
      )
      and closed_at is null
    )
    or (
      status_code in ('CONSUMED', 'RELEASED', 'CLOSED_MIXED')
      and closed_at is not null
    )
  );

create table operations.marketplace_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  channel_id uuid not null references catalog.channels(id) on delete restrict,
  external_order_ref text not null,
  status_code text not null default 'RESERVED',
  reserved_at timestamptz not null,
  closed_at timestamptz null,
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint uq_marketplace_orders_org_id unique (organization_id, id),
  constraint uq_marketplace_orders_external unique (
    organization_id,
    channel_id,
    external_order_ref
  ),
  constraint ck_marketplace_orders_ref_nonblank check (
    btrim(external_order_ref) <> ''
  ),
  constraint ck_marketplace_orders_status check (
    status_code in (
      'RESERVED',
      'PARTIALLY_CLOSED',
      'SHIPPED',
      'CANCELLED',
      'CLOSED_MIXED'
    )
  ),
  constraint ck_marketplace_orders_closed_state check (
    (
      status_code in ('RESERVED', 'PARTIALLY_CLOSED')
      and closed_at is null
    )
    or (
      status_code in ('SHIPPED', 'CANCELLED', 'CLOSED_MIXED')
      and closed_at is not null
    )
  ),
  constraint ck_marketplace_orders_actor_xor_process check (
    (actor_user_id is not null) <> (process_name is not null)
  ),
  constraint ck_marketplace_orders_process_nonblank check (
    process_name is null or btrim(process_name) <> ''
  ),
  constraint ck_marketplace_orders_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  )
);

create trigger trg_marketplace_orders_touch_updated_at
before update on operations.marketplace_orders
for each row execute function app.touch_updated_at();

create table operations.marketplace_order_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  order_id uuid not null,
  line_no integer not null,
  external_item_ref text not null,
  product_id uuid not null,
  quantity_ordered bigint not null,
  product_sku_snapshot text not null,
  reservation_id uuid not null references inventory.stock_reservations(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_marketplace_order_items_org_id unique (organization_id, id),
  constraint fk_marketplace_order_items_order foreign key (organization_id, order_id)
    references operations.marketplace_orders (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_order_items_product foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,
  constraint uq_marketplace_order_items_line unique (order_id, line_no),
  constraint uq_marketplace_order_items_external unique (order_id, external_item_ref),
  constraint uq_marketplace_order_items_reservation unique (reservation_id),
  constraint ck_marketplace_order_items_line_positive check (line_no > 0),
  constraint ck_marketplace_order_items_quantity_positive check (quantity_ordered > 0),
  constraint ck_marketplace_order_items_ref_nonblank check (btrim(external_item_ref) <> ''),
  constraint ck_marketplace_order_items_sku_nonblank check (btrim(product_sku_snapshot) <> '')
);

create table operations.marketplace_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  order_id uuid not null,
  channel_id uuid not null references catalog.channels(id) on delete restrict,
  external_event_ref text not null,
  event_type_code text not null,
  status_code text not null default 'APPLIED',
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default clock_timestamp(),
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  transaction_id uuid null references inventory.stock_transactions(id) on delete restrict,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  note text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_marketplace_events_org_id unique (organization_id, id),
  constraint fk_marketplace_events_order foreign key (organization_id, order_id)
    references operations.marketplace_orders (organization_id, id)
    on delete restrict,
  constraint uq_marketplace_events_external unique (
    organization_id,
    channel_id,
    external_event_ref
  ),
  constraint uq_marketplace_events_idempotency unique (idempotency_command_id),
  constraint uq_marketplace_events_transaction unique (transaction_id),
  constraint ck_marketplace_events_ref_nonblank check (btrim(external_event_ref) <> ''),
  constraint ck_marketplace_events_type check (
    event_type_code in ('RESERVE', 'RELEASE', 'SHIP')
  ),
  constraint ck_marketplace_events_status check (status_code = 'APPLIED'),
  constraint ck_marketplace_events_transaction_rule check (
    (event_type_code = 'SHIP' and transaction_id is not null)
    or (event_type_code in ('RESERVE', 'RELEASE') and transaction_id is null)
  ),
  constraint ck_marketplace_events_actor_xor_process check (
    (actor_user_id is not null) <> (process_name is not null)
  ),
  constraint ck_marketplace_events_process_nonblank check (
    process_name is null or btrim(process_name) <> ''
  ),
  constraint ck_marketplace_events_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  )
);

create table operations.marketplace_event_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  event_id uuid not null,
  line_no integer not null,
  order_item_id uuid not null,
  product_id uuid not null,
  quantity bigint not null,
  source_line_ref text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_marketplace_event_lines_org_id unique (organization_id, id),
  constraint fk_marketplace_event_lines_event foreign key (organization_id, event_id)
    references operations.marketplace_events (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_event_lines_item foreign key (organization_id, order_item_id)
    references operations.marketplace_order_items (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_event_lines_product foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,
  constraint uq_marketplace_event_lines_line unique (event_id, line_no),
  constraint uq_marketplace_event_lines_source unique (event_id, source_line_ref),
  constraint ck_marketplace_event_lines_line_positive check (line_no > 0),
  constraint ck_marketplace_event_lines_quantity_positive check (quantity > 0),
  constraint ck_marketplace_event_lines_source_nonblank check (btrim(source_line_ref) <> '')
);

create table operations.marketplace_ship_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  event_id uuid not null,
  event_line_id uuid not null,
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
  created_at timestamptz not null default clock_timestamp(),
  constraint fk_marketplace_ship_allocations_event foreign key (organization_id, event_id)
    references operations.marketplace_events (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_ship_allocations_event_line foreign key (organization_id, event_line_id)
    references operations.marketplace_event_lines (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_ship_allocations_batch foreign key (
    organization_id,
    product_id,
    batch_id
  ) references catalog.product_batches (organization_id, product_id, id)
    on delete restrict,
  constraint uq_marketplace_ship_allocations_line_no unique (event_line_id, allocation_no),
  constraint uq_marketplace_ship_allocations_ledger unique (ledger_entry_id),
  constraint ck_marketplace_ship_allocations_no_positive check (allocation_no > 0),
  constraint ck_marketplace_ship_allocations_quantity_positive check (quantity_allocated > 0),
  constraint ck_marketplace_ship_allocations_sku_nonblank check (btrim(product_sku_snapshot) <> ''),
  constraint ck_marketplace_ship_allocations_batch_nonblank check (btrim(batch_code_snapshot) <> ''),
  constraint ck_marketplace_ship_allocations_source_nonblank check (btrim(source_line_ref) <> '')
);

create index idx_marketplace_orders_status
on operations.marketplace_orders (
  organization_id,
  channel_id,
  status_code,
  reserved_at,
  id
);

create index idx_marketplace_order_items_product
on operations.marketplace_order_items (organization_id, product_id, order_id, line_no);

create index idx_marketplace_events_order
on operations.marketplace_events (organization_id, order_id, occurred_at, id);

create index idx_marketplace_ship_allocations_batch
on operations.marketplace_ship_allocations (organization_id, batch_id, event_id, allocation_no);

create trigger trg_marketplace_order_items_immutable
before update or delete on operations.marketplace_order_items
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_marketplace_events_immutable
before update or delete on operations.marketplace_events
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_marketplace_event_lines_immutable
before update or delete on operations.marketplace_event_lines
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_marketplace_ship_allocations_immutable
before update or delete on operations.marketplace_ship_allocations
for each row execute function inventory.reject_immutable_mutation();

alter table operations.marketplace_orders enable row level security;
alter table operations.marketplace_order_items enable row level security;
alter table operations.marketplace_events enable row level security;
alter table operations.marketplace_event_lines enable row level security;
alter table operations.marketplace_ship_allocations enable row level security;

create policy marketplace_orders_read_current_org
on operations.marketplace_orders
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy marketplace_order_items_read_current_org
on operations.marketplace_order_items
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy marketplace_events_read_current_org
on operations.marketplace_events
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy marketplace_event_lines_read_current_org
on operations.marketplace_event_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy marketplace_ship_allocations_read_current_org
on operations.marketplace_ship_allocations
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on operations.marketplace_orders,
              operations.marketplace_order_items,
              operations.marketplace_events,
              operations.marketplace_event_lines,
              operations.marketplace_ship_allocations
from anon, authenticated;

grant usage on schema operations to authenticated, service_role;

grant select on operations.marketplace_orders,
                operations.marketplace_order_items,
                operations.marketplace_events,
                operations.marketplace_event_lines,
                operations.marketplace_ship_allocations
  to authenticated, service_role;

create or replace function operations.refresh_reservation_status(
  p_reservation_id uuid,
  p_closed_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, inventory
as $$
begin
  update inventory.stock_reservations reservation
  set
    status_code = case
      when reservation.consumed_qty + reservation.released_qty < reservation.reserved_qty then
        case
          when reservation.consumed_qty > 0 and reservation.released_qty > 0 then 'PARTIALLY_CLOSED'
          when reservation.consumed_qty > 0 then 'PARTIALLY_CONSUMED'
          when reservation.released_qty > 0 then 'PARTIALLY_RELEASED'
          else 'ACTIVE'
        end
      when reservation.consumed_qty = reservation.reserved_qty then 'CONSUMED'
      when reservation.released_qty = reservation.reserved_qty then 'RELEASED'
      else 'CLOSED_MIXED'
    end,
    closed_at = case
      when reservation.consumed_qty + reservation.released_qty = reservation.reserved_qty
        then p_closed_at
      else null
    end
  where reservation.id = p_reservation_id;
end;
$$;

revoke all on function operations.refresh_reservation_status(uuid, timestamptz)
from public, anon, authenticated;

create or replace function operations.refresh_marketplace_order_status(
  p_organization_id uuid,
  p_order_id uuid,
  p_closed_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, inventory, operations
as $$
declare
  v_reserved bigint;
  v_consumed bigint;
  v_released bigint;
begin
  select
    sum(reservation.reserved_qty),
    sum(reservation.consumed_qty),
    sum(reservation.released_qty)
  into v_reserved, v_consumed, v_released
  from operations.marketplace_order_items item
  join inventory.stock_reservations reservation
    on reservation.id = item.reservation_id
  where item.organization_id = p_organization_id
    and item.order_id = p_order_id;

  if v_reserved is null then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_ORDER_ITEMS_REQUIRED';
  end if;

  update operations.marketplace_orders marketplace_order
  set
    status_code = case
      when v_consumed + v_released < v_reserved then
        case
          when v_consumed + v_released = 0 then 'RESERVED'
          else 'PARTIALLY_CLOSED'
        end
      when v_consumed = v_reserved then 'SHIPPED'
      when v_released = v_reserved then 'CANCELLED'
      else 'CLOSED_MIXED'
    end,
    closed_at = case
      when v_consumed + v_released = v_reserved then p_closed_at
      else null
    end
  where marketplace_order.organization_id = p_organization_id
    and marketplace_order.id = p_order_id;
end;
$$;

revoke all on function operations.refresh_marketplace_order_status(uuid, uuid, timestamptz)
from public, anon, authenticated;

create or replace function api.apply_marketplace_event(
  p_organization_id uuid,
  p_idempotency_key text,
  p_channel_code text,
  p_event_type text,
  p_event_ref text,
  p_order_ref text,
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
  v_scope constant text := 'APPLY_MARKETPLACE_EVENT';
  v_idempotency_key text;
  v_channel_code text;
  v_event_type text;
  v_event_ref text;
  v_order_ref text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_timezone text;
  v_effective_local_date date;
  v_safety_buffer_days integer := 0;
  v_channel_id uuid;
  v_reason_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_order_id uuid;
  v_event_id uuid := gen_random_uuid();
  v_transaction_id uuid;
  v_transaction_no text;
  v_recorded_at timestamptz := clock_timestamp();
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_created_by_role_code text;
  v_jwt_role text := coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_total_quantity bigint;
  v_line record;
  v_product_sku text;
  v_product_active boolean;
  v_product_sellable bigint;
  v_product_reserved bigint;
  v_order_item_id uuid;
  v_reservation_id uuid;
  v_reservation_reserved_qty bigint;
  v_reservation_consumed_qty bigint;
  v_reservation_released_qty bigint;
  v_event_line_id uuid;
  v_remaining bigint;
  v_batch record;
  v_allocate bigint;
  v_allocation_no integer;
  v_ledger_line_no integer := 0;
  v_ledger_entry_id uuid;
  v_ledger_seq bigint;
  v_last_product_ledger_seq bigint;
  v_allocations jsonb := '[]'::jsonb;
  v_line_results jsonb := '[]'::jsonb;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  v_channel_code := upper(btrim(coalesce(p_channel_code, '')));
  v_event_type := upper(btrim(coalesce(p_event_type, '')));
  v_event_ref := btrim(coalesce(p_event_ref, ''));
  v_order_ref := btrim(coalesce(p_order_ref, ''));
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;
  if v_channel_code = '' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_CHANNEL_REQUIRED';
  end if;
  if v_event_type not in ('RESERVE', 'RELEASE', 'SHIP') then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_EVENT_TYPE_INVALID';
  end if;
  if v_event_ref = '' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_EVENT_REF_REQUIRED';
  end if;
  if length(v_event_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_EVENT_REF_TOO_LONG';
  end if;
  if v_order_ref = '' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_ORDER_REF_REQUIRED';
  end if;
  if length(v_order_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_ORDER_REF_TOO_LONG';
  end if;
  if p_occurred_at is null then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_OCCURRED_AT_REQUIRED';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) = 0 then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_LINES_REQUIRED';
  end if;
  if jsonb_array_length(p_lines) > 200 then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_LINES_LIMIT_EXCEEDED';
  end if;
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_METADATA_MUST_BE_OBJECT';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_NOTE_TOO_LONG';
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
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_DUPLICATE_SOURCE_LINE';
  end if;

  select sum((item.value ->> 'quantity')::bigint)
  into v_total_quantity
  from jsonb_array_elements(p_lines) item(value);

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
    v_process_name := 'api.apply_marketplace_event';
    v_created_by_role_code := 'SYSTEM_PROCESS';
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = v_channel_code
    and channel.is_marketplace
    and channel.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_CHANNEL_NOT_ALLOWED';
  end if;

  v_effective_local_date := (p_occurred_at at time zone v_timezone)::date;

  if v_event_type = 'SHIP' then
    select reason.id
    into v_reason_id
    from catalog.movement_reasons reason
    where reason.code = 'MARKETPLACE_SALE'
      and reason.direction_code = 'OUTBOUND'
      and reason.is_active;

    if not found then
      raise exception using errcode = 'P0001', message = 'MARKETPLACE_REASON_NOT_CONFIGURED';
    end if;

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
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'channelCode', v_channel_code,
          'eventType', v_event_type,
          'eventRef', v_event_ref,
          'orderRef', v_order_ref,
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
      p_organization_id::text || ':MARKETPLACE_EVENT:' || v_channel_code || ':' || v_event_ref,
      0::bigint
    )
  );

  if exists (
    select 1
    from operations.marketplace_events marketplace_event
    where marketplace_event.organization_id = p_organization_id
      and marketplace_event.channel_id = v_channel_id
      and marketplace_event.external_event_ref = v_event_ref
  ) then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_EVENT_ALREADY_APPLIED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':MARKETPLACE_ORDER:' || v_channel_code || ':' || v_order_ref,
      0::bigint
    )
  );

  if v_event_type = 'RESERVE' then
    if exists (
      select 1
      from operations.marketplace_orders marketplace_order
      where marketplace_order.organization_id = p_organization_id
        and marketplace_order.channel_id = v_channel_id
        and marketplace_order.external_order_ref = v_order_ref
    ) then
      raise exception using errcode = 'P0001', message = 'MARKETPLACE_ORDER_ALREADY_EXISTS';
    end if;
    v_order_id := gen_random_uuid();
  else
    select marketplace_order.id
    into v_order_id
    from operations.marketplace_orders marketplace_order
    where marketplace_order.organization_id = p_organization_id
      and marketplace_order.channel_id = v_channel_id
      and marketplace_order.external_order_ref = v_order_ref
    for update;

    if not found then
      raise exception using errcode = 'P0001', message = 'MARKETPLACE_ORDER_NOT_FOUND';
    end if;
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

  if v_event_type = 'RESERVE' then
    insert into operations.marketplace_orders (
      id,
      organization_id,
      channel_id,
      external_order_ref,
      status_code,
      reserved_at,
      closed_at,
      actor_user_id,
      process_name,
      metadata,
      created_at,
      updated_at
    ) values (
      v_order_id,
      p_organization_id,
      v_channel_id,
      v_order_ref,
      'RESERVED',
      p_occurred_at,
      null,
      v_actor_user_id,
      v_process_name,
      v_metadata,
      v_recorded_at,
      v_recorded_at
    );
  end if;

  if v_event_type = 'SHIP' then
    v_transaction_id := gen_random_uuid();
    v_transaction_no :=
      'MKT-' ||
      to_char(v_effective_local_date, 'YYYYMMDD') ||
      '-' ||
      upper(substr(replace(v_event_id::text, '-', ''), 1, 8));

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
      'MARKETPLACE_OUTBOUND',
      v_reason_id,
      'MARKETPLACE_SALE',
      v_channel_id,
      v_channel_code,
      'MARKETPLACE_ORDER',
      v_order_id,
      v_order_ref,
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
        'eventRef', v_event_ref,
        'eventType', v_event_type,
        'expirySafetyBufferDays', v_safety_buffer_days
      ),
      1
    );
  end if;

  insert into operations.marketplace_events (
    id,
    organization_id,
    order_id,
    channel_id,
    external_event_ref,
    event_type_code,
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
  ) values (
    v_event_id,
    p_organization_id,
    v_order_id,
    v_channel_id,
    v_event_ref,
    v_event_type,
    'APPLIED',
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
      (item.value ->> 'quantity')::bigint as quantity,
      btrim(item.value ->> 'sourceLineRef') as source_line_ref
    from jsonb_array_elements(p_lines) with ordinality item(value, ordinality)
    order by (item.value ->> 'productId')::uuid, btrim(item.value ->> 'sourceLineRef')
  loop
    perform pg_advisory_xact_lock(
      hashtextextended(
        p_organization_id::text || ':PRODUCT_STOCK:' || v_line.product_id::text,
        0::bigint
      )
    );

    if v_event_type = 'RESERVE' then
      select product.sku, product.is_active
      into v_product_sku, v_product_active
      from catalog.products product
      where product.organization_id = p_organization_id
        and product.id = v_line.product_id
      for update;

      if not found then
        raise exception using errcode = 'P0001', message = 'MARKETPLACE_PRODUCT_NOT_FOUND';
      end if;
      if not v_product_active then
        raise exception using errcode = 'P0001', message = 'MARKETPLACE_PRODUCT_INACTIVE';
      end if;

      select position.sellable_qty, position.reserved_qty
      into v_product_sellable, v_product_reserved
      from inventory.stock_product_positions position
      where position.organization_id = p_organization_id
        and position.product_id = v_line.product_id
      for update;

      if not found
         or v_product_sellable - v_product_reserved < v_line.quantity then
        raise exception using errcode = 'P0001', message = 'INSUFFICIENT_AVAILABLE_STOCK';
      end if;

      v_order_item_id := gen_random_uuid();
      v_reservation_id := gen_random_uuid();

      insert into inventory.stock_reservations (
        id,
        organization_id,
        order_id,
        order_item_id,
        product_id,
        reserved_qty,
        consumed_qty,
        released_qty,
        status_code,
        reserved_at,
        closed_at,
        created_at
      ) values (
        v_reservation_id,
        p_organization_id,
        v_order_id,
        v_order_item_id,
        v_line.product_id,
        v_line.quantity,
        0,
        0,
        'ACTIVE',
        p_occurred_at,
        null,
        v_recorded_at
      );

      insert into operations.marketplace_order_items (
        id,
        organization_id,
        order_id,
        line_no,
        external_item_ref,
        product_id,
        quantity_ordered,
        product_sku_snapshot,
        reservation_id,
        created_at
      ) values (
        v_order_item_id,
        p_organization_id,
        v_order_id,
        v_line.line_no,
        v_line.source_line_ref,
        v_line.product_id,
        v_line.quantity,
        v_product_sku,
        v_reservation_id,
        v_recorded_at
      );

      update inventory.stock_product_positions position
      set
        reserved_qty = position.reserved_qty + v_line.quantity,
        updated_at = v_recorded_at,
        version = position.version + 1
      where position.organization_id = p_organization_id
        and position.product_id = v_line.product_id;
    else
      select
        item.id,
        item.reservation_id,
        item.product_sku_snapshot,
        reservation.reserved_qty,
        reservation.consumed_qty,
        reservation.released_qty
      into
        v_order_item_id,
        v_reservation_id,
        v_product_sku,
        v_reservation_reserved_qty,
        v_reservation_consumed_qty,
        v_reservation_released_qty
      from operations.marketplace_order_items item
      join inventory.stock_reservations reservation
        on reservation.id = item.reservation_id
      where item.organization_id = p_organization_id
        and item.order_id = v_order_id
        and item.external_item_ref = v_line.source_line_ref
        and item.product_id = v_line.product_id
      for update of reservation;

      if not found then
        raise exception using errcode = 'P0001', message = 'MARKETPLACE_ORDER_ITEM_NOT_FOUND';
      end if;

      v_remaining :=
        v_reservation_reserved_qty -
        v_reservation_consumed_qty -
        v_reservation_released_qty;

      if v_line.quantity > v_remaining then
        raise exception using errcode = 'P0001', message = 'MARKETPLACE_RESERVATION_EXCEEDED';
      end if;
    end if;

    insert into operations.marketplace_event_lines (
      organization_id,
      event_id,
      line_no,
      order_item_id,
      product_id,
      quantity,
      source_line_ref,
      created_at
    ) values (
      p_organization_id,
      v_event_id,
      v_line.line_no,
      v_order_item_id,
      v_line.product_id,
      v_line.quantity,
      v_line.source_line_ref,
      v_recorded_at
    ) returning id into v_event_line_id;

    if v_event_type = 'RELEASE' then
      select position.sellable_qty, position.reserved_qty
      into v_product_sellable, v_product_reserved
      from inventory.stock_product_positions position
      where position.organization_id = p_organization_id
        and position.product_id = v_line.product_id
      for update;

      if not found or v_product_reserved < v_line.quantity then
        raise exception using errcode = 'P0001', message = 'RESERVATION_PROJECTION_MISMATCH';
      end if;

      update inventory.stock_reservations reservation
      set released_qty = reservation.released_qty + v_line.quantity
      where reservation.id = v_reservation_id;

      update inventory.stock_product_positions position
      set
        reserved_qty = position.reserved_qty - v_line.quantity,
        updated_at = v_recorded_at,
        version = position.version + 1
      where position.organization_id = p_organization_id
        and position.product_id = v_line.product_id;

      perform operations.refresh_reservation_status(v_reservation_id, p_occurred_at);
    elsif v_event_type = 'SHIP' then
      select position.sellable_qty, position.reserved_qty
      into v_product_sellable, v_product_reserved
      from inventory.stock_product_positions position
      where position.organization_id = p_organization_id
        and position.product_id = v_line.product_id
      for update;

      if not found
         or v_product_reserved < v_line.quantity
         or v_product_sellable < v_line.quantity then
        raise exception using errcode = 'P0001', message = 'RESERVATION_PROJECTION_MISMATCH';
      end if;

      v_remaining := v_line.quantity;
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
          source_line_ref,
          occurred_at,
          recorded_at,
          created_at
        ) values (
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
          v_line.source_line_ref || ':' || v_allocation_no::text,
          p_occurred_at,
          v_recorded_at,
          v_recorded_at
        ) returning id, ledger_seq into v_ledger_entry_id, v_ledger_seq;

        update inventory.stock_batch_balances balance
        set
          sellable_qty = balance.sellable_qty - v_allocate,
          last_ledger_seq = greatest(balance.last_ledger_seq, v_ledger_seq),
          updated_at = v_recorded_at,
          version = balance.version + 1
        where balance.organization_id = p_organization_id
          and balance.batch_id = v_batch.batch_id;

        insert into operations.marketplace_ship_allocations (
          organization_id,
          event_id,
          event_line_id,
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
        ) values (
          p_organization_id,
          v_event_id,
          v_event_line_id,
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
        sellable_qty = position.sellable_qty - v_line.quantity,
        reserved_qty = position.reserved_qty - v_line.quantity,
        last_ledger_seq = greatest(position.last_ledger_seq, v_last_product_ledger_seq),
        updated_at = v_recorded_at,
        version = position.version + 1
      where position.organization_id = p_organization_id
        and position.product_id = v_line.product_id;

      update inventory.stock_reservations reservation
      set consumed_qty = reservation.consumed_qty + v_line.quantity
      where reservation.id = v_reservation_id;

      perform operations.refresh_reservation_status(v_reservation_id, p_occurred_at);
    end if;

    v_line_results := v_line_results || jsonb_build_array(
      jsonb_build_object(
        'sourceLineRef', v_line.source_line_ref,
        'productId', v_line.product_id,
        'quantity', v_line.quantity
      )
    );
  end loop;

  perform operations.refresh_marketplace_order_status(
    p_organization_id,
    v_order_id,
    p_occurred_at
  );

  v_response := jsonb_build_object(
    'status', 'APPLIED',
    'eventId', v_event_id,
    'eventType', v_event_type,
    'eventRef', v_event_ref,
    'orderId', v_order_id,
    'orderRef', v_order_ref,
    'channelCode', v_channel_code,
    'transactionId', v_transaction_id,
    'transactionNo', v_transaction_no,
    'lineCount', jsonb_array_length(p_lines),
    'allocationCount', jsonb_array_length(v_allocations),
    'totalQuantity', v_total_quantity,
    'occurredAt', p_occurred_at,
    'recordedAt', v_recorded_at,
    'lines', v_line_results,
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

revoke all on function api.apply_marketplace_event(
  uuid,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  jsonb,
  text,
  jsonb
) from public, anon;

grant execute on function api.apply_marketplace_event(
  uuid,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  jsonb,
  text,
  jsonb
) to authenticated, service_role;

create or replace view api.marketplace_orders
with (security_invoker = true)
as
select
  marketplace_order.id as order_id,
  marketplace_order.organization_id,
  channel.code as channel_code,
  marketplace_order.external_order_ref,
  marketplace_order.status_code,
  marketplace_order.reserved_at,
  marketplace_order.closed_at,
  marketplace_order.actor_user_id,
  marketplace_order.process_name,
  marketplace_order.metadata,
  marketplace_order.created_at,
  marketplace_order.updated_at,
  coalesce(sum(reservation.reserved_qty), 0) as reserved_qty,
  coalesce(sum(reservation.consumed_qty), 0) as shipped_qty,
  coalesce(sum(reservation.released_qty), 0) as released_qty,
  coalesce(
    sum(
      reservation.reserved_qty - reservation.consumed_qty - reservation.released_qty
    ),
    0
  ) as open_qty
from operations.marketplace_orders marketplace_order
join catalog.channels channel on channel.id = marketplace_order.channel_id
left join operations.marketplace_order_items item
  on item.organization_id = marketplace_order.organization_id
 and item.order_id = marketplace_order.id
left join inventory.stock_reservations reservation
  on reservation.id = item.reservation_id
group by marketplace_order.id, channel.code;

create or replace view api.marketplace_reservations
with (security_invoker = true)
as
select
  marketplace_order.organization_id,
  marketplace_order.id as order_id,
  channel.code as channel_code,
  marketplace_order.external_order_ref,
  item.id as order_item_id,
  item.line_no,
  item.external_item_ref,
  item.product_id,
  item.product_sku_snapshot,
  item.quantity_ordered,
  reservation.id as reservation_id,
  reservation.reserved_qty,
  reservation.consumed_qty,
  reservation.released_qty,
  reservation.reserved_qty - reservation.consumed_qty - reservation.released_qty as open_qty,
  reservation.status_code,
  reservation.reserved_at,
  reservation.closed_at
from operations.marketplace_orders marketplace_order
join catalog.channels channel on channel.id = marketplace_order.channel_id
join operations.marketplace_order_items item
  on item.organization_id = marketplace_order.organization_id
 and item.order_id = marketplace_order.id
join inventory.stock_reservations reservation
  on reservation.id = item.reservation_id;

create or replace view api.marketplace_events
with (security_invoker = true)
as
select
  marketplace_event.id as event_id,
  marketplace_event.organization_id,
  marketplace_event.order_id,
  channel.code as channel_code,
  marketplace_event.external_event_ref,
  marketplace_event.event_type_code,
  marketplace_event.status_code,
  marketplace_event.occurred_at,
  marketplace_event.recorded_at,
  marketplace_event.actor_user_id,
  marketplace_event.process_name,
  marketplace_event.transaction_id,
  marketplace_event.note,
  marketplace_event.metadata,
  marketplace_event.created_at
from operations.marketplace_events marketplace_event
join catalog.channels channel on channel.id = marketplace_event.channel_id;

create or replace view api.marketplace_ship_allocations
with (security_invoker = true)
as
select
  allocation.id as allocation_id,
  allocation.organization_id,
  allocation.event_id,
  allocation.event_line_id,
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
from operations.marketplace_ship_allocations allocation;

revoke all on api.marketplace_orders,
              api.marketplace_reservations,
              api.marketplace_events,
              api.marketplace_ship_allocations
from anon;

grant select on api.marketplace_orders,
                api.marketplace_reservations,
                api.marketplace_events,
                api.marketplace_ship_allocations
  to authenticated, service_role;

commit;
