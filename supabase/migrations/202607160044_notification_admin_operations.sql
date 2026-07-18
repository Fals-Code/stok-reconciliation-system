begin;

create table notification.admin_operation_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  operation_code text not null,
  idempotency_key text not null,
  request_hash text not null,
  target_outbox_event_id uuid not null,
  evaluation_family_code text null,
  reason text not null,
  actor_user_id uuid not null
    references auth.users(id) on delete restrict,
  correlation_id uuid not null,
  requested_at timestamptz not null,
  response_snapshot jsonb not null,
  created_at timestamptz not null default clock_timestamp(),

  constraint uq_notification_admin_operation_org_id
    unique (organization_id, id),

  constraint fk_notification_admin_operation_organization
    foreign key (organization_id)
    references app.organizations(id)
    on delete restrict,

  constraint fk_notification_admin_operation_outbox
    foreign key (organization_id, target_outbox_event_id)
    references notification.outbox_events(organization_id, id)
    on delete restrict,

  constraint uq_notification_admin_operation_idempotency
    unique (
      organization_id,
      operation_code,
      idempotency_key
    ),

  constraint ck_notification_admin_operation_code
    check (
      operation_code in (
        'RETRY_OUTBOX_EVENT',
        'REQUEST_EVALUATION'
      )
    ),

  constraint ck_notification_admin_operation_key
    check (
      btrim(idempotency_key) <> ''
      and length(idempotency_key) <= 200
    ),

  constraint ck_notification_admin_operation_hash
    check (request_hash ~ '^[0-9a-f]{64}$'),

  constraint ck_notification_admin_operation_family
    check (
      (
        operation_code = 'RETRY_OUTBOX_EVENT'
        and evaluation_family_code is null
      )
      or (
        operation_code = 'REQUEST_EVALUATION'
        and evaluation_family_code in (
          'EXPIRY',
          'RETURN_INSPECTION',
          'RECONCILIATION',
          'STOCKTAKE'
        )
      )
    ),

  constraint ck_notification_admin_operation_reason
    check (
      btrim(reason) <> ''
      and length(reason) <= 2000
    ),

  constraint ck_notification_admin_operation_response
    check (jsonb_typeof(response_snapshot) = 'object')
);

create index idx_notification_admin_operation_event
on notification.admin_operation_commands (
  organization_id,
  target_outbox_event_id,
  requested_at desc
);

create index idx_notification_admin_operation_recent
on notification.admin_operation_commands (
  organization_id,
  requested_at desc,
  operation_code
);

alter table notification.outbox_events
add column retry_budget_started_at_attempt integer
not null default 0;

alter table notification.outbox_events
add constraint ck_notification_outbox_retry_budget
check (
  retry_budget_started_at_attempt >= 0
  and retry_budget_started_at_attempt <= attempt_count
);

create or replace function notification.recover_stale_outbox_events(
  p_now timestamptz default clock_timestamp(),
  p_lock_timeout interval default interval '5 minutes',
  p_max_attempts integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification
as $$
declare
  v_exhausted_retryable_count integer := 0;
  v_stale_retryable_count integer := 0;
  v_stale_final_count integer := 0;
begin
  if p_now is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_PROCESS_TIME_REQUIRED';
  end if;

  if p_lock_timeout is null
     or p_lock_timeout <= interval '0 seconds'
     or p_lock_timeout > interval '1 day' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_LOCK_TIMEOUT_INVALID';
  end if;

  if p_max_attempts < 1 or p_max_attempts > 20 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_MAX_ATTEMPTS_INVALID';
  end if;

  with finalized as (
    update notification.outbox_events event_row
    set
      status_code = 'FAILED_FINAL',
      locked_at = null,
      locked_by = null,
      completed_at = p_now,
      last_error_code = 'OUTBOX_RETRY_EXHAUSTED',
      last_error_detail = jsonb_build_object(
        'finalizedAt', p_now,
        'attemptCount', event_row.attempt_count,
        'retryBudgetStartedAtAttempt',
          event_row.retry_budget_started_at_attempt,
        'retryCycleAttemptCount',
          event_row.attempt_count
          - event_row.retry_budget_started_at_attempt,
        'reason', 'RETRY_BUDGET_EXHAUSTED'
      )
    where event_row.status_code = 'FAILED_RETRYABLE'
      and (
        event_row.attempt_count
        - event_row.retry_budget_started_at_attempt
      ) >= p_max_attempts
    returning 1
  )
  select count(*)::integer
  into v_exhausted_retryable_count
  from finalized;

  with finalized as (
    update notification.outbox_events event_row
    set
      status_code = 'FAILED_FINAL',
      locked_at = null,
      locked_by = null,
      completed_at = p_now,
      last_error_code = 'OUTBOX_STALE_LOCK_EXHAUSTED',
      last_error_detail = jsonb_build_object(
        'recoveredAt', p_now,
        'previousLockedAt', event_row.locked_at,
        'previousLockedBy', event_row.locked_by,
        'attemptCount', event_row.attempt_count,
        'retryBudgetStartedAtAttempt',
          event_row.retry_budget_started_at_attempt,
        'retryCycleAttemptCount',
          event_row.attempt_count
          - event_row.retry_budget_started_at_attempt,
        'reason', 'STALE_PROCESSING_LOCK'
      )
    where event_row.status_code = 'PROCESSING'
      and event_row.locked_at <= p_now - p_lock_timeout
      and (
        event_row.attempt_count
        - event_row.retry_budget_started_at_attempt
      ) >= p_max_attempts
    returning 1
  )
  select count(*)::integer
  into v_stale_final_count
  from finalized;

  with recovered as (
    update notification.outbox_events event_row
    set
      status_code = 'FAILED_RETRYABLE',
      available_at = greatest(event_row.occurred_at, p_now),
      locked_at = null,
      locked_by = null,
      completed_at = null,
      last_error_code = 'OUTBOX_STALE_LOCK_RECOVERED',
      last_error_detail = jsonb_build_object(
        'recoveredAt', p_now,
        'previousLockedAt', event_row.locked_at,
        'previousLockedBy', event_row.locked_by,
        'attemptCount', event_row.attempt_count,
        'retryBudgetStartedAtAttempt',
          event_row.retry_budget_started_at_attempt,
        'retryCycleAttemptCount',
          event_row.attempt_count
          - event_row.retry_budget_started_at_attempt,
        'reason', 'STALE_PROCESSING_LOCK'
      )
    where event_row.status_code = 'PROCESSING'
      and event_row.locked_at <= p_now - p_lock_timeout
      and (
        event_row.attempt_count
        - event_row.retry_budget_started_at_attempt
      ) < p_max_attempts
    returning 1
  )
  select count(*)::integer
  into v_stale_retryable_count
  from recovered;

  return jsonb_build_object(
    'exhaustedRetryableCount',
    v_exhausted_retryable_count,
    'staleRetryableCount',
    v_stale_retryable_count,
    'staleFinalCount',
    v_stale_final_count
  );
end;
$$;

create or replace function notification.claim_outbox_events(
  p_worker_id text,
  p_limit integer default 10,
  p_now timestamptz default clock_timestamp(),
  p_max_attempts integer default 5
)
returns setof notification.outbox_events
language plpgsql
security definer
set search_path = pg_catalog, notification
as $$
declare
  v_worker_id text :=
    nullif(btrim(coalesce(p_worker_id, '')), '');
begin
  if v_worker_id is null or length(v_worker_id) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_WORKER_ID_INVALID';
  end if;

  if p_limit < 1 or p_limit > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_CLAIM_LIMIT_INVALID';
  end if;

  if p_now is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_PROCESS_TIME_REQUIRED';
  end if;

  if p_max_attempts < 1 or p_max_attempts > 20 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_MAX_ATTEMPTS_INVALID';
  end if;

  return query
  with candidates as (
    select event_row.id
    from notification.outbox_events event_row
    where event_row.status_code in (
        'PENDING',
        'FAILED_RETRYABLE'
      )
      and event_row.available_at <= p_now
      and (
        event_row.attempt_count
        - event_row.retry_budget_started_at_attempt
      ) < p_max_attempts
    order by
      event_row.available_at,
      event_row.created_at,
      event_row.id
    for update skip locked
    limit p_limit
  )
  update notification.outbox_events event_row
  set
    status_code = 'PROCESSING',
    attempt_count = event_row.attempt_count + 1,
    locked_at = p_now,
    locked_by = v_worker_id,
    completed_at = null
  from candidates
  where event_row.id = candidates.id
  returning event_row.*;
end;
$$;

create or replace function notification.fail_outbox_event(
  p_outbox_event_id uuid,
  p_worker_id text,
  p_error_code text,
  p_error_detail jsonb,
  p_failed_at timestamptz default clock_timestamp(),
  p_retryable boolean default true,
  p_max_attempts integer default 5,
  p_base_retry_seconds integer default 60,
  p_max_retry_seconds integer default 3600
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification
as $$
declare
  v_worker_id text :=
    nullif(btrim(coalesce(p_worker_id, '')), '');
  v_error_code text :=
    upper(btrim(coalesce(p_error_code, '')));
  v_event notification.outbox_events%rowtype;
  v_status_code text;
  v_retry_seconds integer;
  v_available_at timestamptz;
  v_retry_cycle_attempt_count integer;
begin
  if p_outbox_event_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_EVENT_ID_REQUIRED';
  end if;

  if v_worker_id is null or length(v_worker_id) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_WORKER_ID_INVALID';
  end if;

  if v_error_code = '' or length(v_error_code) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_ERROR_CODE_INVALID';
  end if;

  if p_error_detail is null
     or jsonb_typeof(p_error_detail) <> 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_ERROR_DETAIL_INVALID';
  end if;

  if p_failed_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_FAILURE_TIME_REQUIRED';
  end if;

  if p_max_attempts < 1 or p_max_attempts > 20 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_MAX_ATTEMPTS_INVALID';
  end if;

  if p_base_retry_seconds < 1
     or p_max_retry_seconds < p_base_retry_seconds
     or p_max_retry_seconds > 86400 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_RETRY_POLICY_INVALID';
  end if;

  select event_row.*
  into v_event
  from notification.outbox_events event_row
  where event_row.id = p_outbox_event_id
  for update;

  if v_event.id is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_EVENT_NOT_FOUND';
  end if;

  if v_event.status_code <> 'PROCESSING'
     or v_event.locked_by <> v_worker_id then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_LOCK_OWNERSHIP_INVALID';
  end if;

  if p_failed_at < v_event.locked_at then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_FAILURE_TIME_INVALID';
  end if;

  v_retry_cycle_attempt_count :=
    v_event.attempt_count
    - v_event.retry_budget_started_at_attempt;

  if p_retryable
     and v_retry_cycle_attempt_count < p_max_attempts then
    v_status_code := 'FAILED_RETRYABLE';

    v_retry_seconds :=
      least(
        p_max_retry_seconds::numeric,
        p_base_retry_seconds::numeric
          * power(
              2::numeric,
              greatest(
                v_retry_cycle_attempt_count - 1,
                0
              )::numeric
            )
      )::integer;

    v_available_at :=
      greatest(
        v_event.occurred_at,
        p_failed_at
          + make_interval(secs => v_retry_seconds)
      );
  else
    v_status_code := 'FAILED_FINAL';
    v_retry_seconds := null;
    v_available_at := v_event.available_at;
  end if;

  update notification.outbox_events event_row
  set
    status_code = v_status_code,
    available_at = v_available_at,
    locked_at = null,
    locked_by = null,
    completed_at =
      case
        when v_status_code = 'FAILED_FINAL'
          then p_failed_at
        else null
      end,
    last_error_code = v_error_code,
    last_error_detail =
      p_error_detail
      || jsonb_build_object(
        'failedAt', p_failed_at,
        'attemptCount', v_event.attempt_count,
        'retryBudgetStartedAtAttempt',
          v_event.retry_budget_started_at_attempt,
        'retryCycleAttemptCount',
          v_retry_cycle_attempt_count,
        'retryable', p_retryable,
        'retryDelaySeconds', v_retry_seconds,
        'nextAvailableAt',
          case
            when v_status_code = 'FAILED_RETRYABLE'
              then v_available_at
            else null
          end
      )
  where event_row.id = v_event.id;

  return jsonb_build_object(
    'action', v_status_code,
    'outboxEventId', v_event.id,
    'status', v_status_code,
    'attemptCount', v_event.attempt_count,
    'retryBudgetStartedAtAttempt',
      v_event.retry_budget_started_at_attempt,
    'retryCycleAttemptCount',
      v_retry_cycle_attempt_count,
    'retryDelaySeconds', v_retry_seconds,
    'availableAt',
      case
        when v_status_code = 'FAILED_RETRYABLE'
          then v_available_at
        else null
      end,
    'completedAt',
      case
        when v_status_code = 'FAILED_FINAL'
          then p_failed_at
        else null
      end
  );
end;
$$;

create or replace function notification.retry_outbox_event(
  p_organization_id uuid,
  p_outbox_event_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_requested_at timestamptz,
  p_correlation_id uuid,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  notification,
  app,
  extensions
as $$
declare
  v_reason text :=
    nullif(btrim(coalesce(p_reason, '')), '');
  v_idempotency_key text :=
    nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_request_hash text;
  v_existing notification.admin_operation_commands%rowtype;
  v_event notification.outbox_events%rowtype;
  v_operation_id uuid := gen_random_uuid();
  v_response jsonb;
  v_available_at timestamptz;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if p_outbox_event_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_EVENT_ID_REQUIRED';
  end if;

  if v_reason is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_RETRY_REASON_REQUIRED';
  end if;

  if length(v_reason) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_RETRY_REASON_TOO_LONG';
  end if;

  if v_idempotency_key is null then
    raise exception using
      errcode = 'P0001',
      message =
        'NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_REQUIRED';
  end if;

  if length(v_idempotency_key) > 200 then
    raise exception using
      errcode = 'P0001',
      message =
        'NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_TOO_LONG';
  end if;

  if p_requested_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_RETRY_REQUESTED_AT_REQUIRED';
  end if;

  if p_correlation_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_CORRELATION_ID_REQUIRED';
  end if;

  if p_actor_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_REQUIRED';
  end if;

  if not exists (
    select 1
    from app.user_profiles profile
    join app.organizations organization
      on organization.id = profile.organization_id
    where profile.user_id = p_actor_user_id
      and profile.organization_id = p_organization_id
      and profile.role_code = 'ADMIN'
      and profile.is_active
      and organization.is_active
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_NOT_AUTHORIZED';
  end if;

  v_request_hash :=
    encode(
      extensions.digest(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'operationCode', 'RETRY_OUTBOX_EVENT',
          'outboxEventId', p_outbox_event_id,
          'reason', v_reason,
          'actorUserId', p_actor_user_id
        )::text,
        'sha256'
      ),
      'hex'
    );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
      || ':NOTIFICATION_ADMIN_OPERATION:RETRY_OUTBOX_EVENT:'
      || v_idempotency_key,
      0::bigint
    )
  );

  select command.*
  into v_existing
  from notification.admin_operation_commands command
  where command.organization_id = p_organization_id
    and command.operation_code = 'RETRY_OUTBOX_EVENT'
    and command.idempotency_key = v_idempotency_key
  for update;

  if v_existing.id is not null then
    if v_existing.request_hash <> v_request_hash then
      raise exception using
        errcode = 'P0001',
        message =
          'NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_CONFLICT';
    end if;

    return
      v_existing.response_snapshot
      || jsonb_build_object(
        'action', 'REPLAYED',
        'originalAction',
          v_existing.response_snapshot ->> 'action'
      );
  end if;

  select event_row.*
  into v_event
  from notification.outbox_events event_row
  where event_row.organization_id = p_organization_id
    and event_row.id = p_outbox_event_id
  for update;

  if v_event.id is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_EVENT_NOT_FOUND';
  end if;

  if v_event.status_code not in (
    'FAILED_RETRYABLE',
    'FAILED_FINAL'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_RETRY_STATUS_INVALID';
  end if;

  v_available_at :=
    greatest(v_event.occurred_at, p_requested_at);

  update notification.outbox_events event_row
  set
    status_code = 'FAILED_RETRYABLE',
    retry_budget_started_at_attempt =
      v_event.attempt_count,
    available_at = v_available_at,
    locked_at = null,
    locked_by = null,
    completed_at = null
  where event_row.organization_id = p_organization_id
    and event_row.id = p_outbox_event_id;

  v_response :=
    jsonb_build_object(
      'action', 'RETRY_REQUESTED',
      'adminOperationId', v_operation_id,
      'outboxEventId', v_event.id,
      'eventTypeCode', v_event.event_type_code,
      'previousStatusCode', v_event.status_code,
      'statusCode', 'FAILED_RETRYABLE',
      'attemptCount', v_event.attempt_count,
      'retryBudgetStartedAtAttempt',
        v_event.attempt_count,
      'retryCycleAttemptCount', 0,
      'availableAt', v_available_at,
      'requestedAt', p_requested_at,
      'requestedByUserId', p_actor_user_id,
      'reason', v_reason,
      'correlationId', p_correlation_id
    );

  insert into notification.admin_operation_commands (
    id,
    organization_id,
    operation_code,
    idempotency_key,
    request_hash,
    target_outbox_event_id,
    evaluation_family_code,
    reason,
    actor_user_id,
    correlation_id,
    requested_at,
    response_snapshot,
    created_at
  )
  values (
    v_operation_id,
    p_organization_id,
    'RETRY_OUTBOX_EVENT',
    v_idempotency_key,
    v_request_hash,
    v_event.id,
    null,
    v_reason,
    p_actor_user_id,
    p_correlation_id,
    p_requested_at,
    v_response,
    clock_timestamp()
  );

  return v_response;
end;
$$;

create or replace function notification.request_manual_evaluation(
  p_organization_id uuid,
  p_evaluation_family_code text,
  p_reason text,
  p_idempotency_key text,
  p_requested_at timestamptz,
  p_correlation_id uuid,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  notification,
  app,
  extensions
as $$
declare
  v_evaluation_family_code text :=
    upper(btrim(coalesce(p_evaluation_family_code, '')));
  v_reason text :=
    nullif(btrim(coalesce(p_reason, '')), '');
  v_idempotency_key text :=
    nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_event_type_code text;
  v_source_event_key text;
  v_request_hash text;
  v_existing notification.admin_operation_commands%rowtype;
  v_enqueue_result jsonb;
  v_outbox_event_id uuid;
  v_operation_id uuid := gen_random_uuid();
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if v_evaluation_family_code not in (
    'EXPIRY',
    'RETURN_INSPECTION',
    'RECONCILIATION',
    'STOCKTAKE'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVALUATION_FAMILY_INVALID';
  end if;

  if v_reason is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVALUATION_REASON_REQUIRED';
  end if;

  if length(v_reason) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVALUATION_REASON_TOO_LONG';
  end if;

  if v_idempotency_key is null then
    raise exception using
      errcode = 'P0001',
      message =
        'NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_REQUIRED';
  end if;

  if length(v_idempotency_key) > 200 then
    raise exception using
      errcode = 'P0001',
      message =
        'NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_TOO_LONG';
  end if;

  if p_requested_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVALUATION_REQUESTED_AT_REQUIRED';
  end if;

  if p_correlation_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_CORRELATION_ID_REQUIRED';
  end if;

  if p_actor_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_REQUIRED';
  end if;

  if not exists (
    select 1
    from app.user_profiles profile
    join app.organizations organization
      on organization.id = profile.organization_id
    where profile.user_id = p_actor_user_id
      and profile.organization_id = p_organization_id
      and profile.role_code = 'ADMIN'
      and profile.is_active
      and organization.is_active
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_NOT_AUTHORIZED';
  end if;

  v_event_type_code :=
    case v_evaluation_family_code
      when 'EXPIRY'
        then 'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED'
      when 'RETURN_INSPECTION'
        then
          'NOTIFICATION_RETURN_INSPECTION_EVALUATION_REQUESTED'
      when 'RECONCILIATION'
        then 'NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED'
      when 'STOCKTAKE'
        then 'NOTIFICATION_STOCKTAKE_EVALUATION_REQUESTED'
    end;

  v_request_hash :=
    encode(
      extensions.digest(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'operationCode', 'REQUEST_EVALUATION',
          'evaluationFamilyCode',
            v_evaluation_family_code,
          'reason', v_reason,
          'actorUserId', p_actor_user_id
        )::text,
        'sha256'
      ),
      'hex'
    );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
      || ':NOTIFICATION_ADMIN_OPERATION:REQUEST_EVALUATION:'
      || v_idempotency_key,
      0::bigint
    )
  );

  select command.*
  into v_existing
  from notification.admin_operation_commands command
  where command.organization_id = p_organization_id
    and command.operation_code = 'REQUEST_EVALUATION'
    and command.idempotency_key = v_idempotency_key
  for update;

  if v_existing.id is not null then
    if v_existing.request_hash <> v_request_hash then
      raise exception using
        errcode = 'P0001',
        message =
          'NOTIFICATION_ADMIN_OPERATION_IDEMPOTENCY_CONFLICT';
    end if;

    return
      v_existing.response_snapshot
      || jsonb_build_object(
        'action', 'REPLAYED',
        'originalAction',
          v_existing.response_snapshot ->> 'action'
      );
  end if;

  v_source_event_key :=
    'admin-evaluation:'
    || lower(v_evaluation_family_code)
    || ':'
    || v_idempotency_key;

  v_enqueue_result :=
    notification.enqueue_outbox_event(
      p_organization_id => p_organization_id,
      p_event_type_code => v_event_type_code,
      p_source_event_key => v_source_event_key,
      p_entity_type_code => 'ORGANIZATION',
      p_entity_id => p_organization_id,
      p_occurred_at => p_requested_at,
      p_payload => jsonb_build_object(
        'schemaVersion', 1,
        'requestType', 'ADMIN_MANUAL_EVALUATION',
        'evaluationFamilyCode',
          v_evaluation_family_code,
        'reason', v_reason,
        'requestedAt', p_requested_at,
        'requestedByUserId', p_actor_user_id
      ),
      p_correlation_id => p_correlation_id,
      p_actor_user_id => p_actor_user_id,
      p_process_name => null
    );

  if v_enqueue_result ->> 'action' not in (
    'CREATED',
    'REPLAYED'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVALUATION_ENQUEUE_FAILED';
  end if;

  begin
    v_outbox_event_id :=
      nullif(
        v_enqueue_result ->> 'outboxEventId',
        ''
      )::uuid;
  exception
    when others then
      raise exception using
        errcode = 'P0001',
        message = 'NOTIFICATION_EVALUATION_EVENT_ID_INVALID';
  end;

  if v_outbox_event_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVALUATION_EVENT_ID_MISSING';
  end if;

  v_response :=
    jsonb_build_object(
      'action', 'EVALUATION_REQUESTED',
      'adminOperationId', v_operation_id,
      'outboxEventId', v_outbox_event_id,
      'eventTypeCode', v_event_type_code,
      'evaluationFamilyCode',
        v_evaluation_family_code,
      'statusCode', 'PENDING',
      'requestedAt', p_requested_at,
      'requestedByUserId', p_actor_user_id,
      'reason', v_reason,
      'correlationId', p_correlation_id,
      'enqueueAction', v_enqueue_result ->> 'action'
    );

  insert into notification.admin_operation_commands (
    id,
    organization_id,
    operation_code,
    idempotency_key,
    request_hash,
    target_outbox_event_id,
    evaluation_family_code,
    reason,
    actor_user_id,
    correlation_id,
    requested_at,
    response_snapshot,
    created_at
  )
  values (
    v_operation_id,
    p_organization_id,
    'REQUEST_EVALUATION',
    v_idempotency_key,
    v_request_hash,
    v_outbox_event_id,
    v_evaluation_family_code,
    v_reason,
    p_actor_user_id,
    p_correlation_id,
    p_requested_at,
    v_response,
    clock_timestamp()
  );

  return v_response;
end;
$$;

create or replace function notification.get_operations_summary(
  p_organization_id uuid,
  p_user_id uuid,
  p_as_of timestamptz,
  p_stale_lock_timeout interval default interval '5 minutes'
)
returns jsonb
language plpgsql
security definer
stable
set search_path =
  pg_catalog,
  notification,
  app
as $$
declare
  v_outbox jsonb;
  v_rule_runs jsonb;
  v_notifications jsonb;
  v_admin_operations jsonb;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if p_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_USER_REQUIRED';
  end if;

  if p_as_of is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_SUMMARY_TIME_REQUIRED';
  end if;

  if p_stale_lock_timeout is null
     or p_stale_lock_timeout <= interval '0 seconds'
     or p_stale_lock_timeout > interval '1 day' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_LOCK_TIMEOUT_INVALID';
  end if;

  if not exists (
    select 1
    from app.user_profiles profile
    join app.organizations organization
      on organization.id = profile.organization_id
    where profile.user_id = p_user_id
      and profile.organization_id = p_organization_id
      and profile.role_code = 'ADMIN'
      and profile.is_active
      and organization.is_active
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_NOT_AUTHORIZED';
  end if;

  select jsonb_build_object(
    'pendingCount',
      count(*) filter (
        where event_row.status_code = 'PENDING'
      ),
    'processingCount',
      count(*) filter (
        where event_row.status_code = 'PROCESSING'
      ),
    'failedRetryableCount',
      count(*) filter (
        where event_row.status_code = 'FAILED_RETRYABLE'
      ),
    'failedFinalCount',
      count(*) filter (
        where event_row.status_code = 'FAILED_FINAL'
      ),
    'completedCount',
      count(*) filter (
        where event_row.status_code = 'COMPLETED'
      ),
    'actionableCount',
      count(*) filter (
        where event_row.status_code in (
          'PENDING',
          'FAILED_RETRYABLE',
          'FAILED_FINAL'
        )
      ),
    'staleProcessingCount',
      count(*) filter (
        where event_row.status_code = 'PROCESSING'
          and event_row.locked_at
              <= p_as_of - p_stale_lock_timeout
      ),
    'oldestActionableAt',
      min(event_row.available_at) filter (
        where event_row.status_code in (
          'PENDING',
          'FAILED_RETRYABLE',
          'FAILED_FINAL'
        )
      )
  )
  into v_outbox
  from notification.outbox_events event_row
  where event_row.organization_id = p_organization_id;

  select jsonb_build_object(
    'startedCount',
      count(*) filter (
        where run.status_code = 'STARTED'
      ),
    'succeededLast24Hours',
      count(*) filter (
        where run.status_code = 'SUCCEEDED'
          and run.completed_at
              >= p_as_of - interval '24 hours'
      ),
    'partiallyFailedLast24Hours',
      count(*) filter (
        where run.status_code = 'PARTIALLY_FAILED'
          and run.completed_at
              >= p_as_of - interval '24 hours'
      ),
    'failedLast24Hours',
      count(*) filter (
        where run.status_code = 'FAILED'
          and run.completed_at
              >= p_as_of - interval '24 hours'
      )
  )
  into v_rule_runs
  from notification.rule_runs run
  where run.organization_id = p_organization_id;

  select jsonb_build_object(
    'openCount',
      count(*) filter (
        where notification_row.lifecycle_status_code = 'OPEN'
      ),
    'acknowledgedCount',
      count(*) filter (
        where notification_row.lifecycle_status_code =
              'ACKNOWLEDGED'
      ),
    'criticalActiveCount',
      count(*) filter (
        where notification_row.lifecycle_status_code in (
          'OPEN',
          'ACKNOWLEDGED'
        )
          and notification_row.severity_code = 'CRITICAL'
      ),
    'highActiveCount',
      count(*) filter (
        where notification_row.lifecycle_status_code in (
          'OPEN',
          'ACKNOWLEDGED'
        )
          and notification_row.severity_code = 'HIGH'
      ),
    'unreadCount',
      count(*) filter (
        where notification_row.lifecycle_status_code in (
          'OPEN',
          'ACKNOWLEDGED'
        )
          and coalesce(
                user_state.read_state_code,
                'UNREAD'
              ) = 'UNREAD'
      )
  )
  into v_notifications
  from notification.notifications notification_row
  left join notification.user_states user_state
    on user_state.organization_id =
       notification_row.organization_id
   and user_state.notification_id =
       notification_row.id
   and user_state.user_id = p_user_id
  where notification_row.organization_id =
        p_organization_id;

  select jsonb_build_object(
    'retryRequestsLast24Hours',
      count(*) filter (
        where command.operation_code =
              'RETRY_OUTBOX_EVENT'
          and command.requested_at
              >= p_as_of - interval '24 hours'
      ),
    'evaluationRequestsLast24Hours',
      count(*) filter (
        where command.operation_code =
              'REQUEST_EVALUATION'
          and command.requested_at
              >= p_as_of - interval '24 hours'
      ),
    'latestRequestedAt',
      max(command.requested_at)
  )
  into v_admin_operations
  from notification.admin_operation_commands command
  where command.organization_id = p_organization_id;

  return jsonb_build_object(
    'organizationId', p_organization_id,
    'userId', p_user_id,
    'generatedAt', p_as_of,
    'staleLockTimeoutSeconds',
      extract(
        epoch from p_stale_lock_timeout
      )::integer,
    'outbox', v_outbox,
    'ruleRuns', v_rule_runs,
    'notifications', v_notifications,
    'adminOperations', v_admin_operations
  );
end;
$$;

create or replace function api.retry_notification_outbox_event(
  p_outbox_event_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_correlation_id uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  notification
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_organization_id uuid;
begin
  if v_actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'AUTHENTICATION_REQUIRED';
  end if;

  v_organization_id := app.current_organization_id();

  if v_organization_id is null or not app.is_admin() then
    raise exception using
      errcode = '42501',
      message = 'ADMIN_ACCESS_REQUIRED';
  end if;

  return notification.retry_outbox_event(
    p_organization_id => v_organization_id,
    p_outbox_event_id => p_outbox_event_id,
    p_reason => p_reason,
    p_idempotency_key => p_idempotency_key,
    p_requested_at => clock_timestamp(),
    p_correlation_id => p_correlation_id,
    p_actor_user_id => v_actor_user_id
  );
end;
$$;

create or replace function api.run_notification_evaluation(
  p_evaluation_family_code text,
  p_reason text,
  p_idempotency_key text,
  p_correlation_id uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  notification
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_organization_id uuid;
begin
  if v_actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'AUTHENTICATION_REQUIRED';
  end if;

  v_organization_id := app.current_organization_id();

  if v_organization_id is null or not app.is_admin() then
    raise exception using
      errcode = '42501',
      message = 'ADMIN_ACCESS_REQUIRED';
  end if;

  return notification.request_manual_evaluation(
    p_organization_id => v_organization_id,
    p_evaluation_family_code =>
      p_evaluation_family_code,
    p_reason => p_reason,
    p_idempotency_key => p_idempotency_key,
    p_requested_at => clock_timestamp(),
    p_correlation_id => p_correlation_id,
    p_actor_user_id => v_actor_user_id
  );
end;
$$;

create or replace function api.get_notification_operations_summary()
returns jsonb
language plpgsql
security definer
stable
set search_path =
  pg_catalog,
  auth,
  app,
  notification
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_organization_id uuid;
begin
  if v_actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'AUTHENTICATION_REQUIRED';
  end if;

  v_organization_id := app.current_organization_id();

  if v_organization_id is null or not app.is_admin() then
    raise exception using
      errcode = '42501',
      message = 'ADMIN_ACCESS_REQUIRED';
  end if;

  return notification.get_operations_summary(
    p_organization_id => v_organization_id,
    p_user_id => v_actor_user_id,
    p_as_of => clock_timestamp(),
    p_stale_lock_timeout => interval '5 minutes'
  );
end;
$$;

revoke all
on notification.admin_operation_commands
from public, anon, authenticated;

grant select
on notification.admin_operation_commands
to service_role;

revoke all
on function notification.retry_outbox_event(
  uuid,
  uuid,
  text,
  text,
  timestamptz,
  uuid,
  uuid
)
from public, anon, authenticated;

revoke all
on function notification.request_manual_evaluation(
  uuid,
  text,
  text,
  text,
  timestamptz,
  uuid,
  uuid
)
from public, anon, authenticated;

revoke all
on function notification.get_operations_summary(
  uuid,
  uuid,
  timestamptz,
  interval
)
from public, anon, authenticated;

grant execute
on function notification.retry_outbox_event(
  uuid,
  uuid,
  text,
  text,
  timestamptz,
  uuid,
  uuid
)
to service_role;

grant execute
on function notification.request_manual_evaluation(
  uuid,
  text,
  text,
  text,
  timestamptz,
  uuid,
  uuid
)
to service_role;

grant execute
on function notification.get_operations_summary(
  uuid,
  uuid,
  timestamptz,
  interval
)
to service_role;

revoke all
on function api.retry_notification_outbox_event(
  uuid,
  text,
  text,
  uuid
)
from public, anon, authenticated;

revoke all
on function api.run_notification_evaluation(
  text,
  text,
  text,
  uuid
)
from public, anon, authenticated;

revoke all
on function api.get_notification_operations_summary()
from public, anon, authenticated;

grant execute
on function api.retry_notification_outbox_event(
  uuid,
  text,
  text,
  uuid
)
to authenticated;

grant execute
on function api.run_notification_evaluation(
  text,
  text,
  text,
  uuid
)
to authenticated;

grant execute
on function api.get_notification_operations_summary()
to authenticated;

commit;
