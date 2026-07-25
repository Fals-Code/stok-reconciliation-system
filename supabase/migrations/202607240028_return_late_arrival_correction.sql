begin;

alter table operations.return_items
add column late_arrival_qty bigint not null default 0;

alter table operations.return_items
drop constraint ck_return_items_arrival_accounting;

alter table operations.return_items
add constraint ck_return_items_late_arrival_nonnegative
check (late_arrival_qty >= 0);

alter table operations.return_items
add constraint ck_return_items_late_arrival_not_over_lost
check (late_arrival_qty <= lost_qty);

alter table operations.return_items
add constraint ck_return_items_late_arrival_accounting
check (received_qty + lost_qty - late_arrival_qty <= expected_qty);

alter table operations.return_events
drop constraint ck_return_events_type;

alter table operations.return_events
add constraint ck_return_events_type
check (event_type_code in ('EXPECTED', 'RECEIPT', 'INSPECTION', 'LOST', 'LATE_ARRIVAL'));

alter table operations.return_events
drop constraint ck_return_events_transaction_rule;

alter table operations.return_events
add constraint ck_return_events_transaction_rule
check (
  (event_type_code in ('EXPECTED', 'LOST', 'LATE_ARRIVAL') and transaction_id is null)
  or event_type_code in ('RECEIPT', 'INSPECTION')
);

create table operations.return_late_arrivals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  return_id uuid not null,
  receipt_id uuid not null,
  event_id uuid not null,
  late_arrival_reference text not null,
  occurred_at timestamptz not null,
  note text null,
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  idempotency_command_id uuid not null references inventory.idempotency_commands(id) on delete restrict,
  request_hash text not null,
  schema_version integer not null default 1,
  rule_version text not null default 'RETURN_LATE_ARRIVAL_V1',
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_return_late_arrivals_org_id unique (organization_id, id),
  constraint uq_return_late_arrivals_reference unique (organization_id, late_arrival_reference),
  constraint uq_return_late_arrivals_receipt unique (organization_id, receipt_id),
  constraint uq_return_late_arrivals_event unique (organization_id, event_id),
  constraint uq_return_late_arrivals_command unique (idempotency_command_id),
  constraint fk_return_late_arrivals_return foreign key (organization_id, return_id)
    references operations.returns (organization_id, id) on delete restrict,
  constraint fk_return_late_arrivals_receipt foreign key (organization_id, receipt_id)
    references operations.return_receipts (organization_id, id) on delete restrict,
  constraint fk_return_late_arrivals_event foreign key (organization_id, event_id)
    references operations.return_events (organization_id, id) on delete restrict,
  constraint ck_return_late_arrivals_reference_nonblank check (btrim(late_arrival_reference) <> '' and length(late_arrival_reference) <= 200),
  constraint ck_return_late_arrivals_note_size check (note is null or length(note) <= 2000),
  constraint ck_return_late_arrivals_actor check ((actor_user_id is not null) <> (process_name is not null)),
  constraint ck_return_late_arrivals_process check (process_name is null or btrim(process_name) <> ''),
  constraint ck_return_late_arrivals_hash check (request_hash ~ '^[0-9a-f]{64}$'),
  constraint ck_return_late_arrivals_schema_version check (schema_version > 0),
  constraint ck_return_late_arrivals_rule_version check (btrim(rule_version) <> '')
);

create table operations.return_late_arrival_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  late_arrival_id uuid not null,
  return_item_id uuid not null,
  lost_event_line_id uuid not null,
  allocation_no integer not null,
  request_line_no integer not null,
  quantity bigint not null,
  product_id uuid not null,
  product_sku_snapshot text not null,
  source_line_ref text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_return_late_arrival_lines_org_id unique (organization_id, id),
  constraint uq_return_late_arrival_lines_allocation unique (late_arrival_id, allocation_no),
  constraint uq_return_late_arrival_lines_lost unique (late_arrival_id, lost_event_line_id),
  constraint fk_return_late_arrival_lines_header foreign key (organization_id, late_arrival_id)
    references operations.return_late_arrivals (organization_id, id) on delete restrict,
  constraint fk_return_late_arrival_lines_item foreign key (organization_id, return_item_id)
    references operations.return_items (organization_id, id) on delete restrict,
  constraint fk_return_late_arrival_lines_lost_event_line foreign key (organization_id, lost_event_line_id)
    references operations.return_event_lines (organization_id, id) on delete restrict,
  constraint fk_return_late_arrival_lines_product foreign key (organization_id, product_id)
    references catalog.products (organization_id, id) on delete restrict,
  constraint ck_return_late_arrival_lines_allocation_positive check (allocation_no > 0 and request_line_no > 0),
  constraint ck_return_late_arrival_lines_quantity_positive check (quantity > 0),
  constraint ck_return_late_arrival_lines_sku_nonblank check (btrim(product_sku_snapshot) <> ''),
  constraint ck_return_late_arrival_lines_source_nonblank check (btrim(source_line_ref) <> '')
);

alter table operations.return_receipt_lines
add column late_arrival_line_id uuid null;

alter table operations.return_receipt_lines
add constraint fk_return_receipt_lines_late_arrival_line
foreign key (organization_id, late_arrival_line_id)
references operations.return_late_arrival_lines (organization_id, id)
on delete restrict;

alter table operations.return_receipt_lines
add constraint uq_return_receipt_lines_late_arrival_line
unique (organization_id, late_arrival_line_id);

create table operations.return_late_arrival_claim_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  late_arrival_id uuid not null,
  claim_id uuid not null,
  claim_status_snapshot text not null,
  warning_required boolean not null,
  detected_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_return_late_arrival_claim_links_org_id unique (organization_id, id),
  constraint uq_return_late_arrival_claim_links_once unique (late_arrival_id, claim_id),
  constraint fk_return_late_arrival_claim_links_header foreign key (organization_id, late_arrival_id)
    references operations.return_late_arrivals (organization_id, id) on delete restrict,
  constraint fk_return_late_arrival_claim_links_claim foreign key (organization_id, claim_id)
    references operations.return_claims (organization_id, id) on delete restrict,
  constraint ck_return_late_arrival_claim_links_status check (claim_status_snapshot in ('NOT_STARTED','DUE_SOON','SUBMITTED','RESOLVED','EXPIRED','EXCEPTION','CANCELLED'))
);

create index idx_return_late_arrivals_return
on operations.return_late_arrivals (organization_id, return_id, occurred_at, id);
create index idx_return_late_arrival_lines_item
on operations.return_late_arrival_lines (organization_id, return_item_id, lost_event_line_id, id);
create index idx_return_late_arrival_claim_links_claim
on operations.return_late_arrival_claim_links (organization_id, claim_id, warning_required, id);

create trigger trg_return_late_arrivals_immutable
before update or delete on operations.return_late_arrivals
for each row execute function inventory.reject_immutable_mutation();
create trigger trg_return_late_arrival_lines_immutable
before update or delete on operations.return_late_arrival_lines
for each row execute function inventory.reject_immutable_mutation();
create trigger trg_return_late_arrival_claim_links_immutable
before update or delete on operations.return_late_arrival_claim_links
for each row execute function inventory.reject_immutable_mutation();

alter table operations.return_late_arrivals enable row level security;
alter table operations.return_late_arrival_lines enable row level security;
alter table operations.return_late_arrival_claim_links enable row level security;

create policy return_late_arrivals_read_current_org on operations.return_late_arrivals
for select to authenticated using (organization_id = (select app.current_organization_id()));
create policy return_late_arrival_lines_read_current_org on operations.return_late_arrival_lines
for select to authenticated using (organization_id = (select app.current_organization_id()));
create policy return_late_arrival_claim_links_read_current_org on operations.return_late_arrival_claim_links
for select to authenticated using (organization_id = (select app.current_organization_id()));

revoke all on operations.return_late_arrivals, operations.return_late_arrival_lines,
  operations.return_late_arrival_claim_links from public, anon, authenticated;
grant select on operations.return_late_arrivals, operations.return_late_arrival_lines,
  operations.return_late_arrival_claim_links to authenticated, service_role;

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
  v_gross_lost bigint;
  v_late_arrival bigint;
  v_net_lost bigint;
  v_pending_arrival bigint;
  v_pending_inspection bigint;
  v_status text;
  v_outcome text;
begin
  select sum(expected_qty), sum(received_qty), sum(sellable_qty), sum(damaged_qty), sum(lost_qty), sum(late_arrival_qty)
  into v_expected, v_received, v_sellable, v_damaged, v_gross_lost, v_late_arrival
  from operations.return_items
  where organization_id = p_organization_id and return_id = p_return_id;

  if v_expected is null then
    raise exception using errcode = 'P0001', message = 'RETURN_ITEMS_REQUIRED';
  end if;

  v_net_lost := v_gross_lost - v_late_arrival;
  v_pending_arrival := v_expected - v_received - v_net_lost;
  v_pending_inspection := v_received - v_sellable - v_damaged;
  v_outcome := null;

  if v_pending_arrival = 0 and v_pending_inspection = 0 then
    if v_net_lost = v_expected and v_received = 0 then
      v_status := 'LOST'; v_outcome := 'LOST';
    elsif v_sellable = v_expected then
      v_status := 'COMPLETED_SELLABLE'; v_outcome := 'SELLABLE';
    elsif v_damaged = v_expected then
      v_status := 'COMPLETED_DAMAGED'; v_outcome := 'DAMAGED';
    else
      v_status := 'COMPLETED_MIXED'; v_outcome := 'MIXED';
    end if;
  elsif v_sellable + v_damaged > 0 then
    v_status := 'PARTIALLY_INSPECTED';
  elsif v_pending_arrival = 0 and v_pending_inspection > 0 then
    v_status := 'RECEIVED_PENDING_INSPECTION';
  elsif v_received + v_net_lost > 0 then
    v_status := 'PARTIALLY_RECEIVED';
  else
    v_status := 'EXPECTED';
  end if;

  update operations.returns
  set status_code = v_status, outcome_code = v_outcome
  where organization_id = p_organization_id and id = p_return_id;
end;
$$;

create or replace function api.confirm_late_return_arrival(
  p_organization_id uuid,
  p_idempotency_key text,
  p_return_ref text,
  p_late_arrival_reference text,
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
  v_scope constant text := 'CONFIRM_LATE_RETURN_ARRIVAL';
  v_key text := btrim(coalesce(p_idempotency_key, ''));
  v_return_ref text := btrim(coalesce(p_return_ref, ''));
  v_late_ref text := btrim(coalesce(p_late_arrival_reference, ''));
  v_receipt_ref text := btrim(coalesce(p_receipt_ref, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_return operations.returns%rowtype;
  v_command_id uuid := gen_random_uuid();
  v_event_id uuid := gen_random_uuid();
  v_receipt_id uuid := gen_random_uuid();
  v_late_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_actor uuid := auth.uid();
  v_process text;
  v_role text := coalesce(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true));
  v_line record;
  v_item operations.return_items%rowtype;
  v_lost record;
  v_requested bigint;
  v_remaining bigint;
  v_available bigint;
  v_allocate bigint;
  v_allocation_no integer := 0;
  v_event_line_id uuid;
  v_late_line_id uuid;
  v_receipt_line_id uuid;
  v_source_allocation record;
  v_total bigint := 0;
  v_results jsonb := '[]'::jsonb;
  v_response jsonb;
begin
  if p_organization_id is null or v_key = '' or v_return_ref = '' or v_late_ref = '' or v_receipt_ref = '' or p_occurred_at is null
     or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0
     or jsonb_array_length(p_lines) > 200 or jsonb_typeof(v_metadata) is distinct from 'object'
     or length(v_late_ref) > 200 or length(v_receipt_ref) > 200 or (v_note is not null and length(v_note) > 2000) then
    raise exception using errcode = 'P0001', message = 'RETURN_LATE_ARRIVAL_REQUEST_INVALID';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
      or jsonb_typeof(item.value->'returnItemId') is distinct from 'string'
      or (item.value->>'returnItemId') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or jsonb_typeof(item.value->'quantity') is distinct from 'number'
      or (item.value->>'quantity') !~ '^[1-9][0-9]{0,8}$'
  ) then
    raise exception using errcode = 'P0001', message = 'RETURN_LATE_ARRIVAL_LINE_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(p_lines) item(value) group by item.value->>'returnItemId' having count(*) > 1) then
    raise exception using errcode = 'P0001', message = 'RETURN_LATE_ARRIVAL_DUPLICATE_ITEM';
  end if;
  if not exists (select 1 from app.organizations where id = p_organization_id and is_active) then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_NOT_FOUND';
  end if;
  if v_role = 'anon' or (v_role = 'authenticated' and v_actor is null) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;
  if v_actor is null and coalesce(v_role, '') <> 'service_role' and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;
  if v_actor is not null then
    if not app.is_admin() or app.current_organization_id() is distinct from p_organization_id then
      raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
    end if;
  else
    v_process := 'api.confirm_late_return_arrival';
  end if;

  select * into v_return from operations.returns
  where organization_id = p_organization_id and external_return_ref = v_return_ref for update;
  if not found then raise exception using errcode = 'P0001', message = 'RETURN_NOT_FOUND'; end if;

  v_hash := encode(extensions.digest(convert_to(jsonb_build_object('organizationId',p_organization_id,'returnRef',v_return_ref,'lateArrivalReference',v_late_ref,'receiptReference',v_receipt_ref,'occurredAt',p_occurred_at,'lines',p_lines,'note',v_note,'metadata',v_metadata,'schemaVersion',1)::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':' || v_scope || ':' || v_key,0));
  select * into v_existing from inventory.idempotency_commands where organization_id=p_organization_id and scope=v_scope and key=v_key for update;
  if found then
    if v_existing.request_hash <> v_hash then raise exception using errcode='P0001', message='IDEMPOTENCY_KEY_REUSED'; end if;
    if v_existing.status_code='SUCCEEDED' then return v_existing.response_snapshot; end if;
    raise exception using errcode='P0001', message='IDEMPOTENCY_COMMAND_IN_PROGRESS';
  end if;
  if exists(select 1 from operations.return_late_arrivals where organization_id=p_organization_id and late_arrival_reference=v_late_ref)
     or exists(select 1 from operations.return_receipts where organization_id=p_organization_id and receipt_ref=v_receipt_ref) then
    raise exception using errcode='P0001', message='RETURN_LATE_ARRIVAL_ALREADY_POSTED';
  end if;

  for v_line in select item.ordinality::integer line_no,(item.value->>'returnItemId')::uuid return_item_id,(item.value->>'quantity')::bigint quantity from jsonb_array_elements(p_lines) with ordinality item(value,ordinality) order by (item.value->>'returnItemId')::uuid loop
    select * into v_item from operations.return_items where organization_id=p_organization_id and return_id=v_return.id and id=v_line.return_item_id for update;
    if not found then raise exception using errcode='P0001', message='RETURN_ITEM_NOT_FOUND'; end if;
    if v_line.quantity > v_item.lost_qty-v_item.late_arrival_qty then raise exception using errcode='P0001', message='RETURN_LATE_ARRIVAL_EXCEEDS_NET_LOST'; end if;
  end loop;

  insert into inventory.idempotency_commands(id,organization_id,scope,key,request_hash,status_code,started_at,response_snapshot)
  values(v_command_id,p_organization_id,v_scope,v_key,v_hash,'STARTED',v_recorded_at,'{}');
  insert into operations.return_events(id,organization_id,return_id,external_event_ref,event_type_code,occurred_at,recorded_at,actor_user_id,process_name,transaction_id,idempotency_command_id,note,metadata,created_at)
  values(v_event_id,p_organization_id,v_return.id,v_late_ref,'LATE_ARRIVAL',p_occurred_at,v_recorded_at,v_actor,v_process,null,v_command_id,v_note,v_metadata||jsonb_build_object('stockEffectCode','NONE'),v_recorded_at);
  insert into operations.return_receipts(id,organization_id,return_id,event_id,receipt_ref,occurred_at,transaction_id,created_at,stock_effect_code)
  values(v_receipt_id,p_organization_id,v_return.id,v_event_id,v_receipt_ref,p_occurred_at,null,v_recorded_at,'NONE');
  insert into operations.return_late_arrivals(id,organization_id,return_id,receipt_id,event_id,late_arrival_reference,occurred_at,note,actor_user_id,process_name,idempotency_command_id,request_hash,created_at)
  values(v_late_id,p_organization_id,v_return.id,v_receipt_id,v_event_id,v_late_ref,p_occurred_at,v_note,v_actor,v_process,v_command_id,v_hash,v_recorded_at);

  for v_line in select item.ordinality::integer line_no,(item.value->>'returnItemId')::uuid return_item_id,(item.value->>'quantity')::bigint quantity from jsonb_array_elements(p_lines) with ordinality item(value,ordinality) order by (item.value->>'returnItemId')::uuid loop
    v_remaining := v_line.quantity;
    select * into v_item from operations.return_items where organization_id=p_organization_id and return_id=v_return.id and id=v_line.return_item_id;
    for v_lost in
      select lost_line.id, lost_line.quantity, lost_event.occurred_at, lost_line.line_no,
        coalesce(sum(existing.quantity),0)::bigint allocated
      from operations.return_event_lines lost_line
      join operations.return_events lost_event on lost_event.organization_id=lost_line.organization_id and lost_event.id=lost_line.event_id
      left join operations.return_late_arrival_lines existing on existing.organization_id=lost_line.organization_id and existing.lost_event_line_id=lost_line.id
      where lost_line.organization_id=p_organization_id and lost_line.return_item_id=v_item.id and lost_event.event_type_code='LOST'
      group by lost_line.id,lost_line.quantity,lost_event.occurred_at,lost_line.line_no
      having lost_line.quantity-coalesce(sum(existing.quantity),0)>0
      order by lost_event.occurred_at,lost_event.id,lost_line.line_no,lost_line.id
    loop
      exit when v_remaining=0;
      v_available := v_lost.quantity-v_lost.allocated;
      v_allocate := least(v_remaining,v_available);
      v_allocation_no := v_allocation_no+1;
      v_late_line_id := gen_random_uuid();
      insert into operations.return_late_arrival_lines(id,organization_id,late_arrival_id,return_item_id,lost_event_line_id,allocation_no,request_line_no,quantity,product_id,product_sku_snapshot,source_line_ref,created_at)
      values(v_late_line_id,p_organization_id,v_late_id,v_item.id,v_lost.id,v_allocation_no,v_line.line_no,v_allocate,v_item.product_id,v_item.product_sku_snapshot,v_late_ref||':'||v_allocation_no::text,v_recorded_at);
      insert into operations.return_event_lines(organization_id,event_id,return_item_id,line_no,quantity,outcome_code,source_line_ref,created_at)
      values(p_organization_id,v_event_id,v_item.id,v_allocation_no,v_allocate,'RECEIVED',v_late_ref||':'||v_allocation_no::text,v_recorded_at) returning id into v_event_line_id;
      select allocation.id,allocation.batch_id,allocation.batch_code_snapshot,allocation.expiry_date_snapshot
      into v_source_allocation
      from operations.marketplace_ship_allocations allocation
      join operations.marketplace_event_lines marketplace_line on marketplace_line.organization_id=allocation.organization_id and marketplace_line.id=allocation.event_line_id
      where allocation.organization_id=p_organization_id and allocation.product_id=v_item.product_id and marketplace_line.order_item_id=v_item.marketplace_order_item_id
      order by allocation.allocation_no,allocation.id limit 1;
      v_receipt_line_id := gen_random_uuid();
      insert into operations.return_receipt_lines(id,organization_id,receipt_id,event_line_id,return_item_id,marketplace_ship_allocation_id,line_no,product_id,batch_id,quantity_received,batch_identity_verified,product_sku_snapshot,batch_code_snapshot,expiry_date_snapshot,source_line_ref,ledger_entry_id,created_at,stock_effect_code,source_batch_id,source_batch_code_snapshot,source_expiry_date_snapshot,late_arrival_line_id)
      values(v_receipt_line_id,p_organization_id,v_receipt_id,v_event_line_id,v_item.id,v_source_allocation.id,v_allocation_no,v_item.product_id,null,v_allocate,v_source_allocation.id is not null,v_item.product_sku_snapshot,null,null,v_late_ref||':'||v_allocation_no::text,null,v_recorded_at,'NONE',v_source_allocation.batch_id,v_source_allocation.batch_code_snapshot,v_source_allocation.expiry_date_snapshot,v_late_line_id);
      v_remaining:=v_remaining-v_allocate;
      v_total:=v_total+v_allocate;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('lateArrivalLineId',v_late_line_id,'receiptLineId',v_receipt_line_id,'returnItemId',v_item.id,'lostEventLineId',v_lost.id,'quantity',v_allocate,'stockEffectCode','NONE'));
    end loop;
    if v_remaining<>0 then raise exception using errcode='P0001',message='RETURN_LATE_ARRIVAL_EXCEEDS_NET_LOST'; end if;
    update operations.return_items set late_arrival_qty=late_arrival_qty+v_line.quantity,received_qty=received_qty+v_line.quantity where id=v_item.id and organization_id=p_organization_id;
  end loop;

  insert into operations.return_late_arrival_claim_links(organization_id,late_arrival_id,claim_id,claim_status_snapshot,warning_required,detected_at,created_at)
  select p_organization_id,v_late_id,claim.id,claim.status_code,claim.status_code in ('SUBMITTED','RESOLVED'),v_recorded_at,v_recorded_at
  from operations.return_claims claim where claim.organization_id=p_organization_id and claim.return_id=v_return.id;
  perform operations.refresh_return_status(p_organization_id,v_return.id);
  v_response:=jsonb_build_object('lateArrivalId',v_late_id,'receiptId',v_receipt_id,'eventId',v_event_id,'returnId',v_return.id,'returnRef',v_return_ref,'stockEffectCode','NONE','totalQuantity',v_total,'lines',v_results);
  update inventory.idempotency_commands set status_code='SUCCEEDED',completed_at=clock_timestamp(),response_snapshot=v_response,error_code=null where id=v_command_id;
  return v_response;
end;
$$;

create or replace view api.returns with (security_invoker = true) as
select return_header.id return_id, return_header.organization_id, channel.code channel_code,
  return_header.marketplace_order_id, marketplace_order.external_order_ref marketplace_order_ref,
  return_header.external_return_ref, return_header.source_status_code, return_header.status_code,
  return_header.outcome_code, return_header.expected_at, return_header.closed_at,
  return_header.actor_user_id, return_header.process_name, return_header.metadata,
  return_header.created_at, return_header.updated_at,
  coalesce(sum(item.expected_qty),0) expected_qty, coalesce(sum(item.received_qty),0) received_qty,
  coalesce(sum(item.sellable_qty),0) sellable_qty, coalesce(sum(item.damaged_qty),0) damaged_qty,
  coalesce(sum(item.lost_qty),0) lost_qty,
  coalesce(sum(item.expected_qty-item.received_qty-item.lost_qty+item.late_arrival_qty),0) pending_arrival_qty,
  coalesce(sum(item.received_qty-item.sellable_qty-item.damaged_qty),0) pending_inspection_qty,
  coalesce(sum(item.lost_qty),0) gross_lost_qty,
  coalesce(sum(item.late_arrival_qty),0) late_arrival_qty,
  coalesce(sum(item.lost_qty-item.late_arrival_qty),0) net_lost_qty
from operations.returns return_header join catalog.channels channel on channel.id=return_header.channel_id
join operations.marketplace_orders marketplace_order on marketplace_order.organization_id=return_header.organization_id and marketplace_order.id=return_header.marketplace_order_id
left join operations.return_items item on item.organization_id=return_header.organization_id and item.return_id=return_header.id
group by return_header.id,channel.code,marketplace_order.external_order_ref;

create or replace view api.return_items with (security_invoker = true) as
select item.id return_item_id,item.organization_id,item.return_id,item.line_no,item.marketplace_order_item_id,
  marketplace_item.external_item_ref marketplace_item_ref,item.product_id,item.product_sku_snapshot,item.source_line_ref,
  item.expected_qty,item.received_qty,item.sellable_qty,item.damaged_qty,item.lost_qty,
  item.expected_qty-item.received_qty-item.lost_qty+item.late_arrival_qty pending_arrival_qty,
  item.received_qty-item.sellable_qty-item.damaged_qty pending_inspection_qty,item.created_at,item.updated_at,
  item.lost_qty gross_lost_qty,item.late_arrival_qty,item.lost_qty-item.late_arrival_qty net_lost_qty
from operations.return_items item join operations.marketplace_order_items marketplace_item
  on marketplace_item.organization_id=item.organization_id and marketplace_item.id=item.marketplace_order_item_id;

create view api.return_late_arrivals with (security_invoker = true) as
select late.id late_arrival_id,late.organization_id,late.return_id,late.receipt_id,late.event_id,
  late.late_arrival_reference,late.occurred_at,late.note,late.actor_user_id,late.process_name,
  late.idempotency_command_id,late.request_hash,late.schema_version,late.rule_version,late.created_at,
  receipt.receipt_ref,receipt.stock_effect_code
from operations.return_late_arrivals late join operations.return_receipts receipt
  on receipt.organization_id=late.organization_id and receipt.id=late.receipt_id;

create view api.return_late_arrival_lines with (security_invoker = true) as
select line.id late_arrival_line_id,line.organization_id,line.late_arrival_id,line.return_item_id,
  line.lost_event_line_id,line.allocation_no,line.request_line_no,line.quantity,line.product_id,
  line.product_sku_snapshot,line.source_line_ref,line.created_at,receipt_line.id receipt_line_id
from operations.return_late_arrival_lines line left join operations.return_receipt_lines receipt_line
  on receipt_line.organization_id=line.organization_id and receipt_line.late_arrival_line_id=line.id;

create view api.return_late_arrival_claim_links with (security_invoker = true) as
select id late_arrival_claim_link_id,organization_id,late_arrival_id,claim_id,claim_status_snapshot,
  warning_required,detected_at,created_at
from operations.return_late_arrival_claim_links;

create or replace function reconciliation.find_return_late_arrival_consistency_mismatches(p_organization_id uuid)
returns table (late_arrival_id uuid, late_arrival_line_id uuid, issue_code text)
language sql stable security definer
set search_path = pg_catalog, operations, reconciliation
as $$
  select late.id,line.id,
    case when lost_event.event_type_code is distinct from 'LOST' then 'RETURN_LATE_ARRIVAL_LOST_LINK_INVALID'
      when lost_line.return_item_id is distinct from line.return_item_id then 'RETURN_LATE_ARRIVAL_ITEM_LINK_INVALID'
      when receipt_line.id is null or receipt_line.stock_effect_code is distinct from 'NONE' then 'RETURN_LATE_ARRIVAL_RECEIPT_LINK_INVALID'
      when late.receipt_id is distinct from receipt_line.receipt_id then 'RETURN_LATE_ARRIVAL_RECEIPT_HEADER_INVALID'
      when line.quantity > lost_line.quantity then 'RETURN_LATE_ARRIVAL_ALLOCATION_EXCEEDS_LOST'
      else 'RETURN_LATE_ARRIVAL_PROJECTION_MISMATCH' end
  from operations.return_late_arrivals late
  join operations.return_late_arrival_lines line on line.organization_id=late.organization_id and line.late_arrival_id=late.id
  left join operations.return_event_lines lost_line on lost_line.organization_id=line.organization_id and lost_line.id=line.lost_event_line_id
  left join operations.return_events lost_event on lost_event.organization_id=lost_line.organization_id and lost_event.id=lost_line.event_id
  left join operations.return_receipt_lines receipt_line on receipt_line.organization_id=line.organization_id and receipt_line.late_arrival_line_id=line.id
  where late.organization_id=p_organization_id and (
    lost_event.event_type_code is distinct from 'LOST' or lost_line.return_item_id is distinct from line.return_item_id
    or receipt_line.id is null or receipt_line.stock_effect_code is distinct from 'NONE'
    or late.receipt_id is distinct from receipt_line.receipt_id or line.quantity>lost_line.quantity
  )
  union all
  select null,null,'RETURN_LATE_ARRIVAL_PROJECTION_MISMATCH'
  where exists (
    select 1 from operations.return_items item
    where item.organization_id=p_organization_id and item.late_arrival_qty is distinct from coalesce((select sum(line.quantity) from operations.return_late_arrival_lines line where line.organization_id=item.organization_id and line.return_item_id=item.id),0)
  );
$$;

revoke all on function api.confirm_late_return_arrival(uuid,text,text,text,text,timestamptz,jsonb,text,jsonb),
  reconciliation.find_return_late_arrival_consistency_mismatches(uuid) from public, anon;
grant execute on function api.confirm_late_return_arrival(uuid,text,text,text,text,timestamptz,jsonb,text,jsonb) to authenticated, service_role;
revoke all on function reconciliation.find_return_late_arrival_consistency_mismatches(uuid) from authenticated, service_role;
revoke all on api.return_late_arrivals,api.return_late_arrival_lines,api.return_late_arrival_claim_links from anon;
grant select on api.return_late_arrivals,api.return_late_arrival_lines,api.return_late_arrival_claim_links to authenticated,service_role;

commit;
