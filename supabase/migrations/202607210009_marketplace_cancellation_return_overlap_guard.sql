begin;

create or replace function operations.guard_return_item_cancellation_overlap()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, operations, inventory
as $$
declare
  v_shipped_qty bigint;
  v_existing_expected_qty bigint;
  v_post_cancelled_qty bigint;
begin
  perform pg_advisory_xact_lock(
    hashtextextended(
      new.organization_id::text ||
      ':RETURNABLE_ORDER_ITEM:' ||
      new.marketplace_order_item_id::text,
      0::bigint
    )
  );

  select coalesce(sum(allocation.quantity_allocated), 0)::bigint
  into v_shipped_qty
  from operations.marketplace_ship_allocations allocation
  join operations.marketplace_event_lines event_line
    on event_line.organization_id = allocation.organization_id
   and event_line.id = allocation.event_line_id
  join operations.marketplace_events marketplace_event
    on marketplace_event.organization_id = allocation.organization_id
   and marketplace_event.id = allocation.event_id
  where allocation.organization_id = new.organization_id
    and event_line.order_item_id = new.marketplace_order_item_id
    and marketplace_event.event_type_code = 'SHIP';

  select coalesce(sum(return_item.expected_qty), 0)::bigint
  into v_existing_expected_qty
  from operations.return_items return_item
  where return_item.organization_id = new.organization_id
    and return_item.marketplace_order_item_id =
      new.marketplace_order_item_id
    and return_item.id <> new.id;

  select coalesce(
    sum(application.quantity_applied) filter (
      where application.effect_code = 'POST_SHIPMENT_REVERSAL'
    ),
    0
  )::bigint
  into v_post_cancelled_qty
  from operations.marketplace_cancellation_applications application
  join operations.marketplace_cancellation_lines cancellation_line
    on cancellation_line.organization_id = application.organization_id
   and cancellation_line.id = application.cancellation_line_id
  where cancellation_line.organization_id = new.organization_id
    and cancellation_line.order_item_id =
      new.marketplace_order_item_id;

  if (
    v_existing_expected_qty +
    new.expected_qty +
    v_post_cancelled_qty
  ) > v_shipped_qty then
    raise exception using
      errcode = 'P0001',
      message = 'RETURN_QUANTITY_EXCEEDS_SHIPPED';
  end if;

  return new;
end;
$$;

revoke all
on function operations.guard_return_item_cancellation_overlap()
from public, anon, authenticated;

create trigger trg_return_items_marketplace_cancellation_overlap
before insert
or update of organization_id, marketplace_order_item_id, expected_qty
on operations.return_items
for each row
execute function operations.guard_return_item_cancellation_overlap();

comment on function operations.guard_return_item_cancellation_overlap()
is
  'Serializes return expectation with post-shipment cancellation and prevents both domains from claiming the same shipped quantity.';

commit;
