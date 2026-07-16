begin;

create or replace function notification.ensure_return_inspection_rule(
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
  v_threshold_hours integer[];
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
      message = 'RETURN_INSPECTION_RULE_EFFECTIVE_TIME_REQUIRED';
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
      || ':NOTIFICATION_RULE:RETURN_INSPECTION_PENDING',
      0::bigint
    )
  );

  select rule.*
  into v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'RETURN_INSPECTION_PENDING'
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
        message = 'RETURN_INSPECTION_RULE_NOT_ACTIVE';
    end if;

    return v_rule.id;
  end if;

  select setting.value
  into v_threshold_json
  from app.settings setting
  where setting.organization_id = p_organization_id
    and setting.key = 'return.inspection_sla_hours'
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
    coalesce(v_threshold_json, '[24,72]'::jsonb);

  begin
    if jsonb_typeof(v_threshold_json) is distinct from 'array'
       or jsonb_array_length(v_threshold_json) is distinct from 2 then
      raise exception using
        errcode = 'P0001',
        message = 'RETURN_INSPECTION_THRESHOLD_CONFIG_INVALID';
    end if;

    select array_agg(
      threshold.value::integer
      order by threshold.ordinality
    )
    into v_threshold_hours
    from jsonb_array_elements_text(v_threshold_json)
      with ordinality as threshold(value, ordinality);
  exception
    when others then
      raise exception using
        errcode = 'P0001',
        message = 'RETURN_INSPECTION_THRESHOLD_CONFIG_INVALID';
  end;

  if cardinality(v_threshold_hours) is distinct from 2
     or v_threshold_hours[1] <= 0
     or v_threshold_hours[2] <= v_threshold_hours[1]
     or v_threshold_hours[2] > 8760 then
    raise exception using
      errcode = 'P0001',
      message = 'RETURN_INSPECTION_THRESHOLD_CONFIG_INVALID';
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
    'RETURN_INSPECTION_PENDING',
    '1.0.0',
    'RETURN',
    'HYBRID',
    'RETURN',
    'RETURN_INSPECTION_AGE_SEVERITY_V1',
    'RETURN_INSPECTION_AGE_STAGE_V1',
    'POSITIVE_PENDING_INSPECTION_QTY_V1',
    'SOURCE_CONDITION_CLEARED_V1',
    '1.0.0',
    'OPEN_RETURN_INSPECTION_DETAIL',
    jsonb_build_object(
      'thresholdHours',
      to_jsonb(v_threshold_hours),
      'stages',
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'PENDING',
          'minimumAgeHours',
          0,
          'severity',
          'WARNING'
        ),
        jsonb_build_object(
          'code',
          'PENDING_24H',
          'minimumAgeHours',
          v_threshold_hours[1],
          'severity',
          'HIGH'
        ),
        jsonb_build_object(
          'code',
          'PENDING_72H',
          'minimumAgeHours',
          v_threshold_hours[2],
          'severity',
          'CRITICAL'
        )
      ),
      'conditionQuantity',
      'RECEIVED_MINUS_SELLABLE_MINUS_DAMAGED',
      'conditionStartedAt',
      'EARLIEST_RECEIPT_LINE_WITH_REMAINING_QUANTITY',
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

create or replace function notification.evaluate_return_inspection(
  p_organization_id uuid,
  p_idempotency_key text,
  p_observed_at timestamptz default clock_timestamp(),
  p_trigger_type_code text default 'SCHEDULED',
  p_correlation_id uuid default gen_random_uuid(),
  p_process_name text default 'notification.evaluate_return_inspection'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app, operations, catalog
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
  v_threshold_hours integer[];
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
  v_age_minutes integer;
  v_age_hours integer;
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
      message = 'RETURN_INSPECTION_TRIGGER_TYPE_INVALID';
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
      || ':NOTIFICATION_EVALUATOR:RETURN_INSPECTION_PENDING',
      0::bigint
    )
  );

  select run.*
  into v_existing_run
  from notification.rule_runs run
  where run.organization_id = p_organization_id
    and run.rule_code_snapshot = 'RETURN_INSPECTION_PENDING'
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

  perform notification.ensure_return_inspection_rule(
    p_organization_id,
    p_observed_at
  );

  select rule.*
  into strict v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'RETURN_INSPECTION_PENDING'
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
      if jsonb_typeof(v_rule.config -> 'thresholdHours')
           is distinct from 'array'
         or jsonb_array_length(v_rule.config -> 'thresholdHours')
           is distinct from 2 then
        raise exception using
          errcode = 'P0001',
          message = 'RETURN_INSPECTION_RULE_CONFIG_INVALID';
      end if;

      select array_agg(
        threshold.value::integer
        order by threshold.ordinality
      )
      into v_threshold_hours
      from jsonb_array_elements_text(
        v_rule.config -> 'thresholdHours'
      ) with ordinality as threshold(value, ordinality);
    exception
      when others then
        raise exception using
          errcode = 'P0001',
          message = 'RETURN_INSPECTION_RULE_CONFIG_INVALID';
    end;

    if cardinality(v_threshold_hours) is distinct from 2
       or v_threshold_hours[1] <= 0
       or v_threshold_hours[2] <= v_threshold_hours[1]
       or v_threshold_hours[2] > 8760 then
      raise exception using
        errcode = 'P0001',
        message = 'RETURN_INSPECTION_RULE_CONFIG_INVALID';
    end if;

    v_local_date :=
      (p_observed_at at time zone v_organization_timezone)::date;

    for v_candidate in
      with inspection_totals as (
        select
          allocation.organization_id,
          allocation.receipt_line_id,
          sum(allocation.quantity_allocated)::bigint
            as inspected_qty
        from operations.return_inspection_allocations allocation
        where allocation.organization_id = p_organization_id
        group by
          allocation.organization_id,
          allocation.receipt_line_id
      ),
      pending_receipt_lines as (
        select
          receipt.organization_id,
          receipt.return_id,
          receipt.id as receipt_id,
          receipt.receipt_ref,
          receipt.occurred_at as receipt_occurred_at,
          receipt_line.id as receipt_line_id,
          receipt_line.quantity_received::bigint,
          coalesce(
            inspection_total.inspected_qty,
            0
          )::bigint as inspected_qty,
          (
            receipt_line.quantity_received
            - coalesce(inspection_total.inspected_qty, 0)
          )::bigint as pending_qty
        from operations.return_receipts receipt
        join operations.return_receipt_lines receipt_line
          on receipt_line.organization_id = receipt.organization_id
         and receipt_line.receipt_id = receipt.id
        left join inspection_totals inspection_total
          on inspection_total.organization_id =
               receipt_line.organization_id
         and inspection_total.receipt_line_id = receipt_line.id
        where receipt.organization_id = p_organization_id
          and receipt_line.quantity_received
              - coalesce(inspection_total.inspected_qty, 0) > 0
      ),
      pending_receipt_stats as (
        select
          pending_line.organization_id,
          pending_line.return_id,
          sum(pending_line.pending_qty)::bigint
            as pending_receipt_qty,
          min(pending_line.receipt_occurred_at)
            as earliest_pending_receipt_at,
          max(pending_line.receipt_occurred_at)
            as latest_pending_receipt_at,
          count(distinct pending_line.receipt_id)::integer
            as pending_receipt_count,
          count(*)::integer as pending_receipt_line_count
        from pending_receipt_lines pending_line
        group by
          pending_line.organization_id,
          pending_line.return_id
      ),
      receipt_stats as (
        select
          receipt.organization_id,
          receipt.return_id,
          count(*)::integer as receipt_count,
          min(receipt.occurred_at) as first_receipt_at,
          max(receipt.occurred_at) as latest_receipt_at
        from operations.return_receipts receipt
        where receipt.organization_id = p_organization_id
        group by
          receipt.organization_id,
          receipt.return_id
      ),
      inspection_stats as (
        select
          inspection.organization_id,
          inspection.return_id,
          count(*)::integer as inspection_count,
          max(inspection.occurred_at) as latest_inspection_at
        from operations.return_inspections inspection
        where inspection.organization_id = p_organization_id
        group by
          inspection.organization_id,
          inspection.return_id
      ),
      item_totals as (
        select
          item.organization_id,
          item.return_id,
          sum(item.expected_qty)::bigint as expected_qty,
          sum(item.received_qty)::bigint as received_qty,
          sum(item.sellable_qty)::bigint as sellable_qty,
          sum(item.damaged_qty)::bigint as damaged_qty,
          sum(item.lost_qty)::bigint as lost_qty,
          sum(
            item.expected_qty
            - item.received_qty
            - item.lost_qty
          )::bigint as pending_arrival_qty,
          sum(
            item.received_qty
            - item.sellable_qty
            - item.damaged_qty
          )::bigint as pending_inspection_qty
        from operations.return_items item
        where item.organization_id = p_organization_id
        group by
          item.organization_id,
          item.return_id
      ),
      source_rows as (
        select
          return_header.id as entity_id,
          return_header.external_return_ref,
          return_header.source_status_code,
          return_header.status_code,
          return_header.outcome_code,
          return_header.expected_at,
          return_header.closed_at,
          return_header.updated_at as return_updated_at,
          return_header.marketplace_order_id,
          marketplace_order.external_order_ref
            as marketplace_order_ref,
          channel.code as channel_code,
          item_total.expected_qty,
          item_total.received_qty,
          item_total.sellable_qty,
          item_total.damaged_qty,
          item_total.lost_qty,
          item_total.pending_arrival_qty,
          item_total.pending_inspection_qty,
          coalesce(
            pending_receipt.pending_receipt_qty,
            0
          )::bigint as pending_receipt_qty,
          pending_receipt.earliest_pending_receipt_at,
          pending_receipt.latest_pending_receipt_at,
          coalesce(
            pending_receipt.pending_receipt_count,
            0
          )::integer as pending_receipt_count,
          coalesce(
            pending_receipt.pending_receipt_line_count,
            0
          )::integer as pending_receipt_line_count,
          coalesce(receipt_stat.receipt_count, 0)::integer
            as receipt_count,
          receipt_stat.first_receipt_at,
          receipt_stat.latest_receipt_at,
          coalesce(
            inspection_stat.inspection_count,
            0
          )::integer as inspection_count,
          inspection_stat.latest_inspection_at,
          false as source_missing
        from operations.returns return_header
        join item_totals item_total
          on item_total.organization_id =
               return_header.organization_id
         and item_total.return_id = return_header.id
        join catalog.channels channel
          on channel.id = return_header.channel_id
        join operations.marketplace_orders marketplace_order
          on marketplace_order.organization_id =
               return_header.organization_id
         and marketplace_order.id =
               return_header.marketplace_order_id
        left join pending_receipt_stats pending_receipt
          on pending_receipt.organization_id =
               return_header.organization_id
         and pending_receipt.return_id = return_header.id
        left join receipt_stats receipt_stat
          on receipt_stat.organization_id =
               return_header.organization_id
         and receipt_stat.return_id = return_header.id
        left join inspection_stats inspection_stat
          on inspection_stat.organization_id =
               return_header.organization_id
         and inspection_stat.return_id = return_header.id
        where return_header.organization_id = p_organization_id
      ),
      active_without_source as (
        select notification_row.entity_id
        from notification.notifications notification_row
        where notification_row.organization_id = p_organization_id
          and notification_row.rule_code_snapshot = v_rule.code
          and notification_row.entity_type_code = 'RETURN'
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
        source_row.external_return_ref,
        source_row.source_status_code,
        source_row.status_code,
        source_row.outcome_code,
        source_row.expected_at,
        source_row.closed_at,
        source_row.return_updated_at,
        source_row.marketplace_order_id,
        source_row.marketplace_order_ref,
        source_row.channel_code,
        source_row.expected_qty,
        source_row.received_qty,
        source_row.sellable_qty,
        source_row.damaged_qty,
        source_row.lost_qty,
        source_row.pending_arrival_qty,
        source_row.pending_inspection_qty,
        source_row.pending_receipt_qty,
        source_row.earliest_pending_receipt_at,
        source_row.latest_pending_receipt_at,
        source_row.pending_receipt_count,
        source_row.pending_receipt_line_count,
        source_row.receipt_count,
        source_row.first_receipt_at,
        source_row.latest_receipt_at,
        source_row.inspection_count,
        source_row.latest_inspection_at,
        source_row.source_missing
      from source_rows source_row

      union all

      select
        orphan.entity_id,
        null::text,
        null::text,
        null::text,
        null::text,
        null::timestamptz,
        null::timestamptz,
        null::timestamptz,
        null::uuid,
        null::text,
        null::text,
        0::bigint,
        0::bigint,
        0::bigint,
        0::bigint,
        0::bigint,
        0::bigint,
        0::bigint,
        0::bigint,
        null::timestamptz,
        null::timestamptz,
        0::integer,
        0::integer,
        0::integer,
        null::timestamptz,
        null::timestamptz,
        0::integer,
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
          and notification_row.entity_type_code = 'RETURN'
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
        v_age_minutes := null;
        v_age_hours := null;

        if v_candidate.source_missing then
          v_resolution_reason := 'SOURCE_ENTITY_MISSING';
        elsif v_candidate.pending_inspection_qty
              <> v_candidate.pending_receipt_qty then
          raise exception using
            errcode = 'P0001',
            message =
              'RETURN_INSPECTION_SOURCE_INCONSISTENT';
        elsif v_candidate.pending_inspection_qty > 0 then
          if v_candidate.earliest_pending_receipt_at
               is null then
            raise exception using
              errcode = 'P0001',
              message =
                'RETURN_INSPECTION_CONDITION_TIME_MISSING';
          end if;

          if p_observed_at
               < v_candidate.earliest_pending_receipt_at then
            raise exception using
              errcode = 'P0001',
              message =
                'RETURN_INSPECTION_OBSERVED_AT_STALE';
          end if;

          v_condition_started_at :=
            v_candidate.earliest_pending_receipt_at;

          v_age_minutes :=
            floor(
              extract(
                epoch
                from (
                  p_observed_at
                  - v_condition_started_at
                )
              ) / 60
            )::integer;

          v_age_hours :=
            floor(v_age_minutes::numeric / 60)::integer;

          if v_age_minutes
               >= v_threshold_hours[2] * 60 then
            v_stage_code := 'PENDING_72H';
            v_severity_code := 'CRITICAL';
          elsif v_age_minutes
                >= v_threshold_hours[1] * 60 then
            v_stage_code := 'PENDING_24H';
            v_severity_code := 'HIGH';
          else
            v_stage_code := 'PENDING';
            v_severity_code := 'WARNING';
          end if;

          v_old_stage_rank :=
            case v_active.stage_code
              when 'PENDING' then 1
              when 'PENDING_24H' then 2
              when 'PENDING_72H' then 3
              else null
            end;

          v_new_stage_rank :=
            case v_stage_code
              when 'PENDING' then 1
              when 'PENDING_24H' then 2
              when 'PENDING_72H' then 3
            end;

          if v_active.id is not null then
            if v_old_stage_rank is null then
              raise exception using
                errcode = 'P0001',
                message =
                  'RETURN_INSPECTION_ACTIVE_STAGE_INVALID';
            elsif v_new_stage_rank > v_old_stage_rank then
              v_stage_direction_code := 'ESCALATED';
            elsif v_new_stage_rank < v_old_stage_rank then
              v_stage_direction_code := 'DEESCALATED';
            end if;
          end if;

          v_due_at :=
            v_condition_started_at
            + make_interval(
                hours => v_threshold_hours[1]
              );

          if v_stage_code = 'PENDING_72H' then
            v_title :=
              'Inspeksi retur sangat terlambat';
          elsif v_stage_code = 'PENDING_24H' then
            v_title :=
              'Inspeksi retur melewati SLA';
          else
            v_title :=
              'Retur menunggu inspeksi';
          end if;

          v_message := format(
            'Retur %s memiliki %s unit yang masih menunggu inspeksi selama %s jam.',
            v_candidate.external_return_ref,
            v_candidate.pending_inspection_qty,
            v_age_hours
          );

          v_action_route :=
            '/admin/returns/'
            || v_candidate.entity_id::text;

          v_source_snapshot := jsonb_build_object(
            'schemaVersion',
            1,
            'organizationTimezone',
            v_organization_timezone,
            'localDate',
            v_local_date,
            'returnId',
            v_candidate.entity_id,
            'returnRef',
            v_candidate.external_return_ref,
            'sourceStatusCode',
            v_candidate.source_status_code,
            'statusCode',
            v_candidate.status_code,
            'outcomeCode',
            v_candidate.outcome_code,
            'channelCode',
            v_candidate.channel_code,
            'marketplaceOrderId',
            v_candidate.marketplace_order_id,
            'marketplaceOrderRef',
            v_candidate.marketplace_order_ref,
            'expectedAt',
            v_candidate.expected_at,
            'closedAt',
            v_candidate.closed_at,
            'returnUpdatedAt',
            v_candidate.return_updated_at,
            'expectedQty',
            v_candidate.expected_qty,
            'receivedQty',
            v_candidate.received_qty,
            'sellableQty',
            v_candidate.sellable_qty,
            'damagedQty',
            v_candidate.damaged_qty,
            'lostQty',
            v_candidate.lost_qty,
            'pendingArrivalQty',
            v_candidate.pending_arrival_qty,
            'pendingInspectionQty',
            v_candidate.pending_inspection_qty,
            'pendingReceiptQty',
            v_candidate.pending_receipt_qty,
            'pendingReceiptCount',
            v_candidate.pending_receipt_count,
            'pendingReceiptLineCount',
            v_candidate.pending_receipt_line_count,
            'receiptCount',
            v_candidate.receipt_count,
            'firstReceiptAt',
            v_candidate.first_receipt_at,
            'latestReceiptAt',
            v_candidate.latest_receipt_at,
            'earliestPendingReceiptAt',
            v_candidate.earliest_pending_receipt_at,
            'latestPendingReceiptAt',
            v_candidate.latest_pending_receipt_at,
            'inspectionCount',
            v_candidate.inspection_count,
            'latestInspectionAt',
            v_candidate.latest_inspection_at,
            'ageMinutes',
            v_age_minutes,
            'ageHours',
            v_age_hours,
            'warningAfterHours',
            v_threshold_hours[1],
            'criticalAfterHours',
            v_threshold_hours[2]
          );

          v_upsert_result :=
            notification.upsert_active_notification(
              p_organization_id => p_organization_id,
              p_rule_id => v_rule.id,
              p_entity_id => v_candidate.entity_id,
              p_deduplication_key =>
                'ACTIVE_PENDING_INSPECTION',
              p_stage_code => v_stage_code,
              p_severity_code => v_severity_code,
              p_title => v_title,
              p_message => v_message,
              p_action_route => v_action_route,
              p_condition_started_at =>
                v_condition_started_at,
              p_observed_at => p_observed_at,
              p_due_at => v_due_at,
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
                'RETURN_INSPECTION_UPSERT_ACTION_INVALID';
          end if;
        elsif v_active.id is not null then
          v_resolution_reason :=
            coalesce(
              v_resolution_reason,
              'PENDING_INSPECTION_ZERO'
            );

          v_resolution_snapshot :=
            jsonb_build_object(
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
              'returnId',
              v_candidate.entity_id,
              'returnRef',
              v_candidate.external_return_ref,
              'statusCode',
              v_candidate.status_code,
              'outcomeCode',
              v_candidate.outcome_code,
              'expectedQty',
              v_candidate.expected_qty,
              'receivedQty',
              v_candidate.received_qty,
              'sellableQty',
              v_candidate.sellable_qty,
              'damagedQty',
              v_candidate.damaged_qty,
              'lostQty',
              v_candidate.lost_qty,
              'pendingArrivalQty',
              v_candidate.pending_arrival_qty,
              'pendingInspectionQty',
              v_candidate.pending_inspection_qty,
              'pendingReceiptQty',
              v_candidate.pending_receipt_qty,
              'receiptCount',
              v_candidate.receipt_count,
              'inspectionCount',
              v_candidate.inspection_count,
              'latestInspectionAt',
              v_candidate.latest_inspection_at
            );

          v_resolve_result :=
            notification.resolve_notification(
              p_organization_id =>
                p_organization_id,
              p_notification_id => v_active.id,
              p_resolution_code =>
                'SOURCE_CONDITION_CLEARED',
              p_resolution_snapshot =>
                v_resolution_snapshot,
              p_resolved_at => p_observed_at,
              p_correlation_id => p_correlation_id,
              p_note => format(
                'Return inspection condition cleared: %s.',
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
                'RETURN_INSPECTION_RESOLUTION_ACTION_INVALID';
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
        'warningAfterHours',
        v_threshold_hours[1],
        'criticalAfterHours',
        v_threshold_hours[2],
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
          else 'RETURN_INSPECTION_ENTITY_EVALUATION_FAILED'
        end,
      error_detail =
        case
          when v_error_count = 0 then '{}'::jsonb
          else jsonb_build_object(
            'items',
            v_error_items
          )
        end
    where run.id = v_rule_run_id
      and run.organization_id = p_organization_id;

    v_response :=
      jsonb_build_object(
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
        error_code =
          'RETURN_INSPECTION_EVALUATION_FAILED',
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
        'localDate',
        v_local_date,
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
        'RETURN_INSPECTION_EVALUATION_FAILED',
        'errorDetail',
        jsonb_build_object(
          'sqlstate',
          v_error_sqlstate,
          'errorCode',
          v_error_message
        )
      );
  end;
end;
$$;

revoke all
on function notification.ensure_return_inspection_rule(
  uuid,
  timestamptz
)
from public, anon, authenticated;

revoke all
on function notification.evaluate_return_inspection(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
from public, anon, authenticated;

grant execute
on function notification.ensure_return_inspection_rule(
  uuid,
  timestamptz
)
to service_role;

grant execute
on function notification.evaluate_return_inspection(
  uuid,
  text,
  timestamptz,
  text,
  uuid,
  text
)
to service_role;

commit;
