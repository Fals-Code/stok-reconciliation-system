begin;

create or replace function reconciliation.find_marketplace_allocation_mismatches(
  p_organization_id uuid
)
returns table (
  event_id uuid,
  order_id uuid,
  transaction_id uuid,
  channel_id uuid,
  external_event_ref text,
  external_order_ref text,
  event_line_quantity bigint,
  allocation_quantity bigint,
  ledger_outbound_quantity bigint,
  event_line_count bigint,
  allocation_count bigint,
  ledger_entry_count bigint,
  invalid_allocation_count bigint,
  invalid_ledger_count bigint,
  orphan_ledger_count bigint,
  issue_code text
)
language sql
stable
security definer
set search_path = pg_catalog, inventory, operations
as $$
  with ship_events as (
    select
      marketplace_event.organization_id,
      marketplace_event.id as event_id,
      marketplace_event.order_id,
      marketplace_event.transaction_id,
      marketplace_event.channel_id,
      marketplace_event.external_event_ref,
      marketplace_order.external_order_ref,
      stock_transaction.id as linked_transaction_id,
      stock_transaction.transaction_type_code,
      stock_transaction.reason_code_snapshot,
      stock_transaction.channel_id as transaction_channel_id,
      stock_transaction.source_type_code,
      stock_transaction.source_id,
      stock_transaction.source_ref_snapshot
    from operations.marketplace_events marketplace_event
    join operations.marketplace_orders marketplace_order
      on marketplace_order.organization_id =
        marketplace_event.organization_id
     and marketplace_order.id =
        marketplace_event.order_id
    left join inventory.stock_transactions stock_transaction
      on stock_transaction.organization_id =
        marketplace_event.organization_id
     and stock_transaction.id =
        marketplace_event.transaction_id
    where marketplace_event.organization_id =
        p_organization_id
      and marketplace_event.event_type_code = 'SHIP'
  ),
  line_aggregate as (
    select
      ship.event_id,
      count(event_line.id)::bigint as event_line_count,
      coalesce(
        sum(event_line.quantity),
        0
      )::bigint as event_line_quantity
    from ship_events ship
    left join operations.marketplace_event_lines event_line
      on event_line.organization_id = ship.organization_id
     and event_line.event_id = ship.event_id
    group by ship.event_id
  ),
  allocation_aggregate as (
    select
      ship.event_id,

      count(allocation.id)::bigint as allocation_count,

      coalesce(
        sum(allocation.quantity_allocated),
        0
      )::bigint as allocation_quantity,

      count(*) filter (
        where allocation.id is not null
          and (
            allocation.event_id is distinct from ship.event_id

            or event_line.id is null

            or event_line.event_id is distinct from ship.event_id

            or allocation.product_id
                 is distinct from event_line.product_id

            or allocation.source_line_ref
                 is distinct from event_line.source_line_ref

            or ledger_entry.id is null

            or ledger_entry.transaction_id
                 is distinct from ship.transaction_id

            or ledger_entry.product_id
                 is distinct from allocation.product_id

            or ledger_entry.batch_id
                 is distinct from allocation.batch_id

            or ledger_entry.bucket_code
                 is distinct from 'SELLABLE'

            or ledger_entry.entry_role_code
                 is distinct from 'EXTERNAL_OUT'

            or ledger_entry.quantity_delta >= 0

            or -ledger_entry.quantity_delta
                 is distinct from allocation.quantity_allocated

            or ledger_entry.source_line_ref
                 is distinct from (
                   event_line.source_line_ref
                   || ':'
                   || allocation.allocation_no::text
                 )
          )
      )::bigint as invalid_allocation_count
    from ship_events ship
    left join operations.marketplace_ship_allocations allocation
      on allocation.organization_id = ship.organization_id
     and allocation.event_id = ship.event_id
    left join operations.marketplace_event_lines event_line
      on event_line.organization_id = allocation.organization_id
     and event_line.id = allocation.event_line_id
    left join inventory.stock_ledger_entries ledger_entry
      on ledger_entry.organization_id = allocation.organization_id
     and ledger_entry.id = allocation.ledger_entry_id
    group by ship.event_id
  ),
  ledger_aggregate as (
    select
      ship.event_id,

      count(ledger_entry.id)::bigint as ledger_entry_count,

      coalesce(
        sum(
          case
            when ledger_entry.quantity_delta < 0
              then -ledger_entry.quantity_delta
            else 0
          end
        ),
        0
      )::bigint as ledger_outbound_quantity,

      count(*) filter (
        where ledger_entry.id is not null
          and (
            ledger_entry.bucket_code
              is distinct from 'SELLABLE'

            or ledger_entry.entry_role_code
              is distinct from 'EXTERNAL_OUT'

            or ledger_entry.quantity_delta >= 0
          )
      )::bigint as invalid_ledger_count,

      count(*) filter (
        where ledger_entry.id is not null
          and not exists (
            select 1
            from operations.marketplace_ship_allocations allocation
            where allocation.organization_id =
                ship.organization_id
              and allocation.event_id = ship.event_id
              and allocation.ledger_entry_id =
                ledger_entry.id
          )
      )::bigint as orphan_ledger_count
    from ship_events ship
    left join inventory.stock_ledger_entries ledger_entry
      on ledger_entry.organization_id = ship.organization_id
     and ledger_entry.transaction_id = ship.transaction_id
    group by ship.event_id
  ),
  comparison as (
    select
      ship.*,

      coalesce(
        line.event_line_quantity,
        0
      )::bigint as event_line_quantity,

      coalesce(
        allocation.allocation_quantity,
        0
      )::bigint as allocation_quantity,

      coalesce(
        ledger.ledger_outbound_quantity,
        0
      )::bigint as ledger_outbound_quantity,

      coalesce(
        line.event_line_count,
        0
      )::bigint as event_line_count,

      coalesce(
        allocation.allocation_count,
        0
      )::bigint as allocation_count,

      coalesce(
        ledger.ledger_entry_count,
        0
      )::bigint as ledger_entry_count,

      coalesce(
        allocation.invalid_allocation_count,
        0
      )::bigint as invalid_allocation_count,

      coalesce(
        ledger.invalid_ledger_count,
        0
      )::bigint as invalid_ledger_count,

      coalesce(
        ledger.orphan_ledger_count,
        0
      )::bigint as orphan_ledger_count
    from ship_events ship
    left join line_aggregate line
      on line.event_id = ship.event_id
    left join allocation_aggregate allocation
      on allocation.event_id = ship.event_id
    left join ledger_aggregate ledger
      on ledger.event_id = ship.event_id
  )
  select
    comparison.event_id,
    comparison.order_id,
    comparison.transaction_id,
    comparison.channel_id,
    comparison.external_event_ref,
    comparison.external_order_ref,
    comparison.event_line_quantity,
    comparison.allocation_quantity,
    comparison.ledger_outbound_quantity,
    comparison.event_line_count,
    comparison.allocation_count,
    comparison.ledger_entry_count,
    comparison.invalid_allocation_count,
    comparison.invalid_ledger_count,
    comparison.orphan_ledger_count,

    case
      when comparison.linked_transaction_id is null
        or comparison.transaction_type_code
             is distinct from 'MARKETPLACE_OUTBOUND'
        or comparison.reason_code_snapshot
             is distinct from 'MARKETPLACE_SALE'
        or comparison.transaction_channel_id
             is distinct from comparison.channel_id
        or comparison.source_type_code
             is distinct from 'MARKETPLACE_ORDER'
        or comparison.source_id
             is distinct from comparison.order_id
        or comparison.source_ref_snapshot
             is distinct from comparison.external_order_ref
        then 'MARKETPLACE_OUTBOUND_TRANSACTION_INVALID'

      when comparison.invalid_allocation_count > 0
        then 'MARKETPLACE_ALLOCATION_LINK_INVALID'

      when comparison.invalid_ledger_count > 0
        then 'MARKETPLACE_OUTBOUND_LEDGER_INVALID'

      when comparison.orphan_ledger_count > 0
        then 'MARKETPLACE_ORPHAN_LEDGER_ENTRY'

      when comparison.event_line_quantity
             <> comparison.allocation_quantity
        then 'MARKETPLACE_ALLOCATION_TOTAL_MISMATCH'

      else 'MARKETPLACE_LEDGER_TOTAL_MISMATCH'
    end as issue_code
  from comparison
  where comparison.event_line_count = 0

     or comparison.linked_transaction_id is null

     or comparison.transaction_type_code
          is distinct from 'MARKETPLACE_OUTBOUND'

     or comparison.reason_code_snapshot
          is distinct from 'MARKETPLACE_SALE'

     or comparison.transaction_channel_id
          is distinct from comparison.channel_id

     or comparison.source_type_code
          is distinct from 'MARKETPLACE_ORDER'

     or comparison.source_id
          is distinct from comparison.order_id

     or comparison.source_ref_snapshot
          is distinct from comparison.external_order_ref

     or comparison.invalid_allocation_count > 0

     or comparison.invalid_ledger_count > 0

     or comparison.orphan_ledger_count > 0

     or comparison.event_line_quantity
          <> comparison.allocation_quantity

     or comparison.event_line_quantity
          <> comparison.ledger_outbound_quantity

     or comparison.allocation_quantity
          <> comparison.ledger_outbound_quantity
  order by comparison.event_id
$$;

revoke all on function
  reconciliation.find_marketplace_allocation_mismatches(uuid)
from public, anon, authenticated, service_role;

commit;