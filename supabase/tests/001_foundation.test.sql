begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

select has_schema('app');
select has_schema('catalog');
select has_schema('inventory');
select has_schema('notification');
select has_schema('api');

-- pgTAP overloads text arguments as object names or test descriptions.
-- Cast schema-qualified identifiers to name so the intended overload is selected.
select has_table('app'::name, 'organizations'::name);
select has_table('app'::name, 'user_profiles'::name);
select has_table('catalog'::name, 'products'::name);
select has_table('catalog'::name, 'product_batches'::name);
select has_table('inventory'::name, 'stock_transactions'::name);
select has_table('inventory'::name, 'stock_ledger_entries'::name);
select has_table('inventory'::name, 'stock_batch_balances'::name);
select has_table('inventory'::name, 'stock_product_positions'::name);

select has_view('api'::name, 'product_inventory'::name);
select has_view('api'::name, 'batch_inventory'::name);
select has_view('api'::name, 'stock_ledger'::name);

select col_is_pk('app'::name, 'organizations'::name, 'id'::name);
select col_is_pk('catalog'::name, 'products'::name, 'id'::name);
select col_is_pk('inventory'::name, 'stock_transactions'::name, 'id'::name);
select col_is_pk('inventory'::name, 'stock_ledger_entries'::name, 'id'::name);

select has_index(
  'catalog'::name,
  'product_batches'::name,
  'idx_product_batches_fefo'::name
);
select has_index(
  'inventory'::name,
  'stock_ledger_entries'::name,
  'idx_stock_ledger_product_seq'::name
);
select has_index(
  'inventory'::name,
  'stock_ledger_entries'::name,
  'idx_stock_ledger_batch_seq'::name
);

select policies_are(
  'catalog',
  'products',
  array['products_read_current_org']
);
select policies_are(
  'inventory',
  'stock_ledger_entries',
  array['stock_ledger_entries_read_current_org']
);

select function_returns('app', 'current_organization_id', array[]::text[], 'uuid');
select function_returns('app', 'is_admin', array[]::text[], 'boolean');

select throws_ok(
  $$update inventory.stock_transactions
    set note = 'mutated'
    where transaction_no = 'SEED-IB-000001'$$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'stock transaction updates are rejected'
);

select * from finish();
rollback;
