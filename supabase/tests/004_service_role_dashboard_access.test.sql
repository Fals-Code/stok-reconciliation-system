begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

select ok(
  has_schema_privilege('service_role', 'api', 'USAGE'),
  'service role can use api schema'
);
select ok(
  has_schema_privilege('service_role', 'catalog', 'USAGE'),
  'service role can use catalog schema'
);
select ok(
  has_schema_privilege('service_role', 'inventory', 'USAGE'),
  'service role can use inventory schema'
);
select ok(
  has_table_privilege('service_role', 'api.product_inventory', 'SELECT'),
  'service role can read product inventory view'
);
select ok(
  has_table_privilege('service_role', 'api.batch_inventory', 'SELECT'),
  'service role can read batch inventory view'
);
select ok(
  has_table_privilege('service_role', 'api.stock_ledger', 'SELECT'),
  'service role can read stock ledger view'
);
select ok(
  has_table_privilege('service_role', 'catalog.products', 'SELECT'),
  'service role can read products through security invoker view'
);
select ok(
  has_table_privilege('service_role', 'catalog.product_batches', 'SELECT'),
  'service role can read batches through security invoker view'
);
select ok(
  has_table_privilege('service_role', 'inventory.stock_product_positions', 'SELECT'),
  'service role can read product positions through security invoker view'
);
select ok(
  has_table_privilege('service_role', 'inventory.stock_batch_balances', 'SELECT'),
  'service role can read batch balances through security invoker view'
);
select ok(
  has_table_privilege('service_role', 'inventory.stock_transactions', 'SELECT'),
  'service role can read transactions through security invoker view'
);
select ok(
  has_table_privilege('service_role', 'inventory.stock_ledger_entries', 'SELECT'),
  'service role can read ledger entries through security invoker view'
);
select ok(
  not has_table_privilege('service_role', 'inventory.stock_ledger_entries', 'INSERT'),
  'service role still cannot insert ledger entries directly'
);

select * from finish();
rollback;
