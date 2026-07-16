begin;

create or replace function notification.append_notification_event(
  p_organization_id uuid,
  p_notification_id uuid,
  p_event_type_code text,
  p_occurred_at timestamptz,
  p_correlation_id uuid,
  p_source_snapshot jsonb default '{}'::jsonb,
  p_note text default null,
  p_from_lifecycle_status_code text default null,
  p_to_lifecycle_status_code text default null,
  p_from_stage_code text default null,
  p_to_stage_code text default null,
  p_from_severity_code text default null,
  p_to_severity_code text default null,
  p_actor_user_id uuid default null,
  p_process_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, notification, app
as $$
declare
  v_event_id uuid;
  v_process_name text :=
    nullif(btrim(coalesce(p_process_name, '')), '');
  v_actor_type_code text;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if p_notification_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ID_REQUIRED';
  end if;

  if p_occurred_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVENT_TIME_REQUIRED';
  end if;

  if p_correlation_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_CORRELATION_ID_REQUIRED';
  end if;

  if btrim(coalesce(p_event_type_code, '')) = '' then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVENT_TYPE_REQUIRED';
  end if;

  if p_source_snapshot is null
     or jsonb_typeof(p_source_snapshot) <> 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_EVENT_SNAPSHOT_INVALID';
  end if;

  if (p_actor_user_id is null) = (v_process_name is null) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_CONTEXT_INVALID';
  end if;

  if p_actor_user_id is not null then
    if not exists (
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

    v_actor_type_code := 'USER';
  else
    v_actor_type_code := 'SYSTEM_PROCESS';
  end if;

  if not exists (
    select 1
    from notification.notifications notification_row
    where notification_row.id = p_notification_id
      and notification_row.organization_id = p_organization_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_NOT_FOUND';
  end if;

  insert into notification.notification_events (
    organization_id,
    notification_id,
    event_type_code,
    from_lifecycle_status_code,
    to_lifecycle_status_code,
    from_stage_code,
    to_stage_code,
    from_severity_code,
    to_severity_code,
    source_snapshot,
    note,
    actor_type_code,
    actor_user_id,
    process_name,
    occurred_at,
    correlation_id
  )
  values (
    p_organization_id,
    p_notification_id,
    upper(btrim(p_event_type_code)),
    p_from_lifecycle_status_code,
    p_to_lifecycle_status_code,
    p_from_stage_code,
    p_to_stage_code,
    p_from_severity_code,
    p_to_severity_code,
    p_source_snapshot,
    nullif(btrim(coalesce(p_note, '')), ''),
    v_actor_type_code,
    p_actor_user_id,
    v_process_name,
    p_occurred_at,
    p_correlation_id
  )
  returning id into v_event_id;

  return v_event_id;
end;
$$;

create or replace function notification.reset_user_read_states(
  p_organization_id uuid,
  p_notification_id uuid,
  p_actor_user_id uuid default null,
  p_process_name text default null
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, notification, app
as $$
declare
  v_process_name text :=
    nullif(btrim(coalesce(p_process_name, '')), '');
  v_reset_count integer;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if p_notification_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ID_REQUIRED';
  end if;

  if (p_actor_user_id is null) = (v_process_name is null) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_CONTEXT_INVALID';
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

  if not exists (
    select 1
    from notification.notifications notification_row
    where notification_row.id = p_notification_id
      and notification_row.organization_id = p_organization_id
      and notification_row.lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'ACTIVE_NOTIFICATION_NOT_FOUND';
  end if;

  insert into notification.user_states as existing_state (
    organization_id,
    notification_id,
    user_id,
    read_state_code,
    read_at,
    archived_at,
    last_seen_version_no,
    created_at,
    updated_at
  )
  select
    p_organization_id,
    p_notification_id,
    profile.user_id,
    'UNREAD',
    null,
    null,
    null,
    clock_timestamp(),
    clock_timestamp()
  from app.user_profiles profile
  where profile.organization_id = p_organization_id
    and profile.role_code = 'ADMIN'
    and profile.is_active
  on conflict (notification_id, user_id) do update
  set
    organization_id = excluded.organization_id,
    read_state_code = 'UNREAD',
    read_at = null,
    archived_at = null
  where existing_state.read_state_code <> 'UNREAD'
     or existing_state.read_at is not null
     or existing_state.archived_at is not null;

  get diagnostics v_reset_count = row_count;

  return v_reset_count;
end;
$$;

create or replace function notification.upsert_active_notification(
  p_organization_id uuid,
  p_rule_id uuid,
  p_entity_id uuid,
  p_deduplication_key text,
  p_stage_code text,
  p_severity_code text,
  p_title text,
  p_message text,
  p_action_route text,
  p_condition_started_at timestamptz,
  p_observed_at timestamptz,
  p_due_at timestamptz default null,
  p_source_snapshot jsonb default '{}'::jsonb,
  p_stage_direction_code text default 'UNCHANGED',
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
  v_rule notification.rules%rowtype;
  v_active notification.notifications%rowtype;
  v_previous notification.notifications%rowtype;
  v_notification_id uuid;
  v_previous_notification_id uuid;
  v_episode_no integer;
  v_version_no bigint;
  v_process_name text :=
    nullif(btrim(coalesce(p_process_name, '')), '');
  v_stage_direction_code text :=
    upper(btrim(coalesce(p_stage_direction_code, 'UNCHANGED')));
  v_deduplication_suffix text;
  v_deduplication_key text;
  v_deduplication_hash text;
  v_old_severity_rank integer;
  v_new_severity_rank integer;
  v_stage_changed boolean;
  v_severity_changed boolean;
  v_severity_escalated boolean;
  v_source_changed boolean;
  v_reset_count integer := 0;
  v_action text;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if p_rule_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_RULE_REQUIRED';
  end if;

  if p_entity_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ENTITY_REQUIRED';
  end if;

  if p_observed_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_OBSERVED_AT_REQUIRED';
  end if;

  if p_condition_started_at is null
     or p_condition_started_at > p_observed_at then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_CONDITION_TIME_INVALID';
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

  select rule.*
  into v_rule
  from notification.rules rule
  where rule.id = p_rule_id
    and rule.organization_id = p_organization_id
    and rule.is_active
    and rule.effective_from <= p_observed_at
    and (
      rule.effective_to is null
      or rule.effective_to > p_observed_at
    )
  for share;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_RULE_NOT_FOUND';
  end if;

  if btrim(coalesce(p_stage_code, '')) = '' then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_STAGE_REQUIRED';
  end if;

  if upper(btrim(coalesce(p_severity_code, ''))) not in (
    'INFO',
    'WARNING',
    'HIGH',
    'CRITICAL'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_SEVERITY_INVALID';
  end if;

  if btrim(coalesce(p_title, '')) = ''
     or length(btrim(p_title)) > 300 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_TITLE_INVALID';
  end if;

  if btrim(coalesce(p_message, '')) = ''
     or length(btrim(p_message)) > 4000 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_MESSAGE_INVALID';
  end if;

  if btrim(coalesce(p_action_route, '')) = ''
     or left(btrim(p_action_route), 1) <> '/'
     or length(btrim(p_action_route)) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTION_ROUTE_INVALID';
  end if;

  if p_source_snapshot is null
     or jsonb_typeof(p_source_snapshot) <> 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_SOURCE_SNAPSHOT_INVALID';
  end if;

  if v_stage_direction_code not in (
    'UNCHANGED',
    'ESCALATED',
    'DEESCALATED'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_STAGE_DIRECTION_INVALID';
  end if;

  v_deduplication_suffix :=
    lower(
      regexp_replace(
        btrim(coalesce(p_deduplication_key, '')),
        '[[:space:]]+',
        ' ',
        'g'
      )
    );

  if v_deduplication_suffix = '' then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_DEDUPLICATION_KEY_REQUIRED';
  end if;

  v_deduplication_key :=
    lower(v_rule.code)
    || ':'
    || lower(v_rule.entity_type_code)
    || ':'
    || p_entity_id::text
    || ':'
    || v_deduplication_suffix;

  v_deduplication_hash :=
    encode(
      extensions.digest(v_deduplication_key, 'sha256'),
      'hex'
    );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':' || v_deduplication_hash,
      0
    )
  );

  select notification_row.*
  into v_active
  from notification.notifications notification_row
  where notification_row.organization_id = p_organization_id
    and notification_row.deduplication_hash = v_deduplication_hash
    and notification_row.lifecycle_status_code in (
      'OPEN',
      'ACKNOWLEDGED'
    )
  for update;

  if v_active.id is not null then
    if p_observed_at < v_active.last_seen_at then
      raise exception using
        errcode = 'P0001',
        message = 'NOTIFICATION_OBSERVED_AT_STALE';
    end if;

    v_stage_changed := v_active.stage_code <> btrim(p_stage_code);

    if v_stage_changed
       and v_stage_direction_code = 'UNCHANGED' then
      raise exception using
        errcode = 'P0001',
        message = 'NOTIFICATION_STAGE_DIRECTION_REQUIRED';
    end if;

    if not v_stage_changed
       and v_stage_direction_code <> 'UNCHANGED' then
      raise exception using
        errcode = 'P0001',
        message = 'NOTIFICATION_STAGE_DIRECTION_MISMATCH';
    end if;

    v_old_severity_rank :=
      case v_active.severity_code
        when 'INFO' then 1
        when 'WARNING' then 2
        when 'HIGH' then 3
        when 'CRITICAL' then 4
      end;

    v_new_severity_rank :=
      case upper(btrim(p_severity_code))
        when 'INFO' then 1
        when 'WARNING' then 2
        when 'HIGH' then 3
        when 'CRITICAL' then 4
      end;

    v_severity_changed :=
      v_active.severity_code <> upper(btrim(p_severity_code));

    v_severity_escalated :=
      v_severity_changed
      and v_new_severity_rank > v_old_severity_rank;

    v_source_changed :=
      v_active.rule_id <> v_rule.id
      or v_active.rule_version_snapshot <> v_rule.version
      or v_active.template_version_snapshot <> v_rule.template_version
      or v_active.title <> btrim(p_title)
      or v_active.message <> btrim(p_message)
      or v_active.action_code <> v_rule.action_code
      or v_active.action_route <> btrim(p_action_route)
      or v_active.due_at is distinct from p_due_at
      or v_active.source_snapshot is distinct from p_source_snapshot
      or v_active.config_snapshot is distinct from v_rule.config;

    update notification.notifications
    set
      rule_id = v_rule.id,
      rule_code_snapshot = v_rule.code,
      rule_version_snapshot = v_rule.version,
      template_version_snapshot = v_rule.template_version,
      notification_type_code = v_rule.code,
      category_code = v_rule.category_code,
      entity_type_code = v_rule.entity_type_code,
      entity_id = p_entity_id,
      stage_code = btrim(p_stage_code),
      severity_code = upper(btrim(p_severity_code)),
      title = btrim(p_title),
      message = btrim(p_message),
      action_code = v_rule.action_code,
      action_route = btrim(p_action_route),
      condition_started_at = least(
        v_active.condition_started_at,
        p_condition_started_at
      ),
      due_at = p_due_at,
      last_seen_at = p_observed_at,
      occurrence_count = v_active.occurrence_count + 1,
      source_snapshot = p_source_snapshot,
      config_snapshot = v_rule.config
    where id = v_active.id
      and organization_id = p_organization_id
    returning version_no into v_version_no;

    if v_stage_changed then
      perform notification.append_notification_event(
        p_organization_id => p_organization_id,
        p_notification_id => v_active.id,
        p_event_type_code =>
          case v_stage_direction_code
            when 'ESCALATED' then 'STAGE_ESCALATED'
            else 'STAGE_DEESCALATED'
          end,
        p_occurred_at => p_observed_at,
        p_correlation_id => p_correlation_id,
        p_source_snapshot => p_source_snapshot,
        p_from_lifecycle_status_code =>
          v_active.lifecycle_status_code,
        p_to_lifecycle_status_code =>
          v_active.lifecycle_status_code,
        p_from_stage_code => v_active.stage_code,
        p_to_stage_code => btrim(p_stage_code),
        p_from_severity_code => v_active.severity_code,
        p_to_severity_code => upper(btrim(p_severity_code)),
        p_actor_user_id => p_actor_user_id,
        p_process_name => v_process_name
      );
    end if;

    if v_severity_changed then
      perform notification.append_notification_event(
        p_organization_id => p_organization_id,
        p_notification_id => v_active.id,
        p_event_type_code => 'SEVERITY_CHANGED',
        p_occurred_at => p_observed_at,
        p_correlation_id => p_correlation_id,
        p_source_snapshot => p_source_snapshot,
        p_from_lifecycle_status_code =>
          v_active.lifecycle_status_code,
        p_to_lifecycle_status_code =>
          v_active.lifecycle_status_code,
        p_from_stage_code => v_active.stage_code,
        p_to_stage_code => btrim(p_stage_code),
        p_from_severity_code => v_active.severity_code,
        p_to_severity_code => upper(btrim(p_severity_code)),
        p_actor_user_id => p_actor_user_id,
        p_process_name => v_process_name
      );
    end if;

    if v_source_changed then
      perform notification.append_notification_event(
        p_organization_id => p_organization_id,
        p_notification_id => v_active.id,
        p_event_type_code => 'SOURCE_SNAPSHOT_UPDATED',
        p_occurred_at => p_observed_at,
        p_correlation_id => p_correlation_id,
        p_source_snapshot => p_source_snapshot,
        p_from_lifecycle_status_code =>
          v_active.lifecycle_status_code,
        p_to_lifecycle_status_code =>
          v_active.lifecycle_status_code,
        p_from_stage_code => v_active.stage_code,
        p_to_stage_code => btrim(p_stage_code),
        p_from_severity_code => v_active.severity_code,
        p_to_severity_code => upper(btrim(p_severity_code)),
        p_actor_user_id => p_actor_user_id,
        p_process_name => v_process_name
      );
    end if;

    if v_stage_direction_code = 'ESCALATED'
       or v_severity_escalated then
      v_reset_count :=
        notification.reset_user_read_states(
          p_organization_id => p_organization_id,
          p_notification_id => v_active.id,
          p_actor_user_id => p_actor_user_id,
          p_process_name => v_process_name
        );

      if v_reset_count > 0 then
        perform notification.append_notification_event(
          p_organization_id => p_organization_id,
          p_notification_id => v_active.id,
          p_event_type_code => 'READ_STATE_RESET_BY_ESCALATION',
          p_occurred_at => p_observed_at,
          p_correlation_id => p_correlation_id,
          p_source_snapshot => jsonb_build_object(
            'resetUserCount',
            v_reset_count,
            'notificationVersion',
            v_version_no
          ),
          p_note => format(
            '%s active Admin notification state(s) reset to UNREAD.',
            v_reset_count
          ),
          p_from_lifecycle_status_code =>
            v_active.lifecycle_status_code,
          p_to_lifecycle_status_code =>
            v_active.lifecycle_status_code,
          p_from_stage_code => v_active.stage_code,
          p_to_stage_code => btrim(p_stage_code),
          p_from_severity_code => v_active.severity_code,
          p_to_severity_code => upper(btrim(p_severity_code)),
          p_actor_user_id => p_actor_user_id,
          p_process_name => v_process_name
        );
      end if;
    end if;

    v_action :=
      case
        when v_stage_changed
          or v_severity_changed
          or v_source_changed
          then 'UPDATED'
        else 'SEEN_AGAIN'
      end;

    return jsonb_build_object(
      'notificationId', v_active.id,
      'action', v_action,
      'episodeNo', v_active.episode_no,
      'previousNotificationId', v_active.previous_notification_id,
      'deduplicationHash', v_deduplication_hash,
      'occurrenceCount', v_active.occurrence_count + 1,
      'versionNo', v_version_no,
      'resetUserCount', v_reset_count
    );
  end if;

  select notification_row.*
  into v_previous
  from notification.notifications notification_row
  where notification_row.organization_id = p_organization_id
    and notification_row.deduplication_hash = v_deduplication_hash
  order by notification_row.episode_no desc
  limit 1;

  if v_previous.id is null then
    v_episode_no := 1;
    v_previous_notification_id := null;
    v_action := 'CREATED';
  else
    if v_previous.lifecycle_status_code <> 'RESOLVED' then
      raise exception using
        errcode = 'P0001',
        message = 'NOTIFICATION_ACTIVE_EPISODE_CONFLICT';
    end if;

    v_episode_no := v_previous.episode_no + 1;
    v_previous_notification_id := v_previous.id;
    v_action := 'REOPENED_AS_NEW_EPISODE';
  end if;

  insert into notification.notifications (
    organization_id,
    rule_id,
    rule_code_snapshot,
    rule_version_snapshot,
    template_version_snapshot,
    notification_type_code,
    category_code,
    entity_type_code,
    entity_id,
    episode_no,
    previous_notification_id,
    deduplication_key,
    deduplication_hash,
    lifecycle_status_code,
    stage_code,
    severity_code,
    title,
    message,
    action_code,
    action_route,
    condition_started_at,
    due_at,
    first_seen_at,
    last_seen_at,
    occurrence_count,
    source_snapshot,
    config_snapshot
  )
  values (
    p_organization_id,
    v_rule.id,
    v_rule.code,
    v_rule.version,
    v_rule.template_version,
    v_rule.code,
    v_rule.category_code,
    v_rule.entity_type_code,
    p_entity_id,
    v_episode_no,
    v_previous_notification_id,
    v_deduplication_key,
    v_deduplication_hash,
    'OPEN',
    btrim(p_stage_code),
    upper(btrim(p_severity_code)),
    btrim(p_title),
    btrim(p_message),
    v_rule.action_code,
    btrim(p_action_route),
    p_condition_started_at,
    p_due_at,
    p_observed_at,
    p_observed_at,
    1,
    p_source_snapshot,
    v_rule.config
  )
  returning id, version_no
  into v_notification_id, v_version_no;

  perform notification.append_notification_event(
    p_organization_id => p_organization_id,
    p_notification_id => v_notification_id,
    p_event_type_code => v_action,
    p_occurred_at => p_observed_at,
    p_correlation_id => p_correlation_id,
    p_source_snapshot => p_source_snapshot,
    p_from_lifecycle_status_code =>
      case
        when v_previous_notification_id is null then null
        else 'RESOLVED'
      end,
    p_to_lifecycle_status_code => 'OPEN',
    p_from_stage_code =>
      case
        when v_previous_notification_id is null
          then null
        else v_previous.stage_code
      end,
    p_to_stage_code => btrim(p_stage_code),
    p_from_severity_code =>
      case
        when v_previous_notification_id is null
          then null
        else v_previous.severity_code
      end,
    p_to_severity_code => upper(btrim(p_severity_code)),
    p_actor_user_id => p_actor_user_id,
    p_process_name => v_process_name
  );

  return jsonb_build_object(
    'notificationId', v_notification_id,
    'action', v_action,
    'episodeNo', v_episode_no,
    'previousNotificationId', v_previous_notification_id,
    'deduplicationHash', v_deduplication_hash,
    'occurrenceCount', 1,
    'versionNo', v_version_no,
    'resetUserCount', 0
  );
end;
$$;

create or replace function notification.resolve_notification(
  p_organization_id uuid,
  p_notification_id uuid,
  p_resolution_code text,
  p_resolution_snapshot jsonb,
  p_resolved_at timestamptz,
  p_correlation_id uuid,
  p_note text default null,
  p_actor_user_id uuid default null,
  p_process_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app
as $$
declare
  v_notification notification.notifications%rowtype;
  v_process_name text :=
    nullif(btrim(coalesce(p_process_name, '')), '');
  v_version_no bigint;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ORGANIZATION_REQUIRED';
  end if;

  if p_notification_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ID_REQUIRED';
  end if;

  if btrim(coalesce(p_resolution_code, '')) = '' then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_RESOLUTION_CODE_REQUIRED';
  end if;

  if p_resolution_snapshot is null
     or jsonb_typeof(p_resolution_snapshot) <> 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_RESOLUTION_SNAPSHOT_INVALID';
  end if;

  if p_resolved_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_RESOLVED_AT_REQUIRED';
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

  select notification_row.*
  into v_notification
  from notification.notifications notification_row
  where notification_row.id = p_notification_id
    and notification_row.organization_id = p_organization_id
  for update;

  if v_notification.id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_NOT_FOUND';
  end if;

  if v_notification.lifecycle_status_code = 'RESOLVED' then
    if v_notification.resolution_code = btrim(p_resolution_code)
       and v_notification.resolution_snapshot = p_resolution_snapshot then
      return jsonb_build_object(
        'notificationId', v_notification.id,
        'action', 'ALREADY_RESOLVED',
        'versionNo', v_notification.version_no,
        'resolvedAt', v_notification.resolved_at
      );
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ALREADY_RESOLVED';
  end if;

  if p_resolved_at < v_notification.last_seen_at then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_RESOLVED_AT_STALE';
  end if;

  update notification.notifications
  set
    lifecycle_status_code = 'RESOLVED',
    resolved_at = p_resolved_at,
    resolution_code = btrim(p_resolution_code),
    resolution_snapshot = p_resolution_snapshot
  where id = v_notification.id
    and organization_id = p_organization_id
  returning version_no into v_version_no;

  perform notification.append_notification_event(
    p_organization_id => p_organization_id,
    p_notification_id => v_notification.id,
    p_event_type_code => 'RESOLVED',
    p_occurred_at => p_resolved_at,
    p_correlation_id => p_correlation_id,
    p_source_snapshot => p_resolution_snapshot,
    p_note => p_note,
    p_from_lifecycle_status_code =>
      v_notification.lifecycle_status_code,
    p_to_lifecycle_status_code => 'RESOLVED',
    p_from_stage_code => v_notification.stage_code,
    p_to_stage_code => v_notification.stage_code,
    p_from_severity_code => v_notification.severity_code,
    p_to_severity_code => v_notification.severity_code,
    p_actor_user_id => p_actor_user_id,
    p_process_name => v_process_name
  );

  return jsonb_build_object(
    'notificationId', v_notification.id,
    'action', 'RESOLVED',
    'versionNo', v_version_no,
    'resolvedAt', p_resolved_at
  );
end;
$$;

revoke all
on function notification.append_notification_event(
  uuid,
  uuid,
  text,
  timestamptz,
  uuid,
  jsonb,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text
)
from public, anon, authenticated;

revoke all
on function notification.reset_user_read_states(
  uuid,
  uuid,
  uuid,
  text
)
from public, anon, authenticated;

revoke all
on function notification.upsert_active_notification(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  jsonb,
  text,
  uuid,
  uuid,
  text
)
from public, anon, authenticated;

revoke all
on function notification.resolve_notification(
  uuid,
  uuid,
  text,
  jsonb,
  timestamptz,
  uuid,
  text,
  uuid,
  text
)
from public, anon, authenticated;

grant execute
on function notification.append_notification_event(
  uuid,
  uuid,
  text,
  timestamptz,
  uuid,
  jsonb,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text
)
to service_role;

grant execute
on function notification.reset_user_read_states(
  uuid,
  uuid,
  uuid,
  text
)
to service_role;

grant execute
on function notification.upsert_active_notification(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  jsonb,
  text,
  uuid,
  uuid,
  text
)
to service_role;

grant execute
on function notification.resolve_notification(
  uuid,
  uuid,
  text,
  jsonb,
  timestamptz,
  uuid,
  text,
  uuid,
  text
)
to service_role;

commit;
