begin;

create or replace function api.notification_outbox_actionable_list(
  p_status_code text default null,
  p_limit integer default 50
)
returns table (
  outbox_event_id uuid,
  event_type_code text,
  source_event_key text,
  entity_type_code text,
  entity_id uuid,
  occurred_at timestamptz,
  status_code text,
  attempt_count integer,
  retry_budget_started_at_attempt integer,
  retry_cycle_attempt_count integer,
  available_at timestamptz,
  locked_at timestamptz,
  locked_by text,
  completed_at timestamptz,
  last_error_code text,
  last_error_detail jsonb,
  correlation_id uuid,
  created_at timestamptz,
  can_retry boolean,
  is_stale_processing boolean
)
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
  v_status_code text :=
    upper(
      btrim(
        coalesce(
          p_status_code,
          'ALL'
        )
      )
    );
  v_as_of timestamptz := statement_timestamp();
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

  if v_status_code not in (
    'ALL',
    'PENDING',
    'PROCESSING',
    'FAILED_RETRYABLE',
    'FAILED_FINAL'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_OUTBOX_STATUS_FILTER_INVALID';
  end if;

  if p_limit < 1 or p_limit > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_OUTBOX_LIST_LIMIT_INVALID';
  end if;

  return query
  select
    event_row.id,
    event_row.event_type_code,
    event_row.source_event_key,
    event_row.entity_type_code,
    event_row.entity_id,
    event_row.occurred_at,
    event_row.status_code,
    event_row.attempt_count,
    event_row.retry_budget_started_at_attempt,
    event_row.attempt_count
      - event_row.retry_budget_started_at_attempt,
    event_row.available_at,
    event_row.locked_at,
    event_row.locked_by,
    event_row.completed_at,
    event_row.last_error_code,
    event_row.last_error_detail,
    event_row.correlation_id,
    event_row.created_at,
    event_row.status_code in (
      'FAILED_RETRYABLE',
      'FAILED_FINAL'
    ),
    event_row.status_code = 'PROCESSING'
      and event_row.locked_at
          <= v_as_of - interval '5 minutes'
  from notification.outbox_events event_row
  where event_row.organization_id = v_organization_id
    and event_row.status_code in (
      'PENDING',
      'PROCESSING',
      'FAILED_RETRYABLE',
      'FAILED_FINAL'
    )
    and (
      v_status_code = 'ALL'
      or event_row.status_code = v_status_code
    )
  order by
    case event_row.status_code
      when 'FAILED_FINAL' then 1
      when 'FAILED_RETRYABLE' then 2
      when 'PROCESSING' then
        case
          when event_row.locked_at
               <= v_as_of - interval '5 minutes'
            then 3
          else 5
        end
      when 'PENDING' then 4
      else 6
    end,
    event_row.available_at,
    event_row.created_at,
    event_row.id
  limit p_limit;
end;
$$;

revoke all
on function api.notification_outbox_actionable_list(
  text,
  integer
)
from public, anon, authenticated;

grant execute
on function api.notification_outbox_actionable_list(
  text,
  integer
)
to authenticated;

commit;
