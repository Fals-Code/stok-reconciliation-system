begin;

insert into catalog.movement_reasons (
  id,
  code,
  name,
  direction_code,
  requires_note,
  is_system,
  is_active
)
values (
  '20000000-0000-4000-8000-000000000018'::uuid,
  'STOCKTAKE_ADJUSTMENT',
  'Koreksi Hasil Stok Opname',
  'ADJUSTMENT',
  true,
  true,
  true
)
on conflict (code) do update
set
  name = excluded.name,
  direction_code = excluded.direction_code,
  requires_note = excluded.requires_note,
  is_system = excluded.is_system,
  is_active = excluded.is_active;

create table operations.stocktake_postings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  stocktake_id uuid not null,
  approval_id uuid not null,
  approval_version_no bigint not null,
  transaction_id uuid not null
    references inventory.stock_transactions(id) on delete restrict,
  reconciliation_run_id uuid not null,
  posting_ledger_seq_before bigint not null,
  posting_ledger_seq_after bigint not null,
  line_count bigint not null,
  nonzero_line_count bigint not null,
  net_adjustment_qty bigint not null,
  total_absolute_adjustment_qty bigint not null,
  posted_at timestamptz not null,
  posted_by uuid null references auth.users(id) on delete set null,
  process_name text null,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  note text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),

  constraint uq_stocktake_postings_org_stocktake_id
    unique (organization_id, stocktake_id, id),

  constraint fk_stocktake_postings_stocktake
    foreign key (organization_id, stocktake_id)
    references operations.stocktakes(organization_id, id)
    on delete restrict,

  constraint fk_stocktake_postings_approval
    foreign key (organization_id, stocktake_id, approval_id)
    references operations.stocktake_approvals(
      organization_id,
      stocktake_id,
      id
    )
    on delete restrict,

  constraint fk_stocktake_postings_reconciliation
    foreign key (organization_id, reconciliation_run_id)
    references reconciliation.runs(organization_id, id)
    on delete restrict,

  constraint uq_stocktake_postings_session
    unique (stocktake_id),

  constraint uq_stocktake_postings_transaction
    unique (transaction_id),

  constraint uq_stocktake_postings_reconciliation
    unique (reconciliation_run_id),

  constraint uq_stocktake_postings_idempotency
    unique (idempotency_command_id),

  constraint ck_stocktake_postings_approval_version
    check (approval_version_no > 0),

  constraint ck_stocktake_postings_ledger_boundaries
    check (
      posting_ledger_seq_before >= 0
      and posting_ledger_seq_after >= posting_ledger_seq_before
    ),

  constraint ck_stocktake_postings_counts
    check (
      line_count > 0
      and nonzero_line_count >= 0
      and nonzero_line_count <= line_count
    ),

  constraint ck_stocktake_postings_absolute_qty
    check (total_absolute_adjustment_qty >= 0),

  constraint ck_stocktake_postings_actor_xor_process
    check ((posted_by is not null) <> (process_name is not null)),

  constraint ck_stocktake_postings_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),

  constraint ck_stocktake_postings_note_length
    check (note is null or length(note) <= 2000),

  constraint ck_stocktake_postings_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create table operations.stocktake_posting_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  stocktake_id uuid not null,
  posting_id uuid not null,
  approval_line_id uuid not null,
  stocktake_line_id uuid not null,
  line_no integer not null,
  product_id uuid not null,
  batch_id uuid not null,
  bucket_code text not null,
  reason_code text null,
  adjustment_qty bigint not null,
  current_ledger_qty_before bigint not null,
  current_ledger_qty_after bigint not null,
  ledger_entry_id uuid null
    references inventory.stock_ledger_entries(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),

  constraint fk_stocktake_posting_lines_posting
    foreign key (organization_id, stocktake_id, posting_id)
    references operations.stocktake_postings(
      organization_id,
      stocktake_id,
      id
    )
    on delete restrict,

  constraint fk_stocktake_posting_lines_approval_line
    foreign key (approval_line_id)
    references operations.stocktake_approval_lines(id)
    on delete restrict,

  constraint fk_stocktake_posting_lines_stocktake_line
    foreign key (organization_id, stocktake_id, stocktake_line_id)
    references operations.stocktake_lines(
      organization_id,
      stocktake_id,
      id
    )
    on delete restrict,

  constraint fk_stocktake_posting_lines_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches(
      organization_id,
      product_id,
      id
    )
    on delete restrict,

  constraint uq_stocktake_posting_lines_number
    unique (posting_id, line_no),

  constraint uq_stocktake_posting_lines_approval
    unique (posting_id, approval_line_id),

  constraint uq_stocktake_posting_lines_stocktake_line
    unique (posting_id, stocktake_line_id),

  constraint uq_stocktake_posting_lines_ledger
    unique (ledger_entry_id),

  constraint ck_stocktake_posting_lines_number
    check (line_no > 0),

  constraint ck_stocktake_posting_lines_bucket
    check (bucket_code in ('SELLABLE', 'QUARANTINE', 'DAMAGED')),

  constraint ck_stocktake_posting_lines_quantity
    check (
      current_ledger_qty_before >= 0
      and current_ledger_qty_after >= 0
      and current_ledger_qty_after =
        current_ledger_qty_before + adjustment_qty
    ),

  constraint ck_stocktake_posting_lines_effect
    check (
      (
        adjustment_qty = 0
        and reason_code is null
        and ledger_entry_id is null
      )
      or
      (
        adjustment_qty <> 0
        and reason_code is not null
        and btrim(reason_code) <> ''
        and ledger_entry_id is not null
      )
    )
);

create index idx_stocktake_postings_session
on operations.stocktake_postings (
  organization_id,
  stocktake_id,
  posted_at desc,
  id
);

create index idx_stocktake_posting_lines_posting
on operations.stocktake_posting_lines (
  organization_id,
  posting_id,
  line_no,
  id
);

create index idx_stocktake_posting_lines_entity
on operations.stocktake_posting_lines (
  organization_id,
  product_id,
  batch_id,
  bucket_code,
  created_at desc,
  id
);

create unique index uidx_stocktakes_stock_transaction
on operations.stocktakes(stock_transaction_id)
where stock_transaction_id is not null;

create unique index uidx_stocktakes_reconciliation_run
on operations.stocktakes(reconciliation_run_id)
where reconciliation_run_id is not null;

create trigger trg_stocktake_postings_immutable
before update or delete on operations.stocktake_postings
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_stocktake_posting_lines_immutable
before update or delete on operations.stocktake_posting_lines
for each row execute function inventory.reject_immutable_mutation();

alter table operations.stocktake_postings enable row level security;
alter table operations.stocktake_posting_lines enable row level security;

create policy stocktake_postings_read_current_org
on operations.stocktake_postings
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stocktake_posting_lines_read_current_org
on operations.stocktake_posting_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all
on operations.stocktake_postings,
   operations.stocktake_posting_lines
from public, anon, authenticated;

grant select
on operations.stocktake_postings,
   operations.stocktake_posting_lines
to authenticated, service_role;

create or replace function reconciliation.run_post_stocktake_projection_checks(
  p_organization_id uuid,
  p_stocktake_id uuid,
  p_approval_version bigint,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  inventory,
  operations,
  reconciliation,
  api
as $$
declare
  v_idempotency_key text;
  v_metadata jsonb;
  v_response jsonb;
  v_run_id uuid;
  v_recorded_at timestamptz := clock_timestamp();
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_stocktake_id is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_ID_REQUIRED';
  end if;

  if p_approval_version is null or p_approval_version <= 0 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_APPROVAL_VERSION_REQUIRED';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'RECONCILIATION_METADATA_MUST_BE_OBJECT';
  end if;

  v_idempotency_key :=
    'stocktake:' ||
    p_stocktake_id::text ||
    ':reconciliation:' ||
    p_approval_version::text;

  select api.run_reconciliation(
    p_organization_id,
    v_idempotency_key,
    array[
      'LEDGER_BATCH_PROJECTION',
      'BATCH_PRODUCT_PROJECTION'
    ]::text[],
    '{}'::jsonb,
    v_metadata || jsonb_build_object(
      'stocktakeId', p_stocktake_id,
      'approvalVersion', p_approval_version,
      'trigger', 'POST_STOCKTAKE'
    )
  )
  into v_response;

  v_run_id := (v_response ->> 'runId')::uuid;

  update reconciliation.runs run
  set
    run_type_code = 'POST_STOCKTAKE',
    trigger_code = 'SYSTEM',
    actor_user_id = null,
    process_name = 'reconciliation.run_post_stocktake_projection_checks',
    metadata = run.metadata || jsonb_build_object(
      'stocktakeId', p_stocktake_id,
      'approvalVersion', p_approval_version,
      'classifiedAt', v_recorded_at
    ),
    updated_at = greatest(run.updated_at, v_recorded_at)
  where run.organization_id = p_organization_id
    and run.id = v_run_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'POST_STOCKTAKE_RECONCILIATION_NOT_FOUND';
  end if;

  v_response := v_response || jsonb_build_object(
    'runType', 'POST_STOCKTAKE',
    'triggerCode', 'SYSTEM',
    'stocktakeId', p_stocktake_id,
    'approvalVersion', p_approval_version
  );

  update inventory.idempotency_commands command
  set response_snapshot = v_response
  where command.organization_id = p_organization_id
    and command.scope = 'RUN_RECONCILIATION'
    and command.key = v_idempotency_key
    and command.status_code = 'SUCCEEDED';

  return v_response;
end;
$$;

revoke all
on function reconciliation.run_post_stocktake_projection_checks(
  uuid,
  uuid,
  bigint,
  jsonb
)
from public, anon, authenticated, service_role;

create or replace function api.post_stocktake_adjustment(
  p_organization_id uuid,
  p_idempotency_key text,
  p_stocktake_id uuid,
  p_approval_version bigint,
  p_confirmation boolean,
  p_note text default null,
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
  reconciliation,
  extensions
as $$
declare
  v_command_scope constant text := 'POST_STOCKTAKE_ADJUSTMENT';
  v_idempotency_key text;
  v_expected_idempotency_key text;
  v_note text;
  v_transaction_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_stocktake operations.stocktakes%rowtype;
  v_approval operations.stocktake_approvals%rowtype;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_created_by_role_code text;
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_organization_timezone text;
  v_reason_id uuid;
  v_channel_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_transaction_id uuid := gen_random_uuid();
  v_posting_id uuid := gen_random_uuid();
  v_correlation_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_effective_local_date date;
  v_transaction_no text;
  v_posting_ledger_seq_before bigint;
  v_posting_ledger_seq_after bigint;
  v_line record;
  v_ledger_entry_id uuid;
  v_ledger_seq bigint;
  v_reconciliation_response jsonb;
  v_reconciliation_run_id uuid;
  v_line_count bigint;
  v_nonzero_line_count bigint;
  v_net_adjustment_qty bigint;
  v_total_absolute_adjustment_qty bigint;
  v_posting_stocktake_version bigint;
  v_final_stocktake_version bigint;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_stocktake_id is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_ID_REQUIRED';
  end if;

  if p_approval_version is null or p_approval_version <= 0 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_APPROVAL_VERSION_REQUIRED';
  end if;

  if not coalesce(p_confirmation, false) then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_POST_CONFIRMATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_expected_idempotency_key :=
    'stocktake:' ||
    p_stocktake_id::text ||
    ':post:' ||
    p_approval_version::text;

  if v_idempotency_key <> v_expected_idempotency_key then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_POST_IDEMPOTENCY_KEY_INVALID';
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');

  if v_note is not null and length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_POST_NOTE_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_METADATA_MUST_BE_OBJECT';
  end if;

  select organization.timezone
  into v_organization_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_NOT_FOUND';
  end if;

  if v_jwt_role = 'anon'
     or (
       v_jwt_role = 'authenticated'
       and v_actor_user_id is null
     ) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id()
          is distinct from p_organization_id then
      raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
    end if;

    v_process_name := null;
    v_created_by_role_code := 'ADMIN';
  else
    v_process_name := 'api.post_stocktake_adjustment';
    v_created_by_role_code := 'SYSTEM_PROCESS';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'stocktakeId', p_stocktake_id,
          'approvalVersion', p_approval_version,
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

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text ||
      ':' ||
      v_command_scope ||
      ':' ||
      v_idempotency_key,
      0::bigint
    )
  );

  select command.*
  into v_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id
    and command.scope = v_command_scope
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
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;

    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text ||
      ':STOCKTAKE:' ||
      p_stocktake_id::text,
      0::bigint
    )
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text ||
      ':STOCKTAKE_POSTING',
      0::bigint
    )
  );

  select stocktake.*
  into v_stocktake
  from operations.stocktakes stocktake
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_NOT_FOUND';
  end if;

  if v_stocktake.status_code <> 'APPROVED' then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_POST_INVALID_STATE';
  end if;

  if v_stocktake.approval_version_no is distinct from p_approval_version
     or v_stocktake.current_approval_id is null then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_APPROVAL_VERSION_CONFLICT';
  end if;

  select approval.*
  into v_approval
  from operations.stocktake_approvals approval
  where approval.organization_id = p_organization_id
    and approval.stocktake_id = p_stocktake_id
    and approval.id = v_stocktake.current_approval_id
    and approval.approval_version_no = p_approval_version
  for share;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_APPROVAL_NOT_FOUND';
  end if;

  if v_stocktake.version_no <> v_approval.stocktake_version_no + 1 then
    raise exception using errcode = 'P0001', message = 'STALE_STOCKTAKE_BASIS';
  end if;

  if exists (
    select 1
    from operations.stocktake_approval_lines approval_line
    full join operations.stocktake_lines line
      on line.organization_id = approval_line.organization_id
     and line.stocktake_id = approval_line.stocktake_id
     and line.id = approval_line.stocktake_line_id
    where coalesce(
      approval_line.organization_id,
      line.organization_id
    ) = p_organization_id
      and coalesce(
        approval_line.stocktake_id,
        line.stocktake_id
      ) = p_stocktake_id
      and (
        approval_line.id is null
        or line.id is null
        or line.version_no <> approval_line.line_version_no
        or line.final_attempt_id <> approval_line.final_attempt_id
        or line.final_physical_qty <> approval_line.final_physical_qty
        or line.expected_qty_at_count <> approval_line.expected_qty_at_count
        or line.variance_qty <> approval_line.variance_qty
        or line.reason_code is distinct from approval_line.reason_code
        or line.review_note is distinct from approval_line.review_note
        or line.expected_formula_version <>
          approval_line.expected_formula_version
        or line.count_cutoff_ledger_seq <>
          approval_line.count_cutoff_ledger_seq
        or line.review_decision_code <>
          approval_line.review_decision_code
        or line.review_status_code <> 'REVIEWED'
        or line.exception_code is not null
      )
  ) then
    raise exception using errcode = 'P0001', message = 'STALE_STOCKTAKE_BASIS';
  end if;

  if exists (
    select 1
    from inventory.stock_transactions transaction
    where transaction.organization_id = p_organization_id
      and transaction.source_type_code = 'STOCKTAKE'
      and transaction.source_id = p_stocktake_id
  ) then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_ALREADY_POSTED';
  end if;

  select reason.id
  into v_reason_id
  from catalog.movement_reasons reason
  where reason.code = 'STOCKTAKE_ADJUSTMENT'
    and reason.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_ADJUSTMENT_REASON_NOT_CONFIGURED';
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = 'SYSTEM'
    and channel.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_SYSTEM_CHANNEL_NOT_CONFIGURED';
  end if;

  perform product.id
  from catalog.products product
  join (
    select distinct line.product_id
    from operations.stocktake_approval_lines approval_line
    join operations.stocktake_lines line
      on line.organization_id = approval_line.organization_id
     and line.stocktake_id = approval_line.stocktake_id
     and line.id = approval_line.stocktake_line_id
    where approval_line.organization_id = p_organization_id
      and approval_line.stocktake_id = p_stocktake_id
      and approval_line.approval_id = v_approval.id
  ) affected
    on affected.product_id = product.id
  where product.organization_id = p_organization_id
  order by product.id
  for update of product;

  perform batch.id
  from catalog.product_batches batch
  join (
    select distinct
      line.product_id,
      line.batch_id
    from operations.stocktake_approval_lines approval_line
    join operations.stocktake_lines line
      on line.organization_id = approval_line.organization_id
     and line.stocktake_id = approval_line.stocktake_id
     and line.id = approval_line.stocktake_line_id
    where approval_line.organization_id = p_organization_id
      and approval_line.stocktake_id = p_stocktake_id
      and approval_line.approval_id = v_approval.id
  ) affected
    on affected.product_id = batch.product_id
   and affected.batch_id = batch.id
  where batch.organization_id = p_organization_id
  order by batch.product_id, batch.id
  for update of batch;

  perform balance.batch_id
  from inventory.stock_batch_balances balance
  join (
    select distinct
      line.product_id,
      line.batch_id
    from operations.stocktake_approval_lines approval_line
    join operations.stocktake_lines line
      on line.organization_id = approval_line.organization_id
     and line.stocktake_id = approval_line.stocktake_id
     and line.id = approval_line.stocktake_line_id
    where approval_line.organization_id = p_organization_id
      and approval_line.stocktake_id = p_stocktake_id
      and approval_line.approval_id = v_approval.id
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
    from operations.stocktake_approval_lines approval_line
    join operations.stocktake_lines line
      on line.organization_id = approval_line.organization_id
     and line.stocktake_id = approval_line.stocktake_id
     and line.id = approval_line.stocktake_line_id
    where approval_line.organization_id = p_organization_id
      and approval_line.stocktake_id = p_stocktake_id
      and approval_line.approval_id = v_approval.id
  ) affected
    on affected.product_id = position.product_id
  where position.organization_id = p_organization_id
  order by position.product_id
  for update of position;

  if exists (
    with affected as (
      select distinct
        line.product_id,
        line.batch_id
      from operations.stocktake_approval_lines approval_line
      join operations.stocktake_lines line
        on line.organization_id = approval_line.organization_id
       and line.stocktake_id = approval_line.stocktake_id
       and line.id = approval_line.stocktake_line_id
      where approval_line.organization_id = p_organization_id
        and approval_line.stocktake_id = p_stocktake_id
        and approval_line.approval_id = v_approval.id
    ),
    ledger as (
      select
        affected.product_id,
        affected.batch_id,
        coalesce(
          sum(entry.quantity_delta)
            filter (where entry.bucket_code = 'SELLABLE'),
          0
        )::bigint as sellable_qty,
        coalesce(
          sum(entry.quantity_delta)
            filter (where entry.bucket_code = 'QUARANTINE'),
          0
        )::bigint as quarantine_qty,
        coalesce(
          sum(entry.quantity_delta)
            filter (where entry.bucket_code = 'DAMAGED'),
          0
        )::bigint as damaged_qty
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
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_PROJECTION_DRIFT';
  end if;

  if exists (
    with affected as (
      select distinct line.product_id
      from operations.stocktake_approval_lines approval_line
      join operations.stocktake_lines line
        on line.organization_id = approval_line.organization_id
       and line.stocktake_id = approval_line.stocktake_id
       and line.id = approval_line.stocktake_line_id
      where approval_line.organization_id = p_organization_id
        and approval_line.stocktake_id = p_stocktake_id
        and approval_line.approval_id = v_approval.id
    ),
    ledger as (
      select
        affected.product_id,
        coalesce(
          sum(entry.quantity_delta)
            filter (where entry.bucket_code = 'SELLABLE'),
          0
        )::bigint as sellable_qty,
        coalesce(
          sum(entry.quantity_delta)
            filter (where entry.bucket_code = 'QUARANTINE'),
          0
        )::bigint as quarantine_qty,
        coalesce(
          sum(entry.quantity_delta)
            filter (where entry.bucket_code = 'DAMAGED'),
          0
        )::bigint as damaged_qty
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
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_PROJECTION_DRIFT';
  end if;

  if exists (
    select 1
    from operations.stocktake_approval_lines approval_line
    join operations.stocktake_lines line
      on line.organization_id = approval_line.organization_id
     and line.stocktake_id = approval_line.stocktake_id
     and line.id = approval_line.stocktake_line_id
    where approval_line.organization_id = p_organization_id
      and approval_line.stocktake_id = p_stocktake_id
      and approval_line.approval_id = v_approval.id
      and (
        select coalesce(sum(entry.quantity_delta), 0)::bigint
        from inventory.stock_ledger_entries entry
        where entry.organization_id = p_organization_id
          and entry.product_id = line.product_id
          and entry.batch_id = line.batch_id
          and entry.bucket_code = line.bucket_code
      ) + approval_line.variance_qty < 0
  ) then
    raise exception using errcode = 'P0001', message = 'STALE_STOCKTAKE_BASIS';
  end if;

  if exists (
    select 1
    from inventory.stock_product_positions position
    join (
      select
        line.product_id,
        coalesce(
          sum(approval_line.variance_qty)
            filter (where line.bucket_code = 'SELLABLE'),
          0
        )::bigint as sellable_adjustment
      from operations.stocktake_approval_lines approval_line
      join operations.stocktake_lines line
        on line.organization_id = approval_line.organization_id
       and line.stocktake_id = approval_line.stocktake_id
       and line.id = approval_line.stocktake_line_id
      where approval_line.organization_id = p_organization_id
        and approval_line.stocktake_id = p_stocktake_id
        and approval_line.approval_id = v_approval.id
      group by line.product_id
    ) adjustment
      on adjustment.product_id = position.product_id
    where position.organization_id = p_organization_id
      and position.sellable_qty + adjustment.sellable_adjustment
          < position.reserved_qty
  ) then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_RESERVED_CONFLICT';
  end if;

  select
    count(*),
    count(*) filter (where approval_line.variance_qty <> 0),
    coalesce(sum(approval_line.variance_qty), 0)::bigint,
    coalesce(sum(abs(approval_line.variance_qty)), 0)::bigint
  into
    v_line_count,
    v_nonzero_line_count,
    v_net_adjustment_qty,
    v_total_absolute_adjustment_qty
  from operations.stocktake_approval_lines approval_line
  where approval_line.organization_id = p_organization_id
    and approval_line.stocktake_id = p_stocktake_id
    and approval_line.approval_id = v_approval.id;

  if v_line_count = 0 then
    raise exception using errcode = 'P0001', message = 'STOCKTAKE_APPROVAL_REQUIRED';
  end if;

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
  )
  values (
    v_command_id,
    p_organization_id,
    v_command_scope,
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

  v_posting_stocktake_version := v_stocktake.version_no + 1;

  update operations.stocktakes stocktake
  set
    status_code = 'POSTING',
    updated_at = v_recorded_at,
    version_no = v_posting_stocktake_version
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id;

  select coalesce(max(entry.ledger_seq), 0)::bigint
  into v_posting_ledger_seq_before
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  v_effective_local_date :=
    (v_recorded_at at time zone v_organization_timezone)::date;

  v_transaction_no :=
    'STK-' ||
    to_char(v_effective_local_date, 'YYYYMMDD') ||
    '-' ||
    upper(
      substr(
        replace(v_transaction_id::text, '-', ''),
        1,
        8
      )
    );

  v_transaction_note := coalesce(
    v_note,
    'Stocktake adjustment ' ||
    v_stocktake.stocktake_no ||
    ' approval ' ||
    p_approval_version::text
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
  )
  values (
    v_transaction_id,
    p_organization_id,
    v_transaction_no,
    'STOCKTAKE_ADJUSTMENT',
    v_reason_id,
    'STOCKTAKE_ADJUSTMENT',
    v_channel_id,
    'SYSTEM',
    'STOCKTAKE',
    p_stocktake_id,
    v_stocktake.stocktake_no,
    v_recorded_at,
    v_recorded_at,
    v_effective_local_date,
    v_actor_user_id,
    v_process_name,
    v_created_by_role_code,
    v_correlation_id,
    v_command_id,
    null,
    v_transaction_note,
    v_metadata || jsonb_build_object(
      'stocktakeId', p_stocktake_id,
      'stocktakeNo', v_stocktake.stocktake_no,
      'approvalId', v_approval.id,
      'approvalVersion', p_approval_version,
      'approvalHash', v_approval.approval_hash,
      'postingLedgerSeqBefore', v_posting_ledger_seq_before,
      'lineReasons', (
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'stocktakeLineId', approval_line.stocktake_line_id,
              'reasonCode', approval_line.reason_code,
              'adjustmentQty', approval_line.variance_qty
            )
            order by approval_line.line_no
          ),
          '[]'::jsonb
        )
        from operations.stocktake_approval_lines approval_line
        where approval_line.organization_id = p_organization_id
          and approval_line.stocktake_id = p_stocktake_id
          and approval_line.approval_id = v_approval.id
      )
    ),
    1
  );

  for v_line in
    select
      approval_line.id as approval_line_id,
      approval_line.stocktake_line_id,
      approval_line.line_no,
      line.product_id,
      line.batch_id,
      line.bucket_code,
      line.product_sku_snapshot,
      line.batch_code_snapshot,
      line.expiry_date_snapshot,
      approval_line.reason_code,
      approval_line.variance_qty
    from operations.stocktake_approval_lines approval_line
    join operations.stocktake_lines line
      on line.organization_id = approval_line.organization_id
     and line.stocktake_id = approval_line.stocktake_id
     and line.id = approval_line.stocktake_line_id
    where approval_line.organization_id = p_organization_id
      and approval_line.stocktake_id = p_stocktake_id
      and approval_line.approval_id = v_approval.id
      and approval_line.variance_qty <> 0
    order by
      line.product_id,
      line.batch_id,
      line.bucket_code,
      approval_line.line_no
  loop
    v_ledger_entry_id := gen_random_uuid();

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
    )
    values (
      v_ledger_entry_id,
      p_organization_id,
      v_transaction_id,
      v_line.line_no,
      v_line.product_id,
      v_line.batch_id,
      v_line.product_sku_snapshot,
      v_line.batch_code_snapshot,
      v_line.expiry_date_snapshot,
      v_line.bucket_code,
      v_line.variance_qty,
      'ADJUSTMENT',
      null,
      v_line.stocktake_line_id::text,
      v_recorded_at,
      v_recorded_at,
      v_recorded_at
    )
    returning ledger_seq into v_ledger_seq;

    update inventory.stock_batch_balances balance
    set
      sellable_qty =
        balance.sellable_qty
        + case
            when v_line.bucket_code = 'SELLABLE'
              then v_line.variance_qty
            else 0
          end,
      quarantine_qty =
        balance.quarantine_qty
        + case
            when v_line.bucket_code = 'QUARANTINE'
              then v_line.variance_qty
            else 0
          end,
      damaged_qty =
        balance.damaged_qty
        + case
            when v_line.bucket_code = 'DAMAGED'
              then v_line.variance_qty
            else 0
          end,
      last_ledger_seq = greatest(
        balance.last_ledger_seq,
        v_ledger_seq
      ),
      updated_at = v_recorded_at,
      version = balance.version + 1
    where balance.organization_id = p_organization_id
      and balance.batch_id = v_line.batch_id
      and balance.product_id = v_line.product_id;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'STOCKTAKE_PROJECTION_DRIFT';
    end if;

    update inventory.stock_product_positions position
    set
      sellable_qty =
        position.sellable_qty
        + case
            when v_line.bucket_code = 'SELLABLE'
              then v_line.variance_qty
            else 0
          end,
      quarantine_qty =
        position.quarantine_qty
        + case
            when v_line.bucket_code = 'QUARANTINE'
              then v_line.variance_qty
            else 0
          end,
      damaged_qty =
        position.damaged_qty
        + case
            when v_line.bucket_code = 'DAMAGED'
              then v_line.variance_qty
            else 0
          end,
      last_ledger_seq = greatest(
        position.last_ledger_seq,
        v_ledger_seq
      ),
      updated_at = v_recorded_at,
      version = position.version + 1
    where position.organization_id = p_organization_id
      and position.product_id = v_line.product_id;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'STOCKTAKE_PROJECTION_DRIFT';
    end if;
  end loop;

  select coalesce(max(entry.ledger_seq), 0)::bigint
  into v_posting_ledger_seq_after
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  select reconciliation.run_post_stocktake_projection_checks(
    p_organization_id,
    p_stocktake_id,
    p_approval_version,
    v_metadata || jsonb_build_object(
      'transactionId', v_transaction_id,
      'postingLedgerSeqBefore', v_posting_ledger_seq_before,
      'postingLedgerSeqAfter', v_posting_ledger_seq_after
    )
  )
  into v_reconciliation_response;

  v_reconciliation_run_id :=
    (v_reconciliation_response ->> 'runId')::uuid;

  insert into operations.stocktake_postings (
    id,
    organization_id,
    stocktake_id,
    approval_id,
    approval_version_no,
    transaction_id,
    reconciliation_run_id,
    posting_ledger_seq_before,
    posting_ledger_seq_after,
    line_count,
    nonzero_line_count,
    net_adjustment_qty,
    total_absolute_adjustment_qty,
    posted_at,
    posted_by,
    process_name,
    idempotency_command_id,
    note,
    metadata,
    created_at
  )
  values (
    v_posting_id,
    p_organization_id,
    p_stocktake_id,
    v_approval.id,
    p_approval_version,
    v_transaction_id,
    v_reconciliation_run_id,
    v_posting_ledger_seq_before,
    v_posting_ledger_seq_after,
    v_line_count,
    v_nonzero_line_count,
    v_net_adjustment_qty,
    v_total_absolute_adjustment_qty,
    v_recorded_at,
    v_actor_user_id,
    v_process_name,
    v_command_id,
    v_note,
    v_metadata || jsonb_build_object(
      'reconciliationIntegrityStatus',
      v_reconciliation_response ->> 'integrityStatus'
    ),
    v_recorded_at
  );

  insert into operations.stocktake_posting_lines (
    organization_id,
    stocktake_id,
    posting_id,
    approval_line_id,
    stocktake_line_id,
    line_no,
    product_id,
    batch_id,
    bucket_code,
    reason_code,
    adjustment_qty,
    current_ledger_qty_before,
    current_ledger_qty_after,
    ledger_entry_id,
    created_at
  )
  select
    p_organization_id,
    p_stocktake_id,
    v_posting_id,
    approval_line.id,
    approval_line.stocktake_line_id,
    approval_line.line_no,
    line.product_id,
    line.batch_id,
    line.bucket_code,
    case
      when approval_line.variance_qty = 0 then null
      else approval_line.reason_code
    end,
    approval_line.variance_qty,
    (
      select coalesce(sum(entry_before.quantity_delta), 0)::bigint
      from inventory.stock_ledger_entries entry_before
      where entry_before.organization_id = p_organization_id
        and entry_before.product_id = line.product_id
        and entry_before.batch_id = line.batch_id
        and entry_before.bucket_code = line.bucket_code
        and entry_before.ledger_seq <= v_posting_ledger_seq_before
    ),
    (
      select coalesce(sum(entry_after.quantity_delta), 0)::bigint
      from inventory.stock_ledger_entries entry_after
      where entry_after.organization_id = p_organization_id
        and entry_after.product_id = line.product_id
        and entry_after.batch_id = line.batch_id
        and entry_after.bucket_code = line.bucket_code
        and entry_after.ledger_seq <= v_posting_ledger_seq_after
    ),
    ledger_entry.id,
    v_recorded_at
  from operations.stocktake_approval_lines approval_line
  join operations.stocktake_lines line
    on line.organization_id = approval_line.organization_id
   and line.stocktake_id = approval_line.stocktake_id
   and line.id = approval_line.stocktake_line_id
  left join inventory.stock_ledger_entries ledger_entry
    on ledger_entry.organization_id = p_organization_id
   and ledger_entry.transaction_id = v_transaction_id
   and ledger_entry.source_line_ref =
       approval_line.stocktake_line_id::text
  where approval_line.organization_id = p_organization_id
    and approval_line.stocktake_id = p_stocktake_id
    and approval_line.approval_id = v_approval.id
  order by approval_line.line_no;

  v_final_stocktake_version := v_posting_stocktake_version + 1;

  update operations.stocktakes stocktake
  set
    status_code = 'POSTED',
    posted_at = v_recorded_at,
    stock_transaction_id = v_transaction_id,
    reconciliation_run_id = v_reconciliation_run_id,
    metadata = stocktake.metadata || jsonb_build_object(
      'postingId', v_posting_id,
      'postingLedgerSeqBefore', v_posting_ledger_seq_before,
      'postingLedgerSeqAfter', v_posting_ledger_seq_after,
      'reconciliationIntegrityStatus',
      v_reconciliation_response ->> 'integrityStatus'
    ),
    updated_at = v_recorded_at,
    version_no = v_final_stocktake_version
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id;

  v_response := jsonb_build_object(
    'status', 'POSTED',
    'stocktakeId', p_stocktake_id,
    'stocktakeNo', v_stocktake.stocktake_no,
    'approvalId', v_approval.id,
    'approvalVersion', p_approval_version,
    'postingId', v_posting_id,
    'transactionId', v_transaction_id,
    'transactionNo', v_transaction_no,
    'reconciliationRunId', v_reconciliation_run_id,
    'reconciliationIntegrityStatus',
    v_reconciliation_response ->> 'integrityStatus',
    'postingLedgerSeqBefore', v_posting_ledger_seq_before,
    'postingLedgerSeqAfter', v_posting_ledger_seq_after,
    'lineCount', v_line_count,
    'nonzeroLineCount', v_nonzero_line_count,
    'netAdjustmentQty', v_net_adjustment_qty,
    'totalAbsoluteAdjustmentQty',
    v_total_absolute_adjustment_qty,
    'stocktakeVersion', v_final_stocktake_version,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'postedAt', v_recorded_at,
    'postedByUserId', v_actor_user_id,
    'postedByProcessName', v_process_name
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

grant usage on schema api to authenticated, service_role;

revoke all
on function api.post_stocktake_adjustment(
  uuid,
  text,
  uuid,
  bigint,
  boolean,
  text,
  jsonb
)
from public, anon;

grant execute
on function api.post_stocktake_adjustment(
  uuid,
  text,
  uuid,
  bigint,
  boolean,
  text,
  jsonb
)
to authenticated, service_role;

create or replace view api.stocktake_postings
with (security_invoker = true, security_barrier = true)
as
select
  posting.id as posting_id,
  posting.organization_id,
  posting.stocktake_id,
  posting.approval_id,
  posting.approval_version_no,
  posting.transaction_id,
  posting.reconciliation_run_id,
  posting.posting_ledger_seq_before,
  posting.posting_ledger_seq_after,
  posting.line_count,
  posting.nonzero_line_count,
  posting.net_adjustment_qty,
  posting.total_absolute_adjustment_qty,
  posting.posted_at,
  posting.posted_by,
  posting.process_name,
  posting.note,
  posting.metadata,
  posting.created_at
from operations.stocktake_postings posting;

create or replace view api.stocktake_posting_lines
with (security_invoker = true, security_barrier = true)
as
select
  posting_line.id as posting_line_id,
  posting_line.organization_id,
  posting_line.stocktake_id,
  posting_line.posting_id,
  posting_line.approval_line_id,
  posting_line.stocktake_line_id,
  posting_line.line_no,
  posting_line.product_id,
  posting_line.batch_id,
  posting_line.bucket_code,
  posting_line.reason_code,
  posting_line.adjustment_qty,
  posting_line.current_ledger_qty_before,
  posting_line.current_ledger_qty_after,
  posting_line.ledger_entry_id,
  posting_line.created_at
from operations.stocktake_posting_lines posting_line;

revoke all
on api.stocktake_postings,
   api.stocktake_posting_lines
from public, anon;

grant select
on api.stocktake_postings,
   api.stocktake_posting_lines
to authenticated, service_role;

alter default privileges in schema operations
revoke all on tables from anon, authenticated;

commit;
