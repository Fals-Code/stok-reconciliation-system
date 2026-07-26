begin;

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
      group by lost_line.id,lost_line.quantity,lost_event.occurred_at,lost_event.id,lost_line.line_no
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

revoke all on function api.confirm_late_return_arrival(uuid,text,text,text,text,timestamptz,jsonb,text,jsonb) from public, anon;
grant execute on function api.confirm_late_return_arrival(uuid,text,text,text,text,timestamptz,jsonb,text,jsonb) to authenticated, service_role;

commit;
