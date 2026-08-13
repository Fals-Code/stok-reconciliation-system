begin;

-- 1. Drop constraints di catalog.master_data_audit_events agar bisa di-extend secara forward
alter table catalog.master_data_audit_events drop constraint if exists ck_master_data_audit_entity_type;
alter table catalog.master_data_audit_events drop constraint if exists ck_master_data_audit_action;
alter table catalog.master_data_audit_events drop constraint if exists ck_master_data_audit_entity_action;
alter table catalog.master_data_audit_events drop constraint if exists ck_master_data_audit_snapshot_shape;

alter table catalog.master_data_audit_events add constraint ck_master_data_audit_entity_type
  check (entity_type_code in ('PRODUCT', 'BATCH', 'PROMO_REFERENCE'));

alter table catalog.master_data_audit_events add constraint ck_master_data_audit_action
  check (
    action_code in (
      'PRODUCT_CREATE',
      'PRODUCT_UPDATE',
      'PRODUCT_ARCHIVE',
      'PRODUCT_REACTIVATE',
      'BATCH_CREATE',
      'BATCH_UPDATE',
      'BATCH_BLOCK',
      'BATCH_UNBLOCK',
      'BATCH_ARCHIVE',
      'BATCH_REACTIVATE',
      'PROMO_REFERENCE_CREATE',
      'PROMO_REFERENCE_UPDATE',
      'PROMO_REFERENCE_DEACTIVATE',
      'PROMO_REFERENCE_REACTIVATE'
    )
  );

alter table catalog.master_data_audit_events add constraint ck_master_data_audit_entity_action
  check (
    (entity_type_code = 'PRODUCT' and action_code like 'PRODUCT_%')
    or
    (entity_type_code = 'BATCH' and action_code like 'BATCH_%')
    or
    (entity_type_code = 'PROMO_REFERENCE' and action_code like 'PROMO_REFERENCE_%')
  );

alter table catalog.master_data_audit_events add constraint ck_master_data_audit_snapshot_shape
  check (
    (
      action_code in ('PRODUCT_CREATE', 'BATCH_CREATE', 'PROMO_REFERENCE_CREATE')
      and before_snapshot is null
      and after_snapshot is not null
    )
    or
    (
      action_code not in ('PRODUCT_CREATE', 'BATCH_CREATE', 'PROMO_REFERENCE_CREATE')
      and before_snapshot is not null
      and after_snapshot is not null
    )
  );

-- 2. Membuat tabel catalog.promo_references
create table catalog.promo_references (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  code text not null,
  name text not null,
  description text null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid null references auth.users(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid null references auth.users(id) on delete restrict,
  row_version bigint not null default 1,
  constraint ck_promo_ref_code_nonblank check (btrim(code) <> ''),
  constraint ck_promo_ref_name_nonblank check (btrim(name) <> '')
);

-- Unique index case-insensitive normalized code per organization
create unique index uidx_promo_references_org_normalized_code
on catalog.promo_references (
  organization_id,
  catalog.normalize_master_identifier(code)
);

-- RLS
alter table catalog.promo_references enable row level security;

create policy promo_references_read_current_org
on catalog.promo_references
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

-- Revoke and Grant
revoke all on catalog.promo_references from anon, authenticated;
grant select on catalog.promo_references to authenticated, service_role;

-- 2b. Menolak physical delete pada catalog.promo_references
create or replace function catalog.reject_promo_reference_delete()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = 'PROMO_REFERENCE_DELETE_FORBIDDEN';
end;
$$;

revoke all on function catalog.reject_promo_reference_delete()
from public, anon, authenticated, service_role;

create trigger trg_promo_references_reject_delete
before delete on catalog.promo_references
for each row execute function catalog.reject_promo_reference_delete();


-- 3. Helper snapshot
create or replace function catalog.promo_reference_snapshot(
  p_row catalog.promo_references
)
returns jsonb
language sql
stable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'id', p_row.id,
    'organizationId', p_row.organization_id,
    'code', p_row.code,
    'name', p_row.name,
    'description', p_row.description,
    'isActive', p_row.is_active,
    'createdAt', p_row.created_at,
    'createdBy', p_row.created_by,
    'updatedAt', p_row.updated_at,
    'updatedBy', p_row.updated_by,
    'rowVersion', p_row.row_version
  )
$$;

revoke all on function catalog.promo_reference_snapshot(catalog.promo_references) from public, anon;
grant execute on function catalog.promo_reference_snapshot(catalog.promo_references) to authenticated, service_role;

-- 4. RPC Create Promo Reference
create or replace function api.create_promo_reference(
  p_organization_id uuid,
  p_idempotency_key text,
  p_code text,
  p_name text,
  p_description text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, extensions
as $$
declare
  v_scope constant text := 'CREATE_PROMO_REFERENCE';
  v_code text := catalog.normalize_master_identifier(coalesce(p_code, ''));
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_request_hash text;
  v_caller record;
  v_command record;
  v_promo catalog.promo_references%rowtype;
  v_promo_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_audit_id uuid;
  v_response jsonb;
begin
  select *
  into v_caller
  from catalog.assert_master_data_caller(
    p_organization_id,
    'api.create_promo_reference'
  );

  if v_code = '' or v_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'PROMO_REFERENCE_REQUIRED_FIELDS_MISSING';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'code', v_code,
          'name', v_name,
          'description', v_description,
          'note', v_note,
          'schemaVersion', 1
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select *
  into v_command
  from catalog.start_master_data_command(
    p_organization_id,
    v_scope,
    p_idempotency_key,
    v_request_hash
  );

  if v_command.is_replay then
    return v_command.response_snapshot;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':PROMO_CODE:' || v_code,
      0::bigint
    )
  );

  if exists (
    select 1
    from catalog.promo_references promo
    where promo.organization_id = p_organization_id
      and catalog.normalize_master_identifier(promo.code) = v_code
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'DUPLICATE_PROMO_CODE';
  end if;

  begin
    insert into catalog.promo_references (
      id,
      organization_id,
      code,
      name,
      description,
      is_active,
      created_at,
      created_by,
      updated_at,
      updated_by,
      row_version
    ) values (
      v_promo_id,
      p_organization_id,
      v_code,
      v_name,
      v_description,
      true,
      v_recorded_at,
      v_caller.actor_user_id,
      v_recorded_at,
      v_caller.actor_user_id,
      1
    )
    returning * into v_promo;
  exception
    when unique_violation then
      raise exception using
        errcode = 'P0001',
        message = 'DUPLICATE_PROMO_CODE';
  end;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'PROMO_REFERENCE',
    v_promo.id,
    'PROMO_REFERENCE_CREATE',
    v_command.command_id,
    null,
    catalog.promo_reference_snapshot(v_promo),
    null,
    v_note,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', 'CREATED',
    'promoId', v_promo.id,
    'code', v_promo.code,
    'name', v_promo.name,
    'description', v_promo.description,
    'isActive', v_promo.is_active,
    'rowVersion', v_promo.row_version,
    'auditId', v_audit_id,
    'idempotencyKey', btrim(p_idempotency_key),
    'stockEffect', 'NONE',
    'recordedAt', v_recorded_at
  );

  perform catalog.complete_master_data_command(
    v_command.command_id,
    v_response
  );

  return v_response;
end;
$$;

revoke all on function api.create_promo_reference(uuid, text, text, text, text, text) from public, anon;
grant execute on function api.create_promo_reference(uuid, text, text, text, text, text) to authenticated, service_role;

-- 5. RPC Update Promo Reference
create or replace function api.update_promo_reference(
  p_organization_id uuid,
  p_idempotency_key text,
  p_promo_id uuid,
  p_expected_row_version bigint,
  p_name text,
  p_description text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, extensions
as $$
declare
  v_scope constant text := 'UPDATE_PROMO_REFERENCE';
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_request_hash text;
  v_caller record;
  v_command record;
  v_before catalog.promo_references%rowtype;
  v_after catalog.promo_references%rowtype;
  v_recorded_at timestamptz := clock_timestamp();
  v_audit_id uuid;
  v_response jsonb;
begin
  select *
  into v_caller
  from catalog.assert_master_data_caller(
    p_organization_id,
    'api.update_promo_reference'
  );

  if p_promo_id is null or p_expected_row_version is null or v_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'PROMO_REFERENCE_REQUIRED_FIELDS_MISSING';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'promoId', p_promo_id,
          'expectedRowVersion', p_expected_row_version,
          'name', v_name,
          'description', v_description,
          'note', v_note,
          'schemaVersion', 1
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select *
  into v_command
  from catalog.start_master_data_command(
    p_organization_id,
    v_scope,
    p_idempotency_key,
    v_request_hash
  );

  if v_command.is_replay then
    return v_command.response_snapshot;
  end if;

  select promo.*
  into v_before
  from catalog.promo_references promo
  where promo.organization_id = p_organization_id
    and promo.id = p_promo_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'PROMO_REFERENCE_NOT_FOUND';
  end if;

  if v_before.row_version <> p_expected_row_version then
    raise exception using
      errcode = 'P0001',
      message = 'CONCURRENCY_ERROR';
  end if;

  update catalog.promo_references promo
  set
    name = v_name,
    description = v_description,
    updated_at = v_recorded_at,
    updated_by = v_caller.actor_user_id,
    row_version = v_before.row_version + 1
  where promo.id = p_promo_id
  returning * into v_after;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'PROMO_REFERENCE',
    v_after.id,
    'PROMO_REFERENCE_UPDATE',
    v_command.command_id,
    catalog.promo_reference_snapshot(v_before),
    catalog.promo_reference_snapshot(v_after),
    null,
    v_note,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', 'UPDATED',
    'promoId', v_after.id,
    'code', v_after.code,
    'name', v_after.name,
    'description', v_after.description,
    'isActive', v_after.is_active,
    'rowVersion', v_after.row_version,
    'auditId', v_audit_id,
    'idempotencyKey', btrim(p_idempotency_key),
    'stockEffect', 'NONE',
    'recordedAt', v_recorded_at
  );

  perform catalog.complete_master_data_command(
    v_command.command_id,
    v_response
  );

  return v_response;
end;
$$;

revoke all on function api.update_promo_reference(uuid, text, uuid, bigint, text, text, text) from public, anon;
grant execute on function api.update_promo_reference(uuid, text, uuid, bigint, text, text, text) to authenticated, service_role;

-- 6. Helper change state active
create or replace function catalog.change_promo_reference_active_state(
  p_organization_id uuid,
  p_idempotency_key text,
  p_promo_id uuid,
  p_expected_row_version bigint,
  p_target_active boolean,
  p_reason text,
  p_process_name text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, extensions
as $$
declare
  v_scope text := case
    when p_target_active then 'REACTIVATE_PROMO_REFERENCE'
    else 'ARCHIVE_PROMO_REFERENCE'
  end;
  v_action text := case
    when p_target_active then 'PROMO_REFERENCE_REACTIVATE'
    else 'PROMO_REFERENCE_DEACTIVATE'
  end;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_request_hash text;
  v_caller record;
  v_command record;
  v_before catalog.promo_references%rowtype;
  v_after catalog.promo_references%rowtype;
  v_recorded_at timestamptz := clock_timestamp();
  v_audit_id uuid;
  v_response jsonb;
begin
  select *
  into v_caller
  from catalog.assert_master_data_caller(
    p_organization_id,
    p_process_name
  );

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'promoId', p_promo_id,
          'expectedRowVersion', p_expected_row_version,
          'targetActive', p_target_active,
          'reason', v_reason,
          'schemaVersion', 1
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select *
  into v_command
  from catalog.start_master_data_command(
    p_organization_id,
    v_scope,
    p_idempotency_key,
    v_request_hash
  );

  if v_command.is_replay then
    return v_command.response_snapshot;
  end if;

  select promo.*
  into v_before
  from catalog.promo_references promo
  where promo.organization_id = p_organization_id
    and promo.id = p_promo_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'PROMO_REFERENCE_NOT_FOUND';
  end if;

  if v_before.row_version <> p_expected_row_version then
    raise exception using
      errcode = 'P0001',
      message = 'CONCURRENCY_ERROR';
  end if;

  if v_before.is_active = p_target_active then
    raise exception using
      errcode = 'P0001',
      message = case
        when p_target_active then 'PROMO_REFERENCE_ALREADY_ACTIVE'
        else 'PROMO_REFERENCE_ALREADY_INACTIVE'
      end;
  end if;

  update catalog.promo_references promo
  set
    is_active = p_target_active,
    updated_at = v_recorded_at,
    updated_by = v_caller.actor_user_id,
    row_version = v_before.row_version + 1
  where promo.id = p_promo_id
  returning * into v_after;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'PROMO_REFERENCE',
    v_after.id,
    v_action,
    v_command.command_id,
    catalog.promo_reference_snapshot(v_before),
    catalog.promo_reference_snapshot(v_after),
    v_reason,
    null,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', case when p_target_active then 'REACTIVATED' else 'ARCHIVED' end,
    'promoId', v_after.id,
    'code', v_after.code,
    'name', v_after.name,
    'description', v_after.description,
    'isActive', v_after.is_active,
    'rowVersion', v_after.row_version,
    'auditId', v_audit_id,
    'idempotencyKey', btrim(p_idempotency_key),
    'stockEffect', 'NONE',
    'recordedAt', v_recorded_at
  );

  perform catalog.complete_master_data_command(
    v_command.command_id,
    v_response
  );

  return v_response;
end;
$$;

revoke all on function catalog.change_promo_reference_active_state(uuid, text, uuid, bigint, boolean, text, text) from public, anon;
grant execute on function catalog.change_promo_reference_active_state(uuid, text, uuid, bigint, boolean, text, text) to authenticated, service_role;

-- 7. RPC Archive/Reactivate Promo Reference
create or replace function api.archive_promo_reference(
  p_organization_id uuid,
  p_idempotency_key text,
  p_promo_id uuid,
  p_expected_row_version bigint,
  p_reason text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalog
as $$
  select catalog.change_promo_reference_active_state(
    p_organization_id,
    p_idempotency_key,
    p_promo_id,
    p_expected_row_version,
    false,
    p_reason,
    'api.archive_promo_reference'
  )
$$;

revoke all on function api.archive_promo_reference(uuid, text, uuid, bigint, text) from public, anon;
grant execute on function api.archive_promo_reference(uuid, text, uuid, bigint, text) to authenticated, service_role;

create or replace function api.reactivate_promo_reference(
  p_organization_id uuid,
  p_idempotency_key text,
  p_promo_id uuid,
  p_expected_row_version bigint,
  p_reason text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalog
as $$
  select catalog.change_promo_reference_active_state(
    p_organization_id,
    p_idempotency_key,
    p_promo_id,
    p_expected_row_version,
    true,
    p_reason,
    'api.reactivate_promo_reference'
  )
$$;

revoke all on function api.reactivate_promo_reference(uuid, text, uuid, bigint, text) from public, anon;
grant execute on function api.reactivate_promo_reference(uuid, text, uuid, bigint, text) to authenticated, service_role;

-- 8. View api.promo_references
create or replace view api.promo_references
with (security_invoker = true)
as
select
  id,
  organization_id,
  code,
  name,
  description,
  is_active,
  created_at,
  created_by,
  updated_at,
  updated_by,
  row_version
from catalog.promo_references;

revoke all on api.promo_references from anon;
grant select on api.promo_references to authenticated, service_role;

commit;
