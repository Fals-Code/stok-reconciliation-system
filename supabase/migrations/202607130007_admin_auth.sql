begin;

create or replace view api.current_admin_profile
with (security_invoker = true)
as
select
  profile.user_id,
  profile.organization_id,
  profile.display_name,
  profile.employee_code,
  profile.role_code,
  organization.code as organization_code,
  organization.name as organization_name,
  organization.timezone
from app.user_profiles profile
join app.organizations organization
  on organization.id = profile.organization_id
where profile.user_id = auth.uid()
  and profile.is_active
  and profile.role_code = 'ADMIN'
  and organization.is_active;

revoke all on api.current_admin_profile from public, anon;
grant select on api.current_admin_profile to authenticated;

create or replace function api.bootstrap_demo_admin(
  p_user_id uuid,
  p_email text,
  p_display_name text default 'Demo Admin'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, app, auth
as $$
declare
  v_organization_id constant uuid := '00000000-0000-4000-8000-000000000001'::uuid;
  v_normalized_email text := lower(btrim(coalesce(p_email, '')));
  v_display_name text := btrim(coalesce(p_display_name, ''));
begin
  if p_user_id is null then
    raise exception using errcode = 'P0001', message = 'ADMIN_USER_ID_REQUIRED';
  end if;

  if v_normalized_email = '' then
    raise exception using errcode = 'P0001', message = 'ADMIN_EMAIL_REQUIRED';
  end if;

  if v_display_name = '' then
    raise exception using errcode = 'P0001', message = 'ADMIN_DISPLAY_NAME_REQUIRED';
  end if;

  if not exists (
    select 1
    from auth.users auth_user
    where auth_user.id = p_user_id
      and lower(coalesce(auth_user.email, '')) = v_normalized_email
  ) then
    raise exception using errcode = 'P0001', message = 'AUTH_USER_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from app.organizations organization
    where organization.id = v_organization_id
      and organization.is_active
  ) then
    raise exception using errcode = 'P0001', message = 'DEMO_ORGANIZATION_NOT_FOUND';
  end if;

  insert into app.user_profiles (
    user_id,
    organization_id,
    display_name,
    employee_code,
    role_code,
    is_active
  )
  values (
    p_user_id,
    v_organization_id,
    v_display_name,
    'DEMO-ADMIN',
    'ADMIN',
    true
  )
  on conflict (user_id) do update
  set
    organization_id = excluded.organization_id,
    display_name = excluded.display_name,
    employee_code = excluded.employee_code,
    role_code = 'ADMIN',
    is_active = true;

  return jsonb_build_object(
    'userId', p_user_id,
    'email', v_normalized_email,
    'organizationId', v_organization_id,
    'roleCode', 'ADMIN',
    'status', 'READY'
  );
end;
$$;

revoke all on function api.bootstrap_demo_admin(uuid, text, text) from public, anon, authenticated;
grant execute on function api.bootstrap_demo_admin(uuid, text, text) to service_role;

commit;
