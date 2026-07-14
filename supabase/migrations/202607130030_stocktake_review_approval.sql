begin;

alter table operations.stocktake_lines
add column review_decision_code text null;

alter table operations.stocktake_lines
add constraint ck_stocktake_lines_review_decision
check (
  review_decision_code is null
  or review_decision_code in (
    'MATCHED',
    'VARIANCE_ACCEPTED',
    'RECOUNT_REQUIRED',
    'EXCEPTION'
  )
);

create table operations.stocktake_approvals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  stocktake_id uuid not null,
  approval_version_no bigint not null,
  approval_hash text not null,
  approved_at timestamptz not null,
  approved_by uuid null references auth.users(id) on delete set null,
  process_name text null,
  stocktake_version_no bigint not null,
  snapshot_ledger_seq bigint not null,
  tolerance_policy_snapshot jsonb not null,
  rule_version text not null,
  line_count bigint not null,
  variance_line_count bigint not null,
  total_variance_qty bigint not null,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  note text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),

  constraint uq_stocktake_approvals_org_stocktake_id
    unique (organization_id, stocktake_id, id),

  constraint fk_stocktake_approvals_stocktake
    foreign key (organization_id, stocktake_id)
    references operations.stocktakes(organization_id, id)
    on delete restrict,

  constraint uq_stocktake_approvals_version
    unique (stocktake_id, approval_version_no),

  constraint uq_stocktake_approvals_hash
    unique (stocktake_id, approval_hash),

  constraint uq_stocktake_approvals_idempotency
    unique (idempotency_command_id),

  constraint ck_stocktake_approvals_version_positive
    check (approval_version_no > 0),

  constraint ck_stocktake_approvals_hash
    check (approval_hash ~ '^[0-9a-f]{64}$'),

  constraint ck_stocktake_approvals_actor_xor_process
    check ((approved_by is not null) <> (process_name is not null)),

  constraint ck_stocktake_approvals_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),

  constraint ck_stocktake_approvals_stocktake_version_positive
    check (stocktake_version_no > 0),

  constraint ck_stocktake_approvals_snapshot_nonnegative
    check (snapshot_ledger_seq >= 0),

  constraint ck_stocktake_approvals_tolerance_object
    check (jsonb_typeof(tolerance_policy_snapshot) = 'object'),

  constraint ck_stocktake_approvals_rule_nonblank
    check (btrim(rule_version) <> ''),

  constraint ck_stocktake_approvals_counts
    check (
      line_count > 0
      and variance_line_count >= 0
      and variance_line_count <= line_count
    ),

  constraint ck_stocktake_approvals_note_length
    check (note is null or length(note) <= 2000),

  constraint ck_stocktake_approvals_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create table operations.stocktake_approval_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  stocktake_id uuid not null,
  approval_id uuid not null,
  stocktake_line_id uuid not null,
  line_no integer not null,
  line_version_no bigint not null,
  review_decision_code text not null,
  final_attempt_id uuid not null,
  final_physical_qty bigint not null,
  expected_qty_at_count bigint not null,
  variance_qty bigint not null,
  reason_code text null,
  review_note text null,
  expected_formula_version text not null,
  count_cutoff_ledger_seq bigint not null,
  created_at timestamptz not null default clock_timestamp(),

  constraint fk_stocktake_approval_lines_approval
    foreign key (organization_id, stocktake_id, approval_id)
    references operations.stocktake_approvals(
      organization_id,
      stocktake_id,
      id
    )
    on delete restrict,

  constraint fk_stocktake_approval_lines_line
    foreign key (organization_id, stocktake_id, stocktake_line_id)
    references operations.stocktake_lines(
      organization_id,
      stocktake_id,
      id
    )
    on delete restrict,

  constraint fk_stocktake_approval_lines_attempt
    foreign key (organization_id, stocktake_line_id, final_attempt_id)
    references operations.stocktake_count_attempts(
      organization_id,
      stocktake_line_id,
      id
    )
    on delete restrict,

  constraint uq_stocktake_approval_lines_line
    unique (approval_id, stocktake_line_id),

  constraint uq_stocktake_approval_lines_number
    unique (approval_id, line_no),

  constraint ck_stocktake_approval_lines_line_positive
    check (line_no > 0),

  constraint ck_stocktake_approval_lines_version_positive
    check (line_version_no > 0),

  constraint ck_stocktake_approval_lines_decision
    check (
      review_decision_code in ('MATCHED', 'VARIANCE_ACCEPTED')
    ),

  constraint ck_stocktake_approval_lines_physical_nonnegative
    check (final_physical_qty >= 0),

  constraint ck_stocktake_approval_lines_variance
    check (variance_qty = final_physical_qty - expected_qty_at_count),

  constraint ck_stocktake_approval_lines_decision_payload
    check (
      (
        review_decision_code = 'MATCHED'
        and variance_qty = 0
        and reason_code is null
      )
      or
      (
        review_decision_code = 'VARIANCE_ACCEPTED'
        and variance_qty <> 0
        and reason_code is not null
        and btrim(reason_code) <> ''
      )
    ),

  constraint ck_stocktake_approval_lines_unknown_note
    check (
      reason_code is null
      or reason_code not in ('UNKNOWN', 'OTHER')
      or (
        review_note is not null
        and btrim(review_note) <> ''
      )
    ),

  constraint ck_stocktake_approval_lines_note_length
    check (review_note is null or length(review_note) <= 2000),

  constraint ck_stocktake_approval_lines_formula_nonblank
    check (btrim(expected_formula_version) <> ''),

  constraint ck_stocktake_approval_lines_cutoff_nonnegative
    check (count_cutoff_ledger_seq >= 0)
);

alter table operations.stocktakes
add column current_approval_id uuid null,
add column approval_version_no bigint null,
add column approved_by uuid null references auth.users(id) on delete set null,
add column approval_process_name text null;

alter table operations.stocktakes
add constraint fk_stocktakes_current_approval
foreign key (organization_id, id, current_approval_id)
references operations.stocktake_approvals(
  organization_id,
  stocktake_id,
  id
)
on delete restrict;

alter table operations.stocktakes
add constraint ck_stocktakes_approval_version_positive
check (approval_version_no is null or approval_version_no > 0);

alter table operations.stocktakes
add constraint ck_stocktakes_approval_actor_pair
check (
  (
    approved_by is null
    and approval_process_name is null
  )
  or
  (
    (approved_by is not null)
    <>
    (approval_process_name is not null)
  )
);

alter table operations.stocktakes
add constraint ck_stocktakes_approval_process_nonblank
check (
  approval_process_name is null
  or btrim(approval_process_name) <> ''
);

alter table operations.stocktakes
add constraint ck_stocktakes_approval_state
check (
  (
    status_code in ('APPROVED', 'POSTING', 'POSTED')
    and current_approval_id is not null
    and approval_version_no is not null
    and approved_at is not null
    and (
      (approved_by is not null)
      <>
      (approval_process_name is not null)
    )
  )
  or
  (
    status_code not in ('APPROVED', 'POSTING', 'POSTED')
    and current_approval_id is null
    and approval_version_no is null
    and approved_at is null
    and approved_by is null
    and approval_process_name is null
  )
);

create index idx_stocktake_approvals_session
on operations.stocktake_approvals (
  organization_id,
  stocktake_id,
  approval_version_no desc,
  id
);

create index idx_stocktake_approval_lines_approval
on operations.stocktake_approval_lines (
  organization_id,
  approval_id,
  line_no,
  id
);

create or replace function operations.stocktake_variance_reason_supported(
  p_reason_code text
)
returns boolean
language sql
immutable
security invoker
set search_path = pg_catalog
as $$
  select upper(btrim(coalesce(p_reason_code, ''))) = any (
    array[
      'UNRECORDED_MANUAL_OUTBOUND',
      'UNRECORDED_INBOUND',
      'RETURN_MISMATCH',
      'WRONG_BATCH_COUNT',
      'WRONG_BUCKET_COUNT',
      'DAMAGE_NOT_RECORDED',
      'EXPIRY_NOT_RECORDED',
      'INITIAL_BALANCE_UNCERTAIN',
      'COUNT_TIMING_DIFFERENCE',
      'DUPLICATE_MOVEMENT',
      'SOURCE_EVENT_FAILURE',
      'PROJECTION_DRIFT',
      'PHYSICAL_LOSS',
      'PHYSICAL_SURPLUS',
      'MASTER_DATA_ERROR',
      'UNKNOWN',
      'OTHER'
    ]::text[]
  );
$$;

revoke all on function operations.stocktake_variance_reason_supported(text)
from public, anon, authenticated;

create or replace function operations.reset_stocktake_review_decision_on_new_count()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, operations
as $$
begin
  if new.final_attempt_id is distinct from old.final_attempt_id
     and new.count_status_code = 'COUNTED' then
    new.review_decision_code := null;
  end if;

  return new;
end;
$$;

revoke all
on function operations.reset_stocktake_review_decision_on_new_count()
from public, anon, authenticated;

create trigger trg_stocktake_lines_reset_review_decision
before update on operations.stocktake_lines
for each row
execute function operations.reset_stocktake_review_decision_on_new_count();

create trigger trg_stocktake_approvals_immutable
before update or delete on operations.stocktake_approvals
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_stocktake_approval_lines_immutable
before update or delete on operations.stocktake_approval_lines
for each row execute function inventory.reject_immutable_mutation();

alter table operations.stocktake_approvals enable row level security;
alter table operations.stocktake_approval_lines enable row level security;

create policy stocktake_approvals_read_current_org
on operations.stocktake_approvals
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stocktake_approval_lines_read_current_org
on operations.stocktake_approval_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all
on operations.stocktake_approvals,
   operations.stocktake_approval_lines
from public, anon, authenticated;

grant select
on operations.stocktake_approvals,
   operations.stocktake_approval_lines
to authenticated, service_role;

create or replace function api.review_stocktake_line(
  p_organization_id uuid,
  p_idempotency_key text,
  p_stocktake_id uuid,
  p_stocktake_line_id uuid,
  p_expected_line_version bigint,
  p_decision_code text,
  p_reason_code text default null,
  p_review_note text default null,
  p_exception_code text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, inventory, operations, extensions
as $$
declare
  v_command_scope constant text := 'REVIEW_STOCKTAKE_LINE';
  v_idempotency_key text;
  v_decision_code text;
  v_reason_code text;
  v_review_note text;
  v_exception_code text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_stocktake operations.stocktakes%rowtype;
  v_line operations.stocktake_lines%rowtype;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_command_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_new_line_version bigint;
  v_new_stocktake_version bigint;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;
  if p_stocktake_id is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_ID_REQUIRED';
  end if;
  if p_stocktake_line_id is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_LINE_ID_REQUIRED';
  end if;
  if p_expected_line_version is null or p_expected_line_version <= 0 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_LINE_VERSION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_decision_code := upper(btrim(coalesce(p_decision_code, '')));
  if v_decision_code not in ('MATCHED', 'VARIANCE_ACCEPTED', 'EXCEPTION') then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_REVIEW_DECISION_REQUIRED';
  end if;

  v_reason_code := nullif(upper(btrim(coalesce(p_reason_code, ''))), '');
  v_review_note := nullif(btrim(coalesce(p_review_note, '')), '');
  v_exception_code := nullif(upper(btrim(coalesce(p_exception_code, ''))), '');

  if v_review_note is not null and length(v_review_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_REVIEW_NOTE_TOO_LONG';
  end if;
  if v_exception_code is not null and length(v_exception_code) > 100 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_EXCEPTION_CODE_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_METADATA_MUST_BE_OBJECT';
  end if;

  if not exists (
    select 1 from app.organizations organization
    where organization.id = p_organization_id and organization.is_active
  ) then
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
  else
    v_process_name := 'api.review_stocktake_line';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'stocktakeId', p_stocktake_id,
          'stocktakeLineId', p_stocktake_line_id,
          'expectedLineVersion', p_expected_line_version,
          'decisionCode', v_decision_code,
          'reasonCode', v_reason_code,
          'reviewNote', v_review_note,
          'exceptionCode', v_exception_code,
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

  select command.* into v_existing
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
  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':STOCKTAKE_LINE:' || p_stocktake_line_id::text,
      0::bigint
    )
  );

  select stocktake.* into v_stocktake
  from operations.stocktakes stocktake
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_NOT_FOUND';
  end if;
  if v_stocktake.status_code <> 'REVIEW' then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_REVIEW_INVALID_STATE';
  end if;

  select line.* into v_line
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
    and line.id = p_stocktake_line_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_LINE_NOT_FOUND';
  end if;
  if v_line.version_no <> p_expected_line_version then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_LINE_VERSION_CONFLICT';
  end if;
  if v_line.count_status_code <> 'COUNTED'
     or v_line.final_attempt_id is null
     or v_line.final_physical_qty is null
     or v_line.expected_qty_at_count is null
     or v_line.variance_qty is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_COUNT_REQUIRED';
  end if;

  if v_decision_code = 'MATCHED' then
    if v_line.variance_qty <> 0
       or v_reason_code is not null
       or v_exception_code is not null then
      raise exception using errcode = 'P0001', message = 'STOCKTAKE_REVIEW_DECISION_INVALID';
    end if;
  elsif v_decision_code = 'VARIANCE_ACCEPTED' then
    if v_line.variance_qty = 0 then
      raise exception using errcode = 'P0001', message = 'STOCKTAKE_REVIEW_DECISION_INVALID';
    end if;
    if v_reason_code is null then
      raise exception using errcode = 'P0001', message = 'STOCKTAKE_REASON_REQUIRED';
    end if;
    if not operations.stocktake_variance_reason_supported(v_reason_code) then
      raise exception using errcode = 'P0001', message = 'STOCKTAKE_REASON_NOT_SUPPORTED';
    end if;
    if v_reason_code in ('UNKNOWN', 'OTHER') and v_review_note is null then
      raise exception using errcode = 'P0001', message = 'STOCKTAKE_REVIEW_NOTE_REQUIRED';
    end if;
    if v_exception_code is not null then
      raise exception using errcode = 'P0001', message = 'STOCKTAKE_REVIEW_DECISION_INVALID';
    end if;
  else
    if v_exception_code is null then
      raise exception using errcode = 'P0001', message = 'STOCKTAKE_EXCEPTION_REQUIRED';
    end if;
    if v_reason_code is not null then
      raise exception using errcode = 'P0001', message = 'STOCKTAKE_REVIEW_DECISION_INVALID';
    end if;
  end if;

  insert into inventory.idempotency_commands (
    id, organization_id, scope, key, request_hash, status_code,
    started_at, completed_at, result_transaction_id, response_snapshot,
    error_code, expires_at
  )
  values (
    v_command_id, p_organization_id, v_command_scope, v_idempotency_key,
    v_request_hash, 'STARTED', v_recorded_at, null, null, '{}'::jsonb,
    null, null
  );

  v_new_line_version := v_line.version_no + 1;
  v_new_stocktake_version := v_stocktake.version_no + 1;

  update operations.stocktake_lines line
  set
    review_status_code = 'REVIEWED',
    review_decision_code = v_decision_code,
    reason_code = case when v_decision_code = 'VARIANCE_ACCEPTED' then v_reason_code else null end,
    review_note = v_review_note,
    exception_code = case when v_decision_code = 'EXCEPTION' then v_exception_code else null end,
    updated_at = v_recorded_at,
    version_no = v_new_line_version
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
    and line.id = p_stocktake_line_id;

  update operations.stocktakes stocktake
  set
    metadata = stocktake.metadata || jsonb_build_object(
      'lastReviewDecisionAt', v_recorded_at,
      'lastReviewDecisionByUserId', v_actor_user_id,
      'lastReviewDecisionByProcessName', v_process_name
    ),
    updated_at = v_recorded_at,
    version_no = v_new_stocktake_version
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id;

  v_response := jsonb_build_object(
    'status', 'REVIEWED',
    'stocktakeId', p_stocktake_id,
    'stocktakeLineId', p_stocktake_line_id,
    'decisionCode', v_decision_code,
    'reasonCode', v_reason_code,
    'reviewNote', v_review_note,
    'exceptionCode', v_exception_code,
    'lineVersion', v_new_line_version,
    'stocktakeVersion', v_new_stocktake_version,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'reviewedAt', v_recorded_at,
    'reviewedByUserId', v_actor_user_id,
    'reviewedByProcessName', v_process_name
  );

  update inventory.idempotency_commands command
  set status_code = 'SUCCEEDED',
      completed_at = clock_timestamp(),
      response_snapshot = v_response,
      error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

create or replace function api.request_stocktake_review_recount(
  p_organization_id uuid,
  p_idempotency_key text,
  p_stocktake_id uuid,
  p_stocktake_line_id uuid,
  p_expected_line_version bigint,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, inventory, operations, extensions
as $$
declare
  v_command_scope constant text := 'REQUEST_STOCKTAKE_REVIEW_RECOUNT';
  v_idempotency_key text;
  v_reason text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_stocktake operations.stocktakes%rowtype;
  v_line operations.stocktake_lines%rowtype;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text := coalesce(
    auth.jwt() ->> 'role',
    current_setting('request.jwt.claim.role', true)
  );
  v_command_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_new_line_version bigint;
  v_new_stocktake_version bigint;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;
  if p_stocktake_id is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_ID_REQUIRED';
  end if;
  if p_stocktake_line_id is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_LINE_ID_REQUIRED';
  end if;
  if p_expected_line_version is null or p_expected_line_version <= 0 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_LINE_VERSION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  if v_reason is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_RECOUNT_REASON_REQUIRED';
  end if;
  if length(v_reason) > 2000 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_RECOUNT_REASON_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_METADATA_MUST_BE_OBJECT';
  end if;

  if not exists (
    select 1 from app.organizations organization
    where organization.id = p_organization_id and organization.is_active
  ) then
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
  else
    v_process_name := 'api.request_stocktake_review_recount';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'stocktakeId', p_stocktake_id,
          'stocktakeLineId', p_stocktake_line_id,
          'expectedLineVersion', p_expected_line_version,
          'reason', v_reason,
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

  select command.* into v_existing
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
  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':STOCKTAKE_LINE:' || p_stocktake_line_id::text,
      0::bigint
    )
  );

  select stocktake.* into v_stocktake
  from operations.stocktakes stocktake
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_NOT_FOUND';
  end if;
  if v_stocktake.status_code <> 'REVIEW' then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_REVIEW_INVALID_STATE';
  end if;

  select line.* into v_line
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
    and line.id = p_stocktake_line_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_LINE_NOT_FOUND';
  end if;
  if v_line.version_no <> p_expected_line_version then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_LINE_VERSION_CONFLICT';
  end if;
  if v_line.count_status_code <> 'COUNTED' or v_line.final_attempt_id is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_COUNT_REQUIRED';
  end if;

  insert into inventory.idempotency_commands (
    id, organization_id, scope, key, request_hash, status_code,
    started_at, completed_at, result_transaction_id, response_snapshot,
    error_code, expires_at
  )
  values (
    v_command_id, p_organization_id, v_command_scope, v_idempotency_key,
    v_request_hash, 'STARTED', v_recorded_at, null, null, '{}'::jsonb,
    null, null
  );

  v_new_line_version := v_line.version_no + 1;
  v_new_stocktake_version := v_stocktake.version_no + 1;

  update operations.stocktake_lines line
  set
    count_status_code = 'RECOUNT_REQUESTED',
    review_status_code = 'PENDING',
    review_decision_code = 'RECOUNT_REQUIRED',
    reason_code = null,
    review_note = v_reason,
    exception_code = null,
    updated_at = v_recorded_at,
    version_no = v_new_line_version
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
    and line.id = p_stocktake_line_id;

  update operations.stocktakes stocktake
  set
    status_code = 'COUNTING',
    counting_completed_at = null,
    approved_at = null,
    current_approval_id = null,
    approval_version_no = null,
    approved_by = null,
    approval_process_name = null,
    metadata = stocktake.metadata || jsonb_build_object(
      'reviewRecountRequestedAt', v_recorded_at,
      'reviewRecountRequestedByUserId', v_actor_user_id,
      'reviewRecountRequestedByProcessName', v_process_name
    ),
    updated_at = v_recorded_at,
    version_no = v_new_stocktake_version
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id;

  v_response := jsonb_build_object(
    'status', 'COUNTING',
    'stocktakeId', p_stocktake_id,
    'stocktakeLineId', p_stocktake_line_id,
    'countStatusCode', 'RECOUNT_REQUESTED',
    'reviewStatusCode', 'PENDING',
    'reviewDecisionCode', 'RECOUNT_REQUIRED',
    'currentAttemptNo', v_line.count_attempt_no,
    'currentCountAttemptId', v_line.final_attempt_id,
    'lineVersion', v_new_line_version,
    'stocktakeVersion', v_new_stocktake_version,
    'reason', v_reason,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'requestedAt', v_recorded_at,
    'requestedByUserId', v_actor_user_id,
    'requestedByProcessName', v_process_name
  );

  update inventory.idempotency_commands command
  set status_code = 'SUCCEEDED',
      completed_at = clock_timestamp(),
      response_snapshot = v_response,
      error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

create or replace function api.approve_stocktake(
  p_organization_id uuid,
  p_idempotency_key text,
  p_stocktake_id uuid,
  p_expected_stocktake_version bigint,
  p_confirmation boolean,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, inventory, operations, extensions
as $$
declare
  v_command_scope constant text := 'APPROVE_STOCKTAKE';
  v_idempotency_key text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_stocktake operations.stocktakes%rowtype;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text := coalesce(
    auth.jwt() ->> 'role',
    current_setting('request.jwt.claim.role', true)
  );
  v_command_id uuid := gen_random_uuid();
  v_approval_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_line_count bigint;
  v_ready_line_count bigint;
  v_variance_line_count bigint;
  v_total_variance_qty bigint;
  v_approval_version bigint;
  v_approval_hash text;
  v_line_snapshot jsonb;
  v_new_stocktake_version bigint;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;
  if p_stocktake_id is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_ID_REQUIRED';
  end if;
  if p_expected_stocktake_version is null or p_expected_stocktake_version <= 0 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_VERSION_REQUIRED';
  end if;
  if not coalesce(p_confirmation, false) then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_APPROVAL_CONFIRMATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');
  if v_note is not null and length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_APPROVAL_NOTE_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_METADATA_MUST_BE_OBJECT';
  end if;

  if not exists (
    select 1 from app.organizations organization
    where organization.id = p_organization_id and organization.is_active
  ) then
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
  else
    v_process_name := 'api.approve_stocktake';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'stocktakeId', p_stocktake_id,
          'expectedStocktakeVersion', p_expected_stocktake_version,
          'confirmation', true,
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
      p_organization_id::text || ':' || v_command_scope || ':' || v_idempotency_key,
      0::bigint
    )
  );

  select command.* into v_existing
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

  select stocktake.* into v_stocktake
  from operations.stocktakes stocktake
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_NOT_FOUND';
  end if;
  if v_stocktake.status_code <> 'REVIEW' then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_REVIEW_INVALID_STATE';
  end if;
  if v_stocktake.version_no <> p_expected_stocktake_version then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_APPROVAL_VERSION_CONFLICT';
  end if;
  if v_stocktake.snapshot_ledger_seq is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_SNAPSHOT_INCOMPLETE';
  end if;

  select
    count(*),
    count(*) filter (
      where line.count_status_code = 'COUNTED'
        and line.final_attempt_id is not null
        and line.review_status_code = 'REVIEWED'
        and line.review_decision_code in ('MATCHED', 'VARIANCE_ACCEPTED')
        and line.exception_code is null
    ),
    count(*) filter (where line.variance_qty <> 0),
    coalesce(sum(line.variance_qty), 0)::bigint
  into
    v_line_count,
    v_ready_line_count,
    v_variance_line_count,
    v_total_variance_qty
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id;

  if v_line_count = 0 or v_ready_line_count <> v_line_count then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_APPROVAL_REQUIRED';
  end if;

  if exists (
    select 1
    from operations.stocktake_lines line
    where line.organization_id = p_organization_id
      and line.stocktake_id = p_stocktake_id
      and (
        (
          line.review_decision_code = 'MATCHED'
          and (line.variance_qty <> 0 or line.reason_code is not null)
        )
        or
        (
          line.review_decision_code = 'VARIANCE_ACCEPTED'
          and (
            line.variance_qty = 0
            or not operations.stocktake_variance_reason_supported(line.reason_code)
            or (
              line.reason_code in ('UNKNOWN', 'OTHER')
              and nullif(btrim(coalesce(line.review_note, '')), '') is null
            )
          )
        )
      )
  ) then
    raise exception using errcode = 'P0001', message = 'STALE_STOCKTAKE_BASIS';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'stocktakeLineId', line.id,
      'lineNo', line.line_no,
      'lineVersion', line.version_no,
      'reviewDecisionCode', line.review_decision_code,
      'finalAttemptId', line.final_attempt_id,
      'physicalQty', line.final_physical_qty,
      'expectedQty', line.expected_qty_at_count,
      'varianceQty', line.variance_qty,
      'reasonCode', line.reason_code,
      'reviewNote', line.review_note,
      'expectedFormulaVersion', line.expected_formula_version,
      'countCutoffLedgerSeq', line.count_cutoff_ledger_seq
    )
    order by line.line_no
  )
  into v_line_snapshot
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id;

  select coalesce(max(approval.approval_version_no), 0) + 1
  into v_approval_version
  from operations.stocktake_approvals approval
  where approval.organization_id = p_organization_id
    and approval.stocktake_id = p_stocktake_id;

  v_approval_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'stocktakeId', p_stocktake_id,
          'approvalVersion', v_approval_version,
          'stocktakeVersion', v_stocktake.version_no,
          'snapshotLedgerSeq', v_stocktake.snapshot_ledger_seq,
          'tolerancePolicy', v_stocktake.tolerance_policy_snapshot,
          'ruleVersion', v_stocktake.rule_version,
          'lines', v_line_snapshot,
          'schemaVersion', 1
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  insert into inventory.idempotency_commands (
    id, organization_id, scope, key, request_hash, status_code,
    started_at, completed_at, result_transaction_id, response_snapshot,
    error_code, expires_at
  )
  values (
    v_command_id, p_organization_id, v_command_scope, v_idempotency_key,
    v_request_hash, 'STARTED', v_recorded_at, null, null, '{}'::jsonb,
    null, null
  );

  insert into operations.stocktake_approvals (
    id, organization_id, stocktake_id, approval_version_no, approval_hash,
    approved_at, approved_by, process_name, stocktake_version_no,
    snapshot_ledger_seq, tolerance_policy_snapshot, rule_version,
    line_count, variance_line_count, total_variance_qty,
    idempotency_command_id, note, metadata, created_at
  )
  values (
    v_approval_id, p_organization_id, p_stocktake_id, v_approval_version,
    v_approval_hash, v_recorded_at, v_actor_user_id, v_process_name,
    v_stocktake.version_no, v_stocktake.snapshot_ledger_seq,
    v_stocktake.tolerance_policy_snapshot, v_stocktake.rule_version,
    v_line_count, v_variance_line_count, v_total_variance_qty,
    v_command_id, v_note, v_metadata, v_recorded_at
  );

  insert into operations.stocktake_approval_lines (
    organization_id, stocktake_id, approval_id, stocktake_line_id,
    line_no, line_version_no, review_decision_code, final_attempt_id,
    final_physical_qty, expected_qty_at_count, variance_qty, reason_code,
    review_note, expected_formula_version, count_cutoff_ledger_seq,
    created_at
  )
  select
    line.organization_id, line.stocktake_id, v_approval_id, line.id,
    line.line_no, line.version_no, line.review_decision_code,
    line.final_attempt_id, line.final_physical_qty,
    line.expected_qty_at_count, line.variance_qty, line.reason_code,
    line.review_note, line.expected_formula_version,
    line.count_cutoff_ledger_seq, v_recorded_at
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
  order by line.line_no;

  v_new_stocktake_version := v_stocktake.version_no + 1;

  update operations.stocktakes stocktake
  set
    status_code = 'APPROVED',
    approved_at = v_recorded_at,
    current_approval_id = v_approval_id,
    approval_version_no = v_approval_version,
    approved_by = v_actor_user_id,
    approval_process_name = v_process_name,
    metadata = stocktake.metadata || jsonb_build_object(
      'approvalHash', v_approval_hash,
      'approvalMetadata', v_metadata
    ),
    updated_at = v_recorded_at,
    version_no = v_new_stocktake_version
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id;

  v_response := jsonb_build_object(
    'status', 'APPROVED',
    'stocktakeId', p_stocktake_id,
    'stocktakeNo', v_stocktake.stocktake_no,
    'approvalId', v_approval_id,
    'approvalVersion', v_approval_version,
    'approvalHash', v_approval_hash,
    'lineCount', v_line_count,
    'varianceLineCount', v_variance_line_count,
    'totalVarianceQty', v_total_variance_qty,
    'stocktakeVersion', v_new_stocktake_version,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'approvedAt', v_recorded_at,
    'approvedByUserId', v_actor_user_id,
    'approvedByProcessName', v_process_name
  );

  update inventory.idempotency_commands command
  set status_code = 'SUCCEEDED',
      completed_at = clock_timestamp(),
      response_snapshot = v_response,
      error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

grant usage on schema api to authenticated, service_role;

revoke all on function api.review_stocktake_line(
  uuid, text, uuid, uuid, bigint, text, text, text, text, jsonb
) from public, anon;
grant execute on function api.review_stocktake_line(
  uuid, text, uuid, uuid, bigint, text, text, text, text, jsonb
) to authenticated, service_role;

revoke all on function api.request_stocktake_review_recount(
  uuid, text, uuid, uuid, bigint, text, jsonb
) from public, anon;
grant execute on function api.request_stocktake_review_recount(
  uuid, text, uuid, uuid, bigint, text, jsonb
) to authenticated, service_role;

revoke all on function api.approve_stocktake(
  uuid, text, uuid, bigint, boolean, text, jsonb
) from public, anon;
grant execute on function api.approve_stocktake(
  uuid, text, uuid, bigint, boolean, text, jsonb
) to authenticated, service_role;

create or replace view api.stocktake_approvals
with (security_invoker = true, security_barrier = true)
as
select
  approval.id as approval_id,
  approval.organization_id,
  approval.stocktake_id,
  approval.approval_version_no,
  approval.approval_hash,
  approval.approved_at,
  approval.approved_by,
  approval.process_name,
  approval.stocktake_version_no,
  approval.snapshot_ledger_seq,
  approval.tolerance_policy_snapshot,
  approval.rule_version,
  approval.line_count,
  approval.variance_line_count,
  approval.total_variance_qty,
  approval.note,
  approval.metadata,
  approval.created_at
from operations.stocktake_approvals approval;

create or replace view api.stocktake_approval_lines
with (security_invoker = true, security_barrier = true)
as
select
  approval_line.id as approval_line_id,
  approval_line.organization_id,
  approval_line.stocktake_id,
  approval_line.approval_id,
  approval_line.stocktake_line_id,
  approval_line.line_no,
  approval_line.line_version_no,
  approval_line.review_decision_code,
  approval_line.final_attempt_id,
  approval_line.final_physical_qty,
  approval_line.expected_qty_at_count,
  approval_line.variance_qty,
  approval_line.reason_code,
  approval_line.review_note,
  approval_line.expected_formula_version,
  approval_line.count_cutoff_ledger_seq,
  approval_line.created_at
from operations.stocktake_approval_lines approval_line;

revoke all on api.stocktake_approvals, api.stocktake_approval_lines
from public, anon;

grant select on api.stocktake_approvals, api.stocktake_approval_lines
to authenticated, service_role;

alter default privileges in schema operations
revoke all on tables from anon, authenticated;

commit;
