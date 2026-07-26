begin;

-- Read-only operational queue. Domain evaluators remain authoritative for
-- stages, severity, due dates, and notification episode resolution.
create index idx_notifications_today_control_active
on notification.notifications (
  organization_id,
  rule_code_snapshot,
  severity_code,
  (coalesce(due_at, condition_started_at)),
  id
)
where lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  and rule_code_snapshot in (
    'RECONCILIATION_ISSUE_HIGH_CRITICAL',
    'RECONCILIATION_RUN_FAILED',
    'CLAIM_DEADLINE',
    'RETURN_INSPECTION_PENDING',
    'EXPIRY_RISK',
    'STOCKTAKE_RECOUNT_REQUIRED',
    'STOCKTAKE_POST_FAILED'
  );

create index idx_notification_outbox_today_control_failure
on notification.outbox_events (
  organization_id,
  status_code,
  available_at,
  id
)
where status_code in ('FAILED_RETRYABLE', 'FAILED_FINAL');

create index idx_notification_rule_runs_today_control_failure
on notification.rule_runs (
  organization_id,
  status_code,
  completed_at,
  id
)
where status_code in ('PARTIALLY_FAILED', 'FAILED');

create or replace function api.today_control_center_work_items(
  p_severity_code text default null,
  p_work_type_code text default null,
  p_limit integer default 50,
  p_after_severity_rank integer default null,
  p_after_sort_at timestamptz default null,
  p_after_work_item_id text default null
)
returns table (
  work_item_id text,
  organization_id uuid,
  work_type_code text,
  severity_code text,
  title text,
  summary text,
  source_entity_type_code text,
  source_entity_id uuid,
  source_reference text,
  occurred_at timestamptz,
  due_at timestamptz,
  route_path text,
  notification_id uuid,
  resolution_status text,
  sort_severity_rank integer,
  sort_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, auth, app, notification
as $$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
  v_severity_code text :=
    nullif(upper(btrim(coalesce(p_severity_code, ''))), '');
  v_work_type_code text :=
    nullif(upper(btrim(coalesce(p_work_type_code, ''))), '');
begin
  if v_user_id is null then
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

  if v_severity_code is not null
     and v_severity_code not in ('INFO', 'WARNING', 'HIGH', 'CRITICAL') then
    raise exception using
      errcode = 'P0001',
      message = 'TODAY_CONTROL_CENTER_SEVERITY_FILTER_INVALID';
  end if;

  if v_work_type_code is not null
     and v_work_type_code not in (
       'RECONCILIATION_ISSUE',
       'RECONCILIATION_RUN_FAILED',
       'TIKTOK_CLAIM_DEADLINE',
       'RETURN_INSPECTION_PENDING',
       'BATCH_EXPIRY',
       'STOCKTAKE_RECOUNT_REQUIRED',
       'STOCKTAKE_POST_FAILED',
       'NOTIFICATION_OUTBOX_FAILURE',
       'NOTIFICATION_RULE_RUN_FAILURE'
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'TODAY_CONTROL_CENTER_WORK_TYPE_FILTER_INVALID';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'TODAY_CONTROL_CENTER_LIMIT_INVALID';
  end if;

  if (
    (p_after_severity_rank is null)
    <> (p_after_sort_at is null)
  )
  or (
    (p_after_severity_rank is null)
    <> (nullif(btrim(coalesce(p_after_work_item_id, '')), '') is null)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'TODAY_CONTROL_CENTER_CURSOR_INVALID';
  end if;

  if p_after_severity_rank is not null
     and p_after_severity_rank not between 1 and 4 then
    raise exception using
      errcode = 'P0001',
      message = 'TODAY_CONTROL_CENTER_CURSOR_INVALID';
  end if;

  return query
  with work_items as (
    select
      concat_ws(
        ':',
        'NOTIFICATION',
        notification_row.rule_code_snapshot,
        notification_row.entity_type_code,
        notification_row.entity_id::text,
        notification_row.episode_no::text
      ) as work_item_id,
      notification_row.organization_id,
      case notification_row.rule_code_snapshot
        when 'RECONCILIATION_ISSUE_HIGH_CRITICAL'
          then 'RECONCILIATION_ISSUE'
        when 'RECONCILIATION_RUN_FAILED'
          then 'RECONCILIATION_RUN_FAILED'
        when 'CLAIM_DEADLINE'
          then 'TIKTOK_CLAIM_DEADLINE'
        when 'RETURN_INSPECTION_PENDING'
          then 'RETURN_INSPECTION_PENDING'
        when 'EXPIRY_RISK'
          then 'BATCH_EXPIRY'
        when 'STOCKTAKE_RECOUNT_REQUIRED'
          then 'STOCKTAKE_RECOUNT_REQUIRED'
        when 'STOCKTAKE_POST_FAILED'
          then 'STOCKTAKE_POST_FAILED'
      end as work_type_code,
      notification_row.severity_code,
      notification_row.title,
      notification_row.message as summary,
      notification_row.entity_type_code as source_entity_type_code,
      notification_row.entity_id as source_entity_id,
      concat_ws(
        ':',
        notification_row.rule_code_snapshot,
        notification_row.stage_code
      ) as source_reference,
      notification_row.condition_started_at as occurred_at,
      notification_row.due_at,
      notification_row.action_route as route_path,
      notification_row.id as notification_id,
      notification_row.lifecycle_status_code as resolution_status,
      case notification_row.severity_code
        when 'CRITICAL' then 1
        when 'HIGH' then 2
        when 'WARNING' then 3
        else 4
      end as sort_severity_rank,
      coalesce(
        notification_row.due_at,
        notification_row.condition_started_at
      ) as sort_at
    from notification.notifications notification_row
    where notification_row.organization_id = v_organization_id
      and notification_row.lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
      and notification_row.rule_code_snapshot in (
        'RECONCILIATION_ISSUE_HIGH_CRITICAL',
        'RECONCILIATION_RUN_FAILED',
        'CLAIM_DEADLINE',
        'RETURN_INSPECTION_PENDING',
        'EXPIRY_RISK',
        'STOCKTAKE_RECOUNT_REQUIRED',
        'STOCKTAKE_POST_FAILED'
      )

    union all

    select
      concat('OUTBOX:', outbox_event.id::text),
      outbox_event.organization_id,
      'NOTIFICATION_OUTBOX_FAILURE',
      case outbox_event.status_code
        when 'FAILED_FINAL' then 'CRITICAL'
        else 'HIGH'
      end,
      'Kegagalan outbox notifikasi',
      concat_ws(
        ' ',
        outbox_event.event_type_code,
        outbox_event.last_error_code
      ),
      'NOTIFICATION_OUTBOX_EVENT',
      outbox_event.id,
      outbox_event.source_event_key,
      outbox_event.occurred_at,
      outbox_event.available_at,
      null,
      null,
      outbox_event.status_code,
      case outbox_event.status_code
        when 'FAILED_FINAL' then 1
        else 2
      end,
      outbox_event.available_at
    from notification.outbox_events outbox_event
    where outbox_event.organization_id = v_organization_id
      and outbox_event.status_code in ('FAILED_RETRYABLE', 'FAILED_FINAL')

    union all

    select
      concat('RULE_RUN:', rule_run.id::text),
      rule_run.organization_id,
      'NOTIFICATION_RULE_RUN_FAILURE',
      case rule_run.status_code
        when 'FAILED' then 'CRITICAL'
        else 'HIGH'
      end,
      'Kegagalan evaluasi notifikasi',
      concat_ws(' ', rule_run.rule_code_snapshot, rule_run.error_code),
      'NOTIFICATION_RULE_RUN',
      rule_run.id,
      rule_run.idempotency_key,
      rule_run.started_at,
      rule_run.completed_at,
      null,
      null,
      rule_run.status_code,
      case rule_run.status_code
        when 'FAILED' then 1
        else 2
      end,
      coalesce(rule_run.completed_at, rule_run.started_at)
    from notification.rule_runs rule_run
    where rule_run.organization_id = v_organization_id
      and rule_run.status_code in ('PARTIALLY_FAILED', 'FAILED')
  )
  select
    item.work_item_id,
    item.organization_id,
    item.work_type_code,
    item.severity_code,
    item.title,
    item.summary,
    item.source_entity_type_code,
    item.source_entity_id,
    item.source_reference,
    item.occurred_at,
    item.due_at,
    item.route_path,
    item.notification_id,
    item.resolution_status,
    item.sort_severity_rank,
    item.sort_at
  from work_items item
  where (v_severity_code is null or item.severity_code = v_severity_code)
    and (v_work_type_code is null or item.work_type_code = v_work_type_code)
    and (
      p_after_severity_rank is null
      or (
        item.sort_severity_rank,
        item.sort_at,
        item.work_item_id
      ) > (
        p_after_severity_rank,
        p_after_sort_at,
        p_after_work_item_id
      )
    )
  order by
    item.sort_severity_rank,
    item.sort_at,
    item.work_item_id
  limit p_limit;
end;
$$;

revoke all
on function api.today_control_center_work_items(
  text,
  text,
  integer,
  integer,
  timestamptz,
  text
)
from public, anon, authenticated;

grant execute
on function api.today_control_center_work_items(
  text,
  text,
  integer,
  integer,
  timestamptz,
  text
)
to authenticated;

commit;
