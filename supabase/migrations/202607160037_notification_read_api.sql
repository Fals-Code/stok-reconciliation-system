begin;

create or replace function api.notification_list(
  p_lifecycle_status_code text default null,
  p_severity_code text default null,
  p_category_code text default null,
  p_read_state_code text default null,
  p_include_archived boolean default false,
  p_limit integer default 50,
  p_before_last_seen_at timestamptz default null,
  p_before_id uuid default null
)
returns table (
  notification_id uuid,
  rule_code text,
  notification_type_code text,
  category_code text,
  entity_type_code text,
  entity_id uuid,
  episode_no integer,
  lifecycle_status_code text,
  stage_code text,
  severity_code text,
  title text,
  message text,
  action_code text,
  action_route text,
  condition_started_at timestamptz,
  due_at timestamptz,
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  occurrence_count integer,
  acknowledged_at timestamptz,
  acknowledged_by uuid,
  acknowledgment_note text,
  resolved_at timestamptz,
  resolution_code text,
  read_state_code text,
  read_at timestamptz,
  archived_at timestamptz,
  version_no bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, auth, app, notification
as $$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
  v_lifecycle_status_code text :=
    nullif(upper(btrim(coalesce(p_lifecycle_status_code, ''))), '');
  v_severity_code text :=
    nullif(upper(btrim(coalesce(p_severity_code, ''))), '');
  v_category_code text :=
    nullif(upper(btrim(coalesce(p_category_code, ''))), '');
  v_read_state_code text :=
    nullif(upper(btrim(coalesce(p_read_state_code, ''))), '');
  v_include_archived boolean := coalesce(p_include_archived, false);
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

  if v_lifecycle_status_code is not null
     and v_lifecycle_status_code not in (
       'OPEN',
       'ACKNOWLEDGED',
       'RESOLVED'
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_LIFECYCLE_FILTER_INVALID';
  end if;

  if v_severity_code is not null
     and v_severity_code not in (
       'INFO',
       'WARNING',
       'HIGH',
       'CRITICAL'
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_SEVERITY_FILTER_INVALID';
  end if;

  if p_category_code is not null and v_category_code is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_CATEGORY_FILTER_INVALID';
  end if;

  if v_read_state_code = 'ARCHIVED_FOR_USER' then
    v_read_state_code := 'ARCHIVED';
  end if;

  if v_read_state_code is not null
     and v_read_state_code not in (
       'UNREAD',
       'READ',
       'ARCHIVED'
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_READ_STATE_FILTER_INVALID';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_LIST_LIMIT_INVALID';
  end if;

  if (p_before_last_seen_at is null) <> (p_before_id is null) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_LIST_CURSOR_INVALID';
  end if;

  return query
  select
    notification_row.id,
    notification_row.rule_code_snapshot,
    notification_row.notification_type_code,
    notification_row.category_code,
    notification_row.entity_type_code,
    notification_row.entity_id,
    notification_row.episode_no,
    notification_row.lifecycle_status_code,
    notification_row.stage_code,
    notification_row.severity_code,
    notification_row.title,
    notification_row.message,
    notification_row.action_code,
    notification_row.action_route,
    notification_row.condition_started_at,
    notification_row.due_at,
    notification_row.first_seen_at,
    notification_row.last_seen_at,
    notification_row.occurrence_count,
    notification_row.acknowledged_at,
    notification_row.acknowledged_by,
    notification_row.acknowledgment_note,
    notification_row.resolved_at,
    notification_row.resolution_code,
    case
      when user_state.read_state_code = 'ARCHIVED'
        then 'ARCHIVED_FOR_USER'
      else coalesce(user_state.read_state_code, 'UNREAD')
    end,
    user_state.read_at,
    user_state.archived_at,
    notification_row.version_no
  from notification.notifications notification_row
  left join notification.user_states user_state
    on user_state.organization_id = notification_row.organization_id
   and user_state.notification_id = notification_row.id
   and user_state.user_id = v_user_id
  where notification_row.organization_id = v_organization_id
    and (
      v_lifecycle_status_code is null
      or notification_row.lifecycle_status_code =
        v_lifecycle_status_code
    )
    and (
      v_severity_code is null
      or notification_row.severity_code = v_severity_code
    )
    and (
      v_category_code is null
      or notification_row.category_code = v_category_code
    )
    and (
      v_read_state_code is null
      or coalesce(user_state.read_state_code, 'UNREAD') =
        v_read_state_code
    )
    and (
      v_include_archived
      or v_read_state_code = 'ARCHIVED'
      or coalesce(user_state.read_state_code, 'UNREAD') <> 'ARCHIVED'
    )
    and (
      p_before_last_seen_at is null
      or (
        notification_row.last_seen_at,
        notification_row.id
      ) < (
        p_before_last_seen_at,
        p_before_id
      )
    )
  order by
    notification_row.last_seen_at desc,
    notification_row.id desc
  limit p_limit;
end;
$$;

create or replace function api.notification_detail(
  p_notification_id uuid
)
returns table (
  notification_id uuid,
  previous_notification_id uuid,
  rule_id uuid,
  rule_code text,
  rule_version text,
  template_version text,
  notification_type_code text,
  category_code text,
  entity_type_code text,
  entity_id uuid,
  episode_no integer,
  lifecycle_status_code text,
  stage_code text,
  severity_code text,
  title text,
  message text,
  action_code text,
  action_route text,
  condition_started_at timestamptz,
  due_at timestamptz,
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  last_reminded_at timestamptz,
  occurrence_count integer,
  acknowledged_at timestamptz,
  acknowledged_by uuid,
  acknowledged_by_display_name text,
  acknowledgment_note text,
  resolved_at timestamptz,
  resolution_code text,
  resolution_snapshot jsonb,
  source_snapshot jsonb,
  config_snapshot jsonb,
  read_state_code text,
  read_at timestamptz,
  archived_at timestamptz,
  last_seen_version_no bigint,
  version_no bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, auth, app, notification
as $$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
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

  if p_notification_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ID_REQUIRED';
  end if;

  if not exists (
    select 1
    from notification.notifications notification_row
    where notification_row.id = p_notification_id
      and notification_row.organization_id = v_organization_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_NOT_FOUND';
  end if;

  return query
  select
    notification_row.id,
    notification_row.previous_notification_id,
    notification_row.rule_id,
    notification_row.rule_code_snapshot,
    notification_row.rule_version_snapshot,
    notification_row.template_version_snapshot,
    notification_row.notification_type_code,
    notification_row.category_code,
    notification_row.entity_type_code,
    notification_row.entity_id,
    notification_row.episode_no,
    notification_row.lifecycle_status_code,
    notification_row.stage_code,
    notification_row.severity_code,
    notification_row.title,
    notification_row.message,
    notification_row.action_code,
    notification_row.action_route,
    notification_row.condition_started_at,
    notification_row.due_at,
    notification_row.first_seen_at,
    notification_row.last_seen_at,
    notification_row.last_reminded_at,
    notification_row.occurrence_count,
    notification_row.acknowledged_at,
    notification_row.acknowledged_by,
    acknowledger.display_name,
    notification_row.acknowledgment_note,
    notification_row.resolved_at,
    notification_row.resolution_code,
    notification_row.resolution_snapshot,
    notification_row.source_snapshot,
    notification_row.config_snapshot,
    case
      when user_state.read_state_code = 'ARCHIVED'
        then 'ARCHIVED_FOR_USER'
      else coalesce(user_state.read_state_code, 'UNREAD')
    end,
    user_state.read_at,
    user_state.archived_at,
    user_state.last_seen_version_no,
    notification_row.version_no,
    notification_row.created_at,
    notification_row.updated_at
  from notification.notifications notification_row
  left join app.user_profiles acknowledger
    on acknowledger.organization_id = notification_row.organization_id
   and acknowledger.user_id = notification_row.acknowledged_by
  left join notification.user_states user_state
    on user_state.organization_id = notification_row.organization_id
   and user_state.notification_id = notification_row.id
   and user_state.user_id = v_user_id
  where notification_row.id = p_notification_id
    and notification_row.organization_id = v_organization_id;
end;
$$;

create or replace function api.notification_unread_count()
returns bigint
language plpgsql
stable
security definer
set search_path = pg_catalog, auth, app, notification
as $$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
  v_count bigint;
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

  select count(*)
  into v_count
  from notification.notifications notification_row
  left join notification.user_states user_state
    on user_state.organization_id = notification_row.organization_id
   and user_state.notification_id = notification_row.id
   and user_state.user_id = v_user_id
  where notification_row.organization_id = v_organization_id
    and notification_row.lifecycle_status_code in (
      'OPEN',
      'ACKNOWLEDGED'
    )
    and coalesce(user_state.read_state_code, 'UNREAD') = 'UNREAD';

  return v_count;
end;
$$;

create or replace function api.notification_event_history(
  p_notification_id uuid,
  p_limit integer default 100,
  p_after_occurred_at timestamptz default null,
  p_after_id uuid default null
)
returns table (
  event_id uuid,
  event_type_code text,
  from_lifecycle_status_code text,
  to_lifecycle_status_code text,
  from_stage_code text,
  to_stage_code text,
  from_severity_code text,
  to_severity_code text,
  source_snapshot jsonb,
  note text,
  actor_type_code text,
  actor_user_id uuid,
  actor_display_name text,
  process_name text,
  occurred_at timestamptz,
  correlation_id uuid
)
language plpgsql
stable
security definer
set search_path = pg_catalog, auth, app, notification
as $$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
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

  if p_notification_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ID_REQUIRED';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVENT_LIMIT_INVALID';
  end if;

  if (p_after_occurred_at is null) <> (p_after_id is null) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVENT_CURSOR_INVALID';
  end if;

  if not exists (
    select 1
    from notification.notifications notification_row
    where notification_row.id = p_notification_id
      and notification_row.organization_id = v_organization_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_NOT_FOUND';
  end if;

  return query
  select
    event_row.id,
    event_row.event_type_code,
    event_row.from_lifecycle_status_code,
    event_row.to_lifecycle_status_code,
    event_row.from_stage_code,
    event_row.to_stage_code,
    event_row.from_severity_code,
    event_row.to_severity_code,
    event_row.source_snapshot,
    event_row.note,
    event_row.actor_type_code,
    event_row.actor_user_id,
    actor_profile.display_name,
    event_row.process_name,
    event_row.occurred_at,
    event_row.correlation_id
  from notification.notification_events event_row
  left join app.user_profiles actor_profile
    on actor_profile.organization_id = event_row.organization_id
   and actor_profile.user_id = event_row.actor_user_id
  where event_row.organization_id = v_organization_id
    and event_row.notification_id = p_notification_id
    and (
      p_after_occurred_at is null
      or (
        event_row.occurred_at,
        event_row.id
      ) > (
        p_after_occurred_at,
        p_after_id
      )
    )
  order by
    event_row.occurred_at,
    event_row.id
  limit p_limit;
end;
$$;

revoke all
on function api.notification_list(
  text,
  text,
  text,
  text,
  boolean,
  integer,
  timestamptz,
  uuid
)
from public, anon, authenticated;

revoke all
on function api.notification_detail(uuid)
from public, anon, authenticated;

revoke all
on function api.notification_unread_count()
from public, anon, authenticated;

revoke all
on function api.notification_event_history(
  uuid,
  integer,
  timestamptz,
  uuid
)
from public, anon, authenticated;

grant execute
on function api.notification_list(
  text,
  text,
  text,
  text,
  boolean,
  integer,
  timestamptz,
  uuid
)
to authenticated;

grant execute
on function api.notification_detail(uuid)
to authenticated;

grant execute
on function api.notification_unread_count()
to authenticated;

grant execute
on function api.notification_event_history(
  uuid,
  integer,
  timestamptz,
  uuid
)
to authenticated;

commit;
