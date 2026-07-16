begin;

create or replace function notification.ensure_stocktake_recount_rule(
  p_organization_id uuid,
  p_effective_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, notification, app
as $$
declare
  v_rule notification.rules%rowtype;
  v_rule_id uuid;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if p_effective_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_RECOUNT_RULE_EFFECTIVE_TIME_REQUIRED';
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

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
      || ':NOTIFICATION_RULE:STOCKTAKE_RECOUNT_REQUIRED',
      0::bigint
    )
  );

  select rule.*
  into v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'STOCKTAKE_RECOUNT_REQUIRED'
  order by
    rule.effective_from desc,
    rule.created_at desc,
    rule.id desc
  limit 1
  for update;

  if v_rule.id is not null then
    if not v_rule.is_active
       or v_rule.effective_from > p_effective_at
       or (
         v_rule.effective_to is not null
         and v_rule.effective_to <= p_effective_at
       ) then
      raise exception using
        errcode = 'P0001',
        message = 'STOCKTAKE_RECOUNT_RULE_NOT_ACTIVE';
    end if;

    return v_rule.id;
  end if;

  insert into notification.rules (
    organization_id,
    code,
    version,
    category_code,
    trigger_mode_code,
    entity_type_code,
    severity_strategy_code,
    stage_strategy_code,
    condition_strategy_code,
    resolution_strategy_code,
    template_version,
    action_code,
    config,
    is_active,
    effective_from,
    effective_to,
    created_by,
    created_at,
    updated_by,
    updated_at
  )
  values (
    p_organization_id,
    'STOCKTAKE_RECOUNT_REQUIRED',
    '1.0.0',
    'STOCKTAKE',
    'HYBRID',
    'STOCKTAKE',
    'FIXED_HIGH_V1',
    'FIXED_RECOUNT_REQUIRED_V1',
    'RECOUNT_REQUIRED_LINE_COUNT_POSITIVE_V1',
    'SOURCE_CONDITION_CLEARED_V1',
    '1.0.0',
    'OPEN_STOCKTAKE_RECOUNT_LINES',
    jsonb_build_object(
      'stageCode',
      'RECOUNT_REQUIRED',
      'severityCode',
      'HIGH',
      'eligibleCountStatuses',
      jsonb_build_array('RECOUNT_REQUESTED'),
      'eligibleReviewDecisions',
      jsonb_build_array('RECOUNT_REQUIRED'),
      'terminalStatuses',
      jsonb_build_array('POSTED', 'CANCELLED'),
      'conditionStartedAt',
      'EARLIEST_RECOUNT_LINE_UPDATED_AT',
      'messageSchemaVersion',
      1
    ),
    true,
    p_effective_at,
    null,
    null,
    clock_timestamp(),
    null,
    clock_timestamp()
  )
  returning id into v_rule_id;

  return v_rule_id;
end;
$$;

create or replace function notification.ensure_stocktake_post_failed_rule(
  p_organization_id uuid,
  p_effective_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, notification, app
as $$
declare
  v_rule notification.rules%rowtype;
  v_rule_id uuid;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if p_effective_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_POST_FAILURE_RULE_EFFECTIVE_TIME_REQUIRED';
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

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
      || ':NOTIFICATION_RULE:STOCKTAKE_POST_FAILED',
      0::bigint
    )
  );

  select rule.*
  into v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'STOCKTAKE_POST_FAILED'
  order by
    rule.effective_from desc,
    rule.created_at desc,
    rule.id desc
  limit 1
  for update;

  if v_rule.id is not null then
    if not v_rule.is_active
       or v_rule.effective_from > p_effective_at
       or (
         v_rule.effective_to is not null
         and v_rule.effective_to <= p_effective_at
       ) then
      raise exception using
        errcode = 'P0001',
        message = 'STOCKTAKE_POST_FAILURE_RULE_NOT_ACTIVE';
    end if;

    return v_rule.id;
  end if;

  insert into notification.rules (
    organization_id,
    code,
    version,
    category_code,
    trigger_mode_code,
    entity_type_code,
    severity_strategy_code,
    stage_strategy_code,
    condition_strategy_code,
    resolution_strategy_code,
    template_version,
    action_code,
    config,
    is_active,
    effective_from,
    effective_to,
    created_by,
    created_at,
    updated_by,
    updated_at
  )
  values (
    p_organization_id,
    'STOCKTAKE_POST_FAILED',
    '1.0.0',
    'STOCKTAKE',
    'HYBRID',
    'STOCKTAKE',
    'FIXED_CRITICAL_V1',
    'POST_FAILURE_STAGE_V1',
    'EXCEPTION_STALE_POSTING_OR_FAILED_RECONCILIATION_V1',
    'SOURCE_CONDITION_CLEARED_V1',
    '1.0.0',
    'OPEN_STOCKTAKE_DETAIL',
    jsonb_build_object(
      'postingStaleMinutes',
      30,
      'severityCode',
      'CRITICAL',
      'stages',
      jsonb_build_array(
        jsonb_build_object(
          'code', 'RESULT_UNCERTAIN',
          'rank', 1
        ),
        jsonb_build_object(
          'code', 'RECONCILIATION_FAILED',
          'rank', 2
        )
      ),
      'exceptionStatusCode',
      'EXCEPTION',
      'postingStatusCode',
      'POSTING',
      'failedReconciliationStatusCode',
      'FAILED',
      'resolutionConditions',
      jsonb_build_array(
        'SESSION_RECOVERED',
        'POSTING_COMPLETED',
        'RECONCILIATION_RECOVERED',
        'SESSION_CANCELLED',
        'SOURCE_ENTITY_MISSING'
      ),
      'messageSchemaVersion',
      1
    ),
    true,
    p_effective_at,
    null,
    null,
    clock_timestamp(),
    null,
    clock_timestamp()
  )
  returning id into v_rule_id;

  return v_rule_id;
end;
$$;

create or replace function notification.evaluate_stocktake_recounts(
  p_organization_id uuid,
  p_idempotency_key text,
  p_observed_at timestamptz default clock_timestamp(),
  p_trigger_type_code text default 'SCHEDULED',
  p_correlation_id uuid default gen_random_uuid(),
  p_process_name text default 'notification.evaluate_stocktake_recounts'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app, operations
as $$
declare
  v_idempotency_key text :=
    btrim(coalesce(p_idempotency_key, ''));
  v_trigger_type_code text :=
    upper(btrim(coalesce(p_trigger_type_code, '')));
  v_process_name text :=
    nullif(btrim(coalesce(p_process_name, '')), '');
  v_rule notification.rules%rowtype;
  v_existing_run notification.rule_runs%rowtype;
  v_active notification.notifications%rowtype;
  v_rule_run_id uuid;
  v_organization_timezone text;
  v_local_date date;
  v_candidate record;
  v_upsert_result jsonb;
  v_resolve_result jsonb;
  v_action text;
  v_title text;
  v_message text;
  v_action_route text;
  v_condition_started_at timestamptz;
  v_source_snapshot jsonb;
  v_resolution_snapshot jsonb;
  v_resolution_reason text;
  v_evaluated_count integer := 0;
  v_created_count integer := 0;
  v_updated_count integer := 0;
  v_resolved_count integer := 0;
  v_skipped_count integer := 0;
  v_error_count integer := 0;
  v_error_items jsonb := '[]'::jsonb;
  v_status_code text;
  v_completed_at timestamptz;
  v_error_sqlstate text;
  v_error_message text;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if v_idempotency_key = '' then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_RULE_RUN_IDEMPOTENCY_REQUIRED';
  end if;

  if length(v_idempotency_key) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_RULE_RUN_IDEMPOTENCY_TOO_LONG';
  end if;

  if p_observed_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_OBSERVED_AT_REQUIRED';
  end if;

  if v_trigger_type_code not in (
    'SCHEDULED',
    'MANUAL',
    'EVENT_DRIVEN'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_RECOUNT_TRIGGER_TYPE_INVALID';
  end if;

  if p_correlation_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_CORRELATION_ID_REQUIRED';
  end if;

  if v_process_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_PROCESS_NAME_REQUIRED';
  end if;

  select organization.timezone
  into v_organization_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if v_organization_timezone is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_NOT_FOUND';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
      || ':NOTIFICATION_EVALUATOR:STOCKTAKE_RECOUNT_REQUIRED',
      0::bigint
    )
  );

  select run.*
  into v_existing_run
  from notification.rule_runs run
  where run.organization_id = p_organization_id
    and run.rule_code_snapshot = 'STOCKTAKE_RECOUNT_REQUIRED'
    and run.idempotency_key = v_idempotency_key
  for update;

  if v_existing_run.id is not null then
    return jsonb_build_object(
      'action', 'REPLAYED',
      'ruleRunId', v_existing_run.id,
      'ruleCode', v_existing_run.rule_code_snapshot,
      'ruleVersion', v_existing_run.rule_version_snapshot,
      'status', v_existing_run.status_code,
      'evaluatedCount', v_existing_run.evaluated_count,
      'createdCount', v_existing_run.created_count,
      'updatedCount', v_existing_run.updated_count,
      'resolvedCount', v_existing_run.resolved_count,
      'skippedCount', v_existing_run.skipped_count,
      'errorCount', v_existing_run.error_count,
      'summary', v_existing_run.summary
    );
  end if;

  perform notification.ensure_stocktake_recount_rule(
    p_organization_id,
    p_observed_at
  );

  select rule.*
  into strict v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'STOCKTAKE_RECOUNT_REQUIRED'
    and rule.is_active
    and rule.effective_from <= p_observed_at
    and (
      rule.effective_to is null
      or rule.effective_to > p_observed_at
    )
  order by
    rule.effective_from desc,
    rule.created_at desc,
    rule.id desc
  limit 1;

  insert into notification.rule_runs (
    organization_id,
    rule_id,
    rule_code_snapshot,
    rule_version_snapshot,
    trigger_type_code,
    triggered_by_outbox_event_id,
    idempotency_key,
    status_code,
    started_at,
    completed_at,
    evaluated_count,
    created_count,
    updated_count,
    resolved_count,
    skipped_count,
    error_count,
    summary,
    error_code,
    error_detail,
    correlation_id,
    actor_user_id,
    process_name,
    created_at
  )
  values (
    p_organization_id,
    v_rule.id,
    v_rule.code,
    v_rule.version,
    v_trigger_type_code,
    null,
    v_idempotency_key,
    'STARTED',
    clock_timestamp(),
    null,
    0,
    0,
    0,
    0,
    0,
    0,
    '{}'::jsonb,
    null,
    '{}'::jsonb,
    p_correlation_id,
    null,
    v_process_name,
    clock_timestamp()
  )
  returning id into v_rule_run_id;

  begin
    if v_rule.config ->> 'stageCode'
         is distinct from 'RECOUNT_REQUIRED'
       or v_rule.config ->> 'severityCode'
         is distinct from 'HIGH'
       or jsonb_typeof(
         v_rule.config -> 'terminalStatuses'
       ) is distinct from 'array' then
      raise exception using
        errcode = 'P0001',
        message = 'STOCKTAKE_RECOUNT_RULE_CONFIG_INVALID';
    end if;

    v_local_date :=
      (p_observed_at at time zone v_organization_timezone)::date;

    for v_candidate in
      with source_rows as (
        select
          stocktake.id as entity_id,
          stocktake.stocktake_no,
          stocktake.title,
          stocktake.stocktake_type_code,
          stocktake.mode_code,
          stocktake.visibility_code,
          stocktake.status_code,
          stocktake.scope_definition,
          stocktake.tolerance_policy_snapshot,
          stocktake.rule_version,
          stocktake.timezone_snapshot,
          stocktake.planned_at,
          stocktake.snapshot_ledger_seq,
          stocktake.started_at,
          stocktake.counting_completed_at,
          stocktake.approved_at,
          stocktake.posted_at,
          stocktake.stock_transaction_id,
          stocktake.reconciliation_run_id,
          stocktake.note,
          stocktake.metadata,
          stocktake.created_at as stocktake_created_at,
          stocktake.updated_at as stocktake_updated_at,
          stocktake.version_no,
          coalesce(line_summary.line_count, 0)::bigint
            as line_count,
          coalesce(
            line_summary.recount_required_line_count,
            0
          )::bigint as recount_required_line_count,
          line_summary.earliest_recount_requested_at,
          false as source_missing
        from operations.stocktakes stocktake
        left join lateral (
          select
            count(*)::bigint as line_count,
            count(*) filter (
              where line.count_status_code =
                    'RECOUNT_REQUESTED'
                 or line.review_decision_code =
                    'RECOUNT_REQUIRED'
            )::bigint as recount_required_line_count,
            min(line.updated_at) filter (
              where line.count_status_code =
                    'RECOUNT_REQUESTED'
                 or line.review_decision_code =
                    'RECOUNT_REQUIRED'
            ) as earliest_recount_requested_at
          from operations.stocktake_lines line
          where line.organization_id =
                stocktake.organization_id
            and line.stocktake_id = stocktake.id
        ) line_summary on true
        where stocktake.organization_id =
              p_organization_id
      ),
      active_without_source as (
        select notification_row.entity_id
        from notification.notifications notification_row
        where notification_row.organization_id =
              p_organization_id
          and notification_row.rule_code_snapshot =
              v_rule.code
          and notification_row.entity_type_code =
              'STOCKTAKE'
          and notification_row.lifecycle_status_code in (
            'OPEN',
            'ACKNOWLEDGED'
          )
          and not exists (
            select 1
            from source_rows source_row
            where source_row.entity_id =
                  notification_row.entity_id
          )
      )
      select
        source_row.entity_id,
        source_row.stocktake_no,
        source_row.title,
        source_row.stocktake_type_code,
        source_row.mode_code,
        source_row.visibility_code,
        source_row.status_code,
        source_row.scope_definition,
        source_row.tolerance_policy_snapshot,
        source_row.rule_version,
        source_row.timezone_snapshot,
        source_row.planned_at,
        source_row.snapshot_ledger_seq,
        source_row.started_at,
        source_row.counting_completed_at,
        source_row.approved_at,
        source_row.posted_at,
        source_row.stock_transaction_id,
        source_row.reconciliation_run_id,
        source_row.note,
        source_row.metadata,
        source_row.stocktake_created_at,
        source_row.stocktake_updated_at,
        source_row.version_no,
        source_row.line_count,
        source_row.recount_required_line_count,
        source_row.earliest_recount_requested_at,
        source_row.source_missing
      from source_rows source_row

      union all

      select
        orphan.entity_id,
        null::text,
        null::text,
        null::text,
        null::text,
        null::text,
        null::text,
        '{}'::jsonb,
        '{}'::jsonb,
        null::text,
        null::text,
        null::timestamptz,
        null::bigint,
        null::timestamptz,
        null::timestamptz,
        null::timestamptz,
        null::timestamptz,
        null::uuid,
        null::uuid,
        null::text,
        '{}'::jsonb,
        null::timestamptz,
        null::timestamptz,
        null::bigint,
        0::bigint,
        0::bigint,
        null::timestamptz,
        true
      from active_without_source orphan
      order by entity_id
    loop
      v_evaluated_count := v_evaluated_count + 1;

      begin
        select notification_row.*
        into v_active
        from notification.notifications notification_row
        where notification_row.organization_id =
              p_organization_id
          and notification_row.rule_code_snapshot =
              v_rule.code
          and notification_row.entity_type_code =
              'STOCKTAKE'
          and notification_row.entity_id =
              v_candidate.entity_id
          and notification_row.lifecycle_status_code in (
            'OPEN',
            'ACKNOWLEDGED'
          )
        order by notification_row.episode_no desc
        limit 1
        for update;

        v_title := null;
        v_message := null;
        v_action_route := null;
        v_condition_started_at := null;
        v_source_snapshot := '{}'::jsonb;
        v_resolution_snapshot := '{}'::jsonb;
        v_resolution_reason := null;

        if v_candidate.source_missing then
          v_resolution_reason := 'SOURCE_ENTITY_MISSING';
        elsif v_candidate.recount_required_line_count > 0
              and v_candidate.status_code not in (
                'POSTED',
                'CANCELLED'
              ) then
          v_condition_started_at :=
            v_candidate.earliest_recount_requested_at;

          if v_condition_started_at is null
             or v_condition_started_at > p_observed_at then
            raise exception using
              errcode = 'P0001',
              message =
                'STOCKTAKE_RECOUNT_CONDITION_TIME_INVALID';
          end if;

          v_title := 'Stocktake memerlukan recount';

          v_message := format(
            'Stocktake %s memiliki %s line yang harus dihitung ulang.',
            v_candidate.stocktake_no,
            v_candidate.recount_required_line_count
          );

          v_action_route :=
            '/admin/stocktakes/'
            || v_candidate.entity_id::text
            || '?filter=recount-required';

          v_source_snapshot := jsonb_build_object(
            'schemaVersion', 1,
            'organizationTimezone',
              v_organization_timezone,
            'localDate', v_local_date,
            'stocktakeId', v_candidate.entity_id,
            'stocktakeNo', v_candidate.stocktake_no,
            'title', v_candidate.title,
            'stocktakeTypeCode',
              v_candidate.stocktake_type_code,
            'modeCode', v_candidate.mode_code,
            'visibilityCode',
              v_candidate.visibility_code,
            'statusCode', v_candidate.status_code,
            'lineCount', v_candidate.line_count,
            'recountRequiredLineCount',
              v_candidate.recount_required_line_count,
            'earliestRecountRequestedAt',
              v_candidate.earliest_recount_requested_at,
            'scopeDefinition',
              v_candidate.scope_definition,
            'tolerancePolicySnapshot',
              v_candidate.tolerance_policy_snapshot,
            'ruleVersion', v_candidate.rule_version,
            'timezoneSnapshot',
              v_candidate.timezone_snapshot,
            'plannedAt', v_candidate.planned_at,
            'snapshotLedgerSeq',
              v_candidate.snapshot_ledger_seq,
            'startedAt', v_candidate.started_at,
            'countingCompletedAt',
              v_candidate.counting_completed_at,
            'stocktakeUpdatedAt',
              v_candidate.stocktake_updated_at,
            'stocktakeVersion',
              v_candidate.version_no
          );

          v_upsert_result :=
            notification.upsert_active_notification(
              p_organization_id => p_organization_id,
              p_rule_id => v_rule.id,
              p_entity_id => v_candidate.entity_id,
              p_deduplication_key =>
                'ACTIVE_RECOUNT_REQUIRED',
              p_stage_code => 'RECOUNT_REQUIRED',
              p_severity_code => 'HIGH',
              p_title => v_title,
              p_message => v_message,
              p_action_route => v_action_route,
              p_condition_started_at =>
                v_condition_started_at,
              p_observed_at => p_observed_at,
              p_due_at => null,
              p_source_snapshot => v_source_snapshot,
              p_stage_direction_code => 'UNCHANGED',
              p_correlation_id => p_correlation_id,
              p_process_name => v_process_name
            );

          v_action := v_upsert_result ->> 'action';

          if v_action in (
            'CREATED',
            'REOPENED_AS_NEW_EPISODE'
          ) then
            v_created_count := v_created_count + 1;
          elsif v_action in (
            'UPDATED',
            'SEEN_AGAIN'
          ) then
            v_updated_count := v_updated_count + 1;
          else
            raise exception using
              errcode = 'P0001',
              message =
                'STOCKTAKE_RECOUNT_UPSERT_ACTION_INVALID';
          end if;
        elsif v_active.id is not null then
          v_resolution_reason :=
            coalesce(
              v_resolution_reason,
              case
                when v_candidate.status_code = 'POSTED'
                  then 'SESSION_POSTED'
                when v_candidate.status_code = 'CANCELLED'
                  then 'SESSION_CANCELLED'
                when v_candidate.recount_required_line_count = 0
                  then 'RECOUNT_REQUIRED_LINE_COUNT_ZERO'
                else 'SOURCE_CONDITION_CLEARED'
              end
            );

          v_resolution_snapshot := jsonb_build_object(
            'schemaVersion', 1,
            'ruleRunId', v_rule_run_id,
            'resolutionReason', v_resolution_reason,
            'organizationTimezone',
              v_organization_timezone,
            'localDate', v_local_date,
            'stocktakeId', v_candidate.entity_id,
            'stocktakeNo', v_candidate.stocktake_no,
            'statusCode', v_candidate.status_code,
            'recountRequiredLineCount',
              v_candidate.recount_required_line_count,
            'stocktakeUpdatedAt',
              v_candidate.stocktake_updated_at,
            'stocktakeVersion',
              v_candidate.version_no
          );

          v_resolve_result :=
            notification.resolve_notification(
              p_organization_id => p_organization_id,
              p_notification_id => v_active.id,
              p_resolution_code =>
                'SOURCE_CONDITION_CLEARED',
              p_resolution_snapshot =>
                v_resolution_snapshot,
              p_resolved_at => p_observed_at,
              p_correlation_id => p_correlation_id,
              p_note => format(
                'Stocktake recount condition cleared: %s.',
                v_resolution_reason
              ),
              p_process_name => v_process_name
            );

          if v_resolve_result ->> 'action' in (
            'RESOLVED',
            'ALREADY_RESOLVED'
          ) then
            v_resolved_count :=
              v_resolved_count + 1;
          else
            raise exception using
              errcode = 'P0001',
              message =
                'STOCKTAKE_RECOUNT_RESOLUTION_ACTION_INVALID';
          end if;
        else
          v_skipped_count := v_skipped_count + 1;
        end if;
      exception
        when others then
          v_error_count := v_error_count + 1;

          if jsonb_array_length(v_error_items) < 100 then
            v_error_items :=
              v_error_items
              || jsonb_build_array(
                jsonb_build_object(
                  'entityId',
                  v_candidate.entity_id,
                  'sqlstate',
                  sqlstate,
                  'errorCode',
                  sqlerrm
                )
              );
          end if;
      end;
    end loop;

    v_completed_at := clock_timestamp();

    v_status_code :=
      case
        when v_error_count = 0 then 'SUCCEEDED'
        else 'PARTIALLY_FAILED'
      end;

    update notification.rule_runs run
    set
      status_code = v_status_code,
      completed_at = v_completed_at,
      evaluated_count = v_evaluated_count,
      created_count = v_created_count,
      updated_count = v_updated_count,
      resolved_count = v_resolved_count,
      skipped_count = v_skipped_count,
      error_count = v_error_count,
      summary = jsonb_build_object(
        'schemaVersion', 1,
        'ruleCode', v_rule.code,
        'ruleVersion', v_rule.version,
        'organizationTimezone',
          v_organization_timezone,
        'localDate', v_local_date,
        'observedAt', p_observed_at,
        'evaluatedCount', v_evaluated_count,
        'createdCount', v_created_count,
        'updatedCount', v_updated_count,
        'resolvedCount', v_resolved_count,
        'skippedCount', v_skipped_count,
        'errorCount', v_error_count
      ),
      error_code =
        case
          when v_error_count = 0 then null
          else 'STOCKTAKE_RECOUNT_ENTITY_EVALUATION_FAILED'
        end,
      error_detail =
        case
          when v_error_count = 0 then '{}'::jsonb
          else jsonb_build_object('items', v_error_items)
        end
    where run.id = v_rule_run_id
      and run.organization_id = p_organization_id;

    v_response := jsonb_build_object(
      'action', 'COMPLETED',
      'ruleRunId', v_rule_run_id,
      'ruleCode', v_rule.code,
      'ruleVersion', v_rule.version,
      'status', v_status_code,
      'localDate', v_local_date,
      'evaluatedCount', v_evaluated_count,
      'createdCount', v_created_count,
      'updatedCount', v_updated_count,
      'resolvedCount', v_resolved_count,
      'skippedCount', v_skipped_count,
      'errorCount', v_error_count
    );

    return v_response;
  exception
    when others then
      get stacked diagnostics
        v_error_sqlstate = returned_sqlstate,
        v_error_message = message_text;

      v_completed_at := clock_timestamp();

      update notification.rule_runs run
      set
        status_code = 'FAILED',
        completed_at = v_completed_at,
        evaluated_count = 0,
        created_count = 0,
        updated_count = 0,
        resolved_count = 0,
        skipped_count = 0,
        error_count = 1,
        summary = jsonb_build_object(
          'schemaVersion', 1,
          'ruleCode', v_rule.code,
          'ruleVersion', v_rule.version,
          'observedAt', p_observed_at,
          'failedAt', v_completed_at
        ),
        error_code = 'STOCKTAKE_RECOUNT_EVALUATION_FAILED',
        error_detail = jsonb_build_object(
          'sqlstate', v_error_sqlstate,
          'errorCode', v_error_message
        )
      where run.id = v_rule_run_id
        and run.organization_id = p_organization_id;

      return jsonb_build_object(
        'action', 'COMPLETED',
        'ruleRunId', v_rule_run_id,
        'ruleCode', v_rule.code,
        'ruleVersion', v_rule.version,
        'status', 'FAILED',
        'localDate', v_local_date,
        'evaluatedCount', 0,
        'createdCount', 0,
        'updatedCount', 0,
        'resolvedCount', 0,
        'skippedCount', 0,
        'errorCount', 1,
        'errorCode',
          'STOCKTAKE_RECOUNT_EVALUATION_FAILED',
        'errorDetail',
          jsonb_build_object(
            'sqlstate', v_error_sqlstate,
            'errorCode', v_error_message
          )
      );
  end;
end;
$$;

create or replace function notification.evaluate_stocktake_post_failures(
  p_organization_id uuid,
  p_idempotency_key text,
  p_observed_at timestamptz default clock_timestamp(),
  p_trigger_type_code text default 'SCHEDULED',
  p_correlation_id uuid default gen_random_uuid(),
  p_process_name text default 'notification.evaluate_stocktake_post_failures'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app, operations, reconciliation
as $$
declare
  v_idempotency_key text :=
    btrim(coalesce(p_idempotency_key, ''));
  v_trigger_type_code text :=
    upper(btrim(coalesce(p_trigger_type_code, '')));
  v_process_name text :=
    nullif(btrim(coalesce(p_process_name, '')), '');
  v_rule notification.rules%rowtype;
  v_existing_run notification.rule_runs%rowtype;
  v_active notification.notifications%rowtype;
  v_rule_run_id uuid;
  v_organization_timezone text;
  v_local_date date;
  v_posting_stale_minutes integer;
  v_candidate record;
  v_upsert_result jsonb;
  v_resolve_result jsonb;
  v_action text;
  v_stage_code text;
  v_stage_direction_code text;
  v_title text;
  v_message text;
  v_action_route text;
  v_condition_started_at timestamptz;
  v_source_snapshot jsonb;
  v_resolution_snapshot jsonb;
  v_resolution_reason text;
  v_old_stage_rank integer;
  v_new_stage_rank integer;
  v_evaluated_count integer := 0;
  v_created_count integer := 0;
  v_updated_count integer := 0;
  v_resolved_count integer := 0;
  v_skipped_count integer := 0;
  v_error_count integer := 0;
  v_error_items jsonb := '[]'::jsonb;
  v_status_code text;
  v_completed_at timestamptz;
  v_error_sqlstate text;
  v_error_message text;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if v_idempotency_key = '' then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_RULE_RUN_IDEMPOTENCY_REQUIRED';
  end if;

  if length(v_idempotency_key) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_RULE_RUN_IDEMPOTENCY_TOO_LONG';
  end if;

  if p_observed_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_OBSERVED_AT_REQUIRED';
  end if;

  if v_trigger_type_code not in (
    'SCHEDULED',
    'MANUAL',
    'EVENT_DRIVEN'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_POST_FAILURE_TRIGGER_TYPE_INVALID';
  end if;

  if p_correlation_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_CORRELATION_ID_REQUIRED';
  end if;

  if v_process_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_PROCESS_NAME_REQUIRED';
  end if;

  select organization.timezone
  into v_organization_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if v_organization_timezone is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_NOT_FOUND';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
      || ':NOTIFICATION_EVALUATOR:STOCKTAKE_POST_FAILED',
      0::bigint
    )
  );

  select run.*
  into v_existing_run
  from notification.rule_runs run
  where run.organization_id = p_organization_id
    and run.rule_code_snapshot = 'STOCKTAKE_POST_FAILED'
    and run.idempotency_key = v_idempotency_key
  for update;

  if v_existing_run.id is not null then
    return jsonb_build_object(
      'action', 'REPLAYED',
      'ruleRunId', v_existing_run.id,
      'ruleCode', v_existing_run.rule_code_snapshot,
      'ruleVersion', v_existing_run.rule_version_snapshot,
      'status', v_existing_run.status_code,
      'evaluatedCount', v_existing_run.evaluated_count,
      'createdCount', v_existing_run.created_count,
      'updatedCount', v_existing_run.updated_count,
      'resolvedCount', v_existing_run.resolved_count,
      'skippedCount', v_existing_run.skipped_count,
      'errorCount', v_existing_run.error_count,
      'summary', v_existing_run.summary
    );
  end if;

  perform notification.ensure_stocktake_post_failed_rule(
    p_organization_id,
    p_observed_at
  );

  select rule.*
  into strict v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'STOCKTAKE_POST_FAILED'
    and rule.is_active
    and rule.effective_from <= p_observed_at
    and (
      rule.effective_to is null
      or rule.effective_to > p_observed_at
    )
  order by
    rule.effective_from desc,
    rule.created_at desc,
    rule.id desc
  limit 1;

  insert into notification.rule_runs (
    organization_id,
    rule_id,
    rule_code_snapshot,
    rule_version_snapshot,
    trigger_type_code,
    triggered_by_outbox_event_id,
    idempotency_key,
    status_code,
    started_at,
    completed_at,
    evaluated_count,
    created_count,
    updated_count,
    resolved_count,
    skipped_count,
    error_count,
    summary,
    error_code,
    error_detail,
    correlation_id,
    actor_user_id,
    process_name,
    created_at
  )
  values (
    p_organization_id,
    v_rule.id,
    v_rule.code,
    v_rule.version,
    v_trigger_type_code,
    null,
    v_idempotency_key,
    'STARTED',
    clock_timestamp(),
    null,
    0,
    0,
    0,
    0,
    0,
    0,
    '{}'::jsonb,
    null,
    '{}'::jsonb,
    p_correlation_id,
    null,
    v_process_name,
    clock_timestamp()
  )
  returning id into v_rule_run_id;

  begin
    begin
      v_posting_stale_minutes :=
        (v_rule.config ->> 'postingStaleMinutes')::integer;
    exception
      when others then
        raise exception using
          errcode = 'P0001',
          message =
            'STOCKTAKE_POST_FAILURE_RULE_CONFIG_INVALID';
    end;

    if v_posting_stale_minutes is null
       or v_posting_stale_minutes <= 0
       or v_posting_stale_minutes > 10080
       or v_rule.config ->> 'severityCode'
            is distinct from 'CRITICAL'
       or jsonb_typeof(v_rule.config -> 'stages')
            is distinct from 'array'
       or not exists (
         select 1
         from jsonb_array_elements(
           v_rule.config -> 'stages'
         ) stage(item)
         where stage.item ->> 'code' = 'RESULT_UNCERTAIN'
       )
       or not exists (
         select 1
         from jsonb_array_elements(
           v_rule.config -> 'stages'
         ) stage(item)
         where stage.item ->> 'code' =
               'RECONCILIATION_FAILED'
       ) then
      raise exception using
        errcode = 'P0001',
        message = 'STOCKTAKE_POST_FAILURE_RULE_CONFIG_INVALID';
    end if;

    v_local_date :=
      (p_observed_at at time zone v_organization_timezone)::date;

    for v_candidate in
      with source_rows as (
        select
          stocktake.id as entity_id,
          stocktake.stocktake_no,
          stocktake.title,
          stocktake.stocktake_type_code,
          stocktake.mode_code,
          stocktake.visibility_code,
          stocktake.status_code,
          stocktake.scope_definition,
          stocktake.tolerance_policy_snapshot,
          stocktake.rule_version,
          stocktake.timezone_snapshot,
          stocktake.planned_at,
          stocktake.snapshot_ledger_seq,
          stocktake.started_at,
          stocktake.counting_completed_at,
          stocktake.approved_at,
          stocktake.posted_at,
          stocktake.stock_transaction_id,
          stocktake.reconciliation_run_id,
          stocktake.current_approval_id,
          stocktake.approval_version_no,
          stocktake.note,
          stocktake.metadata,
          stocktake.created_at as stocktake_created_at,
          stocktake.updated_at as stocktake_updated_at,
          stocktake.version_no,
          reconciliation_run.run_no
            as reconciliation_run_no,
          reconciliation_run.status_code
            as reconciliation_status_code,
          reconciliation_run.started_at
            as reconciliation_started_at,
          reconciliation_run.completed_at
            as reconciliation_completed_at,
          reconciliation_run.error_code
            as reconciliation_error_code,
          reconciliation_run.error_detail
            as reconciliation_error_detail,
          reconciliation_run.summary
            as reconciliation_summary,
          reconciliation_run.updated_at
            as reconciliation_updated_at,
          false as source_missing
        from operations.stocktakes stocktake
        left join reconciliation.runs reconciliation_run
          on reconciliation_run.organization_id =
             stocktake.organization_id
         and reconciliation_run.id =
             stocktake.reconciliation_run_id
        where stocktake.organization_id =
              p_organization_id
      ),
      active_without_source as (
        select notification_row.entity_id
        from notification.notifications notification_row
        where notification_row.organization_id =
              p_organization_id
          and notification_row.rule_code_snapshot =
              v_rule.code
          and notification_row.entity_type_code =
              'STOCKTAKE'
          and notification_row.lifecycle_status_code in (
            'OPEN',
            'ACKNOWLEDGED'
          )
          and not exists (
            select 1
            from source_rows source_row
            where source_row.entity_id =
                  notification_row.entity_id
          )
      )
      select
        source_row.entity_id,
        source_row.stocktake_no,
        source_row.title,
        source_row.stocktake_type_code,
        source_row.mode_code,
        source_row.visibility_code,
        source_row.status_code,
        source_row.scope_definition,
        source_row.tolerance_policy_snapshot,
        source_row.rule_version,
        source_row.timezone_snapshot,
        source_row.planned_at,
        source_row.snapshot_ledger_seq,
        source_row.started_at,
        source_row.counting_completed_at,
        source_row.approved_at,
        source_row.posted_at,
        source_row.stock_transaction_id,
        source_row.reconciliation_run_id,
        source_row.current_approval_id,
        source_row.approval_version_no,
        source_row.note,
        source_row.metadata,
        source_row.stocktake_created_at,
        source_row.stocktake_updated_at,
        source_row.version_no,
        source_row.reconciliation_run_no,
        source_row.reconciliation_status_code,
        source_row.reconciliation_started_at,
        source_row.reconciliation_completed_at,
        source_row.reconciliation_error_code,
        source_row.reconciliation_error_detail,
        source_row.reconciliation_summary,
        source_row.reconciliation_updated_at,
        source_row.source_missing
      from source_rows source_row

      union all

      select
        orphan.entity_id,
        null::text,
        null::text,
        null::text,
        null::text,
        null::text,
        null::text,
        '{}'::jsonb,
        '{}'::jsonb,
        null::text,
        null::text,
        null::timestamptz,
        null::bigint,
        null::timestamptz,
        null::timestamptz,
        null::timestamptz,
        null::timestamptz,
        null::uuid,
        null::uuid,
        null::uuid,
        null::bigint,
        null::text,
        '{}'::jsonb,
        null::timestamptz,
        null::timestamptz,
        null::bigint,
        null::text,
        null::text,
        null::timestamptz,
        null::timestamptz,
        null::text,
        null::jsonb,
        null::jsonb,
        null::timestamptz,
        true
      from active_without_source orphan
      order by entity_id
    loop
      v_evaluated_count := v_evaluated_count + 1;

      begin
        select notification_row.*
        into v_active
        from notification.notifications notification_row
        where notification_row.organization_id =
              p_organization_id
          and notification_row.rule_code_snapshot =
              v_rule.code
          and notification_row.entity_type_code =
              'STOCKTAKE'
          and notification_row.entity_id =
              v_candidate.entity_id
          and notification_row.lifecycle_status_code in (
            'OPEN',
            'ACKNOWLEDGED'
          )
        order by notification_row.episode_no desc
        limit 1
        for update;

        v_stage_code := null;
        v_stage_direction_code := 'UNCHANGED';
        v_title := null;
        v_message := null;
        v_action_route := null;
        v_condition_started_at := null;
        v_source_snapshot := '{}'::jsonb;
        v_resolution_snapshot := '{}'::jsonb;
        v_resolution_reason := null;

        if v_candidate.source_missing then
          v_resolution_reason := 'SOURCE_ENTITY_MISSING';
        elsif v_candidate.status_code = 'CANCELLED' then
          v_resolution_reason := 'SESSION_CANCELLED';
        elsif v_candidate.reconciliation_status_code = 'FAILED' then
          v_stage_code := 'RECONCILIATION_FAILED';
          v_condition_started_at :=
            coalesce(
              v_candidate.reconciliation_completed_at,
              v_candidate.reconciliation_updated_at,
              v_candidate.stocktake_updated_at
            );
        elsif v_candidate.status_code = 'EXCEPTION' then
          v_stage_code := 'RESULT_UNCERTAIN';
          v_condition_started_at :=
            v_candidate.stocktake_updated_at;
        elsif v_candidate.status_code = 'POSTING'
              and v_candidate.stocktake_updated_at
                  <= p_observed_at
                     - make_interval(
                         mins => v_posting_stale_minutes
                       ) then
          v_stage_code := 'RESULT_UNCERTAIN';
          v_condition_started_at :=
            v_candidate.stocktake_updated_at;
        end if;

        if v_stage_code is not null then
          if v_condition_started_at is null
             or v_condition_started_at > p_observed_at then
            raise exception using
              errcode = 'P0001',
              message =
                'STOCKTAKE_POST_FAILURE_CONDITION_TIME_INVALID';
          end if;

          v_old_stage_rank :=
            case v_active.stage_code
              when 'RESULT_UNCERTAIN' then 1
              when 'RECONCILIATION_FAILED' then 2
              else null
            end;

          v_new_stage_rank :=
            case v_stage_code
              when 'RESULT_UNCERTAIN' then 1
              when 'RECONCILIATION_FAILED' then 2
            end;

          if v_active.id is not null then
            if v_old_stage_rank is null then
              raise exception using
                errcode = 'P0001',
                message =
                  'STOCKTAKE_POST_FAILURE_ACTIVE_STAGE_INVALID';
            elsif v_new_stage_rank > v_old_stage_rank then
              v_stage_direction_code := 'ESCALATED';
            elsif v_new_stage_rank < v_old_stage_rank then
              v_stage_direction_code := 'DEESCALATED';
            end if;
          end if;

          if v_stage_code = 'RECONCILIATION_FAILED' then
            v_title :=
              'Post-stocktake reconciliation gagal';
            v_message := format(
              'Stocktake %s memiliki post-reconciliation gagal%s.',
              v_candidate.stocktake_no,
              case
                when nullif(
                  btrim(
                    coalesce(
                      v_candidate.reconciliation_error_code,
                      ''
                    )
                  ),
                  ''
                ) is null
                  then ''
                else
                  ' dengan error '
                  || v_candidate.reconciliation_error_code
              end
            );
          else
            v_title := 'Hasil posting stocktake tidak pasti';
            v_message := format(
              'Stocktake %s berada pada status %s dan memerlukan verifikasi aman.',
              v_candidate.stocktake_no,
              v_candidate.status_code
            );
          end if;

          v_action_route :=
            '/admin/stocktakes/'
            || v_candidate.entity_id::text;

          v_source_snapshot := jsonb_build_object(
            'schemaVersion', 1,
            'organizationTimezone',
              v_organization_timezone,
            'localDate', v_local_date,
            'postingStaleMinutes',
              v_posting_stale_minutes,
            'stocktakeId', v_candidate.entity_id,
            'stocktakeNo', v_candidate.stocktake_no,
            'title', v_candidate.title,
            'stocktakeTypeCode',
              v_candidate.stocktake_type_code,
            'modeCode', v_candidate.mode_code,
            'visibilityCode',
              v_candidate.visibility_code,
            'statusCode', v_candidate.status_code,
            'scopeDefinition',
              v_candidate.scope_definition,
            'tolerancePolicySnapshot',
              v_candidate.tolerance_policy_snapshot,
            'ruleVersion', v_candidate.rule_version,
            'timezoneSnapshot',
              v_candidate.timezone_snapshot,
            'plannedAt', v_candidate.planned_at,
            'snapshotLedgerSeq',
              v_candidate.snapshot_ledger_seq,
            'startedAt', v_candidate.started_at,
            'countingCompletedAt',
              v_candidate.counting_completed_at,
            'approvedAt', v_candidate.approved_at,
            'postedAt', v_candidate.posted_at,
            'stockTransactionId',
              v_candidate.stock_transaction_id,
            'currentApprovalId',
              v_candidate.current_approval_id,
            'approvalVersion',
              v_candidate.approval_version_no,
            'reconciliationRunId',
              v_candidate.reconciliation_run_id,
            'reconciliationRunNo',
              v_candidate.reconciliation_run_no,
            'reconciliationStatusCode',
              v_candidate.reconciliation_status_code,
            'reconciliationStartedAt',
              v_candidate.reconciliation_started_at,
            'reconciliationCompletedAt',
              v_candidate.reconciliation_completed_at,
            'reconciliationErrorCode',
              v_candidate.reconciliation_error_code,
            'reconciliationErrorDetail',
              v_candidate.reconciliation_error_detail,
            'reconciliationSummary',
              v_candidate.reconciliation_summary,
            'metadata', v_candidate.metadata,
            'stocktakeUpdatedAt',
              v_candidate.stocktake_updated_at,
            'stocktakeVersion',
              v_candidate.version_no,
            'stageCode', v_stage_code
          );

          v_upsert_result :=
            notification.upsert_active_notification(
              p_organization_id => p_organization_id,
              p_rule_id => v_rule.id,
              p_entity_id => v_candidate.entity_id,
              p_deduplication_key =>
                'ACTIVE_POST_FAILURE',
              p_stage_code => v_stage_code,
              p_severity_code => 'CRITICAL',
              p_title => v_title,
              p_message => v_message,
              p_action_route => v_action_route,
              p_condition_started_at =>
                v_condition_started_at,
              p_observed_at => p_observed_at,
              p_due_at => null,
              p_source_snapshot => v_source_snapshot,
              p_stage_direction_code =>
                v_stage_direction_code,
              p_correlation_id => p_correlation_id,
              p_process_name => v_process_name
            );

          v_action := v_upsert_result ->> 'action';

          if v_action in (
            'CREATED',
            'REOPENED_AS_NEW_EPISODE'
          ) then
            v_created_count := v_created_count + 1;
          elsif v_action in (
            'UPDATED',
            'SEEN_AGAIN'
          ) then
            v_updated_count := v_updated_count + 1;
          else
            raise exception using
              errcode = 'P0001',
              message =
                'STOCKTAKE_POST_FAILURE_UPSERT_ACTION_INVALID';
          end if;
        elsif v_active.id is not null then
          v_resolution_reason :=
            coalesce(
              v_resolution_reason,
              case
                when v_candidate.status_code = 'CANCELLED'
                  then 'SESSION_CANCELLED'
                when v_candidate.status_code = 'POSTED'
                     and coalesce(
                       v_candidate.reconciliation_status_code,
                       'SUCCEEDED'
                     ) <> 'FAILED'
                  then 'POSTING_COMPLETED'
                when v_candidate.status_code = 'APPROVED'
                  then 'SESSION_RETURNED_TO_APPROVED'
                when v_candidate.status_code = 'POSTING'
                  then 'POSTING_NO_LONGER_STALE'
                when v_candidate.reconciliation_status_code
                     is not null
                     and v_candidate.reconciliation_status_code
                         <> 'FAILED'
                  then 'RECONCILIATION_RECOVERED'
                else 'SOURCE_CONDITION_CLEARED'
              end
            );

          v_resolution_snapshot := jsonb_build_object(
            'schemaVersion', 1,
            'ruleRunId', v_rule_run_id,
            'resolutionReason', v_resolution_reason,
            'organizationTimezone',
              v_organization_timezone,
            'localDate', v_local_date,
            'postingStaleMinutes',
              v_posting_stale_minutes,
            'stocktakeId', v_candidate.entity_id,
            'stocktakeNo', v_candidate.stocktake_no,
            'statusCode', v_candidate.status_code,
            'stockTransactionId',
              v_candidate.stock_transaction_id,
            'reconciliationRunId',
              v_candidate.reconciliation_run_id,
            'reconciliationStatusCode',
              v_candidate.reconciliation_status_code,
            'reconciliationErrorCode',
              v_candidate.reconciliation_error_code,
            'stocktakeUpdatedAt',
              v_candidate.stocktake_updated_at,
            'stocktakeVersion',
              v_candidate.version_no
          );

          v_resolve_result :=
            notification.resolve_notification(
              p_organization_id => p_organization_id,
              p_notification_id => v_active.id,
              p_resolution_code =>
                'SOURCE_CONDITION_CLEARED',
              p_resolution_snapshot =>
                v_resolution_snapshot,
              p_resolved_at => p_observed_at,
              p_correlation_id => p_correlation_id,
              p_note => format(
                'Stocktake post failure condition cleared: %s.',
                v_resolution_reason
              ),
              p_process_name => v_process_name
            );

          if v_resolve_result ->> 'action' in (
            'RESOLVED',
            'ALREADY_RESOLVED'
          ) then
            v_resolved_count :=
              v_resolved_count + 1;
          else
            raise exception using
              errcode = 'P0001',
              message =
                'STOCKTAKE_POST_FAILURE_RESOLUTION_ACTION_INVALID';
          end if;
        else
          v_skipped_count := v_skipped_count + 1;
        end if;
      exception
        when others then
          v_error_count := v_error_count + 1;

          if jsonb_array_length(v_error_items) < 100 then
            v_error_items :=
              v_error_items
              || jsonb_build_array(
                jsonb_build_object(
                  'entityId',
                  v_candidate.entity_id,
                  'sqlstate',
                  sqlstate,
                  'errorCode',
                  sqlerrm
                )
              );
          end if;
      end;
    end loop;

    v_completed_at := clock_timestamp();

    v_status_code :=
      case
        when v_error_count = 0 then 'SUCCEEDED'
        else 'PARTIALLY_FAILED'
      end;

    update notification.rule_runs run
    set
      status_code = v_status_code,
      completed_at = v_completed_at,
      evaluated_count = v_evaluated_count,
      created_count = v_created_count,
      updated_count = v_updated_count,
      resolved_count = v_resolved_count,
      skipped_count = v_skipped_count,
      error_count = v_error_count,
      summary = jsonb_build_object(
        'schemaVersion', 1,
        'ruleCode', v_rule.code,
        'ruleVersion', v_rule.version,
        'organizationTimezone',
          v_organization_timezone,
        'localDate', v_local_date,
        'observedAt', p_observed_at,
        'postingStaleMinutes',
          v_posting_stale_minutes,
        'evaluatedCount', v_evaluated_count,
        'createdCount', v_created_count,
        'updatedCount', v_updated_count,
        'resolvedCount', v_resolved_count,
        'skippedCount', v_skipped_count,
        'errorCount', v_error_count
      ),
      error_code =
        case
          when v_error_count = 0 then null
          else
            'STOCKTAKE_POST_FAILURE_ENTITY_EVALUATION_FAILED'
        end,
      error_detail =
        case
          when v_error_count = 0 then '{}'::jsonb
          else jsonb_build_object('items', v_error_items)
        end
    where run.id = v_rule_run_id
      and run.organization_id = p_organization_id;

    v_response := jsonb_build_object(
      'action', 'COMPLETED',
      'ruleRunId', v_rule_run_id,
      'ruleCode', v_rule.code,
      'ruleVersion', v_rule.version,
      'status', v_status_code,
      'localDate', v_local_date,
      'postingStaleMinutes',
        v_posting_stale_minutes,
      'evaluatedCount', v_evaluated_count,
      'createdCount', v_created_count,
      'updatedCount', v_updated_count,
      'resolvedCount', v_resolved_count,
      'skippedCount', v_skipped_count,
      'errorCount', v_error_count
    );

    return v_response;
  exception
    when others then
      get stacked diagnostics
        v_error_sqlstate = returned_sqlstate,
        v_error_message = message_text;

      v_completed_at := clock_timestamp();

      update notification.rule_runs run
      set
        status_code = 'FAILED',
        completed_at = v_completed_at,
        evaluated_count = 0,
        created_count = 0,
        updated_count = 0,
        resolved_count = 0,
        skipped_count = 0,
        error_count = 1,
        summary = jsonb_build_object(
          'schemaVersion', 1,
          'ruleCode', v_rule.code,
          'ruleVersion', v_rule.version,
          'observedAt', p_observed_at,
          'failedAt', v_completed_at
        ),
        error_code =
          'STOCKTAKE_POST_FAILURE_EVALUATION_FAILED',
        error_detail = jsonb_build_object(
          'sqlstate', v_error_sqlstate,
          'errorCode', v_error_message
        )
      where run.id = v_rule_run_id
        and run.organization_id = p_organization_id;

      return jsonb_build_object(
        'action', 'COMPLETED',
        'ruleRunId', v_rule_run_id,
        'ruleCode', v_rule.code,
        'ruleVersion', v_rule.version,
        'status', 'FAILED',
        'localDate', v_local_date,
        'evaluatedCount', 0,
        'createdCount', 0,
        'updatedCount', 0,
        'resolvedCount', 0,
        'skippedCount', 0,
        'errorCount', 1,
        'errorCode',
          'STOCKTAKE_POST_FAILURE_EVALUATION_FAILED',
        'errorDetail',
          jsonb_build_object(
            'sqlstate', v_error_sqlstate,
            'errorCode', v_error_message
          )
      );
  end;
end;
$$;

revoke all
on function notification.ensure_stocktake_recount_rule(
  uuid,
  timestamptz
)
from public, anon, authenticated;

revoke all
on function notification.ensure_stocktake_post_failed_rule(
  uuid,
  timestamptz
)
from public, anon, authenticated;

revoke all
on function notification.evaluate_stocktake_recounts(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
from public, anon, authenticated;

revoke all
on function notification.evaluate_stocktake_post_failures(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
from public, anon, authenticated;

grant execute
on function notification.ensure_stocktake_recount_rule(
  uuid,
  timestamptz
)
to service_role;

grant execute
on function notification.ensure_stocktake_post_failed_rule(
  uuid,
  timestamptz
)
to service_role;

grant execute
on function notification.evaluate_stocktake_recounts(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
to service_role;

grant execute
on function notification.evaluate_stocktake_post_failures(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
to service_role;

commit;
