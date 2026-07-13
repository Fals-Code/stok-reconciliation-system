begin;

create table operations.returns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  channel_id uuid not null references catalog.channels(id) on delete restrict,
  marketplace_order_id uuid not null,
  external_return_ref text not null,
  source_status_code text null,
  status_code text not null default 'EXPECTED',
  outcome_code text null,
  expected_at timestamptz not null,
  closed_at timestamptz null,
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint uq_returns_org_id unique (organization_id, id),
  constraint fk_returns_marketplace_order foreign key (organization_id, marketplace_order_id)
    references operations.marketplace_orders (organization_id, id)
    on delete restrict,
  constraint uq_returns_external unique (
    organization_id,
    channel_id,
    external_return_ref
  ),
  constraint ck_returns_ref_nonblank check (btrim(external_return_ref) <> ''),
  constraint ck_returns_source_status_nonblank check (
    source_status_code is null or btrim(source_status_code) <> ''
  ),
  constraint ck_returns_status check (
    status_code in (
      'EXPECTED',
      'IN_TRANSIT',
      'PARTIALLY_RECEIVED',
      'RECEIVED_PENDING_INSPECTION',
      'PARTIALLY_INSPECTED',
      'COMPLETED_SELLABLE',
      'COMPLETED_DAMAGED',
      'COMPLETED_MIXED',
      'LOST',
      'CLOSED',
      'EXCEPTION'
    )
  ),
  constraint ck_returns_outcome check (
    outcome_code is null
    or outcome_code in ('SELLABLE', 'DAMAGED', 'MIXED', 'LOST')
  ),
  constraint ck_returns_closed_state check (
    (status_code = 'CLOSED' and closed_at is not null)
    or (status_code <> 'CLOSED' and closed_at is null)
  ),
  constraint ck_returns_actor_xor_process check (
    (actor_user_id is not null) <> (process_name is not null)
  ),
  constraint ck_returns_process_nonblank check (
    process_name is null or btrim(process_name) <> ''
  ),
  constraint ck_returns_metadata_object check (jsonb_typeof(metadata) = 'object')
);

create trigger trg_returns_touch_updated_at
before update on operations.returns
for each row execute function app.touch_updated_at();

create table operations.return_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  return_id uuid not null,
  line_no integer not null,
  marketplace_order_item_id uuid not null,
  product_id uuid not null,
  expected_qty bigint not null,
  received_qty bigint not null default 0,
  sellable_qty bigint not null default 0,
  damaged_qty bigint not null default 0,
  lost_qty bigint not null default 0,
  product_sku_snapshot text not null,
  source_line_ref text not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint uq_return_items_org_id unique (organization_id, id),
  constraint fk_return_items_return foreign key (organization_id, return_id)
    references operations.returns (organization_id, id)
    on delete restrict,
  constraint fk_return_items_marketplace_item foreign key (
    organization_id,
    marketplace_order_item_id
  ) references operations.marketplace_order_items (organization_id, id)
    on delete restrict,
  constraint fk_return_items_product foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,
  constraint uq_return_items_line unique (return_id, line_no),
  constraint uq_return_items_marketplace_item unique (return_id, marketplace_order_item_id),
  constraint uq_return_items_source_line unique (return_id, source_line_ref),
  constraint ck_return_items_line_positive check (line_no > 0),
  constraint ck_return_items_expected_positive check (expected_qty > 0),
  constraint ck_return_items_received_nonnegative check (received_qty >= 0),
  constraint ck_return_items_sellable_nonnegative check (sellable_qty >= 0),
  constraint ck_return_items_damaged_nonnegative check (damaged_qty >= 0),
  constraint ck_return_items_lost_nonnegative check (lost_qty >= 0),
  constraint ck_return_items_arrival_accounting check (
    received_qty + lost_qty <= expected_qty
  ),
  constraint ck_return_items_inspection_accounting check (
    sellable_qty + damaged_qty <= received_qty
  ),
  constraint ck_return_items_sku_nonblank check (btrim(product_sku_snapshot) <> ''),
  constraint ck_return_items_source_nonblank check (btrim(source_line_ref) <> '')
);

create trigger trg_return_items_touch_updated_at
before update on operations.return_items
for each row execute function app.touch_updated_at();

create table operations.return_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  return_id uuid not null,
  external_event_ref text not null,
  event_type_code text not null,
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
  constraint uq_return_events_org_id unique (organization_id, id),
  constraint fk_return_events_return foreign key (organization_id, return_id)
    references operations.returns (organization_id, id)
    on delete restrict,
  constraint uq_return_events_external unique (organization_id, external_event_ref),
  constraint uq_return_events_idempotency unique (idempotency_command_id),
  constraint uq_return_events_transaction unique (transaction_id),
  constraint ck_return_events_ref_nonblank check (btrim(external_event_ref) <> ''),
  constraint ck_return_events_type check (
    event_type_code in ('EXPECTED', 'RECEIPT', 'INSPECTION', 'LOST')
  ),
  constraint ck_return_events_transaction_rule check (
    (event_type_code in ('RECEIPT', 'INSPECTION') and transaction_id is not null)
    or (event_type_code in ('EXPECTED', 'LOST') and transaction_id is null)
  ),
  constraint ck_return_events_actor_xor_process check (
    (actor_user_id is not null) <> (process_name is not null)
  ),
  constraint ck_return_events_process_nonblank check (
    process_name is null or btrim(process_name) <> ''
  ),
  constraint ck_return_events_metadata_object check (jsonb_typeof(metadata) = 'object')
);

create table operations.return_event_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  event_id uuid not null,
  return_item_id uuid not null,
  line_no integer not null,
  quantity bigint not null,
  outcome_code text not null,
  source_line_ref text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_return_event_lines_org_id unique (organization_id, id),
  constraint fk_return_event_lines_event foreign key (organization_id, event_id)
    references operations.return_events (organization_id, id)
    on delete restrict,
  constraint fk_return_event_lines_item foreign key (organization_id, return_item_id)
    references operations.return_items (organization_id, id)
    on delete restrict,
  constraint uq_return_event_lines_line unique (event_id, line_no),
  constraint uq_return_event_lines_source unique (event_id, source_line_ref),
  constraint ck_return_event_lines_line_positive check (line_no > 0),
  constraint ck_return_event_lines_quantity_positive check (quantity > 0),
  constraint ck_return_event_lines_outcome check (
    outcome_code in ('EXPECTED', 'QUARANTINE', 'SELLABLE', 'DAMAGED', 'MIXED', 'LOST')
  ),
  constraint ck_return_event_lines_source_nonblank check (btrim(source_line_ref) <> '')
);

create table operations.return_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  return_id uuid not null,
  event_id uuid not null,
  receipt_ref text not null,
  occurred_at timestamptz not null,
  transaction_id uuid not null references inventory.stock_transactions(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_return_receipts_org_id unique (organization_id, id),
  constraint fk_return_receipts_return foreign key (organization_id, return_id)
    references operations.returns (organization_id, id)
    on delete restrict,
  constraint fk_return_receipts_event foreign key (organization_id, event_id)
    references operations.return_events (organization_id, id)
    on delete restrict,
  constraint uq_return_receipts_ref unique (organization_id, receipt_ref),
  constraint uq_return_receipts_event unique (event_id),
  constraint uq_return_receipts_transaction unique (transaction_id),
  constraint ck_return_receipts_ref_nonblank check (btrim(receipt_ref) <> '')
);

create table operations.return_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  receipt_id uuid not null,
  event_line_id uuid not null,
  return_item_id uuid not null,
  marketplace_ship_allocation_id uuid null
    references operations.marketplace_ship_allocations(id) on delete restrict,
  line_no integer not null,
  product_id uuid not null,
  batch_id uuid not null,
  quantity_received bigint not null,
  batch_identity_verified boolean not null,
  product_sku_snapshot text not null,
  batch_code_snapshot text not null,
  expiry_date_snapshot date not null,
  source_line_ref text not null,
  ledger_entry_id uuid not null references inventory.stock_ledger_entries(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_return_receipt_lines_org_id unique (organization_id, id),
  constraint fk_return_receipt_lines_receipt foreign key (organization_id, receipt_id)
    references operations.return_receipts (organization_id, id)
    on delete restrict,
  constraint fk_return_receipt_lines_event_line foreign key (organization_id, event_line_id)
    references operations.return_event_lines (organization_id, id)
    on delete restrict,
  constraint fk_return_receipt_lines_item foreign key (organization_id, return_item_id)
    references operations.return_items (organization_id, id)
    on delete restrict,
  constraint fk_return_receipt_lines_batch foreign key (
    organization_id,
    product_id,
    batch_id
  ) references catalog.product_batches (organization_id, product_id, id)
    on delete restrict,
  constraint uq_return_receipt_lines_line unique (receipt_id, line_no),
  constraint uq_return_receipt_lines_source unique (receipt_id, source_line_ref),
  constraint uq_return_receipt_lines_event_line unique (event_line_id),
  constraint uq_return_receipt_lines_ledger unique (ledger_entry_id),
  constraint ck_return_receipt_lines_line_positive check (line_no > 0),
  constraint ck_return_receipt_lines_quantity_positive check (quantity_received > 0),
  constraint ck_return_receipt_lines_sku_nonblank check (btrim(product_sku_snapshot) <> ''),
  constraint ck_return_receipt_lines_batch_nonblank check (btrim(batch_code_snapshot) <> ''),
  constraint ck_return_receipt_lines_source_nonblank check (btrim(source_line_ref) <> '')
);

create table operations.return_inspections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  return_id uuid not null,
  event_id uuid not null,
  inspection_ref text not null,
  occurred_at timestamptz not null,
  transaction_id uuid not null references inventory.stock_transactions(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_return_inspections_org_id unique (organization_id, id),
  constraint fk_return_inspections_return foreign key (organization_id, return_id)
    references operations.returns (organization_id, id)
    on delete restrict,
  constraint fk_return_inspections_event foreign key (organization_id, event_id)
    references operations.return_events (organization_id, id)
    on delete restrict,
  constraint uq_return_inspections_ref unique (organization_id, inspection_ref),
  constraint uq_return_inspections_event unique (event_id),
  constraint uq_return_inspections_transaction unique (transaction_id),
  constraint ck_return_inspections_ref_nonblank check (btrim(inspection_ref) <> '')
);

create table operations.return_inspection_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  inspection_id uuid not null,
  event_line_id uuid not null,
  receipt_line_id uuid not null,
  allocation_no integer not null,
  destination_bucket_code text not null,
  quantity_allocated bigint not null,
  pair_no integer not null,
  source_ledger_entry_id uuid not null references inventory.stock_ledger_entries(id) on delete restrict,
  destination_ledger_entry_id uuid not null references inventory.stock_ledger_entries(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint fk_return_inspection_allocations_inspection foreign key (
    organization_id,
    inspection_id
  ) references operations.return_inspections (organization_id, id)
    on delete restrict,
  constraint fk_return_inspection_allocations_event_line foreign key (
    organization_id,
    event_line_id
  ) references operations.return_event_lines (organization_id, id)
    on delete restrict,
  constraint fk_return_inspection_allocations_receipt_line foreign key (
    organization_id,
    receipt_line_id
  ) references operations.return_receipt_lines (organization_id, id)
    on delete restrict,
  constraint uq_return_inspection_allocations_no unique (inspection_id, allocation_no),
  constraint uq_return_inspection_allocations_bucket unique (
    inspection_id,
    receipt_line_id,
    destination_bucket_code
  ),
  constraint uq_return_inspection_allocations_source_ledger unique (source_ledger_entry_id),
  constraint uq_return_inspection_allocations_destination_ledger unique (destination_ledger_entry_id),
  constraint ck_return_inspection_allocations_no_positive check (allocation_no > 0),
  constraint ck_return_inspection_allocations_destination check (
    destination_bucket_code in ('SELLABLE', 'DAMAGED')
  ),
  constraint ck_return_inspection_allocations_quantity_positive check (quantity_allocated > 0),
  constraint ck_return_inspection_allocations_pair_positive check (pair_no > 0),
  constraint ck_return_inspection_allocations_distinct_ledger check (
    source_ledger_entry_id <> destination_ledger_entry_id
  )
);

create index idx_returns_status
on operations.returns (organization_id, status_code, expected_at, id);

create index idx_returns_order
on operations.returns (organization_id, marketplace_order_id, expected_at, id);

create index idx_return_items_order_item
on operations.return_items (
  organization_id,
  marketplace_order_item_id,
  return_id,
  line_no
);

create index idx_return_events_return
on operations.return_events (organization_id, return_id, occurred_at, id);

create index idx_return_receipt_lines_item
on operations.return_receipt_lines (organization_id, return_item_id, receipt_id, line_no);

create index idx_return_receipt_lines_batch
on operations.return_receipt_lines (organization_id, batch_id, receipt_id, line_no);

create index idx_return_inspection_allocations_receipt
on operations.return_inspection_allocations (
  organization_id,
  receipt_line_id,
  inspection_id,
  allocation_no
);

create trigger trg_return_events_immutable
before update or delete on operations.return_events
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_return_event_lines_immutable
before update or delete on operations.return_event_lines
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_return_receipts_immutable
before update or delete on operations.return_receipts
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_return_receipt_lines_immutable
before update or delete on operations.return_receipt_lines
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_return_inspections_immutable
before update or delete on operations.return_inspections
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_return_inspection_allocations_immutable
before update or delete on operations.return_inspection_allocations
for each row execute function inventory.reject_immutable_mutation();

alter table operations.returns enable row level security;
alter table operations.return_items enable row level security;
alter table operations.return_events enable row level security;
alter table operations.return_event_lines enable row level security;
alter table operations.return_receipts enable row level security;
alter table operations.return_receipt_lines enable row level security;
alter table operations.return_inspections enable row level security;
alter table operations.return_inspection_allocations enable row level security;

create policy returns_read_current_org
on operations.returns
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy return_items_read_current_org
on operations.return_items
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy return_events_read_current_org
on operations.return_events
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy return_event_lines_read_current_org
on operations.return_event_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy return_receipts_read_current_org
on operations.return_receipts
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy return_receipt_lines_read_current_org
on operations.return_receipt_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy return_inspections_read_current_org
on operations.return_inspections
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy return_inspection_allocations_read_current_org
on operations.return_inspection_allocations
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on operations.returns,
              operations.return_items,
              operations.return_events,
              operations.return_event_lines,
              operations.return_receipts,
              operations.return_receipt_lines,
              operations.return_inspections,
              operations.return_inspection_allocations
from anon, authenticated;

grant usage on schema operations to authenticated, service_role;

grant select on operations.returns,
                operations.return_items,
                operations.return_events,
                operations.return_event_lines,
                operations.return_receipts,
                operations.return_receipt_lines,
                operations.return_inspections,
                operations.return_inspection_allocations
  to authenticated, service_role;

create or replace function operations.refresh_return_status(
  p_organization_id uuid,
  p_return_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, operations
as $$
declare
  v_expected bigint;
  v_received bigint;
  v_sellable bigint;
  v_damaged bigint;
  v_lost bigint;
  v_pending_arrival bigint;
  v_pending_inspection bigint;
  v_status text;
  v_outcome text;
begin
  select
    sum(item.expected_qty),
    sum(item.received_qty),
    sum(item.sellable_qty),
    sum(item.damaged_qty),
    sum(item.lost_qty)
  into
    v_expected,
    v_received,
    v_sellable,
    v_damaged,
    v_lost
  from operations.return_items item
  where item.organization_id = p_organization_id
    and item.return_id = p_return_id;

  if v_expected is null then
    raise exception using errcode = 'P0001', message = 'RETURN_ITEMS_REQUIRED';
  end if;

  v_pending_arrival := v_expected - v_received - v_lost;
  v_pending_inspection := v_received - v_sellable - v_damaged;
  v_outcome := null;

  if v_pending_arrival = 0 and v_pending_inspection = 0 then
    if v_lost = v_expected and v_received = 0 then
      v_status := 'LOST';
      v_outcome := 'LOST';
    elsif v_sellable = v_expected then
      v_status := 'COMPLETED_SELLABLE';
      v_outcome := 'SELLABLE';
    elsif v_damaged = v_expected then
      v_status := 'COMPLETED_DAMAGED';
      v_outcome := 'DAMAGED';
    else
      v_status := 'COMPLETED_MIXED';
      v_outcome := 'MIXED';
    end if;
  elsif v_sellable + v_damaged > 0 then
    v_status := 'PARTIALLY_INSPECTED';
  elsif v_pending_arrival = 0 and v_pending_inspection > 0 then
    v_status := 'RECEIVED_PENDING_INSPECTION';
  elsif v_received + v_lost > 0 then
    v_status := 'PARTIALLY_RECEIVED';
  else
    v_status := 'EXPECTED';
  end if;

  update operations.returns return_header
  set
    status_code = v_status,
    outcome_code = v_outcome
  where return_header.organization_id = p_organization_id
    and return_header.id = p_return_id;
end;
$$;

revoke all on function operations.refresh_return_status(uuid, uuid)
from public, anon, authenticated;

create or replace view api.returns
with (security_invoker = true)
as
select
  return_header.id as return_id,
  return_header.organization_id,
  channel.code as channel_code,
  return_header.marketplace_order_id,
  marketplace_order.external_order_ref as marketplace_order_ref,
  return_header.external_return_ref,
  return_header.source_status_code,
  return_header.status_code,
  return_header.outcome_code,
  return_header.expected_at,
  return_header.closed_at,
  return_header.actor_user_id,
  return_header.process_name,
  return_header.metadata,
  return_header.created_at,
  return_header.updated_at,
  coalesce(sum(item.expected_qty), 0) as expected_qty,
  coalesce(sum(item.received_qty), 0) as received_qty,
  coalesce(sum(item.sellable_qty), 0) as sellable_qty,
  coalesce(sum(item.damaged_qty), 0) as damaged_qty,
  coalesce(sum(item.lost_qty), 0) as lost_qty,
  coalesce(sum(item.expected_qty - item.received_qty - item.lost_qty), 0)
    as pending_arrival_qty,
  coalesce(sum(item.received_qty - item.sellable_qty - item.damaged_qty), 0)
    as pending_inspection_qty
from operations.returns return_header
join catalog.channels channel on channel.id = return_header.channel_id
join operations.marketplace_orders marketplace_order
  on marketplace_order.organization_id = return_header.organization_id
 and marketplace_order.id = return_header.marketplace_order_id
left join operations.return_items item
  on item.organization_id = return_header.organization_id
 and item.return_id = return_header.id
group by
  return_header.id,
  channel.code,
  marketplace_order.external_order_ref;

create or replace view api.return_items
with (security_invoker = true)
as
select
  item.id as return_item_id,
  item.organization_id,
  item.return_id,
  item.line_no,
  item.marketplace_order_item_id,
  marketplace_item.external_item_ref as marketplace_item_ref,
  item.product_id,
  item.product_sku_snapshot,
  item.source_line_ref,
  item.expected_qty,
  item.received_qty,
  item.sellable_qty,
  item.damaged_qty,
  item.lost_qty,
  item.expected_qty - item.received_qty - item.lost_qty as pending_arrival_qty,
  item.received_qty - item.sellable_qty - item.damaged_qty as pending_inspection_qty,
  item.created_at,
  item.updated_at
from operations.return_items item
join operations.marketplace_order_items marketplace_item
  on marketplace_item.organization_id = item.organization_id
 and marketplace_item.id = item.marketplace_order_item_id;

create or replace view api.return_events
with (security_invoker = true)
as
select
  event.id as event_id,
  event.organization_id,
  event.return_id,
  event.external_event_ref,
  event.event_type_code,
  event.occurred_at,
  event.recorded_at,
  event.actor_user_id,
  event.process_name,
  event.transaction_id,
  event.note,
  event.metadata,
  event.created_at
from operations.return_events event;

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
  line.created_at
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
  allocation.created_at
from operations.return_inspection_allocations allocation
join operations.return_inspections inspection
  on inspection.organization_id = allocation.organization_id
 and inspection.id = allocation.inspection_id;

revoke all on api.returns,
              api.return_items,
              api.return_events,
              api.return_receipt_lines,
              api.return_inspection_allocations
from anon;

grant select on api.returns,
                api.return_items,
                api.return_events,
                api.return_receipt_lines,
                api.return_inspection_allocations
  to authenticated, service_role;

alter default privileges in schema operations revoke all on tables from anon, authenticated;

commit;
