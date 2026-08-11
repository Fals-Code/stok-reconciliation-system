begin;

create or replace view api.marketplace_ship_allocation_context
with (
  security_invoker = true,
  security_barrier = true
)
as
select
  allocation.id as allocation_id,
  allocation.organization_id,
  allocation.event_id,
  allocation.event_line_id,
  event_line.order_item_id,
  allocation.allocation_no,
  allocation.product_id,
  allocation.batch_id,
  allocation.quantity_allocated,
  allocation.product_sku_snapshot,
  allocation.batch_code_snapshot,
  allocation.expiry_date_snapshot,
  allocation.received_first_at_snapshot,
  allocation.source_line_ref,
  allocation.created_at
from operations.marketplace_ship_allocations allocation
join operations.marketplace_event_lines event_line
  on event_line.organization_id = allocation.organization_id
 and event_line.id = allocation.event_line_id;

revoke all on api.marketplace_ship_allocation_context from public, anon;
grant select on api.marketplace_ship_allocation_context
to authenticated, service_role;

commit;
