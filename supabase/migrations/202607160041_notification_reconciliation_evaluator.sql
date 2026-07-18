begin;

create or replace function notification.ensure_reconciliation_issue_rule(
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
      message = 'RECONCILIATION_ISSUE_RULE_EFFECTIVE_TIME_REQUIRED';
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
      || ':NOTIFICATION_RULE:RECONCILIATION_ISSUE_HIGH_CRITICAL',
      0::bigint
    )
  );

  select rule.*
  into v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'RECONCILIATION_ISSUE_HIGH_CRITICAL'
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
        message = 'RECONCILIATION_ISSUE_RULE_NOT_ACTIVE';
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
    'RECONCILIATION_ISSUE_HIGH_CRITICAL',
    '1.0.0',
    'RECONCILIATION',
    'HYBRID',
    'RECONCILIATION_ISSUE',
    'SOURCE_SEVERITY_V1',
    'SOURCE_SEVERITY_STAGE_V1',
    'OPEN_HIGH_OR_CRITICAL_V1',
    'SOURCE_CONDITION_CLEARED_V1',
    '1.0.0',
    'OPEN_RECONCILIATION_ISSUE_DETAIL',
    jsonb_build_object(
      'eligibleSeverities',
      jsonb_build_array('HIGH', 'CRITICAL'),
      'stages',
      jsonb_build_array(
        jsonb_build_object(
          'code', 'HIGH',
          'severity', 'HIGH',
          'rank', 1
        ),
        jsonb_build_object(
          'code', 'CRITICAL',
          'severity', 'CRITICAL',
          'rank', 2
        )
      ),
      'activeStatusCode',
      'OPEN',
      'conditionStartedAt',
      'ISSUE_FIRST_SEEN_AT',
      'resolutionConditions',
      jsonb_build_array(
        'ISSUE_RESOLVED',
        'SEVERITY_BELOW_HIGH',
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

create or replace function notification.ensure_reconciliation_run_failed_rule(
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
      message = 'RECONCILIATION_FAILURE_RULE_EFFECTIVE_TIME_REQUIRED';
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
      || ':NOTIFICATION_RULE:RECONCILIATION_RUN_FAILED',
      0::bigint
    )
  );

  select rule.*
  into v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'RECONCILIATION_RUN_FAILED'
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
        message = 'RECONCILIATION_FAILURE_RULE_NOT_ACTIVE';
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
    'RECONCILIATION_RUN_FAILED',
    '1.0.0',
    'RECONCILIATION',
    'HYBRID',
    'RECONCILIATION_RUN',
    'FIXED_CRITICAL_V1',
    'FIXED_FAILED_STAGE_V1',
    'RUN_STATUS_FAILED_WITHOUT_SUCCESSFUL_RETRY_V1',
    'RUN_RECOVERED_OR_RETRIED_SUCCESSFULLY_V1',
    '1.0.0',
    'OPEN_RECONCILIATION_RUN_DETAIL',
    jsonb_build_object(
      'failedStatusCode',
      'FAILED',
      'resolvedStatusCode',
      'SUCCEEDED',
      'stageCode',
      'FAILED',
      'severityCode',
      'CRITICAL',
      'successfulRetryMetadataKey',
      'retryOfRunId',
      'conditionStartedAt',
      'RUN_COMPLETED_AT',
      'resolutionConditions',
      jsonb_build_array(
        'RUN_STATUS_RECOVERED',
        'SUCCESSFUL_RETRY_FOUND',
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

create or replace function notification.evaluate_reconciliation_issues(
  p_organization_id uuid,
  p_idempotency_key text,
  p_observed_at timestamptz default clock_timestamp(),
  p_trigger_type_code text default 'SCHEDULED',
  p_correlation_id uuid default gen_random_uuid(),
  p_process_name text default 'notification.evaluate_reconciliation_issues'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app, reconciliation, catalog
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
  v_previous notification.notifications%rowtype;
  v_rule_run_id uuid;
  v_organization_timezone text;
  v_local_date date;
  v_eligible_severities text[];
  v_candidate record;
  v_upsert_result jsonb;
  v_resolve_result jsonb;
  v_action text;
  v_stage_code text;
  v_severity_code text;
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
      message = 'RECONCILIATION_ISSUE_TRIGGER_TYPE_INVALID';
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
      || ':NOTIFICATION_EVALUATOR:RECONCILIATION_ISSUE_HIGH_CRITICAL',
      0::bigint
    )
  );

  select run.*
  into v_existing_run
  from notification.rule_runs run
  where run.organization_id = p_organization_id
    and run.rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
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

  perform notification.ensure_reconciliation_issue_rule(
    p_organization_id,
    p_observed_at
  );

  select rule.*
  into strict v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'RECONCILIATION_ISSUE_HIGH_CRITICAL'
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
      if jsonb_typeof(v_rule.config -> 'eligibleSeverities')
           is distinct from 'array'
         or jsonb_array_length(
           v_rule.config -> 'eligibleSeverities'
         ) is distinct from 2 then
        raise exception using
          errcode = 'P0001',
          message = 'RECONCILIATION_ISSUE_RULE_CONFIG_INVALID';
      end if;

      select array_agg(
        upper(btrim(severity.value))
        order by severity.ordinality
      )
      into v_eligible_severities
      from jsonb_array_elements_text(
        v_rule.config -> 'eligibleSeverities'
      ) with ordinality as severity(value, ordinality);
    exception
      when others then
        raise exception using
          errcode = 'P0001',
          message = 'RECONCILIATION_ISSUE_RULE_CONFIG_INVALID';
    end;

    if cardinality(v_eligible_severities) is distinct from 2
       or not ('HIGH' = any(v_eligible_severities))
       or not ('CRITICAL' = any(v_eligible_severities)) then
      raise exception using
        errcode = 'P0001',
        message = 'RECONCILIATION_ISSUE_RULE_CONFIG_INVALID';
    end if;

    v_local_date :=
      (p_observed_at at time zone v_organization_timezone)::date;

    for v_candidate in
      with source_rows as (
        select
          issue.id as entity_id,
          issue.fingerprint,
          issue.check_code,
          issue.rule_version,
          issue.status_code,
          issue.severity_code,
          issue.entity_type_code,
          issue.entity_key,
          issue.product_id,
          issue.batch_id,
          issue.source_type_code,
          issue.source_ref,
          issue.expected_value,
          issue.actual_value,
          issue.difference_value,
          issue.first_seen_run_id,
          first_run.run_no as first_seen_run_no,
          issue.last_seen_run_id,
          last_run.run_no as last_seen_run_no,
          issue.first_seen_at,
          issue.last_seen_at,
          issue.recurrence_count,
          issue.resolved_at,
          issue.resolution_code,
          issue.resolution_note,
          issue.updated_at as issue_updated_at,
          product.sku as product_sku,
          product.name as product_name,
          batch.batch_code,
          false as source_missing
        from reconciliation.issues issue
        join reconciliation.runs first_run
          on first_run.organization_id = issue.organization_id
         and first_run.id = issue.first_seen_run_id
        join reconciliation.runs last_run
          on last_run.organization_id = issue.organization_id
         and last_run.id = issue.last_seen_run_id
        left join catalog.products product
          on product.organization_id = issue.organization_id
         and product.id = issue.product_id
        left join catalog.product_batches batch
          on batch.organization_id = issue.organization_id
         and batch.product_id = issue.product_id
         and batch.id = issue.batch_id
        where issue.organization_id = p_organization_id
      ),
      active_without_source as (
        select notification_row.entity_id
        from notification.notifications notification_row
        where notification_row.organization_id = p_organization_id
          and notification_row.rule_code_snapshot = v_rule.code
          and notification_row.entity_type_code =
            'RECONCILIATION_ISSUE'
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
        source_row.fingerprint,
        source_row.check_code,
        source_row.rule_version,
        source_row.status_code,
        source_row.severity_code,
        source_row.entity_type_code,
        source_row.entity_key,
        source_row.product_id,
        source_row.batch_id,
        source_row.source_type_code,
        source_row.source_ref,
        source_row.expected_value,
        source_row.actual_value,
        source_row.difference_value,
        source_row.first_seen_run_id,
        source_row.first_seen_run_no,
        source_row.last_seen_run_id,
        source_row.last_seen_run_no,
        source_row.first_seen_at,
        source_row.last_seen_at,
        source_row.recurrence_count,
        source_row.resolved_at,
        source_row.resolution_code,
        source_row.resolution_note,
        source_row.issue_updated_at,
        source_row.product_sku,
        source_row.product_name,
        source_row.batch_code,
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
        null::uuid,
        null::uuid,
        null::text,
        null::text,
        null::jsonb,
        null::jsonb,
        null::jsonb,
        null::uuid,
        null::text,
        null::uuid,
        null::text,
        null::timestamptz,
        null::timestamptz,
        null::bigint,
        null::timestamptz,
        null::text,
        null::text,
        null::timestamptz,
        null::text,
        null::text,
        null::text,
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
              'RECONCILIATION_ISSUE'
          and notification_row.entity_id =
              v_candidate.entity_id
          and notification_row.lifecycle_status_code in (
            'OPEN',
            'ACKNOWLEDGED'
          )
        order by notification_row.episode_no desc
        limit 1
        for update;

        select notification_row.*
        into v_previous
        from notification.notifications notification_row
        where notification_row.organization_id =
              p_organization_id
          and notification_row.rule_code_snapshot =
              v_rule.code
          and notification_row.entity_type_code =
              'RECONCILIATION_ISSUE'
          and notification_row.entity_id =
              v_candidate.entity_id
        order by notification_row.episode_no desc
        limit 1;

        v_stage_code := null;
        v_severity_code := null;
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
        elsif v_candidate.status_code = 'OPEN'
              and v_candidate.severity_code = any(
                v_eligible_severities
              ) then
          if v_candidate.first_seen_at is null
             or v_candidate.first_seen_at > p_observed_at then
            raise exception using
              errcode = 'P0001',
              message =
                'RECONCILIATION_ISSUE_CONDITION_TIME_INVALID';
          end if;

          v_stage_code := v_candidate.severity_code;
          v_severity_code := v_candidate.severity_code;
          v_condition_started_at :=
            case
              when v_active.id is not null then
                v_active.condition_started_at
              when v_previous.id is not null
                   and v_previous.lifecycle_status_code = 'RESOLVED'
                then greatest(
                  v_candidate.last_seen_at,
                  coalesce(
                    v_previous.resolved_at,
                    v_candidate.last_seen_at
                  )
                )
              else v_candidate.first_seen_at
            end;

          v_old_stage_rank :=
            case v_active.stage_code
              when 'HIGH' then 1
              when 'CRITICAL' then 2
              else null
            end;

          v_new_stage_rank :=
            case v_stage_code
              when 'HIGH' then 1
              when 'CRITICAL' then 2
            end;

          if v_active.id is not null then
            if v_old_stage_rank is null then
              raise exception using
                errcode = 'P0001',
                message =
                  'RECONCILIATION_ISSUE_ACTIVE_STAGE_INVALID';
            elsif v_new_stage_rank > v_old_stage_rank then
              v_stage_direction_code := 'ESCALATED';
            elsif v_new_stage_rank < v_old_stage_rank then
              v_stage_direction_code := 'DEESCALATED';
            end if;
          end if;

          if v_stage_code = 'CRITICAL' then
            v_title := 'Issue rekonsiliasi kritis';
          else
            v_title := 'Issue rekonsiliasi prioritas tinggi';
          end if;

          v_message := format(
            'Issue %s pada %s masih OPEN dengan severity %s.',
            v_candidate.check_code,
            v_candidate.entity_type_code,
            v_candidate.severity_code
          );

          v_action_route :=
            '/reconciliation?issueId='
            || v_candidate.entity_id::text;

          v_source_snapshot := jsonb_build_object(
            'schemaVersion', 1,
            'organizationTimezone', v_organization_timezone,
            'localDate', v_local_date,
            'issueId', v_candidate.entity_id,
            'fingerprint', v_candidate.fingerprint,
            'checkCode', v_candidate.check_code,
            'ruleVersion', v_candidate.rule_version,
            'statusCode', v_candidate.status_code,
            'severityCode', v_candidate.severity_code,
            'entityTypeCode', v_candidate.entity_type_code,
            'entityKey', v_candidate.entity_key,
            'productId', v_candidate.product_id,
            'productSku', v_candidate.product_sku,
            'productName', v_candidate.product_name,
            'batchId', v_candidate.batch_id,
            'batchCode', v_candidate.batch_code,
            'sourceTypeCode', v_candidate.source_type_code,
            'sourceRef', v_candidate.source_ref,
            'expectedValue', v_candidate.expected_value,
            'actualValue', v_candidate.actual_value,
            'differenceValue', v_candidate.difference_value,
            'firstSeenRunId', v_candidate.first_seen_run_id,
            'firstSeenRunNo', v_candidate.first_seen_run_no,
            'lastSeenRunId', v_candidate.last_seen_run_id,
            'lastSeenRunNo', v_candidate.last_seen_run_no,
            'firstSeenAt', v_candidate.first_seen_at,
            'lastSeenAt', v_candidate.last_seen_at,
            'recurrenceCount', v_candidate.recurrence_count,
            'issueUpdatedAt', v_candidate.issue_updated_at
          );

          v_upsert_result :=
            notification.upsert_active_notification(
              p_organization_id => p_organization_id,
              p_rule_id => v_rule.id,
              p_entity_id => v_candidate.entity_id,
              p_deduplication_key =>
                'ACTIVE_HIGH_CRITICAL_ISSUE',
              p_stage_code => v_stage_code,
              p_severity_code => v_severity_code,
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
                'RECONCILIATION_ISSUE_UPSERT_ACTION_INVALID';
          end if;
        elsif v_active.id is not null then
          v_resolution_reason :=
            coalesce(
              v_resolution_reason,
              case
                when v_candidate.status_code = 'RESOLVED'
                  then 'ISSUE_RESOLVED'
                when v_candidate.severity_code not in (
                  'HIGH',
                  'CRITICAL'
                )
                  then 'SEVERITY_BELOW_HIGH'
                else 'SOURCE_CONDITION_CLEARED'
              end
            );

          v_resolution_snapshot := jsonb_build_object(
            'schemaVersion', 1,
            'ruleRunId', v_rule_run_id,
            'resolutionReason', v_resolution_reason,
            'organizationTimezone', v_organization_timezone,
            'localDate', v_local_date,
            'issueId', v_candidate.entity_id,
            'fingerprint', v_candidate.fingerprint,
            'checkCode', v_candidate.check_code,
            'statusCode', v_candidate.status_code,
            'severityCode', v_candidate.severity_code,
            'lastSeenRunId', v_candidate.last_seen_run_id,
            'lastSeenRunNo', v_candidate.last_seen_run_no,
            'lastSeenAt', v_candidate.last_seen_at,
            'sourceResolvedAt', v_candidate.resolved_at,
            'sourceResolutionCode',
              v_candidate.resolution_code,
            'sourceResolutionNote',
              v_candidate.resolution_note
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
                'Reconciliation issue condition cleared: %s.',
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
                'RECONCILIATION_ISSUE_RESOLUTION_ACTION_INVALID';
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
        'organizationTimezone', v_organization_timezone,
        'localDate', v_local_date,
        'observedAt', p_observed_at,
        'eligibleSeverities',
          to_jsonb(v_eligible_severities),
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
          else 'RECONCILIATION_ISSUE_ENTITY_EVALUATION_FAILED'
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
        error_code =
          'RECONCILIATION_ISSUE_EVALUATION_FAILED',
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
          'RECONCILIATION_ISSUE_EVALUATION_FAILED',
        'errorDetail',
          jsonb_build_object(
            'sqlstate', v_error_sqlstate,
            'errorCode', v_error_message
          )
      );
  end;
end;
$$;

create or replace function notification.evaluate_reconciliation_failures(
  p_organization_id uuid,
  p_idempotency_key text,
  p_observed_at timestamptz default clock_timestamp(),
  p_trigger_type_code text default 'SCHEDULED',
  p_correlation_id uuid default gen_random_uuid(),
  p_process_name text default 'notification.evaluate_reconciliation_failures'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app, reconciliation
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
  v_retry_metadata_key text;
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
      message = 'RECONCILIATION_FAILURE_TRIGGER_TYPE_INVALID';
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
      || ':NOTIFICATION_EVALUATOR:RECONCILIATION_RUN_FAILED',
      0::bigint
    )
  );

  select run.*
  into v_existing_run
  from notification.rule_runs run
  where run.organization_id = p_organization_id
    and run.rule_code_snapshot = 'RECONCILIATION_RUN_FAILED'
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

  perform notification.ensure_reconciliation_run_failed_rule(
    p_organization_id,
    p_observed_at
  );

  select rule.*
  into strict v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'RECONCILIATION_RUN_FAILED'
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
    v_retry_metadata_key :=
      nullif(
        btrim(
          coalesce(
            v_rule.config ->>
              'successfulRetryMetadataKey',
            ''
          )
        ),
        ''
      );

    if v_retry_metadata_key is null
       or length(v_retry_metadata_key) > 100
       or v_rule.config ->> 'failedStatusCode' <> 'FAILED'
       or v_rule.config ->> 'resolvedStatusCode' <> 'SUCCEEDED'
       or v_rule.config ->> 'stageCode' <> 'FAILED'
       or v_rule.config ->> 'severityCode' <> 'CRITICAL' then
      raise exception using
        errcode = 'P0001',
        message = 'RECONCILIATION_FAILURE_RULE_CONFIG_INVALID';
    end if;

    v_local_date :=
      (p_observed_at at time zone v_organization_timezone)::date;

    for v_candidate in
      with source_rows as (
        select
          failed_run.id as entity_id,
          failed_run.run_no,
          failed_run.run_type_code,
          failed_run.trigger_code,
          failed_run.status_code,
          failed_run.scope,
          failed_run.check_codes,
          failed_run.rule_set_version,
          failed_run.ledger_seq_from,
          failed_run.ledger_seq_to,
          failed_run.started_at,
          failed_run.completed_at,
          failed_run.actor_user_id,
          failed_run.process_name as source_process_name,
          failed_run.summary,
          failed_run.error_code,
          failed_run.error_detail,
          failed_run.metadata,
          failed_run.created_at as run_created_at,
          failed_run.updated_at as run_updated_at,
          retry_run.id as successful_retry_run_id,
          retry_run.run_no as successful_retry_run_no,
          retry_run.completed_at
            as successful_retry_completed_at,
          false as source_missing
        from reconciliation.runs failed_run
        left join lateral (
          select candidate_retry.*
          from reconciliation.runs candidate_retry
          where candidate_retry.organization_id =
                failed_run.organization_id
            and candidate_retry.status_code = 'SUCCEEDED'
            and candidate_retry.metadata ->>
                  v_retry_metadata_key =
                failed_run.id::text
          order by
            candidate_retry.completed_at desc,
            candidate_retry.id desc
          limit 1
        ) retry_run on true
        where failed_run.organization_id =
              p_organization_id
      ),
      active_without_source as (
        select notification_row.entity_id
        from notification.notifications notification_row
        where notification_row.organization_id = p_organization_id
          and notification_row.rule_code_snapshot = v_rule.code
          and notification_row.entity_type_code =
            'RECONCILIATION_RUN'
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
        source_row.run_no,
        source_row.run_type_code,
        source_row.trigger_code,
        source_row.status_code,
        source_row.scope,
        source_row.check_codes,
        source_row.rule_set_version,
        source_row.ledger_seq_from,
        source_row.ledger_seq_to,
        source_row.started_at,
        source_row.completed_at,
        source_row.actor_user_id,
        source_row.source_process_name,
        source_row.summary,
        source_row.error_code,
        source_row.error_detail,
        source_row.metadata,
        source_row.run_created_at,
        source_row.run_updated_at,
        source_row.successful_retry_run_id,
        source_row.successful_retry_run_no,
        source_row.successful_retry_completed_at,
        source_row.source_missing
      from source_rows source_row

      union all

      select
        orphan.entity_id,
        null::text,
        null::text,
        null::text,
        null::text,
        '{}'::jsonb,
        array[]::text[],
        null::text,
        null::bigint,
        null::bigint,
        null::timestamptz,
        null::timestamptz,
        null::uuid,
        null::text,
        '{}'::jsonb,
        null::text,
        null::jsonb,
        '{}'::jsonb,
        null::timestamptz,
        null::timestamptz,
        null::uuid,
        null::text,
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
              'RECONCILIATION_RUN'
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
        elsif v_candidate.status_code = 'FAILED'
              and v_candidate.successful_retry_run_id is null then
          v_condition_started_at :=
            coalesce(
              v_candidate.completed_at,
              v_candidate.run_updated_at,
              v_candidate.started_at
            );

          if v_condition_started_at is null
             or v_condition_started_at > p_observed_at then
            raise exception using
              errcode = 'P0001',
              message =
                'RECONCILIATION_FAILURE_CONDITION_TIME_INVALID';
          end if;

          v_title := 'Reconciliation run gagal';

          v_message := format(
            'Reconciliation run %s gagal%s.',
            v_candidate.run_no,
            case
              when nullif(
                btrim(coalesce(v_candidate.error_code, '')),
                ''
              ) is null
                then ''
              else
                ' dengan error ' || v_candidate.error_code
            end
          );

          v_action_route :=
            '/reconciliation?runId='
            || v_candidate.entity_id::text;

          v_source_snapshot := jsonb_build_object(
            'schemaVersion', 1,
            'organizationTimezone', v_organization_timezone,
            'localDate', v_local_date,
            'runId', v_candidate.entity_id,
            'runNo', v_candidate.run_no,
            'runTypeCode', v_candidate.run_type_code,
            'triggerCode', v_candidate.trigger_code,
            'statusCode', v_candidate.status_code,
            'scope', v_candidate.scope,
            'checkCodes', to_jsonb(v_candidate.check_codes),
            'ruleSetVersion', v_candidate.rule_set_version,
            'ledgerSeqFrom', v_candidate.ledger_seq_from,
            'ledgerSeqTo', v_candidate.ledger_seq_to,
            'startedAt', v_candidate.started_at,
            'completedAt', v_candidate.completed_at,
            'actorUserId', v_candidate.actor_user_id,
            'processName', v_candidate.source_process_name,
            'summary', v_candidate.summary,
            'errorCode', v_candidate.error_code,
            'errorDetail', v_candidate.error_detail,
            'metadata', v_candidate.metadata,
            'runCreatedAt', v_candidate.run_created_at,
            'runUpdatedAt', v_candidate.run_updated_at,
            'retryMetadataKey', v_retry_metadata_key
          );

          v_upsert_result :=
            notification.upsert_active_notification(
              p_organization_id => p_organization_id,
              p_rule_id => v_rule.id,
              p_entity_id => v_candidate.entity_id,
              p_deduplication_key =>
                'ACTIVE_FAILED_RUN',
              p_stage_code => 'FAILED',
              p_severity_code => 'CRITICAL',
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
                'RECONCILIATION_FAILURE_UPSERT_ACTION_INVALID';
          end if;
        elsif v_active.id is not null then
          v_resolution_reason :=
            coalesce(
              v_resolution_reason,
              case
                when v_candidate.successful_retry_run_id
                     is not null
                  then 'SUCCESSFUL_RETRY_FOUND'
                when v_candidate.status_code <> 'FAILED'
                  then 'RUN_STATUS_RECOVERED'
                else 'SOURCE_CONDITION_CLEARED'
              end
            );

          v_resolution_snapshot := jsonb_build_object(
            'schemaVersion', 1,
            'ruleRunId', v_rule_run_id,
            'resolutionReason', v_resolution_reason,
            'organizationTimezone', v_organization_timezone,
            'localDate', v_local_date,
            'failedRunId', v_candidate.entity_id,
            'failedRunNo', v_candidate.run_no,
            'currentStatusCode', v_candidate.status_code,
            'sourceErrorCode', v_candidate.error_code,
            'successfulRetryRunId',
              v_candidate.successful_retry_run_id,
            'successfulRetryRunNo',
              v_candidate.successful_retry_run_no,
            'successfulRetryCompletedAt',
              v_candidate.successful_retry_completed_at,
            'retryMetadataKey', v_retry_metadata_key
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
                'Reconciliation failure condition cleared: %s.',
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
                'RECONCILIATION_FAILURE_RESOLUTION_ACTION_INVALID';
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
        'organizationTimezone', v_organization_timezone,
        'localDate', v_local_date,
        'observedAt', p_observed_at,
        'successfulRetryMetadataKey',
          v_retry_metadata_key,
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
          else 'RECONCILIATION_FAILURE_ENTITY_EVALUATION_FAILED'
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
        error_code =
          'RECONCILIATION_FAILURE_EVALUATION_FAILED',
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
          'RECONCILIATION_FAILURE_EVALUATION_FAILED',
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
on function notification.ensure_reconciliation_issue_rule(
  uuid,
  timestamptz
)
from public, anon, authenticated;

revoke all
on function notification.ensure_reconciliation_run_failed_rule(
  uuid,
  timestamptz
)
from public, anon, authenticated;

revoke all
on function notification.evaluate_reconciliation_issues(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
from public, anon, authenticated;

revoke all
on function notification.evaluate_reconciliation_failures(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
from public, anon, authenticated;

grant execute
on function notification.ensure_reconciliation_issue_rule(
  uuid,
  timestamptz
)
to service_role;

grant execute
on function notification.ensure_reconciliation_run_failed_rule(
  uuid,
  timestamptz
)
to service_role;

grant execute
on function notification.evaluate_reconciliation_issues(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
to service_role;

grant execute
on function notification.evaluate_reconciliation_failures(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
to service_role;

commit;
