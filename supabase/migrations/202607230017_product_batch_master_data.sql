begin;

create or replace function catalog.normalize_master_identifier(
  p_value text
)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select upper(
    regexp_replace(
      btrim(p_value),
      '[[:space:]]+',
      ' ',
      'g'
    )
  )
$$;

revoke all on function catalog.normalize_master_identifier(text)
from public, anon;

grant execute on function catalog.normalize_master_identifier(text)
to authenticated, service_role;

create unique index uidx_products_org_normalized_sku
on catalog.products (
  organization_id,
  catalog.normalize_master_identifier(sku)
);

create unique index uidx_product_batches_org_product_normalized_code
on catalog.product_batches (
  organization_id,
  product_id,
  catalog.normalize_master_identifier(batch_code)
);

create table catalog.master_data_audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references app.organizations(id) on delete restrict,
  entity_type_code text not null,
  entity_id uuid not null,
  action_code text not null,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  before_snapshot jsonb null,
  after_snapshot jsonb null,
  reason text null,
  note text null,
  actor_user_id uuid null
    references auth.users(id) on delete restrict,
  process_name text null,
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default clock_timestamp(),
  schema_version integer not null default 1,
  constraint uq_master_data_audit_command
    unique (idempotency_command_id),
  constraint ck_master_data_audit_entity_type
    check (entity_type_code in ('PRODUCT', 'BATCH')),
  constraint ck_master_data_audit_action
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
        'BATCH_REACTIVATE'
      )
    ),
  constraint ck_master_data_audit_entity_action
    check (
      (entity_type_code = 'PRODUCT' and action_code like 'PRODUCT_%')
      or
      (entity_type_code = 'BATCH' and action_code like 'BATCH_%')
    ),
  constraint ck_master_data_audit_snapshot_shape
    check (
      (
        action_code in ('PRODUCT_CREATE', 'BATCH_CREATE')
        and before_snapshot is null
        and after_snapshot is not null
      )
      or
      (
        action_code not in ('PRODUCT_CREATE', 'BATCH_CREATE')
        and before_snapshot is not null
        and after_snapshot is not null
      )
    ),
  constraint ck_master_data_audit_snapshot_objects
    check (
      (before_snapshot is null or jsonb_typeof(before_snapshot) = 'object')
      and jsonb_typeof(after_snapshot) = 'object'
    ),
  constraint ck_master_data_audit_reason_nonblank
    check (reason is null or btrim(reason) <> ''),
  constraint ck_master_data_audit_note_nonblank
    check (note is null or btrim(note) <> ''),
  constraint ck_master_data_audit_actor_xor_process
    check ((actor_user_id is not null) <> (process_name is not null)),
  constraint ck_master_data_audit_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),
  constraint ck_master_data_audit_time_order
    check (recorded_at >= occurred_at),
  constraint ck_master_data_audit_schema_version
    check (schema_version > 0)
);

create index idx_master_data_audit_entity
on catalog.master_data_audit_events (
  organization_id,
  entity_type_code,
  entity_id,
  occurred_at desc,
  id desc
);

create index idx_master_data_audit_action
on catalog.master_data_audit_events (
  organization_id,
  action_code,
  occurred_at desc,
  id desc
);

create trigger trg_master_data_audit_immutable
before update or delete on catalog.master_data_audit_events
for each row execute function inventory.reject_immutable_mutation();

alter table catalog.master_data_audit_events enable row level security;

create policy master_data_audit_read_current_org
on catalog.master_data_audit_events
for select
to authenticated
using (
  organization_id = (
    select app.current_organization_id()
  )
);

revoke all on catalog.master_data_audit_events
from public, anon, authenticated, service_role;

grant select on catalog.master_data_audit_events
to authenticated, service_role;

create or replace function catalog.reject_master_data_delete()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_table_name = 'products' then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_DELETE_FORBIDDEN';
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'BATCH_DELETE_FORBIDDEN';
end;
$$;

revoke all on function catalog.reject_master_data_delete()
from public, anon, authenticated, service_role;

create trigger trg_products_reject_delete
before delete on catalog.products
for each row execute function catalog.reject_master_data_delete();

create trigger trg_product_batches_reject_delete
before delete on catalog.product_batches
for each row execute function catalog.reject_master_data_delete();

create or replace function catalog.protect_product_batch_identity()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.id is distinct from old.id
     or new.organization_id is distinct from old.organization_id then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_IDENTITY_CHANGE_FORBIDDEN';
  end if;

  if new.product_id is distinct from old.product_id then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_PRODUCT_CHANGE_FORBIDDEN';
  end if;

  if new.batch_kind_code is distinct from old.batch_kind_code then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_KIND_CHANGE_FORBIDDEN';
  end if;

  return new;
end;
$$;

revoke all on function catalog.protect_product_batch_identity()
from public, anon, authenticated, service_role;

create trigger trg_product_batches_protect_identity
before update on catalog.product_batches
for each row execute function catalog.protect_product_batch_identity();

create or replace function catalog.product_master_snapshot(
  p_product catalog.products
)
returns jsonb
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'productId', p_product.id,
    'organizationId', p_product.organization_id,
    'sku', p_product.sku,
    'name', p_product.name,
    'unitCode', p_product.unit_code,
    'description', p_product.description,
    'isActive', p_product.is_active,
    'isBatchTracked', p_product.is_batch_tracked,
    'isExpiryTracked', p_product.is_expiry_tracked,
    'rowVersion', p_product.row_version,
    'createdAt', p_product.created_at,
    'createdBy', p_product.created_by,
    'updatedAt', p_product.updated_at,
    'updatedBy', p_product.updated_by
  )
$$;

create or replace function catalog.product_batch_master_snapshot(
  p_batch catalog.product_batches
)
returns jsonb
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'batchId', p_batch.id,
    'organizationId', p_batch.organization_id,
    'productId', p_batch.product_id,
    'batchCode', p_batch.batch_code,
    'manufacturedDate', p_batch.manufactured_date,
    'expiryDate', p_batch.expiry_date,
    'receivedFirstAt', p_batch.received_first_at,
    'lifecycleStatusCode', p_batch.status_code,
    'blockReason', p_batch.block_reason,
    'batchKindCode', p_batch.batch_kind_code,
    'rowVersion', p_batch.row_version,
    'createdAt', p_batch.created_at,
    'createdBy', p_batch.created_by,
    'updatedAt', p_batch.updated_at,
    'updatedBy', p_batch.updated_by
  )
$$;

revoke all on function catalog.product_master_snapshot(catalog.products)
from public, anon, authenticated, service_role;

revoke all on function catalog.product_batch_master_snapshot(
  catalog.product_batches
) from public, anon, authenticated, service_role;

create or replace function catalog.product_has_authoritative_history(
  p_organization_id uuid,
  p_product_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, catalog, inventory, operations, reconciliation
as $$
  select
    exists (
      select 1
      from inventory.stock_ledger_entries entry
      where entry.organization_id = p_organization_id
        and entry.product_id = p_product_id
    )
    or exists (
      select 1
      from inventory.stock_reservations reservation
      where reservation.organization_id = p_organization_id
        and reservation.product_id = p_product_id
    )
    or exists (
      select 1
      from operations.receipt_lines line
      where line.organization_id = p_organization_id
        and line.product_id = p_product_id
    )
    or exists (
      select 1
      from operations.manual_outbound_lines line
      where line.organization_id = p_organization_id
        and line.product_id = p_product_id
    )
    or exists (
      select 1
      from operations.marketplace_order_items item
      where item.organization_id = p_organization_id
        and item.product_id = p_product_id
    )
    or exists (
      select 1
      from operations.marketplace_event_lines line
      where line.organization_id = p_organization_id
        and line.product_id = p_product_id
    )
    or exists (
      select 1
      from operations.marketplace_source_line_components component
      where component.organization_id = p_organization_id
        and component.product_id = p_product_id
    )
    or exists (
      select 1
      from operations.marketplace_cancellation_lines line
      where line.organization_id = p_organization_id
        and line.product_id = p_product_id
    )
    or exists (
      select 1
      from operations.return_items item
      where item.organization_id = p_organization_id
        and item.product_id = p_product_id
    )
    or exists (
      select 1
      from operations.stocktake_lines line
      where line.organization_id = p_organization_id
        and line.product_id = p_product_id
    )
    or exists (
      select 1
      from operations.opening_balance_cutover_lines line
      where line.organization_id = p_organization_id
        and line.product_id = p_product_id
    )
    or exists (
      select 1
      from operations.stock_disposal_lines line
      where line.organization_id = p_organization_id
        and line.product_id = p_product_id
    )
    or exists (
      select 1
      from catalog.marketplace_single_listing_versions version
      where version.organization_id = p_organization_id
        and version.product_id = p_product_id
    )
    or exists (
      select 1
      from catalog.bundle_components component
      join catalog.bundle_recipes recipe
        on recipe.id = component.bundle_recipe_id
      where recipe.organization_id = p_organization_id
        and component.product_id = p_product_id
    )
    or exists (
      select 1
      from reconciliation.issues issue
      where issue.organization_id = p_organization_id
        and issue.product_id = p_product_id
    )
$$;

create or replace function catalog.product_batch_has_authoritative_history(
  p_organization_id uuid,
  p_batch_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, inventory, operations, reconciliation
as $$
  select
    exists (
      select 1
      from inventory.stock_ledger_entries entry
      where entry.organization_id = p_organization_id
        and entry.batch_id = p_batch_id
    )
    or exists (
      select 1
      from operations.receipt_lines line
      where line.organization_id = p_organization_id
        and line.batch_id = p_batch_id
    )
    or exists (
      select 1
      from operations.manual_outbound_allocations allocation
      where allocation.organization_id = p_organization_id
        and allocation.batch_id = p_batch_id
    )
    or exists (
      select 1
      from operations.marketplace_ship_allocations allocation
      where allocation.organization_id = p_organization_id
        and allocation.batch_id = p_batch_id
    )
    or exists (
      select 1
      from operations.return_receipt_lines line
      where line.organization_id = p_organization_id
        and (
          line.batch_id = p_batch_id
          or line.source_batch_id = p_batch_id
        )
    )
    or exists (
      select 1
      from operations.return_stock_batches provenance
      where provenance.organization_id = p_organization_id
        and (
          provenance.batch_id = p_batch_id
          or provenance.source_batch_id = p_batch_id
        )
    )
    or exists (
      select 1
      from operations.return_inspection_allocations allocation
      where allocation.organization_id = p_organization_id
        and allocation.return_batch_id = p_batch_id
    )
    or exists (
      select 1
      from operations.stocktake_lines line
      where line.organization_id = p_organization_id
        and line.batch_id = p_batch_id
    )
    or exists (
      select 1
      from operations.stocktake_snapshots snapshot
      where snapshot.organization_id = p_organization_id
        and snapshot.batch_id = p_batch_id
    )
    or exists (
      select 1
      from operations.stocktake_posting_lines line
      where line.organization_id = p_organization_id
        and line.batch_id = p_batch_id
    )
    or exists (
      select 1
      from operations.opening_balance_cutover_lines line
      where line.organization_id = p_organization_id
        and line.batch_id = p_batch_id
    )
    or exists (
      select 1
      from operations.opening_balance_verification_applications application
      where application.organization_id = p_organization_id
        and application.batch_id = p_batch_id
    )
    or exists (
      select 1
      from operations.stock_disposal_lines line
      where line.organization_id = p_organization_id
        and line.batch_id = p_batch_id
    )
    or exists (
      select 1
      from reconciliation.issues issue
      where issue.organization_id = p_organization_id
        and issue.batch_id = p_batch_id
    )
$$;

revoke all on function catalog.product_has_authoritative_history(uuid, uuid)
from public, anon;

revoke all on function catalog.product_batch_has_authoritative_history(
  uuid,
  uuid
) from public, anon;

grant execute on function catalog.product_has_authoritative_history(uuid, uuid)
to authenticated, service_role;

grant execute on function catalog.product_batch_has_authoritative_history(
  uuid,
  uuid
) to authenticated, service_role;

create or replace function inventory.validate_stock_ledger_entry()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog, inventory
as $$
declare
  v_transaction_org_id uuid;
  v_transaction_type_code text;
  v_reversal_of_transaction_id uuid;
  v_transaction_occurred_at timestamptz;
  v_transaction_recorded_at timestamptz;
  v_product_sku text;
  v_batch_code text;
  v_expiry_date date;
  v_snapshot_matches_current boolean;
  v_snapshot_matches_reversed_entry boolean;
begin
  select
    transaction.organization_id,
    transaction.transaction_type_code,
    transaction.reversal_of_transaction_id,
    transaction.occurred_at,
    transaction.recorded_at
  into strict
    v_transaction_org_id,
    v_transaction_type_code,
    v_reversal_of_transaction_id,
    v_transaction_occurred_at,
    v_transaction_recorded_at
  from inventory.stock_transactions transaction
  where transaction.id = new.transaction_id;

  if new.organization_id <> v_transaction_org_id then
    raise exception using
      errcode = 'P0001',
      message = 'LEDGER_ORGANIZATION_MISMATCH';
  end if;

  select product.sku, batch.batch_code, batch.expiry_date
  into strict v_product_sku, v_batch_code, v_expiry_date
  from catalog.products product
  join catalog.product_batches batch
    on batch.organization_id = product.organization_id
   and batch.product_id = product.id
  where product.organization_id = new.organization_id
    and product.id = new.product_id
    and batch.id = new.batch_id;

  v_snapshot_matches_current :=
    new.product_sku_snapshot = v_product_sku
    and new.batch_code_snapshot = v_batch_code
    and new.expiry_date_snapshot = v_expiry_date;

  v_snapshot_matches_reversed_entry :=
    v_transaction_type_code = 'REVERSAL'
    and v_reversal_of_transaction_id is not null
    and exists (
      select 1
      from inventory.stock_ledger_entries original
      where original.transaction_id = v_reversal_of_transaction_id
        and original.organization_id = new.organization_id
        and original.product_id = new.product_id
        and original.batch_id = new.batch_id
        and original.product_sku_snapshot = new.product_sku_snapshot
        and original.batch_code_snapshot = new.batch_code_snapshot
        and original.expiry_date_snapshot = new.expiry_date_snapshot
        and original.bucket_code = new.bucket_code
    );

  if not v_snapshot_matches_current
     and not v_snapshot_matches_reversed_entry then
    raise exception using
      errcode = 'P0001',
      message = 'LEDGER_MASTER_SNAPSHOT_MISMATCH';
  end if;

  if new.occurred_at <> v_transaction_occurred_at
     or new.recorded_at <> v_transaction_recorded_at then
    raise exception using
      errcode = 'P0001',
      message = 'LEDGER_TRANSACTION_TIME_MISMATCH';
  end if;

  return new;
end;
$$;

create or replace function catalog.assert_master_data_caller(
  p_organization_id uuid,
  p_process_name text
)
returns table (
  actor_user_id uuid,
  process_name text
)
language plpgsql
security definer
set search_path = pg_catalog, auth, app
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text := coalesce(
    auth.jwt() ->> 'role',
    current_setting('request.jwt.claim.role', true)
  );
begin
  if p_organization_id is null
     or not exists (
       select 1
       from app.organizations organization
       where organization.id = p_organization_id
         and organization.is_active
     ) then
    raise exception using
      errcode = '42501',
      message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  if v_jwt_role = 'anon'
     or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using
      errcode = '42501',
      message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using
      errcode = '42501',
      message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id then
      raise exception using
        errcode = '42501',
        message = 'ORGANIZATION_ACCESS_DENIED';
    end if;

    return query select v_actor_user_id, null::text;
    return;
  end if;

  return query select null::uuid, p_process_name;
end;
$$;

create or replace function catalog.start_master_data_command(
  p_organization_id uuid,
  p_scope text,
  p_idempotency_key text,
  p_request_hash text
)
returns table (
  command_id uuid,
  is_replay boolean,
  response_snapshot jsonb
)
language plpgsql
security definer
set search_path = pg_catalog, inventory
as $$
declare
  v_key text := btrim(coalesce(p_idempotency_key, ''));
  v_existing inventory.idempotency_commands%rowtype;
  v_command_id uuid := gen_random_uuid();
begin
  if v_key = '' then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  if length(v_key) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':' || p_scope || ':' || v_key,
      0::bigint
    )
  );

  select command.*
  into v_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id
    and command.scope = p_scope
    and command.key = v_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_KEY_REUSED';
    end if;

    if v_existing.status_code = 'SUCCEEDED' then
      return query
      select v_existing.id, true, v_existing.response_snapshot;
      return;
    end if;

    if v_existing.status_code = 'STARTED' then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  insert into inventory.idempotency_commands (
    id,
    organization_id,
    scope,
    key,
    request_hash,
    status_code,
    started_at,
    response_snapshot
  ) values (
    v_command_id,
    p_organization_id,
    p_scope,
    v_key,
    p_request_hash,
    'STARTED',
    clock_timestamp(),
    '{}'::jsonb
  );

  return query select v_command_id, false, '{}'::jsonb;
end;
$$;

create or replace function catalog.complete_master_data_command(
  p_command_id uuid,
  p_response_snapshot jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, inventory
as $$
begin
  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    response_snapshot = p_response_snapshot,
    error_code = null
  where command.id = p_command_id
    and command.status_code = 'STARTED';

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_COMMAND_NOT_STARTED';
  end if;
end;
$$;

create or replace function catalog.record_master_data_audit(
  p_organization_id uuid,
  p_entity_type_code text,
  p_entity_id uuid,
  p_action_code text,
  p_idempotency_command_id uuid,
  p_before_snapshot jsonb,
  p_after_snapshot jsonb,
  p_reason text,
  p_note text,
  p_actor_user_id uuid,
  p_process_name text,
  p_occurred_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, catalog
as $$
declare
  v_audit_id uuid;
begin
  insert into catalog.master_data_audit_events (
    organization_id,
    entity_type_code,
    entity_id,
    action_code,
    idempotency_command_id,
    before_snapshot,
    after_snapshot,
    reason,
    note,
    actor_user_id,
    process_name,
    occurred_at,
    recorded_at,
    schema_version
  ) values (
    p_organization_id,
    p_entity_type_code,
    p_entity_id,
    p_action_code,
    p_idempotency_command_id,
    p_before_snapshot,
    p_after_snapshot,
    nullif(btrim(coalesce(p_reason, '')), ''),
    nullif(btrim(coalesce(p_note, '')), ''),
    p_actor_user_id,
    p_process_name,
    p_occurred_at,
    p_occurred_at,
    1
  )
  returning id into v_audit_id;

  return v_audit_id;
end;
$$;

revoke all on function catalog.assert_master_data_caller(uuid, text)
from public, anon, authenticated, service_role;

revoke all on function catalog.start_master_data_command(
  uuid,
  text,
  text,
  text
) from public, anon, authenticated, service_role;

revoke all on function catalog.complete_master_data_command(uuid, jsonb)
from public, anon, authenticated, service_role;

revoke all on function catalog.record_master_data_audit(
  uuid,
  text,
  uuid,
  text,
  uuid,
  jsonb,
  jsonb,
  text,
  text,
  uuid,
  text,
  timestamptz
) from public, anon, authenticated, service_role;

create or replace function api.create_product(
  p_organization_id uuid,
  p_idempotency_key text,
  p_sku text,
  p_name text,
  p_unit_code text default 'UNIT',
  p_description text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, extensions
as $$
declare
  v_scope constant text := 'CREATE_PRODUCT';
  v_sku text :=
    catalog.normalize_master_identifier(coalesce(p_sku, ''));
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_unit_code text := upper(btrim(coalesce(p_unit_code, '')));
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_request_hash text;
  v_caller record;
  v_command record;
  v_product catalog.products%rowtype;
  v_product_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_audit_id uuid;
  v_response jsonb;
begin
  select *
  into v_caller
  from catalog.assert_master_data_caller(
    p_organization_id,
    'api.create_product'
  );

  if v_sku = '' or v_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_REQUIRED_FIELDS_MISSING';
  end if;

  if v_unit_code <> 'UNIT' then
    raise exception using
      errcode = 'P0001',
      message = 'UNSUPPORTED_UNIT';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'sku', v_sku,
          'name', v_name,
          'unitCode', v_unit_code,
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
      p_organization_id::text || ':PRODUCT_SKU:' || v_sku,
      0::bigint
    )
  );

  if exists (
    select 1
    from catalog.products product
    where product.organization_id = p_organization_id
      and catalog.normalize_master_identifier(product.sku) = v_sku
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'DUPLICATE_SKU';
  end if;

  begin
    insert into catalog.products (
      id,
      organization_id,
      sku,
      name,
      unit_code,
      barcode,
      description,
      is_batch_tracked,
      is_expiry_tracked,
      is_active,
      created_at,
      created_by,
      updated_at,
      updated_by,
      row_version
    ) values (
      v_product_id,
      p_organization_id,
      v_sku,
      v_name,
      'UNIT',
      null,
      v_description,
      true,
      true,
      true,
      v_recorded_at,
      v_caller.actor_user_id,
      v_recorded_at,
      v_caller.actor_user_id,
      1
    )
    returning * into v_product;
  exception
    when unique_violation then
      raise exception using
        errcode = 'P0001',
        message = 'DUPLICATE_SKU';
  end;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'PRODUCT',
    v_product.id,
    'PRODUCT_CREATE',
    v_command.command_id,
    null,
    catalog.product_master_snapshot(v_product),
    null,
    v_note,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', 'CREATED',
    'productId', v_product.id,
    'sku', v_product.sku,
    'name', v_product.name,
    'unitCode', v_product.unit_code,
    'description', v_product.description,
    'isActive', v_product.is_active,
    'rowVersion', v_product.row_version,
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

create or replace function api.update_product(
  p_organization_id uuid,
  p_idempotency_key text,
  p_product_id uuid,
  p_expected_row_version bigint,
  p_sku text,
  p_name text,
  p_unit_code text default 'UNIT',
  p_description text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, extensions
as $$
declare
  v_scope constant text := 'UPDATE_PRODUCT';
  v_sku text :=
    catalog.normalize_master_identifier(coalesce(p_sku, ''));
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_unit_code text := upper(btrim(coalesce(p_unit_code, '')));
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_request_hash text;
  v_caller record;
  v_command record;
  v_before catalog.products%rowtype;
  v_after catalog.products%rowtype;
  v_recorded_at timestamptz := clock_timestamp();
  v_audit_id uuid;
  v_response jsonb;
begin
  select *
  into v_caller
  from catalog.assert_master_data_caller(
    p_organization_id,
    'api.update_product'
  );

  if p_product_id is null
     or v_sku = ''
     or v_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_REQUIRED_FIELDS_MISSING';
  end if;

  if v_unit_code <> 'UNIT' then
    raise exception using
      errcode = 'P0001',
      message = 'UNSUPPORTED_UNIT';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'productId', p_product_id,
          'expectedRowVersion', p_expected_row_version,
          'sku', v_sku,
          'name', v_name,
          'unitCode', v_unit_code,
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

  select product.*
  into v_before
  from catalog.products product
  where product.organization_id = p_organization_id
    and product.id = p_product_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_NOT_FOUND';
  end if;

  if p_expected_row_version is null
     or v_before.row_version <> p_expected_row_version then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_STALE_VERSION';
  end if;

  if v_sku <> v_before.sku
     and catalog.product_has_authoritative_history(
       p_organization_id,
       p_product_id
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'TRANSACTED_SKU_CHANGE_FORBIDDEN';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':PRODUCT_SKU:' || v_sku,
      0::bigint
    )
  );

  if exists (
    select 1
    from catalog.products product
    where product.organization_id = p_organization_id
      and product.id <> p_product_id
      and catalog.normalize_master_identifier(product.sku) = v_sku
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'DUPLICATE_SKU';
  end if;

  begin
    update catalog.products product
    set
      sku = v_sku,
      name = v_name,
      unit_code = 'UNIT',
      description = v_description,
      updated_by = v_caller.actor_user_id
    where product.organization_id = p_organization_id
      and product.id = p_product_id
    returning * into v_after;
  exception
    when unique_violation then
      raise exception using
        errcode = 'P0001',
        message = 'DUPLICATE_SKU';
  end;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'PRODUCT',
    v_after.id,
    'PRODUCT_UPDATE',
    v_command.command_id,
    catalog.product_master_snapshot(v_before),
    catalog.product_master_snapshot(v_after),
    null,
    v_note,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', 'UPDATED',
    'productId', v_after.id,
    'sku', v_after.sku,
    'name', v_after.name,
    'unitCode', v_after.unit_code,
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

create or replace function catalog.change_product_active_state(
  p_organization_id uuid,
  p_idempotency_key text,
  p_product_id uuid,
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
    when p_target_active then 'REACTIVATE_PRODUCT'
    else 'ARCHIVE_PRODUCT'
  end;
  v_action text := case
    when p_target_active then 'PRODUCT_REACTIVATE'
    else 'PRODUCT_ARCHIVE'
  end;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_request_hash text;
  v_caller record;
  v_command record;
  v_before catalog.products%rowtype;
  v_after catalog.products%rowtype;
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
          'productId', p_product_id,
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

  select product.*
  into v_before
  from catalog.products product
  where product.organization_id = p_organization_id
    and product.id = p_product_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_NOT_FOUND';
  end if;

  if p_expected_row_version is null
     or v_before.row_version <> p_expected_row_version then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_STALE_VERSION';
  end if;

  if not p_target_active and not v_before.is_active then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_ALREADY_ARCHIVED';
  end if;

  if p_target_active and v_before.is_active then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_NOT_ARCHIVED';
  end if;

  if p_target_active and exists (
    select 1
    from catalog.products product
    where product.organization_id = p_organization_id
      and product.id <> p_product_id
      and product.is_active
      and catalog.normalize_master_identifier(product.sku)
        = catalog.normalize_master_identifier(v_before.sku)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_REACTIVATION_CONFLICT';
  end if;

  begin
    update catalog.products product
    set
      is_active = p_target_active,
      updated_by = v_caller.actor_user_id
    where product.organization_id = p_organization_id
      and product.id = p_product_id
    returning * into v_after;
  exception
    when unique_violation then
      raise exception using
        errcode = 'P0001',
        message = 'PRODUCT_REACTIVATION_CONFLICT';
  end;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'PRODUCT',
    v_after.id,
    v_action,
    v_command.command_id,
    catalog.product_master_snapshot(v_before),
    catalog.product_master_snapshot(v_after),
    v_reason,
    null,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', case
      when p_target_active then 'REACTIVATED'
      else 'ARCHIVED'
    end,
    'productId', v_after.id,
    'sku', v_after.sku,
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

revoke all on function catalog.change_product_active_state(
  uuid,
  text,
  uuid,
  bigint,
  boolean,
  text,
  text
) from public, anon, authenticated, service_role;

create or replace function api.archive_product(
  p_organization_id uuid,
  p_idempotency_key text,
  p_product_id uuid,
  p_expected_row_version bigint,
  p_reason text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalog
as $$
  select catalog.change_product_active_state(
    p_organization_id,
    p_idempotency_key,
    p_product_id,
    p_expected_row_version,
    false,
    p_reason,
    'api.archive_product'
  )
$$;

create or replace function api.reactivate_product(
  p_organization_id uuid,
  p_idempotency_key text,
  p_product_id uuid,
  p_expected_row_version bigint,
  p_reason text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalog
as $$
  select catalog.change_product_active_state(
    p_organization_id,
    p_idempotency_key,
    p_product_id,
    p_expected_row_version,
    true,
    p_reason,
    'api.reactivate_product'
  )
$$;

create or replace function api.create_product_batch(
  p_organization_id uuid,
  p_idempotency_key text,
  p_product_id uuid,
  p_batch_code text,
  p_expiry_date date,
  p_manufactured_date date default null,
  p_received_first_at timestamptz default null,
  p_batch_kind_code text default 'STANDARD',
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, extensions
as $$
declare
  v_scope constant text := 'CREATE_PRODUCT_BATCH';
  v_batch_code text :=
    catalog.normalize_master_identifier(coalesce(p_batch_code, ''));
  v_batch_kind_code text :=
    upper(btrim(coalesce(p_batch_kind_code, '')));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_request_hash text;
  v_caller record;
  v_command record;
  v_product catalog.products%rowtype;
  v_batch catalog.product_batches%rowtype;
  v_batch_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_audit_id uuid;
  v_response jsonb;
begin
  select *
  into v_caller
  from catalog.assert_master_data_caller(
    p_organization_id,
    'api.create_product_batch'
  );

  if p_product_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_NOT_FOUND';
  end if;

  if v_batch_code = '' then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_CODE_REQUIRED';
  end if;

  if p_expiry_date is null then
    raise exception using
      errcode = 'P0001',
      message = 'EXPIRY_DATE_REQUIRED';
  end if;

  if p_manufactured_date is not null
     and p_manufactured_date > p_expiry_date then
    raise exception using
      errcode = 'P0001',
      message = 'INVALID_BATCH_DATE_RANGE';
  end if;

  if v_batch_kind_code <> 'STANDARD' then
    raise exception using
      errcode = 'P0001',
      message = case
        when v_batch_kind_code in ('RETURN', 'UNIDENTIFIED_RETURN')
          then 'MANUAL_BATCH_KIND_FORBIDDEN'
        else 'MANUAL_BATCH_KIND_FORBIDDEN'
      end;
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'productId', p_product_id,
          'batchCode', v_batch_code,
          'expiryDate', p_expiry_date,
          'manufacturedDate', p_manufactured_date,
          'receivedFirstAt', p_received_first_at,
          'batchKindCode', v_batch_kind_code,
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

  select product.*
  into v_product
  from catalog.products product
  where product.organization_id = p_organization_id
    and product.id = p_product_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_NOT_FOUND';
  end if;

  if not v_product.is_active then
    raise exception using
      errcode = 'P0001',
      message = 'INACTIVE_PRODUCT_FOR_TRANSACTION';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text ||
      ':PRODUCT_BATCH:' ||
      p_product_id::text ||
      ':' ||
      v_batch_code,
      0::bigint
    )
  );

  if exists (
    select 1
    from catalog.product_batches batch
    where batch.organization_id = p_organization_id
      and batch.product_id = p_product_id
      and catalog.normalize_master_identifier(batch.batch_code)
        = v_batch_code
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'DUPLICATE_PRODUCT_BATCH';
  end if;

  begin
    insert into catalog.product_batches (
      id,
      organization_id,
      product_id,
      batch_code,
      manufactured_date,
      expiry_date,
      received_first_at,
      status_code,
      block_reason,
      created_at,
      created_by,
      updated_at,
      updated_by,
      row_version,
      batch_kind_code
    ) values (
      v_batch_id,
      p_organization_id,
      p_product_id,
      v_batch_code,
      p_manufactured_date,
      p_expiry_date,
      p_received_first_at,
      'ACTIVE',
      null,
      v_recorded_at,
      v_caller.actor_user_id,
      v_recorded_at,
      v_caller.actor_user_id,
      1,
      'STANDARD'
    )
    returning * into v_batch;
  exception
    when unique_violation then
      raise exception using
        errcode = 'P0001',
        message = 'DUPLICATE_PRODUCT_BATCH';
  end;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'BATCH',
    v_batch.id,
    'BATCH_CREATE',
    v_command.command_id,
    null,
    catalog.product_batch_master_snapshot(v_batch),
    null,
    v_note,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', 'CREATED',
    'batchId', v_batch.id,
    'productId', v_batch.product_id,
    'batchCode', v_batch.batch_code,
    'manufacturedDate', v_batch.manufactured_date,
    'expiryDate', v_batch.expiry_date,
    'receivedFirstAt', v_batch.received_first_at,
    'lifecycleStatusCode', v_batch.status_code,
    'batchKindCode', v_batch.batch_kind_code,
    'rowVersion', v_batch.row_version,
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

create or replace function api.update_product_batch(
  p_organization_id uuid,
  p_idempotency_key text,
  p_batch_id uuid,
  p_expected_row_version bigint,
  p_product_id uuid,
  p_batch_kind_code text,
  p_batch_code text,
  p_manufactured_date date,
  p_expiry_date date,
  p_received_first_at timestamptz,
  p_reason text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, extensions
as $$
declare
  v_scope constant text := 'UPDATE_PRODUCT_BATCH';
  v_batch_code text :=
    catalog.normalize_master_identifier(coalesce(p_batch_code, ''));
  v_batch_kind_code text :=
    upper(btrim(coalesce(p_batch_kind_code, '')));
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_request_hash text;
  v_caller record;
  v_command record;
  v_before catalog.product_batches%rowtype;
  v_after catalog.product_batches%rowtype;
  v_has_history boolean;
  v_recorded_at timestamptz := clock_timestamp();
  v_audit_id uuid;
  v_response jsonb;
begin
  select *
  into v_caller
  from catalog.assert_master_data_caller(
    p_organization_id,
    'api.update_product_batch'
  );

  if p_batch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_NOT_FOUND';
  end if;

  if v_batch_code = '' then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_CODE_REQUIRED';
  end if;

  if p_expiry_date is null then
    raise exception using
      errcode = 'P0001',
      message = 'EXPIRY_DATE_REQUIRED';
  end if;

  if p_manufactured_date is not null
     and p_manufactured_date > p_expiry_date then
    raise exception using
      errcode = 'P0001',
      message = 'INVALID_BATCH_DATE_RANGE';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'batchId', p_batch_id,
          'expectedRowVersion', p_expected_row_version,
          'productId', p_product_id,
          'batchKindCode', v_batch_kind_code,
          'batchCode', v_batch_code,
          'manufacturedDate', p_manufactured_date,
          'expiryDate', p_expiry_date,
          'receivedFirstAt', p_received_first_at,
          'reason', v_reason,
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

  select batch.*
  into v_before
  from catalog.product_batches batch
  where batch.organization_id = p_organization_id
    and batch.id = p_batch_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_NOT_FOUND';
  end if;

  if p_expected_row_version is null
     or v_before.row_version <> p_expected_row_version then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_STALE_VERSION';
  end if;

  if p_product_id is distinct from v_before.product_id then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_PRODUCT_CHANGE_FORBIDDEN';
  end if;

  if v_batch_kind_code is distinct from v_before.batch_kind_code then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_KIND_CHANGE_FORBIDDEN';
  end if;

  v_has_history :=
    catalog.product_batch_has_authoritative_history(
      p_organization_id,
      p_batch_id
    );

  if v_batch_code <> v_before.batch_code and v_has_history then
    raise exception using
      errcode = 'P0001',
      message = 'TRANSACTED_BATCH_CODE_CHANGE_FORBIDDEN';
  end if;

  if p_expiry_date is distinct from v_before.expiry_date
     and v_has_history
     and v_reason is null then
    raise exception using
      errcode = 'P0001',
      message = 'EXPIRY_CHANGE_REASON_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text ||
      ':PRODUCT_BATCH:' ||
      v_before.product_id::text ||
      ':' ||
      v_batch_code,
      0::bigint
    )
  );

  if exists (
    select 1
    from catalog.product_batches batch
    where batch.organization_id = p_organization_id
      and batch.product_id = v_before.product_id
      and batch.id <> p_batch_id
      and catalog.normalize_master_identifier(batch.batch_code)
        = v_batch_code
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'DUPLICATE_PRODUCT_BATCH';
  end if;

  begin
    update catalog.product_batches batch
    set
      batch_code = v_batch_code,
      manufactured_date = p_manufactured_date,
      expiry_date = p_expiry_date,
      received_first_at = p_received_first_at,
      updated_by = v_caller.actor_user_id
    where batch.organization_id = p_organization_id
      and batch.id = p_batch_id
    returning * into v_after;
  exception
    when unique_violation then
      raise exception using
        errcode = 'P0001',
        message = 'DUPLICATE_PRODUCT_BATCH';
  end;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'BATCH',
    v_after.id,
    'BATCH_UPDATE',
    v_command.command_id,
    catalog.product_batch_master_snapshot(v_before),
    catalog.product_batch_master_snapshot(v_after),
    v_reason,
    v_note,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', 'UPDATED',
    'batchId', v_after.id,
    'productId', v_after.product_id,
    'batchCode', v_after.batch_code,
    'manufacturedDate', v_after.manufactured_date,
    'expiryDate', v_after.expiry_date,
    'receivedFirstAt', v_after.received_first_at,
    'lifecycleStatusCode', v_after.status_code,
    'batchKindCode', v_after.batch_kind_code,
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

create or replace function catalog.change_product_batch_lifecycle(
  p_organization_id uuid,
  p_idempotency_key text,
  p_batch_id uuid,
  p_expected_row_version bigint,
  p_action_code text,
  p_reason text,
  p_note text,
  p_process_name text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, extensions
as $$
declare
  v_scope text := p_action_code;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_target_status text;
  v_request_hash text;
  v_caller record;
  v_command record;
  v_before catalog.product_batches%rowtype;
  v_after catalog.product_batches%rowtype;
  v_product catalog.products%rowtype;
  v_timezone text;
  v_local_date date;
  v_recorded_at timestamptz := clock_timestamp();
  v_audit_id uuid;
  v_response jsonb;
begin
  if p_action_code not in (
    'BATCH_BLOCK',
    'BATCH_UNBLOCK',
    'BATCH_ARCHIVE',
    'BATCH_REACTIVATE'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_LIFECYCLE_ACTION_INVALID';
  end if;

  if v_reason is null then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_STATUS_REASON_REQUIRED';
  end if;

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
          'batchId', p_batch_id,
          'expectedRowVersion', p_expected_row_version,
          'actionCode', p_action_code,
          'reason', v_reason,
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

  select batch.*
  into v_before
  from catalog.product_batches batch
  where batch.organization_id = p_organization_id
    and batch.id = p_batch_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_NOT_FOUND';
  end if;

  if p_expected_row_version is null
     or v_before.row_version <> p_expected_row_version then
    raise exception using
      errcode = 'P0001',
      message = 'BATCH_STALE_VERSION';
  end if;

  select product.*
  into v_product
  from catalog.products product
  where product.organization_id = p_organization_id
    and product.id = v_before.product_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCT_NOT_FOUND';
  end if;

  select organization.timezone
  into v_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  v_local_date :=
    (v_recorded_at at time zone v_timezone)::date;

  case p_action_code
    when 'BATCH_BLOCK' then
      if v_before.status_code <> 'ACTIVE' then
        raise exception using
          errcode = 'P0001',
          message = 'BATCH_NOT_ACTIVE';
      end if;
      v_target_status := 'BLOCKED';
    when 'BATCH_UNBLOCK' then
      if v_before.status_code <> 'BLOCKED' then
        raise exception using
          errcode = 'P0001',
          message = 'BATCH_NOT_BLOCKED';
      end if;
      if v_before.expiry_date < v_local_date then
        raise exception using
          errcode = 'P0001',
          message = 'BATCH_EFFECTIVELY_EXPIRED';
      end if;
      v_target_status := 'ACTIVE';
    when 'BATCH_ARCHIVE' then
      if v_before.status_code = 'ARCHIVED' then
        raise exception using
          errcode = 'P0001',
          message = 'BATCH_ALREADY_ARCHIVED';
      end if;
      v_target_status := 'ARCHIVED';
    when 'BATCH_REACTIVATE' then
      if v_before.status_code <> 'ARCHIVED' then
        raise exception using
          errcode = 'P0001',
          message = 'BATCH_NOT_ARCHIVED';
      end if;
      if not v_product.is_active then
        raise exception using
          errcode = 'P0001',
          message = 'PRODUCT_REACTIVATION_CONFLICT';
      end if;
      if v_before.expiry_date < v_local_date then
        raise exception using
          errcode = 'P0001',
          message = 'BATCH_EFFECTIVELY_EXPIRED';
      end if;
      if exists (
        select 1
        from catalog.product_batches batch
        where batch.organization_id = p_organization_id
          and batch.product_id = v_before.product_id
          and batch.id <> v_before.id
          and catalog.normalize_master_identifier(batch.batch_code)
            = catalog.normalize_master_identifier(v_before.batch_code)
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'DUPLICATE_PRODUCT_BATCH';
      end if;
      v_target_status := 'ACTIVE';
  end case;

  update catalog.product_batches batch
  set
    status_code = v_target_status,
    block_reason = case
      when v_target_status = 'BLOCKED' then v_reason
      else null
    end,
    updated_by = v_caller.actor_user_id
  where batch.organization_id = p_organization_id
    and batch.id = p_batch_id
  returning * into v_after;

  v_audit_id := catalog.record_master_data_audit(
    p_organization_id,
    'BATCH',
    v_after.id,
    p_action_code,
    v_command.command_id,
    catalog.product_batch_master_snapshot(v_before),
    catalog.product_batch_master_snapshot(v_after),
    v_reason,
    v_note,
    v_caller.actor_user_id,
    v_caller.process_name,
    v_recorded_at
  );

  v_response := jsonb_build_object(
    'status', replace(p_action_code, 'BATCH_', ''),
    'batchId', v_after.id,
    'productId', v_after.product_id,
    'batchCode', v_after.batch_code,
    'lifecycleStatusCode', v_after.status_code,
    'effectiveExpiryState', case
      when v_after.expiry_date < v_local_date then 'EXPIRED'
      when v_after.expiry_date = v_local_date then 'EXPIRES_TODAY'
      else 'CURRENT'
    end,
    'blockReason', v_after.block_reason,
    'batchKindCode', v_after.batch_kind_code,
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

revoke all on function catalog.change_product_batch_lifecycle(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text,
  text,
  text
) from public, anon, authenticated, service_role;

create or replace function api.block_product_batch(
  p_organization_id uuid,
  p_idempotency_key text,
  p_batch_id uuid,
  p_expected_row_version bigint,
  p_reason text,
  p_note text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalog
as $$
  select catalog.change_product_batch_lifecycle(
    p_organization_id,
    p_idempotency_key,
    p_batch_id,
    p_expected_row_version,
    'BATCH_BLOCK',
    p_reason,
    p_note,
    'api.block_product_batch'
  )
$$;

create or replace function api.unblock_product_batch(
  p_organization_id uuid,
  p_idempotency_key text,
  p_batch_id uuid,
  p_expected_row_version bigint,
  p_reason text,
  p_note text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalog
as $$
  select catalog.change_product_batch_lifecycle(
    p_organization_id,
    p_idempotency_key,
    p_batch_id,
    p_expected_row_version,
    'BATCH_UNBLOCK',
    p_reason,
    p_note,
    'api.unblock_product_batch'
  )
$$;

create or replace function api.archive_product_batch(
  p_organization_id uuid,
  p_idempotency_key text,
  p_batch_id uuid,
  p_expected_row_version bigint,
  p_reason text,
  p_note text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalog
as $$
  select catalog.change_product_batch_lifecycle(
    p_organization_id,
    p_idempotency_key,
    p_batch_id,
    p_expected_row_version,
    'BATCH_ARCHIVE',
    p_reason,
    p_note,
    'api.archive_product_batch'
  )
$$;

create or replace function api.reactivate_product_batch(
  p_organization_id uuid,
  p_idempotency_key text,
  p_batch_id uuid,
  p_expected_row_version bigint,
  p_reason text,
  p_note text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalog
as $$
  select catalog.change_product_batch_lifecycle(
    p_organization_id,
    p_idempotency_key,
    p_batch_id,
    p_expected_row_version,
    'BATCH_REACTIVATE',
    p_reason,
    p_note,
    'api.reactivate_product_batch'
  )
$$;

create or replace view api.product_master
with (security_invoker = true)
as
select
  product.id as product_id,
  product.organization_id,
  product.sku,
  product.name,
  product.unit_code,
  product.description,
  product.is_active,
  product.row_version,
  product.created_at,
  product.created_by,
  product.updated_at,
  product.updated_by,
  coalesce(position.sellable_qty, 0)::bigint as sellable_qty,
  coalesce(position.quarantine_qty, 0)::bigint as quarantine_qty,
  coalesce(position.damaged_qty, 0)::bigint as damaged_qty,
  coalesce(position.reserved_qty, 0)::bigint as reserved_qty,
  (
    coalesce(position.sellable_qty, 0)
    - coalesce(position.reserved_qty, 0)
  )::bigint as available_qty,
  coalesce(position.last_ledger_seq, 0)::bigint as last_ledger_seq,
  catalog.product_has_authoritative_history(
    product.organization_id,
    product.id
  ) as has_authoritative_history,
  (
    select count(*)
    from catalog.product_batches batch
    where batch.organization_id = product.organization_id
      and batch.product_id = product.id
  )::bigint as batch_count,
  (
    select count(*)
    from (
      select
        'SINGLE:' || version.listing_id::text as listing_reference
      from catalog.marketplace_single_listing_versions version
      where version.organization_id = product.organization_id
        and version.product_id = product.id
      union
      select
        'BUNDLE:' || listing.id::text
      from catalog.bundle_components component
      join catalog.bundle_recipes recipe
        on recipe.id = component.bundle_recipe_id
      join catalog.marketplace_listings listing
        on listing.organization_id = recipe.organization_id
       and listing.channel_id = recipe.channel_id
       and listing.external_listing_code = recipe.external_listing_sku
      where recipe.organization_id = product.organization_id
        and component.product_id = product.id
    ) reference
  )::bigint as listing_reference_count
from catalog.products product
left join inventory.stock_product_positions position
  on position.organization_id = product.organization_id
 and position.product_id = product.id;

create or replace view api.product_batch_master
with (security_invoker = true)
as
select
  batch.id as batch_id,
  batch.organization_id,
  batch.product_id,
  product.sku as product_sku,
  product.name as product_name,
  product.is_active as product_is_active,
  batch.batch_code,
  batch.manufactured_date,
  batch.expiry_date,
  batch.received_first_at,
  batch.status_code as lifecycle_status_code,
  case
    when batch.expiry_date < local_context.local_date then 'EXPIRED'
    when batch.expiry_date = local_context.local_date then 'EXPIRES_TODAY'
    else 'CURRENT'
  end as effective_expiry_state,
  batch.expiry_date < local_context.local_date
    as is_effectively_expired,
  (batch.expiry_date - local_context.local_date)::integer
    as days_to_expiry,
  batch.block_reason,
  batch.batch_kind_code,
  batch.row_version,
  coalesce(balance.sellable_qty, 0)::bigint as sellable_qty,
  coalesce(balance.quarantine_qty, 0)::bigint as quarantine_qty,
  coalesce(balance.damaged_qty, 0)::bigint as damaged_qty,
  coalesce(position.reserved_qty, 0)::bigint as reserved_qty,
  (
    coalesce(position.sellable_qty, 0)
    - coalesce(position.reserved_qty, 0)
  )::bigint as available_qty,
  'PRODUCT'::text as reservation_scope_code,
  coalesce(balance.last_ledger_seq, 0)::bigint as last_ledger_seq,
  catalog.product_batch_has_authoritative_history(
    batch.organization_id,
    batch.id
  ) as has_authoritative_history,
  (
    product.is_active
    and batch.status_code = 'ACTIVE'
    and batch.expiry_date
      > local_context.local_date + local_context.safety_buffer_days
    and coalesce(balance.sellable_qty, 0) > 0
    and (
      coalesce(position.sellable_qty, 0)
      - coalesce(position.reserved_qty, 0)
    ) > 0
  ) as is_fefo_eligible,
  local_context.local_date,
  local_context.safety_buffer_days,
  batch.created_at,
  batch.created_by,
  batch.updated_at,
  batch.updated_by
from catalog.product_batches batch
join catalog.products product
  on product.organization_id = batch.organization_id
 and product.id = batch.product_id
join app.organizations organization
  on organization.id = batch.organization_id
left join inventory.stock_batch_balances balance
  on balance.organization_id = batch.organization_id
 and balance.batch_id = batch.id
left join inventory.stock_product_positions position
  on position.organization_id = batch.organization_id
 and position.product_id = batch.product_id
cross join lateral (
  select
    (clock_timestamp() at time zone organization.timezone)::date
      as local_date,
    coalesce(
      (
        select case
          when jsonb_typeof(setting.value) = 'number'
            then (setting.value #>> '{}')::integer
          else 0
        end
        from app.settings setting
        where setting.organization_id = batch.organization_id
          and setting.key = 'expiry.safety_buffer_days'
          and setting.effective_from <= clock_timestamp()
          and (
            setting.effective_to is null
            or setting.effective_to > clock_timestamp()
          )
        order by setting.version desc, setting.effective_from desc
        limit 1
      ),
      0
    )::integer as safety_buffer_days
) local_context;

create or replace view api.product_master_audit
with (security_invoker = true)
as
select
  audit.id as audit_id,
  audit.organization_id,
  audit.entity_id as product_id,
  audit.action_code,
  audit.idempotency_command_id,
  command.scope as command_scope,
  command.key as idempotency_key,
  audit.before_snapshot,
  audit.after_snapshot,
  audit.reason,
  audit.note,
  audit.actor_user_id,
  profile.display_name as actor_display_name,
  audit.process_name,
  audit.occurred_at,
  audit.recorded_at,
  audit.schema_version
from catalog.master_data_audit_events audit
join inventory.idempotency_commands command
  on command.id = audit.idempotency_command_id
 and command.organization_id = audit.organization_id
left join app.user_profiles profile
  on profile.user_id = audit.actor_user_id
 and profile.organization_id = audit.organization_id
where audit.entity_type_code = 'PRODUCT';

create or replace view api.product_batch_master_audit
with (security_invoker = true)
as
select
  audit.id as audit_id,
  audit.organization_id,
  audit.entity_id as batch_id,
  audit.action_code,
  audit.idempotency_command_id,
  command.scope as command_scope,
  command.key as idempotency_key,
  audit.before_snapshot,
  audit.after_snapshot,
  audit.reason,
  audit.note,
  audit.actor_user_id,
  profile.display_name as actor_display_name,
  audit.process_name,
  audit.occurred_at,
  audit.recorded_at,
  audit.schema_version
from catalog.master_data_audit_events audit
join inventory.idempotency_commands command
  on command.id = audit.idempotency_command_id
 and command.organization_id = audit.organization_id
left join app.user_profiles profile
  on profile.user_id = audit.actor_user_id
 and profile.organization_id = audit.organization_id
where audit.entity_type_code = 'BATCH';

revoke all on api.product_master,
              api.product_batch_master,
              api.product_master_audit,
              api.product_batch_master_audit
from public, anon;

grant select on api.product_master,
                api.product_batch_master,
                api.product_master_audit,
                api.product_batch_master_audit
to authenticated, service_role;

revoke all on function api.create_product(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text
) from public, anon;

grant execute on function api.create_product(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text
) to authenticated, service_role;

revoke all on function api.update_product(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text,
  text,
  text,
  text
) from public, anon;

grant execute on function api.update_product(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text,
  text,
  text,
  text
) to authenticated, service_role;

revoke all on function api.archive_product(
  uuid,
  text,
  uuid,
  bigint,
  text
) from public, anon;

grant execute on function api.archive_product(
  uuid,
  text,
  uuid,
  bigint,
  text
) to authenticated, service_role;

revoke all on function api.reactivate_product(
  uuid,
  text,
  uuid,
  bigint,
  text
) from public, anon;

grant execute on function api.reactivate_product(
  uuid,
  text,
  uuid,
  bigint,
  text
) to authenticated, service_role;

revoke all on function api.create_product_batch(
  uuid,
  text,
  uuid,
  text,
  date,
  date,
  timestamptz,
  text,
  text
) from public, anon;

grant execute on function api.create_product_batch(
  uuid,
  text,
  uuid,
  text,
  date,
  date,
  timestamptz,
  text,
  text
) to authenticated, service_role;

revoke all on function api.update_product_batch(
  uuid,
  text,
  uuid,
  bigint,
  uuid,
  text,
  text,
  date,
  date,
  timestamptz,
  text,
  text
) from public, anon;

grant execute on function api.update_product_batch(
  uuid,
  text,
  uuid,
  bigint,
  uuid,
  text,
  text,
  date,
  date,
  timestamptz,
  text,
  text
) to authenticated, service_role;

revoke all on function api.block_product_batch(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text
) from public, anon;

grant execute on function api.block_product_batch(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text
) to authenticated, service_role;

revoke all on function api.unblock_product_batch(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text
) from public, anon;

grant execute on function api.unblock_product_batch(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text
) to authenticated, service_role;

revoke all on function api.archive_product_batch(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text
) from public, anon;

grant execute on function api.archive_product_batch(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text
) to authenticated, service_role;

revoke all on function api.reactivate_product_batch(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text
) from public, anon;

grant execute on function api.reactivate_product_batch(
  uuid,
  text,
  uuid,
  bigint,
  text,
  text
) to authenticated, service_role;

comment on table catalog.master_data_audit_events is
  'Immutable, organization-scoped Product and Batch master-data audit history.';

comment on view api.product_batch_master is
  'Batch lifecycle, effective local expiry, stock buckets, product-scoped reservation, and FEFO eligibility read model.';

commit;
