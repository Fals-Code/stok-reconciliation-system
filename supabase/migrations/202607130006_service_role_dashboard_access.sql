begin;

grant usage on schema app, catalog, inventory, api to service_role;

grant select on catalog.products,
                catalog.product_batches
 to service_role;

grant select on inventory.stock_transactions,
                inventory.stock_ledger_entries,
                inventory.stock_batch_balances,
                inventory.stock_product_positions
 to service_role;

grant select on api.product_inventory,
                api.batch_inventory,
                api.stock_ledger
 to service_role;

commit;
