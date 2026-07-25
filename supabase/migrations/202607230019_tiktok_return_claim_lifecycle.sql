begin;

create table operations.return_claims (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  return_id uuid not null,
  claim_type_code text not null,
  status_code text not null default 'NOT_STARTED',
  resolution_code text,
  external_claim_ref text,
  claim_basis_code text not null,
  claim_basis_at timestamptz,
  window_days_snapshot integer not null,
  timezone_snapshot text not null,
  deadline_source_code text not null,
  deadline_at timestamptz,
  policy_version_snapshot text not null,
  schema_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  submitted_at timestamptz,
  resolved_at timestamptz,
  cancelled_at timestamptz,
  actor_user_id uuid references auth.users(id) on delete set null,
  process_name text,
  idempotency_command_id uuid not null references inventory.idempotency_commands(id) on delete restrict,
  request_hash text not null,
  constraint uq_return_claims_org_id unique (organization_id, id),
  constraint uq_return_claims_command unique (idempotency_command_id),
  constraint fk_return_claims_return foreign key (organization_id, return_id) references operations.returns(organization_id, id) on delete restrict,
  constraint ck_return_claim_type check (claim_type_code in ('LOST_RETURN','PARTIAL_RETURN_MISSING','DAMAGED_IN_TRANSIT','OTHER_RETURN_EXCEPTION')),
  constraint ck_return_claim_status check (status_code in ('NOT_STARTED','DUE_SOON','SUBMITTED','RESOLVED','EXPIRED','EXCEPTION','CANCELLED')),
  constraint ck_return_claim_resolution check (resolution_code is null or resolution_code in ('APPROVED','REJECTED','PARTIALLY_APPROVED','NO_ACTION','OTHER')),
  constraint ck_return_claim_tiktok_policy check ((claim_basis_code = 'RETURN_CREATED_AT' and window_days_snapshot = 40 and timezone_snapshot = 'Asia/Jakarta' and deadline_source_code = 'INTERNAL_RETURN_CREATED_AT' and deadline_at = claim_basis_at + interval '40 days') or (claim_basis_at is null and deadline_at is null)),
  constraint ck_return_claim_ref check (external_claim_ref is null or (btrim(external_claim_ref) <> '' and length(external_claim_ref) <= 200)),
  constraint ck_return_claim_hash check (request_hash ~ '^[0-9a-f]{64}$'),
  constraint ck_return_claim_actor check ((actor_user_id is not null) <> (process_name is not null)),
  constraint ck_return_claim_process check (process_name is null or btrim(process_name) <> ''),
  constraint ck_return_claim_terminal_times check ((status_code <> 'SUBMITTED' or submitted_at is not null) and (status_code <> 'RESOLVED' or resolved_at is not null) and (status_code <> 'CANCELLED' or cancelled_at is not null))
);

create unique index uidx_return_claim_external_ref on operations.return_claims(organization_id, external_claim_ref) where external_claim_ref is not null;
create index idx_return_claim_deadline on operations.return_claims(organization_id, status_code, deadline_at);

create table operations.return_claim_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  claim_id uuid not null,
  return_item_id uuid not null,
  quantity bigint not null,
  eligible_lost_qty_snapshot bigint not null,
  product_id uuid not null,
  product_sku_snapshot text not null,
  source_line_ref_snapshot text not null,
  canonical_components_snapshot jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_return_claim_items_org_id unique (organization_id, id),
  constraint fk_return_claim_items_claim foreign key (organization_id, claim_id) references operations.return_claims(organization_id, id) on delete restrict,
  constraint fk_return_claim_items_item foreign key (organization_id, return_item_id) references operations.return_items(organization_id, id) on delete restrict,
  constraint ck_return_claim_items_qty check (quantity > 0 and eligible_lost_qty_snapshot >= quantity),
  constraint ck_return_claim_items_components check (jsonb_typeof(canonical_components_snapshot) = 'array' and jsonb_array_length(canonical_components_snapshot) > 0),
  constraint uq_return_claim_items_item unique (claim_id, return_item_id)
);

create table operations.return_claim_events (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null, claim_id uuid not null,
  event_type_code text not null, occurred_at timestamptz not null, recorded_at timestamptz not null default clock_timestamp(),
  actor_user_id uuid references auth.users(id) on delete set null, process_name text,
  idempotency_command_id uuid not null references inventory.idempotency_commands(id) on delete restrict,
  note text, snapshot jsonb not null default '{}'::jsonb,
  constraint uq_return_claim_events_org_id unique (organization_id,id), constraint uq_return_claim_events_command unique (idempotency_command_id),
  constraint fk_return_claim_events_claim foreign key (organization_id,claim_id) references operations.return_claims(organization_id,id) on delete restrict,
  constraint ck_return_claim_event check (event_type_code in ('CREATED','SUBMITTED','RESOLVED','CANCELLED','EXPIRED','EXCEPTION')),
  constraint ck_return_claim_event_actor check ((actor_user_id is not null) <> (process_name is not null)),
  constraint ck_return_claim_event_snapshot check (jsonb_typeof(snapshot) = 'object')
);

create function operations.reject_return_claim_history_mutation() returns trigger language plpgsql set search_path = pg_catalog as $$ begin raise exception using errcode = 'P0001', message = 'RETURN_CLAIM_HISTORY_IMMUTABLE'; end $$;
create function operations.protect_return_claim_snapshot() returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if row(new.organization_id,new.return_id,new.claim_type_code,new.claim_basis_code,new.claim_basis_at,new.window_days_snapshot,new.timezone_snapshot,new.deadline_source_code,new.deadline_at,new.policy_version_snapshot,new.schema_version,new.created_at,new.actor_user_id,new.process_name,new.idempotency_command_id,new.request_hash)
     is distinct from row(old.organization_id,old.return_id,old.claim_type_code,old.claim_basis_code,old.claim_basis_at,old.window_days_snapshot,old.timezone_snapshot,old.deadline_source_code,old.deadline_at,old.policy_version_snapshot,old.schema_version,old.created_at,old.actor_user_id,old.process_name,old.idempotency_command_id,old.request_hash) then
    raise exception using errcode = 'P0001', message = 'RETURN_CLAIM_SNAPSHOT_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger trg_return_claim_events_immutable before update or delete on operations.return_claim_events for each row execute function operations.reject_return_claim_history_mutation();
create trigger trg_return_claim_items_immutable before update or delete on operations.return_claim_items for each row execute function operations.reject_return_claim_history_mutation();
create trigger trg_return_claims_snapshot_immutable before update on operations.return_claims for each row execute function operations.protect_return_claim_snapshot();

alter table operations.return_claims enable row level security;
alter table operations.return_claim_items enable row level security;
alter table operations.return_claim_events enable row level security;
create policy return_claims_read_current_org on operations.return_claims for select using (organization_id = app.current_organization_id());
create policy return_claim_items_read_current_org on operations.return_claim_items for select using (organization_id = app.current_organization_id());
create policy return_claim_events_read_current_org on operations.return_claim_events for select using (organization_id = app.current_organization_id());
revoke all on operations.return_claims, operations.return_claim_items, operations.return_claim_events from public, anon, authenticated;

create function api.create_tiktok_return_claim(p_organization_id uuid, p_idempotency_key text, p_return_id uuid, p_claim_type_code text, p_items jsonb, p_occurred_at timestamptz default clock_timestamp()) returns jsonb language plpgsql security definer set search_path = pg_catalog, auth, app, operations, inventory, catalog, extensions as $$
declare v_key text := btrim(coalesce(p_idempotency_key,'')); v_hash text; v_existing inventory.idempotency_commands%rowtype; v_return operations.returns%rowtype; v_claim uuid := gen_random_uuid(); v_cmd uuid := gen_random_uuid(); v_actor uuid := auth.uid(); v_item record; v_response jsonb; v_item_count integer; v_distinct_count integer;
begin
  if p_organization_id is null or p_return_id is null or v_key = '' or length(v_key) > 200 or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception using errcode='P0001',message='RETURN_CLAIM_REQUEST_INVALID'; end if;
  if v_actor is null or not app.is_admin() or app.current_organization_id() is distinct from p_organization_id then raise exception using errcode='42501',message='ORGANIZATION_ACCESS_DENIED'; end if;
  if p_claim_type_code not in ('LOST_RETURN','PARTIAL_RETURN_MISSING','DAMAGED_IN_TRANSIT','OTHER_RETURN_EXCEPTION') then raise exception using errcode='P0001',message='RETURN_CLAIM_TYPE_INVALID'; end if;
  select r.* into v_return from operations.returns r join catalog.channels channel on channel.id=r.channel_id where r.organization_id=p_organization_id and r.id=p_return_id and upper(channel.code)='TIKTOK_SHOP' for update;
  if not found then raise exception using errcode='P0001',message='TIKTOK_RETURN_NOT_FOUND'; end if;
  select count(*), count(distinct value->>'returnItemId') into v_item_count,v_distinct_count from jsonb_array_elements(p_items);
  if v_item_count <> v_distinct_count then raise exception using errcode='P0001',message='RETURN_CLAIM_DUPLICATE_ITEM'; end if;
  v_hash := encode(extensions.digest(convert_to(jsonb_build_object('returnId',p_return_id,'claimTypeCode',p_claim_type_code,'items',p_items)::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':CREATE_TIKTOK_RETURN_CLAIM:'||v_key,0));
  select * into v_existing from inventory.idempotency_commands where organization_id=p_organization_id and scope='CREATE_TIKTOK_RETURN_CLAIM' and key=v_key for update;
  if found then if v_existing.request_hash <> v_hash then raise exception using errcode='P0001',message='IDEMPOTENCY_KEY_REUSED'; end if; return v_existing.response_snapshot; end if;
  insert into inventory.idempotency_commands(id,organization_id,scope,key,request_hash,status_code) values(v_cmd,p_organization_id,'CREATE_TIKTOK_RETURN_CLAIM',v_key,v_hash,'STARTED');
  insert into operations.return_claims(id,organization_id,return_id,claim_type_code,claim_basis_code,claim_basis_at,window_days_snapshot,timezone_snapshot,deadline_source_code,deadline_at,policy_version_snapshot,actor_user_id,idempotency_command_id,request_hash) values(v_claim,p_organization_id,p_return_id,p_claim_type_code,'RETURN_CREATED_AT',v_return.created_at,40,'Asia/Jakarta','INTERNAL_RETURN_CREATED_AT',v_return.created_at+interval '40 days','TIKTOK_RETURN_CREATED_AT_V1',v_actor,v_cmd,v_hash);
  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item.value) <> 'object' or coalesce(v_item.value->>'returnItemId','') = '' or coalesce(v_item.value->>'quantity','') !~ '^[1-9][0-9]*$' then raise exception using errcode='P0001',message='RETURN_CLAIM_ITEM_INVALID'; end if;
    insert into operations.return_claim_items(organization_id,claim_id,return_item_id,quantity,eligible_lost_qty_snapshot,product_id,product_sku_snapshot,source_line_ref_snapshot,canonical_components_snapshot)
    select p_organization_id,v_claim,i.id,(v_item.value->>'quantity')::bigint,i.lost_qty,i.product_id,i.product_sku_snapshot,i.source_line_ref,jsonb_build_array(jsonb_build_object('returnItemId',i.id,'productId',i.product_id,'productSku',i.product_sku_snapshot,'sourceLineRef',i.source_line_ref,'historicalRecipeVersion','RETURN_ITEM_CANONICAL_V1'))
    from operations.return_items i where i.organization_id=p_organization_id and i.return_id=p_return_id and i.id=(v_item.value->>'returnItemId')::uuid and (v_item.value->>'quantity')::bigint <= i.lost_qty;
    if not found then raise exception using errcode='P0001',message='RETURN_CLAIM_ITEM_NOT_ELIGIBLE'; end if;
  end loop;
  insert into operations.return_claim_events(organization_id,claim_id,event_type_code,occurred_at,actor_user_id,idempotency_command_id,snapshot) values(p_organization_id,v_claim,'CREATED',p_occurred_at,v_actor,v_cmd,jsonb_build_object('stockEffectCode','NONE','claimBasisCode','RETURN_CREATED_AT','deadlineSourceCode','INTERNAL_RETURN_CREATED_AT'));
  v_response := jsonb_build_object('claimId',v_claim,'deadlineAt',v_return.created_at+interval '40 days','stockEffectCode','NONE'); update inventory.idempotency_commands set status_code='SUCCEEDED',completed_at=clock_timestamp(),response_snapshot=v_response where id=v_cmd; return v_response;
end $$;

create function api.transition_tiktok_return_claim(p_organization_id uuid,p_idempotency_key text,p_claim_id uuid,p_action text,p_external_claim_ref text default null,p_resolution_code text default null,p_reason text default null,p_occurred_at timestamptz default clock_timestamp()) returns jsonb language plpgsql security definer set search_path = pg_catalog, auth, app, operations, inventory, extensions as $$
declare v_claim operations.return_claims%rowtype; v_action text:=upper(btrim(p_action)); v_key text:=btrim(coalesce(p_idempotency_key,'')); v_hash text; v_existing inventory.idempotency_commands%rowtype; v_cmd uuid:=gen_random_uuid(); v_actor uuid:=auth.uid(); v_status text; v_event text; v_response jsonb;
begin
  if p_organization_id is null or p_claim_id is null or v_key='' or p_occurred_at is null then raise exception using errcode='P0001',message='RETURN_CLAIM_REQUEST_INVALID'; end if;
  if v_actor is null or not app.is_admin() or app.current_organization_id() is distinct from p_organization_id then raise exception using errcode='42501',message='ORGANIZATION_ACCESS_DENIED'; end if;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('claimId',p_claim_id,'action',v_action,'externalRef',nullif(btrim(coalesce(p_external_claim_ref,'')),''),'resolution',p_resolution_code,'reason',nullif(btrim(coalesce(p_reason,'')),''),'occurredAt',p_occurred_at)::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':'||v_action||':'||v_key,0));
  select * into v_existing from inventory.idempotency_commands where organization_id=p_organization_id and scope='TIKTOK_RETURN_CLAIM_'||v_action and key=v_key for update;
  if found then if v_existing.request_hash<>v_hash then raise exception using errcode='P0001',message='IDEMPOTENCY_KEY_REUSED'; end if; return v_existing.response_snapshot; end if;
  select * into v_claim from operations.return_claims where organization_id=p_organization_id and id=p_claim_id for update; if not found then raise exception using errcode='P0001',message='RETURN_CLAIM_NOT_FOUND'; end if;
  if v_action='SUBMIT' then if v_claim.status_code not in ('NOT_STARTED','DUE_SOON','EXPIRED') or btrim(coalesce(p_external_claim_ref,''))='' then raise exception using errcode='P0001',message='RETURN_CLAIM_SUBMIT_INVALID'; end if; v_status:='SUBMITTED';v_event:='SUBMITTED';
  elsif v_action='RESOLVE' then if v_claim.status_code not in ('SUBMITTED','EXPIRED') or p_resolution_code not in ('APPROVED','REJECTED','PARTIALLY_APPROVED','NO_ACTION','OTHER') then raise exception using errcode='P0001',message='RETURN_CLAIM_RESOLVE_INVALID'; end if; v_status:='RESOLVED';v_event:='RESOLVED';
  elsif v_action='CANCEL' then if v_claim.status_code not in ('NOT_STARTED','DUE_SOON','EXCEPTION') or btrim(coalesce(p_reason,''))='' then raise exception using errcode='P0001',message='RETURN_CLAIM_CANCEL_INVALID'; end if; v_status:='CANCELLED';v_event:='CANCELLED';
  elsif v_action='EVALUATE' then if v_claim.status_code in ('SUBMITTED','RESOLVED','CANCELLED') then return jsonb_build_object('claimId',p_claim_id,'status',v_claim.status_code,'stockEffectCode','NONE'); end if; if p_occurred_at>v_claim.deadline_at then v_status:='EXPIRED';v_event:='EXPIRED'; elsif p_occurred_at>=v_claim.deadline_at-interval '14 days' then v_status:='DUE_SOON';v_event:='EXCEPTION'; else v_status:='NOT_STARTED';v_event:='EXCEPTION'; end if; if v_status=v_claim.status_code then return jsonb_build_object('claimId',p_claim_id,'status',v_status,'stockEffectCode','NONE'); end if;
  else raise exception using errcode='P0001',message='RETURN_CLAIM_ACTION_INVALID'; end if;
  insert into inventory.idempotency_commands(id,organization_id,scope,key,request_hash,status_code) values(v_cmd,p_organization_id,'TIKTOK_RETURN_CLAIM_'||v_action,v_key,v_hash,'STARTED');
  update operations.return_claims set status_code=v_status,external_claim_ref=case when v_action='SUBMIT' then btrim(p_external_claim_ref) else external_claim_ref end,resolution_code=case when v_action='RESOLVE' then p_resolution_code else resolution_code end,submitted_at=case when v_action='SUBMIT' then p_occurred_at else submitted_at end,resolved_at=case when v_action='RESOLVE' then p_occurred_at else resolved_at end,cancelled_at=case when v_action='CANCEL' then p_occurred_at else cancelled_at end where id=p_claim_id and organization_id=p_organization_id;
  insert into operations.return_claim_events(organization_id,claim_id,event_type_code,occurred_at,actor_user_id,idempotency_command_id,note,snapshot) values(p_organization_id,p_claim_id,v_event,p_occurred_at,v_actor,v_cmd,p_reason,jsonb_build_object('stockEffectCode','NONE','status',v_status));
  v_response:=jsonb_build_object('claimId',p_claim_id,'status',v_status,'stockEffectCode','NONE'); update inventory.idempotency_commands set status_code='SUCCEEDED',completed_at=clock_timestamp(),response_snapshot=v_response where id=v_cmd; return v_response;
end $$;

create function api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamptz default clock_timestamp()) returns jsonb language sql security definer set search_path = pg_catalog, api as $$ select api.transition_tiktok_return_claim($1,$2,$3,'SUBMIT',$4,null,null,$5) $$;
create function api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamptz default clock_timestamp()) returns jsonb language sql security definer set search_path = pg_catalog, api as $$ select api.transition_tiktok_return_claim($1,$2,$3,'RESOLVE',null,$4,null,$5) $$;
create function api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamptz default clock_timestamp()) returns jsonb language sql security definer set search_path = pg_catalog, api as $$ select api.transition_tiktok_return_claim($1,$2,$3,'CANCEL',null,null,$4,$5) $$;
create function api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamptz default clock_timestamp()) returns jsonb language sql security definer set search_path = pg_catalog, api as $$ select api.transition_tiktok_return_claim($1,$2,$3,'EVALUATE',null,null,null,$4) $$;

create view api.return_claim_master with (security_invoker = true) as select c.*, 'NONE'::text stock_effect_code, case when clock_timestamp()>c.deadline_at then 'OVERDUE' when clock_timestamp()>=c.deadline_at then 'DUE_TODAY' when clock_timestamp()>=c.deadline_at-interval '1 day' then 'D1' when clock_timestamp()>=c.deadline_at-interval '3 days' then 'D3' when clock_timestamp()>=c.deadline_at-interval '7 days' then 'D7' when clock_timestamp()>=c.deadline_at-interval '14 days' then 'D14' else 'NOT_DUE' end derived_deadline_stage from operations.return_claims c where c.organization_id=app.current_organization_id();
create view api.return_claim_items with (security_invoker = true) as select i.* from operations.return_claim_items i where i.organization_id=app.current_organization_id();
create view api.return_claim_events with (security_invoker = true) as select e.* from operations.return_claim_events e where e.organization_id=app.current_organization_id();
revoke all on function operations.reject_return_claim_history_mutation(),operations.protect_return_claim_snapshot(),api.create_tiktok_return_claim(uuid,text,uuid,text,jsonb,timestamptz),api.transition_tiktok_return_claim(uuid,text,uuid,text,text,text,text,timestamptz),api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamptz),api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamptz),api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamptz),api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamptz) from public, anon, authenticated;
grant execute on function api.create_tiktok_return_claim(uuid,text,uuid,text,jsonb,timestamptz),api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamptz),api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamptz),api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamptz),api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamptz) to authenticated, service_role;
revoke all on api.return_claim_master,api.return_claim_items,api.return_claim_events from public,anon;
grant select on api.return_claim_master,api.return_claim_items,api.return_claim_events to authenticated,service_role;
commit;
