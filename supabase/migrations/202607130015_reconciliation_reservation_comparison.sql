begin;

create or replace function reconciliation.find_reservation_consistency_mismatches(
  p_organization_id uuid
)
returns table (
  product_id uuid,
  expected_reserved_qty bigint,
  actual_reserved_qty bigint,
  sellable_qty bigint,
  expected_available_qty bigint,
  actual_available_qty bigint,
  reservation_difference bigint,
  issue_code text
)
language sql
stable
security definer
set search_path = pg_catalog, inventory
as $$
  with reservation_aggregate as (
    select
      reservation.product_id,
      sum(
        reservation.reserved_qty
        - reservation.consumed_qty
        - reservation.released_qty
      )::bigint as expected_reserved_qty
    from inventory.stock_reservations reservation
    where reservation.organization_id = p_organization_id
      and (
        reservation.reserved_qty
        - reservation.consumed_qty
        - reservation.released_qty
      ) > 0
    group by reservation.product_id
  ),
  entity_keys as (
    select aggregate.product_id
    from reservation_aggregate aggregate

    union

    select position.product_id
    from inventory.stock_product_positions position
    where position.organization_id = p_organization_id
  ),
  comparison as (
    select
      entity.product_id,

      coalesce(
        aggregate.expected_reserved_qty,
        0
      )::bigint as expected_reserved_qty,

      coalesce(
        position.reserved_qty,
        0
      )::bigint as actual_reserved_qty,

      coalesce(
        position.sellable_qty,
        0
      )::bigint as sellable_qty
    from entity_keys entity
    left join reservation_aggregate aggregate
      on aggregate.product_id = entity.product_id
    left join inventory.stock_product_positions position
      on position.organization_id = p_organization_id
     and position.product_id = entity.product_id
  )
  select
    comparison.product_id,
    comparison.expected_reserved_qty,
    comparison.actual_reserved_qty,
    comparison.sellable_qty,

    (
      comparison.sellable_qty
      - comparison.expected_reserved_qty
    )::bigint as expected_available_qty,

    (
      comparison.sellable_qty
      - comparison.actual_reserved_qty
    )::bigint as actual_available_qty,

    (
      comparison.actual_reserved_qty
      - comparison.expected_reserved_qty
    )::bigint as reservation_difference,

    case
      when comparison.expected_reserved_qty
             > comparison.sellable_qty
        then 'RESERVATION_EXCEEDS_SELLABLE'

      when comparison.actual_reserved_qty
             > comparison.sellable_qty
        then 'PROJECTION_RESERVED_EXCEEDS_SELLABLE'

      else 'RESERVATION_PROJECTION_MISMATCH'
    end as issue_code
  from comparison
  where comparison.expected_reserved_qty
          <> comparison.actual_reserved_qty
     or comparison.expected_reserved_qty
          > comparison.sellable_qty
     or comparison.actual_reserved_qty
          > comparison.sellable_qty
  order by comparison.product_id
$$;

revoke all on function
  reconciliation.find_reservation_consistency_mismatches(uuid)
from public, anon, authenticated, service_role;

commit;