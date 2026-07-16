begin;

create or replace function notification.acknowledge_notification(
  p_organization_id uuid,
  p_notification_id uuid,
  p_acknowledged_at timestamptz,
  p_correlation_id uuid,
  p_actor_user_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app
as $$
declare
  v_notification notification.notifications%rowtype;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
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

  if p_acknowledged_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACKNOWLEDGED_AT_REQUIRED';
  end if;

  if p_correlation_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_CORRELATION_ID_REQUIRED';
  end if;

  if p_actor_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_REQUIRED';
  end if;

  if v_note is not null and length(v_note) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACKNOWLEDGMENT_NOTE_TOO_LONG';
  end if;

  if not exists (
    select 1
    from app.user_profiles profile
    join app.organizations organization
      on organization.id = profile.organization_id
    where profile.user_id = p_actor_user_id
      and profile.organization_id = p_organization_id
      and profile.role_code = 'ADMIN'
      and profile.is_active
      and organization.is_active
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
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ALREADY_RESOLVED';
  end if;

  if v_notification.lifecycle_status_code = 'ACKNOWLEDGED' then
    return jsonb_build_object(
      'notificationId', v_notification.id,
      'action', 'ALREADY_ACKNOWLEDGED',
      'lifecycleStatusCode', v_notification.lifecycle_status_code,
      'acknowledgedAt', v_notification.acknowledged_at,
      'acknowledgedBy', v_notification.acknowledged_by,
      'versionNo', v_notification.version_no
    );
  end if;

  if p_acknowledged_at < v_notification.first_seen_at then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACKNOWLEDGED_AT_STALE';
  end if;

  update notification.notifications
  set
    lifecycle_status_code = 'ACKNOWLEDGED',
    acknowledged_at = p_acknowledged_at,
    acknowledged_by = p_actor_user_id,
    acknowledgment_note = v_note
  where id = v_notification.id
    and organization_id = p_organization_id
  returning version_no into v_version_no;

  perform notification.append_notification_event(
    p_organization_id => p_organization_id,
    p_notification_id => v_notification.id,
    p_event_type_code => 'ACKNOWLEDGED',
    p_occurred_at => p_acknowledged_at,
    p_correlation_id => p_correlation_id,
    p_source_snapshot => v_notification.source_snapshot,
    p_note => v_note,
    p_from_lifecycle_status_code => 'OPEN',
    p_to_lifecycle_status_code => 'ACKNOWLEDGED',
    p_from_stage_code => v_notification.stage_code,
    p_to_stage_code => v_notification.stage_code,
    p_from_severity_code => v_notification.severity_code,
    p_to_severity_code => v_notification.severity_code,
    p_actor_user_id => p_actor_user_id
  );

  return jsonb_build_object(
    'notificationId', v_notification.id,
    'action', 'ACKNOWLEDGED',
    'lifecycleStatusCode', 'ACKNOWLEDGED',
    'acknowledgedAt', p_acknowledged_at,
    'acknowledgedBy', p_actor_user_id,
    'versionNo', v_version_no
  );
end;
$$;

create or replace function notification.revoke_notification_acknowledgment(
  p_organization_id uuid,
  p_notification_id uuid,
  p_revoked_at timestamptz,
  p_correlation_id uuid,
  p_actor_user_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app
as $$
declare
  v_notification notification.notifications%rowtype;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
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

  if p_revoked_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_REVOCATION_TIME_REQUIRED';
  end if;

  if p_correlation_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_CORRELATION_ID_REQUIRED';
  end if;

  if p_actor_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACTOR_REQUIRED';
  end if;

  if v_note is not null and length(v_note) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ACKNOWLEDGMENT_NOTE_TOO_LONG';
  end if;

  if not exists (
    select 1
    from app.user_profiles profile
    join app.organizations organization
      on organization.id = profile.organization_id
    where profile.user_id = p_actor_user_id
      and profile.organization_id = p_organization_id
      and profile.role_code = 'ADMIN'
      and profile.is_active
      and organization.is_active
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
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_ALREADY_RESOLVED';
  end if;

  if v_notification.lifecycle_status_code = 'OPEN' then
    return jsonb_build_object(
      'notificationId', v_notification.id,
      'action', 'ALREADY_OPEN',
      'lifecycleStatusCode', v_notification.lifecycle_status_code,
      'versionNo', v_notification.version_no
    );
  end if;

  if p_revoked_at < v_notification.acknowledged_at then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_REVOCATION_TIME_STALE';
  end if;

  update notification.notifications
  set
    lifecycle_status_code = 'OPEN',
    acknowledged_at = null,
    acknowledged_by = null,
    acknowledgment_note = null
  where id = v_notification.id
    and organization_id = p_organization_id
  returning version_no into v_version_no;

  perform notification.append_notification_event(
    p_organization_id => p_organization_id,
    p_notification_id => v_notification.id,
    p_event_type_code => 'ACKNOWLEDGMENT_REVOKED',
    p_occurred_at => p_revoked_at,
    p_correlation_id => p_correlation_id,
    p_source_snapshot => v_notification.source_snapshot,
    p_note => v_note,
    p_from_lifecycle_status_code => 'ACKNOWLEDGED',
    p_to_lifecycle_status_code => 'OPEN',
    p_from_stage_code => v_notification.stage_code,
    p_to_stage_code => v_notification.stage_code,
    p_from_severity_code => v_notification.severity_code,
    p_to_severity_code => v_notification.severity_code,
    p_actor_user_id => p_actor_user_id
  );

  return jsonb_build_object(
    'notificationId', v_notification.id,
    'action', 'ACKNOWLEDGMENT_REVOKED',
    'lifecycleStatusCode', 'OPEN',
    'versionNo', v_version_no
  );
end;
$$;

create or replace function notification.set_notification_read_state(
  p_organization_id uuid,
  p_notification_id uuid,
  p_user_id uuid,
  p_read_state_code text,
  p_changed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, notification, app
as $$
declare
  v_notification notification.notifications%rowtype;
  v_existing notification.user_states%rowtype;
  v_read_state_code text :=
    upper(btrim(coalesce(p_read_state_code, '')));
  v_public_state_code text;
  v_read_at timestamptz;
  v_archived_at timestamptz;
  v_last_seen_version_no bigint;
  v_action text;
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

  if p_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_USER_REQUIRED';
  end if;

  if p_changed_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_STATE_CHANGED_AT_REQUIRED';
  end if;

  if v_read_state_code = 'ARCHIVED_FOR_USER' then
    v_read_state_code := 'ARCHIVED';
  end if;

  if v_read_state_code not in ('UNREAD', 'READ', 'ARCHIVED') then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_READ_STATE_INVALID';
  end if;

  if not exists (
    select 1
    from app.user_profiles profile
    join app.organizations organization
      on organization.id = profile.organization_id
    where profile.user_id = p_user_id
      and profile.organization_id = p_organization_id
      and profile.role_code = 'ADMIN'
      and profile.is_active
      and organization.is_active
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
  for share;

  if v_notification.id is null then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_NOT_FOUND';
  end if;

  if p_changed_at < v_notification.first_seen_at then
    raise exception using
      errcode = 'P0001',
      message = 'NOTIFICATION_STATE_CHANGED_AT_STALE';
  end if;

  select state.*
  into v_existing
  from notification.user_states state
  where state.notification_id = p_notification_id
    and state.user_id = p_user_id
    and state.organization_id = p_organization_id
  for update;

  if v_read_state_code = 'UNREAD' then
    v_public_state_code := 'UNREAD';
    v_read_at := null;
    v_archived_at := null;
    v_last_seen_version_no := null;
    v_action := 'SET_UNREAD';

    if v_existing.id is not null
       and v_existing.read_state_code = 'UNREAD'
       and v_existing.read_at is null
       and v_existing.archived_at is null
       and v_existing.last_seen_version_no is null then
      return jsonb_build_object(
        'notificationId', p_notification_id,
        'userId', p_user_id,
        'action', 'ALREADY_UNREAD',
        'readStateCode', v_public_state_code,
        'notificationVersionNo', v_notification.version_no
      );
    end if;
  elsif v_read_state_code = 'READ' then
    v_public_state_code := 'READ';
    v_read_at := p_changed_at;
    v_archived_at := null;
    v_last_seen_version_no := v_notification.version_no;
    v_action := 'SET_READ';

    if v_existing.id is not null
       and v_existing.read_state_code = 'READ'
       and v_existing.archived_at is null
       and v_existing.last_seen_version_no = v_notification.version_no then
      return jsonb_build_object(
        'notificationId', p_notification_id,
        'userId', p_user_id,
        'action', 'ALREADY_READ',
        'readStateCode', v_public_state_code,
        'notificationVersionNo', v_notification.version_no
      );
    end if;
  else
    v_public_state_code := 'ARCHIVED_FOR_USER';
    v_read_at := coalesce(v_existing.read_at, p_changed_at);
    v_archived_at := coalesce(v_existing.archived_at, p_changed_at);
    v_last_seen_version_no := v_notification.version_no;
    v_action := 'SET_ARCHIVED';

    if v_existing.id is not null
       and v_existing.read_state_code = 'ARCHIVED'
       and v_existing.last_seen_version_no = v_notification.version_no then
      return jsonb_build_object(
        'notificationId', p_notification_id,
        'userId', p_user_id,
        'action', 'ALREADY_ARCHIVED',
        'readStateCode', v_public_state_code,
        'notificationVersionNo', v_notification.version_no
      );
    end if;
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
  values (
    p_organization_id,
    p_notification_id,
    p_user_id,
    v_read_state_code,
    v_read_at,
    v_archived_at,
    v_last_seen_version_no,
    p_changed_at,
    p_changed_at
  )
  on conflict (notification_id, user_id) do update
  set
    organization_id = excluded.organization_id,
    read_state_code = excluded.read_state_code,
    read_at = excluded.read_at,
    archived_at = excluded.archived_at,
    last_seen_version_no = excluded.last_seen_version_no;

  return jsonb_build_object(
    'notificationId', p_notification_id,
    'userId', p_user_id,
    'action', v_action,
    'readStateCode', v_public_state_code,
    'notificationVersionNo', v_notification.version_no
  );
end;
$$;

create or replace function api.acknowledge_notification(
  p_notification_id uuid,
  p_note text default null,
  p_correlation_id uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, notification
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_organization_id uuid;
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

  return notification.acknowledge_notification(
    p_organization_id => v_organization_id,
    p_notification_id => p_notification_id,
    p_acknowledged_at => clock_timestamp(),
    p_correlation_id => p_correlation_id,
    p_actor_user_id => v_actor_user_id,
    p_note => p_note
  );
end;
$$;

create or replace function api.revoke_notification_acknowledgment(
  p_notification_id uuid,
  p_note text default null,
  p_correlation_id uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, notification
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_organization_id uuid;
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

  return notification.revoke_notification_acknowledgment(
    p_organization_id => v_organization_id,
    p_notification_id => p_notification_id,
    p_revoked_at => clock_timestamp(),
    p_correlation_id => p_correlation_id,
    p_actor_user_id => v_actor_user_id,
    p_note => p_note
  );
end;
$$;

create or replace function api.set_notification_read_state(
  p_notification_id uuid,
  p_read_state_code text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, notification
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_organization_id uuid;
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

  return notification.set_notification_read_state(
    p_organization_id => v_organization_id,
    p_notification_id => p_notification_id,
    p_user_id => v_actor_user_id,
    p_read_state_code => p_read_state_code,
    p_changed_at => clock_timestamp()
  );
end;
$$;

revoke all
on function notification.acknowledge_notification(
  uuid,
  uuid,
  timestamptz,
  uuid,
  uuid,
  text
)
from public, anon, authenticated;

revoke all
on function notification.revoke_notification_acknowledgment(
  uuid,
  uuid,
  timestamptz,
  uuid,
  uuid,
  text
)
from public, anon, authenticated;

revoke all
on function notification.set_notification_read_state(
  uuid,
  uuid,
  uuid,
  text,
  timestamptz
)
from public, anon, authenticated;

grant execute
on function notification.acknowledge_notification(
  uuid,
  uuid,
  timestamptz,
  uuid,
  uuid,
  text
)
to service_role;

grant execute
on function notification.revoke_notification_acknowledgment(
  uuid,
  uuid,
  timestamptz,
  uuid,
  uuid,
  text
)
to service_role;

grant execute
on function notification.set_notification_read_state(
  uuid,
  uuid,
  uuid,
  text,
  timestamptz
)
to service_role;

revoke all
on function api.acknowledge_notification(uuid, text, uuid)
from public, anon, authenticated;

revoke all
on function api.revoke_notification_acknowledgment(uuid, text, uuid)
from public, anon, authenticated;

revoke all
on function api.set_notification_read_state(uuid, text)
from public, anon, authenticated;

grant execute
on function api.acknowledge_notification(uuid, text, uuid)
to authenticated;

grant execute
on function api.revoke_notification_acknowledgment(uuid, text, uuid)
to authenticated;

grant execute
on function api.set_notification_read_state(uuid, text)
to authenticated;

commit;
