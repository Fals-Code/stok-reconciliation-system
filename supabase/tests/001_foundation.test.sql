begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

select has_schema('app');
select has_schema('catalog');
select has_schema('inventory');
select has_schema('notification');
select has_schema('api');

select has_table('app', 'organizations');
select has_table('app', 'user_profiles');
select has_table('catalog', 'products');
select has_table('catalog', 'product_batches');
select has_table('inventory', 'stock_transactions');
select has_table('inventory', 'stock_ledger_entries');
select has_table('inventory', 'stock_batch_balances');
select has_table('inventory', 'stock_product_positions');

select has_view('api', 'product_inventory');
select has_view('api', 'batch_inventory');
select has_view('api', 'stock_ledger');

select col_is_pk('app', 'organizations', 'id');
select col_is_pk('catalog', 'products', 'id');
select col_is_pk('inventory', 'stock_transactions', 'id');
select col_is_pk('inventory', 'stock_ledger_entries', 'id');

select has_index('catalog', 'product_batches', 'idx_product_batches_fefo');
select has_index('inventory', 'stock_ledger_entries', 'idx_stock_ledger_product_seq');
select has_index('inventory', 'stock_ledger_entries', 'idx_stock_ledger_batch_seq');

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
