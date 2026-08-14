begin;

create or replace function api.product_stock_explanation(p_product_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, catalog, inventory
as $$
  with authorized_product as materialized (
    select product.id, product.organization_id
    from catalog.products product
    where product.id = p_product_id
  ),
  boundary as materialized (
    select coalesce(max(entry.ledger_seq), 0)::bigint as ledger_seq
    from inventory.stock_ledger_entries entry
    join authorized_product product
      on product.organization_id = entry.organization_id
     and product.id = entry.product_id
  ),
  raw_entries as materialized (
    select entry.ledger_seq, entry.transaction_id, entry.bucket_code, entry.quantity_delta
    from inventory.stock_ledger_entries entry
    join authorized_product product
      on product.organization_id = entry.organization_id
     and product.id = entry.product_id
    cross join boundary
    where entry.ledger_seq <= boundary.ledger_seq
  ),
  ledger_totals as materialized (
    select
      coalesce(sum(quantity_delta) filter (where bucket_code = 'SELLABLE'), 0)::bigint as sellable_qty,
      coalesce(sum(quantity_delta) filter (where bucket_code = 'QUARANTINE'), 0)::bigint as quarantine_qty,
      coalesce(sum(quantity_delta) filter (where bucket_code = 'DAMAGED'), 0)::bigint as damaged_qty
    from raw_entries
  ),
  enriched_entries as materialized (
    select raw.ledger_seq, raw.bucket_code, raw.quantity_delta,
      coalesce(transaction.transaction_type_code, 'UNCLASSIFIED_LEDGER_ENTRY') as transaction_type_code,
      coalesce(transaction.reason_code_snapshot, 'UNAVAILABLE') as reason_code_snapshot,
      coalesce(transaction.channel_code_snapshot, 'UNAVAILABLE') as channel_code_snapshot,
      coalesce(transaction.source_type_code, 'UNAVAILABLE') as source_type_code
    from raw_entries raw
    left join inventory.stock_transactions transaction
      on transaction.id = raw.transaction_id
     and transaction.organization_id = (select organization_id from authorized_product)
  ),
  projection as materialized (
    select coalesce(position.sellable_qty, 0)::bigint as sellable_qty,
      coalesce(position.quarantine_qty, 0)::bigint as quarantine_qty,
      coalesce(position.damaged_qty, 0)::bigint as damaged_qty,
      coalesce(position.reserved_qty, 0)::bigint as reserved_qty
    from authorized_product product
    left join inventory.stock_product_positions position
      on position.organization_id = product.organization_id and position.product_id = product.id
  ),
  grouped_evidence as materialized (
    select coalesce(jsonb_agg(jsonb_build_object(
      'transactionTypeCode', grouped.transaction_type_code,
      'reasonCode', grouped.reason_code_snapshot,
      'channelCode', grouped.channel_code_snapshot,
      'sourceTypeCode', grouped.source_type_code,
      'sellableDelta', grouped.sellable_qty,
      'quarantineDelta', grouped.quarantine_qty,
      'damagedDelta', grouped.damaged_qty,
      'onHandDelta', grouped.sellable_qty + grouped.quarantine_qty + grouped.damaged_qty
    ) order by grouped.transaction_type_code, grouped.reason_code_snapshot, grouped.channel_code_snapshot, grouped.source_type_code), '[]'::jsonb) as movements
    from (
      select transaction_type_code, reason_code_snapshot, channel_code_snapshot, source_type_code,
        coalesce(sum(quantity_delta) filter (where bucket_code = 'SELLABLE'), 0)::bigint as sellable_qty,
        coalesce(sum(quantity_delta) filter (where bucket_code = 'QUARANTINE'), 0)::bigint as quarantine_qty,
        coalesce(sum(quantity_delta) filter (where bucket_code = 'DAMAGED'), 0)::bigint as damaged_qty
      from enriched_entries
      group by transaction_type_code, reason_code_snapshot, channel_code_snapshot, source_type_code
    ) grouped
  )
  select jsonb_build_object(
    'ledgerBoundarySeq', boundary.ledger_seq,
    'ledger', jsonb_build_object('sellableQty', ledger_totals.sellable_qty, 'quarantineQty', ledger_totals.quarantine_qty, 'damagedQty', ledger_totals.damaged_qty, 'onHandQty', ledger_totals.sellable_qty + ledger_totals.quarantine_qty + ledger_totals.damaged_qty),
    'projection', jsonb_build_object('sellableQty', projection.sellable_qty, 'quarantineQty', projection.quarantine_qty, 'damagedQty', projection.damaged_qty, 'reservedQty', projection.reserved_qty, 'availableQty', projection.sellable_qty - projection.reserved_qty, 'onHandQty', projection.sellable_qty + projection.quarantine_qty + projection.damaged_qty),
    'comparison', jsonb_build_object('sellableMatches', ledger_totals.sellable_qty = projection.sellable_qty, 'quarantineMatches', ledger_totals.quarantine_qty = projection.quarantine_qty, 'damagedMatches', ledger_totals.damaged_qty = projection.damaged_qty, 'onHandMatches', ledger_totals.sellable_qty + ledger_totals.quarantine_qty + ledger_totals.damaged_qty = projection.sellable_qty + projection.quarantine_qty + projection.damaged_qty),
    'groupedMovements', grouped_evidence.movements
  )
  from authorized_product cross join boundary cross join ledger_totals cross join projection cross join grouped_evidence
$$;

revoke all on function api.product_stock_explanation(uuid) from public, anon;
grant execute on function api.product_stock_explanation(uuid) to authenticated, service_role;

commit;