begin;

select plan(30);

select has_column(
  'catalog',
  'product_batches',
  'batch_kind_code',
  'product batches expose their origin kind'
);

select col_not_null(
  'catalog',
  'product_batches',
  'batch_kind_code',
  'batch kind is mandatory'
);

select is(
  (
    select column_default
    from information_schema.columns
    where table_schema = 'catalog'
      and table_name = 'product_batches'
      and column_name = 'batch_kind_code'
  ),
  '''STANDARD''::text',
  'normal batches default to STANDARD'
);

select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conname = 'ck_product_batches_kind'
  ),
  'batch kind check constraint exists'
);

select ok(
  exists (
    select 1
    from catalog.movement_reasons reason
    where reason.code = 'RETURN_SELLABLE'
      and reason.direction_code = 'INBOUND'
      and reason.is_active
  ),
  'sellable return inbound reason is configured'
);

select ok(
  position(
    'RETURN_SELLABLE_INBOUND'
    in (
      select pg_get_constraintdef(constraint_row.oid)
      from pg_constraint constraint_row
      where constraint_row.conname = 'ck_stock_transactions_type'
    )
  ) > 0,
  'stock transaction contract accepts sellable return inbound'
);

select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'operations'
      and table_name = 'return_receipts'
      and column_name = 'transaction_id'
  ),
  'YES',
  'return receipt transaction is optional'
);

select has_column(
  'operations',
  'return_receipts',
  'stock_effect_code',
  'return receipts expose stock effect separately'
);

select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conname =
      'ck_return_receipts_transaction_effect'
  ),
  'return receipt transaction/effect invariant exists'
);

select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'operations'
      and table_name = 'return_receipt_lines'
      and column_name = 'batch_id'
  ),
  'YES',
  'receipt destination batch is optional'
);

select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'operations'
      and table_name = 'return_receipt_lines'
      and column_name = 'ledger_entry_id'
  ),
  'YES',
  'receipt ledger entry is optional'
);

select has_column(
  'operations',
  'return_receipt_lines',
  'source_batch_id',
  'receipt line stores source batch provenance'
);

select has_column(
  'operations',
  'return_receipt_lines',
  'source_batch_code_snapshot',
  'receipt line stores source batch code snapshot'
);

select has_column(
  'operations',
  'return_receipt_lines',
  'source_expiry_date_snapshot',
  'receipt line stores source expiry snapshot'
);

select has_column(
  'operations',
  'return_receipt_lines',
  'stock_effect_code',
  'receipt line exposes stock effect separately'
);

select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conname =
      'ck_return_receipt_lines_effect_shape'
  ),
  'receipt line effect shape is constrained'
);

select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'operations'
      and table_name = 'return_inspections'
      and column_name = 'transaction_id'
  ),
  'YES',
  'inspection transaction is optional'
);

select has_column(
  'operations',
  'return_inspections',
  'stock_effect_code',
  'inspection exposes stock effect separately'
);

select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'operations'
      and table_name = 'return_inspection_allocations'
      and column_name = 'destination_bucket_code'
  ),
  'YES',
  'damaged inspection needs no destination stock bucket'
);

select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'operations'
      and table_name = 'return_inspection_allocations'
      and column_name = 'pair_no'
  ),
  'YES',
  'Phase 2 inspection needs no paired ledger movement'
);

select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'operations'
      and table_name = 'return_inspection_allocations'
      and column_name = 'source_ledger_entry_id'
  ),
  'YES',
  'sellable return inbound needs no source ledger entry'
);

select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'operations'
      and table_name = 'return_inspection_allocations'
      and column_name = 'destination_ledger_entry_id'
  ),
  'YES',
  'damaged inspection needs no destination ledger entry'
);

select has_column(
  'operations',
  'return_inspection_allocations',
  'condition_code',
  'physical condition is stored separately'
);

select col_not_null(
  'operations',
  'return_inspection_allocations',
  'condition_code',
  'inspection condition is mandatory'
);

select has_column(
  'operations',
  'return_inspection_allocations',
  'stock_effect_code',
  'inspection allocation stores its stock effect'
);

select has_column(
  'operations',
  'return_inspection_allocations',
  'return_batch_id',
  'sellable inspection can reference its return batch'
);

select has_table(
  'operations',
  'return_stock_batches',
  'return batch provenance table exists'
);

select ok(
  (
    select class.relrowsecurity
    from pg_class class
    join pg_namespace namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'return_stock_batches'
  ),
  'return batch provenance has RLS enabled'
);

select ok(
  exists (
    select 1
    from pg_trigger trigger_row
    join pg_class class
      on class.oid = trigger_row.tgrelid
    join pg_namespace namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'operations'
      and class.relname = 'return_stock_batches'
      and trigger_row.tgname = 'trg_return_stock_batches_immutable'
      and not trigger_row.tgisinternal
  ),
  'return batch provenance is append-only'
);

select has_view(
  'api',
  'return_stock_batches',
  'return batch provenance read view exists'
);

select * from finish();

rollback;