begin;

create or replace function notification.dispatch_outbox_event(
  p_outbox_event_id uuid,
  p_process_name text default 'notification.dispatch_outbox_event'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification
as $$
declare
  v_process_name text :=
    nullif(btrim(coalesce(p_process_name, '')), '');
  v_event notification.outbox_events%rowtype;
  v_base_idempotency_key text;
  v_results jsonb := '[]'::jsonb;
  v_item jsonb;
  v_rule_run_id uuid;
  v_rule_run_linked_count integer;
  v_evaluator_status text;
  v_overall_status text := 'SUCCEEDED';
  v_evaluator_count integer := 0;
begin
  if p_outbox_event_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_EVENT_ID_REQUIRED';
  end if;

  if v_process_name is null or length(v_process_name) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_PROCESS_NAME_REQUIRED';
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
     or v_event.locked_at is null
     or v_event.locked_by is null then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_DISPATCH_EVENT_NOT_PROCESSING';
  end if;

  v_base_idempotency_key :=
    'outbox:'
    || v_event.id::text
    || ':attempt:'
    || v_event.attempt_count::text
    || ':available:'
    || extract(epoch from v_event.available_at)::text;

  case v_event.event_type_code
    when 'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED' then
      v_results :=
        jsonb_build_array(
          notification.evaluate_expiry(
            p_organization_id => v_event.organization_id,
            p_idempotency_key =>
              v_base_idempotency_key || ':expiry',
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'SCHEDULED',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          )
        );

    when 'NOTIFICATION_RETURN_INSPECTION_EVALUATION_REQUESTED' then
      v_results :=
        jsonb_build_array(
          notification.evaluate_return_inspection(
            p_organization_id => v_event.organization_id,
            p_idempotency_key =>
              v_base_idempotency_key || ':return-inspection',
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'EVENT_DRIVEN',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          )
        );

    when 'NOTIFICATION_RECONCILIATION_ISSUE_EVALUATION_REQUESTED' then
      v_results :=
        jsonb_build_array(
          notification.evaluate_reconciliation_issues(
            p_organization_id => v_event.organization_id,
            p_idempotency_key =>
              v_base_idempotency_key
              || ':reconciliation-issues',
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'EVENT_DRIVEN',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          )
        );

    when 'NOTIFICATION_RECONCILIATION_FAILURE_EVALUATION_REQUESTED' then
      v_results :=
        jsonb_build_array(
          notification.evaluate_reconciliation_failures(
            p_organization_id => v_event.organization_id,
            p_idempotency_key =>
              v_base_idempotency_key
              || ':reconciliation-failures',
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'EVENT_DRIVEN',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          )
        );

    when 'NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED' then
      v_results :=
        jsonb_build_array(
          notification.evaluate_reconciliation_issues(
            p_organization_id => v_event.organization_id,
            p_idempotency_key =>
              v_base_idempotency_key
              || ':reconciliation-issues',
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'EVENT_DRIVEN',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          ),
          notification.evaluate_reconciliation_failures(
            p_organization_id => v_event.organization_id,
            p_idempotency_key =>
              v_base_idempotency_key
              || ':reconciliation-failures',
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'EVENT_DRIVEN',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          )
        );

    when 'NOTIFICATION_STOCKTAKE_RECOUNT_EVALUATION_REQUESTED' then
      v_results :=
        jsonb_build_array(
          notification.evaluate_stocktake_recounts(
            p_organization_id => v_event.organization_id,
            p_idempotency_key =>
              v_base_idempotency_key
              || ':stocktake-recounts',
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'EVENT_DRIVEN',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          )
        );

    when 'NOTIFICATION_STOCKTAKE_POST_FAILURE_EVALUATION_REQUESTED' then
      v_results :=
        jsonb_build_array(
          notification.evaluate_stocktake_post_failures(
            p_organization_id => v_event.organization_id,
            p_idempotency_key =>
              v_base_idempotency_key
              || ':stocktake-post-failures',
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'EVENT_DRIVEN',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          )
        );

    when 'NOTIFICATION_STOCKTAKE_EVALUATION_REQUESTED' then
      v_results :=
        jsonb_build_array(
          notification.evaluate_stocktake_recounts(
            p_organization_id => v_event.organization_id,
            p_idempotency_key =>
              v_base_idempotency_key
              || ':stocktake-recounts',
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'EVENT_DRIVEN',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          ),
          notification.evaluate_stocktake_post_failures(
            p_organization_id => v_event.organization_id,
            p_idempotency_key =>
              v_base_idempotency_key
              || ':stocktake-post-failures',
            p_observed_at => v_event.occurred_at,
            p_trigger_type_code => 'EVENT_DRIVEN',
            p_correlation_id => v_event.correlation_id,
            p_process_name => v_process_name
          )
        );

    else
      raise exception using
        errcode = 'P0001',
        message = 'OUTBOX_EVENT_TYPE_UNSUPPORTED';
  end case;

  if jsonb_typeof(v_results) is distinct from 'array'
     or jsonb_array_length(v_results) = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'OUTBOX_DISPATCH_RESULT_INVALID';
  end if;

  for v_item in
    select result.value
    from jsonb_array_elements(v_results) result(value)
  loop
    v_evaluator_count := v_evaluator_count + 1;

    if jsonb_typeof(v_item) is distinct from 'object' then
      raise exception using
        errcode = 'P0001',
        message = 'OUTBOX_EVALUATOR_RESULT_INVALID';
    end if;

    begin
      v_rule_run_id :=
        nullif(v_item ->> 'ruleRunId', '')::uuid;
    exception
      when others then
        raise exception using
          errcode = 'P0001',
          message = 'OUTBOX_RULE_RUN_ID_INVALID';
    end;

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
      upper(coalesce(v_item ->> 'status', ''));

    if v_evaluator_status = 'FAILED' then
      v_overall_status := 'FAILED';
    elsif v_evaluator_status = 'PARTIALLY_FAILED' then
      if v_overall_status <> 'FAILED' then
        v_overall_status := 'PARTIALLY_FAILED';
      end if;
    elsif v_evaluator_status <> 'SUCCEEDED' then
      raise exception using
        errcode = 'P0001',
        message = 'OUTBOX_EVALUATOR_STATUS_INVALID';
    end if;
  end loop;

  return jsonb_build_object(
    'action', 'DISPATCHED',
    'outboxEventId', v_event.id,
    'eventTypeCode', v_event.event_type_code,
    'organizationId', v_event.organization_id,
    'attemptCount', v_event.attempt_count,
    'status', v_overall_status,
    'evaluatorCount', v_evaluator_count,
    'results', v_results
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
  v_dispatch_result jsonb;
  v_transition_result jsonb;
  v_dispatch_status text;
  v_claimed_count integer := 0;
  v_completed_count integer := 0;
  v_retryable_failure_count integer := 0;
  v_final_failure_count integer := 0;
  v_result_items jsonb := '[]'::jsonb;
  v_error_sqlstate text;
  v_error_message text;
  v_exception_retryable boolean;
  v_exception_error_code text;
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
    v_dispatch_result := null;

    begin
      v_dispatch_result :=
        notification.dispatch_outbox_event(
          p_outbox_event_id => v_event.id,
          p_process_name => v_process_name
        );

      v_dispatch_status :=
        upper(coalesce(v_dispatch_result ->> 'status', ''));

      if v_dispatch_status = 'SUCCEEDED' then
        v_transition_result :=
          notification.complete_outbox_event(
            p_outbox_event_id => v_event.id,
            p_worker_id => v_worker_id,
            p_completed_at => p_now
          );
      elsif v_dispatch_status in (
        'PARTIALLY_FAILED',
        'FAILED'
      ) then
        v_transition_result :=
          notification.fail_outbox_event(
            p_outbox_event_id => v_event.id,
            p_worker_id => v_worker_id,
            p_error_code =>
              case v_dispatch_status
                when 'PARTIALLY_FAILED'
                  then 'OUTBOX_EVALUATOR_PARTIALLY_FAILED'
                else 'OUTBOX_EVALUATOR_FAILED'
              end,
            p_error_detail => jsonb_build_object(
              'dispatchResult',
              v_dispatch_result
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
              'dispatchResult',
              v_dispatch_result
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

        v_exception_retryable :=
          v_error_message not in (
            'OUTBOX_EVENT_TYPE_UNSUPPORTED',
            'OUTBOX_DISPATCH_EVENT_NOT_PROCESSING',
            'OUTBOX_RULE_RUN_ID_INVALID',
            'OUTBOX_RULE_RUN_ID_MISSING',
            'OUTBOX_EVALUATOR_STATUS_INVALID',
            'OUTBOX_EVALUATOR_RESULT_INVALID',
            'OUTBOX_DISPATCH_RESULT_INVALID'
          );

        v_exception_error_code :=
          case
            when v_error_message =
                 'OUTBOX_EVENT_TYPE_UNSUPPORTED'
              then 'OUTBOX_EVENT_TYPE_UNSUPPORTED'
            else 'OUTBOX_DISPATCH_EXCEPTION'
          end;

        v_transition_result :=
          notification.fail_outbox_event(
            p_outbox_event_id => v_event.id,
            p_worker_id => v_worker_id,
            p_error_code => v_exception_error_code,
            p_error_detail => jsonb_build_object(
              'sqlstate', v_error_sqlstate,
              'errorCode', v_error_message,
              'eventTypeCode', v_event.event_type_code
            ),
            p_failed_at => p_now,
            p_retryable => v_exception_retryable,
            p_max_attempts => p_max_attempts,
            p_base_retry_seconds => p_base_retry_seconds,
            p_max_retry_seconds => p_max_retry_seconds
          );
    end;

    case v_transition_result ->> 'action'
      when 'COMPLETED' then
        v_completed_count := v_completed_count + 1;
      when 'ALREADY_COMPLETED' then
        v_completed_count := v_completed_count + 1;
      when 'FAILED_RETRYABLE' then
        v_retryable_failure_count :=
          v_retryable_failure_count + 1;
      when 'FAILED_FINAL' then
        v_final_failure_count :=
          v_final_failure_count + 1;
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
            'outboxEventId', v_event.id,
            'eventTypeCode', v_event.event_type_code,
            'attemptCount', v_event.attempt_count,
            'transition', v_transition_result,
            'evaluatorResult', v_dispatch_result,
            'dispatchResult', v_dispatch_result
          )
        );
    end if;
  end loop;

  return jsonb_build_object(
    'workerId', v_worker_id,
    'processedAt', p_now,
    'claimedCount', v_claimed_count,
    'completedCount', v_completed_count,
    'retryableFailureCount', v_retryable_failure_count,
    'finalFailureCount', v_final_failure_count,
    'recovery', v_recovery_result,
    'items', v_result_items
  );
end;
$$;

revoke all
on function notification.dispatch_outbox_event(
  uuid,
  text
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
on function notification.dispatch_outbox_event(
  uuid,
  text
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
