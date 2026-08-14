begin;

-- Production reference bootstrap only. This migration intentionally creates no
-- products, batches, balances, orders, reservations, or ledger history.

insert into app.organizations (id, code, name, timezone, is_active)
values (
  gen_random_uuid(),
  'STOK_RECONCILIATION_PRODUCTION',
  'Sistem Rekonsiliasi Stok',
  'Asia/Jakarta',
  true
)
on conflict (code) do nothing;

insert into catalog.channels (id, code, name, is_marketplace, is_active)
values
  ('10000000-0000-4000-8000-000000000001'::uuid, 'MANUAL', 'Manual', false, true),
  ('10000000-0000-4000-8000-000000000002'::uuid, 'SHOPEE', 'Shopee', true, true),
  ('10000000-0000-4000-8000-000000000003'::uuid, 'TIKTOK_SHOP', 'TikTok Shop', true, true),
  ('10000000-0000-4000-8000-000000000004'::uuid, 'IMPORT', 'Import', false, true),
  ('10000000-0000-4000-8000-000000000005'::uuid, 'SIMULATOR', 'Simulator', false, true),
  ('10000000-0000-4000-8000-000000000006'::uuid, 'SYSTEM', 'Sistem', false, true)
on conflict (code) do nothing;

insert into catalog.movement_reasons (id, code, name, direction_code, requires_note, is_system, is_active)
values
  ('20000000-0000-4000-8000-000000000001'::uuid, 'INITIAL_BALANCE', 'Saldo awal', 'ADJUSTMENT', false, true, true),
  ('20000000-0000-4000-8000-000000000002'::uuid, 'MAKLON_RECEIPT', 'Penerimaan maklon', 'INBOUND', false, false, true),
  ('20000000-0000-4000-8000-000000000003'::uuid, 'MARKETPLACE_SALE', 'Penjualan marketplace', 'OUTBOUND', false, true, true),
  ('20000000-0000-4000-8000-000000000004'::uuid, 'OFFLINE_SALE', 'Penjualan offline', 'OUTBOUND', false, false, true),
  ('20000000-0000-4000-8000-000000000005'::uuid, 'BONUS', 'Bonus', 'OUTBOUND', true, false, true),
  ('20000000-0000-4000-8000-000000000006'::uuid, 'PROMO', 'Promosi', 'OUTBOUND', true, false, true),
  ('20000000-0000-4000-8000-000000000007'::uuid, 'SAMPLE', 'Sampel', 'OUTBOUND', true, false, true),
  ('20000000-0000-4000-8000-000000000008'::uuid, 'RETURN_RECEIVED', 'Retur diterima', 'INBOUND', false, true, true),
  ('20000000-0000-4000-8000-000000000009'::uuid, 'RETURN_SELLABLE', 'Retur layak jual', 'INBOUND', false, true, true),
  ('20000000-0000-4000-8000-000000000010'::uuid, 'RETURN_DAMAGED', 'Retur rusak', 'TRANSFER', false, true, true),
  ('20000000-0000-4000-8000-000000000011'::uuid, 'DAMAGED_FOUND', 'Kerusakan ditemukan', 'TRANSFER', true, false, true),
  ('20000000-0000-4000-8000-000000000012'::uuid, 'EXPIRED_DISPOSAL', 'Pemusnahan kedaluwarsa', 'OUTBOUND', true, true, true),
  ('20000000-0000-4000-8000-000000000013'::uuid, 'DAMAGED_DISPOSAL', 'Pemusnahan rusak', 'OUTBOUND', true, true, true),
  ('20000000-0000-4000-8000-000000000014'::uuid, 'STOCKTAKE_GAIN', 'Selisih opname bertambah', 'ADJUSTMENT', true, false, true),
  ('20000000-0000-4000-8000-000000000015'::uuid, 'STOCKTAKE_LOSS', 'Selisih opname berkurang', 'ADJUSTMENT', true, false, true),
  ('20000000-0000-4000-8000-000000000016'::uuid, 'REVERSAL', 'Koreksi entri', 'ADJUSTMENT', true, true, true),
  ('20000000-0000-4000-8000-000000000017'::uuid, 'RETURN_INSPECTION', 'Pemeriksaan retur', 'TRANSFER', false, true, true),
  ('20000000-0000-4000-8000-000000000018'::uuid, 'STOCKTAKE_ADJUSTMENT', 'Penyesuaian opname', 'ADJUSTMENT', true, true, true)
on conflict (code) do nothing;

insert into app.settings (organization_id, key, value, version)
select organization.id, setting.key, setting.value, 1
from app.organizations organization
cross join (
  values
    ('expiry.warning_days'::text, '[90,60,30,0]'::jsonb),
    ('expiry.safety_buffer_days'::text, '0'::jsonb),
    ('return.inspection_sla_hours'::text, '[24,72]'::jsonb)
) as setting(key, value)
where organization.code = 'STOK_RECONCILIATION_PRODUCTION'
  and not exists (
    select 1
    from app.settings existing
    where existing.organization_id = organization.id
      and existing.key = setting.key
      and existing.effective_to is null
  );

create or replace function api.bootstrap_admin(
  p_user_id uuid,
  p_email text,
  p_display_name text default 'Admin'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, app, auth
as $$
declare
  v_organization_id uuid;
  v_normalized_email text := lower(btrim(coalesce(p_email, '')));
  v_display_name text := btrim(coalesce(p_display_name, ''));
  v_employee_code text;
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

  select organization.id
  into v_organization_id
  from app.organizations organization
  where organization.code = 'STOK_RECONCILIATION_PRODUCTION'
    and organization.is_active;

  if v_organization_id is null then
    raise exception using errcode = 'P0001', message = 'PRODUCTION_ORGANIZATION_NOT_FOUND';
  end if;

  v_employee_code := 'ADMIN-' || substr(replace(p_user_id::text, '-', ''), 1, 12);

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
    v_employee_code,
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
    'email', v_normalized_email,
    'organizationCode', 'STOK_RECONCILIATION_PRODUCTION',
    'roleCode', 'ADMIN',
    'status', 'READY'
  );
end;
$$;

revoke all on function api.bootstrap_admin(uuid, text, text) from public, anon, authenticated;
grant execute on function api.bootstrap_admin(uuid, text, text) to service_role;

commit;