begin;

create or replace function reconciliation.find_return_receipt_quarantine_mismatches(
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
set search_path = pg_catalog, inventory, operations
as $$
  with relevant_events as (
    select
      event.organization_id,
      event.id as event_id,
      event.return_id,
      event.external_event_ref,
      event.event_type_code,
      event.transaction_id,
      return_header.external_return_ref,
      return_header.channel_id
    from operations.return_events event
    join operations.returns return_header
      on return_header.organization_id =
          event.organization_id
     and return_header.id = event.return_id
    where event.organization_id = p_organization_id
      and event.event_type_code in (
        'EXPECTED',
        'RECEIPT',
        'LOST'
      )
  ),
  receipt_context as (
    select
      event.*,
      receipt.id as receipt_id,
      receipt.receipt_ref,
      receipt.transaction_id as receipt_transaction_id,
      stock_transaction.id as linked_transaction_id,
      stock_transaction.transaction_type_code,
      stock_transaction.reason_code_snapshot,
      stock_transaction.channel_id as transaction_channel_id,
      stock_transaction.source_type_code,
      stock_transaction.source_id,
      stock_transaction.source_ref_snapshot
    from relevant_events event
    left join operations.return_receipts receipt
      on receipt.organization_id = event.organization_id
     and receipt.event_id = event.event_id
    left join inventory.stock_transactions stock_transaction
      on stock_transaction.organization_id =
          event.organization_id
     and stock_transaction.id = event.transaction_id
  ),
  event_line_aggregate as (
    select
      event.event_id,
      count(event_line.id)::bigint as event_line_count,
      coalesce(
        sum(event_line.quantity),
        0
      )::bigint as event_line_quantity
    from relevant_events event
    left join operations.return_event_lines event_line
      on event_line.organization_id =
          event.organization_id
     and event_line.event_id = event.event_id
    group by event.event_id
  ),
  receipt_line_aggregate as (
    select
      context.event_id,

      count(receipt_line.id)::bigint
        as receipt_line_count,

      coalesce(
        sum(receipt_line.quantity_received),
        0
      )::bigint as receipt_quantity,

      count(*) filter (
        where receipt_line.id is not null
          and (
            event_line.id is null

            or event_line.event_id
                 is distinct from context.event_id

            or event_line.return_item_id
                 is distinct from receipt_line.return_item_id

            or event_line.quantity
                 is distinct from receipt_line.quantity_received

            or event_line.outcome_code
                 is distinct from 'QUARANTINE'

            or event_line.source_line_ref
                 is distinct from receipt_line.source_line_ref

            or return_item.id is null

            or return_item.return_id
                 is distinct from context.return_id

            or return_item.product_id
                 is distinct from receipt_line.product_id

            or ledger_entry.id is null

            or ledger_entry.transaction_id
                 is distinct from context.transaction_id

            or ledger_entry.product_id
                 is distinct from receipt_line.product_id

            or ledger_entry.batch_id
                 is distinct from receipt_line.batch_id

            or ledger_entry.bucket_code
                 is distinct from 'QUARANTINE'

            or ledger_entry.quantity_delta
                 is distinct from receipt_line.quantity_received

            or ledger_entry.entry_role_code
                 is distinct from 'EXTERNAL_IN'

            or ledger_entry.source_line_ref
                 is distinct from receipt_line.source_line_ref
          )
      )::bigint as invalid_receipt_line_count
    from receipt_context context
    left join operations.return_receipt_lines receipt_line
      on receipt_line.organization_id =
          context.organization_id
     and receipt_line.receipt_id = context.receipt_id
    left join operations.return_event_lines event_line
      on event_line.organization_id =
          receipt_line.organization_id
     and event_line.id = receipt_line.event_line_id
    left join operations.return_items return_item
      on return_item.organization_id =
          receipt_line.organization_id
     and return_item.id = receipt_line.return_item_id
    left join inventory.stock_ledger_entries ledger_entry
      on ledger_entry.organization_id =
          receipt_line.organization_id
     and ledger_entry.id = receipt_line.ledger_entry_id
    group by context.event_id
  ),
  ledger_aggregate as (
    select
      context.event_id,

      count(ledger_entry.id)::bigint
        as ledger_entry_count,

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

      count(*) filter (
        where ledger_entry.id is not null
          and (
            ledger_entry.bucket_code
              is distinct from 'QUARANTINE'

            or ledger_entry.quantity_delta <= 0

            or ledger_entry.entry_role_code
              is distinct from 'EXTERNAL_IN'
          )
      )::bigint as invalid_ledger_count,

      count(*) filter (
        where ledger_entry.id is not null
          and not exists (
            select 1
            from operations.return_receipt_lines receipt_line
            where receipt_line.organization_id =
                context.organization_id
              and receipt_line.receipt_id =
                context.receipt_id
              and receipt_line.ledger_entry_id =
                ledger_entry.id
          )
      )::bigint as orphan_ledger_count
    from receipt_context context
    left join inventory.stock_ledger_entries ledger_entry
      on ledger_entry.organization_id =
          context.organization_id
     and ledger_entry.transaction_id =
          context.transaction_id
    group by context.event_id
  ),
  nonphysical_effects as (
    select
      event.event_id,

      count(
        distinct stock_effect.transaction_id
      )::bigint as unexpected_transaction_count
    from relevant_events event
    left join lateral (
      select event.transaction_id as transaction_id
      where event.transaction_id is not null

      union

      select stock_transaction.id
      from inventory.stock_transactions stock_transaction
      where stock_transaction.organization_id =
          event.organization_id
        and stock_transaction.source_type_code = 'RETURN'
        and stock_transaction.source_id = event.return_id
        and stock_transaction.source_ref_snapshot =
            event.external_event_ref
    ) stock_effect on true
    where event.event_type_code in ('EXPECTED', 'LOST')
    group by event.event_id
  ),
  comparison as (
    select
      context.*,

      coalesce(
        event_line.event_line_quantity,
        0
      )::bigint as event_line_quantity,

      coalesce(
        receipt_line.receipt_quantity,
        0
      )::bigint as receipt_quantity,

      coalesce(
        ledger.ledger_quarantine_quantity,
        0
      )::bigint as ledger_quarantine_quantity,

      coalesce(
        event_line.event_line_count,
        0
      )::bigint as event_line_count,

      coalesce(
        receipt_line.receipt_line_count,
        0
      )::bigint as receipt_line_count,

      coalesce(
        ledger.ledger_entry_count,
        0
      )::bigint as ledger_entry_count,

      coalesce(
        receipt_line.invalid_receipt_line_count,
        0
      )::bigint as invalid_receipt_line_count,

      coalesce(
        ledger.invalid_ledger_count,
        0
      )::bigint as invalid_ledger_count,

      coalesce(
        ledger.orphan_ledger_count,
        0
      )::bigint as orphan_ledger_count,

      coalesce(
        nonphysical.unexpected_transaction_count,
        0
      )::bigint as unexpected_transaction_count
    from receipt_context context
    left join event_line_aggregate event_line
      on event_line.event_id = context.event_id
    left join receipt_line_aggregate receipt_line
      on receipt_line.event_id = context.event_id
    left join ledger_aggregate ledger
      on ledger.event_id = context.event_id
    left join nonphysical_effects nonphysical
      on nonphysical.event_id = context.event_id
  )
  select
    comparison.event_id,
    comparison.return_id,
    comparison.receipt_id,
    comparison.transaction_id,
    comparison.event_type_code,
    comparison.external_event_ref,
    comparison.external_return_ref,
    comparison.receipt_ref,
    comparison.event_line_quantity,
    comparison.receipt_quantity,
    comparison.ledger_quarantine_quantity,
    comparison.event_line_count,
    comparison.receipt_line_count,
    comparison.ledger_entry_count,
    comparison.invalid_receipt_line_count,
    comparison.invalid_ledger_count,
    comparison.orphan_ledger_count,
    comparison.unexpected_transaction_count,

    case
      when comparison.event_type_code in (
        'EXPECTED',
        'LOST'
      )
        then 'RETURN_NONPHYSICAL_EVENT_HAS_STOCK_EFFECT'

      when comparison.receipt_id is null
        or comparison.linked_transaction_id is null
        or comparison.receipt_transaction_id
             is distinct from comparison.transaction_id
        or comparison.receipt_ref
             is distinct from comparison.external_event_ref
        or comparison.transaction_type_code
             is distinct from 'RETURN_RECEIPT'
        or comparison.reason_code_snapshot
             is distinct from 'RETURN_RECEIVED'
        or comparison.transaction_channel_id
             is distinct from comparison.channel_id
        or comparison.source_type_code
             is distinct from 'RETURN'
        or comparison.source_id
             is distinct from comparison.return_id
        or comparison.source_ref_snapshot
             is distinct from comparison.receipt_ref
        then 'RETURN_RECEIPT_TRANSACTION_INVALID'

      when comparison.invalid_receipt_line_count > 0
        then 'RETURN_RECEIPT_LINE_LINK_INVALID'

      when comparison.invalid_ledger_count > 0
        then 'RETURN_RECEIPT_LEDGER_INVALID'

      when comparison.orphan_ledger_count > 0
        then 'RETURN_RECEIPT_ORPHAN_LEDGER_ENTRY'

      when comparison.event_line_quantity
             <> comparison.receipt_quantity
        or comparison.event_line_count = 0
        or comparison.receipt_line_count = 0
        then 'RETURN_RECEIPT_TOTAL_MISMATCH'

      else 'RETURN_RECEIPT_LEDGER_TOTAL_MISMATCH'
    end as issue_code
  from comparison
  where (
    comparison.event_type_code in ('EXPECTED', 'LOST')
    and comparison.unexpected_transaction_count > 0
  )
  or (
    comparison.event_type_code = 'RECEIPT'
    and (
      comparison.receipt_id is null

      or comparison.linked_transaction_id is null

      or comparison.receipt_transaction_id
           is distinct from comparison.transaction_id

      or comparison.receipt_ref
           is distinct from comparison.external_event_ref

      or comparison.transaction_type_code
           is distinct from 'RETURN_RECEIPT'

      or comparison.reason_code_snapshot
           is distinct from 'RETURN_RECEIVED'

      or comparison.transaction_channel_id
           is distinct from comparison.channel_id

      or comparison.source_type_code
           is distinct from 'RETURN'

      or comparison.source_id
           is distinct from comparison.return_id

      or comparison.source_ref_snapshot
           is distinct from comparison.receipt_ref

      or comparison.event_line_count = 0

      or comparison.receipt_line_count = 0

      or comparison.invalid_receipt_line_count > 0

      or comparison.invalid_ledger_count > 0

      or comparison.orphan_ledger_count > 0

      or comparison.event_line_quantity
           <> comparison.receipt_quantity

      or comparison.event_line_quantity
           <> comparison.ledger_quarantine_quantity

      or comparison.receipt_quantity
           <> comparison.ledger_quarantine_quantity
    )
  )
  order by
    comparison.event_type_code,
    comparison.event_id
$$;

revoke all on function
  reconciliation.find_return_receipt_quarantine_mismatches(uuid)
from public, anon, authenticated, service_role;

commit;