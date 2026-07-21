begin;

alter table operations.marketplace_events
drop constraint ck_marketplace_events_type;

alter table operations.marketplace_events
add constraint ck_marketplace_events_type
check (
  event_type_code in ('RESERVE', 'RELEASE', 'SHIP', 'CANCEL')
);

alter table operations.marketplace_events
drop constraint ck_marketplace_events_transaction_rule;

alter table operations.marketplace_events
add constraint ck_marketplace_events_transaction_rule
check (
  (
    event_type_code = 'SHIP'
    and transaction_id is not null
  )
  or (
    event_type_code in ('RESERVE', 'RELEASE', 'CANCEL')
    and transaction_id is null
  )
);

create table operations.marketplace_cancellations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  cancellation_no text not null,
  event_id uuid not null,
  order_id uuid not null,
  channel_id uuid not null references catalog.channels(id) on delete restrict,
  external_event_ref text not null,
  source_status_code text not null,
  status_code text not null default 'POSTED',
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default clock_timestamp(),
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  total_quantity bigint not null,
  pre_shipment_quantity bigint not null,
  post_shipment_quantity bigint not null,
  request_hash text not null,
  note text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_marketplace_cancellations_org_id
    unique (organization_id, id),
  constraint fk_marketplace_cancellations_event
    foreign key (organization_id, event_id)
    references operations.marketplace_events (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_cancellations_order
    foreign key (organization_id, order_id)
    references operations.marketplace_orders (organization_id, id)
    on delete restrict,
  constraint uq_marketplace_cancellations_no
    unique (organization_id, cancellation_no),
  constraint uq_marketplace_cancellations_event
    unique (event_id),
  constraint uq_marketplace_cancellations_external
    unique (organization_id, channel_id, external_event_ref),
  constraint uq_marketplace_cancellations_idempotency
    unique (idempotency_command_id),
  constraint ck_marketplace_cancellations_no_nonblank
    check (btrim(cancellation_no) <> ''),
  constraint ck_marketplace_cancellations_event_ref_nonblank
    check (btrim(external_event_ref) <> ''),
  constraint ck_marketplace_cancellations_source_status_nonblank
    check (btrim(source_status_code) <> ''),
  constraint ck_marketplace_cancellations_status
    check (status_code = 'POSTED'),
  constraint ck_marketplace_cancellations_actor_xor_process
    check ((actor_user_id is not null) <> (process_name is not null)),
  constraint ck_marketplace_cancellations_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),
  constraint ck_marketplace_cancellations_total_positive
    check (total_quantity > 0),
  constraint ck_marketplace_cancellations_pre_nonnegative
    check (pre_shipment_quantity >= 0),
  constraint ck_marketplace_cancellations_post_nonnegative
    check (post_shipment_quantity >= 0),
  constraint ck_marketplace_cancellations_quantity_math
    check (
      total_quantity =
      pre_shipment_quantity + post_shipment_quantity
    ),
  constraint ck_marketplace_cancellations_request_hash
    check (request_hash ~ '^[0-9a-f]{64}$'),
  constraint ck_marketplace_cancellations_note_nonblank
    check (note is null or btrim(note) <> ''),
  constraint ck_marketplace_cancellations_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create table operations.marketplace_cancellation_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  cancellation_id uuid not null,
  event_line_id uuid not null,
  line_no integer not null,
  order_item_id uuid not null,
  reservation_id uuid not null
    references inventory.stock_reservations(id) on delete restrict,
  product_id uuid not null,
  phase_code text not null,
  quantity_cancelled bigint not null,
  product_sku_snapshot text not null,
  order_item_ref_snapshot text not null,
  source_line_ref text not null,
  open_reserved_before bigint not null,
  open_reserved_after bigint not null,
  shipped_before bigint not null,
  return_expected_before bigint not null,
  post_cancelled_before bigint not null,
  post_cancelled_after bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_marketplace_cancellation_lines_org_id
    unique (organization_id, id),
  constraint fk_marketplace_cancellation_lines_cancellation
    foreign key (organization_id, cancellation_id)
    references operations.marketplace_cancellations (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_cancellation_lines_event_line
    foreign key (organization_id, event_line_id)
    references operations.marketplace_event_lines (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_cancellation_lines_order_item
    foreign key (organization_id, order_item_id)
    references operations.marketplace_order_items (organization_id, id)
    on delete restrict,
  constraint fk_marketplace_cancellation_lines_product
    foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,
  constraint uq_marketplace_cancellation_lines_line
    unique (cancellation_id, line_no),
  constraint uq_marketplace_cancellation_lines_source
    unique (cancellation_id, source_line_ref),
  constraint uq_marketplace_cancellation_lines_item_phase
    unique (cancellation_id, order_item_id, phase_code),
  constraint uq_marketplace_cancellation_lines_event_line
    unique (event_line_id),
  constraint ck_marketplace_cancellation_lines_line_positive
    check (line_no > 0),
  constraint ck_marketplace_cancellation_lines_phase
    check (phase_code in ('PRE_SHIPMENT', 'POST_SHIPMENT')),
  constraint ck_marketplace_cancellation_lines_quantity_positive
    check (quantity_cancelled > 0),
  constraint ck_marketplace_cancellation_lines_sku_nonblank
    check (btrim(product_sku_snapshot) <> ''),
  constraint ck_marketplace_cancellation_lines_item_ref_nonblank
    check (btrim(order_item_ref_snapshot) <> ''),
  constraint ck_marketplace_cancellation_lines_source_nonblank
    check (btrim(source_line_ref) <> ''),
  constraint ck_marketplace_cancellation_lines_open_before_nonnegative
    check (open_reserved_before >= 0),
  constraint ck_marketplace_cancellation_lines_open_after_nonnegative
    check (open_reserved_after >= 0),
  constraint ck_marketplace_cancellation_lines_shipped_nonnegative
    check (shipped_before >= 0),
  constraint ck_marketplace_cancellation_lines_return_nonnegative
    check (return_expected_before >= 0),
  constraint ck_marketplace_cancellation_lines_post_before_nonnegative
    check (post_cancelled_before >= 0),
  constraint ck_marketplace_cancellation_lines_post_after_nonnegative
    check (post_cancelled_after >= 0),
  constraint ck_marketplace_cancellation_lines_phase_math
    check (
      (
        phase_code = 'PRE_SHIPMENT'
        and open_reserved_after =
          open_reserved_before - quantity_cancelled
        and post_cancelled_after = post_cancelled_before
      )
      or (
        phase_code = 'POST_SHIPMENT'
        and open_reserved_after = open_reserved_before
        and post_cancelled_after =
          post_cancelled_before + quantity_cancelled
      )
    )
);

create table operations.marketplace_cancellation_applications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  cancellation_line_id uuid not null,
  application_no integer not null,
  effect_code text not null,
  quantity_applied bigint not null,
  reservation_id uuid not null
    references inventory.stock_reservations(id) on delete restrict,
  marketplace_ship_allocation_id uuid null
    references operations.marketplace_ship_allocations(id) on delete restrict,
  stock_reversal_application_id uuid null
    references inventory.stock_reversal_applications(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_marketplace_cancellation_applications_org_id
    unique (organization_id, id),
  constraint fk_marketplace_cancellation_applications_line
    foreign key (organization_id, cancellation_line_id)
    references operations.marketplace_cancellation_lines (organization_id, id)
    on delete restrict,
  constraint uq_marketplace_cancellation_applications_no
    unique (cancellation_line_id, application_no),
  constraint uq_marketplace_cancellation_applications_reversal
    unique (stock_reversal_application_id),
  constraint ck_marketplace_cancellation_applications_no_positive
    check (application_no > 0),
  constraint ck_marketplace_cancellation_applications_effect
    check (
      effect_code in (
        'PRE_SHIPMENT_RELEASE',
        'POST_SHIPMENT_REVERSAL'
      )
    ),
  constraint ck_marketplace_cancellation_applications_quantity
    check (quantity_applied > 0),
  constraint ck_marketplace_cancellation_applications_shape
    check (
      (
        effect_code = 'PRE_SHIPMENT_RELEASE'
        and marketplace_ship_allocation_id is null
        and stock_reversal_application_id is null
      )
      or (
        effect_code = 'POST_SHIPMENT_REVERSAL'
        and marketplace_ship_allocation_id is not null
        and stock_reversal_application_id is not null
      )
    )
);

create index idx_marketplace_cancellations_order
on operations.marketplace_cancellations (
  organization_id,
  order_id,
  occurred_at desc,
  id
);

create index idx_marketplace_cancellation_lines_item
on operations.marketplace_cancellation_lines (
  organization_id,
  order_item_id,
  phase_code,
  cancellation_id,
  line_no
);

create index idx_marketplace_cancellation_applications_allocation
on operations.marketplace_cancellation_applications (
  organization_id,
  marketplace_ship_allocation_id,
  cancellation_line_id,
  application_no
)
where marketplace_ship_allocation_id is not null;

create or replace function operations.validate_marketplace_cancellation_application()
returns trigger
language plpgsql
set search_path = pg_catalog, inventory, operations
as $$
declare
  v_line operations.marketplace_cancellation_lines%rowtype;
  v_allocation operations.marketplace_ship_allocations%rowtype;
  v_event_line operations.marketplace_event_lines%rowtype;
  v_event operations.marketplace_events%rowtype;
  v_reversal inventory.stock_reversal_applications%rowtype;
  v_applied_before bigint;
begin
  select cancellation_line.*
  into v_line
  from operations.marketplace_cancellation_lines cancellation_line
  where cancellation_line.id = new.cancellation_line_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_LINE_NOT_FOUND';
  end if;

  if v_line.organization_id <> new.organization_id
     or v_line.reservation_id <> new.reservation_id then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_APPLICATION_IDENTITY_MISMATCH';
  end if;

  if (
    v_line.phase_code = 'PRE_SHIPMENT'
    and new.effect_code <> 'PRE_SHIPMENT_RELEASE'
  ) or (
    v_line.phase_code = 'POST_SHIPMENT'
    and new.effect_code <> 'POST_SHIPMENT_REVERSAL'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_APPLICATION_PHASE_MISMATCH';
  end if;

  select coalesce(sum(application.quantity_applied), 0)::bigint
  into v_applied_before
  from operations.marketplace_cancellation_applications application
  where application.cancellation_line_id = new.cancellation_line_id;

  if v_applied_before + new.quantity_applied > v_line.quantity_cancelled then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_APPLICATION_OVER_APPLIED';
  end if;

  if new.effect_code = 'PRE_SHIPMENT_RELEASE' then
    return new;
  end if;

  select allocation.*
  into v_allocation
  from operations.marketplace_ship_allocations allocation
  where allocation.id = new.marketplace_ship_allocation_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_ALLOCATION_NOT_FOUND';
  end if;

  select event_line.*
  into v_event_line
  from operations.marketplace_event_lines event_line
  where event_line.id = v_allocation.event_line_id;

  select marketplace_event.*
  into v_event
  from operations.marketplace_events marketplace_event
  where marketplace_event.id = v_allocation.event_id;

  select reversal_application.*
  into v_reversal
  from inventory.stock_reversal_applications reversal_application
  where reversal_application.id = new.stock_reversal_application_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_REVERSAL_APPLICATION_NOT_FOUND';
  end if;

  if v_allocation.organization_id <> new.organization_id
     or v_event_line.organization_id <> new.organization_id
     or v_event.organization_id <> new.organization_id
     or v_reversal.organization_id <> new.organization_id
     or v_event_line.order_item_id <> v_line.order_item_id
     or v_allocation.product_id <> v_line.product_id
     or v_event.event_type_code <> 'SHIP'
     or v_event.transaction_id is null
     or v_reversal.original_transaction_id <> v_event.transaction_id
     or v_reversal.original_entry_id <> v_allocation.ledger_entry_id
     or v_reversal.quantity_applied <> new.quantity_applied then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_REVERSAL_LINK_MISMATCH';
  end if;

  return new;
end;
$$;

create trigger trg_marketplace_cancellation_applications_validate
before insert on operations.marketplace_cancellation_applications
for each row
execute function operations.validate_marketplace_cancellation_application();

create trigger trg_marketplace_cancellations_immutable
before update or delete on operations.marketplace_cancellations
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_marketplace_cancellation_lines_immutable
before update or delete on operations.marketplace_cancellation_lines
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_marketplace_cancellation_applications_immutable
before update or delete on operations.marketplace_cancellation_applications
for each row execute function inventory.reject_immutable_mutation();

alter table operations.marketplace_cancellations enable row level security;
alter table operations.marketplace_cancellation_lines enable row level security;
alter table operations.marketplace_cancellation_applications enable row level security;

create policy marketplace_cancellations_read_current_org
on operations.marketplace_cancellations
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy marketplace_cancellation_lines_read_current_org
on operations.marketplace_cancellation_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy marketplace_cancellation_applications_read_current_org
on operations.marketplace_cancellation_applications
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on operations.marketplace_cancellations,
              operations.marketplace_cancellation_lines,
              operations.marketplace_cancellation_applications
from public, anon, authenticated;

grant select on operations.marketplace_cancellations,
                operations.marketplace_cancellation_lines,
                operations.marketplace_cancellation_applications
to authenticated, service_role;

revoke all on function
  operations.validate_marketplace_cancellation_application()
from public, anon, authenticated, service_role;

create or replace function inventory.preview_marketplace_cancellation_core(
  p_organization_id uuid,
  p_channel_code text,
  p_event_ref text,
  p_order_ref text,
  p_occurred_at timestamptz,
  p_source_status text,
  p_lines jsonb,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_lock_basis boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_channel_code text;
  v_event_ref text;
  v_order_ref text;
  v_source_status text;
  v_note text;
  v_metadata jsonb;
  v_normalized_lines jsonb;
  v_request_payload jsonb;
  v_request_hash text;
  v_timezone text;
  v_effective_local_date date;
  v_channel_id uuid;
  v_order_id uuid;
  v_order_status text;
  v_order_reserved_at timestamptz;
  v_source_already_posted boolean := false;
  v_total_quantity bigint := 0;
  v_pre_quantity bigint := 0;
  v_post_quantity bigint := 0;
  v_lines jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_basis jsonb;
  v_basis_hash text;
  v_line record;
  v_order_item_id uuid;
  v_reservation_id uuid;
  v_product_sku text;
  v_reserved_qty bigint;
  v_shipped_qty bigint;
  v_released_qty bigint;
  v_open_reserved_qty bigint;
  v_pre_cancelled_qty bigint;
  v_post_cancelled_qty bigint;
  v_return_expected_qty bigint;
  v_remaining_post_qty bigint;
  v_line_blockers jsonb;
  v_line_applications jsonb;
  v_remaining bigint;
  v_application_no integer;
  v_allocation record;
  v_allocation_remaining bigint;
  v_take bigint;
  v_item_found boolean;
  v_product_position_found boolean;
  v_product_sellable bigint;
  v_product_reserved bigint;
  v_product_position_version bigint;
  v_original_transaction record;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  v_channel_code := upper(btrim(coalesce(p_channel_code, '')));
  v_event_ref := btrim(coalesce(p_event_ref, ''));
  v_order_ref := btrim(coalesce(p_order_ref, ''));
  v_source_status := btrim(coalesce(p_source_status, ''));
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_channel_code = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_CHANNEL_REQUIRED';
  end if;

  if v_event_ref = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_EVENT_REF_REQUIRED';
  end if;

  if length(v_event_ref) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_EVENT_REF_TOO_LONG';
  end if;

  if v_order_ref = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_ORDER_REF_REQUIRED';
  end if;

  if length(v_order_ref) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_ORDER_REF_TOO_LONG';
  end if;

  if v_source_status = '' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_SOURCE_STATUS_REQUIRED';
  end if;

  if length(v_source_status) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_SOURCE_STATUS_TOO_LONG';
  end if;

  if p_occurred_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_OCCURRED_AT_REQUIRED';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_LINES_MUST_BE_ARRAY';
  end if;

  if jsonb_array_length(p_lines) = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_LINES_REQUIRED';
  end if;

  if jsonb_array_length(p_lines) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_LINES_LIMIT_EXCEEDED';
  end if;

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_METADATA_MUST_BE_OBJECT';
  end if;

  if v_note is not null and length(v_note) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_NOTE_TOO_LONG';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'productId') is distinct from 'string'
       or (item.value ->> 'productId')
            !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'orderItemRef') is distinct from 'string'
       or btrim(item.value ->> 'orderItemRef') = ''
       or length(btrim(item.value ->> 'orderItemRef')) > 100
       or jsonb_typeof(item.value -> 'phaseCode') is distinct from 'string'
       or upper(btrim(item.value ->> 'phaseCode'))
            not in ('PRE_SHIPMENT', 'POST_SHIPMENT')
       or jsonb_typeof(item.value -> 'quantity') is distinct from 'number'
       or (item.value ->> 'quantity') !~ '^[1-9][0-9]{0,8}$'
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 100
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_DUPLICATE_SOURCE_LINE';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by
      btrim(item.value ->> 'orderItemRef'),
      upper(btrim(item.value ->> 'phaseCode'))
    having count(*) > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_DUPLICATE_ITEM_PHASE';
  end if;

  select
    jsonb_agg(
      jsonb_build_object(
        'lineNo', item.ordinality::integer,
        'productId', lower(item.value ->> 'productId'),
        'orderItemRef', btrim(item.value ->> 'orderItemRef'),
        'phaseCode', upper(btrim(item.value ->> 'phaseCode')),
        'quantity', (item.value ->> 'quantity')::bigint,
        'sourceLineRef', btrim(item.value ->> 'sourceLineRef')
      )
      order by item.ordinality
    ),
    sum((item.value ->> 'quantity')::bigint),
    sum(
      case
        when upper(btrim(item.value ->> 'phaseCode')) = 'PRE_SHIPMENT'
          then (item.value ->> 'quantity')::bigint
        else 0
      end
    ),
    sum(
      case
        when upper(btrim(item.value ->> 'phaseCode')) = 'POST_SHIPMENT'
          then (item.value ->> 'quantity')::bigint
        else 0
      end
    )
  into
    v_normalized_lines,
    v_total_quantity,
    v_pre_quantity,
    v_post_quantity
  from jsonb_array_elements(p_lines)
       with ordinality item(value, ordinality);

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

  select organization.timezone
  into v_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  v_effective_local_date :=
    (p_occurred_at at time zone v_timezone)::date;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = v_channel_code
    and channel.is_marketplace
    and channel.is_active;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_CHANNEL_NOT_ALLOWED';
  end if;

  if p_lock_basis then
    select
      marketplace_order.id,
      marketplace_order.status_code,
      marketplace_order.reserved_at
    into v_order_id, v_order_status, v_order_reserved_at
    from operations.marketplace_orders marketplace_order
    where marketplace_order.organization_id = p_organization_id
      and marketplace_order.channel_id = v_channel_id
      and marketplace_order.external_order_ref = v_order_ref
    for update;
  else
    select
      marketplace_order.id,
      marketplace_order.status_code,
      marketplace_order.reserved_at
    into v_order_id, v_order_status, v_order_reserved_at
    from operations.marketplace_orders marketplace_order
    where marketplace_order.organization_id = p_organization_id
      and marketplace_order.channel_id = v_channel_id
      and marketplace_order.external_order_ref = v_order_ref;
  end if;

  if not found then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'MARKETPLACE_CANCELLATION_ORDER_NOT_FOUND',
        'scope', 'REQUEST',
        'message', 'Order marketplace tidak ditemukan.'
      )
    );
    v_order_id := null;
    v_order_status := null;
    v_order_reserved_at := null;
  elsif p_occurred_at < v_order_reserved_at then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'MARKETPLACE_CANCELLATION_BEFORE_ORDER',
        'scope', 'REQUEST',
        'message', 'Waktu pembatalan tidak boleh mendahului waktu order.'
      )
    );
  end if;

  select exists (
    select 1
    from operations.marketplace_events marketplace_event
    where marketplace_event.organization_id = p_organization_id
      and marketplace_event.channel_id = v_channel_id
      and marketplace_event.external_event_ref = v_event_ref
  )
  into v_source_already_posted;

  if v_source_already_posted then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'MARKETPLACE_CANCELLATION_EVENT_ALREADY_APPLIED',
        'scope', 'REQUEST',
        'message', 'Referensi event pembatalan sudah pernah diterapkan.'
      )
    );
  end if;

  if v_post_quantity > 0 and v_note is null then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'MARKETPLACE_CANCELLATION_POST_NOTE_REQUIRED',
        'scope', 'REQUEST',
        'message', 'Alasan pembatalan setelah shipment wajib diisi.'
      )
    );
  end if;

  v_request_payload := jsonb_build_object(
    'organizationId', p_organization_id,
    'channelCode', v_channel_code,
    'eventRef', v_event_ref,
    'orderRef', v_order_ref,
    'occurredAt', p_occurred_at,
    'sourceStatus', v_source_status,
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

  if p_lock_basis and v_order_id is not null then
    for v_original_transaction in
      select distinct
        marketplace_event.transaction_id
      from operations.marketplace_events marketplace_event
      where marketplace_event.organization_id = p_organization_id
        and marketplace_event.order_id = v_order_id
        and marketplace_event.event_type_code = 'SHIP'
        and marketplace_event.transaction_id is not null
      order by marketplace_event.transaction_id
    loop
      perform pg_advisory_xact_lock(
        hashtextextended(
          p_organization_id::text ||
          ':STOCK_TRANSACTION_REVERSAL:' ||
          v_original_transaction.transaction_id::text,
          0::bigint
        )
      );
    end loop;

    perform allocation.id
    from operations.marketplace_ship_allocations allocation
    join operations.marketplace_events marketplace_event
      on marketplace_event.organization_id = allocation.organization_id
     and marketplace_event.id = allocation.event_id
    where allocation.organization_id = p_organization_id
      and marketplace_event.order_id = v_order_id
    order by allocation.product_id, allocation.batch_id, allocation.id
    for update of allocation;

    perform entry.id
    from inventory.stock_ledger_entries entry
    join operations.marketplace_ship_allocations allocation
      on allocation.ledger_entry_id = entry.id
    join operations.marketplace_events marketplace_event
      on marketplace_event.organization_id = allocation.organization_id
     and marketplace_event.id = allocation.event_id
    where entry.organization_id = p_organization_id
      and marketplace_event.order_id = v_order_id
    order by entry.ledger_seq
    for update of entry;

    perform balance.batch_id
    from inventory.stock_batch_balances balance
    join operations.marketplace_ship_allocations allocation
      on allocation.organization_id = balance.organization_id
     and allocation.product_id = balance.product_id
     and allocation.batch_id = balance.batch_id
    join operations.marketplace_events marketplace_event
      on marketplace_event.organization_id = allocation.organization_id
     and marketplace_event.id = allocation.event_id
    where balance.organization_id = p_organization_id
      and marketplace_event.order_id = v_order_id
    order by balance.product_id, balance.batch_id
    for update of balance;
  end if;

  for v_line in
    select
      (line.value ->> 'lineNo')::integer as line_no,
      (line.value ->> 'productId')::uuid as product_id,
      line.value ->> 'orderItemRef' as order_item_ref,
      line.value ->> 'phaseCode' as phase_code,
      (line.value ->> 'quantity')::bigint as quantity,
      line.value ->> 'sourceLineRef' as source_line_ref
    from jsonb_array_elements(v_normalized_lines) line(value)
    order by
      line.value ->> 'orderItemRef',
      line.value ->> 'phaseCode',
      (line.value ->> 'lineNo')::integer
  loop
    v_line_blockers := '[]'::jsonb;
    v_line_applications := '[]'::jsonb;
    v_order_item_id := null;
    v_reservation_id := null;
    v_product_sku := null;
    v_reserved_qty := 0;
    v_shipped_qty := 0;
    v_released_qty := 0;
    v_open_reserved_qty := 0;
    v_pre_cancelled_qty := 0;
    v_post_cancelled_qty := 0;
    v_return_expected_qty := 0;
    v_remaining_post_qty := 0;
    v_item_found := false;
    v_product_position_found := false;
    v_product_sellable := 0;
    v_product_reserved := 0;
    v_product_position_version := 0;

    if v_order_id is not null then
      if p_lock_basis then
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
          v_reserved_qty,
          v_shipped_qty,
          v_released_qty
        from operations.marketplace_order_items item
        join inventory.stock_reservations reservation
          on reservation.id = item.reservation_id
        where item.organization_id = p_organization_id
          and item.order_id = v_order_id
          and item.external_item_ref = v_line.order_item_ref
          and item.product_id = v_line.product_id
        for update of reservation;
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
          v_reserved_qty,
          v_shipped_qty,
          v_released_qty
        from operations.marketplace_order_items item
        join inventory.stock_reservations reservation
          on reservation.id = item.reservation_id
        where item.organization_id = p_organization_id
          and item.order_id = v_order_id
          and item.external_item_ref = v_line.order_item_ref
          and item.product_id = v_line.product_id;
      end if;

      v_item_found := found;
    end if;

    if not v_item_found then
      v_line_blockers := v_line_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'MARKETPLACE_CANCELLATION_ORDER_ITEM_NOT_FOUND',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Item order marketplace tidak ditemukan.'
        )
      );
    else
      if p_lock_basis then
        perform pg_advisory_xact_lock(
          hashtextextended(
            p_organization_id::text ||
            ':RETURNABLE_ORDER_ITEM:' ||
            v_order_item_id::text,
            0::bigint
          )
        );
      end if;

      v_open_reserved_qty :=
        v_reserved_qty - v_shipped_qty - v_released_qty;

      select
        coalesce(
          sum(application.quantity_applied) filter (
            where application.effect_code = 'PRE_SHIPMENT_RELEASE'
          ),
          0
        )::bigint,
        coalesce(
          sum(application.quantity_applied) filter (
            where application.effect_code = 'POST_SHIPMENT_REVERSAL'
          ),
          0
        )::bigint
      into
        v_pre_cancelled_qty,
        v_post_cancelled_qty
      from operations.marketplace_cancellation_applications application
      join operations.marketplace_cancellation_lines cancellation_line
        on cancellation_line.organization_id = application.organization_id
       and cancellation_line.id = application.cancellation_line_id
      where cancellation_line.organization_id = p_organization_id
        and cancellation_line.order_item_id = v_order_item_id;

      select coalesce(sum(return_item.expected_qty), 0)::bigint
      into v_return_expected_qty
      from operations.return_items return_item
      where return_item.organization_id = p_organization_id
        and return_item.marketplace_order_item_id = v_order_item_id;

      v_remaining_post_qty :=
        greatest(
          v_shipped_qty -
          v_post_cancelled_qty -
          v_return_expected_qty,
          0
        );

      if p_lock_basis then
        select
          position.sellable_qty,
          position.reserved_qty,
          position.version
        into
          v_product_sellable,
          v_product_reserved,
          v_product_position_version
        from inventory.stock_product_positions position
        where position.organization_id = p_organization_id
          and position.product_id = v_line.product_id
        for update;
      else
        select
          position.sellable_qty,
          position.reserved_qty,
          position.version
        into
          v_product_sellable,
          v_product_reserved,
          v_product_position_version
        from inventory.stock_product_positions position
        where position.organization_id = p_organization_id
          and position.product_id = v_line.product_id;
      end if;

      v_product_position_found := found;

      if not v_product_position_found then
        v_line_blockers := v_line_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'MARKETPLACE_CANCELLATION_PRODUCT_POSITION_NOT_FOUND',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'message', 'Posisi stok produk tidak ditemukan.'
          )
        );
      else
        if v_product_reserved is distinct from (
          select coalesce(
            sum(
              reservation.reserved_qty -
              reservation.consumed_qty -
              reservation.released_qty
            ),
            0
          )::bigint
          from inventory.stock_reservations reservation
          where reservation.organization_id = p_organization_id
            and reservation.product_id = v_line.product_id
        ) then
          v_line_blockers := v_line_blockers || jsonb_build_array(
            jsonb_build_object(
              'code', 'MARKETPLACE_CANCELLATION_RESERVATION_PROJECTION_DRIFT',
              'scope', 'LINE',
              'lineNo', v_line.line_no,
              'message', 'Projection reserved tidak sama dengan reservasi yang masih terbuka.'
            )
          );
        end if;

        if exists (
          with ledger as (
            select
              coalesce(
                sum(entry.quantity_delta) filter (
                  where entry.bucket_code = 'SELLABLE'
                ),
                0
              )::bigint as sellable_qty,
              coalesce(
                sum(entry.quantity_delta) filter (
                  where entry.bucket_code = 'QUARANTINE'
                ),
                0
              )::bigint as quarantine_qty,
              coalesce(
                sum(entry.quantity_delta) filter (
                  where entry.bucket_code = 'DAMAGED'
                ),
                0
              )::bigint as damaged_qty
            from inventory.stock_ledger_entries entry
            where entry.organization_id = p_organization_id
              and entry.product_id = v_line.product_id
          )
          select 1
          from ledger
          where ledger.sellable_qty <> v_product_sellable
             or ledger.quarantine_qty <> (
               select position.quarantine_qty
               from inventory.stock_product_positions position
               where position.organization_id = p_organization_id
                 and position.product_id = v_line.product_id
             )
             or ledger.damaged_qty <> (
               select position.damaged_qty
               from inventory.stock_product_positions position
               where position.organization_id = p_organization_id
                 and position.product_id = v_line.product_id
             )
        ) then
          v_line_blockers := v_line_blockers || jsonb_build_array(
            jsonb_build_object(
              'code', 'MARKETPLACE_CANCELLATION_PRODUCT_PROJECTION_DRIFT',
              'scope', 'LINE',
              'lineNo', v_line.line_no,
              'message', 'Projection produk tidak sama dengan ledger.'
            )
          );
        end if;
      end if;

      if v_line.phase_code = 'PRE_SHIPMENT' then
        if v_line.quantity > v_open_reserved_qty then
          v_line_blockers := v_line_blockers || jsonb_build_array(
            jsonb_build_object(
              'code', 'MARKETPLACE_CANCELLATION_EXCEEDS_OPEN_RESERVATION',
              'scope', 'LINE',
              'lineNo', v_line.line_no,
              'message', 'Kuantitas pembatalan melebihi reservasi yang masih terbuka.'
            )
          );
        end if;

        if v_product_position_found
           and v_product_reserved < v_line.quantity then
          v_line_blockers := v_line_blockers || jsonb_build_array(
            jsonb_build_object(
              'code', 'MARKETPLACE_CANCELLATION_RESERVATION_PROJECTION_MISMATCH',
              'scope', 'LINE',
              'lineNo', v_line.line_no,
              'message', 'Projection reserved tidak cukup untuk pelepasan reservasi.'
            )
          );
        end if;

        v_line_applications := jsonb_build_array(
          jsonb_build_object(
            'applicationNo', 1,
            'effectCode', 'PRE_SHIPMENT_RELEASE',
            'quantity', v_line.quantity,
            'reservationId', v_reservation_id
          )
        );
      else
        if v_return_expected_qty > 0 then
          v_line_blockers := v_line_blockers || jsonb_build_array(
            jsonb_build_object(
              'code', 'MARKETPLACE_CANCELLATION_RETURN_CONFLICT',
              'scope', 'LINE',
              'lineNo', v_line.line_no,
              'message', 'Item sudah memiliki proses retur dan tidak boleh dibalik melalui pembatalan shipment.'
            )
          );
        end if;

        if exists (
          select 1
          from operations.marketplace_ship_allocations allocation
          join operations.marketplace_event_lines event_line
            on event_line.organization_id = allocation.organization_id
           and event_line.id = allocation.event_line_id
          join operations.marketplace_events marketplace_event
            on marketplace_event.organization_id = allocation.organization_id
           and marketplace_event.id = allocation.event_id
          where allocation.organization_id = p_organization_id
            and event_line.order_item_id = v_order_item_id
            and marketplace_event.event_type_code = 'SHIP'
            and marketplace_event.occurred_at > p_occurred_at
        ) then
          v_line_blockers := v_line_blockers || jsonb_build_array(
            jsonb_build_object(
              'code', 'MARKETPLACE_CANCELLATION_BEFORE_SHIPMENT',
              'scope', 'LINE',
              'lineNo', v_line.line_no,
              'message', 'Waktu pembatalan tidak boleh mendahului shipment item.'
            )
          );
        end if;

        if v_line.quantity > v_remaining_post_qty then
          v_line_blockers := v_line_blockers || jsonb_build_array(
            jsonb_build_object(
              'code', 'MARKETPLACE_CANCELLATION_EXCEEDS_SHIPPED_REMAINING',
              'scope', 'LINE',
              'lineNo', v_line.line_no,
              'message', 'Kuantitas pembatalan melebihi shipment yang belum dibalik.'
            )
          );
        end if;

        v_remaining := v_line.quantity;
        v_application_no := 0;

        for v_allocation in
          select
            allocation.id as allocation_id,
            allocation.allocation_no,
            allocation.quantity_allocated,
            allocation.product_id,
            allocation.batch_id,
            allocation.product_sku_snapshot,
            allocation.batch_code_snapshot,
            allocation.expiry_date_snapshot,
            allocation.ledger_entry_id,
            marketplace_event.id as ship_event_id,
            marketplace_event.external_event_ref as ship_event_ref,
            marketplace_event.transaction_id as original_transaction_id,
            stock_transaction.transaction_no as original_transaction_no,
            ledger_entry.ledger_seq as original_ledger_seq,
            ledger_entry.bucket_code,
            coalesce(
              (
                select sum(reversal_application.quantity_applied)
                from inventory.stock_reversal_applications reversal_application
                where reversal_application.original_entry_id =
                  allocation.ledger_entry_id
              ),
              0
            )::bigint as already_reversed_qty,
            balance.sellable_qty as batch_sellable_qty,
            balance.version as batch_balance_version
          from operations.marketplace_ship_allocations allocation
          join operations.marketplace_event_lines event_line
            on event_line.organization_id = allocation.organization_id
           and event_line.id = allocation.event_line_id
          join operations.marketplace_events marketplace_event
            on marketplace_event.organization_id = allocation.organization_id
           and marketplace_event.id = allocation.event_id
          join inventory.stock_transactions stock_transaction
            on stock_transaction.id = marketplace_event.transaction_id
          join inventory.stock_ledger_entries ledger_entry
            on ledger_entry.id = allocation.ledger_entry_id
          join inventory.stock_batch_balances balance
            on balance.organization_id = allocation.organization_id
           and balance.product_id = allocation.product_id
           and balance.batch_id = allocation.batch_id
          where allocation.organization_id = p_organization_id
            and event_line.order_item_id = v_order_item_id
            and marketplace_event.event_type_code = 'SHIP'
            and marketplace_event.transaction_id is not null
          order by
            ledger_entry.ledger_seq desc,
            allocation.allocation_no desc,
            allocation.id
        loop
          exit when v_remaining = 0;

          if exists (
            with ledger as (
              select
                coalesce(
                  sum(entry.quantity_delta) filter (
                    where entry.bucket_code = 'SELLABLE'
                  ),
                  0
                )::bigint as sellable_qty,
                coalesce(
                  sum(entry.quantity_delta) filter (
                    where entry.bucket_code = 'QUARANTINE'
                  ),
                  0
                )::bigint as quarantine_qty,
                coalesce(
                  sum(entry.quantity_delta) filter (
                    where entry.bucket_code = 'DAMAGED'
                  ),
                  0
                )::bigint as damaged_qty
              from inventory.stock_ledger_entries entry
              where entry.organization_id = p_organization_id
                and entry.product_id = v_allocation.product_id
                and entry.batch_id = v_allocation.batch_id
            )
            select 1
            from ledger
            join inventory.stock_batch_balances balance
              on balance.organization_id = p_organization_id
             and balance.product_id = v_allocation.product_id
             and balance.batch_id = v_allocation.batch_id
            where ledger.sellable_qty <> balance.sellable_qty
               or ledger.quarantine_qty <> balance.quarantine_qty
               or ledger.damaged_qty <> balance.damaged_qty
          ) then
            v_line_blockers := v_line_blockers || jsonb_build_array(
              jsonb_build_object(
                'code', 'MARKETPLACE_CANCELLATION_BATCH_PROJECTION_DRIFT',
                'scope', 'LINE',
                'lineNo', v_line.line_no,
                'message', 'Projection batch shipment tidak sama dengan ledger.'
              )
            );
          end if;

          v_allocation_remaining :=
            greatest(
              v_allocation.quantity_allocated -
              v_allocation.already_reversed_qty,
              0
            );

          if v_allocation_remaining = 0 then
            continue;
          end if;

          v_take := least(v_remaining, v_allocation_remaining);
          v_application_no := v_application_no + 1;

          v_line_applications := v_line_applications || jsonb_build_array(
            jsonb_build_object(
              'applicationNo', v_application_no,
              'effectCode', 'POST_SHIPMENT_REVERSAL',
              'quantity', v_take,
              'reservationId', v_reservation_id,
              'shipAllocationId', v_allocation.allocation_id,
              'shipAllocationNo', v_allocation.allocation_no,
              'shipEventId', v_allocation.ship_event_id,
              'shipEventRef', v_allocation.ship_event_ref,
              'originalTransactionId', v_allocation.original_transaction_id,
              'originalTransactionNo', v_allocation.original_transaction_no,
              'originalLedgerEntryId', v_allocation.ledger_entry_id,
              'originalLedgerSeq', v_allocation.original_ledger_seq,
              'productId', v_allocation.product_id,
              'productSku', v_allocation.product_sku_snapshot,
              'batchId', v_allocation.batch_id,
              'batchCode', v_allocation.batch_code_snapshot,
              'expiryDate', v_allocation.expiry_date_snapshot,
              'bucketCode', v_allocation.bucket_code,
              'allocationQuantity', v_allocation.quantity_allocated,
              'alreadyReversedQuantity', v_allocation.already_reversed_qty,
              'remainingBeforeQuantity', v_allocation_remaining,
              'batchSellableBefore', v_allocation.batch_sellable_qty,
              'batchSellableAfter',
                v_allocation.batch_sellable_qty + v_take,
              'batchBalanceVersion', v_allocation.batch_balance_version
            )
          );

          v_remaining := v_remaining - v_take;
        end loop;

        if v_remaining > 0 then
          v_line_blockers := v_line_blockers || jsonb_build_array(
            jsonb_build_object(
              'code', 'MARKETPLACE_CANCELLATION_ALLOCATION_BASIS_INSUFFICIENT',
              'scope', 'LINE',
              'lineNo', v_line.line_no,
              'message', 'Alokasi shipment yang dapat dibalik tidak mencukupi.'
            )
          );
        end if;
      end if;
    end if;

    v_blockers := v_blockers || v_line_blockers;

    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'lineNo', v_line.line_no,
        'productId', v_line.product_id,
        'productSku', v_product_sku,
        'orderItemId', v_order_item_id,
        'orderItemRef', v_line.order_item_ref,
        'reservationId', v_reservation_id,
        'phaseCode', v_line.phase_code,
        'quantity', v_line.quantity,
        'sourceLineRef', v_line.source_line_ref,
        'reservedQuantity', v_reserved_qty,
        'shippedQuantity', v_shipped_qty,
        'releasedQuantity', v_released_qty,
        'openReservedBefore', v_open_reserved_qty,
        'openReservedAfter',
          case
            when v_line.phase_code = 'PRE_SHIPMENT'
              then v_open_reserved_qty - v_line.quantity
            else v_open_reserved_qty
          end,
        'preShipmentCancelledBefore', v_pre_cancelled_qty,
        'preShipmentCancelledAfter',
          v_pre_cancelled_qty +
          case
            when v_line.phase_code = 'PRE_SHIPMENT'
              then v_line.quantity
            else 0
          end,
        'postShipmentCancelledBefore', v_post_cancelled_qty,
        'postShipmentCancelledAfter',
          v_post_cancelled_qty +
          case
            when v_line.phase_code = 'POST_SHIPMENT'
              then v_line.quantity
            else 0
          end,
        'returnExpectedQuantity', v_return_expected_qty,
        'remainingPostCancellableBefore', v_remaining_post_qty,
        'remainingPostCancellableAfter',
          case
            when v_line.phase_code = 'POST_SHIPMENT'
              then v_remaining_post_qty - v_line.quantity
            else v_remaining_post_qty
          end,
        'productSellableBefore', v_product_sellable,
        'productSellableAfter',
          v_product_sellable +
          case
            when v_line.phase_code = 'POST_SHIPMENT'
              then v_line.quantity
            else 0
          end,
        'productReservedBefore', v_product_reserved,
        'productReservedAfter',
          v_product_reserved -
          case
            when v_line.phase_code = 'PRE_SHIPMENT'
              then v_line.quantity
            else 0
          end,
        'productPositionVersion', v_product_position_version,
        'applications', v_line_applications,
        'eligible', jsonb_array_length(v_line_blockers) = 0,
        'blockers', v_line_blockers
      )
    );
  end loop;

  v_basis := jsonb_build_object(
    'organizationId', p_organization_id,
    'organizationTimezone', v_timezone,
    'effectiveLocalDate', v_effective_local_date,
    'channelId', v_channel_id,
    'channelCode', v_channel_code,
    'orderId', v_order_id,
    'orderRef', v_order_ref,
    'orderStatus', v_order_status,
    'orderReservedAt', v_order_reserved_at,
    'sourceAlreadyPosted', v_source_already_posted,
    'requestHash', v_request_hash,
    'lines', v_lines,
    'schemaVersion', 1
  );

  v_basis_hash := encode(
    extensions.digest(
      convert_to(v_basis::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  return jsonb_build_object(
    'eligible', jsonb_array_length(v_blockers) = 0,
    'blockers', v_blockers,
    'requestHash', v_request_hash,
    'basisHash', v_basis_hash,
    'organizationId', p_organization_id,
    'organizationTimezone', v_timezone,
    'effectiveLocalDate', v_effective_local_date,
    'channelId', v_channel_id,
    'channelCode', v_channel_code,
    'eventRef', v_event_ref,
    'orderId', v_order_id,
    'orderRef', v_order_ref,
    'orderStatus', v_order_status,
    'orderReservedAt', v_order_reserved_at,
    'sourceStatus', v_source_status,
    'occurredAt', p_occurred_at,
    'sourceAlreadyPosted', v_source_already_posted,
    'totalRequestedQuantity', v_total_quantity,
    'preShipmentQuantity', v_pre_quantity,
    'postShipmentQuantity', v_post_quantity,
    'note', v_note,
    'metadata', v_metadata,
    'lines', v_lines
  );
end;
$$;

revoke all on function inventory.preview_marketplace_cancellation_core(
  uuid,
  text,
  text,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  jsonb,
  boolean
) from public, anon, authenticated, service_role;

create or replace function api.preview_marketplace_cancellation(
  p_organization_id uuid,
  p_channel_code text,
  p_event_ref text,
  p_order_ref text,
  p_occurred_at timestamptz,
  p_source_status text,
  p_lines jsonb,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
begin
  return inventory.preview_marketplace_cancellation_core(
    p_organization_id,
    p_channel_code,
    p_event_ref,
    p_order_ref,
    p_occurred_at,
    p_source_status,
    p_lines,
    p_note,
    p_metadata,
    false
  );
end;
$$;

revoke all on function api.preview_marketplace_cancellation(
  uuid,
  text,
  text,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  jsonb
) from public, anon;

grant execute on function api.preview_marketplace_cancellation(
  uuid,
  text,
  text,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  jsonb
) to authenticated, service_role;

create or replace function api.post_marketplace_cancellation(
  p_organization_id uuid,
  p_idempotency_key text,
  p_channel_code text,
  p_event_ref text,
  p_order_ref text,
  p_occurred_at timestamptz,
  p_source_status text,
  p_lines jsonb,
  p_preview_basis_hash text,
  p_confirmation boolean,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
declare
  v_scope constant text := 'POST_MARKETPLACE_CANCELLATION';
  v_child_scope constant text :=
    'POST_MARKETPLACE_CANCELLATION_REVERSAL';
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_idempotency_key text;
  v_channel_code text;
  v_event_ref text;
  v_order_ref text;
  v_source_status text;
  v_note text;
  v_metadata jsonb;
  v_expected_basis_hash text;
  v_command_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_preview jsonb;
  v_actual_basis_hash text;
  v_request_hash text;
  v_timezone text;
  v_effective_local_date date;
  v_channel_id uuid;
  v_order_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_event_id uuid := gen_random_uuid();
  v_cancellation_id uuid := gen_random_uuid();
  v_cancellation_no text;
  v_recorded_at timestamptz := clock_timestamp();
  v_process_name text;
  v_created_by_role_code text;
  v_total_quantity bigint;
  v_pre_quantity bigint;
  v_post_quantity bigint;
  v_event_line_id uuid;
  v_cancellation_line_id uuid;
  v_line record;
  v_application record;
  v_line_id_map jsonb := '{}'::jsonb;
  v_reversal_transactions jsonb := '[]'::jsonb;
  v_result_lines jsonb := '[]'::jsonb;
  v_response jsonb;
  v_original_transaction inventory.stock_transactions%rowtype;
  v_original_transaction_id uuid;
  v_child_command_id uuid;
  v_child_key text;
  v_child_request_hash text;
  v_reversal_transaction_id uuid;
  v_reversal_transaction_no text;
  v_reversal_line_no integer;
  v_reversal_entry_id uuid;
  v_reversal_application_id uuid;
  v_ledger_seq bigint;
  v_line_application_id uuid;
  v_application_count integer;
  v_reversal_quantity bigint;
  v_single_reversal_transaction_id uuid := null;
  v_reversal_transaction_count integer := 0;
begin
  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  v_channel_code := upper(btrim(coalesce(p_channel_code, '')));
  v_event_ref := btrim(coalesce(p_event_ref, ''));
  v_order_ref := btrim(coalesce(p_order_ref, ''));
  v_source_status := btrim(coalesce(p_source_status, ''));
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  v_expected_basis_hash :=
    lower(btrim(coalesce(p_preview_basis_hash, '')));

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  if v_expected_basis_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_PREVIEW_HASH_INVALID';
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

  v_command_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'idempotencyKey', v_idempotency_key,
          'channelCode', v_channel_code,
          'eventRef', v_event_ref,
          'orderRef', v_order_ref,
          'occurredAt', p_occurred_at,
          'sourceStatus', v_source_status,
          'lines', p_lines,
          'previewBasisHash', v_expected_basis_hash,
          'confirmation', coalesce(p_confirmation, false),
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
      p_organization_id::text ||
      ':' ||
      v_scope ||
      ':' ||
      v_idempotency_key,
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
      p_organization_id::text ||
      ':MARKETPLACE_EVENT:' ||
      v_channel_code ||
      ':' ||
      v_event_ref,
      0::bigint
    )
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text ||
      ':MARKETPLACE_ORDER:' ||
      v_channel_code ||
      ':' ||
      v_order_ref,
      0::bigint
    )
  );

  v_preview := inventory.preview_marketplace_cancellation_core(
    p_organization_id,
    v_channel_code,
    v_event_ref,
    v_order_ref,
    p_occurred_at,
    v_source_status,
    p_lines,
    v_note,
    v_metadata,
    true
  );

  v_actual_basis_hash := lower(v_preview ->> 'basisHash');

  if v_actual_basis_hash is distinct from v_expected_basis_hash then
    raise exception using
      errcode = 'P0001',
      message = 'STALE_MARKETPLACE_CANCELLATION_PREVIEW';
  end if;

  if not coalesce((v_preview ->> 'eligible')::boolean, false) then
    raise exception using
      errcode = 'P0001',
      message = coalesce(
        v_preview #>> '{blockers,0,code}',
        'MARKETPLACE_CANCELLATION_PREVIEW_BLOCKED'
      );
  end if;

  v_request_hash := v_preview ->> 'requestHash';
  v_timezone := v_preview ->> 'organizationTimezone';
  v_effective_local_date :=
    (v_preview ->> 'effectiveLocalDate')::date;
  v_channel_id := (v_preview ->> 'channelId')::uuid;
  v_order_id := (v_preview ->> 'orderId')::uuid;
  v_total_quantity :=
    (v_preview ->> 'totalRequestedQuantity')::bigint;
  v_pre_quantity :=
    (v_preview ->> 'preShipmentQuantity')::bigint;
  v_post_quantity :=
    (v_preview ->> 'postShipmentQuantity')::bigint;

  if v_post_quantity > 0
     and not coalesce(p_confirmation, false) then
    raise exception using
      errcode = 'P0001',
      message = 'MARKETPLACE_CANCELLATION_CONFIRMATION_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    v_process_name := null;
    v_created_by_role_code := 'ADMIN';
  else
    v_process_name := 'api.post_marketplace_cancellation';
    v_created_by_role_code := 'SYSTEM_PROCESS';
  end if;

  v_cancellation_no :=
    'MCC-' ||
    to_char(v_effective_local_date, 'YYYYMMDD') ||
    '-' ||
    upper(
      substr(
        replace(v_cancellation_id::text, '-', ''),
        1,
        8
      )
    );

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
    v_command_request_hash,
    'STARTED',
    v_recorded_at,
    null,
    null,
    '{}'::jsonb,
    null,
    null
  );

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
  )
  values (
    v_event_id,
    p_organization_id,
    v_order_id,
    v_channel_id,
    v_event_ref,
    'CANCEL',
    'APPLIED',
    p_occurred_at,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    null,
    v_command_id,
    v_note,
    v_metadata || jsonb_build_object(
      'sourceStatus', v_source_status,
      'preShipmentQuantity', v_pre_quantity,
      'postShipmentQuantity', v_post_quantity,
      'stockEffectCode',
        case
          when v_post_quantity = 0 then 'NONE'
          when v_pre_quantity = 0 then 'REVERSAL'
          else 'MIXED'
        end,
      'previewBasisHash', v_expected_basis_hash,
      'requestHash', v_request_hash
    ),
    v_recorded_at
  );

  insert into operations.marketplace_cancellations (
    id,
    organization_id,
    cancellation_no,
    event_id,
    order_id,
    channel_id,
    external_event_ref,
    source_status_code,
    status_code,
    occurred_at,
    recorded_at,
    actor_user_id,
    process_name,
    idempotency_command_id,
    total_quantity,
    pre_shipment_quantity,
    post_shipment_quantity,
    request_hash,
    note,
    metadata,
    created_at
  )
  values (
    v_cancellation_id,
    p_organization_id,
    v_cancellation_no,
    v_event_id,
    v_order_id,
    v_channel_id,
    v_event_ref,
    v_source_status,
    'POSTED',
    p_occurred_at,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    v_command_id,
    v_total_quantity,
    v_pre_quantity,
    v_post_quantity,
    v_request_hash,
    v_note,
    v_metadata || jsonb_build_object(
      'previewBasisHash', v_expected_basis_hash
    ),
    v_recorded_at
  );

  for v_line in
    select
      line.value,
      (line.value ->> 'lineNo')::integer as line_no
    from jsonb_array_elements(v_preview -> 'lines') line(value)
    order by (line.value ->> 'lineNo')::integer
  loop
    insert into operations.marketplace_event_lines (
      organization_id,
      event_id,
      line_no,
      order_item_id,
      product_id,
      quantity,
      source_line_ref,
      created_at
    )
    values (
      p_organization_id,
      v_event_id,
      v_line.line_no,
      (v_line.value ->> 'orderItemId')::uuid,
      (v_line.value ->> 'productId')::uuid,
      (v_line.value ->> 'quantity')::bigint,
      v_line.value ->> 'sourceLineRef',
      v_recorded_at
    )
    returning id into v_event_line_id;

    insert into operations.marketplace_cancellation_lines (
      organization_id,
      cancellation_id,
      event_line_id,
      line_no,
      order_item_id,
      reservation_id,
      product_id,
      phase_code,
      quantity_cancelled,
      product_sku_snapshot,
      order_item_ref_snapshot,
      source_line_ref,
      open_reserved_before,
      open_reserved_after,
      shipped_before,
      return_expected_before,
      post_cancelled_before,
      post_cancelled_after,
      created_at
    )
    values (
      p_organization_id,
      v_cancellation_id,
      v_event_line_id,
      v_line.line_no,
      (v_line.value ->> 'orderItemId')::uuid,
      (v_line.value ->> 'reservationId')::uuid,
      (v_line.value ->> 'productId')::uuid,
      v_line.value ->> 'phaseCode',
      (v_line.value ->> 'quantity')::bigint,
      v_line.value ->> 'productSku',
      v_line.value ->> 'orderItemRef',
      v_line.value ->> 'sourceLineRef',
      (v_line.value ->> 'openReservedBefore')::bigint,
      (v_line.value ->> 'openReservedAfter')::bigint,
      (v_line.value ->> 'shippedQuantity')::bigint,
      (v_line.value ->> 'returnExpectedQuantity')::bigint,
      (v_line.value ->> 'postShipmentCancelledBefore')::bigint,
      (v_line.value ->> 'postShipmentCancelledAfter')::bigint,
      v_recorded_at
    )
    returning id into v_cancellation_line_id;

    v_line_id_map :=
      v_line_id_map ||
      jsonb_build_object(
        v_line.line_no::text,
        v_cancellation_line_id::text
      );

    if v_line.value ->> 'phaseCode' = 'PRE_SHIPMENT' then
      update inventory.stock_reservations reservation
      set released_qty =
        reservation.released_qty +
        (v_line.value ->> 'quantity')::bigint
      where reservation.id =
        (v_line.value ->> 'reservationId')::uuid
        and reservation.organization_id = p_organization_id
        and reservation.released_qty +
            reservation.consumed_qty +
            (v_line.value ->> 'quantity')::bigint
            <= reservation.reserved_qty;

      if not found then
        raise exception using
          errcode = 'P0001',
          message = 'MARKETPLACE_CANCELLATION_RESERVATION_STALE';
      end if;

      update inventory.stock_product_positions position
      set
        reserved_qty =
          position.reserved_qty -
          (v_line.value ->> 'quantity')::bigint,
        updated_at = v_recorded_at,
        version = position.version + 1
      where position.organization_id = p_organization_id
        and position.product_id =
          (v_line.value ->> 'productId')::uuid
        and position.reserved_qty >=
          (v_line.value ->> 'quantity')::bigint;

      if not found then
        raise exception using
          errcode = 'P0001',
          message =
            'MARKETPLACE_CANCELLATION_RESERVATION_PROJECTION_STALE';
      end if;

      perform operations.refresh_reservation_status(
        (v_line.value ->> 'reservationId')::uuid,
        p_occurred_at
      );

      insert into operations.marketplace_cancellation_applications (
        organization_id,
        cancellation_line_id,
        application_no,
        effect_code,
        quantity_applied,
        reservation_id,
        marketplace_ship_allocation_id,
        stock_reversal_application_id,
        created_at
      )
      values (
        p_organization_id,
        v_cancellation_line_id,
        1,
        'PRE_SHIPMENT_RELEASE',
        (v_line.value ->> 'quantity')::bigint,
        (v_line.value ->> 'reservationId')::uuid,
        null,
        null,
        v_recorded_at
      );
    end if;

    v_result_lines := v_result_lines || jsonb_build_array(
      jsonb_build_object(
        'cancellationLineId', v_cancellation_line_id,
        'eventLineId', v_event_line_id,
        'lineNo', v_line.line_no,
        'orderItemId', v_line.value ->> 'orderItemId',
        'orderItemRef', v_line.value ->> 'orderItemRef',
        'productId', v_line.value ->> 'productId',
        'productSku', v_line.value ->> 'productSku',
        'phaseCode', v_line.value ->> 'phaseCode',
        'quantity', (v_line.value ->> 'quantity')::bigint,
        'sourceLineRef', v_line.value ->> 'sourceLineRef'
      )
    );
  end loop;

  for v_original_transaction_id in
    select distinct
      (application.value ->> 'originalTransactionId')::uuid
    from jsonb_array_elements(v_preview -> 'lines') line(value)
    cross join lateral
      jsonb_array_elements(line.value -> 'applications') application(value)
    where application.value ->> 'effectCode' =
      'POST_SHIPMENT_REVERSAL'
    order by
      (application.value ->> 'originalTransactionId')::uuid
  loop
    select stock_transaction.*
    into v_original_transaction
    from inventory.stock_transactions stock_transaction
    where stock_transaction.organization_id = p_organization_id
      and stock_transaction.id = v_original_transaction_id
      and stock_transaction.transaction_type_code =
        'MARKETPLACE_OUTBOUND'
    for update;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'MARKETPLACE_CANCELLATION_ORIGINAL_TRANSACTION_NOT_FOUND';
    end if;

    v_child_command_id := gen_random_uuid();
    v_reversal_transaction_id := gen_random_uuid();
    v_reversal_line_no := 0;
    v_reversal_quantity := 0;
    v_application_count := 0;

    v_child_key :=
      'marketplace-cancellation-reversal:' ||
      encode(
        extensions.digest(
          convert_to(
            v_idempotency_key ||
            ':' ||
            v_original_transaction_id::text,
            'UTF8'
          ),
          'sha256'
        ),
        'hex'
      );

    v_child_request_hash := encode(
      extensions.digest(
        convert_to(
          jsonb_build_object(
            'parentCommandId', v_command_id,
            'cancellationId', v_cancellation_id,
            'eventRef', v_event_ref,
            'originalTransactionId', v_original_transaction_id,
            'previewBasisHash', v_expected_basis_hash,
            'schemaVersion', 1
          )::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );

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
      v_child_command_id,
      p_organization_id,
      v_child_scope,
      v_child_key,
      v_child_request_hash,
      'STARTED',
      v_recorded_at,
      null,
      null,
      '{}'::jsonb,
      null,
      null
    );

    v_reversal_transaction_no :=
      'MCR-' ||
      to_char(v_effective_local_date, 'YYYYMMDD') ||
      '-' ||
      upper(
        substr(
          replace(v_reversal_transaction_id::text, '-', ''),
          1,
          8
        )
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
    select
      v_reversal_transaction_id,
      p_organization_id,
      v_reversal_transaction_no,
      'REVERSAL',
      reason.id,
      'REVERSAL',
      v_original_transaction.channel_id,
      v_original_transaction.channel_code_snapshot,
      'MARKETPLACE_CANCELLATION',
      v_cancellation_id,
      v_event_ref,
      p_occurred_at,
      v_recorded_at,
      v_effective_local_date,
      v_actor_user_id,
      v_process_name,
      v_created_by_role_code,
      gen_random_uuid(),
      v_child_command_id,
      v_original_transaction_id,
      v_note,
      v_metadata || jsonb_build_object(
        'cancellationId', v_cancellation_id,
        'cancellationNo', v_cancellation_no,
        'cancellationEventId', v_event_id,
        'cancellationEventRef', v_event_ref,
        'originalTransactionId', v_original_transaction_id,
        'originalTransactionNo',
          v_original_transaction.transaction_no,
        'previewBasisHash', v_expected_basis_hash,
        'requestHash', v_request_hash
      ),
      1
    from catalog.movement_reasons reason
    where reason.code = 'REVERSAL'
      and reason.is_active;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'REVERSAL_REASON_NOT_CONFIGURED';
    end if;

    for v_application in
      select
        (line.value ->> 'lineNo')::integer as line_no,
        line.value ->> 'phaseCode' as phase_code,
        (line.value ->> 'reservationId')::uuid as reservation_id,
        application.value,
        (application.value ->> 'applicationNo')::integer
          as application_no,
        (application.value ->> 'quantity')::bigint
          as quantity_applied,
        (application.value ->> 'shipAllocationId')::uuid
          as ship_allocation_id,
        (application.value ->> 'originalLedgerEntryId')::uuid
          as original_ledger_entry_id,
        (application.value ->> 'productId')::uuid
          as product_id,
        (application.value ->> 'batchId')::uuid
          as batch_id,
        application.value ->> 'productSku' as product_sku,
        application.value ->> 'batchCode' as batch_code,
        (application.value ->> 'expiryDate')::date
          as expiry_date,
        application.value ->> 'bucketCode' as bucket_code
      from jsonb_array_elements(v_preview -> 'lines') line(value)
      cross join lateral
        jsonb_array_elements(line.value -> 'applications')
          application(value)
      where application.value ->> 'effectCode' =
        'POST_SHIPMENT_REVERSAL'
        and (
          application.value ->> 'originalTransactionId'
        )::uuid = v_original_transaction_id
      order by
        (application.value ->> 'originalLedgerSeq')::bigint desc,
        (line.value ->> 'lineNo')::integer,
        (application.value ->> 'applicationNo')::integer
    loop
      v_reversal_line_no := v_reversal_line_no + 1;
      v_reversal_entry_id := gen_random_uuid();

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
      )
      values (
        v_reversal_entry_id,
        p_organization_id,
        v_reversal_transaction_id,
        v_reversal_line_no,
        v_application.product_id,
        v_application.batch_id,
        v_application.product_sku,
        v_application.batch_code,
        v_application.expiry_date,
        v_application.bucket_code,
        v_application.quantity_applied,
        'REVERSAL',
        null,
        v_application.original_ledger_entry_id::text,
        p_occurred_at,
        v_recorded_at,
        v_recorded_at
      )
      returning ledger_seq into v_ledger_seq;

      update inventory.stock_batch_balances balance
      set
        sellable_qty =
          balance.sellable_qty +
          case
            when v_application.bucket_code = 'SELLABLE'
              then v_application.quantity_applied
            else 0
          end,
        quarantine_qty =
          balance.quarantine_qty +
          case
            when v_application.bucket_code = 'QUARANTINE'
              then v_application.quantity_applied
            else 0
          end,
        damaged_qty =
          balance.damaged_qty +
          case
            when v_application.bucket_code = 'DAMAGED'
              then v_application.quantity_applied
            else 0
          end,
        last_ledger_seq =
          greatest(balance.last_ledger_seq, v_ledger_seq),
        updated_at = v_recorded_at,
        version = balance.version + 1
      where balance.organization_id = p_organization_id
        and balance.product_id = v_application.product_id
        and balance.batch_id = v_application.batch_id;

      if not found then
        raise exception using
          errcode = 'P0001',
          message =
            'MARKETPLACE_CANCELLATION_BATCH_PROJECTION_NOT_FOUND';
      end if;

      update inventory.stock_product_positions position
      set
        sellable_qty =
          position.sellable_qty +
          case
            when v_application.bucket_code = 'SELLABLE'
              then v_application.quantity_applied
            else 0
          end,
        quarantine_qty =
          position.quarantine_qty +
          case
            when v_application.bucket_code = 'QUARANTINE'
              then v_application.quantity_applied
            else 0
          end,
        damaged_qty =
          position.damaged_qty +
          case
            when v_application.bucket_code = 'DAMAGED'
              then v_application.quantity_applied
            else 0
          end,
        last_ledger_seq =
          greatest(position.last_ledger_seq, v_ledger_seq),
        updated_at = v_recorded_at,
        version = position.version + 1
      where position.organization_id = p_organization_id
        and position.product_id = v_application.product_id;

      if not found then
        raise exception using
          errcode = 'P0001',
          message =
            'MARKETPLACE_CANCELLATION_PRODUCT_PROJECTION_NOT_FOUND';
      end if;

      insert into inventory.stock_reversal_applications (
        organization_id,
        original_transaction_id,
        reversal_transaction_id,
        original_entry_id,
        reversal_entry_id,
        quantity_applied,
        created_at
      )
      values (
        p_organization_id,
        v_original_transaction_id,
        v_reversal_transaction_id,
        v_application.original_ledger_entry_id,
        v_reversal_entry_id,
        v_application.quantity_applied,
        v_recorded_at
      )
      returning id into v_reversal_application_id;

      insert into operations.marketplace_cancellation_applications (
        organization_id,
        cancellation_line_id,
        application_no,
        effect_code,
        quantity_applied,
        reservation_id,
        marketplace_ship_allocation_id,
        stock_reversal_application_id,
        created_at
      )
      values (
        p_organization_id,
        (
          v_line_id_map ->>
          v_application.line_no::text
        )::uuid,
        v_application.application_no,
        'POST_SHIPMENT_REVERSAL',
        v_application.quantity_applied,
        v_application.reservation_id,
        v_application.ship_allocation_id,
        v_reversal_application_id,
        v_recorded_at
      )
      returning id into v_line_application_id;

      v_application_count := v_application_count + 1;
      v_reversal_quantity :=
        v_reversal_quantity + v_application.quantity_applied;
    end loop;

    update inventory.idempotency_commands command
    set
      status_code = 'SUCCEEDED',
      completed_at = clock_timestamp(),
      result_transaction_id = v_reversal_transaction_id,
      response_snapshot = jsonb_build_object(
        'status', 'SUCCEEDED',
        'cancellationId', v_cancellation_id,
        'originalTransactionId', v_original_transaction_id,
        'reversalTransactionId', v_reversal_transaction_id,
        'reversalTransactionNo', v_reversal_transaction_no,
        'applicationCount', v_application_count,
        'totalQuantity', v_reversal_quantity
      ),
      error_code = null
    where command.id = v_child_command_id;

    v_reversal_transaction_count :=
      v_reversal_transaction_count + 1;

    if v_reversal_transaction_count = 1 then
      v_single_reversal_transaction_id :=
        v_reversal_transaction_id;
    else
      v_single_reversal_transaction_id := null;
    end if;

    v_reversal_transactions :=
      v_reversal_transactions ||
      jsonb_build_array(
        jsonb_build_object(
          'originalTransactionId', v_original_transaction_id,
          'originalTransactionNo',
            v_original_transaction.transaction_no,
          'reversalTransactionId', v_reversal_transaction_id,
          'reversalTransactionNo', v_reversal_transaction_no,
          'applicationCount', v_application_count,
          'totalQuantity', v_reversal_quantity
        )
      );
  end loop;

  perform operations.refresh_marketplace_order_status(
    p_organization_id,
    v_order_id,
    p_occurred_at
  );

  v_response := jsonb_build_object(
    'status', 'POSTED',
    'cancellationId', v_cancellation_id,
    'cancellationNo', v_cancellation_no,
    'eventId', v_event_id,
    'eventRef', v_event_ref,
    'orderId', v_order_id,
    'orderRef', v_order_ref,
    'channelCode', v_channel_code,
    'sourceStatus', v_source_status,
    'totalQuantity', v_total_quantity,
    'preShipmentQuantity', v_pre_quantity,
    'postShipmentQuantity', v_post_quantity,
    'lineCount', jsonb_array_length(v_result_lines),
    'reversalTransactionCount',
      jsonb_array_length(v_reversal_transactions),
    'singleReversalTransactionId',
      v_single_reversal_transaction_id,
    'occurredAt', p_occurred_at,
    'recordedAt', v_recorded_at,
    'requestHash', v_request_hash,
    'previewBasisHash', v_expected_basis_hash,
    'lines', v_result_lines,
    'reversalTransactions', v_reversal_transactions
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    result_transaction_id = v_single_reversal_transaction_id,
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

revoke all on function api.post_marketplace_cancellation(
  uuid,
  text,
  text,
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

grant execute on function api.post_marketplace_cancellation(
  uuid,
  text,
  text,
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

create or replace view api.marketplace_cancellations
with (security_invoker = true)
as
select
  cancellation.id as cancellation_id,
  cancellation.organization_id,
  cancellation.cancellation_no,
  cancellation.event_id,
  cancellation.order_id,
  cancellation.channel_id,
  channel.code as channel_code,
  marketplace_order.external_order_ref,
  cancellation.external_event_ref,
  cancellation.source_status_code,
  cancellation.status_code,
  cancellation.occurred_at,
  cancellation.recorded_at,
  cancellation.actor_user_id,
  cancellation.process_name,
  cancellation.total_quantity,
  cancellation.pre_shipment_quantity,
  cancellation.post_shipment_quantity,
  cancellation.request_hash,
  cancellation.note,
  cancellation.metadata,
  cancellation.created_at
from operations.marketplace_cancellations cancellation
join catalog.channels channel
  on channel.id = cancellation.channel_id
join operations.marketplace_orders marketplace_order
  on marketplace_order.organization_id = cancellation.organization_id
 and marketplace_order.id = cancellation.order_id;

create or replace view api.marketplace_cancellation_lines
with (security_invoker = true)
as
select
  cancellation_line.id as cancellation_line_id,
  cancellation_line.organization_id,
  cancellation_line.cancellation_id,
  cancellation.cancellation_no,
  cancellation.external_event_ref,
  cancellation_line.event_line_id,
  cancellation_line.line_no,
  cancellation_line.order_item_id,
  cancellation_line.reservation_id,
  cancellation_line.product_id,
  cancellation_line.phase_code,
  cancellation_line.quantity_cancelled,
  cancellation_line.product_sku_snapshot,
  cancellation_line.order_item_ref_snapshot,
  cancellation_line.source_line_ref,
  cancellation_line.open_reserved_before,
  cancellation_line.open_reserved_after,
  cancellation_line.shipped_before,
  cancellation_line.return_expected_before,
  cancellation_line.post_cancelled_before,
  cancellation_line.post_cancelled_after,
  cancellation_line.created_at
from operations.marketplace_cancellation_lines cancellation_line
join operations.marketplace_cancellations cancellation
  on cancellation.organization_id = cancellation_line.organization_id
 and cancellation.id = cancellation_line.cancellation_id;

create or replace view api.marketplace_cancellation_applications
with (security_invoker = true)
as
select
  application.id as cancellation_application_id,
  application.organization_id,
  application.cancellation_line_id,
  cancellation_line.cancellation_id,
  cancellation.cancellation_no,
  cancellation.external_event_ref,
  application.application_no,
  application.effect_code,
  application.quantity_applied,
  application.reservation_id,
  application.marketplace_ship_allocation_id,
  allocation.event_id as original_ship_event_id,
  ship_event.external_event_ref as original_ship_event_ref,
  allocation.ledger_entry_id as original_ledger_entry_id,
  reversal_application.id as stock_reversal_application_id,
  reversal_application.original_transaction_id,
  original_transaction.transaction_no as original_transaction_no,
  reversal_application.reversal_transaction_id,
  reversal_transaction.transaction_no as reversal_transaction_no,
  reversal_application.reversal_entry_id,
  allocation.product_id,
  allocation.batch_id,
  allocation.product_sku_snapshot,
  allocation.batch_code_snapshot,
  allocation.expiry_date_snapshot,
  application.created_at
from operations.marketplace_cancellation_applications application
join operations.marketplace_cancellation_lines cancellation_line
  on cancellation_line.organization_id = application.organization_id
 and cancellation_line.id = application.cancellation_line_id
join operations.marketplace_cancellations cancellation
  on cancellation.organization_id = cancellation_line.organization_id
 and cancellation.id = cancellation_line.cancellation_id
left join operations.marketplace_ship_allocations allocation
  on allocation.id = application.marketplace_ship_allocation_id
left join operations.marketplace_events ship_event
  on ship_event.id = allocation.event_id
left join inventory.stock_reversal_applications reversal_application
  on reversal_application.id = application.stock_reversal_application_id
left join inventory.stock_transactions original_transaction
  on original_transaction.id =
    reversal_application.original_transaction_id
left join inventory.stock_transactions reversal_transaction
  on reversal_transaction.id =
    reversal_application.reversal_transaction_id;

create or replace view api.marketplace_cancellation_candidates
with (security_invoker = true)
as
with cancellation_totals as (
  select
    cancellation_line.organization_id,
    cancellation_line.order_item_id,
    coalesce(
      sum(application.quantity_applied) filter (
        where application.effect_code = 'PRE_SHIPMENT_RELEASE'
      ),
      0
    )::bigint as pre_shipment_cancelled_qty,
    coalesce(
      sum(application.quantity_applied) filter (
        where application.effect_code = 'POST_SHIPMENT_REVERSAL'
      ),
      0
    )::bigint as post_shipment_cancelled_qty
  from operations.marketplace_cancellation_lines cancellation_line
  join operations.marketplace_cancellation_applications application
    on application.organization_id = cancellation_line.organization_id
   and application.cancellation_line_id = cancellation_line.id
  group by
    cancellation_line.organization_id,
    cancellation_line.order_item_id
),
return_totals as (
  select
    return_item.organization_id,
    return_item.marketplace_order_item_id as order_item_id,
    coalesce(sum(return_item.expected_qty), 0)::bigint
      as return_expected_qty,
    coalesce(sum(return_item.received_qty), 0)::bigint
      as return_received_qty,
    coalesce(sum(return_item.sellable_qty), 0)::bigint
      as return_sellable_qty,
    coalesce(sum(return_item.damaged_qty), 0)::bigint
      as return_damaged_qty,
    coalesce(sum(return_item.lost_qty), 0)::bigint
      as return_lost_qty
  from operations.return_items return_item
  group by
    return_item.organization_id,
    return_item.marketplace_order_item_id
)
select
  marketplace_order.organization_id,
  marketplace_order.id as order_id,
  channel.code as channel_code,
  marketplace_order.external_order_ref,
  marketplace_order.status_code as order_status_code,
  item.id as order_item_id,
  item.line_no,
  item.external_item_ref,
  item.product_id,
  item.product_sku_snapshot,
  item.quantity_ordered,
  reservation.id as reservation_id,
  reservation.reserved_qty,
  reservation.consumed_qty as shipped_qty,
  reservation.released_qty,
  (
    reservation.reserved_qty -
    reservation.consumed_qty -
    reservation.released_qty
  )::bigint as open_reserved_qty,
  coalesce(
    cancellation_totals.pre_shipment_cancelled_qty,
    0
  )::bigint as pre_shipment_cancelled_qty,
  coalesce(
    cancellation_totals.post_shipment_cancelled_qty,
    0
  )::bigint as post_shipment_cancelled_qty,
  coalesce(return_totals.return_expected_qty, 0)::bigint
    as return_expected_qty,
  coalesce(return_totals.return_received_qty, 0)::bigint
    as return_received_qty,
  coalesce(return_totals.return_sellable_qty, 0)::bigint
    as return_sellable_qty,
  coalesce(return_totals.return_damaged_qty, 0)::bigint
    as return_damaged_qty,
  coalesce(return_totals.return_lost_qty, 0)::bigint
    as return_lost_qty,
  greatest(
    reservation.consumed_qty -
    coalesce(
      cancellation_totals.post_shipment_cancelled_qty,
      0
    ) -
    coalesce(return_totals.return_expected_qty, 0),
    0
  )::bigint as remaining_post_cancellable_qty,
  (
    reservation.reserved_qty -
    reservation.consumed_qty -
    reservation.released_qty +
    greatest(
      reservation.consumed_qty -
      coalesce(
        cancellation_totals.post_shipment_cancelled_qty,
        0
      ) -
      coalesce(return_totals.return_expected_qty, 0),
      0
    )
  )::bigint as total_remaining_cancellable_qty,
  case
    when coalesce(
      cancellation_totals.pre_shipment_cancelled_qty,
      0
    ) = 0
     and coalesce(
       cancellation_totals.post_shipment_cancelled_qty,
       0
     ) = 0
      then 'NONE'
    when coalesce(
      cancellation_totals.pre_shipment_cancelled_qty,
      0
    ) > 0
     and coalesce(
       cancellation_totals.post_shipment_cancelled_qty,
       0
     ) > 0
      then 'MIXED'
    when coalesce(
      cancellation_totals.pre_shipment_cancelled_qty,
      0
    ) > 0
      then 'PRE_SHIPMENT'
    else 'POST_SHIPMENT'
  end as cancellation_status_code,
  reservation.status_code as reservation_status_code,
  reservation.reserved_at,
  reservation.closed_at
from operations.marketplace_orders marketplace_order
join catalog.channels channel
  on channel.id = marketplace_order.channel_id
join operations.marketplace_order_items item
  on item.organization_id = marketplace_order.organization_id
 and item.order_id = marketplace_order.id
join inventory.stock_reservations reservation
  on reservation.id = item.reservation_id
left join cancellation_totals
  on cancellation_totals.organization_id = item.organization_id
 and cancellation_totals.order_item_id = item.id
left join return_totals
  on return_totals.organization_id = item.organization_id
 and return_totals.order_item_id = item.id;

create or replace view api.marketplace_reservations
with (security_invoker = true)
as
select
  candidate.organization_id,
  candidate.order_id,
  candidate.channel_code,
  candidate.external_order_ref,
  candidate.order_item_id,
  candidate.line_no,
  candidate.external_item_ref,
  candidate.product_id,
  candidate.product_sku_snapshot,
  candidate.quantity_ordered,
  candidate.reservation_id,
  candidate.reserved_qty,
  candidate.shipped_qty as consumed_qty,
  candidate.released_qty,
  candidate.open_reserved_qty as open_qty,
  candidate.reservation_status_code as status_code,
  candidate.reserved_at,
  candidate.closed_at,
  candidate.pre_shipment_cancelled_qty,
  candidate.post_shipment_cancelled_qty,
  candidate.return_expected_qty,
  candidate.remaining_post_cancellable_qty,
  candidate.total_remaining_cancellable_qty,
  candidate.cancellation_status_code
from api.marketplace_cancellation_candidates candidate;

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
  coalesce(sum(candidate.reserved_qty), 0)
    as reserved_qty,
  coalesce(sum(candidate.shipped_qty), 0)
    as shipped_qty,
  coalesce(sum(candidate.released_qty), 0)
    as released_qty,
  coalesce(sum(candidate.open_reserved_qty), 0)
    as open_qty,
  coalesce(
    sum(candidate.pre_shipment_cancelled_qty),
    0
  )::bigint as pre_shipment_cancelled_qty,
  coalesce(
    sum(candidate.post_shipment_cancelled_qty),
    0
  )::bigint as post_shipment_cancelled_qty,
  coalesce(sum(candidate.return_expected_qty), 0)::bigint
    as return_expected_qty,
  coalesce(
    sum(candidate.remaining_post_cancellable_qty),
    0
  )::bigint as remaining_post_cancellable_qty,
  coalesce(
    sum(candidate.total_remaining_cancellable_qty),
    0
  )::bigint as total_remaining_cancellable_qty,
  case
    when coalesce(
      sum(candidate.pre_shipment_cancelled_qty),
      0
    ) = 0
     and coalesce(
       sum(candidate.post_shipment_cancelled_qty),
       0
     ) = 0
      then 'NONE'
    when coalesce(
      sum(candidate.pre_shipment_cancelled_qty),
      0
    ) > 0
     and coalesce(
       sum(candidate.post_shipment_cancelled_qty),
       0
     ) > 0
      then 'MIXED'
    when coalesce(
      sum(candidate.pre_shipment_cancelled_qty),
      0
    ) > 0
      then 'PRE_SHIPMENT'
    else 'POST_SHIPMENT'
  end as cancellation_status_code
from operations.marketplace_orders marketplace_order
join catalog.channels channel
  on channel.id = marketplace_order.channel_id
left join api.marketplace_cancellation_candidates candidate
  on candidate.organization_id = marketplace_order.organization_id
 and candidate.order_id = marketplace_order.id
group by marketplace_order.id, channel.code;

revoke all on api.marketplace_cancellations,
              api.marketplace_cancellation_lines,
              api.marketplace_cancellation_applications,
              api.marketplace_cancellation_candidates
from public, anon, authenticated;

grant select on api.marketplace_cancellations,
                api.marketplace_cancellation_lines,
                api.marketplace_cancellation_applications,
                api.marketplace_cancellation_candidates
to authenticated, service_role;

grant select on api.marketplace_orders,
                api.marketplace_reservations
to authenticated, service_role;

comment on table operations.marketplace_cancellations is
  'Immutable canonical marketplace cancellation headers. One external cancellation may create zero or multiple exact stock reversal transactions.';

comment on table operations.marketplace_cancellation_lines is
  'Immutable per-item cancellation lines with explicit PRE_SHIPMENT or POST_SHIPMENT phase and authoritative quantity snapshots.';

comment on table operations.marketplace_cancellation_applications is
  'Immutable applications linking reservation release or exact shipment allocation reversal to a cancellation line.';

comment on function api.preview_marketplace_cancellation(
  uuid,
  text,
  text,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  jsonb
) is
  'Returns a stock-neutral authoritative preview for explicit per-item marketplace cancellation phases.';

comment on function api.post_marketplace_cancellation(
  uuid,
  text,
  text,
  text,
  text,
  timestamptz,
  text,
  jsonb,
  text,
  boolean,
  text,
  jsonb
) is
  'Posts one immutable marketplace cancellation event. PRE_SHIPMENT releases reservations; POST_SHIPMENT creates exact partial reversal applications without rerunning FEFO.';

commit;
