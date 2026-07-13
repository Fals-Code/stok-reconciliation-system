begin;

grant select on catalog.channels,
                inventory.stock_reservations
  to service_role;

commit;
