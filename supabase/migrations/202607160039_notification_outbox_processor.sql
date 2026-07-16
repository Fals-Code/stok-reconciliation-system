begin;

create or replace function notification.enqueue_outbox_event(
  p_organization_id uuid,
  p_event_type_code text,
  p_source_event_key text,
  p_entity_type_code text,
  p_entity_id uuid,
  p_occurred_at timestamptz,
  p_payload jsonb default '{}'::jsonb,
  p_correlation_id uuid default gen_random_uuid(),
  p_actor_user_id uuid default null,
  p_process_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app, extensions
as $$
declare
  v_event_type_code text :=
    upper(btrim(coalesce(p_event_type_code, '')));
  v_source_event_key text :=
    btrim(coalesce(p_source_event_key, ''));
  v_entity_type_code text :=
    upper(btrim(coalesce(p_entity_type_code, '')));
  v_process_name text :=
    nullif(btrim(coalesce(p_process_name, '')), '');
  v_payload_hash text;
  v_existing notification.outbox_events%rowtype;
  v_event_id uuid;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if v_event_type_code = ''
     or length(v_event_type_code) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_EVENT_TYPE_INVALID';
  end if;

  if v_source_event_key = ''
     or length(v_source_event_key) > 500 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_SOURCE_EVENT_KEY_INVALID';
  end if;

  if v_entity_type_code = ''
     or length(v_entity_type_code) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_ENTITY_TYPE_INVALID';
  end if;

  if p_entity_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_ENTITY_ID_REQUIRED';
  end if;

  if p_occurred_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_OCCURRED_AT_REQUIRED';
  end if;

  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_PAYLOAD_INVALID';
  end if;

  if p_correlation_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_CORRELATION_ID_REQUIRED';
  end if;

  if (p_actor_user_id is null) = (v_process_name is null) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_CONTEXT_INVALID';
  end if;

  if not exists (
    select 1
    from app.organizations organization
    where organization.id = p_organization_id
      and organization.is_active
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_NOT_FOUND';
  end if;

  if p_actor_user_id is not null
     and not exists (
       select 1
       from app.user_profiles profile
       where profile.user_id = p_actor_user_id
         and profile.organization_id = p_organization_id
         and profile.role_code = 'ADMIN'
         and profile.is_active
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_NOT_AUTHORIZED';
  end if;

  v_payload_hash :=
    encode(
      extensions.digest(p_payload::text, 'sha256'),
      'hex'
    );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
      || ':'
      || v_event_type_code
      || ':'
      || v_source_event_key,
      0::bigint
    )
  );

  select event_row.*
  into v_existing
  from notification.outbox_events event_row
  where event_row.organization_id = p_organization_id
    and event_row.event_type_code = v_event_type_code
    and event_row.source_event_key = v_source_event_key
  for update;

  if v_existing.id is not null then
    if v_existing.entity_type_code <> v_entity_type_code
       or v_existing.entity_id <> p_entity_id
       or v_existing.occurred_at <> p_occurred_at
       or v_existing.payload_hash <> v_payload_hash then
      raise exception using
        errcode = 'P0001',
        message = 'OUTBOX_SOURCE_EVENT_CONFLICT';
    end if;

    return jsonb_build_object(
      'action',
      'REPLAYED',
      'outboxEventId',
      v_existing.id,
      'status',
      v_existing.status_code,
      'attemptCount',
      v_existing.attempt_count,
      'payloadHash',
      v_existing.payload_hash
    );
  end if;

  insert into notification.outbox_events (
    organization_id,
    event_type_code,
    source_event_key,
    entity_type_code,
    entity_id,
    occurred_at,
    payload,
    payload_hash,
    correlation_id,
    status_code,
    attempt_count,
    available_at,
    locked_at,
    locked_by,
    completed_at,
    last_error_code,
    last_error_detail,
    actor_user_id,
    process_name,
    created_at
  )
  values (
    p_organization_id,
    v_event_type_code,
    v_source_event_key,
    v_entity_type_code,
    p_entity_id,
    p_occurred_at,
    p_payload,
    v_payload_hash,
    p_correlation_id,
    'PENDING',
    0,
    p_occurred_at,
    null,
    null,
    null,
    null,
    '{}'::jsonb,
    p_actor_user_id,
    v_process_name,
    clock_timestamp()
  )
  returning id into v_event_id;

  return jsonb_build_object(
    'action',
    'CREATED',
    'outboxEventId',
    v_event_id,
    'status',
    'PENDING',
    'attemptCount',
    0,
    'payloadHash',
    v_payload_hash
  );
end;
$$;

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
        'finalizedAt',
        p_now,
        'attemptCount',
        event_row.attempt_count,
        'reason',
        'RETRY_BUDGET_EXHAUSTED'
      )
    where event_row.status_code = 'FAILED_RETRYABLE'
      and event_row.attempt_count >= p_max_attempts
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
        'recoveredAt',
        p_now,
        'previousLockedAt',
        event_row.locked_at,
        'previousLockedBy',
        event_row.locked_by,
        'attemptCount',
        event_row.attempt_count,
        'reason',
        'STALE_PROCESSING_LOCK'
      )
    where event_row.status_code = 'PROCESSING'
      and event_row.locked_at <= p_now - p_lock_timeout
      and event_row.attempt_count >= p_max_attempts
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
        'recoveredAt',
        p_now,
        'previousLockedAt',
        event_row.locked_at,
        'previousLockedBy',
        event_row.locked_by,
        'attemptCount',
        event_row.attempt_count,
        'reason',
        'STALE_PROCESSING_LOCK'
      )
    where event_row.status_code = 'PROCESSING'
      and event_row.locked_at <= p_now - p_lock_timeout
      and event_row.attempt_count < p_max_attempts
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
      and event_row.attempt_count < p_max_attempts
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

create or replace function notification.complete_outbox_event(
  p_outbox_event_id uuid,
  p_worker_id text,
  p_completed_at timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification
as $$
declare
  v_worker_id text :=
    nullif(btrim(coalesce(p_worker_id, '')), '');
  v_event notification.outbox_events%rowtype;
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

  if p_completed_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_COMPLETION_TIME_REQUIRED';
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

  if v_event.status_code = 'COMPLETED' then
    return jsonb_build_object(
      'action',
      'ALREADY_COMPLETED',
      'outboxEventId',
      v_event.id,
      'status',
      v_event.status_code,
      'attemptCount',
      v_event.attempt_count,
      'completedAt',
      v_event.completed_at
    );
  end if;

  if v_event.status_code <> 'PROCESSING'
     or v_event.locked_by <> v_worker_id then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_LOCK_OWNERSHIP_INVALID';
  end if;

  if p_completed_at < v_event.locked_at then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_COMPLETION_TIME_INVALID';
  end if;

  update notification.outbox_events event_row
  set
    status_code = 'COMPLETED',
    locked_at = null,
    locked_by = null,
    completed_at = p_completed_at,
    last_error_code = null,
    last_error_detail = '{}'::jsonb
  where event_row.id = v_event.id;

  return jsonb_build_object(
    'action',
    'COMPLETED',
    'outboxEventId',
    v_event.id,
    'status',
    'COMPLETED',
    'attemptCount',
    v_event.attempt_count,
    'completedAt',
    p_completed_at
  );
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

  if p_retryable and v_event.attempt_count < p_max_attempts then
    v_status_code := 'FAILED_RETRYABLE';

    v_retry_seconds :=
      least(
        p_max_retry_seconds::numeric,
        p_base_retry_seconds::numeric
          * power(
              2::numeric,
              greatest(v_event.attempt_count - 1, 0)::numeric
            )
      )::integer;

    v_available_at :=
      greatest(
        v_event.occurred_at,
        p_failed_at + make_interval(secs => v_retry_seconds)
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
        when v_status_code = 'FAILED_FINAL' then p_failed_at
        else null
      end,
    last_error_code = v_error_code,
    last_error_detail =
      p_error_detail
      || jsonb_build_object(
        'failedAt',
        p_failed_at,
        'attemptCount',
        v_event.attempt_count,
        'retryable',
        p_retryable,
        'retryDelaySeconds',
        v_retry_seconds,
        'nextAvailableAt',
        case
          when v_status_code = 'FAILED_RETRYABLE'
            then v_available_at
          else null
        end
      )
  where event_row.id = v_event.id;

  return jsonb_build_object(
    'action',
    v_status_code,
    'outboxEventId',
    v_event.id,
    'status',
    v_status_code,
    'attemptCount',
    v_event.attempt_count,
    'retryDelaySeconds',
    v_retry_seconds,
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

create or replace function notification.process_outbox(
  p_worker_id text,
  p_limit integer default 10,
  p_now timestamptz default clock_timestamp(),
  p_lock_timeout interval default interval '5 minutes',
  p_max_attempts integer default 5,
  p_base_retry_seconds integer default 60,
  p_max_retry_seconds integer default 3600,
  p_process_name text default 'notification.process_outbox'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification
as $$
declare
  v_worker_id text :=
    nullif(btrim(coalesce(p_worker_id, '')), '');
  v_process_name text :=
    nullif(btrim(coalesce(p_process_name, '')), '');
  v_recovery_result jsonb;
  v_event notification.outbox_events%rowtype;
  v_evaluator_result jsonb;
  v_transition_result jsonb;
  v_rule_run_id uuid;
  v_rule_run_linked_count integer;
  v_evaluator_status text;
  v_run_idempotency_key text;
  v_claimed_count integer := 0;
  v_completed_count integer := 0;
  v_retryable_failure_count integer := 0;
  v_final_failure_count integer := 0;
  v_result_items jsonb := '[]'::jsonb;
  v_error_sqlstate text;
  v_error_message text;
begin
  if v_worker_id is null or length(v_worker_id) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_WORKER_ID_INVALID';
  end if;

  if v_process_name is null or length(v_process_name) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_PROCESS_NAME_REQUIRED';
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

  if p_base_retry_seconds < 1
     or p_max_retry_seconds < p_base_retry_seconds
     or p_max_retry_seconds > 86400 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_RETRY_POLICY_INVALID';
  end if;

  v_recovery_result :=
    notification.recover_stale_outbox_events(
      p_now => p_now,
      p_lock_timeout => p_lock_timeout,
      p_max_attempts => p_max_attempts
    );

  for v_event in
    select claimed.*
    from notification.claim_outbox_events(
      p_worker_id => v_worker_id,
      p_limit => p_limit,
      p_now => p_now,
      p_max_attempts => p_max_attempts
    ) claimed
  loop
    v_claimed_count := v_claimed_count + 1;
    v_transition_result := null;
    v_evaluator_result := null;

    if v_event.event_type_code =
       'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED' then
      begin
        v_run_idempotency_key :=
          'outbox:'
          || v_event.id::text
          || ':attempt:'
          || v_event.attempt_count::text
          || ':available:'
          || extract(epoch from v_event.available_at)::text;

        v_evaluator_result :=
          notification.evaluate_expiry(
            p_organization_id => v_event.organization_id,
            p_idempotency_key => v_run_idempotency_key,
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'SCHEDULED',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          );

        v_rule_run_id :=
          nullif(v_evaluator_result ->> 'ruleRunId', '')::uuid;

        if v_rule_run_id is null then
          raise exception using
            errcode = 'P0001',
            message = 'OUTBOX_RULE_RUN_ID_MISSING';
        end if;

        update notification.rule_runs run
        set
          trigger_type_code = 'OUTBOX',
          triggered_by_outbox_event_id = v_event.id
        where run.id = v_rule_run_id
          and run.organization_id = v_event.organization_id
          and (
            run.triggered_by_outbox_event_id is null
            or run.triggered_by_outbox_event_id = v_event.id
          );

        get diagnostics v_rule_run_linked_count = row_count;

        if v_rule_run_linked_count <> 1 then
          raise exception using
            errcode = 'P0001',
            message = 'OUTBOX_RULE_RUN_LINK_FAILED';
        end if;

        v_evaluator_status :=
          upper(coalesce(v_evaluator_result ->> 'status', ''));

        if v_evaluator_status = 'SUCCEEDED' then
          v_transition_result :=
            notification.complete_outbox_event(
              p_outbox_event_id => v_event.id,
              p_worker_id => v_worker_id,
              p_completed_at => p_now
            );
        elsif v_evaluator_status in (
          'PARTIALLY_FAILED',
          'FAILED'
        ) then
          v_transition_result :=
            notification.fail_outbox_event(
              p_outbox_event_id => v_event.id,
              p_worker_id => v_worker_id,
              p_error_code =>
                case v_evaluator_status
                  when 'PARTIALLY_FAILED'
                    then 'OUTBOX_EVALUATOR_PARTIALLY_FAILED'
                  else 'OUTBOX_EVALUATOR_FAILED'
                end,
              p_error_detail => jsonb_build_object(
                'evaluatorResult',
                v_evaluator_result
              ),
              p_failed_at => p_now,
              p_retryable => true,
              p_max_attempts => p_max_attempts,
              p_base_retry_seconds => p_base_retry_seconds,
              p_max_retry_seconds => p_max_retry_seconds
            );
        else
          v_transition_result :=
            notification.fail_outbox_event(
              p_outbox_event_id => v_event.id,
              p_worker_id => v_worker_id,
              p_error_code => 'OUTBOX_EVALUATOR_STATUS_INVALID',
              p_error_detail => jsonb_build_object(
                'evaluatorResult',
                v_evaluator_result
              ),
              p_failed_at => p_now,
              p_retryable => false,
              p_max_attempts => p_max_attempts,
              p_base_retry_seconds => p_base_retry_seconds,
              p_max_retry_seconds => p_max_retry_seconds
            );
        end if;
      exception
        when others then
          get stacked diagnostics
            v_error_sqlstate = returned_sqlstate,
            v_error_message = message_text;

          v_transition_result :=
            notification.fail_outbox_event(
              p_outbox_event_id => v_event.id,
              p_worker_id => v_worker_id,
              p_error_code => 'OUTBOX_DISPATCH_EXCEPTION',
              p_error_detail => jsonb_build_object(
                'sqlstate',
                v_error_sqlstate,
                'errorCode',
                v_error_message
              ),
              p_failed_at => p_now,
              p_retryable => true,
              p_max_attempts => p_max_attempts,
              p_base_retry_seconds => p_base_retry_seconds,
              p_max_retry_seconds => p_max_retry_seconds
            );
      end;
    else
      v_transition_result :=
        notification.fail_outbox_event(
          p_outbox_event_id => v_event.id,
          p_worker_id => v_worker_id,
          p_error_code => 'OUTBOX_EVENT_TYPE_UNSUPPORTED',
          p_error_detail => jsonb_build_object(
            'eventTypeCode',
            v_event.event_type_code
          ),
          p_failed_at => p_now,
          p_retryable => false,
          p_max_attempts => p_max_attempts,
          p_base_retry_seconds => p_base_retry_seconds,
          p_max_retry_seconds => p_max_retry_seconds
        );
    end if;

    case v_transition_result ->> 'action'
      when 'COMPLETED' then
        v_completed_count := v_completed_count + 1;
      when 'ALREADY_COMPLETED' then
        v_completed_count := v_completed_count + 1;
      when 'FAILED_RETRYABLE' then
        v_retryable_failure_count :=
          v_retryable_failure_count + 1;
      when 'FAILED_FINAL' then
        v_final_failure_count := v_final_failure_count + 1;
      else
        raise exception using
          errcode = 'P0001',
          message = 'OUTBOX_TRANSITION_RESULT_INVALID';
    end case;

    if jsonb_array_length(v_result_items) < 100 then
      v_result_items :=
        v_result_items
        || jsonb_build_array(
          jsonb_build_object(
            'outboxEventId',
            v_event.id,
            'eventTypeCode',
            v_event.event_type_code,
            'attemptCount',
            v_event.attempt_count,
            'transition',
            v_transition_result,
            'evaluatorResult',
            v_evaluator_result
          )
        );
    end if;
  end loop;

  return jsonb_build_object(
    'workerId',
    v_worker_id,
    'processedAt',
    p_now,
    'claimedCount',
    v_claimed_count,
    'completedCount',
    v_completed_count,
    'retryableFailureCount',
    v_retryable_failure_count,
    'finalFailureCount',
    v_final_failure_count,
    'recovery',
    v_recovery_result,
    'items',
    v_result_items
  );
end;
$$;

revoke all
on function notification.enqueue_outbox_event(
  uuid,
  text,
  text,
  text,
  uuid,
  timestamptz,
  jsonb,
  uuid,
  uuid,
  text
)
from public, anon, authenticated;

revoke all
on function notification.recover_stale_outbox_events(
  timestamptz,
  interval,
  integer
)
from public, anon, authenticated;

revoke all
on function notification.claim_outbox_events(
  text,
  integer,
  timestamptz,
  integer
)
from public, anon, authenticated;

revoke all
on function notification.complete_outbox_event(
  uuid,
  text,
  timestamptz
)
from public, anon, authenticated;

revoke all
on function notification.fail_outbox_event(
  uuid,
  text,
  text,
  jsonb,
  timestamptz,
  boolean,
  integer,
  integer,
  integer
)
from public, anon, authenticated;

revoke all
on function notification.process_outbox(
  text,
  integer,
  timestamptz,
  interval,
  integer,
  integer,
  integer,
  text
)
from public, anon, authenticated;

grant execute
on function notification.enqueue_outbox_event(
  uuid,
  text,
  text,
  text,
  uuid,
  timestamptz,
  jsonb,
  uuid,
  uuid,
  text
)
to service_role;

grant execute
on function notification.recover_stale_outbox_events(
  timestamptz,
  interval,
  integer
)
to service_role;

grant execute
on function notification.claim_outbox_events(
  text,
  integer,
  timestamptz,
  integer
)
to service_role;

grant execute
on function notification.complete_outbox_event(
  uuid,
  text,
  timestamptz
)
to service_role;

grant execute
on function notification.fail_outbox_event(
  uuid,
  text,
  text,
  jsonb,
  timestamptz,
  boolean,
  integer,
  integer,
  integer
)
to service_role;

grant execute
on function notification.process_outbox(
  text,
  integer,
  timestamptz,
  interval,
  integer,
  integer,
  integer,
  text
)
to service_role;

commit;
