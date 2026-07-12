begin;

create table inventory.idempotency_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  scope text not null,
  key text not null,
  request_hash text not null,
  status_code text not null default 'STARTED',
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz null,
  result_transaction_id uuid null,
  response_snapshot jsonb not null default '{}'::jsonb,
  error_code text null,
  expires_at timestamptz null,
  constraint uq_idempotency_commands_scope_key unique (organization_id, scope, key),
  constraint ck_idempotency_commands_scope_nonblank check (btrim(scope) <> ''),
  constraint ck_idempotency_commands_key_nonblank check (btrim(key) <> ''),
  constraint ck_idempotency_commands_hash check (request_hash ~ '^[0-9a-f]{64}$'),
  constraint ck_idempotency_commands_status check (
    status_code in ('STARTED', 'SUCCEEDED', 'FAILED')
  ),
  constraint ck_idempotency_commands_completion check (
    (status_code = 'STARTED' and completed_at is null)
    or (status_code in ('SUCCEEDED', 'FAILED') and completed_at is not null)
  )
);

create table inventory.stock_transactions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  transaction_no text not null,
  transaction_type_code text not null,
  reason_id uuid not null references catalog.movement_reasons(id) on delete restrict,
  reason_code_snapshot text not null,
  channel_id uuid not null references catalog.channels(id) on delete restrict,
  channel_code_snapshot text not null,
  source_type_code text not null,
  source_id uuid null,
  source_ref_snapshot text not null,
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default clock_timestamp(),
  effective_local_date date not null,
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  created_by_role_code text not null,
  correlation_id uuid not null default gen_random_uuid(),
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  reversal_of_transaction_id uuid null
    references inventory.stock_transactions(id) on delete restrict,
  note text null,
  metadata jsonb not null default '{}'::jsonb,
  schema_version integer not null default 1,
  constraint uq_stock_transactions_org_no unique (organization_id, transaction_no),
  constraint uq_stock_transactions_idempotency unique (idempotency_command_id),
  constraint ck_stock_transactions_no_nonblank check (btrim(transaction_no) <> ''),
  constraint ck_stock_transactions_type check (
    transaction_type_code in (
      'INITIAL_BALANCE',
      'RECEIPT',
      'MARKETPLACE_OUTBOUND',
      'MANUAL_OUTBOUND',
      'RETURN_RECEIPT',
      'RETURN_INSPECTION_TRANSFER',
      'DISPOSAL',
      'STOCKTAKE_ADJUSTMENT',
      'REVERSAL'
    )
  ),
  constraint ck_stock_transactions_reason_snapshot_nonblank
    check (btrim(reason_code_snapshot) <> ''),
  constraint ck_stock_transactions_channel_snapshot_nonblank
    check (btrim(channel_code_snapshot) <> ''),
  constraint ck_stock_transactions_source_type_nonblank
    check (btrim(source_type_code) <> ''),
  constraint ck_stock_transactions_source_ref_nonblank
    check (btrim(source_ref_snapshot) <> ''),
  constraint ck_stock_transactions_actor_xor_process
    check ((actor_user_id is not null) <> (process_name is not null)),
  constraint ck_stock_transactions_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),
  constraint ck_stock_transactions_role_nonblank
    check (btrim(created_by_role_code) <> ''),
  constraint ck_stock_transactions_schema_version_positive check (schema_version > 0),
  constraint ck_stock_transactions_reversal_not_self
    check (reversal_of_transaction_id is null or reversal_of_transaction_id <> id)
);

alter table inventory.idempotency_commands
add constraint fk_idempotency_commands_result_transaction
foreign key (result_transaction_id)
references inventory.stock_transactions(id)
on delete restrict;

create table inventory.stock_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  ledger_seq bigint generated always as identity,
  organization_id uuid not null,
  transaction_id uuid not null
    references inventory.stock_transactions(id) on delete restrict,
  line_no integer not null,
  product_id uuid not null,
  batch_id uuid not null,
  product_sku_snapshot text not null,
  batch_code_snapshot text not null,
  expiry_date_snapshot date not null,
  bucket_code text not null,
  quantity_delta bigint not null,
  entry_role_code text not null,
  pair_no integer null,
  source_line_ref text null,
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default now(),
  constraint uq_stock_ledger_entries_seq unique (ledger_seq),
  constraint uq_stock_ledger_entries_transaction_line unique (transaction_id, line_no),
  constraint fk_stock_ledger_entries_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches (organization_id, product_id, id)
    on delete restrict,
  constraint ck_stock_ledger_entries_line_positive check (line_no > 0),
  constraint ck_stock_ledger_entries_delta_nonzero check (quantity_delta <> 0),
  constraint ck_stock_ledger_entries_bucket check (
    bucket_code in ('SELLABLE', 'QUARANTINE', 'DAMAGED')
  ),
  constraint ck_stock_ledger_entries_role check (
    entry_role_code in (
      'SOURCE',
      'DESTINATION',
      'EXTERNAL_IN',
      'EXTERNAL_OUT',
      'ADJUSTMENT',
      'REVERSAL'
    )
  ),
  constraint ck_stock_ledger_entries_pair_positive check (pair_no is null or pair_no > 0),
  constraint ck_stock_ledger_entries_sku_nonblank check (btrim(product_sku_snapshot) <> ''),
  constraint ck_stock_ledger_entries_batch_nonblank check (btrim(batch_code_snapshot) <> '')
);

create table inventory.stock_batch_balances (
  organization_id uuid not null,
  batch_id uuid not null,
  product_id uuid not null,
  sellable_qty bigint not null default 0,
  quarantine_qty bigint not null default 0,
  damaged_qty bigint not null default 0,
  last_ledger_seq bigint not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  version bigint not null default 0,
  constraint pk_stock_batch_balances primary key (organization_id, batch_id),
  constraint fk_stock_batch_balances_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches (organization_id, product_id, id)
    on delete restrict,
  constraint ck_stock_batch_balances_sellable_nonnegative check (sellable_qty >= 0),
  constraint ck_stock_batch_balances_quarantine_nonnegative check (quarantine_qty >= 0),
  constraint ck_stock_batch_balances_damaged_nonnegative check (damaged_qty >= 0),
  constraint ck_stock_batch_balances_ledger_seq_nonnegative check (last_ledger_seq >= 0),
  constraint ck_stock_batch_balances_version_nonnegative check (version >= 0)
);

create table inventory.stock_product_positions (
  organization_id uuid not null,
  product_id uuid not null,
  sellable_qty bigint not null default 0,
  quarantine_qty bigint not null default 0,
  damaged_qty bigint not null default 0,
  reserved_qty bigint not null default 0,
  last_ledger_seq bigint not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  version bigint not null default 0,
  constraint pk_stock_product_positions primary key (organization_id, product_id),
  constraint fk_stock_product_positions_product
    foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,
  constraint ck_stock_product_positions_sellable_nonnegative check (sellable_qty >= 0),
  constraint ck_stock_product_positions_quarantine_nonnegative check (quarantine_qty >= 0),
  constraint ck_stock_product_positions_damaged_nonnegative check (damaged_qty >= 0),
  constraint ck_stock_product_positions_reserved_nonnegative check (reserved_qty >= 0),
  constraint ck_stock_product_positions_reserved_lte_sellable check (reserved_qty <= sellable_qty),
  constraint ck_stock_product_positions_ledger_seq_nonnegative check (last_ledger_seq >= 0),
  constraint ck_stock_product_positions_version_nonnegative check (version >= 0)
);

create table inventory.stock_reservations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  order_id uuid not null,
  order_item_id uuid not null,
  product_id uuid not null,
  reserved_qty bigint not null,
  consumed_qty bigint not null default 0,
  released_qty bigint not null default 0,
  status_code text not null default 'ACTIVE',
  reserved_at timestamptz not null default clock_timestamp(),
  closed_at timestamptz null,
  created_at timestamptz not null default now(),
  constraint uq_stock_reservations_order_item unique (order_item_id),
  constraint fk_stock_reservations_product
    foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,
  constraint ck_stock_reservations_reserved_positive check (reserved_qty > 0),
  constraint ck_stock_reservations_consumed_nonnegative check (consumed_qty >= 0),
  constraint ck_stock_reservations_released_nonnegative check (released_qty >= 0),
  constraint ck_stock_reservations_total check (
    consumed_qty + released_qty <= reserved_qty
  ),
  constraint ck_stock_reservations_status check (
    status_code in ('ACTIVE', 'PARTIALLY_CONSUMED', 'CONSUMED', 'RELEASED')
  ),
  constraint ck_stock_reservations_closed_state check (
    (status_code in ('ACTIVE', 'PARTIALLY_CONSUMED') and closed_at is null)
    or (status_code in ('CONSUMED', 'RELEASED') and closed_at is not null)
  )
);

create index idx_idempotency_commands_status
on inventory.idempotency_commands (organization_id, status_code, started_at);

create index idx_stock_transactions_source
on inventory.stock_transactions (
  organization_id,
  source_type_code,
  source_ref_snapshot
);

create index idx_stock_transactions_occurred
on inventory.stock_transactions (organization_id, occurred_at desc, id);

create index idx_stock_ledger_product_seq
on inventory.stock_ledger_entries (organization_id, product_id, ledger_seq desc);

create index idx_stock_ledger_batch_seq
on inventory.stock_ledger_entries (organization_id, batch_id, ledger_seq desc);

create index idx_stock_ledger_transaction
on inventory.stock_ledger_entries (transaction_id, line_no);

create index idx_stock_reservations_active_product
on inventory.stock_reservations (organization_id, product_id, reserved_at, id)
where status_code in ('ACTIVE', 'PARTIALLY_CONSUMED');

create or replace function inventory.validate_stock_transaction()
returns trigger
language plpgsql
set search_path = pg_catalog, app, catalog
as $$
declare
  v_reason_code text;
  v_reason_requires_note boolean;
  v_channel_code text;
  v_timezone text;
  v_effective_date date;
begin
  select reason.code, reason.requires_note
  into strict v_reason_code, v_reason_requires_note
  from catalog.movement_reasons reason
  where reason.id = new.reason_id and reason.is_active;

  if new.reason_code_snapshot <> v_reason_code then
    raise exception using errcode = 'P0001', message = 'REASON_SNAPSHOT_MISMATCH';
  end if;

  if v_reason_requires_note and (new.note is null or btrim(new.note) = '') then
    raise exception using errcode = 'P0001', message = 'TRANSACTION_NOTE_REQUIRED';
  end if;

  select channel.code
  into strict v_channel_code
  from catalog.channels channel
  where channel.id = new.channel_id and channel.is_active;

  if new.channel_code_snapshot <> v_channel_code then
    raise exception using errcode = 'P0001', message = 'CHANNEL_SNAPSHOT_MISMATCH';
  end if;

  select organization.timezone
  into strict v_timezone
  from app.organizations organization
  where organization.id = new.organization_id and organization.is_active;

  v_effective_date := (new.occurred_at at time zone v_timezone)::date;

  if new.effective_local_date <> v_effective_date then
    raise exception using errcode = 'P0001', message = 'EFFECTIVE_LOCAL_DATE_MISMATCH';
  end if;

  return new;
end;
$$;

create trigger trg_stock_transactions_validate
before insert on inventory.stock_transactions
for each row execute function inventory.validate_stock_transaction();

create or replace function inventory.validate_stock_ledger_entry()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog, inventory
as $$
declare
  v_transaction_org_id uuid;
  v_transaction_occurred_at timestamptz;
  v_transaction_recorded_at timestamptz;
  v_product_sku text;
  v_batch_code text;
  v_expiry_date date;
begin
  select transaction.organization_id, transaction.occurred_at, transaction.recorded_at
  into strict v_transaction_org_id, v_transaction_occurred_at, v_transaction_recorded_at
  from inventory.stock_transactions transaction
  where transaction.id = new.transaction_id;

  if new.organization_id <> v_transaction_org_id then
    raise exception using errcode = 'P0001', message = 'LEDGER_ORGANIZATION_MISMATCH';
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

  if new.product_sku_snapshot <> v_product_sku
     or new.batch_code_snapshot <> v_batch_code
     or new.expiry_date_snapshot <> v_expiry_date then
    raise exception using errcode = 'P0001', message = 'LEDGER_MASTER_SNAPSHOT_MISMATCH';
  end if;

  if new.occurred_at <> v_transaction_occurred_at
     or new.recorded_at <> v_transaction_recorded_at then
    raise exception using errcode = 'P0001', message = 'LEDGER_TRANSACTION_TIME_MISMATCH';
  end if;

  return new;
end;
$$;

create trigger trg_stock_ledger_entries_validate
before insert on inventory.stock_ledger_entries
for each row execute function inventory.validate_stock_ledger_entry();

create or replace function inventory.reject_immutable_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = 'P0001', message = 'IMMUTABLE_LEDGER_RECORD';
end;
$$;

create trigger trg_stock_transactions_immutable
before update or delete on inventory.stock_transactions
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_stock_ledger_entries_immutable
before update or delete on inventory.stock_ledger_entries
for each row execute function inventory.reject_immutable_mutation();

commit;
