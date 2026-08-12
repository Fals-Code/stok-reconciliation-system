begin;

create table operations.stocktake_cancellations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  stocktake_id uuid not null,
  status_before_code text not null,
  status_after_code text not null default 'CANCELLED',
  reason text not null,
  cancelled_at timestamptz not null,
  cancelled_by uuid null references auth.users(id) on delete set null,
  process_name text null,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),

  constraint fk_stocktake_cancellations_stocktake
    foreign key (organization_id, stocktake_id)
    references operations.stocktakes(organization_id, id)
    on delete restrict,

  constraint uq_stocktake_cancellations_session unique (stocktake_id),
  constraint uq_stocktake_cancellations_command
    unique (idempotency_command_id),

  constraint ck_stocktake_cancellations_before
    check (status_before_code in ('DRAFT', 'READY', 'COUNTING', 'REVIEW')),
  constraint ck_stocktake_cancellations_after
    check (status_after_code = 'CANCELLED'),
  constraint ck_stocktake_cancellations_reason
    check (btrim(reason) <> '' and length(reason) <= 2000),
  constraint ck_stocktake_cancellations_actor
    check ((cancelled_by is not null) <> (process_name is not null)),
  constraint ck_stocktake_cancellations_process
    check (process_name is null or btrim(process_name) <> ''),
  constraint ck_stocktake_cancellations_metadata
    check (jsonb_typeof(metadata) = 'object')
);

create index idx_stocktake_cancellations_org_time
on operations.stocktake_cancellations (
  organization_id,
  cancelled_at desc,
  stocktake_id
);

create trigger trg_stocktake_cancellations_immutable
before update or delete on operations.stocktake_cancellations
for each row execute function inventory.reject_immutable_mutation();

alter table operations.stocktake_cancellations enable row level security;

create policy stocktake_cancellations_read_current_org
on operations.stocktake_cancellations
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on operations.stocktake_cancellations
from public, anon, authenticated;

grant select on operations.stocktake_cancellations
to authenticated, service_role;

create or replace view api.stocktake_cancellations
with (security_invoker = true)
as
select
  cancellation.id as cancellation_id,
  cancellation.organization_id,
  cancellation.stocktake_id,
  cancellation.status_before_code,
  cancellation.status_after_code,
  cancellation.reason,
  cancellation.cancelled_at,
  cancellation.cancelled_by,
  cancellation.process_name,
  cancellation.idempotency_command_id,
  cancellation.metadata,
  cancellation.created_at
from operations.stocktake_cancellations cancellation;

revoke all on api.stocktake_cancellations
from public, anon;

grant select on api.stocktake_cancellations
to authenticated, service_role;

create or replace function api.cancel_stocktake(
  p_organization_id uuid,
  p_idempotency_key text,
  p_stocktake_id uuid,
  p_reason text,
  p_confirmation boolean,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, inventory, operations, extensions
as $$
declare
  v_command_scope constant text := 'CANCEL_STOCKTAKE';
  v_idempotency_key text;
  v_reason text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_stocktake operations.stocktakes%rowtype;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_command_id uuid := gen_random_uuid();
  v_cancellation_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_stocktake_id is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_ID_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_reason := btrim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_CANCEL_REASON_REQUIRED';
  end if;
  if length(v_reason) > 2000 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_CANCEL_REASON_TOO_LONG';
  end if;
  if coalesce(p_confirmation, false) is not true then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_CANCEL_CONFIRMATION_REQUIRED';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_METADATA_MUST_BE_OBJECT';
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
  else
    v_process_name := 'api.cancel_stocktake';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'stocktakeId', p_stocktake_id,
          'reason', v_reason,
          'confirmation', true,
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
      p_organization_id::text || ':' || v_command_scope || ':' || v_idempotency_key,
      0::bigint
    )
  );

  select command.*
  into v_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id
    and command.scope = v_command_scope
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
      p_organization_id::text || ':STOCKTAKE:' || p_stocktake_id::text,
      0::bigint
    )
  );

  select stocktake.*
  into v_stocktake
  from operations.stocktakes stocktake
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_NOT_FOUND';
  end if;

  if v_stocktake.status_code not in ('DRAFT', 'READY', 'COUNTING', 'REVIEW') then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_CANCEL_INVALID_STATE';
  end if;

  if v_stocktake.stock_transaction_id is not null
     or v_stocktake.reconciliation_run_id is not null
     or exists (
       select 1
       from operations.stocktake_postings posting
       where posting.organization_id = p_organization_id
         and posting.stocktake_id = p_stocktake_id
     )
     or exists (
       select 1
       from inventory.stock_transactions transaction
       where transaction.organization_id = p_organization_id
         and transaction.source_type_code = 'STOCKTAKE'
         and transaction.source_id = p_stocktake_id
     ) then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_ALREADY_POSTED';
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
  )
  values (
    v_command_id,
    p_organization_id,
    v_command_scope,
    v_idempotency_key,
    v_request_hash,
    'STARTED',
    v_recorded_at,
    '{}'::jsonb
  );

  insert into operations.stocktake_cancellations (
    id,
    organization_id,
    stocktake_id,
    status_before_code,
    reason,
    cancelled_at,
    cancelled_by,
    process_name,
    idempotency_command_id,
    metadata
  )
  values (
    v_cancellation_id,
    p_organization_id,
    p_stocktake_id,
    v_stocktake.status_code,
    v_reason,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    v_command_id,
    v_metadata
  );

  update operations.stocktakes stocktake
  set
    status_code = 'CANCELLED',
    metadata =
      stocktake.metadata
      || jsonb_build_object(
        'cancelledAt', v_recorded_at,
        'cancelledByUserId', v_actor_user_id,
        'cancelledByProcessName', v_process_name,
        'cancelReason', v_reason,
        'cancelMetadata', v_metadata
      ),
    updated_at = v_recorded_at,
    version_no = stocktake.version_no + 1
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id;

  v_response := jsonb_build_object(
    'status', 'CANCELLED',
    'stocktakeId', p_stocktake_id,
    'stocktakeNo', v_stocktake.stocktake_no,
    'statusBefore', v_stocktake.status_code,
    'cancellationId', v_cancellation_id,
    'reason', v_reason,
    'cancelledAt', v_recorded_at,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'versionNo', v_stocktake.version_no + 1
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

revoke all
on function api.cancel_stocktake(uuid, text, uuid, text, boolean, jsonb)
from public, anon;

grant execute
on function api.cancel_stocktake(uuid, text, uuid, text, boolean, jsonb)
to authenticated, service_role;

commit;
