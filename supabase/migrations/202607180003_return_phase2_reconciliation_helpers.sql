begin;

create or replace function reconciliation.find_return_receipt_consistency_mismatches(
  p_organization_id uuid
)
returns table (
  event_id uuid,
  return_id uuid,
  receipt_id uuid,
  transaction_id uuid,
  event_type_code text,
  external_event_ref text,
  external_return_ref text,
  receipt_ref text,
  event_line_quantity bigint,
  receipt_quantity bigint,
  ledger_quarantine_quantity bigint,
  event_line_count bigint,
  receipt_line_count bigint,
  ledger_entry_count bigint,
  invalid_receipt_line_count bigint,
  invalid_ledger_count bigint,
  orphan_ledger_count bigint,
  unexpected_transaction_count bigint,
  issue_code text
)
language sql
stable
security definer
set search_path = pg_catalog, catalog, inventory, operations, reconciliation
as $$
  with legacy_or_nonphysical as (
    select legacy.*
    from reconciliation.find_return_receipt_quarantine_mismatches(
      p_organization_id
    ) legacy
    left join operations.return_receipts receipt
      on receipt.organization_id = p_organization_id
     and receipt.id = legacy.receipt_id
    where legacy.event_type_code <> 'RECEIPT'
       or receipt.stock_effect_code = 'LEGACY_QUARANTINE_INBOUND'
  ),
  phase2_context as (
    select
      return_event.organization_id,
      return_event.id as event_id,
      return_event.return_id,
      return_event.external_event_ref,
      return_event.event_type_code,
      return_event.transaction_id,
      return_header.external_return_ref,
      receipt.id as receipt_id,
      receipt.receipt_ref,
      receipt.transaction_id as receipt_transaction_id,
      receipt.stock_effect_code as receipt_stock_effect_code
    from operations.return_events return_event
    join operations.returns return_header
      on return_header.organization_id = return_event.organization_id
     and return_header.id = return_event.return_id
    left join operations.return_receipts receipt
      on receipt.organization_id = return_event.organization_id
     and receipt.event_id = return_event.id
    where return_event.organization_id = p_organization_id
      and return_event.event_type_code = 'RECEIPT'
      and (
        receipt.id is null
        or receipt.stock_effect_code = 'NONE'
      )
  ),
  event_line_stats as (
    select
      context.event_id,
      count(event_line.id)::bigint as event_line_count,
      coalesce(sum(event_line.quantity), 0)::bigint
        as event_line_quantity
    from phase2_context context
    left join operations.return_event_lines event_line
      on event_line.organization_id = context.organization_id
     and event_line.event_id = context.event_id
    group by context.event_id
  ),
  receipt_line_stats as (
    select
      context.event_id,
      count(receipt_line.id)::bigint as receipt_line_count,
      coalesce(sum(receipt_line.quantity_received), 0)::bigint
        as receipt_quantity,
      count(*) filter (
        where receipt_line.id is not null
          and (
            event_line.id is null
            or event_line.event_id is distinct from context.event_id
            or event_line.return_item_id
                 is distinct from receipt_line.return_item_id
            or event_line.quantity
                 is distinct from receipt_line.quantity_received
            or event_line.outcome_code is distinct from 'RECEIVED'
            or event_line.source_line_ref
                 is distinct from receipt_line.source_line_ref
            or return_item.id is null
            or return_item.return_id
                 is distinct from context.return_id
            or return_item.product_id
                 is distinct from receipt_line.product_id
            or receipt_line.stock_effect_code is distinct from 'NONE'
            or receipt_line.batch_id is not null
            or receipt_line.batch_code_snapshot is not null
            or receipt_line.expiry_date_snapshot is not null
            or receipt_line.ledger_entry_id is not null
            or (
              receipt_line.batch_identity_verified
              and (
                receipt_line.marketplace_ship_allocation_id is null
                or ship_allocation.id is null
                or receipt_line.source_batch_id is null
                or receipt_line.source_batch_id
                     is distinct from ship_allocation.batch_id
                or receipt_line.source_batch_code_snapshot is null
                or receipt_line.source_batch_code_snapshot
                     is distinct from ship_allocation.batch_code_snapshot
                or receipt_line.source_expiry_date_snapshot is null
                or receipt_line.source_expiry_date_snapshot
                     is distinct from ship_allocation.expiry_date_snapshot
              )
            )
            or (
              not receipt_line.batch_identity_verified
              and (
                receipt_line.marketplace_ship_allocation_id is not null
                or receipt_line.source_batch_id is not null
                or receipt_line.source_batch_code_snapshot is not null
                or receipt_line.source_expiry_date_snapshot is not null
              )
            )
          )
      )::bigint as invalid_receipt_line_count
    from phase2_context context
    left join operations.return_receipt_lines receipt_line
      on receipt_line.organization_id = context.organization_id
     and receipt_line.receipt_id = context.receipt_id
    left join operations.return_event_lines event_line
      on event_line.organization_id = receipt_line.organization_id
     and event_line.id = receipt_line.event_line_id
    left join operations.return_items return_item
      on return_item.organization_id = receipt_line.organization_id
     and return_item.id = receipt_line.return_item_id
    left join operations.marketplace_ship_allocations ship_allocation
      on ship_allocation.organization_id = receipt_line.organization_id
     and ship_allocation.id = receipt_line.marketplace_ship_allocation_id
    group by context.event_id
  ),
  effect_transactions as (
    select distinct
      context.event_id,
      stock_transaction.id as transaction_id
    from phase2_context context
    join inventory.stock_transactions stock_transaction
      on stock_transaction.organization_id = context.organization_id
     and (
       stock_transaction.id = context.transaction_id
       or (
         stock_transaction.source_type_code = 'RETURN'
         and stock_transaction.source_id = context.return_id
         and stock_transaction.source_ref_snapshot = context.external_event_ref
       )
     )
  ),
  effect_stats as (
    select
      context.event_id,
      count(distinct effect.transaction_id)::bigint
        as unexpected_transaction_count,
      count(ledger_entry.id)::bigint as ledger_entry_count,
      coalesce(
        sum(
          case
            when ledger_entry.bucket_code = 'QUARANTINE'
              then ledger_entry.quantity_delta
            else 0
          end
        ),
        0
      )::bigint as ledger_quarantine_quantity,
      count(ledger_entry.id)::bigint as invalid_ledger_count,
      count(ledger_entry.id)::bigint as orphan_ledger_count
    from phase2_context context
    left join effect_transactions effect
      on effect.event_id = context.event_id
    left join inventory.stock_ledger_entries ledger_entry
      on ledger_entry.organization_id = context.organization_id
     and ledger_entry.transaction_id = effect.transaction_id
    group by context.event_id
  ),
  phase2_compared as (
    select
      context.event_id,
      context.return_id,
      context.receipt_id,
      context.transaction_id,
      context.event_type_code,
      context.external_event_ref,
      context.external_return_ref,
      context.receipt_ref,
      coalesce(event_stats.event_line_quantity, 0)::bigint
        as event_line_quantity,
      coalesce(receipt_stats.receipt_quantity, 0)::bigint
        as receipt_quantity,
      coalesce(effect.ledger_quarantine_quantity, 0)::bigint
        as ledger_quarantine_quantity,
      coalesce(event_stats.event_line_count, 0)::bigint
        as event_line_count,
      coalesce(receipt_stats.receipt_line_count, 0)::bigint
        as receipt_line_count,
      coalesce(effect.ledger_entry_count, 0)::bigint
        as ledger_entry_count,
      coalesce(receipt_stats.invalid_receipt_line_count, 0)::bigint
        as invalid_receipt_line_count,
      coalesce(effect.invalid_ledger_count, 0)::bigint
        as invalid_ledger_count,
      coalesce(effect.orphan_ledger_count, 0)::bigint
        as orphan_ledger_count,
      coalesce(effect.unexpected_transaction_count, 0)::bigint
        as unexpected_transaction_count,
      context.receipt_transaction_id,
      context.receipt_stock_effect_code
    from phase2_context context
    left join event_line_stats event_stats
      on event_stats.event_id = context.event_id
    left join receipt_line_stats receipt_stats
      on receipt_stats.event_id = context.event_id
    left join effect_stats effect
      on effect.event_id = context.event_id
  ),
  phase2_mismatches as (
    select
      compared.event_id,
      compared.return_id,
      compared.receipt_id,
      compared.transaction_id,
      compared.event_type_code,
      compared.external_event_ref,
      compared.external_return_ref,
      compared.receipt_ref,
      compared.event_line_quantity,
      compared.receipt_quantity,
      compared.ledger_quarantine_quantity,
      compared.event_line_count,
      compared.receipt_line_count,
      compared.ledger_entry_count,
      compared.invalid_receipt_line_count,
      compared.invalid_ledger_count,
      compared.orphan_ledger_count,
      compared.unexpected_transaction_count,
      case
        when compared.receipt_id is null
          or compared.receipt_ref is distinct from compared.external_event_ref
          or compared.receipt_stock_effect_code is distinct from 'NONE'
          then 'RETURN_RECEIPT_HEADER_INVALID'
        when compared.transaction_id is not null
          or compared.receipt_transaction_id is not null
          or compared.unexpected_transaction_count > 0
          then 'RETURN_RECEIPT_UNEXPECTED_STOCK_TRANSACTION'
        when compared.invalid_receipt_line_count > 0
          then 'RETURN_RECEIPT_LINE_LINK_INVALID'
        when compared.invalid_ledger_count > 0
          or compared.orphan_ledger_count > 0
          or compared.ledger_entry_count > 0
          or compared.ledger_quarantine_quantity <> 0
          then 'RETURN_RECEIPT_UNEXPECTED_LEDGER_EFFECT'
        else 'RETURN_RECEIPT_TOTAL_MISMATCH'
      end as issue_code
    from phase2_compared compared
    where compared.receipt_id is null
       or compared.receipt_ref is distinct from compared.external_event_ref
       or compared.receipt_stock_effect_code is distinct from 'NONE'
       or compared.transaction_id is not null
       or compared.receipt_transaction_id is not null
       or compared.unexpected_transaction_count > 0
       or compared.event_line_count = 0
       or compared.receipt_line_count = 0
       or compared.invalid_receipt_line_count > 0
       or compared.invalid_ledger_count > 0
       or compared.orphan_ledger_count > 0
       or compared.ledger_entry_count > 0
       or compared.ledger_quarantine_quantity <> 0
       or compared.event_line_quantity <> compared.receipt_quantity
  )
  select * from legacy_or_nonphysical
  union all
  select * from phase2_mismatches
  order by event_type_code, event_id
$$;

revoke all on function
  reconciliation.find_return_receipt_consistency_mismatches(uuid)
from public, anon, authenticated, service_role;

create or replace function reconciliation.find_return_inspection_consistency_mismatches(
  p_organization_id uuid
)
returns table (
  organization_id uuid,
  inspection_id uuid,
  return_id uuid,
  event_id uuid,
  inspection_ref text,
  transaction_id uuid,
  event_line_quantity bigint,
  allocation_quantity bigint,
  source_quarantine_quantity bigint,
  destination_quantity bigint,
  net_quantity bigint,
  event_line_count bigint,
  allocation_count bigint,
  source_ledger_count bigint,
  destination_ledger_count bigint,
  invalid_header_count bigint,
  line_total_mismatch_count bigint,
  invalid_allocation_count bigint,
  invalid_source_ledger_count bigint,
  invalid_destination_ledger_count bigint,
  orphan_ledger_count bigint,
  issue_code text
)
language sql
stable
security definer
set search_path = pg_catalog, catalog, inventory, operations, reconciliation
as $$
  with legacy_mismatches as (
    select legacy.*
    from reconciliation.find_return_inspection_transfer_mismatches(
      p_organization_id
    ) legacy
    join operations.return_inspections inspection
      on inspection.organization_id = legacy.organization_id
     and inspection.id = legacy.inspection_id
    where inspection.stock_effect_code = 'LEGACY_QUARANTINE_TRANSFER'
  ),
  phase2_base as (
    select
      inspection.organization_id,
      inspection.id as inspection_id,
      inspection.return_id,
      inspection.event_id,
      inspection.inspection_ref,
      inspection.occurred_at,
      inspection.transaction_id,
      inspection.stock_effect_code,
      return_header.channel_id,
      return_event.id as linked_event_id,
      return_event.return_id as event_return_id,
      return_event.external_event_ref,
      return_event.event_type_code,
      return_event.occurred_at as event_occurred_at,
      return_event.transaction_id as event_transaction_id,
      return_event.idempotency_command_id as event_command_id,
      stock_transaction.id as linked_transaction_id,
      stock_transaction.transaction_type_code,
      stock_transaction.reason_code_snapshot,
      stock_transaction.channel_id as transaction_channel_id,
      stock_transaction.source_type_code,
      stock_transaction.source_id,
      stock_transaction.source_ref_snapshot,
      stock_transaction.occurred_at as transaction_occurred_at,
      stock_transaction.idempotency_command_id as transaction_command_id
    from operations.return_inspections inspection
    join operations.returns return_header
      on return_header.organization_id = inspection.organization_id
     and return_header.id = inspection.return_id
    left join operations.return_events return_event
      on return_event.organization_id = inspection.organization_id
     and return_event.id = inspection.event_id
    left join inventory.stock_transactions stock_transaction
      on stock_transaction.organization_id = inspection.organization_id
     and stock_transaction.id = inspection.transaction_id
    where inspection.organization_id = p_organization_id
      and inspection.stock_effect_code in ('NONE', 'SELLABLE_INBOUND')
  ),
  effect_transactions as (
    select distinct
      base.inspection_id,
      stock_transaction.id as transaction_id
    from phase2_base base
    join inventory.stock_transactions stock_transaction
      on stock_transaction.organization_id = base.organization_id
     and (
       stock_transaction.id = base.transaction_id
       or (
         stock_transaction.source_type_code = 'RETURN'
         and stock_transaction.source_id = base.return_id
         and stock_transaction.source_ref_snapshot = base.inspection_ref
       )
     )
  ),
  event_stats as (
    select
      base.inspection_id,
      coalesce(sum(event_line.quantity), 0)::bigint as event_line_quantity,
      count(event_line.id)::bigint as event_line_count
    from phase2_base base
    left join operations.return_event_lines event_line
      on event_line.organization_id = base.organization_id
     and event_line.event_id = base.event_id
    group by base.inspection_id
  ),
  event_line_allocation_stats as (
    select
      base.inspection_id,
      event_line.id as event_line_id,
      event_line.quantity as event_line_quantity,
      coalesce(sum(allocation.quantity_allocated), 0)::bigint
        as allocation_quantity
    from phase2_base base
    join operations.return_event_lines event_line
      on event_line.organization_id = base.organization_id
     and event_line.event_id = base.event_id
    left join operations.return_inspection_allocations allocation
      on allocation.organization_id = base.organization_id
     and allocation.inspection_id = base.inspection_id
     and allocation.event_line_id = event_line.id
    group by base.inspection_id, event_line.id, event_line.quantity
  ),
  line_mismatch_stats as (
    select
      stats.inspection_id,
      count(*) filter (
        where stats.event_line_quantity <> stats.allocation_quantity
      )::bigint as line_total_mismatch_count
    from event_line_allocation_stats stats
    group by stats.inspection_id
  ),
  allocation_rows as (
    select
      base.organization_id,
      base.inspection_id,
      base.return_id,
      base.event_id,
      base.inspection_ref,
      base.transaction_id,
      base.stock_effect_code as inspection_stock_effect_code,
      allocation.id as allocation_id,
      allocation.event_line_id,
      allocation.receipt_line_id,
      allocation.quantity_allocated,
      allocation.destination_bucket_code,
      allocation.pair_no,
      allocation.source_ledger_entry_id,
      allocation.destination_ledger_entry_id,
      allocation.condition_code,
      allocation.stock_effect_code,
      allocation.return_batch_id,
      event_line.id as linked_event_line_id,
      event_line.event_id as allocation_event_id,
      event_line.return_item_id as event_return_item_id,
      event_line.source_line_ref as event_source_line_ref,
      receipt_line.id as linked_receipt_line_id,
      receipt_line.return_item_id as receipt_return_item_id,
      receipt_line.product_id,
      receipt_line.source_batch_id,
      receipt_line.source_expiry_date_snapshot,
      return_item.id as linked_return_item_id,
      return_item.return_id as item_return_id,
      return_item.product_id as item_product_id,
      source_entry.id as linked_source_ledger_id,
      source_entry.quantity_delta as source_quantity_delta,
      destination_entry.id as linked_destination_ledger_id,
      destination_entry.organization_id as destination_organization_id,
      destination_entry.transaction_id as destination_transaction_id,
      destination_entry.product_id as destination_product_id,
      destination_entry.batch_id as destination_batch_id,
      destination_entry.bucket_code as ledger_destination_bucket_code,
      destination_entry.quantity_delta as destination_quantity_delta,
      destination_entry.entry_role_code as destination_entry_role_code,
      destination_entry.pair_no as destination_pair_no,
      destination_entry.source_line_ref as destination_source_line_ref,
      provenance.id as provenance_id,
      provenance.return_id as provenance_return_id,
      provenance.return_item_id as provenance_return_item_id,
      provenance.receipt_line_id as provenance_receipt_line_id,
      provenance.product_id as provenance_product_id,
      provenance.batch_id as provenance_batch_id,
      provenance.source_batch_id as provenance_source_batch_id,
      return_batch.id as linked_return_batch_id,
      return_batch.product_id as return_batch_product_id,
      return_batch.batch_kind_code,
      return_batch.status_code as return_batch_status_code,
      return_batch.expiry_date as return_batch_expiry_date
    from phase2_base base
    join operations.return_inspection_allocations allocation
      on allocation.organization_id = base.organization_id
     and allocation.inspection_id = base.inspection_id
    left join operations.return_event_lines event_line
      on event_line.organization_id = allocation.organization_id
     and event_line.id = allocation.event_line_id
    left join operations.return_receipt_lines receipt_line
      on receipt_line.organization_id = allocation.organization_id
     and receipt_line.id = allocation.receipt_line_id
    left join operations.return_items return_item
      on return_item.organization_id = allocation.organization_id
     and return_item.id = receipt_line.return_item_id
    left join inventory.stock_ledger_entries source_entry
      on source_entry.organization_id = allocation.organization_id
     and source_entry.id = allocation.source_ledger_entry_id
    left join inventory.stock_ledger_entries destination_entry
      on destination_entry.organization_id = allocation.organization_id
     and destination_entry.id = allocation.destination_ledger_entry_id
    left join operations.return_stock_batches provenance
      on provenance.organization_id = allocation.organization_id
     and provenance.receipt_line_id = allocation.receipt_line_id
     and provenance.batch_id = allocation.return_batch_id
    left join catalog.product_batches return_batch
      on return_batch.organization_id = allocation.organization_id
     and return_batch.product_id = receipt_line.product_id
     and return_batch.id = allocation.return_batch_id
  ),
  allocation_stats as (
    select
      row.inspection_id,
      coalesce(sum(row.quantity_allocated), 0)::bigint as allocation_quantity,
      coalesce(
        sum(
          case when row.condition_code = 'SELLABLE'
            then row.quantity_allocated else 0 end
        ),
        0
      )::bigint as sellable_allocation_quantity,
      coalesce(
        sum(
          case when row.source_quantity_delta < 0
            then -row.source_quantity_delta
            else coalesce(row.source_quantity_delta, 0) end
        ),
        0
      )::bigint as source_quarantine_quantity,
      coalesce(sum(row.destination_quantity_delta), 0)::bigint
        as destination_quantity,
      coalesce(
        sum(
          coalesce(row.source_quantity_delta, 0)
            + coalesce(row.destination_quantity_delta, 0)
        ),
        0
      )::bigint as net_quantity,
      count(row.allocation_id)::bigint as allocation_count,
      count(row.linked_source_ledger_id)::bigint as source_ledger_count,
      count(row.linked_destination_ledger_id)::bigint
        as destination_ledger_count,
      count(*) filter (
        where row.linked_event_line_id is null
          or row.allocation_event_id <> row.event_id
          or row.linked_receipt_line_id is null
          or row.linked_return_item_id is null
          or row.item_return_id <> row.return_id
          or row.event_return_item_id <> row.receipt_return_item_id
          or row.item_product_id <> row.product_id
          or row.quantity_allocated <= 0
          or (
            row.condition_code = 'SELLABLE'
            and (
              row.inspection_stock_effect_code <> 'SELLABLE_INBOUND'
              or row.stock_effect_code <> 'SELLABLE_INBOUND'
              or row.destination_bucket_code <> 'SELLABLE'
              or row.return_batch_id is null
              or row.pair_no is not null
              or row.source_ledger_entry_id is not null
              or row.destination_ledger_entry_id is null
            )
          )
          or (
            row.condition_code = 'DAMAGED'
            and (
              row.stock_effect_code <> 'NONE'
              or row.destination_bucket_code is not null
              or row.return_batch_id is not null
              or row.pair_no is not null
              or row.source_ledger_entry_id is not null
              or row.destination_ledger_entry_id is not null
            )
          )
          or row.condition_code not in ('SELLABLE', 'DAMAGED')
      )::bigint as invalid_allocation_count,
      count(*) filter (
        where row.source_ledger_entry_id is not null
      )::bigint as invalid_source_ledger_count,
      count(*) filter (
        where (
          row.condition_code = 'SELLABLE'
          and (
            row.linked_destination_ledger_id is null
            or row.destination_organization_id <> row.organization_id
            or row.destination_transaction_id <> row.transaction_id
            or row.destination_product_id <> row.product_id
            or row.destination_batch_id <> row.return_batch_id
            or row.ledger_destination_bucket_code <> 'SELLABLE'
            or row.destination_quantity_delta <> row.quantity_allocated
            or row.destination_entry_role_code <> 'EXTERNAL_IN'
            or row.destination_pair_no is not null
            or row.destination_source_line_ref
                 <> row.event_source_line_ref || ':SELLABLE'
            or row.provenance_id is null
            or row.provenance_return_id <> row.return_id
            or row.provenance_return_item_id <> row.receipt_return_item_id
            or row.provenance_receipt_line_id <> row.receipt_line_id
            or row.provenance_product_id <> row.product_id
            or row.provenance_batch_id <> row.return_batch_id
            or row.provenance_source_batch_id <> row.source_batch_id
            or row.linked_return_batch_id is null
            or row.return_batch_product_id <> row.product_id
            or row.batch_kind_code <> 'RETURN'
            or row.return_batch_status_code <> 'ACTIVE'
            or row.return_batch_expiry_date
                 <> row.source_expiry_date_snapshot
            or row.return_batch_id = row.source_batch_id
          )
        )
        or (
          row.condition_code = 'DAMAGED'
          and row.destination_ledger_entry_id is not null
        )
      )::bigint as invalid_destination_ledger_count
    from allocation_rows row
    group by row.inspection_id
  ),
  orphan_stats as (
    select
      base.inspection_id,
      count(ledger_entry.id)::bigint as orphan_ledger_count
    from phase2_base base
    join effect_transactions effect
      on effect.inspection_id = base.inspection_id
    join inventory.stock_ledger_entries ledger_entry
      on ledger_entry.organization_id = base.organization_id
     and ledger_entry.transaction_id = effect.transaction_id
    where not exists (
      select 1
      from operations.return_inspection_allocations allocation
      where allocation.organization_id = base.organization_id
        and allocation.inspection_id = base.inspection_id
        and allocation.destination_ledger_entry_id = ledger_entry.id
    )
    group by base.inspection_id
  ),
  effect_counts as (
    select
      base.inspection_id,
      count(distinct effect.transaction_id)::bigint as transaction_count
    from phase2_base base
    left join effect_transactions effect
      on effect.inspection_id = base.inspection_id
    group by base.inspection_id
  ),
  phase2_compared as (
    select
      base.organization_id,
      base.inspection_id,
      base.return_id,
      base.event_id,
      base.inspection_ref,
      base.transaction_id,
      coalesce(event_stats.event_line_quantity, 0)::bigint
        as event_line_quantity,
      coalesce(allocation.allocation_quantity, 0)::bigint
        as allocation_quantity,
      coalesce(allocation.source_quarantine_quantity, 0)::bigint
        as source_quarantine_quantity,
      coalesce(allocation.destination_quantity, 0)::bigint
        as destination_quantity,
      coalesce(allocation.net_quantity, 0)::bigint as net_quantity,
      coalesce(event_stats.event_line_count, 0)::bigint
        as event_line_count,
      coalesce(allocation.allocation_count, 0)::bigint
        as allocation_count,
      coalesce(allocation.source_ledger_count, 0)::bigint
        as source_ledger_count,
      coalesce(allocation.destination_ledger_count, 0)::bigint
        as destination_ledger_count,
      case
        when base.linked_event_id is null
          or base.event_return_id <> base.return_id
          or base.external_event_ref <> base.inspection_ref
          or base.event_type_code <> 'INSPECTION'
          or base.event_occurred_at <> base.occurred_at
          or base.event_transaction_id is distinct from base.transaction_id
          or (
            base.stock_effect_code = 'SELLABLE_INBOUND'
            and (
              base.linked_transaction_id is null
              or base.transaction_type_code <> 'RETURN_SELLABLE_INBOUND'
              or base.reason_code_snapshot <> 'RETURN_SELLABLE'
              or base.transaction_channel_id <> base.channel_id
              or base.source_type_code <> 'RETURN'
              or base.source_id <> base.return_id
              or base.source_ref_snapshot <> base.inspection_ref
              or base.transaction_occurred_at <> base.occurred_at
              or base.transaction_command_id <> base.event_command_id
              or coalesce(effect.transaction_count, 0) <> 1
            )
          )
          or (
            base.stock_effect_code = 'NONE'
            and (
              base.transaction_id is not null
              or base.event_transaction_id is not null
              or coalesce(effect.transaction_count, 0) <> 0
            )
          )
          then 1::bigint
        else 0::bigint
      end as invalid_header_count,
      coalesce(line_stats.line_total_mismatch_count, 0)::bigint
        as line_total_mismatch_count,
      coalesce(allocation.invalid_allocation_count, 0)::bigint
        as invalid_allocation_count,
      coalesce(allocation.invalid_source_ledger_count, 0)::bigint
        as invalid_source_ledger_count,
      coalesce(allocation.invalid_destination_ledger_count, 0)::bigint
        as invalid_destination_ledger_count,
      coalesce(orphan.orphan_ledger_count, 0)::bigint
        as orphan_ledger_count,
      coalesce(allocation.sellable_allocation_quantity, 0)::bigint
        as sellable_allocation_quantity,
      base.stock_effect_code
    from phase2_base base
    left join event_stats
      on event_stats.inspection_id = base.inspection_id
    left join line_mismatch_stats line_stats
      on line_stats.inspection_id = base.inspection_id
    left join allocation_stats allocation
      on allocation.inspection_id = base.inspection_id
    left join orphan_stats orphan
      on orphan.inspection_id = base.inspection_id
    left join effect_counts effect
      on effect.inspection_id = base.inspection_id
  ),
  phase2_mismatches as (
    select
      compared.organization_id,
      compared.inspection_id,
      compared.return_id,
      compared.event_id,
      compared.inspection_ref,
      compared.transaction_id,
      compared.event_line_quantity,
      compared.allocation_quantity,
      compared.source_quarantine_quantity,
      compared.destination_quantity,
      compared.net_quantity,
      compared.event_line_count,
      compared.allocation_count,
      compared.source_ledger_count,
      compared.destination_ledger_count,
      compared.invalid_header_count,
      compared.line_total_mismatch_count,
      compared.invalid_allocation_count,
      compared.invalid_source_ledger_count,
      compared.invalid_destination_ledger_count,
      compared.orphan_ledger_count,
      case
        when compared.invalid_header_count > 0
          then 'RETURN_INSPECTION_TRANSACTION_INVALID'
        when compared.invalid_allocation_count > 0
          or compared.line_total_mismatch_count > 0
          or compared.event_line_count = 0
          or compared.allocation_count = 0
          then 'RETURN_INSPECTION_ALLOCATION_LINK_INVALID'
        when compared.invalid_source_ledger_count > 0
          then 'RETURN_INSPECTION_SOURCE_LEDGER_INVALID'
        when compared.invalid_destination_ledger_count > 0
          then 'RETURN_INSPECTION_DESTINATION_LEDGER_INVALID'
        when compared.orphan_ledger_count > 0
          then 'RETURN_INSPECTION_ORPHAN_LEDGER_ENTRY'
        when compared.event_line_quantity <> compared.allocation_quantity
          then 'RETURN_INSPECTION_EVENT_TOTAL_MISMATCH'
        when compared.source_quarantine_quantity <> 0
          then 'RETURN_INSPECTION_UNEXPECTED_SOURCE_LEDGER'
        when compared.destination_quantity <> compared.sellable_allocation_quantity
          then 'RETURN_INSPECTION_SELLABLE_LEDGER_TOTAL_MISMATCH'
        else 'RETURN_INSPECTION_NET_EFFECT_MISMATCH'
      end as issue_code
    from phase2_compared compared
    where compared.invalid_header_count > 0
       or compared.line_total_mismatch_count > 0
       or compared.event_line_count = 0
       or compared.allocation_count = 0
       or compared.invalid_allocation_count > 0
       or compared.invalid_source_ledger_count > 0
       or compared.invalid_destination_ledger_count > 0
       or compared.orphan_ledger_count > 0
       or compared.event_line_quantity <> compared.allocation_quantity
       or compared.source_quarantine_quantity <> 0
       or compared.destination_quantity <> compared.sellable_allocation_quantity
       or compared.net_quantity <> compared.sellable_allocation_quantity
       or compared.source_ledger_count <> 0
       or compared.destination_ledger_count <> (
         select count(*)::bigint
         from operations.return_inspection_allocations sellable
         where sellable.organization_id = compared.organization_id
           and sellable.inspection_id = compared.inspection_id
           and sellable.condition_code = 'SELLABLE'
       )
       or (
         compared.stock_effect_code = 'NONE'
         and compared.sellable_allocation_quantity <> 0
       )
       or (
         compared.stock_effect_code = 'SELLABLE_INBOUND'
         and compared.sellable_allocation_quantity = 0
       )
  )
  select * from legacy_mismatches
  union all
  select * from phase2_mismatches
  order by inspection_id
$$;

revoke all on function
  reconciliation.find_return_inspection_consistency_mismatches(uuid)
from public, anon, authenticated, service_role;

commit;
