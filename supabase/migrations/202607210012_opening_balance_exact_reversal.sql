
begin;

-- A posted cutover remains immutable. Active-ness is maintained separately so a
-- fully reversed cutover can be replaced without rewriting historical headers.
create table operations.opening_balance_active_cutovers (
  organization_id uuid primary key
    references app.organizations(id) on delete restrict,
  cutover_id uuid not null unique,
  activated_at timestamptz not null,
  activated_by uuid null references auth.users(id) on delete set null,
  process_name text null,
  activation_rule_version text not null default
    'opening-balance-active-cutover-v1',
  created_at timestamptz not null default clock_timestamp(),

  constraint fk_opening_balance_active_cutover
    foreign key (organization_id, cutover_id)
    references operations.opening_balance_cutovers(organization_id, id)
    on delete restrict,

  constraint ck_opening_balance_active_actor
    check ((activated_by is not null) <> (process_name is not null)),

  constraint ck_opening_balance_active_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),

  constraint ck_opening_balance_active_rule_nonblank
    check (btrim(activation_rule_version) <> '')
);

create or replace function operations.validate_opening_balance_active_cutover()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, operations
as $$
declare
  v_cutover operations.opening_balance_cutovers%rowtype;
begin
  select cutover.*
  into v_cutover
  from operations.opening_balance_cutovers cutover
  where cutover.organization_id = new.organization_id
    and cutover.id = new.cutover_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_ACTIVE_CUTOVER_NOT_FOUND';
  end if;

  if v_cutover.status_code <> 'POSTED'
     or v_cutover.transaction_id is null
     or v_cutover.posted_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_ACTIVE_CUTOVER_NOT_POSTED';
  end if;

  if new.activated_at is distinct from v_cutover.posted_at
     or new.activated_by is distinct from v_cutover.posted_by
     or new.process_name is distinct from v_cutover.post_process_name then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_ACTIVE_CUTOVER_ACTOR_MISMATCH';
  end if;

  return new;
end;
$$;

create trigger trg_opening_balance_active_cutovers_validate
before insert or update
on operations.opening_balance_active_cutovers
for each row execute function operations.validate_opening_balance_active_cutover();

insert into operations.opening_balance_active_cutovers (
  organization_id,
  cutover_id,
  activated_at,
  activated_by,
  process_name,
  activation_rule_version,
  created_at
)
select
  cutover.organization_id,
  cutover.id,
  cutover.posted_at,
  cutover.posted_by,
  cutover.post_process_name,
  'opening-balance-active-cutover-v1',
  cutover.posted_at
from operations.opening_balance_cutovers cutover
where cutover.status_code = 'POSTED';

drop index operations.uidx_opening_balance_cutovers_posted_org;

create or replace function operations.register_opening_balance_active_cutover()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, operations
as $$
begin
  if new.status_code = 'POSTED'
     and old.status_code is distinct from 'POSTED' then
    begin
      insert into operations.opening_balance_active_cutovers (
        organization_id,
        cutover_id,
        activated_at,
        activated_by,
        process_name,
        activation_rule_version,
        created_at
      ) values (
        new.organization_id,
        new.id,
        new.posted_at,
        new.posted_by,
        new.post_process_name,
        'opening-balance-active-cutover-v1',
        clock_timestamp()
      );
    exception
      when unique_violation then
        raise exception using
          errcode = 'P0001',
          message = 'OPENING_BALANCE_ACTIVE_CUTOVER_EXISTS';
    end;
  end if;

  return new;
end;
$$;

create trigger trg_opening_balance_cutovers_register_active
after update of status_code
on operations.opening_balance_cutovers
for each row execute function operations.register_opening_balance_active_cutover();

create table operations.opening_balance_cutover_reversals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  opening_balance_cutover_id uuid not null,
  original_transaction_id uuid not null
    references inventory.stock_transactions(id) on delete restrict,
  reversal_transaction_id uuid not null
    references inventory.stock_transactions(id) on delete restrict,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  preview_basis_hash text not null,
  ledger_seq_before bigint not null,
  ledger_seq_after bigint not null,
  line_count bigint not null,
  total_absolute_quantity bigint not null,
  reversed_at timestamptz not null,
  reversed_by uuid null references auth.users(id) on delete set null,
  process_name text null,
  note text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),

  constraint uq_opening_balance_cutover_reversals_org_id
    unique (organization_id, id),

  constraint fk_opening_balance_cutover_reversal_cutover
    foreign key (organization_id, opening_balance_cutover_id)
    references operations.opening_balance_cutovers(organization_id, id)
    on delete restrict,

  constraint uq_opening_balance_cutover_reversal_cutover
    unique (opening_balance_cutover_id),

  constraint uq_opening_balance_cutover_reversal_original
    unique (original_transaction_id),

  constraint uq_opening_balance_cutover_reversal_transaction
    unique (reversal_transaction_id),

  constraint uq_opening_balance_cutover_reversal_command
    unique (idempotency_command_id),

  constraint ck_opening_balance_cutover_reversal_hash
    check (preview_basis_hash ~ '^[0-9a-f]{64}$'),

  constraint ck_opening_balance_cutover_reversal_ledger_boundary
    check (
      ledger_seq_before >= 0
      and ledger_seq_after >= ledger_seq_before
    ),

  constraint ck_opening_balance_cutover_reversal_counts
    check (line_count > 0 and total_absolute_quantity > 0),

  constraint ck_opening_balance_cutover_reversal_actor
    check ((reversed_by is not null) <> (process_name is not null)),

  constraint ck_opening_balance_cutover_reversal_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),

  constraint ck_opening_balance_cutover_reversal_note
    check (btrim(note) <> '' and length(note) <= 2000),

  constraint ck_opening_balance_cutover_reversal_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create index idx_opening_balance_cutover_reversals_org_time
on operations.opening_balance_cutover_reversals (
  organization_id,
  reversed_at desc,
  opening_balance_cutover_id
);

create or replace function operations.validate_opening_balance_cutover_reversal()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, inventory, operations
as $$
declare
  v_cutover operations.opening_balance_cutovers%rowtype;
  v_original inventory.stock_transactions%rowtype;
  v_reversal inventory.stock_transactions%rowtype;
  v_command inventory.idempotency_commands%rowtype;
  v_line_count bigint;
  v_total_quantity bigint;
begin
  select cutover.*
  into v_cutover
  from operations.opening_balance_cutovers cutover
  where cutover.organization_id = new.organization_id
    and cutover.id = new.opening_balance_cutover_id;

  if not found or v_cutover.status_code <> 'POSTED' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_CUTOVER_INVALID';
  end if;

  select transaction.*
  into v_original
  from inventory.stock_transactions transaction
  where transaction.id = new.original_transaction_id;

  select transaction.*
  into v_reversal
  from inventory.stock_transactions transaction
  where transaction.id = new.reversal_transaction_id;

  if v_original.id is null
     or v_original.organization_id <> new.organization_id
     or v_original.transaction_type_code <> 'INITIAL_BALANCE'
     or v_original.source_type_code <> 'OPENING_BALANCE_CUTOVER'
     or v_original.source_id is distinct from v_cutover.id
     or v_cutover.transaction_id is distinct from v_original.id then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_ORIGINAL_INVALID';
  end if;

  if v_reversal.id is null
     or v_reversal.organization_id <> new.organization_id
     or v_reversal.transaction_type_code <> 'REVERSAL'
     or v_reversal.reversal_of_transaction_id is distinct from v_original.id then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_TRANSACTION_INVALID';
  end if;

  select command.*
  into v_command
  from inventory.idempotency_commands command
  where command.id = new.idempotency_command_id;

  if v_command.id is null
     or v_command.organization_id <> new.organization_id
     or v_command.scope <> 'REVERSE_OPENING_BALANCE_CUTOVER' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_COMMAND_INVALID';
  end if;

  if new.reversed_at is distinct from v_reversal.recorded_at
     or new.reversed_by is distinct from v_reversal.actor_user_id
     or new.process_name is distinct from v_reversal.process_name then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_ACTOR_MISMATCH';
  end if;

  select
    count(*),
    coalesce(sum(abs(entry.quantity_delta)), 0)::bigint
  into v_line_count, v_total_quantity
  from inventory.stock_ledger_entries entry
  where entry.organization_id = new.organization_id
    and entry.transaction_id = new.reversal_transaction_id;

  if v_line_count <> new.line_count
     or v_total_quantity <> new.total_absolute_quantity then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_TOTAL_MISMATCH';
  end if;

  return new;
end;
$$;

create trigger trg_opening_balance_cutover_reversals_validate
before insert or update
on operations.opening_balance_cutover_reversals
for each row execute function operations.validate_opening_balance_cutover_reversal();

create trigger trg_opening_balance_cutover_reversals_immutable
before update or delete
on operations.opening_balance_cutover_reversals
for each row execute function inventory.reject_immutable_mutation();

alter table operations.opening_balance_active_cutovers enable row level security;
alter table operations.opening_balance_cutover_reversals enable row level security;

create policy opening_balance_active_cutovers_read_current_org
on operations.opening_balance_active_cutovers
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy opening_balance_cutover_reversals_read_current_org
on operations.opening_balance_cutover_reversals
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all
on operations.opening_balance_active_cutovers,
   operations.opening_balance_cutover_reversals
from public, anon, authenticated;

grant select
on operations.opening_balance_active_cutovers,
   operations.opening_balance_cutover_reversals
to authenticated, service_role;


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

  select active.cutover_id
  into v_existing_posted_cutover_id
  from operations.opening_balance_active_cutovers active
  where active.organization_id = p_organization_id
    and active.cutover_id <> p_cutover_id
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

create or replace function inventory.apply_opening_balance_first_verification()
returns trigger
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations
as $$
declare
  v_posting operations.stocktake_postings%rowtype;
  v_approval operations.stocktake_approvals%rowtype;
  v_approval_line operations.stocktake_approval_lines%rowtype;
  v_stocktake_line operations.stocktake_lines%rowtype;
  v_count_attempt operations.stocktake_count_attempts%rowtype;
  v_cutover_id uuid;
  v_opening_balance_line_id uuid;
  v_opening_balance_quantity bigint;
  v_opening_balance_ledger_seq_after bigint;
  v_cutover_posted_at timestamptz;
begin
  select
    cutover.id,
    line.id,
    line.quantity,
    cutover.ledger_seq_after,
    cutover.posted_at
  into
    v_cutover_id,
    v_opening_balance_line_id,
    v_opening_balance_quantity,
    v_opening_balance_ledger_seq_after,
    v_cutover_posted_at
  from operations.opening_balance_cutover_lines line
  join operations.opening_balance_cutovers cutover
    on cutover.organization_id = line.organization_id
   and cutover.id = line.cutover_id
  join operations.opening_balance_active_cutovers active
    on active.organization_id = cutover.organization_id
   and active.cutover_id = cutover.id
  where line.organization_id = new.organization_id
    and line.product_id = new.product_id
    and line.batch_id = new.batch_id
    and line.bucket_code = new.bucket_code
    and line.quantity > 0
    and line.ledger_entry_id is not null
    and cutover.status_code = 'POSTED'
    and cutover.posted_at is not null
    and cutover.ledger_seq_after is not null
    and not exists (
      select 1
      from operations.opening_balance_verification_applications application
      where application.opening_balance_line_id = line.id
    )
  order by cutover.posted_at, line.line_no
  limit 1;

  if not found then
    return new;
  end if;

  select posting.*
  into v_posting
  from operations.stocktake_postings posting
  where posting.organization_id = new.organization_id
    and posting.stocktake_id = new.stocktake_id
    and posting.id = new.posting_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_POSTING_NOT_FOUND';
  end if;

  select approval.*
  into v_approval
  from operations.stocktake_approvals approval
  where approval.organization_id = new.organization_id
    and approval.stocktake_id = new.stocktake_id
    and approval.id = v_posting.approval_id
    and approval.approval_version_no = v_posting.approval_version_no;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_APPROVAL_INVALID';
  end if;

  select approval_line.*
  into v_approval_line
  from operations.stocktake_approval_lines approval_line
  where approval_line.organization_id = new.organization_id
    and approval_line.stocktake_id = new.stocktake_id
    and approval_line.approval_id = v_posting.approval_id
    and approval_line.id = new.approval_line_id
    and approval_line.stocktake_line_id = new.stocktake_line_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_APPROVAL_LINE_INVALID';
  end if;

  select line.*
  into v_stocktake_line
  from operations.stocktake_lines line
  where line.organization_id = new.organization_id
    and line.stocktake_id = new.stocktake_id
    and line.id = new.stocktake_line_id
    and line.product_id = new.product_id
    and line.batch_id = new.batch_id
    and line.bucket_code = new.bucket_code;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_STOCKTAKE_LINE_INVALID';
  end if;

  if new.line_no <> v_approval_line.line_no
     or new.adjustment_qty <> v_approval_line.variance_qty
     or v_stocktake_line.final_attempt_id is distinct from
        v_approval_line.final_attempt_id
     or v_stocktake_line.final_physical_qty is distinct from
        v_approval_line.final_physical_qty
     or v_stocktake_line.expected_qty_at_count is distinct from
        v_approval_line.expected_qty_at_count
     or v_stocktake_line.count_cutoff_ledger_seq is distinct from
        v_approval_line.count_cutoff_ledger_seq then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_POSTING_LINE_INVALID';
  end if;

  select attempt.*
  into v_count_attempt
  from operations.stocktake_count_attempts attempt
  where attempt.organization_id = new.organization_id
    and attempt.stocktake_id = new.stocktake_id
    and attempt.stocktake_line_id = new.stocktake_line_id
    and attempt.id = v_approval_line.final_attempt_id
    and attempt.status_code = 'VALID';

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_COUNT_EVIDENCE_INVALID';
  end if;

  if v_count_attempt.physical_qty <> v_approval_line.final_physical_qty
     or v_count_attempt.expected_qty_at_count <>
        v_approval_line.expected_qty_at_count
     or v_count_attempt.variance_qty <> v_approval_line.variance_qty
     or v_count_attempt.count_cutoff_ledger_seq <>
        v_approval_line.count_cutoff_ledger_seq then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_COUNT_EVIDENCE_INVALID';
  end if;

  if v_count_attempt.counted_at < v_cutover_posted_at
     or v_count_attempt.count_cutoff_ledger_seq <
        v_opening_balance_ledger_seq_after
     or v_posting.posting_ledger_seq_before <
        v_opening_balance_ledger_seq_after then
    return new;
  end if;

  perform line.id
  from operations.opening_balance_cutover_lines line
  where line.organization_id = new.organization_id
    and line.id = v_opening_balance_line_id
    and exists (
      select 1
      from operations.opening_balance_active_cutovers active
      where active.organization_id = line.organization_id
        and active.cutover_id = line.cutover_id
    )
    and not exists (
      select 1
      from operations.opening_balance_verification_applications application
      where application.opening_balance_line_id = line.id
    )
  for update of line;

  if not found then
    return new;
  end if;

  insert into operations.opening_balance_verification_applications (
    organization_id,
    opening_balance_cutover_id,
    opening_balance_line_id,
    stocktake_id,
    stocktake_approval_id,
    approval_version_no,
    stocktake_posting_id,
    stocktake_posting_line_id,
    stocktake_line_id,
    count_attempt_id,
    product_id,
    batch_id,
    bucket_code,
    opening_balance_quantity,
    physical_quantity,
    stocktake_variance_quantity,
    count_cutoff_ledger_seq,
    opening_balance_ledger_seq_after,
    verified_at,
    verified_by,
    process_name,
    verification_rule_version,
    metadata,
    created_at
  ) values (
    new.organization_id,
    v_cutover_id,
    v_opening_balance_line_id,
    new.stocktake_id,
    v_posting.approval_id,
    v_posting.approval_version_no,
    new.posting_id,
    new.id,
    new.stocktake_line_id,
    v_count_attempt.id,
    new.product_id,
    new.batch_id,
    new.bucket_code,
    v_opening_balance_quantity,
    v_count_attempt.physical_qty,
    v_approval_line.variance_qty,
    v_count_attempt.count_cutoff_ledger_seq,
    v_opening_balance_ledger_seq_after,
    v_posting.posted_at,
    v_posting.posted_by,
    v_posting.process_name,
    'opening-balance-first-stocktake-v1',
    jsonb_build_object(
      'source', 'STOCKTAKE_POSTING',
      'stocktakePostingLineId', new.id,
      'countedAt', v_count_attempt.counted_at,
      'cutoverPostedAt', v_cutover_posted_at
    ),
    clock_timestamp()
  )
  on conflict (opening_balance_line_id) do nothing;

  return new;
end;
$$;


revoke all
on function inventory.apply_opening_balance_first_verification()
from public, anon, authenticated, service_role;


create or replace function inventory.preview_opening_balance_reversal_core(
  p_organization_id uuid,
  p_cutover_id uuid,
  p_lock_basis boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
declare
  v_cutover operations.opening_balance_cutovers%rowtype;
  v_original inventory.stock_transactions%rowtype;
  v_active operations.opening_balance_active_cutovers%rowtype;
  v_lines jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_basis jsonb;
  v_basis_hash text;
  v_current_ledger_seq bigint;
  v_verification_count bigint;
  v_original_line_count bigint;
  v_original_total_quantity bigint;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_cutover_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CUTOVER_ID_REQUIRED';
  end if;

  if p_lock_basis then
    select cutover.*
    into v_cutover
    from operations.opening_balance_cutovers cutover
    where cutover.organization_id = p_organization_id
      and cutover.id = p_cutover_id
    for share;
  else
    select cutover.*
    into v_cutover
    from operations.opening_balance_cutovers cutover
    where cutover.organization_id = p_organization_id
      and cutover.id = p_cutover_id;
  end if;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CUTOVER_NOT_FOUND';
  end if;

  if p_lock_basis then
    select active.*
    into v_active
    from operations.opening_balance_active_cutovers active
    where active.organization_id = p_organization_id
    for update;
  else
    select active.*
    into v_active
    from operations.opening_balance_active_cutovers active
    where active.organization_id = p_organization_id;
  end if;

  if v_cutover.status_code <> 'POSTED' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_CUTOVER_NOT_POSTED',
      'message', 'Cutover saldo awal belum diposting.'
    ));
  end if;

  if v_active.cutover_id is distinct from p_cutover_id then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_CUTOVER_NOT_ACTIVE',
      'activeCutoverId', v_active.cutover_id,
      'message', 'Cutover bukan saldo awal aktif organisasi.'
    ));
  end if;

  if v_cutover.transaction_id is null then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_TRANSACTION_REQUIRED',
      'message', 'Cutover tidak memiliki transaksi saldo awal.'
    ));
  else
    if p_lock_basis then
      select transaction.*
      into v_original
      from inventory.stock_transactions transaction
      where transaction.organization_id = p_organization_id
        and transaction.id = v_cutover.transaction_id
      for share;
    else
      select transaction.*
      into v_original
      from inventory.stock_transactions transaction
      where transaction.organization_id = p_organization_id
        and transaction.id = v_cutover.transaction_id;
    end if;

    if not found
       or v_original.transaction_type_code <> 'INITIAL_BALANCE'
       or v_original.source_type_code <> 'OPENING_BALANCE_CUTOVER'
       or v_original.source_id is distinct from p_cutover_id then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code', 'OPENING_BALANCE_TRANSACTION_INVALID',
        'message', 'Transaksi asal tidak cocok dengan cutover saldo awal.'
      ));
    end if;
  end if;

  if exists (
    select 1
    from operations.opening_balance_cutover_reversals reversal
    where reversal.organization_id = p_organization_id
      and reversal.opening_balance_cutover_id = p_cutover_id
  ) or exists (
    select 1
    from inventory.stock_transactions reversal_transaction
    where reversal_transaction.organization_id = p_organization_id
      and reversal_transaction.transaction_type_code = 'REVERSAL'
      and reversal_transaction.reversal_of_transaction_id = v_cutover.transaction_id
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_ALREADY_REVERSED',
      'message', 'Cutover saldo awal sudah dibalik.'
    ));
  end if;

  select
    count(*) filter (where line.quantity > 0),
    coalesce(sum(line.quantity) filter (where line.quantity > 0), 0)::bigint
  into v_original_line_count, v_original_total_quantity
  from operations.opening_balance_cutover_lines line
  where line.organization_id = p_organization_id
    and line.cutover_id = p_cutover_id;

  if v_original_line_count = 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_REVERSAL_LINES_REQUIRED',
      'message', 'Cutover tidak memiliki line positif untuk dibalik.'
    ));
  end if;

  if exists (
    select 1
    from operations.opening_balance_cutover_lines line
    left join inventory.stock_ledger_entries entry
      on entry.organization_id = line.organization_id
     and entry.id = line.ledger_entry_id
     and entry.transaction_id = v_cutover.transaction_id
    where line.organization_id = p_organization_id
      and line.cutover_id = p_cutover_id
      and line.quantity > 0
      and (
        line.ledger_entry_id is null
        or entry.id is null
        or entry.product_id <> line.product_id
        or entry.batch_id <> line.batch_id
        or entry.bucket_code <> line.bucket_code
        or entry.quantity_delta <> line.quantity
        or entry.source_line_ref is distinct from line.source_line_ref
      )
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_LEDGER_LINK_INVALID',
      'message', 'Link ledger saldo awal tidak lengkap atau tidak cocok.'
    ));
  end if;

  if exists (
    select 1
    from operations.opening_balance_cutover_lines line
    join inventory.stock_reversal_applications application
      on application.organization_id = p_organization_id
     and application.original_entry_id = line.ledger_entry_id
    where line.organization_id = p_organization_id
      and line.cutover_id = p_cutover_id
      and line.quantity > 0
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_ALREADY_REVERSED',
      'message', 'Salah satu entry saldo awal sudah memiliki pembalikan.'
    ));
  end if;

  if p_lock_basis then
    perform product.id
    from catalog.products product
    join (
      select distinct line.product_id
      from operations.opening_balance_cutover_lines line
      where line.organization_id = p_organization_id
        and line.cutover_id = p_cutover_id
        and line.quantity > 0
    ) affected on affected.product_id = product.id
    where product.organization_id = p_organization_id
    order by product.id
    for update of product;

    perform batch.id
    from catalog.product_batches batch
    join (
      select distinct line.product_id, line.batch_id
      from operations.opening_balance_cutover_lines line
      where line.organization_id = p_organization_id
        and line.cutover_id = p_cutover_id
        and line.quantity > 0
    ) affected
      on affected.product_id = batch.product_id
     and affected.batch_id = batch.id
    where batch.organization_id = p_organization_id
    order by batch.product_id, batch.id
    for update of batch;

    perform balance.batch_id
    from inventory.stock_batch_balances balance
    join (
      select distinct line.product_id, line.batch_id
      from operations.opening_balance_cutover_lines line
      where line.organization_id = p_organization_id
        and line.cutover_id = p_cutover_id
        and line.quantity > 0
    ) affected
      on affected.product_id = balance.product_id
     and affected.batch_id = balance.batch_id
    where balance.organization_id = p_organization_id
    order by balance.product_id, balance.batch_id
    for update of balance;

    perform position.product_id
    from inventory.stock_product_positions position
    join (
      select distinct line.product_id
      from operations.opening_balance_cutover_lines line
      where line.organization_id = p_organization_id
        and line.cutover_id = p_cutover_id
        and line.quantity > 0
    ) affected on affected.product_id = position.product_id
    where position.organization_id = p_organization_id
    order by position.product_id
    for update of position;
  end if;

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
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_REVERSAL_PROJECTION_DRIFT',
      'message', 'Projection batch tidak sama dengan ledger.'
    ));
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
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_REVERSAL_PROJECTION_DRIFT',
      'message', 'Projection produk tidak sama dengan ledger.'
    ));
  end if;

  if exists (
    select 1
    from operations.opening_balance_cutover_lines line
    join inventory.stock_batch_balances balance
      on balance.organization_id = line.organization_id
     and balance.product_id = line.product_id
     and balance.batch_id = line.batch_id
    where line.organization_id = p_organization_id
      and line.cutover_id = p_cutover_id
      and line.quantity > 0
      and (
        case line.bucket_code
          when 'SELLABLE' then balance.sellable_qty
          when 'QUARANTINE' then balance.quarantine_qty
          when 'DAMAGED' then balance.damaged_qty
        end
      ) - line.quantity < 0
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_REVERSAL_NEGATIVE_BUCKET',
      'message', 'Pembalikan akan membuat saldo bucket menjadi negatif.'
    ));
  end if;

  if exists (
    with effect as (
      select
        line.product_id,
        coalesce(sum(line.quantity) filter (
          where line.bucket_code = 'SELLABLE'
        ), 0)::bigint as sellable_quantity
      from operations.opening_balance_cutover_lines line
      where line.organization_id = p_organization_id
        and line.cutover_id = p_cutover_id
        and line.quantity > 0
      group by line.product_id
    )
    select 1
    from effect
    join inventory.stock_product_positions position
      on position.organization_id = p_organization_id
     and position.product_id = effect.product_id
    where position.sellable_qty - effect.sellable_quantity
          < position.reserved_qty
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'OPENING_BALANCE_REVERSAL_RESERVED_CONFLICT',
      'message', 'Pembalikan akan membuat reserved melebihi sellable.'
    ));
  end if;

  with product_effect as (
    select
      line.product_id,
      coalesce(sum(line.quantity) filter (
        where line.bucket_code = 'SELLABLE'
      ), 0)::bigint as sellable_quantity,
      coalesce(sum(line.quantity) filter (
        where line.bucket_code = 'QUARANTINE'
      ), 0)::bigint as quarantine_quantity,
      coalesce(sum(line.quantity) filter (
        where line.bucket_code = 'DAMAGED'
      ), 0)::bigint as damaged_quantity
    from operations.opening_balance_cutover_lines line
    where line.organization_id = p_organization_id
      and line.cutover_id = p_cutover_id
      and line.quantity > 0
    group by line.product_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'openingBalanceLineId', line.id,
        'originalEntryId', line.ledger_entry_id,
        'lineNo', line.line_no,
        'sourceLineRef', line.source_line_ref,
        'productId', line.product_id,
        'productSku', line.product_sku_snapshot,
        'batchId', line.batch_id,
        'batchCode', line.batch_code_snapshot,
        'expiryDate', line.expiry_date_snapshot,
        'bucketCode', line.bucket_code,
        'originalQuantity', line.quantity,
        'reversalDelta', -line.quantity,
        'currentBatchBucketQty',
          case line.bucket_code
            when 'SELLABLE' then balance.sellable_qty
            when 'QUARANTINE' then balance.quarantine_qty
            when 'DAMAGED' then balance.damaged_qty
          end,
        'resultingBatchBucketQty',
          case line.bucket_code
            when 'SELLABLE' then balance.sellable_qty
            when 'QUARANTINE' then balance.quarantine_qty
            when 'DAMAGED' then balance.damaged_qty
          end - line.quantity,
        'currentProductSellableQty', position.sellable_qty,
        'currentProductQuarantineQty', position.quarantine_qty,
        'currentProductDamagedQty', position.damaged_qty,
        'currentProductReservedQty', position.reserved_qty,
        'resultingProductSellableQty',
          position.sellable_qty - effect.sellable_quantity,
        'resultingProductQuarantineQty',
          position.quarantine_qty - effect.quarantine_quantity,
        'resultingProductDamagedQty',
          position.damaged_qty - effect.damaged_quantity,
        'batchBalanceVersion', balance.version,
        'productPositionVersion', position.version,
        'originalLedgerSeq', entry.ledger_seq
      )
      order by line.line_no
    ),
    '[]'::jsonb
  )
  into v_lines
  from operations.opening_balance_cutover_lines line
  join inventory.stock_ledger_entries entry
    on entry.organization_id = line.organization_id
   and entry.id = line.ledger_entry_id
  join inventory.stock_batch_balances balance
    on balance.organization_id = line.organization_id
   and balance.product_id = line.product_id
   and balance.batch_id = line.batch_id
  join inventory.stock_product_positions position
    on position.organization_id = line.organization_id
   and position.product_id = line.product_id
  join product_effect effect
    on effect.product_id = line.product_id
  where line.organization_id = p_organization_id
    and line.cutover_id = p_cutover_id
    and line.quantity > 0;

  select coalesce(max(entry.ledger_seq), 0)::bigint
  into v_current_ledger_seq
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  select count(*)::bigint
  into v_verification_count
  from operations.opening_balance_verification_applications application
  where application.organization_id = p_organization_id
    and application.opening_balance_cutover_id = p_cutover_id;

  v_basis := jsonb_build_object(
    'schemaVersion', 1,
    'organizationId', p_organization_id,
    'cutoverId', v_cutover.id,
    'cutoverNo', v_cutover.cutover_no,
    'activeCutoverId', v_active.cutover_id,
    'cutoverPostedAt', v_cutover.posted_at,
    'cutoverLedgerSeqAfter', v_cutover.ledger_seq_after,
    'originalTransactionId', v_original.id,
    'originalTransactionNo', v_original.transaction_no,
    'originalTransactionType', v_original.transaction_type_code,
    'currentOrganizationLedgerSeq', v_current_ledger_seq,
    'positiveLineCount', v_original_line_count,
    'totalQuantity', v_original_total_quantity,
    'verificationApplicationCount', v_verification_count,
    'lines', v_lines
  );

  v_basis_hash := encode(
    extensions.digest(convert_to(v_basis::text, 'UTF8'), 'sha256'),
    'hex'
  );

  return jsonb_build_object(
    'status',
      case
        when jsonb_array_length(v_blockers) = 0 then 'PREVIEW_READY'
        else 'BLOCKED'
      end,
    'eligible', jsonb_array_length(v_blockers) = 0,
    'basisHash', v_basis_hash,
    'schemaVersion', 1,
    'cutoverId', v_cutover.id,
    'cutoverNo', v_cutover.cutover_no,
    'originalTransactionId', v_original.id,
    'originalTransactionNo', v_original.transaction_no,
    'lineCount', v_original_line_count,
    'totalAbsoluteQuantity', v_original_total_quantity,
    'verificationApplicationCount', v_verification_count,
    'lines', v_lines,
    'blockers', v_blockers
  );
end;
$$;

revoke all
on function inventory.preview_opening_balance_reversal_core(uuid, uuid, boolean)
from public, anon, authenticated, service_role;

create or replace function api.preview_opening_balance_reversal(
  p_organization_id uuid,
  p_cutover_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
declare
  v_actor_user_id uuid := auth.uid();
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_cutover_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CUTOVER_ID_REQUIRED';
  end if;

  if v_actor_user_id is null then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if not app.is_admin()
     or app.current_organization_id() is distinct from p_organization_id then
    raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  return inventory.preview_opening_balance_reversal_core(
    p_organization_id,
    p_cutover_id,
    false
  );
end;
$$;

create or replace function api.reverse_opening_balance_cutover(
  p_organization_id uuid,
  p_idempotency_key text,
  p_cutover_id uuid,
  p_preview_basis_hash text,
  p_confirmation boolean,
  p_note text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
declare
  v_scope constant text := 'REVERSE_OPENING_BALANCE_CUTOVER';
  v_idempotency_key text;
  v_preview_basis_hash text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_cutover operations.opening_balance_cutovers%rowtype;
  v_original inventory.stock_transactions%rowtype;
  v_preview jsonb;
  v_blocker_code text;
  v_reason_id uuid;
  v_channel_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_reversal_transaction_id uuid := gen_random_uuid();
  v_reversal_record_id uuid := gen_random_uuid();
  v_correlation_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_effective_local_date date;
  v_organization_timezone text;
  v_transaction_no text;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_created_by_role_code text;
  v_line record;
  v_reversal_entry_id uuid;
  v_ledger_seq bigint;
  v_ledger_seq_before bigint;
  v_ledger_seq_after bigint;
  v_line_count bigint := 0;
  v_total_absolute_quantity bigint := 0;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_cutover_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CUTOVER_ID_REQUIRED';
  end if;

  if not coalesce(p_confirmation, false) then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_CONFIRMATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_preview_basis_hash := lower(btrim(coalesce(p_preview_basis_hash, '')));
  if v_preview_basis_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_PREVIEW_HASH_INVALID';
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');
  if v_note is null then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_NOTE_REQUIRED';
  end if;
  if length(v_note) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_NOTE_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_METADATA_MUST_BE_OBJECT';
  end if;

  if v_actor_user_id is null then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if not app.is_admin()
     or app.current_organization_id() is distinct from p_organization_id then
    raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  v_process_name := null;
  v_created_by_role_code := 'ADMIN';

  select organization.timezone
  into v_organization_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_NOT_FOUND';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':OPENING_BALANCE_REVERSAL',
    0::bigint
  ));

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':' || v_scope || ':' || v_idempotency_key,
    0::bigint
  ));

  select cutover.*
  into v_cutover
  from operations.opening_balance_cutovers cutover
  where cutover.organization_id = p_organization_id
    and cutover.id = p_cutover_id
  for share;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_CUTOVER_NOT_FOUND';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'cutoverId', p_cutover_id,
          'originalTransactionId', v_cutover.transaction_id,
          'previewBasisHash', v_preview_basis_hash,
          'confirmation', true,
          'note', v_note,
          'metadata', v_metadata,
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
    if v_existing.request_hash <> v_request_hash then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REUSED';
    end if;

    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot;
    end if;

    if v_existing.status_code = 'STARTED' then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;

    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  v_preview := inventory.preview_opening_balance_reversal_core(
    p_organization_id,
    p_cutover_id,
    true
  );

  if lower(v_preview ->> 'basisHash') is distinct from v_preview_basis_hash then
    raise exception using
      errcode = 'P0001',
      message = 'STALE_OPENING_BALANCE_REVERSAL_PREVIEW';
  end if;

  if not coalesce((v_preview ->> 'eligible')::boolean, false) then
    v_blocker_code := v_preview #>> '{blockers,0,code}';
    raise exception using
      errcode = 'P0001',
      message = coalesce(v_blocker_code, 'OPENING_BALANCE_REVERSAL_NOT_ALLOWED');
  end if;

  select transaction.*
  into v_original
  from inventory.stock_transactions transaction
  where transaction.organization_id = p_organization_id
    and transaction.id = v_cutover.transaction_id
  for share;

  select reason.id
  into v_reason_id
  from catalog.movement_reasons reason
  where reason.code = 'REVERSAL'
    and reason.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'REVERSAL_REASON_NOT_CONFIGURED';
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = 'MANUAL'
    and channel.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'REVERSAL_CHANNEL_NOT_CONFIGURED';
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
    v_request_hash,
    'STARTED',
    v_recorded_at,
    null,
    null,
    '{}'::jsonb,
    null,
    null
  );

  v_effective_local_date :=
    (v_recorded_at at time zone v_organization_timezone)::date;

  v_transaction_no :=
    'OBR-' ||
    to_char(v_effective_local_date, 'YYYYMMDD') ||
    '-' ||
    upper(substr(replace(v_reversal_transaction_id::text, '-', ''), 1, 8));

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
    v_reversal_transaction_id,
    p_organization_id,
    v_transaction_no,
    'REVERSAL',
    v_reason_id,
    'REVERSAL',
    v_channel_id,
    'MANUAL',
    'OPENING_BALANCE_CUTOVER_REVERSAL',
    p_cutover_id,
    v_cutover.cutover_no,
    v_recorded_at,
    v_recorded_at,
    v_effective_local_date,
    v_actor_user_id,
    v_process_name,
    v_created_by_role_code,
    v_correlation_id,
    v_command_id,
    v_original.id,
    v_note,
    v_metadata || jsonb_build_object(
      'openingBalanceCutoverId', p_cutover_id,
      'openingBalanceCutoverNo', v_cutover.cutover_no,
      'originalTransactionId', v_original.id,
      'originalTransactionNo', v_original.transaction_no,
      'previewBasisHash', v_preview_basis_hash
    ),
    1
  );

  for v_line in
    select
      line.id as opening_balance_line_id,
      line.line_no,
      line.product_id,
      line.batch_id,
      line.product_sku_snapshot,
      line.batch_code_snapshot,
      line.expiry_date_snapshot,
      line.bucket_code,
      line.quantity,
      line.ledger_entry_id
    from operations.opening_balance_cutover_lines line
    where line.organization_id = p_organization_id
      and line.cutover_id = p_cutover_id
      and line.quantity > 0
    order by line.line_no
  loop
    v_reversal_entry_id := gen_random_uuid();

    insert into inventory.stock_ledger_entries (
      id,
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
      v_reversal_entry_id,
      p_organization_id,
      v_reversal_transaction_id,
      v_line.line_no,
      v_line.product_id,
      v_line.batch_id,
      v_line.product_sku_snapshot,
      v_line.batch_code_snapshot,
      v_line.expiry_date_snapshot,
      v_line.bucket_code,
      -v_line.quantity,
      'REVERSAL',
      null,
      v_line.ledger_entry_id::text,
      v_recorded_at,
      v_recorded_at,
      v_recorded_at
    )
    returning ledger_seq into v_ledger_seq;

    update inventory.stock_batch_balances balance
    set
      sellable_qty = balance.sellable_qty + case
        when v_line.bucket_code = 'SELLABLE' then -v_line.quantity else 0 end,
      quarantine_qty = balance.quarantine_qty + case
        when v_line.bucket_code = 'QUARANTINE' then -v_line.quantity else 0 end,
      damaged_qty = balance.damaged_qty + case
        when v_line.bucket_code = 'DAMAGED' then -v_line.quantity else 0 end,
      last_ledger_seq = greatest(balance.last_ledger_seq, v_ledger_seq),
      updated_at = v_recorded_at,
      version = balance.version + 1
    where balance.organization_id = p_organization_id
      and balance.product_id = v_line.product_id
      and balance.batch_id = v_line.batch_id
      and (
        case v_line.bucket_code
          when 'SELLABLE' then balance.sellable_qty
          when 'QUARANTINE' then balance.quarantine_qty
          when 'DAMAGED' then balance.damaged_qty
        end
      ) >= v_line.quantity;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'OPENING_BALANCE_REVERSAL_NEGATIVE_BUCKET';
    end if;

    update inventory.stock_product_positions position
    set
      sellable_qty = position.sellable_qty + case
        when v_line.bucket_code = 'SELLABLE' then -v_line.quantity else 0 end,
      quarantine_qty = position.quarantine_qty + case
        when v_line.bucket_code = 'QUARANTINE' then -v_line.quantity else 0 end,
      damaged_qty = position.damaged_qty + case
        when v_line.bucket_code = 'DAMAGED' then -v_line.quantity else 0 end,
      last_ledger_seq = greatest(position.last_ledger_seq, v_ledger_seq),
      updated_at = v_recorded_at,
      version = position.version + 1
    where position.organization_id = p_organization_id
      and position.product_id = v_line.product_id
      and position.sellable_qty + case
        when v_line.bucket_code = 'SELLABLE' then -v_line.quantity else 0 end
          >= position.reserved_qty
      and position.quarantine_qty + case
        when v_line.bucket_code = 'QUARANTINE' then -v_line.quantity else 0 end
          >= 0
      and position.damaged_qty + case
        when v_line.bucket_code = 'DAMAGED' then -v_line.quantity else 0 end
          >= 0;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'OPENING_BALANCE_REVERSAL_RESERVED_CONFLICT';
    end if;

    insert into inventory.stock_reversal_applications (
      organization_id,
      original_transaction_id,
      reversal_transaction_id,
      original_entry_id,
      reversal_entry_id,
      quantity_applied,
      created_at
    ) values (
      p_organization_id,
      v_original.id,
      v_reversal_transaction_id,
      v_line.ledger_entry_id,
      v_reversal_entry_id,
      v_line.quantity,
      v_recorded_at
    );

    v_line_count := v_line_count + 1;
    v_total_absolute_quantity :=
      v_total_absolute_quantity + v_line.quantity;
  end loop;

  if v_line_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_LINES_REQUIRED';
  end if;

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
    join inventory.stock_batch_balances balance
      on balance.organization_id = p_organization_id
     and balance.product_id = ledger.product_id
     and balance.batch_id = ledger.batch_id
    where balance.sellable_qty <> ledger.sellable_qty
       or balance.quarantine_qty <> ledger.quarantine_qty
       or balance.damaged_qty <> ledger.damaged_qty
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_PROJECTION_DRIFT';
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
    join inventory.stock_product_positions position
      on position.organization_id = p_organization_id
     and position.product_id = ledger.product_id
    where position.sellable_qty <> ledger.sellable_qty
       or position.quarantine_qty <> ledger.quarantine_qty
       or position.damaged_qty <> ledger.damaged_qty
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_REVERSAL_PROJECTION_DRIFT';
  end if;

  select coalesce(max(entry.ledger_seq), 0)::bigint
  into v_ledger_seq_after
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  insert into operations.opening_balance_cutover_reversals (
    id,
    organization_id,
    opening_balance_cutover_id,
    original_transaction_id,
    reversal_transaction_id,
    idempotency_command_id,
    preview_basis_hash,
    ledger_seq_before,
    ledger_seq_after,
    line_count,
    total_absolute_quantity,
    reversed_at,
    reversed_by,
    process_name,
    note,
    metadata,
    created_at
  ) values (
    v_reversal_record_id,
    p_organization_id,
    p_cutover_id,
    v_original.id,
    v_reversal_transaction_id,
    v_command_id,
    v_preview_basis_hash,
    v_ledger_seq_before,
    v_ledger_seq_after,
    v_line_count,
    v_total_absolute_quantity,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    v_note,
    v_metadata,
    v_recorded_at
  );

  delete from operations.opening_balance_active_cutovers active
  where active.organization_id = p_organization_id
    and active.cutover_id = p_cutover_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_ACTIVE_CUTOVER_MISSING';
  end if;

  v_response := jsonb_build_object(
    'status', 'REVERSED',
    'cutoverId', p_cutover_id,
    'cutoverNo', v_cutover.cutover_no,
    'originalTransactionId', v_original.id,
    'originalTransactionNo', v_original.transaction_no,
    'reversalRecordId', v_reversal_record_id,
    'reversalTransactionId', v_reversal_transaction_id,
    'reversalTransactionNo', v_transaction_no,
    'lineCount', v_line_count,
    'totalAbsoluteQuantity', v_total_absolute_quantity,
    'previewBasisHash', v_preview_basis_hash,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'ledgerSeqBefore', v_ledger_seq_before,
    'ledgerSeqAfter', v_ledger_seq_after,
    'recordedAt', v_recorded_at,
    'actorUserId', v_actor_user_id
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    result_transaction_id = v_reversal_transaction_id,
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

revoke all
on function api.preview_opening_balance_reversal(uuid, uuid)
from public, anon, service_role;

grant execute
on function api.preview_opening_balance_reversal(uuid, uuid)
to authenticated;

revoke all
on function api.reverse_opening_balance_cutover(
  uuid, text, uuid, text, boolean, text, jsonb
)
from public, anon, service_role;

grant execute
on function api.reverse_opening_balance_cutover(
  uuid, text, uuid, text, boolean, text, jsonb
)
to authenticated;



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
    when verification.verified_line_count = 0 then 'UNVERIFIED'
    when verification.verified_line_count < cutover.positive_line_count
      then 'PARTIALLY_VERIFIED'
    else 'VERIFIED'
  end as verification_status_code,
  verification.verified_line_count,
  case
    when cutover.status_code = 'POSTED' then greatest(
      cutover.positive_line_count - verification.verified_line_count,
      0
    )
    else 0
  end as unverified_line_count,
  case
    when cutover.status_code <> 'POSTED' then cutover.status_code
    when reversal.id is not null then 'REVERSED'
    when active.cutover_id is not null then 'ACTIVE'
    else 'POSTED_INACTIVE'
  end as operational_status_code,
  active.cutover_id is not null as is_active,
  reversal.id as reversal_record_id,
  reversal.reversal_transaction_id,
  reversal.reversed_at,
  reversal.reversed_by,
  reversal.process_name as reversal_process_name,
  reversal.note as reversal_note,
  reversal.ledger_seq_before as reversal_ledger_seq_before,
  reversal.ledger_seq_after as reversal_ledger_seq_after
from operations.opening_balance_cutovers cutover
left join operations.opening_balance_active_cutovers active
  on active.organization_id = cutover.organization_id
 and active.cutover_id = cutover.id
left join operations.opening_balance_cutover_reversals reversal
  on reversal.organization_id = cutover.organization_id
 and reversal.opening_balance_cutover_id = cutover.id
cross join lateral (
  select count(*)::bigint as verified_line_count
  from operations.opening_balance_verification_applications application
  where application.organization_id = cutover.organization_id
    and application.opening_balance_cutover_id = cutover.id
) verification;

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
    when application.id is not null then 'VERIFIED'
    else 'UNVERIFIED'
  end as verification_status_code,
  application.id as verification_application_id,
  application.stocktake_id as verifying_stocktake_id,
  application.stocktake_approval_id as verifying_stocktake_approval_id,
  application.approval_version_no as verifying_approval_version_no,
  application.stocktake_posting_id as verifying_stocktake_posting_id,
  application.stocktake_posting_line_id as verifying_stocktake_posting_line_id,
  application.stocktake_line_id as verifying_stocktake_line_id,
  application.count_attempt_id as verifying_count_attempt_id,
  application.physical_quantity as verifying_physical_quantity,
  application.stocktake_variance_quantity as verifying_variance_quantity,
  application.verified_at,
  count_attempt.counted_at as verifying_counted_at,
  posting_line.ledger_entry_id as verifying_adjustment_ledger_entry_id,
  stocktake.stocktake_no as verifying_stocktake_no,
  case
    when reversal.id is not null then 'REVERSED'
    when active.cutover_id is not null then 'ACTIVE'
    else cutover.status_code
  end as cutover_operational_status_code,
  reversal.id as reversal_record_id,
  reversal.reversal_transaction_id,
  reversal.reversed_at
from operations.opening_balance_cutover_lines line
join operations.opening_balance_cutovers cutover
  on cutover.organization_id = line.organization_id
 and cutover.id = line.cutover_id
left join operations.opening_balance_active_cutovers active
  on active.organization_id = cutover.organization_id
 and active.cutover_id = cutover.id
left join operations.opening_balance_cutover_reversals reversal
  on reversal.organization_id = cutover.organization_id
 and reversal.opening_balance_cutover_id = cutover.id
left join operations.opening_balance_verification_applications application
  on application.organization_id = line.organization_id
 and application.opening_balance_line_id = line.id
left join operations.stocktake_count_attempts count_attempt
  on count_attempt.organization_id = application.organization_id
 and count_attempt.stocktake_line_id = application.stocktake_line_id
 and count_attempt.id = application.count_attempt_id
left join operations.stocktake_posting_lines posting_line
  on posting_line.id = application.stocktake_posting_line_id
left join operations.stocktakes stocktake
  on stocktake.organization_id = application.organization_id
 and stocktake.id = application.stocktake_id;

create or replace view api.opening_balance_active_cutovers
with (security_invoker = true, security_barrier = true)
as
select
  active.organization_id,
  active.cutover_id,
  cutover.cutover_no,
  cutover.transaction_id,
  active.activated_at,
  active.activated_by,
  active.process_name,
  active.activation_rule_version,
  active.created_at
from operations.opening_balance_active_cutovers active
join operations.opening_balance_cutovers cutover
  on cutover.organization_id = active.organization_id
 and cutover.id = active.cutover_id;

create or replace view api.opening_balance_cutover_reversals
with (security_invoker = true, security_barrier = true)
as
select
  reversal.id as reversal_record_id,
  reversal.organization_id,
  reversal.opening_balance_cutover_id,
  cutover.cutover_no,
  reversal.original_transaction_id,
  original_transaction.transaction_no as original_transaction_no,
  reversal.reversal_transaction_id,
  reversal_transaction.transaction_no as reversal_transaction_no,
  reversal.idempotency_command_id,
  reversal.preview_basis_hash,
  reversal.ledger_seq_before,
  reversal.ledger_seq_after,
  reversal.line_count,
  reversal.total_absolute_quantity,
  reversal.reversed_at,
  reversal.reversed_by,
  reversal.process_name,
  reversal.note,
  reversal.metadata,
  reversal.created_at
from operations.opening_balance_cutover_reversals reversal
join operations.opening_balance_cutovers cutover
  on cutover.organization_id = reversal.organization_id
 and cutover.id = reversal.opening_balance_cutover_id
join inventory.stock_transactions original_transaction
  on original_transaction.organization_id = reversal.organization_id
 and original_transaction.id = reversal.original_transaction_id
join inventory.stock_transactions reversal_transaction
  on reversal_transaction.organization_id = reversal.organization_id
 and reversal_transaction.id = reversal.reversal_transaction_id;

revoke all
on api.opening_balance_cutovers,
   api.opening_balance_cutover_lines,
   api.opening_balance_active_cutovers,
   api.opening_balance_cutover_reversals
from public, anon;

grant select
on api.opening_balance_cutovers,
   api.opening_balance_cutover_lines,
   api.opening_balance_active_cutovers,
   api.opening_balance_cutover_reversals
to authenticated, service_role;

comment on table operations.opening_balance_active_cutovers
is 'Current organization-scoped opening-balance pointer. Historical posted cutovers remain immutable; a completed exact reversal removes only this operational pointer.';

comment on table operations.opening_balance_cutover_reversals
is 'Immutable audit record for one exact full reversal of a posted opening-balance cutover.';

comment on function inventory.preview_opening_balance_reversal_core(uuid, uuid, boolean)
is 'Authoritative exact opening-balance reversal preview. It never uses FEFO or substitutes product, batch, bucket, or quantity.';

comment on function api.reverse_opening_balance_cutover(uuid, text, uuid, text, boolean, text, jsonb)
is 'Atomically reverses every positive INITIAL_BALANCE line, preserves verification history, and releases the active-cutover pointer for a replacement cutover.';

commit;
