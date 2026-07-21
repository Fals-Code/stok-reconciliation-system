begin;

create table operations.opening_balance_cutovers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  cutover_no text not null,
  source_ref text not null,
  source_estimate_ref text not null,
  status_code text not null default 'DRAFT',
  cutover_at timestamptz not null,
  effective_local_date date not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  created_by uuid null references auth.users(id) on delete set null,
  create_process_name text null,
  reviewed_at timestamptz null,
  reviewed_by uuid null references auth.users(id) on delete set null,
  review_process_name text null,
  posted_at timestamptz null,
  posted_by uuid null references auth.users(id) on delete set null,
  post_process_name text null,
  transaction_id uuid null references inventory.stock_transactions(id) on delete restrict,
  idempotency_command_id uuid null
    references inventory.idempotency_commands(id) on delete restrict,
  request_hash text null,
  posted_basis_hash text null,
  ledger_seq_before bigint null,
  ledger_seq_after bigint null,
  line_count bigint not null default 0,
  positive_line_count bigint not null default 0,
  total_quantity bigint not null default 0,
  note text not null,
  metadata jsonb not null default '{}'::jsonb,
  row_version bigint not null default 1,
  constraint uq_opening_balance_cutovers_org_id unique (organization_id, id),
  constraint uq_opening_balance_cutovers_org_no unique (organization_id, cutover_no),
  constraint uq_opening_balance_cutovers_org_source unique (organization_id, source_ref),
  constraint uq_opening_balance_cutovers_transaction unique (transaction_id),
  constraint uq_opening_balance_cutovers_idempotency unique (idempotency_command_id),
  constraint ck_opening_balance_cutovers_no_nonblank
    check (btrim(cutover_no) <> ''),
  constraint ck_opening_balance_cutovers_source_nonblank
    check (btrim(source_ref) <> ''),
  constraint ck_opening_balance_cutovers_estimate_nonblank
    check (btrim(source_estimate_ref) <> ''),
  constraint ck_opening_balance_cutovers_status
    check (status_code in ('DRAFT', 'REVIEW', 'POSTED')),
  constraint ck_opening_balance_cutovers_created_actor
    check ((created_by is not null) <> (create_process_name is not null)),
  constraint ck_opening_balance_cutovers_create_process_nonblank
    check (create_process_name is null or btrim(create_process_name) <> ''),
  constraint ck_opening_balance_cutovers_review_actor
    check (
      (reviewed_by is null and review_process_name is null)
      or ((reviewed_by is not null) <> (review_process_name is not null))
    ),
  constraint ck_opening_balance_cutovers_review_process_nonblank
    check (review_process_name is null or btrim(review_process_name) <> ''),
  constraint ck_opening_balance_cutovers_post_actor
    check (
      (posted_by is null and post_process_name is null)
      or ((posted_by is not null) <> (post_process_name is not null))
    ),
  constraint ck_opening_balance_cutovers_post_process_nonblank
    check (post_process_name is null or btrim(post_process_name) <> ''),
  constraint ck_opening_balance_cutovers_request_hash
    check (request_hash is null or request_hash ~ '^[0-9a-f]{64}$'),
  constraint ck_opening_balance_cutovers_basis_hash
    check (posted_basis_hash is null or posted_basis_hash ~ '^[0-9a-f]{64}$'),
  constraint ck_opening_balance_cutovers_ledger_boundary
    check (
      (ledger_seq_before is null and ledger_seq_after is null)
      or (
        ledger_seq_before >= 0
        and ledger_seq_after >= ledger_seq_before
      )
    ),
  constraint ck_opening_balance_cutovers_counts
    check (
      line_count >= 0
      and positive_line_count >= 0
      and positive_line_count <= line_count
      and total_quantity >= 0
    ),
  constraint ck_opening_balance_cutovers_note_nonblank
    check (btrim(note) <> '' and length(note) <= 2000),
  constraint ck_opening_balance_cutovers_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  constraint ck_opening_balance_cutovers_version_positive
    check (row_version > 0),
  constraint ck_opening_balance_cutovers_lifecycle
    check (
      (
        status_code = 'DRAFT'
        and reviewed_at is null
        and reviewed_by is null
        and review_process_name is null
        and posted_at is null
        and posted_by is null
        and post_process_name is null
        and transaction_id is null
        and idempotency_command_id is null
        and request_hash is null
        and posted_basis_hash is null
        and ledger_seq_before is null
        and ledger_seq_after is null
      )
      or
      (
        status_code = 'REVIEW'
        and reviewed_at is not null
        and ((reviewed_by is not null) <> (review_process_name is not null))
        and posted_at is null
        and posted_by is null
        and post_process_name is null
        and transaction_id is null
        and idempotency_command_id is null
        and request_hash is not null
        and posted_basis_hash is null
        and ledger_seq_before is null
        and ledger_seq_after is null
      )
      or
      (
        status_code = 'POSTED'
        and reviewed_at is not null
        and ((reviewed_by is not null) <> (review_process_name is not null))
        and posted_at is not null
        and ((posted_by is not null) <> (post_process_name is not null))
        and transaction_id is not null
        and idempotency_command_id is not null
        and request_hash is not null
        and posted_basis_hash is not null
        and ledger_seq_before is not null
        and ledger_seq_after is not null
      )
    )
);

create table operations.opening_balance_cutover_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  cutover_id uuid not null,
  line_no integer not null,
  product_id uuid not null,
  batch_id uuid not null,
  bucket_code text not null,
  quantity bigint not null,
  batch_identity_verified boolean not null default true,
  exception_reference text null,
  product_sku_snapshot text not null,
  product_name_snapshot text not null,
  batch_code_snapshot text not null,
  expiry_date_snapshot date not null,
  batch_status_code_snapshot text not null,
  product_row_version_snapshot bigint not null,
  batch_row_version_snapshot bigint not null,
  source_line_ref text not null,
  ledger_entry_id uuid null references inventory.stock_ledger_entries(id) on delete restrict,
  batch_bucket_qty_before bigint null,
  batch_bucket_qty_after bigint null,
  product_bucket_qty_before bigint null,
  product_bucket_qty_after bigint null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint uq_opening_balance_cutover_lines_org_id
    unique (organization_id, id),
  constraint fk_opening_balance_cutover_lines_cutover
    foreign key (organization_id, cutover_id)
    references operations.opening_balance_cutovers(organization_id, id)
    on delete restrict,
  constraint fk_opening_balance_cutover_lines_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches(organization_id, product_id, id)
    on delete restrict,
  constraint uq_opening_balance_cutover_lines_number
    unique (cutover_id, line_no),
  constraint uq_opening_balance_cutover_lines_source
    unique (cutover_id, source_line_ref),
  constraint uq_opening_balance_cutover_lines_identity
    unique (cutover_id, product_id, batch_id, bucket_code),
  constraint uq_opening_balance_cutover_lines_ledger
    unique (ledger_entry_id),
  constraint ck_opening_balance_cutover_lines_number
    check (line_no > 0),
  constraint ck_opening_balance_cutover_lines_bucket
    check (bucket_code in ('SELLABLE', 'QUARANTINE', 'DAMAGED')),
  constraint ck_opening_balance_cutover_lines_quantity
    check (quantity >= 0),
  constraint ck_opening_balance_cutover_lines_identity_status
    check (
      (
        batch_identity_verified
        and exception_reference is null
      )
      or
      (
        not batch_identity_verified
        and bucket_code = 'QUARANTINE'
        and exception_reference is not null
        and btrim(exception_reference) <> ''
      )
    ),
  constraint ck_opening_balance_cutover_lines_exception_length
    check (exception_reference is null or length(exception_reference) <= 200),
  constraint ck_opening_balance_cutover_lines_sku_nonblank
    check (btrim(product_sku_snapshot) <> ''),
  constraint ck_opening_balance_cutover_lines_product_nonblank
    check (btrim(product_name_snapshot) <> ''),
  constraint ck_opening_balance_cutover_lines_batch_nonblank
    check (btrim(batch_code_snapshot) <> ''),
  constraint ck_opening_balance_cutover_lines_batch_status
    check (batch_status_code_snapshot in ('ACTIVE', 'BLOCKED', 'EXPIRED', 'ARCHIVED')),
  constraint ck_opening_balance_cutover_lines_versions
    check (product_row_version_snapshot > 0 and batch_row_version_snapshot > 0),
  constraint ck_opening_balance_cutover_lines_source_nonblank
    check (btrim(source_line_ref) <> '' and length(source_line_ref) <= 100),
  constraint ck_opening_balance_cutover_lines_effect_shape
    check (
      (
        batch_bucket_qty_before is null
        and batch_bucket_qty_after is null
        and product_bucket_qty_before is null
        and product_bucket_qty_after is null
        and ledger_entry_id is null
      )
      or
      (
        batch_bucket_qty_before >= 0
        and batch_bucket_qty_after = batch_bucket_qty_before + quantity
        and product_bucket_qty_before >= 0
        and product_bucket_qty_after = product_bucket_qty_before + quantity
        and (
          (quantity = 0 and ledger_entry_id is null)
          or (quantity > 0 and ledger_entry_id is not null)
        )
      )
    )
);

create unique index uidx_opening_balance_cutovers_posted_org
on operations.opening_balance_cutovers(organization_id)
where status_code = 'POSTED';

create index idx_opening_balance_cutovers_org_status
on operations.opening_balance_cutovers(
  organization_id,
  status_code,
  cutover_at desc,
  id
);

create index idx_opening_balance_cutover_lines_scope
on operations.opening_balance_cutover_lines(
  organization_id,
  product_id,
  batch_id,
  bucket_code,
  cutover_id,
  line_no
);

create or replace function operations.guard_opening_balance_cutover_mutation()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CUTOVER_DELETE_FORBIDDEN';
  end if;

  if old.status_code = 'POSTED' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CUTOVER_IMMUTABLE';
  end if;

  if old.status_code = 'DRAFT'
     and new.status_code not in ('DRAFT', 'REVIEW') then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_STATUS_TRANSITION_INVALID';
  end if;

  if old.status_code = 'REVIEW'
     and new.status_code not in ('REVIEW', 'POSTED') then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_STATUS_TRANSITION_INVALID';
  end if;

  return new;
end;
$$;

create trigger trg_opening_balance_cutovers_guard
before update or delete on operations.opening_balance_cutovers
for each row execute function operations.guard_opening_balance_cutover_mutation();

create or replace function operations.guard_opening_balance_cutover_line_mutation()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, operations
as $$
declare
  v_cutover_id uuid;
  v_status text;
begin
  v_cutover_id := case when tg_op = 'DELETE' then old.cutover_id else new.cutover_id end;

  select cutover.status_code
  into v_status
  from operations.opening_balance_cutovers cutover
  where cutover.id = v_cutover_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CUTOVER_NOT_FOUND';
  end if;

  if v_status = 'POSTED' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CUTOVER_LINE_IMMUTABLE';
  end if;

  if tg_op in ('INSERT', 'DELETE') and v_status <> 'DRAFT' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_LINES_NOT_EDITABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create trigger trg_opening_balance_cutover_lines_guard
before insert or update or delete on operations.opening_balance_cutover_lines
for each row execute function operations.guard_opening_balance_cutover_line_mutation();

alter table operations.opening_balance_cutovers enable row level security;
alter table operations.opening_balance_cutover_lines enable row level security;

create policy opening_balance_cutovers_read_current_org
on operations.opening_balance_cutovers
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy opening_balance_cutover_lines_read_current_org
on operations.opening_balance_cutover_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on operations.opening_balance_cutovers,
              operations.opening_balance_cutover_lines
from public, anon, authenticated;

grant select on operations.opening_balance_cutovers,
                operations.opening_balance_cutover_lines
to authenticated, service_role;

create or replace function inventory.opening_balance_cutover_request_payload(
  p_organization_id uuid,
  p_cutover_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, inventory, operations
as $$
declare
  v_cutover operations.opening_balance_cutovers%rowtype;
  v_lines jsonb;
begin
  select cutover.*
  into v_cutover
  from operations.opening_balance_cutovers cutover
  where cutover.organization_id = p_organization_id
    and cutover.id = p_cutover_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CUTOVER_NOT_FOUND';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'lineNo', line.line_no,
        'productId', line.product_id,
        'batchId', line.batch_id,
        'bucketCode', line.bucket_code,
        'quantity', line.quantity,
        'batchIdentityVerified', line.batch_identity_verified,
        'exceptionReference', line.exception_reference,
        'sourceLineRef', line.source_line_ref
      )
      order by line.line_no
    ),
    '[]'::jsonb
  )
  into v_lines
  from operations.opening_balance_cutover_lines line
  where line.organization_id = p_organization_id
    and line.cutover_id = p_cutover_id;

  return jsonb_build_object(
    'organizationId', p_organization_id,
    'cutoverId', p_cutover_id,
    'sourceRef', v_cutover.source_ref,
    'sourceEstimateRef', v_cutover.source_estimate_ref,
    'cutoverAt', v_cutover.cutover_at,
    'effectiveLocalDate', v_cutover.effective_local_date,
    'note', v_cutover.note,
    'metadata', v_cutover.metadata,
    'lines', v_lines,
    'schemaVersion', 1
  );
end;
$$;

revoke all on function inventory.opening_balance_cutover_request_payload(uuid, uuid)
from public, anon, authenticated, service_role;

create or replace function inventory.preview_opening_balance_cutover_core(
  p_organization_id uuid,
  p_cutover_id uuid,
  p_lock_basis boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text :=
    coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_cutover operations.opening_balance_cutovers%rowtype;
  v_request_payload jsonb;
  v_request_hash text;
  v_existing_posted_cutover_id uuid;
  v_max_ledger_seq bigint;
  v_line record;
  v_master_found boolean;
  v_product_sku text;
  v_product_name text;
  v_product_active boolean;
  v_product_row_version bigint;
  v_batch_code text;
  v_batch_expiry date;
  v_batch_status text;
  v_batch_kind text;
  v_batch_row_version bigint;
  v_balance_found boolean;
  v_batch_sellable bigint;
  v_batch_quarantine bigint;
  v_batch_damaged bigint;
  v_balance_version bigint;
  v_balance_last_ledger_seq bigint;
  v_position_found boolean;
  v_product_sellable bigint;
  v_product_quarantine bigint;
  v_product_damaged bigint;
  v_product_reserved bigint;
  v_position_version bigint;
  v_position_last_ledger_seq bigint;
  v_batch_ledger_sellable bigint;
  v_batch_ledger_quarantine bigint;
  v_batch_ledger_damaged bigint;
  v_product_ledger_sellable bigint;
  v_product_ledger_quarantine bigint;
  v_product_ledger_damaged bigint;
  v_current_batch_bucket bigint;
  v_current_product_bucket bigint;
  v_lines jsonb := '[]'::jsonb;
  v_basis_lines jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_basis jsonb;
  v_basis_hash text;
  v_eligible boolean;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_cutover_id is null then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_ID_REQUIRED';
  end if;

  if v_jwt_role = 'anon'
     or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null
     and (
       not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id
     ) then
    raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  if p_lock_basis then
    select cutover.*
    into v_cutover
    from operations.opening_balance_cutovers cutover
    where cutover.organization_id = p_organization_id
      and cutover.id = p_cutover_id
    for update;
  else
    select cutover.*
    into v_cutover
    from operations.opening_balance_cutovers cutover
    where cutover.organization_id = p_organization_id
      and cutover.id = p_cutover_id;
  end if;

  if not found then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_NOT_FOUND';
  end if;

  if v_cutover.status_code <> 'REVIEW' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_NOT_IN_REVIEW';
  end if;

  v_request_payload := inventory.opening_balance_cutover_request_payload(
    p_organization_id,
    p_cutover_id
  );

  v_request_hash := encode(
    extensions.digest(convert_to(v_request_payload::text, 'UTF8'), 'sha256'),
    'hex'
  );

  if v_cutover.request_hash is distinct from v_request_hash then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'OPENING_BALANCE_REVIEW_PAYLOAD_CHANGED',
        'scope', 'CUTOVER',
        'message', 'Isi cutover berubah setelah masuk tahap review.'
      )
    );
  end if;

  select cutover.id
  into v_existing_posted_cutover_id
  from operations.opening_balance_cutovers cutover
  where cutover.organization_id = p_organization_id
    and cutover.status_code = 'POSTED'
    and cutover.id <> p_cutover_id
  order by cutover.posted_at, cutover.id
  limit 1;

  if found then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'OPENING_BALANCE_POSTED_CUTOVER_EXISTS',
        'scope', 'CUTOVER',
        'existingCutoverId', v_existing_posted_cutover_id,
        'message', 'Organisasi sudah memiliki cutover saldo awal yang diposting.'
      )
    );
  end if;

  select coalesce(max(entry.ledger_seq), 0)::bigint
  into v_max_ledger_seq
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  for v_line in
    select line.*
    from operations.opening_balance_cutover_lines line
    where line.organization_id = p_organization_id
      and line.cutover_id = p_cutover_id
    order by line.product_id, line.batch_id, line.bucket_code, line.line_no
  loop
    if p_lock_basis then
      perform pg_advisory_xact_lock(
        hashtextextended(
          p_organization_id::text
            || ':PRODUCT_STOCK:'
            || v_line.product_id::text,
          0::bigint
        )
      );
    end if;

    v_product_sku := null;
    v_product_name := null;
    v_product_active := null;
    v_product_row_version := null;
    v_batch_code := null;
    v_batch_expiry := null;
    v_batch_status := null;
    v_batch_kind := null;
    v_batch_row_version := null;

    if p_lock_basis then
      select
        product.sku,
        product.name,
        product.is_active,
        product.row_version,
        batch.batch_code,
        batch.expiry_date,
        batch.status_code,
        batch.batch_kind_code,
        batch.row_version
      into
        v_product_sku,
        v_product_name,
        v_product_active,
        v_product_row_version,
        v_batch_code,
        v_batch_expiry,
        v_batch_status,
        v_batch_kind,
        v_batch_row_version
      from catalog.products product
      join catalog.product_batches batch
        on batch.organization_id = product.organization_id
       and batch.product_id = product.id
      where product.organization_id = p_organization_id
        and product.id = v_line.product_id
        and batch.id = v_line.batch_id
      for update of product, batch;
    else
      select
        product.sku,
        product.name,
        product.is_active,
        product.row_version,
        batch.batch_code,
        batch.expiry_date,
        batch.status_code,
        batch.batch_kind_code,
        batch.row_version
      into
        v_product_sku,
        v_product_name,
        v_product_active,
        v_product_row_version,
        v_batch_code,
        v_batch_expiry,
        v_batch_status,
        v_batch_kind,
        v_batch_row_version
      from catalog.products product
      join catalog.product_batches batch
        on batch.organization_id = product.organization_id
       and batch.product_id = product.id
      where product.organization_id = p_organization_id
        and product.id = v_line.product_id
        and batch.id = v_line.batch_id;
    end if;

    v_master_found := found;

    v_batch_sellable := 0;
    v_batch_quarantine := 0;
    v_batch_damaged := 0;
    v_balance_version := 0;
    v_balance_last_ledger_seq := 0;

    if p_lock_basis then
      select
        balance.sellable_qty,
        balance.quarantine_qty,
        balance.damaged_qty,
        balance.version,
        balance.last_ledger_seq
      into
        v_batch_sellable,
        v_batch_quarantine,
        v_batch_damaged,
        v_balance_version,
        v_balance_last_ledger_seq
      from inventory.stock_batch_balances balance
      where balance.organization_id = p_organization_id
        and balance.product_id = v_line.product_id
        and balance.batch_id = v_line.batch_id
      for update;
    else
      select
        balance.sellable_qty,
        balance.quarantine_qty,
        balance.damaged_qty,
        balance.version,
        balance.last_ledger_seq
      into
        v_batch_sellable,
        v_batch_quarantine,
        v_batch_damaged,
        v_balance_version,
        v_balance_last_ledger_seq
      from inventory.stock_batch_balances balance
      where balance.organization_id = p_organization_id
        and balance.product_id = v_line.product_id
        and balance.batch_id = v_line.batch_id;
    end if;

    v_balance_found := found;
    v_batch_sellable := coalesce(v_batch_sellable, 0);
    v_batch_quarantine := coalesce(v_batch_quarantine, 0);
    v_batch_damaged := coalesce(v_batch_damaged, 0);
    v_balance_version := coalesce(v_balance_version, 0);
    v_balance_last_ledger_seq := coalesce(v_balance_last_ledger_seq, 0);

    v_product_sellable := 0;
    v_product_quarantine := 0;
    v_product_damaged := 0;
    v_product_reserved := 0;
    v_position_version := 0;
    v_position_last_ledger_seq := 0;

    if p_lock_basis then
      select
        position.sellable_qty,
        position.quarantine_qty,
        position.damaged_qty,
        position.reserved_qty,
        position.version,
        position.last_ledger_seq
      into
        v_product_sellable,
        v_product_quarantine,
        v_product_damaged,
        v_product_reserved,
        v_position_version,
        v_position_last_ledger_seq
      from inventory.stock_product_positions position
      where position.organization_id = p_organization_id
        and position.product_id = v_line.product_id
      for update;
    else
      select
        position.sellable_qty,
        position.quarantine_qty,
        position.damaged_qty,
        position.reserved_qty,
        position.version,
        position.last_ledger_seq
      into
        v_product_sellable,
        v_product_quarantine,
        v_product_damaged,
        v_product_reserved,
        v_position_version,
        v_position_last_ledger_seq
      from inventory.stock_product_positions position
      where position.organization_id = p_organization_id
        and position.product_id = v_line.product_id;
    end if;

    v_position_found := found;
    v_product_sellable := coalesce(v_product_sellable, 0);
    v_product_quarantine := coalesce(v_product_quarantine, 0);
    v_product_damaged := coalesce(v_product_damaged, 0);
    v_product_reserved := coalesce(v_product_reserved, 0);
    v_position_version := coalesce(v_position_version, 0);
    v_position_last_ledger_seq := coalesce(v_position_last_ledger_seq, 0);

    select
      coalesce(sum(entry.quantity_delta) filter (
        where entry.bucket_code = 'SELLABLE'
      ), 0)::bigint,
      coalesce(sum(entry.quantity_delta) filter (
        where entry.bucket_code = 'QUARANTINE'
      ), 0)::bigint,
      coalesce(sum(entry.quantity_delta) filter (
        where entry.bucket_code = 'DAMAGED'
      ), 0)::bigint
    into
      v_batch_ledger_sellable,
      v_batch_ledger_quarantine,
      v_batch_ledger_damaged
    from inventory.stock_ledger_entries entry
    where entry.organization_id = p_organization_id
      and entry.product_id = v_line.product_id
      and entry.batch_id = v_line.batch_id;

    select
      coalesce(sum(entry.quantity_delta) filter (
        where entry.bucket_code = 'SELLABLE'
      ), 0)::bigint,
      coalesce(sum(entry.quantity_delta) filter (
        where entry.bucket_code = 'QUARANTINE'
      ), 0)::bigint,
      coalesce(sum(entry.quantity_delta) filter (
        where entry.bucket_code = 'DAMAGED'
      ), 0)::bigint
    into
      v_product_ledger_sellable,
      v_product_ledger_quarantine,
      v_product_ledger_damaged
    from inventory.stock_ledger_entries entry
    where entry.organization_id = p_organization_id
      and entry.product_id = v_line.product_id;

    if not v_master_found then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'OPENING_BALANCE_LINE_MASTER_NOT_FOUND',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'productId', v_line.product_id,
          'batchId', v_line.batch_id,
          'message', 'Produk atau batch tidak ditemukan pada organisasi aktif.'
        )
      );
    else
      if not v_product_active then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'OPENING_BALANCE_PRODUCT_INACTIVE',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'message', 'Produk tidak aktif.'
          )
        );
      end if;

      if v_batch_status = 'ARCHIVED' then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'OPENING_BALANCE_BATCH_ARCHIVED',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'message', 'Batch archived tidak dapat menerima saldo awal.'
          )
        );
      end if;

      if v_line.product_sku_snapshot <> v_product_sku
         or v_line.product_name_snapshot <> v_product_name
         or v_line.batch_code_snapshot <> v_batch_code
         or v_line.expiry_date_snapshot <> v_batch_expiry
         or v_line.batch_status_code_snapshot <> v_batch_status
         or v_line.product_row_version_snapshot <> v_product_row_version
         or v_line.batch_row_version_snapshot <> v_batch_row_version then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'OPENING_BALANCE_MASTER_DATA_CHANGED',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'message', 'Produk atau batch berubah setelah draft disimpan.'
          )
        );
      end if;

      if not v_line.batch_identity_verified
         and (
           v_line.bucket_code <> 'QUARANTINE'
           or v_line.exception_reference is null
           or btrim(v_line.exception_reference) = ''
         ) then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'UNKNOWN_BATCH_NOT_QUARANTINED',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'message', 'Batch belum terverifikasi wajib ditempatkan di quarantine.'
          )
        );
      end if;

      if v_line.bucket_code = 'SELLABLE'
         and not v_line.batch_identity_verified then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'OPENING_BALANCE_SELLABLE_IDENTITY_REQUIRED',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'message', 'Saldo sellable memerlukan identitas batch terverifikasi.'
          )
        );
      end if;

      if v_line.bucket_code = 'SELLABLE'
         and v_batch_status <> 'ACTIVE' then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'OPENING_BALANCE_SELLABLE_BATCH_NOT_ACTIVE',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'message', 'Saldo sellable hanya dapat masuk ke batch aktif.'
          )
        );
      end if;

      if v_line.bucket_code = 'SELLABLE'
         and v_batch_expiry < v_cutover.effective_local_date then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'OPENING_BALANCE_SELLABLE_BATCH_EXPIRED',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'message', 'Batch kedaluwarsa tidak dapat menerima saldo sellable.'
          )
        );
      end if;

      if v_batch_kind = 'UNIDENTIFIED_RETURN'
         and (
           v_line.bucket_code <> 'QUARANTINE'
           or v_line.batch_identity_verified
         ) then
        v_blockers := v_blockers || jsonb_build_array(
          jsonb_build_object(
            'code', 'OPENING_BALANCE_UNIDENTIFIED_BATCH_SCOPE_INVALID',
            'scope', 'LINE',
            'lineNo', v_line.line_no,
            'message', 'Batch tanpa identitas hanya dapat dicatat sebagai quarantine exception.'
          )
        );
      end if;
    end if;

    if v_batch_sellable <> v_batch_ledger_sellable
       or v_batch_quarantine <> v_batch_ledger_quarantine
       or v_batch_damaged <> v_batch_ledger_damaged then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'OPENING_BALANCE_BATCH_PROJECTION_DRIFT',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Projection batch tidak sama dengan ledger.'
        )
      );
    end if;

    if v_product_sellable <> v_product_ledger_sellable
       or v_product_quarantine <> v_product_ledger_quarantine
       or v_product_damaged <> v_product_ledger_damaged then
      v_blockers := v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'OPENING_BALANCE_PRODUCT_PROJECTION_DRIFT',
          'scope', 'LINE',
          'lineNo', v_line.line_no,
          'message', 'Projection produk tidak sama dengan ledger.'
        )
      );
    end if;

    v_current_batch_bucket := case v_line.bucket_code
      when 'SELLABLE' then v_batch_sellable
      when 'QUARANTINE' then v_batch_quarantine
      when 'DAMAGED' then v_batch_damaged
    end;

    v_current_product_bucket := case v_line.bucket_code
      when 'SELLABLE' then v_product_sellable
      when 'QUARANTINE' then v_product_quarantine
      when 'DAMAGED' then v_product_damaged
    end;

    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'lineNo', v_line.line_no,
        'openingBalanceLineId', v_line.id,
        'productId', v_line.product_id,
        'productSku', coalesce(v_product_sku, v_line.product_sku_snapshot),
        'productName', coalesce(v_product_name, v_line.product_name_snapshot),
        'batchId', v_line.batch_id,
        'batchCode', coalesce(v_batch_code, v_line.batch_code_snapshot),
        'expiryDate', coalesce(v_batch_expiry, v_line.expiry_date_snapshot),
        'batchStatusCode', coalesce(v_batch_status, v_line.batch_status_code_snapshot),
        'bucketCode', v_line.bucket_code,
        'quantity', v_line.quantity,
        'batchIdentityVerified', v_line.batch_identity_verified,
        'exceptionReference', v_line.exception_reference,
        'sourceLineRef', v_line.source_line_ref,
        'currentBatchBucketQty', v_current_batch_bucket,
        'resultingBatchBucketQty', v_current_batch_bucket + v_line.quantity,
        'currentProductBucketQty', v_current_product_bucket,
        'resultingProductBucketQty', v_current_product_bucket + v_line.quantity,
        'reservedQty', v_product_reserved,
        'verificationStatusCode',
          case when v_line.quantity > 0 then 'UNVERIFIED' else 'NOT_APPLICABLE' end
      )
    );

    v_basis_lines := v_basis_lines || jsonb_build_array(
      jsonb_build_object(
        'lineNo', v_line.line_no,
        'productId', v_line.product_id,
        'batchId', v_line.batch_id,
        'bucketCode', v_line.bucket_code,
        'quantity', v_line.quantity,
        'productFound', v_master_found,
        'productRowVersion', v_product_row_version,
        'batchRowVersion', v_batch_row_version,
        'batchStatusCode', v_batch_status,
        'batchKindCode', v_batch_kind,
        'balanceFound', v_balance_found,
        'batchSellableQty', v_batch_sellable,
        'batchQuarantineQty', v_batch_quarantine,
        'batchDamagedQty', v_batch_damaged,
        'batchBalanceVersion', v_balance_version,
        'batchLastLedgerSeq', v_balance_last_ledger_seq,
        'positionFound', v_position_found,
        'productSellableQty', v_product_sellable,
        'productQuarantineQty', v_product_quarantine,
        'productDamagedQty', v_product_damaged,
        'productReservedQty', v_product_reserved,
        'productPositionVersion', v_position_version,
        'productLastLedgerSeq', v_position_last_ledger_seq,
        'batchLedgerSellableQty', v_batch_ledger_sellable,
        'batchLedgerQuarantineQty', v_batch_ledger_quarantine,
        'batchLedgerDamagedQty', v_batch_ledger_damaged,
        'productLedgerSellableQty', v_product_ledger_sellable,
        'productLedgerQuarantineQty', v_product_ledger_quarantine,
        'productLedgerDamagedQty', v_product_ledger_damaged
      )
    );
  end loop;

  if v_cutover.line_count = 0 then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'OPENING_BALANCE_LINES_REQUIRED',
        'scope', 'CUTOVER',
        'message', 'Cutover belum memiliki baris saldo awal.'
      )
    );
  end if;

  v_basis := jsonb_build_object(
    'organizationId', p_organization_id,
    'cutoverId', p_cutover_id,
    'cutoverStatus', v_cutover.status_code,
    'cutoverRowVersion', v_cutover.row_version,
    'requestHash', v_request_hash,
    'storedRequestHash', v_cutover.request_hash,
    'currentMaxLedgerSeq', v_max_ledger_seq,
    'existingPostedCutoverId', v_existing_posted_cutover_id,
    'lines', v_basis_lines,
    'schemaVersion', 1
  );

  v_basis_hash := encode(
    extensions.digest(convert_to(v_basis::text, 'UTF8'), 'sha256'),
    'hex'
  );

  v_eligible := jsonb_array_length(v_blockers) = 0;

  return jsonb_build_object(
    'status', case when v_eligible then 'PREVIEW_READY' else 'BLOCKED' end,
    'eligible', v_eligible,
    'schemaVersion', 1,
    'organizationId', p_organization_id,
    'cutoverId', p_cutover_id,
    'cutoverNo', v_cutover.cutover_no,
    'sourceRef', v_cutover.source_ref,
    'sourceEstimateRef', v_cutover.source_estimate_ref,
    'cutoverAt', v_cutover.cutover_at,
    'effectiveLocalDate', v_cutover.effective_local_date,
    'requestHash', v_request_hash,
    'basisHash', v_basis_hash,
    'lineCount', v_cutover.line_count,
    'positiveLineCount', v_cutover.positive_line_count,
    'totalQuantity', v_cutover.total_quantity,
    'note', v_cutover.note,
    'metadata', v_cutover.metadata,
    'lines', v_lines,
    'blockers', v_blockers
  );
end;
$$;

revoke all on function inventory.preview_opening_balance_cutover_core(uuid, uuid, boolean)
from public, anon, authenticated, service_role;

create or replace function api.create_opening_balance_cutover(
  p_organization_id uuid,
  p_source_ref text,
  p_cutover_at timestamptz,
  p_source_estimate_ref text,
  p_note text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, inventory, operations
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text :=
    coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_process_name text;
  v_source_ref text;
  v_source_estimate_ref text;
  v_note text;
  v_metadata jsonb;
  v_timezone text;
  v_effective_local_date date;
  v_cutover_id uuid := gen_random_uuid();
  v_cutover_no text;
  v_now timestamptz := clock_timestamp();
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  v_source_ref := btrim(coalesce(p_source_ref, ''));
  if v_source_ref = '' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_SOURCE_REQUIRED';
  end if;
  if length(v_source_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_SOURCE_TOO_LONG';
  end if;

  if p_cutover_at is null then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_AT_REQUIRED';
  end if;

  v_source_estimate_ref := btrim(coalesce(p_source_estimate_ref, ''));
  if v_source_estimate_ref = '' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_ESTIMATE_REFERENCE_REQUIRED';
  end if;
  if length(v_source_estimate_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_ESTIMATE_REFERENCE_TOO_LONG';
  end if;

  v_note := btrim(coalesce(p_note, ''));
  if v_note = '' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_NOTE_REQUIRED';
  end if;
  if length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_NOTE_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_METADATA_MUST_BE_OBJECT';
  end if;

  select organization.timezone
  into v_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_NOT_FOUND';
  end if;

  if v_jwt_role = 'anon'
     or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id then
      raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
    end if;
    v_process_name := null;
  else
    v_process_name := 'api.create_opening_balance_cutover';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':OPENING_BALANCE_SOURCE:' || v_source_ref,
      0::bigint
    )
  );

  if exists (
    select 1
    from operations.opening_balance_cutovers cutover
    where cutover.organization_id = p_organization_id
      and cutover.source_ref = v_source_ref
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_SOURCE_ALREADY_EXISTS';
  end if;

  v_effective_local_date := (p_cutover_at at time zone v_timezone)::date;
  v_cutover_no :=
    'CUT-' || to_char(v_effective_local_date, 'YYYYMMDD') || '-'
    || upper(substr(replace(v_cutover_id::text, '-', ''), 1, 8));

  insert into operations.opening_balance_cutovers (
    id,
    organization_id,
    cutover_no,
    source_ref,
    source_estimate_ref,
    status_code,
    cutover_at,
    effective_local_date,
    created_at,
    updated_at,
    created_by,
    create_process_name,
    note,
    metadata,
    row_version
  ) values (
    v_cutover_id,
    p_organization_id,
    v_cutover_no,
    v_source_ref,
    v_source_estimate_ref,
    'DRAFT',
    p_cutover_at,
    v_effective_local_date,
    v_now,
    v_now,
    v_actor_user_id,
    v_process_name,
    v_note,
    v_metadata,
    1
  );

  return jsonb_build_object(
    'status', 'DRAFT',
    'cutoverId', v_cutover_id,
    'cutoverNo', v_cutover_no,
    'sourceRef', v_source_ref,
    'cutoverAt', p_cutover_at,
    'effectiveLocalDate', v_effective_local_date,
    'rowVersion', 1
  );
end;
$$;

create or replace function api.save_opening_balance_cutover_draft(
  p_organization_id uuid,
  p_cutover_id uuid,
  p_expected_row_version bigint,
  p_cutover_at timestamptz,
  p_source_estimate_ref text,
  p_note text,
  p_lines jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text :=
    coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_cutover operations.opening_balance_cutovers%rowtype;
  v_source_estimate_ref text;
  v_note text;
  v_metadata jsonb;
  v_timezone text;
  v_effective_local_date date;
  v_line record;
  v_product_sku text;
  v_product_name text;
  v_product_active boolean;
  v_product_row_version bigint;
  v_batch_code text;
  v_batch_expiry date;
  v_batch_status text;
  v_batch_row_version bigint;
  v_batch_identity_verified boolean;
  v_exception_reference text;
  v_line_count bigint;
  v_positive_line_count bigint;
  v_total_quantity bigint;
  v_new_version bigint;
  v_now timestamptz := clock_timestamp();
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;
  if p_cutover_id is null then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_ID_REQUIRED';
  end if;
  if p_expected_row_version is null or p_expected_row_version <= 0 then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_VERSION_REQUIRED';
  end if;
  if p_cutover_at is null then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_AT_REQUIRED';
  end if;

  v_source_estimate_ref := btrim(coalesce(p_source_estimate_ref, ''));
  if v_source_estimate_ref = '' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_ESTIMATE_REFERENCE_REQUIRED';
  end if;
  if length(v_source_estimate_ref) > 200 then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_ESTIMATE_REFERENCE_TOO_LONG';
  end if;

  v_note := btrim(coalesce(p_note, ''));
  if v_note = '' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_NOTE_REQUIRED';
  end if;
  if length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_NOTE_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_METADATA_MUST_BE_OBJECT';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_LINES_MUST_BE_ARRAY';
  end if;
  if jsonb_array_length(p_lines) > 500 then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_LINES_LIMIT_EXCEEDED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'productId') is distinct from 'string'
       or (item.value ->> 'productId')
            !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'batchId') is distinct from 'string'
       or (item.value ->> 'batchId')
            !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item.value -> 'bucketCode') is distinct from 'string'
       or upper(btrim(item.value ->> 'bucketCode'))
            not in ('SELLABLE', 'QUARANTINE', 'DAMAGED')
       or jsonb_typeof(item.value -> 'quantity') is distinct from 'number'
       or (item.value ->> 'quantity') !~ '^(0|[1-9][0-9]{0,8})$'
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 100
       or (
         item.value ? 'batchIdentityVerified'
         and jsonb_typeof(item.value -> 'batchIdentityVerified') <> 'boolean'
       )
       or (
         item.value ? 'exceptionReference'
         and jsonb_typeof(item.value -> 'exceptionReference')
               not in ('string', 'null')
       )
  ) then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_LINE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by
      lower(item.value ->> 'productId'),
      lower(item.value ->> 'batchId'),
      upper(btrim(item.value ->> 'bucketCode'))
    having count(*) > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_DUPLICATE_BATCH_BUCKET_LINE';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    group by btrim(item.value ->> 'sourceLineRef')
    having count(*) > 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_DUPLICATE_SOURCE_LINE';
  end if;

  if v_jwt_role = 'anon'
     or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null
     and (
       not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id
     ) then
    raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  select organization.timezone
  into v_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_NOT_FOUND';
  end if;

  select cutover.*
  into v_cutover
  from operations.opening_balance_cutovers cutover
  where cutover.organization_id = p_organization_id
    and cutover.id = p_cutover_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_NOT_FOUND';
  end if;

  if v_cutover.status_code <> 'DRAFT' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_DRAFT_NOT_EDITABLE';
  end if;

  if v_cutover.row_version <> p_expected_row_version then
    raise exception using errcode = 'P0001', message = 'STALE_OPENING_BALANCE_DRAFT';
  end if;

  v_effective_local_date := (p_cutover_at at time zone v_timezone)::date;

  delete from operations.opening_balance_cutover_lines line
  where line.organization_id = p_organization_id
    and line.cutover_id = p_cutover_id;

  for v_line in
    select
      item.ordinality::integer as line_no,
      (item.value ->> 'productId')::uuid as product_id,
      (item.value ->> 'batchId')::uuid as batch_id,
      upper(btrim(item.value ->> 'bucketCode')) as bucket_code,
      (item.value ->> 'quantity')::bigint as quantity,
      coalesce((item.value ->> 'batchIdentityVerified')::boolean, true)
        as batch_identity_verified,
      nullif(btrim(coalesce(item.value ->> 'exceptionReference', '')), '')
        as exception_reference,
      btrim(item.value ->> 'sourceLineRef') as source_line_ref
    from jsonb_array_elements(p_lines) with ordinality item(value, ordinality)
    order by item.ordinality
  loop
    v_batch_identity_verified := v_line.batch_identity_verified;
    v_exception_reference := v_line.exception_reference;

    if not v_batch_identity_verified
       and (
         v_line.bucket_code <> 'QUARANTINE'
         or v_exception_reference is null
       ) then
      raise exception using
        errcode = 'P0001',
        message = 'UNKNOWN_BATCH_NOT_QUARANTINED';
    end if;

    if v_batch_identity_verified and v_exception_reference is not null then
      raise exception using
        errcode = 'P0001',
        message = 'OPENING_BALANCE_VERIFIED_BATCH_EXCEPTION_FORBIDDEN';
    end if;

    if v_exception_reference is not null
       and length(v_exception_reference) > 200 then
      raise exception using
        errcode = 'P0001',
        message = 'OPENING_BALANCE_EXCEPTION_REFERENCE_TOO_LONG';
    end if;

    select
      product.sku,
      product.name,
      product.is_active,
      product.row_version,
      batch.batch_code,
      batch.expiry_date,
      batch.status_code,
      batch.row_version
    into
      v_product_sku,
      v_product_name,
      v_product_active,
      v_product_row_version,
      v_batch_code,
      v_batch_expiry,
      v_batch_status,
      v_batch_row_version
    from catalog.products product
    join catalog.product_batches batch
      on batch.organization_id = product.organization_id
     and batch.product_id = product.id
    where product.organization_id = p_organization_id
      and product.id = v_line.product_id
      and batch.id = v_line.batch_id
    for update of product, batch;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'OPENING_BALANCE_LINE_MASTER_NOT_FOUND';
    end if;

    if not v_product_active then
      raise exception using
        errcode = 'P0001',
        message = 'OPENING_BALANCE_PRODUCT_INACTIVE';
    end if;

    if v_batch_status = 'ARCHIVED' then
      raise exception using
        errcode = 'P0001',
        message = 'OPENING_BALANCE_BATCH_ARCHIVED';
    end if;

    insert into operations.opening_balance_cutover_lines (
      organization_id,
      cutover_id,
      line_no,
      product_id,
      batch_id,
      bucket_code,
      quantity,
      batch_identity_verified,
      exception_reference,
      product_sku_snapshot,
      product_name_snapshot,
      batch_code_snapshot,
      expiry_date_snapshot,
      batch_status_code_snapshot,
      product_row_version_snapshot,
      batch_row_version_snapshot,
      source_line_ref,
      created_at,
      updated_at
    ) values (
      p_organization_id,
      p_cutover_id,
      v_line.line_no,
      v_line.product_id,
      v_line.batch_id,
      v_line.bucket_code,
      v_line.quantity,
      v_batch_identity_verified,
      v_exception_reference,
      v_product_sku,
      v_product_name,
      v_batch_code,
      v_batch_expiry,
      v_batch_status,
      v_product_row_version,
      v_batch_row_version,
      v_line.source_line_ref,
      v_now,
      v_now
    );
  end loop;

  select
    count(*),
    count(*) filter (where line.quantity > 0),
    coalesce(sum(line.quantity), 0)::bigint
  into
    v_line_count,
    v_positive_line_count,
    v_total_quantity
  from operations.opening_balance_cutover_lines line
  where line.organization_id = p_organization_id
    and line.cutover_id = p_cutover_id;

  update operations.opening_balance_cutovers cutover
  set
    cutover_at = p_cutover_at,
    effective_local_date = v_effective_local_date,
    source_estimate_ref = v_source_estimate_ref,
    note = v_note,
    metadata = v_metadata,
    line_count = v_line_count,
    positive_line_count = v_positive_line_count,
    total_quantity = v_total_quantity,
    updated_at = v_now,
    row_version = cutover.row_version + 1
  where cutover.organization_id = p_organization_id
    and cutover.id = p_cutover_id
  returning cutover.row_version into v_new_version;

  return jsonb_build_object(
    'status', 'DRAFT',
    'cutoverId', p_cutover_id,
    'rowVersion', v_new_version,
    'lineCount', v_line_count,
    'positiveLineCount', v_positive_line_count,
    'totalQuantity', v_total_quantity,
    'effectiveLocalDate', v_effective_local_date
  );
end;
$$;

create or replace function api.submit_opening_balance_cutover_review(
  p_organization_id uuid,
  p_cutover_id uuid,
  p_expected_row_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, inventory, operations, extensions
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text :=
    coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_process_name text;
  v_cutover operations.opening_balance_cutovers%rowtype;
  v_request_payload jsonb;
  v_request_hash text;
  v_now timestamptz := clock_timestamp();
  v_new_version bigint;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;
  if p_cutover_id is null then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_ID_REQUIRED';
  end if;
  if p_expected_row_version is null or p_expected_row_version <= 0 then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_VERSION_REQUIRED';
  end if;

  if v_jwt_role = 'anon'
     or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id then
      raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
    end if;
    v_process_name := null;
  else
    v_process_name := 'api.submit_opening_balance_cutover_review';
  end if;

  select cutover.*
  into v_cutover
  from operations.opening_balance_cutovers cutover
  where cutover.organization_id = p_organization_id
    and cutover.id = p_cutover_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_NOT_FOUND';
  end if;

  if v_cutover.status_code <> 'DRAFT' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_NOT_DRAFT';
  end if;

  if v_cutover.row_version <> p_expected_row_version then
    raise exception using errcode = 'P0001', message = 'STALE_OPENING_BALANCE_DRAFT';
  end if;

  if v_cutover.line_count = 0 then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_LINES_REQUIRED';
  end if;

  v_request_payload := inventory.opening_balance_cutover_request_payload(
    p_organization_id,
    p_cutover_id
  );

  v_request_hash := encode(
    extensions.digest(convert_to(v_request_payload::text, 'UTF8'), 'sha256'),
    'hex'
  );

  update operations.opening_balance_cutovers cutover
  set
    status_code = 'REVIEW',
    request_hash = v_request_hash,
    reviewed_at = v_now,
    reviewed_by = v_actor_user_id,
    review_process_name = v_process_name,
    updated_at = v_now,
    row_version = cutover.row_version + 1
  where cutover.organization_id = p_organization_id
    and cutover.id = p_cutover_id
  returning cutover.row_version into v_new_version;

  return jsonb_build_object(
    'status', 'REVIEW',
    'cutoverId', p_cutover_id,
    'requestHash', v_request_hash,
    'rowVersion', v_new_version,
    'lineCount', v_cutover.line_count,
    'positiveLineCount', v_cutover.positive_line_count,
    'totalQuantity', v_cutover.total_quantity
  );
end;
$$;

create or replace function api.preview_opening_balance_cutover(
  p_organization_id uuid,
  p_cutover_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
begin
  return inventory.preview_opening_balance_cutover_core(
    p_organization_id,
    p_cutover_id,
    false
  );
end;
$$;

create or replace function api.post_opening_balance_cutover(
  p_organization_id uuid,
  p_idempotency_key text,
  p_cutover_id uuid,
  p_preview_basis_hash text,
  p_confirmation boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_scope constant text := 'POST_OPENING_BALANCE';
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text :=
    coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_process_name text;
  v_created_by_role_code text;
  v_idempotency_key text;
  v_expected_basis_hash text;
  v_cutover operations.opening_balance_cutovers%rowtype;
  v_command_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_preview jsonb;
  v_actual_basis_hash text;
  v_reason_id uuid;
  v_channel_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_transaction_id uuid := gen_random_uuid();
  v_correlation_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_ledger_seq_before bigint;
  v_ledger_seq_after bigint;
  v_line record;
  v_ledger_entry_id uuid;
  v_ledger_seq bigint;
  v_batch_sellable bigint;
  v_batch_quarantine bigint;
  v_batch_damaged bigint;
  v_product_sellable bigint;
  v_product_quarantine bigint;
  v_product_damaged bigint;
  v_batch_before bigint;
  v_product_before bigint;
  v_result_lines jsonb;
  v_response jsonb;
begin
  if p_confirmation is distinct from true then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CONFIRMATION_REQUIRED';
  end if;

  v_expected_basis_hash := lower(btrim(coalesce(p_preview_basis_hash, '')));
  if v_expected_basis_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_PREVIEW_HASH_INVALID';
  end if;

  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;
  if p_cutover_id is null then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_ID_REQUIRED';
  end if;

  if v_jwt_role = 'anon'
     or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id() is distinct from p_organization_id then
      raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
    end if;
    v_process_name := null;
    v_created_by_role_code := 'ADMIN';
  else
    v_process_name := 'api.post_opening_balance_cutover';
    v_created_by_role_code := 'SYSTEM_PROCESS';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':OPENING_BALANCE_POST',
      0::bigint
    )
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':' || v_scope || ':' || v_idempotency_key,
      0::bigint
    )
  );

  select cutover.*
  into v_cutover
  from operations.opening_balance_cutovers cutover
  where cutover.organization_id = p_organization_id
    and cutover.id = p_cutover_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_NOT_FOUND';
  end if;

  v_command_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'cutoverId', p_cutover_id,
          'cutoverRequestHash', v_cutover.request_hash,
          'previewBasisHash', v_expected_basis_hash,
          'schemaVersion', 1
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select command.*
  into v_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id
    and command.scope = v_scope
    and command.key = v_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> v_command_request_hash then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REUSED';
    end if;

    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot;
    end if;

    if v_existing.status_code = 'STARTED' then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;

    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  if v_cutover.status_code <> 'REVIEW' then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_CUTOVER_NOT_IN_REVIEW';
  end if;

  v_preview := inventory.preview_opening_balance_cutover_core(
    p_organization_id,
    p_cutover_id,
    true
  );

  v_actual_basis_hash := lower(v_preview ->> 'basisHash');
  if v_actual_basis_hash is distinct from v_expected_basis_hash then
    raise exception using errcode = 'P0001', message = 'STALE_OPENING_BALANCE_PREVIEW';
  end if;

  if coalesce((v_preview ->> 'eligible')::boolean, false) is not true then
    raise exception using errcode = 'P0001', message = 'OPENING_BALANCE_PREVIEW_BLOCKED';
  end if;

  select reason.id
  into v_reason_id
  from catalog.movement_reasons reason
  where reason.code = 'INITIAL_BALANCE'
    and reason.is_active
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REASON_NOT_CONFIGURED';
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = 'MANUAL'
    and channel.is_active
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CHANNEL_NOT_CONFIGURED';
  end if;

  select coalesce(max(entry.ledger_seq), 0)::bigint
  into v_ledger_seq_before
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  insert into inventory.idempotency_commands (
    id,
    organization_id,
    scope,
    key,
    request_hash,
    status_code,
    started_at,
    completed_at,
    result_transaction_id,
    response_snapshot,
    error_code,
    expires_at
  ) values (
    v_command_id,
    p_organization_id,
    v_scope,
    v_idempotency_key,
    v_command_request_hash,
    'STARTED',
    v_recorded_at,
    null,
    null,
    '{}'::jsonb,
    null,
    null
  );

  insert into inventory.stock_transactions (
    id,
    organization_id,
    transaction_no,
    transaction_type_code,
    reason_id,
    reason_code_snapshot,
    channel_id,
    channel_code_snapshot,
    source_type_code,
    source_id,
    source_ref_snapshot,
    occurred_at,
    recorded_at,
    effective_local_date,
    actor_user_id,
    process_name,
    created_by_role_code,
    correlation_id,
    idempotency_command_id,
    reversal_of_transaction_id,
    note,
    metadata,
    schema_version
  ) values (
    v_transaction_id,
    p_organization_id,
    v_cutover.cutover_no,
    'INITIAL_BALANCE',
    v_reason_id,
    'INITIAL_BALANCE',
    v_channel_id,
    'MANUAL',
    'OPENING_BALANCE_CUTOVER',
    p_cutover_id,
    v_cutover.source_ref,
    v_cutover.cutover_at,
    v_recorded_at,
    v_cutover.effective_local_date,
    v_actor_user_id,
    v_process_name,
    v_created_by_role_code,
    v_correlation_id,
    v_command_id,
    null,
    v_cutover.note,
    v_cutover.metadata || jsonb_build_object(
      'cutoverId', p_cutover_id,
      'cutoverNo', v_cutover.cutover_no,
      'sourceEstimateRef', v_cutover.source_estimate_ref,
      'previewBasisHash', v_expected_basis_hash
    ),
    1
  );

  for v_line in
    select line.*
    from operations.opening_balance_cutover_lines line
    where line.organization_id = p_organization_id
      and line.cutover_id = p_cutover_id
    order by line.line_no
  loop
    select
      coalesce(balance.sellable_qty, 0),
      coalesce(balance.quarantine_qty, 0),
      coalesce(balance.damaged_qty, 0)
    into
      v_batch_sellable,
      v_batch_quarantine,
      v_batch_damaged
    from (select 1) seed
    left join inventory.stock_batch_balances balance
      on balance.organization_id = p_organization_id
     and balance.product_id = v_line.product_id
     and balance.batch_id = v_line.batch_id;

    select
      coalesce(position.sellable_qty, 0),
      coalesce(position.quarantine_qty, 0),
      coalesce(position.damaged_qty, 0)
    into
      v_product_sellable,
      v_product_quarantine,
      v_product_damaged
    from (select 1) seed
    left join inventory.stock_product_positions position
      on position.organization_id = p_organization_id
     and position.product_id = v_line.product_id;

    v_batch_before := case v_line.bucket_code
      when 'SELLABLE' then v_batch_sellable
      when 'QUARANTINE' then v_batch_quarantine
      when 'DAMAGED' then v_batch_damaged
    end;

    v_product_before := case v_line.bucket_code
      when 'SELLABLE' then v_product_sellable
      when 'QUARANTINE' then v_product_quarantine
      when 'DAMAGED' then v_product_damaged
    end;

    v_ledger_entry_id := null;

    if v_line.quantity > 0 then
      insert into inventory.stock_ledger_entries (
        organization_id,
        transaction_id,
        line_no,
        product_id,
        batch_id,
        product_sku_snapshot,
        batch_code_snapshot,
        expiry_date_snapshot,
        bucket_code,
        quantity_delta,
        entry_role_code,
        pair_no,
        source_line_ref,
        occurred_at,
        recorded_at,
        created_at
      ) values (
        p_organization_id,
        v_transaction_id,
        v_line.line_no,
        v_line.product_id,
        v_line.batch_id,
        v_line.product_sku_snapshot,
        v_line.batch_code_snapshot,
        v_line.expiry_date_snapshot,
        v_line.bucket_code,
        v_line.quantity,
        'ADJUSTMENT',
        null,
        v_line.source_line_ref,
        v_cutover.cutover_at,
        v_recorded_at,
        v_recorded_at
      )
      returning id, ledger_seq into v_ledger_entry_id, v_ledger_seq;

      insert into inventory.stock_batch_balances as current_balance (
        organization_id,
        batch_id,
        product_id,
        sellable_qty,
        quarantine_qty,
        damaged_qty,
        last_ledger_seq,
        updated_at,
        version
      ) values (
        p_organization_id,
        v_line.batch_id,
        v_line.product_id,
        case when v_line.bucket_code = 'SELLABLE' then v_line.quantity else 0 end,
        case when v_line.bucket_code = 'QUARANTINE' then v_line.quantity else 0 end,
        case when v_line.bucket_code = 'DAMAGED' then v_line.quantity else 0 end,
        v_ledger_seq,
        v_recorded_at,
        1
      )
      on conflict (organization_id, batch_id) do update
      set
        product_id = excluded.product_id,
        sellable_qty = current_balance.sellable_qty + excluded.sellable_qty,
        quarantine_qty = current_balance.quarantine_qty + excluded.quarantine_qty,
        damaged_qty = current_balance.damaged_qty + excluded.damaged_qty,
        last_ledger_seq = greatest(current_balance.last_ledger_seq, excluded.last_ledger_seq),
        updated_at = excluded.updated_at,
        version = current_balance.version + 1;

      insert into inventory.stock_product_positions as current_position (
        organization_id,
        product_id,
        sellable_qty,
        quarantine_qty,
        damaged_qty,
        reserved_qty,
        last_ledger_seq,
        updated_at,
        version
      ) values (
        p_organization_id,
        v_line.product_id,
        case when v_line.bucket_code = 'SELLABLE' then v_line.quantity else 0 end,
        case when v_line.bucket_code = 'QUARANTINE' then v_line.quantity else 0 end,
        case when v_line.bucket_code = 'DAMAGED' then v_line.quantity else 0 end,
        0,
        v_ledger_seq,
        v_recorded_at,
        1
      )
      on conflict (organization_id, product_id) do update
      set
        sellable_qty = current_position.sellable_qty + excluded.sellable_qty,
        quarantine_qty = current_position.quarantine_qty + excluded.quarantine_qty,
        damaged_qty = current_position.damaged_qty + excluded.damaged_qty,
        last_ledger_seq = greatest(current_position.last_ledger_seq, excluded.last_ledger_seq),
        updated_at = excluded.updated_at,
        version = current_position.version + 1;
    end if;

    update operations.opening_balance_cutover_lines line
    set
      ledger_entry_id = v_ledger_entry_id,
      batch_bucket_qty_before = v_batch_before,
      batch_bucket_qty_after = v_batch_before + v_line.quantity,
      product_bucket_qty_before = v_product_before,
      product_bucket_qty_after = v_product_before + v_line.quantity,
      updated_at = v_recorded_at
    where line.organization_id = p_organization_id
      and line.id = v_line.id;
  end loop;

  if exists (
    with affected as (
      select distinct line.product_id, line.batch_id
      from operations.opening_balance_cutover_lines line
      where line.organization_id = p_organization_id
        and line.cutover_id = p_cutover_id
        and line.quantity > 0
    ),
    ledger as (
      select
        affected.product_id,
        affected.batch_id,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'SELLABLE'
        ), 0)::bigint as sellable_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'QUARANTINE'
        ), 0)::bigint as quarantine_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'DAMAGED'
        ), 0)::bigint as damaged_qty
      from affected
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = p_organization_id
       and entry.product_id = affected.product_id
       and entry.batch_id = affected.batch_id
      group by affected.product_id, affected.batch_id
    )
    select 1
    from ledger
    left join inventory.stock_batch_balances balance
      on balance.organization_id = p_organization_id
     and balance.product_id = ledger.product_id
     and balance.batch_id = ledger.batch_id
    where balance.batch_id is null
       or balance.sellable_qty <> ledger.sellable_qty
       or balance.quarantine_qty <> ledger.quarantine_qty
       or balance.damaged_qty <> ledger.damaged_qty
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_BATCH_PROJECTION_DRIFT';
  end if;

  if exists (
    with affected as (
      select distinct line.product_id
      from operations.opening_balance_cutover_lines line
      where line.organization_id = p_organization_id
        and line.cutover_id = p_cutover_id
        and line.quantity > 0
    ),
    ledger as (
      select
        affected.product_id,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'SELLABLE'
        ), 0)::bigint as sellable_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'QUARANTINE'
        ), 0)::bigint as quarantine_qty,
        coalesce(sum(entry.quantity_delta) filter (
          where entry.bucket_code = 'DAMAGED'
        ), 0)::bigint as damaged_qty
      from affected
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = p_organization_id
       and entry.product_id = affected.product_id
      group by affected.product_id
    )
    select 1
    from ledger
    left join inventory.stock_product_positions position
      on position.organization_id = p_organization_id
     and position.product_id = ledger.product_id
    where position.product_id is null
       or position.sellable_qty <> ledger.sellable_qty
       or position.quarantine_qty <> ledger.quarantine_qty
       or position.damaged_qty <> ledger.damaged_qty
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_PRODUCT_PROJECTION_DRIFT';
  end if;

  select coalesce(max(entry.ledger_seq), 0)::bigint
  into v_ledger_seq_after
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  update operations.opening_balance_cutovers cutover
  set
    status_code = 'POSTED',
    posted_at = v_recorded_at,
    posted_by = v_actor_user_id,
    post_process_name = v_process_name,
    transaction_id = v_transaction_id,
    idempotency_command_id = v_command_id,
    posted_basis_hash = v_expected_basis_hash,
    ledger_seq_before = v_ledger_seq_before,
    ledger_seq_after = v_ledger_seq_after,
    updated_at = v_recorded_at,
    row_version = cutover.row_version + 1
  where cutover.organization_id = p_organization_id
    and cutover.id = p_cutover_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'lineNo', line.line_no,
        'openingBalanceLineId', line.id,
        'productId', line.product_id,
        'productSku', line.product_sku_snapshot,
        'batchId', line.batch_id,
        'batchCode', line.batch_code_snapshot,
        'bucketCode', line.bucket_code,
        'quantity', line.quantity,
        'ledgerEntryId', line.ledger_entry_id,
        'batchBucketQtyBefore', line.batch_bucket_qty_before,
        'batchBucketQtyAfter', line.batch_bucket_qty_after,
        'productBucketQtyBefore', line.product_bucket_qty_before,
        'productBucketQtyAfter', line.product_bucket_qty_after,
        'verificationStatusCode',
          case when line.quantity > 0 then 'UNVERIFIED' else 'NOT_APPLICABLE' end
      )
      order by line.line_no
    ),
    '[]'::jsonb
  )
  into v_result_lines
  from operations.opening_balance_cutover_lines line
  where line.organization_id = p_organization_id
    and line.cutover_id = p_cutover_id;

  v_response := jsonb_build_object(
    'status', 'POSTED',
    'cutoverId', p_cutover_id,
    'cutoverNo', v_cutover.cutover_no,
    'transactionId', v_transaction_id,
    'transactionNo', v_cutover.cutover_no,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_cutover.request_hash,
    'previewBasisHash', v_expected_basis_hash,
    'sourceRef', v_cutover.source_ref,
    'sourceEstimateRef', v_cutover.source_estimate_ref,
    'cutoverAt', v_cutover.cutover_at,
    'recordedAt', v_recorded_at,
    'ledgerSeqBefore', v_ledger_seq_before,
    'ledgerSeqAfter', v_ledger_seq_after,
    'lineCount', v_cutover.line_count,
    'positiveLineCount', v_cutover.positive_line_count,
    'totalQuantity', v_cutover.total_quantity,
    'verificationStatusCode',
      case
        when v_cutover.positive_line_count > 0 then 'UNVERIFIED'
        else 'NOT_APPLICABLE'
      end,
    'lines', v_result_lines
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    result_transaction_id = v_transaction_id,
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

revoke all on function api.create_opening_balance_cutover(
  uuid, text, timestamptz, text, text, jsonb
) from public, anon;

grant execute on function api.create_opening_balance_cutover(
  uuid, text, timestamptz, text, text, jsonb
) to authenticated, service_role;

revoke all on function api.save_opening_balance_cutover_draft(
  uuid, uuid, bigint, timestamptz, text, text, jsonb, jsonb
) from public, anon;

grant execute on function api.save_opening_balance_cutover_draft(
  uuid, uuid, bigint, timestamptz, text, text, jsonb, jsonb
) to authenticated, service_role;

revoke all on function api.submit_opening_balance_cutover_review(
  uuid, uuid, bigint
) from public, anon;

grant execute on function api.submit_opening_balance_cutover_review(
  uuid, uuid, bigint
) to authenticated, service_role;

revoke all on function api.preview_opening_balance_cutover(uuid, uuid)
from public, anon;

grant execute on function api.preview_opening_balance_cutover(uuid, uuid)
to authenticated, service_role;

revoke all on function api.post_opening_balance_cutover(
  uuid, text, uuid, text, boolean
) from public, anon;

grant execute on function api.post_opening_balance_cutover(
  uuid, text, uuid, text, boolean
) to authenticated, service_role;

create or replace view api.opening_balance_cutovers
with (security_invoker = true, security_barrier = true)
as
select
  cutover.id as cutover_id,
  cutover.organization_id,
  cutover.cutover_no,
  cutover.source_ref,
  cutover.source_estimate_ref,
  cutover.status_code,
  cutover.cutover_at,
  cutover.effective_local_date,
  cutover.created_at,
  cutover.updated_at,
  cutover.created_by,
  cutover.create_process_name,
  cutover.reviewed_at,
  cutover.reviewed_by,
  cutover.review_process_name,
  cutover.posted_at,
  cutover.posted_by,
  cutover.post_process_name,
  cutover.transaction_id,
  cutover.request_hash,
  cutover.posted_basis_hash,
  cutover.ledger_seq_before,
  cutover.ledger_seq_after,
  cutover.line_count,
  cutover.positive_line_count,
  cutover.total_quantity,
  cutover.note,
  cutover.metadata,
  cutover.row_version,
  case
    when cutover.status_code <> 'POSTED' then 'PENDING_POST'
    when cutover.positive_line_count = 0 then 'NOT_APPLICABLE'
    else 'UNVERIFIED'
  end as verification_status_code,
  0::bigint as verified_line_count,
  case
    when cutover.status_code = 'POSTED' then cutover.positive_line_count
    else 0
  end as unverified_line_count
from operations.opening_balance_cutovers cutover;

create or replace view api.opening_balance_cutover_lines
with (security_invoker = true, security_barrier = true)
as
select
  line.id as opening_balance_line_id,
  line.organization_id,
  line.cutover_id,
  line.line_no,
  line.product_id,
  line.batch_id,
  line.bucket_code,
  line.quantity,
  line.batch_identity_verified,
  line.exception_reference,
  line.product_sku_snapshot,
  line.product_name_snapshot,
  line.batch_code_snapshot,
  line.expiry_date_snapshot,
  line.batch_status_code_snapshot,
  line.product_row_version_snapshot,
  line.batch_row_version_snapshot,
  line.source_line_ref,
  line.ledger_entry_id,
  line.batch_bucket_qty_before,
  line.batch_bucket_qty_after,
  line.product_bucket_qty_before,
  line.product_bucket_qty_after,
  line.created_at,
  line.updated_at,
  case
    when cutover.status_code <> 'POSTED' then 'PENDING_POST'
    when line.quantity = 0 then 'NOT_APPLICABLE'
    else 'UNVERIFIED'
  end as verification_status_code
from operations.opening_balance_cutover_lines line
join operations.opening_balance_cutovers cutover
  on cutover.organization_id = line.organization_id
 and cutover.id = line.cutover_id;

revoke all on api.opening_balance_cutovers,
              api.opening_balance_cutover_lines
from public, anon;

grant select on api.opening_balance_cutovers,
                api.opening_balance_cutover_lines
to authenticated, service_role;

comment on table operations.opening_balance_cutovers
is 'Opening-balance cutover lifecycle. Posted rows are immutable and remain unverified until a later stocktake-verification contract links them.';

comment on table operations.opening_balance_cutover_lines
is 'Opening-balance quantities per product, batch, and physical bucket with exact INITIAL_BALANCE ledger linkage after posting.';

comment on function inventory.preview_opening_balance_cutover_core(uuid, uuid, boolean)
is 'Authoritative stock-neutral opening-balance preview core. Internal callers may lock the complete basis before posting.';

comment on function api.post_opening_balance_cutover(uuid, text, uuid, text, boolean)
is 'Posts one atomic, idempotent INITIAL_BALANCE transaction from a reviewed cutover and exact preview basis.';

commit;
