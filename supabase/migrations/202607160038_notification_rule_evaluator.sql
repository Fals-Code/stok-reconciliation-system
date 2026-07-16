begin;

create or replace function notification.ensure_expiry_rule(
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
  v_threshold_json jsonb;
  v_threshold_days integer[];
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
      message = 'EXPIRY_RULE_EFFECTIVE_TIME_REQUIRED';
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
      p_organization_id::text || ':NOTIFICATION_RULE:EXPIRY_RISK',
      0::bigint
    )
  );

  select rule.*
  into v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'EXPIRY_RISK'
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
        message = 'EXPIRY_RULE_NOT_ACTIVE';
    end if;

    return v_rule.id;
  end if;

  select setting.value
  into v_threshold_json
  from app.settings setting
  where setting.organization_id = p_organization_id
    and setting.key = 'expiry.warning_days'
    and setting.effective_from <= p_effective_at
    and (
      setting.effective_to is null
      or setting.effective_to > p_effective_at
    )
  order by
    setting.version desc,
    setting.effective_from desc,
    setting.id desc
  limit 1;

  v_threshold_json :=
    coalesce(v_threshold_json, '[90,60,30,0]'::jsonb);

  begin
    if jsonb_typeof(v_threshold_json) is distinct from 'array'
       or jsonb_array_length(v_threshold_json) is distinct from 4 then
      raise exception using
        errcode = 'P0001',
        message = 'EXPIRY_THRESHOLD_CONFIG_INVALID';
    end if;

    select array_agg(
      threshold.value::integer
      order by threshold.ordinality
    )
    into v_threshold_days
    from jsonb_array_elements_text(v_threshold_json)
      with ordinality as threshold(value, ordinality);
  exception
    when others then
      raise exception using
        errcode = 'P0001',
        message = 'EXPIRY_THRESHOLD_CONFIG_INVALID';
  end;

  if cardinality(v_threshold_days) is distinct from 4
     or v_threshold_days[1] <= v_threshold_days[2]
     or v_threshold_days[2] <= v_threshold_days[3]
     or v_threshold_days[3] <= v_threshold_days[4]
     or v_threshold_days[4] <> 0
     or v_threshold_days[1] > 3650 then
    raise exception using
      errcode = 'P0001',
      message = 'EXPIRY_THRESHOLD_CONFIG_INVALID';
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
    'EXPIRY_RISK',
    '1.0.0',
    'EXPIRY',
    'SCHEDULED',
    'PRODUCT_BATCH',
    'EXPIRY_STAGE_SEVERITY_V1',
    'LOCAL_DATE_THRESHOLD_V1',
    'POSITIVE_RELEVANT_BALANCE_V1',
    'SOURCE_CONDITION_CLEARED_V1',
    '1.0.0',
    'OPEN_BATCH_EXPIRY_DETAIL',
    jsonb_build_object(
      'thresholdDays',
      to_jsonb(v_threshold_days),
      'riskQuantityBuckets',
      jsonb_build_array('SELLABLE', 'QUARANTINE'),
      'physicalQuantityBuckets',
      jsonb_build_array(
        'SELLABLE',
        'QUARANTINE',
        'DAMAGED'
      ),
      'sameDayStage',
      'D30',
      'expiredBeginsAfterLocalDate',
      true,
      'timezoneSource',
      'ORGANIZATION',
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

create or replace function notification.evaluate_expiry(
  p_organization_id uuid,
  p_idempotency_key text,
  p_observed_at timestamptz default clock_timestamp(),
  p_trigger_type_code text default 'SCHEDULED',
  p_correlation_id uuid default gen_random_uuid(),
  p_process_name text default 'notification.evaluate_expiry'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app, catalog, inventory
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
  v_threshold_days integer[];
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
  v_due_at timestamptz;
  v_source_snapshot jsonb;
  v_resolution_snapshot jsonb;
  v_resolution_reason text;
  v_days_remaining integer;
  v_risk_qty bigint;
  v_physical_qty bigint;
  v_relevant_qty bigint;
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

  if v_trigger_type_code not in ('SCHEDULED', 'MANUAL') then
    raise exception using
      errcode = 'P0001',
      message = 'EXPIRY_TRIGGER_TYPE_INVALID';
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
      p_organization_id::text || ':NOTIFICATION_EVALUATOR:EXPIRY_RISK',
      0::bigint
    )
  );

  select run.*
  into v_existing_run
  from notification.rule_runs run
  where run.organization_id = p_organization_id
    and run.rule_code_snapshot = 'EXPIRY_RISK'
    and run.idempotency_key = v_idempotency_key
  for update;

  if v_existing_run.id is not null then
    return jsonb_build_object(
      'action',
      'REPLAYED',
      'ruleRunId',
      v_existing_run.id,
      'ruleCode',
      v_existing_run.rule_code_snapshot,
      'ruleVersion',
      v_existing_run.rule_version_snapshot,
      'status',
      v_existing_run.status_code,
      'evaluatedCount',
      v_existing_run.evaluated_count,
      'createdCount',
      v_existing_run.created_count,
      'updatedCount',
      v_existing_run.updated_count,
      'resolvedCount',
      v_existing_run.resolved_count,
      'skippedCount',
      v_existing_run.skipped_count,
      'errorCount',
      v_existing_run.error_count,
      'summary',
      v_existing_run.summary
    );
  end if;

  perform notification.ensure_expiry_rule(
    p_organization_id,
    p_observed_at
  );

  select rule.*
  into strict v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'EXPIRY_RISK'
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
      if jsonb_typeof(v_rule.config -> 'thresholdDays') is distinct from 'array'
         or jsonb_array_length(v_rule.config -> 'thresholdDays') is distinct from 4 then
        raise exception using
          errcode = 'P0001',
          message = 'EXPIRY_RULE_CONFIG_INVALID';
      end if;

      select array_agg(
        threshold.value::integer
        order by threshold.ordinality
      )
      into v_threshold_days
      from jsonb_array_elements_text(v_rule.config -> 'thresholdDays')
        with ordinality as threshold(value, ordinality);
    exception
      when others then
        raise exception using
          errcode = 'P0001',
          message = 'EXPIRY_RULE_CONFIG_INVALID';
    end;

    if cardinality(v_threshold_days) is distinct from 4
       or v_threshold_days[1] <= v_threshold_days[2]
       or v_threshold_days[2] <= v_threshold_days[3]
       or v_threshold_days[3] <= v_threshold_days[4]
       or v_threshold_days[4] <> 0
       or v_threshold_days[1] > 3650 then
      raise exception using
        errcode = 'P0001',
        message = 'EXPIRY_RULE_CONFIG_INVALID';
    end if;

    v_local_date :=
      (p_observed_at at time zone v_organization_timezone)::date;

    for v_candidate in
      with source_rows as (
        select
          batch.id as entity_id,
          batch.product_id,
          product.sku as product_sku,
          product.name as product_name,
          product.is_active as product_is_active,
          batch.batch_code,
          batch.expiry_date,
          batch.status_code as batch_status_code,
          batch.row_version as batch_row_version,
          coalesce(balance.sellable_qty, 0)::bigint
            as sellable_qty,
          coalesce(balance.quarantine_qty, 0)::bigint
            as quarantine_qty,
          coalesce(balance.damaged_qty, 0)::bigint
            as damaged_qty,
          coalesce(balance.last_ledger_seq, 0)::bigint
            as last_ledger_seq,
          coalesce(balance.version, 0)::bigint
            as balance_version,
          false as source_missing
        from catalog.product_batches batch
        join catalog.products product
          on product.organization_id = batch.organization_id
         and product.id = batch.product_id
        left join inventory.stock_batch_balances balance
          on balance.organization_id = batch.organization_id
         and balance.batch_id = batch.id
         and balance.product_id = batch.product_id
        where batch.organization_id = p_organization_id
      ),
      active_without_source as (
        select
          notification_row.entity_id
        from notification.notifications notification_row
        where notification_row.organization_id = p_organization_id
          and notification_row.rule_code_snapshot = v_rule.code
          and notification_row.entity_type_code = 'PRODUCT_BATCH'
          and notification_row.lifecycle_status_code in (
            'OPEN',
            'ACKNOWLEDGED'
          )
          and not exists (
            select 1
            from source_rows source_row
            where source_row.entity_id = notification_row.entity_id
          )
      )
      select
        source_row.entity_id,
        source_row.product_id,
        source_row.product_sku,
        source_row.product_name,
        source_row.product_is_active,
        source_row.batch_code,
        source_row.expiry_date,
        source_row.batch_status_code,
        source_row.batch_row_version,
        source_row.sellable_qty,
        source_row.quarantine_qty,
        source_row.damaged_qty,
        source_row.last_ledger_seq,
        source_row.balance_version,
        source_row.source_missing
      from source_rows source_row

      union all

      select
        orphan.entity_id,
        null::uuid,
        null::text,
        null::text,
        null::boolean,
        null::text,
        null::date,
        null::text,
        null::bigint,
        0::bigint,
        0::bigint,
        0::bigint,
        0::bigint,
        0::bigint,
        true
      from active_without_source orphan
      order by entity_id
    loop
      v_evaluated_count := v_evaluated_count + 1;

      begin
        select notification_row.*
        into v_active
        from notification.notifications notification_row
        where notification_row.organization_id = p_organization_id
          and notification_row.rule_code_snapshot = v_rule.code
          and notification_row.entity_type_code = 'PRODUCT_BATCH'
          and notification_row.entity_id = v_candidate.entity_id
          and notification_row.lifecycle_status_code in (
            'OPEN',
            'ACKNOWLEDGED'
          )
        order by notification_row.episode_no desc
        limit 1
        for update;

        v_stage_code := null;
        v_severity_code := null;
        v_stage_direction_code := 'UNCHANGED';
        v_title := null;
        v_message := null;
        v_action_route := null;
        v_condition_started_at := null;
        v_due_at := null;
        v_source_snapshot := '{}'::jsonb;
        v_resolution_snapshot := '{}'::jsonb;
        v_resolution_reason := null;
        v_days_remaining := null;
        v_risk_qty := 0;
        v_physical_qty := 0;
        v_relevant_qty := 0;

        if v_candidate.source_missing then
          v_resolution_reason := 'SOURCE_ENTITY_MISSING';
        else
          v_days_remaining :=
            v_candidate.expiry_date - v_local_date;
          v_risk_qty :=
            v_candidate.sellable_qty
            + v_candidate.quarantine_qty;
          v_physical_qty :=
            v_risk_qty
            + v_candidate.damaged_qty;

          if v_days_remaining < 0 then
            if v_physical_qty > 0 then
              v_stage_code := 'EXPIRED';
              v_severity_code := 'CRITICAL';
              v_relevant_qty := v_physical_qty;
            else
              v_resolution_reason := 'PHYSICAL_BALANCE_ZERO';
            end if;
          elsif v_days_remaining <= v_threshold_days[3] then
            if v_risk_qty > 0 then
              v_stage_code := 'D30';
              v_severity_code := 'HIGH';
              v_relevant_qty := v_risk_qty;
            else
              v_resolution_reason := 'RISK_BALANCE_ZERO';
            end if;
          elsif v_days_remaining <= v_threshold_days[2] then
            if v_risk_qty > 0 then
              v_stage_code := 'D60';
              v_severity_code := 'WARNING';
              v_relevant_qty := v_risk_qty;
            else
              v_resolution_reason := 'RISK_BALANCE_ZERO';
            end if;
          elsif v_days_remaining <= v_threshold_days[1] then
            if v_risk_qty > 0 then
              v_stage_code := 'D90';
              v_severity_code := 'INFO';
              v_relevant_qty := v_risk_qty;
            else
              v_resolution_reason := 'RISK_BALANCE_ZERO';
            end if;
          else
            v_resolution_reason := 'OUTSIDE_EXPIRY_WINDOW';
          end if;
        end if;

        if v_stage_code is not null then
          v_old_stage_rank :=
            case v_active.stage_code
              when 'D90' then 1
              when 'D60' then 2
              when 'D30' then 3
              when 'EXPIRED' then 4
              else null
            end;

          v_new_stage_rank :=
            case v_stage_code
              when 'D90' then 1
              when 'D60' then 2
              when 'D30' then 3
              when 'EXPIRED' then 4
            end;

          if v_active.id is not null then
            if v_old_stage_rank is null then
              raise exception using
                errcode = 'P0001',
                message = 'EXPIRY_ACTIVE_STAGE_INVALID';
            elsif v_new_stage_rank > v_old_stage_rank then
              v_stage_direction_code := 'ESCALATED';
            elsif v_new_stage_rank < v_old_stage_rank then
              v_stage_direction_code := 'DEESCALATED';
            end if;
          end if;

          v_due_at :=
            (
              (v_candidate.expiry_date + 1)::timestamp
              at time zone v_organization_timezone
            );

          v_condition_started_at :=
            (
              case v_stage_code
                when 'D90' then
                  (
                    v_candidate.expiry_date
                    - v_threshold_days[1]
                  )::timestamp
                when 'D60' then
                  (
                    v_candidate.expiry_date
                    - v_threshold_days[2]
                  )::timestamp
                when 'D30' then
                  (
                    v_candidate.expiry_date
                    - v_threshold_days[3]
                  )::timestamp
                else
                  (v_candidate.expiry_date + 1)::timestamp
              end
              at time zone v_organization_timezone
            );

          if v_stage_code = 'EXPIRED' then
            v_title := 'Batch kedaluwarsa masih bersaldo';
            v_message := format(
              'Batch %s (%s) telah kedaluwarsa dan masih memiliki %s unit fisik.',
              v_candidate.batch_code,
              v_candidate.product_sku,
              v_physical_qty
            );
          else
            v_title := 'Batch mendekati kedaluwarsa';
            v_message := format(
              'Batch %s (%s) kedaluwarsa dalam %s hari dan memiliki %s unit berisiko.',
              v_candidate.batch_code,
              v_candidate.product_sku,
              v_days_remaining,
              v_risk_qty
            );
          end if;

          v_action_route :=
            '/admin/products/'
            || v_candidate.product_id::text
            || '/batches/'
            || v_candidate.entity_id::text;

          v_source_snapshot := jsonb_build_object(
            'schemaVersion',
            1,
            'organizationTimezone',
            v_organization_timezone,
            'localDate',
            v_local_date,
            'productId',
            v_candidate.product_id,
            'productSku',
            v_candidate.product_sku,
            'productName',
            v_candidate.product_name,
            'productIsActive',
            v_candidate.product_is_active,
            'batchId',
            v_candidate.entity_id,
            'batchCode',
            v_candidate.batch_code,
            'batchStatusCode',
            v_candidate.batch_status_code,
            'batchRowVersion',
            v_candidate.batch_row_version,
            'expiryDate',
            v_candidate.expiry_date,
            'daysRemaining',
            v_days_remaining,
            'sellableQty',
            v_candidate.sellable_qty,
            'quarantineQty',
            v_candidate.quarantine_qty,
            'damagedQty',
            v_candidate.damaged_qty,
            'riskQty',
            v_risk_qty,
            'physicalQty',
            v_physical_qty,
            'relevantQty',
            v_relevant_qty,
            'lastLedgerSeq',
            v_candidate.last_ledger_seq,
            'balanceVersion',
            v_candidate.balance_version
          );

          v_upsert_result :=
            notification.upsert_active_notification(
              p_organization_id => p_organization_id,
              p_rule_id => v_rule.id,
              p_entity_id => v_candidate.entity_id,
              p_deduplication_key => 'ACTIVE_EXPIRY_CONDITION',
              p_stage_code => v_stage_code,
              p_severity_code => v_severity_code,
              p_title => v_title,
              p_message => v_message,
              p_action_route => v_action_route,
              p_condition_started_at => v_condition_started_at,
              p_observed_at => p_observed_at,
              p_due_at => v_due_at,
              p_source_snapshot => v_source_snapshot,
              p_stage_direction_code => v_stage_direction_code,
              p_correlation_id => p_correlation_id,
              p_process_name => v_process_name
            );

          v_action := v_upsert_result ->> 'action';

          if v_action in (
            'CREATED',
            'REOPENED_AS_NEW_EPISODE'
          ) then
            v_created_count := v_created_count + 1;
          elsif v_action in ('UPDATED', 'SEEN_AGAIN') then
            v_updated_count := v_updated_count + 1;
          else
            raise exception using
              errcode = 'P0001',
              message = 'EXPIRY_UPSERT_ACTION_INVALID';
          end if;
        elsif v_active.id is not null then
          v_resolution_snapshot := jsonb_build_object(
            'schemaVersion',
            1,
            'ruleRunId',
            v_rule_run_id,
            'resolutionReason',
            v_resolution_reason,
            'organizationTimezone',
            v_organization_timezone,
            'localDate',
            v_local_date,
            'batchId',
            v_candidate.entity_id,
            'productId',
            v_candidate.product_id,
            'expiryDate',
            v_candidate.expiry_date,
            'daysRemaining',
            v_days_remaining,
            'sellableQty',
            v_candidate.sellable_qty,
            'quarantineQty',
            v_candidate.quarantine_qty,
            'damagedQty',
            v_candidate.damaged_qty,
            'riskQty',
            v_risk_qty,
            'physicalQty',
            v_physical_qty,
            'lastLedgerSeq',
            v_candidate.last_ledger_seq,
            'balanceVersion',
            v_candidate.balance_version
          );

          v_resolve_result :=
            notification.resolve_notification(
              p_organization_id => p_organization_id,
              p_notification_id => v_active.id,
              p_resolution_code => 'SOURCE_CONDITION_CLEARED',
              p_resolution_snapshot => v_resolution_snapshot,
              p_resolved_at => p_observed_at,
              p_correlation_id => p_correlation_id,
              p_note => format(
                'Expiry condition cleared: %s.',
                v_resolution_reason
              ),
              p_process_name => v_process_name
            );

          if v_resolve_result ->> 'action' in (
            'RESOLVED',
            'ALREADY_RESOLVED'
          ) then
            v_resolved_count := v_resolved_count + 1;
          else
            raise exception using
              errcode = 'P0001',
              message = 'EXPIRY_RESOLUTION_ACTION_INVALID';
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
        'schemaVersion',
        1,
        'ruleCode',
        v_rule.code,
        'ruleVersion',
        v_rule.version,
        'organizationTimezone',
        v_organization_timezone,
        'localDate',
        v_local_date,
        'observedAt',
        p_observed_at,
        'evaluatedCount',
        v_evaluated_count,
        'createdCount',
        v_created_count,
        'updatedCount',
        v_updated_count,
        'resolvedCount',
        v_resolved_count,
        'skippedCount',
        v_skipped_count,
        'errorCount',
        v_error_count
      ),
      error_code =
        case
          when v_error_count = 0 then null
          else 'EXPIRY_ENTITY_EVALUATION_FAILED'
        end,
      error_detail =
        case
          when v_error_count = 0 then '{}'::jsonb
          else jsonb_build_object('items', v_error_items)
        end
    where run.id = v_rule_run_id
      and run.organization_id = p_organization_id;

    v_response := jsonb_build_object(
      'action',
      'COMPLETED',
      'ruleRunId',
      v_rule_run_id,
      'ruleCode',
      v_rule.code,
      'ruleVersion',
      v_rule.version,
      'status',
      v_status_code,
      'localDate',
      v_local_date,
      'evaluatedCount',
      v_evaluated_count,
      'createdCount',
      v_created_count,
      'updatedCount',
      v_updated_count,
      'resolvedCount',
      v_resolved_count,
      'skippedCount',
      v_skipped_count,
      'errorCount',
      v_error_count
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
          'schemaVersion',
          1,
          'ruleCode',
          v_rule.code,
          'ruleVersion',
          v_rule.version,
          'observedAt',
          p_observed_at,
          'failedAt',
          v_completed_at
        ),
        error_code = 'EXPIRY_EVALUATION_FAILED',
        error_detail = jsonb_build_object(
          'sqlstate',
          v_error_sqlstate,
          'errorCode',
          v_error_message
        )
      where run.id = v_rule_run_id
        and run.organization_id = p_organization_id;

      return jsonb_build_object(
        'action',
        'COMPLETED',
        'ruleRunId',
        v_rule_run_id,
        'ruleCode',
        v_rule.code,
        'ruleVersion',
        v_rule.version,
        'status',
        'FAILED',
        'evaluatedCount',
        0,
        'createdCount',
        0,
        'updatedCount',
        0,
        'resolvedCount',
        0,
        'skippedCount',
        0,
        'errorCount',
        1,
        'errorCode',
        'EXPIRY_EVALUATION_FAILED'
      );
  end;
end;
$$;

revoke all
on function notification.ensure_expiry_rule(uuid, timestamptz)
from public, anon, authenticated;

revoke all
on function notification.evaluate_expiry(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
from public, anon, authenticated;

grant execute
on function notification.ensure_expiry_rule(uuid, timestamptz)
to service_role;

grant execute
on function notification.evaluate_expiry(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
to service_role;

commit;
