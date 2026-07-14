begin;

create or replace function reconciliation.find_return_inspection_transfer_mismatches(
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
set search_path = pg_catalog, inventory, operations
as $$
  with inspection_base as (
    select
      inspection.organization_id,
      inspection.id as inspection_id,
      inspection.return_id,
      inspection.event_id,
      inspection.inspection_ref,
      inspection.occurred_at,
      inspection.transaction_id,
      return_header.channel_id,
      return_event.id as linked_event_id,
      return_event.return_id as event_return_id,
      return_event.external_event_ref,
      return_event.event_type_code,
      return_event.occurred_at as event_occurred_at,
      return_event.transaction_id as event_transaction_id,
      return_event.idempotency_command_id as event_command_id,
      stock_transaction.id as linked_transaction_id,
      stock_transaction.organization_id as transaction_organization_id,
      stock_transaction.transaction_type_code,
      stock_transaction.reason_code_snapshot,
      stock_transaction.channel_id as transaction_channel_id,
      stock_transaction.source_type_code,
      stock_transaction.source_id,
      stock_transaction.source_ref_snapshot,
      stock_transaction.occurred_at as transaction_occurred_at,
      stock_transaction.idempotency_command_id as transaction_command_id,
      case
        when return_event.id is null
          or stock_transaction.id is null
          or return_event.return_id <> inspection.return_id
          or return_event.external_event_ref <> inspection.inspection_ref
          or return_event.event_type_code <> 'INSPECTION'
          or return_event.occurred_at <> inspection.occurred_at
          or return_event.transaction_id <> inspection.transaction_id
          or stock_transaction.organization_id <> inspection.organization_id
          or stock_transaction.transaction_type_code
            <> 'RETURN_INSPECTION_TRANSFER'
          or stock_transaction.reason_code_snapshot
            <> 'RETURN_INSPECTION'
          or stock_transaction.channel_id <> return_header.channel_id
          or stock_transaction.source_type_code <> 'RETURN'
          or stock_transaction.source_id <> inspection.return_id
          or stock_transaction.source_ref_snapshot
            <> inspection.inspection_ref
          or stock_transaction.occurred_at <> inspection.occurred_at
          or stock_transaction.idempotency_command_id
            <> return_event.idempotency_command_id
          then 1::bigint
        else 0::bigint
      end as invalid_header_count
    from operations.return_inspections inspection
    join operations.returns return_header
      on return_header.organization_id = inspection.organization_id
     and return_header.id = inspection.return_id
    left join operations.return_events return_event
      on return_event.organization_id = inspection.organization_id
     and return_event.id = inspection.event_id
    left join inventory.stock_transactions stock_transaction
      on stock_transaction.id = inspection.transaction_id
    where inspection.organization_id = p_organization_id
  ),
  event_stats as (
    select
      base.inspection_id,
      coalesce(sum(event_line.quantity), 0)::bigint
        as event_line_quantity,
      count(event_line.id)::bigint as event_line_count
    from inspection_base base
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
      coalesce(
        sum(allocation.quantity_allocated),
        0
      )::bigint as allocation_quantity
    from inspection_base base
    join operations.return_event_lines event_line
      on event_line.organization_id = base.organization_id
     and event_line.event_id = base.event_id
    left join operations.return_inspection_allocations allocation
      on allocation.organization_id = base.organization_id
     and allocation.inspection_id = base.inspection_id
     and allocation.event_line_id = event_line.id
    group by
      base.inspection_id,
      event_line.id,
      event_line.quantity
  ),
  line_mismatch_stats as (
    select
      stats.inspection_id,
      count(*) filter (
        where stats.event_line_quantity
          <> stats.allocation_quantity
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
      allocation.id as allocation_id,
      allocation.event_line_id,
      allocation.receipt_line_id,
      allocation.destination_bucket_code
        as allocation_destination_bucket_code,
      allocation.quantity_allocated,
      allocation.pair_no,
      allocation.source_ledger_entry_id,
      allocation.destination_ledger_entry_id,
      event_line.id as linked_event_line_id,
      event_line.event_id as allocation_event_id,
      event_line.return_item_id as event_return_item_id,
      event_line.source_line_ref as event_source_line_ref,
      receipt_line.id as linked_receipt_line_id,
      receipt_line.return_item_id as receipt_return_item_id,
      receipt_line.product_id,
      receipt_line.batch_id,
      return_item.id as linked_return_item_id,
      return_item.return_id as item_return_id,
      return_item.product_id as item_product_id,
      source_entry.id as linked_source_ledger_id,
      source_entry.organization_id as source_organization_id,
      source_entry.transaction_id as source_transaction_id,
      source_entry.product_id as source_product_id,
      source_entry.batch_id as source_batch_id,
      source_entry.bucket_code as source_bucket_code,
      source_entry.quantity_delta as source_quantity_delta,
      source_entry.entry_role_code as source_entry_role_code,
      source_entry.pair_no as source_pair_no,
      source_entry.source_line_ref as source_line_ref,
      destination_entry.id as linked_destination_ledger_id,
      destination_entry.organization_id
        as destination_organization_id,
      destination_entry.transaction_id
        as destination_transaction_id,
      destination_entry.product_id as destination_product_id,
      destination_entry.batch_id as destination_batch_id,
      destination_entry.bucket_code
        as ledger_destination_bucket_code,
      destination_entry.quantity_delta
        as destination_quantity_delta,
      destination_entry.entry_role_code
        as destination_entry_role_code,
      destination_entry.pair_no as destination_pair_no,
      destination_entry.source_line_ref
        as destination_source_line_ref
    from inspection_base base
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
      on source_entry.id = allocation.source_ledger_entry_id
    left join inventory.stock_ledger_entries destination_entry
      on destination_entry.id =
        allocation.destination_ledger_entry_id
  ),
  allocation_stats as (
    select
      row.inspection_id,
      coalesce(sum(row.quantity_allocated), 0)::bigint
        as allocation_quantity,
      coalesce(
        sum(
          case
            when row.source_quantity_delta < 0
              then -row.source_quantity_delta
            else row.source_quantity_delta
          end
        ),
        0
      )::bigint as source_quarantine_quantity,
      coalesce(
        sum(row.destination_quantity_delta),
        0
      )::bigint as destination_quantity,
      coalesce(
        sum(
          coalesce(row.source_quantity_delta, 0)
            + coalesce(row.destination_quantity_delta, 0)
        ),
        0
      )::bigint as net_quantity,
      count(row.allocation_id)::bigint as allocation_count,
      count(row.linked_source_ledger_id)::bigint
        as source_ledger_count,
      count(row.linked_destination_ledger_id)::bigint
        as destination_ledger_count,
      count(*) filter (
        where row.linked_event_line_id is null
          or row.allocation_event_id <> row.event_id
          or row.linked_receipt_line_id is null
          or row.linked_return_item_id is null
          or row.item_return_id <> row.return_id
          or row.event_return_item_id
            <> row.receipt_return_item_id
          or row.item_product_id <> row.product_id
          or row.allocation_destination_bucket_code not in (
            'SELLABLE',
            'DAMAGED'
          )
          or row.quantity_allocated <= 0
          or row.pair_no <= 0
          or row.source_ledger_entry_id
            = row.destination_ledger_entry_id
      )::bigint as invalid_allocation_count,
      count(*) filter (
        where row.linked_source_ledger_id is null
          or row.source_organization_id <> row.organization_id
          or row.source_transaction_id <> row.transaction_id
          or row.source_product_id <> row.product_id
          or row.source_batch_id <> row.batch_id
          or row.source_bucket_code <> 'QUARANTINE'
          or row.source_quantity_delta <> -row.quantity_allocated
          or row.source_entry_role_code <> 'SOURCE'
          or row.source_pair_no <> row.pair_no
          or row.source_line_ref
            <> (
              row.event_source_line_ref
                || ':'
                || row.allocation_destination_bucket_code
                || ':SOURCE'
            )
      )::bigint as invalid_source_ledger_count,
      count(*) filter (
        where row.linked_destination_ledger_id is null
          or row.destination_organization_id
            <> row.organization_id
          or row.destination_transaction_id <> row.transaction_id
          or row.destination_product_id <> row.product_id
          or row.destination_batch_id <> row.batch_id
          or row.ledger_destination_bucket_code
            <> row.allocation_destination_bucket_code
          or row.destination_quantity_delta
            <> row.quantity_allocated
          or row.destination_entry_role_code <> 'DESTINATION'
          or row.destination_pair_no <> row.pair_no
          or row.destination_source_line_ref
            <> (
              row.event_source_line_ref
                || ':'
                || row.allocation_destination_bucket_code
                || ':DESTINATION'
            )
      )::bigint as invalid_destination_ledger_count
    from allocation_rows row
    group by row.inspection_id
  ),
  orphan_stats as (
    select
      base.inspection_id,
      count(ledger_entry.id)::bigint as orphan_ledger_count
    from inspection_base base
    join inventory.stock_ledger_entries ledger_entry
      on ledger_entry.organization_id = base.organization_id
     and ledger_entry.transaction_id = base.transaction_id
    where not exists (
      select 1
      from operations.return_inspection_allocations allocation
      where allocation.organization_id = base.organization_id
        and allocation.inspection_id = base.inspection_id
        and (
          allocation.source_ledger_entry_id = ledger_entry.id
          or allocation.destination_ledger_entry_id =
            ledger_entry.id
        )
    )
    group by base.inspection_id
  ),
  compared as (
    select
      base.organization_id,
      base.inspection_id,
      base.return_id,
      base.event_id,
      base.inspection_ref,
      base.transaction_id,
      coalesce(event_stats.event_line_quantity, 0)::bigint
        as event_line_quantity,
      coalesce(
        allocation_stats.allocation_quantity,
        0
      )::bigint as allocation_quantity,
      coalesce(
        allocation_stats.source_quarantine_quantity,
        0
      )::bigint as source_quarantine_quantity,
      coalesce(
        allocation_stats.destination_quantity,
        0
      )::bigint as destination_quantity,
      coalesce(
        allocation_stats.net_quantity,
        0
      )::bigint as net_quantity,
      coalesce(event_stats.event_line_count, 0)::bigint
        as event_line_count,
      coalesce(
        allocation_stats.allocation_count,
        0
      )::bigint as allocation_count,
      coalesce(
        allocation_stats.source_ledger_count,
        0
      )::bigint as source_ledger_count,
      coalesce(
        allocation_stats.destination_ledger_count,
        0
      )::bigint as destination_ledger_count,
      base.invalid_header_count,
      coalesce(
        line_mismatch_stats.line_total_mismatch_count,
        0
      )::bigint as line_total_mismatch_count,
      coalesce(
        allocation_stats.invalid_allocation_count,
        0
      )::bigint as invalid_allocation_count,
      coalesce(
        allocation_stats.invalid_source_ledger_count,
        0
      )::bigint as invalid_source_ledger_count,
      coalesce(
        allocation_stats.invalid_destination_ledger_count,
        0
      )::bigint as invalid_destination_ledger_count,
      coalesce(
        orphan_stats.orphan_ledger_count,
        0
      )::bigint as orphan_ledger_count
    from inspection_base base
    left join event_stats
      on event_stats.inspection_id = base.inspection_id
    left join line_mismatch_stats
      on line_mismatch_stats.inspection_id = base.inspection_id
    left join allocation_stats
      on allocation_stats.inspection_id = base.inspection_id
    left join orphan_stats
      on orphan_stats.inspection_id = base.inspection_id
  )
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
      when compared.event_line_quantity
        <> compared.allocation_quantity
        then 'RETURN_INSPECTION_EVENT_TOTAL_MISMATCH'
      when compared.allocation_quantity
        <> compared.source_quarantine_quantity
        then 'RETURN_INSPECTION_SOURCE_TOTAL_MISMATCH'
      when compared.allocation_quantity
        <> compared.destination_quantity
        then 'RETURN_INSPECTION_DESTINATION_TOTAL_MISMATCH'
      else 'RETURN_INSPECTION_NOT_NET_ZERO'
    end as issue_code
  from compared
  where compared.invalid_header_count > 0
    or compared.line_total_mismatch_count > 0
    or compared.event_line_count = 0
    or compared.allocation_count = 0
    or compared.invalid_allocation_count > 0
    or compared.invalid_source_ledger_count > 0
    or compared.invalid_destination_ledger_count > 0
    or compared.orphan_ledger_count > 0
    or compared.event_line_quantity
      <> compared.allocation_quantity
    or compared.allocation_quantity
      <> compared.source_quarantine_quantity
    or compared.allocation_quantity
      <> compared.destination_quantity
    or compared.net_quantity <> 0
    or compared.source_ledger_count
      <> compared.allocation_count
    or compared.destination_ledger_count
      <> compared.allocation_count;
$$;

revoke all on function
  reconciliation.find_return_inspection_transfer_mismatches(uuid)
from public, anon, authenticated, service_role;

commit;