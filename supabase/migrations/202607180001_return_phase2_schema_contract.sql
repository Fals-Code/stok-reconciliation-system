begin;

-- Phase 2 distinguishes normal inventory batches from batches created by
-- sellable return inspections. Existing production and receipt batches remain
-- STANDARD. Legacy unidentified return placeholders are classified explicitly.
alter table catalog.product_batches
add column batch_kind_code text not null default 'STANDARD';

alter table catalog.product_batches
add constraint ck_product_batches_kind
check (
  batch_kind_code in (
    'STANDARD',
    'RETURN',
    'UNIDENTIFIED_RETURN'
  )
);

update catalog.product_batches
set batch_kind_code = 'UNIDENTIFIED_RETURN'
where block_reason = 'UNIDENTIFIED_RETURN_BATCH';

create index idx_product_batches_return_kind
on catalog.product_batches (
  organization_id,
  product_id,
  batch_kind_code,
  received_first_at,
  id
)
where batch_kind_code in ('RETURN', 'UNIDENTIFIED_RETURN');

-- A sellable return is an inbound stock effect into a dedicated return batch.
alter table inventory.stock_transactions
drop constraint ck_stock_transactions_type;

alter table inventory.stock_transactions
add constraint ck_stock_transactions_type
check (
  transaction_type_code in (
    'INITIAL_BALANCE',
    'RECEIPT',
    'MARKETPLACE_OUTBOUND',
    'MANUAL_OUTBOUND',
    'RETURN_RECEIPT',
    'RETURN_INSPECTION_TRANSFER',
    'RETURN_SELLABLE_INBOUND',
    'DISPOSAL',
    'STOCKTAKE_ADJUSTMENT',
    'REVERSAL'
  )
);

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
  gen_random_uuid(),
  'RETURN_SELLABLE',
  'Retur Layak Jual',
  'INBOUND',
  false,
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

-- Expected and lost events never have a stock transaction.
-- Receipt and inspection events may be stock-neutral under Phase 2.
alter table operations.return_events
drop constraint ck_return_events_transaction_rule;

alter table operations.return_events
add constraint ck_return_events_transaction_rule
check (
  (
    event_type_code in ('EXPECTED', 'LOST')
    and transaction_id is null
  )
  or event_type_code in ('RECEIPT', 'INSPECTION')
);

alter table operations.return_event_lines
drop constraint ck_return_event_lines_outcome;

alter table operations.return_event_lines
add constraint ck_return_event_lines_outcome
check (
  outcome_code in (
    'EXPECTED',
    'RECEIVED',
    'QUARANTINE',
    'SELLABLE',
    'DAMAGED',
    'MIXED',
    'LOST'
  )
);

-- Legacy receipts wrote quarantine inventory. Phase 2 receipts only record
-- physical arrival and therefore carry no stock transaction.
alter table operations.return_receipts
alter column transaction_id drop not null;

alter table operations.return_receipts
add column stock_effect_code text
not null
default 'LEGACY_QUARANTINE_INBOUND';

alter table operations.return_receipts
add constraint ck_return_receipts_stock_effect
check (
  stock_effect_code in (
    'NONE',
    'LEGACY_QUARANTINE_INBOUND'
  )
);

alter table operations.return_receipts
add constraint ck_return_receipts_transaction_effect
check (
  (
    stock_effect_code = 'NONE'
    and transaction_id is null
  )
  or (
    stock_effect_code = 'LEGACY_QUARANTINE_INBOUND'
    and transaction_id is not null
  )
);

-- Destination batch and ledger fields are nullable for Phase 2 receipt lines.
-- Explicit source fields retain outbound batch provenance without restoring
-- inventory to that original batch.
alter table operations.return_receipt_lines
add column stock_effect_code text
not null
default 'LEGACY_QUARANTINE_INBOUND';

alter table operations.return_receipt_lines
add column source_batch_id uuid null;

alter table operations.return_receipt_lines
add column source_batch_code_snapshot text null;

alter table operations.return_receipt_lines
add column source_expiry_date_snapshot date null;

alter table operations.return_receipt_lines
alter column batch_id drop not null;

alter table operations.return_receipt_lines
alter column batch_code_snapshot drop not null;

alter table operations.return_receipt_lines
alter column expiry_date_snapshot drop not null;

alter table operations.return_receipt_lines
alter column ledger_entry_id drop not null;

alter table operations.return_receipt_lines
add constraint fk_return_receipt_lines_source_batch
foreign key (
  organization_id,
  product_id,
  source_batch_id
)
references catalog.product_batches (
  organization_id,
  product_id,
  id
)
on delete restrict;

alter table operations.return_receipt_lines
add constraint ck_return_receipt_lines_stock_effect
check (
  stock_effect_code in (
    'NONE',
    'LEGACY_QUARANTINE_INBOUND'
  )
);

alter table operations.return_receipt_lines
add constraint ck_return_receipt_lines_effect_shape
check (
  (
    stock_effect_code = 'NONE'
    and batch_id is null
    and batch_code_snapshot is null
    and expiry_date_snapshot is null
    and ledger_entry_id is null
  )
  or (
    stock_effect_code = 'LEGACY_QUARANTINE_INBOUND'
    and batch_id is not null
    and batch_code_snapshot is not null
    and expiry_date_snapshot is not null
    and ledger_entry_id is not null
  )
);

alter table operations.return_receipt_lines
add constraint ck_return_receipt_lines_source_batch_shape
check (
  (
    source_batch_id is null
    and source_batch_code_snapshot is null
    and source_expiry_date_snapshot is null
  )
  or (
    source_batch_id is not null
    and source_batch_code_snapshot is not null
    and btrim(source_batch_code_snapshot) <> ''
    and source_expiry_date_snapshot is not null
  )
);

-- Preserve source provenance for legacy verified receipt lines.
alter table operations.return_receipt_lines
disable trigger trg_return_receipt_lines_immutable;

update operations.return_receipt_lines
set
  source_batch_id = batch_id,
  source_batch_code_snapshot = batch_code_snapshot,
  source_expiry_date_snapshot = expiry_date_snapshot
where batch_identity_verified
  and batch_id is not null;

alter table operations.return_receipt_lines
enable trigger trg_return_receipt_lines_immutable;

-- Phase 2 inspections have a transaction only when sellable quantity is posted.
alter table operations.return_inspections
alter column transaction_id drop not null;

alter table operations.return_inspections
add column stock_effect_code text
not null
default 'LEGACY_QUARANTINE_TRANSFER';

alter table operations.return_inspections
add constraint ck_return_inspections_stock_effect
check (
  stock_effect_code in (
    'NONE',
    'SELLABLE_INBOUND',
    'LEGACY_QUARANTINE_TRANSFER'
  )
);

alter table operations.return_inspections
add constraint ck_return_inspections_transaction_effect
check (
  (
    stock_effect_code = 'NONE'
    and transaction_id is null
  )
  or (
    stock_effect_code in (
      'SELLABLE_INBOUND',
      'LEGACY_QUARANTINE_TRANSFER'
    )
    and transaction_id is not null
  )
);

-- Allocation rows now separate physical condition from inventory impact.
alter table operations.return_inspection_allocations
add column condition_code text null;

alter table operations.return_inspection_allocations
add column stock_effect_code text
not null
default 'LEGACY_QUARANTINE_TRANSFER';

alter table operations.return_inspection_allocations
add column return_batch_id uuid null
references catalog.product_batches(id)
on delete restrict;

alter table operations.return_inspection_allocations
alter column destination_bucket_code drop not null;

alter table operations.return_inspection_allocations
alter column pair_no drop not null;

alter table operations.return_inspection_allocations
alter column source_ledger_entry_id drop not null;

alter table operations.return_inspection_allocations
alter column destination_ledger_entry_id drop not null;

alter table operations.return_inspection_allocations
disable trigger trg_return_inspection_allocations_immutable;

update operations.return_inspection_allocations
set condition_code = destination_bucket_code;

alter table operations.return_inspection_allocations
enable trigger trg_return_inspection_allocations_immutable;

alter table operations.return_inspection_allocations
alter column condition_code set not null;

alter table operations.return_inspection_allocations
add constraint ck_return_inspection_allocations_condition
check (condition_code in ('SELLABLE', 'DAMAGED'));

alter table operations.return_inspection_allocations
add constraint ck_return_inspection_allocations_stock_effect
check (
  stock_effect_code in (
    'NONE',
    'SELLABLE_INBOUND',
    'LEGACY_QUARANTINE_TRANSFER'
  )
);

alter table operations.return_inspection_allocations
add constraint ck_return_inspection_allocations_effect_shape
check (
  (
    stock_effect_code = 'LEGACY_QUARANTINE_TRANSFER'
    and destination_bucket_code in ('SELLABLE', 'DAMAGED')
    and pair_no is not null
    and source_ledger_entry_id is not null
    and destination_ledger_entry_id is not null
    and return_batch_id is null
  )
  or (
    stock_effect_code = 'SELLABLE_INBOUND'
    and condition_code = 'SELLABLE'
    and destination_bucket_code = 'SELLABLE'
    and pair_no is null
    and source_ledger_entry_id is null
    and destination_ledger_entry_id is not null
    and return_batch_id is not null
  )
  or (
    stock_effect_code = 'NONE'
    and condition_code = 'DAMAGED'
    and destination_bucket_code is null
    and pair_no is null
    and source_ledger_entry_id is null
    and destination_ledger_entry_id is null
    and return_batch_id is null
  )
);

alter table operations.return_inspection_allocations
add constraint uq_return_inspection_allocations_condition
unique (
  inspection_id,
  receipt_line_id,
  condition_code
);

-- Keep the old inspection RPC functional until the next forward-fix migration
-- replaces it. New Phase 2 writes provide condition_code explicitly.
create or replace function operations.normalize_return_inspection_allocation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.condition_code is null then
    new.condition_code := new.destination_bucket_code;
  end if;

  return new;
end;
$$;

create trigger trg_return_inspection_allocations_normalize
before insert on operations.return_inspection_allocations
for each row
execute function operations.normalize_return_inspection_allocation();

-- One dedicated return batch is created per physical receipt line. Partial
-- inspections of the same receipt line reuse that return batch.
create table operations.return_stock_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  return_id uuid not null,
  return_item_id uuid not null,
  receipt_line_id uuid not null,
  created_from_inspection_id uuid not null,
  product_id uuid not null,
  batch_id uuid not null,
  source_batch_id uuid null,
  source_batch_code_snapshot text null,
  source_expiry_date_snapshot date null,
  created_at timestamptz not null default clock_timestamp(),
  constraint uq_return_stock_batches_org_id
    unique (organization_id, id),
  constraint fk_return_stock_batches_return
    foreign key (organization_id, return_id)
    references operations.returns (organization_id, id)
    on delete restrict,
  constraint fk_return_stock_batches_item
    foreign key (organization_id, return_item_id)
    references operations.return_items (organization_id, id)
    on delete restrict,
  constraint fk_return_stock_batches_receipt_line
    foreign key (organization_id, receipt_line_id)
    references operations.return_receipt_lines (organization_id, id)
    on delete restrict,
  constraint fk_return_stock_batches_inspection
    foreign key (organization_id, created_from_inspection_id)
    references operations.return_inspections (organization_id, id)
    on delete restrict,
  constraint fk_return_stock_batches_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches (organization_id, product_id, id)
    on delete restrict,
  constraint fk_return_stock_batches_source_batch
    foreign key (organization_id, product_id, source_batch_id)
    references catalog.product_batches (organization_id, product_id, id)
    on delete restrict,
  constraint uq_return_stock_batches_receipt_line
    unique (organization_id, receipt_line_id),
  constraint uq_return_stock_batches_batch
    unique (organization_id, batch_id),
  constraint ck_return_stock_batches_source_shape
    check (
      (
        source_batch_id is null
        and source_batch_code_snapshot is null
        and source_expiry_date_snapshot is null
      )
      or (
        source_batch_id is not null
        and source_batch_code_snapshot is not null
        and btrim(source_batch_code_snapshot) <> ''
        and source_expiry_date_snapshot is not null
      )
    )
);

create index idx_return_stock_batches_return
on operations.return_stock_batches (
  organization_id,
  return_id,
  return_item_id,
  receipt_line_id
);

create trigger trg_return_stock_batches_immutable
before update or delete on operations.return_stock_batches
for each row
execute function inventory.reject_immutable_mutation();

alter table operations.return_stock_batches enable row level security;

create policy return_stock_batches_read_current_org
on operations.return_stock_batches
for select
to authenticated
using (
  organization_id = (
    select app.current_organization_id()
  )
);

revoke all on operations.return_stock_batches
from public, anon, authenticated;

grant select on operations.return_stock_batches
to authenticated, service_role;

create or replace view api.return_stock_batches
with (security_invoker = true)
as
select
  provenance.id as return_stock_batch_id,
  provenance.organization_id,
  provenance.return_id,
  provenance.return_item_id,
  provenance.receipt_line_id,
  provenance.created_from_inspection_id,
  provenance.product_id,
  provenance.batch_id,
  batch.batch_code,
  batch.batch_kind_code,
  batch.expiry_date,
  batch.received_first_at,
  batch.status_code,
  provenance.source_batch_id,
  provenance.source_batch_code_snapshot,
  provenance.source_expiry_date_snapshot,
  provenance.created_at
from operations.return_stock_batches provenance
join catalog.product_batches batch
  on batch.organization_id = provenance.organization_id
 and batch.product_id = provenance.product_id
 and batch.id = provenance.batch_id;

revoke all on api.return_stock_batches from anon;

grant select on api.return_stock_batches
to authenticated, service_role;

create or replace view api.batch_inventory
with (security_invoker = true)
as
select
  batch.id as batch_id,
  batch.organization_id,
  batch.product_id,
  product.sku,
  product.name as product_name,
  batch.batch_code,
  batch.expiry_date,
  batch.received_first_at,
  batch.status_code,
  coalesce(balance.sellable_qty, 0) as sellable_qty,
  coalesce(balance.quarantine_qty, 0) as quarantine_qty,
  coalesce(balance.damaged_qty, 0) as damaged_qty,
  coalesce(balance.last_ledger_seq, 0) as last_ledger_seq,
  balance.updated_at as stock_updated_at,
  batch.batch_kind_code
from catalog.product_batches batch
join catalog.products product
  on product.organization_id = batch.organization_id
 and product.id = batch.product_id
left join inventory.stock_batch_balances balance
  on balance.organization_id = batch.organization_id
 and balance.batch_id = batch.id;

commit;