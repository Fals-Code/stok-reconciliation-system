begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

select has_function(
  'reconciliation',
  'find_duplicate_source_effects',
  array['uuid']::text[],
  'duplicate source comparison helper exists'
);

select is(
  (
    select procedure.prosecdef
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'reconciliation'
      and procedure.proname =
        'find_duplicate_source_effects'
      and pg_get_function_identity_arguments(procedure.oid) =
        'p_organization_id uuid'
  ),
  true,
  'duplicate source helper uses security definer'
);

select is(
  (
    select array_to_string(procedure.proconfig, ',')
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'reconciliation'
      and procedure.proname =
        'find_duplicate_source_effects'
      and pg_get_function_identity_arguments(procedure.oid) =
        'p_organization_id uuid'
  ),
  'search_path=pg_catalog, inventory, operations',
  'duplicate source helper has a fixed search path'
);

select is(
  (
    select count(*)
    from information_schema.routine_privileges privilege
    where privilege.specific_schema = 'reconciliation'
      and privilege.routine_name =
        'find_duplicate_source_effects'
      and privilege.grantee in (
        'PUBLIC',
        'anon',
        'authenticated',
        'service_role'
      )
      and privilege.privilege_type = 'EXECUTE'
  ),
  0::bigint,
  'duplicate source helper is not executable by client roles'
);

select is(
  (
    select count(*)
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'clean seed has no duplicate source effect'
);

create temp table duplicate_source_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

insert into duplicate_source_results (kind, result)
select
  'RECEIPT',
  api.post_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-DUPLICATE-SOURCE-RECEIPT-001',
    'RECON-DUPLICATE-SOURCE-001',
    '2026-07-28 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'batchId',
        '40000000-0000-4000-8000-000000000001',
        'quantity',
        2,
        'sourceLineRef',
        'RECON-DUPLICATE-SOURCE-LINE-001'
      )
    ),
    'Duplicate source reconciliation fixture.',
    '{"test": true, "fixture": "duplicate-source"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from duplicate_source_results
    where kind = 'RECEIPT'
  ),
  'POSTED',
  'duplicate source receipt fixture is posted'
);

select is(
  (
    select count(*)
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'one valid source transaction is not a duplicate'
);

insert into inventory.idempotency_commands (
  id,
  organization_id,
  scope,
  key,
  request_hash,
  status_code,
  started_at,
  completed_at,
  response_snapshot
)
values (
  '91000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'POST_RECEIPT',
  'PGTAP-RECON-DUPLICATE-SOURCE-CORRUPT-001',
  repeat('a', 64),
  'SUCCEEDED',
  '2026-07-28 10:01:00+07'::timestamptz,
  '2026-07-28 10:01:01+07'::timestamptz,
  '{}'::jsonb
);

insert into inventory.stock_transactions (
  id,
  organization_id,
  transaction_no,
  transaction_type_code,
  reason_id,
  reason_code_snapshot,
  channel_id,
  channel_code_snapshot,
  source_type_code,
  source_id,
  source_ref_snapshot,
  occurred_at,
  recorded_at,
  effective_local_date,
  actor_user_id,
  process_name,
  created_by_role_code,
  correlation_id,
  idempotency_command_id,
  reversal_of_transaction_id,
  note,
  metadata,
  schema_version
)
select
  '92000000-0000-4000-8000-000000000001'::uuid,
  stock_transaction.organization_id,
  'RCV-20260728-DUPL0001',
  stock_transaction.transaction_type_code,
  stock_transaction.reason_id,
  stock_transaction.reason_code_snapshot,
  stock_transaction.channel_id,
  stock_transaction.channel_code_snapshot,
  stock_transaction.source_type_code,
  gen_random_uuid(),
  stock_transaction.source_ref_snapshot,
  stock_transaction.occurred_at,
  stock_transaction.recorded_at,
  stock_transaction.effective_local_date,
  stock_transaction.actor_user_id,
  stock_transaction.process_name,
  stock_transaction.created_by_role_code,
  gen_random_uuid(),
  '91000000-0000-4000-8000-000000000001'::uuid,
  null,
  'Corrupted duplicate source transaction.',
  stock_transaction.metadata
    || '{"corruption": "duplicate-source"}'::jsonb,
  stock_transaction.schema_version
from inventory.stock_transactions stock_transaction
where stock_transaction.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and stock_transaction.transaction_type_code = 'RECEIPT'
  and stock_transaction.source_type_code = 'RECEIPT'
  and stock_transaction.source_ref_snapshot =
    'RECON-DUPLICATE-SOURCE-001';

insert into inventory.stock_ledger_entries (
  organization_id,
  transaction_id,
  line_no,
  product_id,
  batch_id,
  product_sku_snapshot,
  batch_code_snapshot,
  expiry_date_snapshot,
  bucket_code,
  quantity_delta,
  entry_role_code,
  pair_no,
  source_line_ref,
  occurred_at,
  recorded_at,
  created_at
)
select
  ledger_entry.organization_id,
  '92000000-0000-4000-8000-000000000001'::uuid,
  ledger_entry.line_no,
  ledger_entry.product_id,
  ledger_entry.batch_id,
  ledger_entry.product_sku_snapshot,
  ledger_entry.batch_code_snapshot,
  ledger_entry.expiry_date_snapshot,
  ledger_entry.bucket_code,
  ledger_entry.quantity_delta,
  ledger_entry.entry_role_code,
  ledger_entry.pair_no,
  ledger_entry.source_line_ref,
  ledger_entry.occurred_at,
  ledger_entry.recorded_at,
  ledger_entry.created_at
from inventory.stock_ledger_entries ledger_entry
join inventory.stock_transactions stock_transaction
  on stock_transaction.id = ledger_entry.transaction_id
where stock_transaction.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and stock_transaction.transaction_type_code = 'RECEIPT'
  and stock_transaction.source_type_code = 'RECEIPT'
  and stock_transaction.source_ref_snapshot =
    'RECON-DUPLICATE-SOURCE-001'
  and stock_transaction.id
    <> '92000000-0000-4000-8000-000000000001'::uuid;

update inventory.idempotency_commands command
set
  result_transaction_id =
    '92000000-0000-4000-8000-000000000001'::uuid,
  response_snapshot = jsonb_build_object(
    'transactionId',
    '92000000-0000-4000-8000-000000000001'::uuid
  )
where command.id =
  '91000000-0000-4000-8000-000000000001'::uuid;

select is(
  (
    select count(*)
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where issue_code = 'DUPLICATE_SOURCE_TRANSACTION'
  ),
  1::bigint,
  'duplicate physical source creates one transaction mismatch'
);

select is(
  (
    select
      transaction_count::text
        || ':'
        || command_count::text
        || ':'
        || ledger_entry_count::text
        || ':'
        || absolute_quantity::text
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where issue_code = 'DUPLICATE_SOURCE_TRANSACTION'
  ),
  '2:2:2:4',
  'duplicate source diagnostics count transactions commands and quantity'
);

select is(
  (
    select
      transaction_type_code
        || ':'
        || source_type_code
        || ':'
        || source_ref
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where issue_code = 'DUPLICATE_SOURCE_TRANSACTION'
  ),
  'RECEIPT:RECEIPT:RECON-DUPLICATE-SOURCE-001',
  'duplicate source mismatch retains its canonical identity'
);

select is(
  (
    select jsonb_array_length(transaction_ids)
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where issue_code = 'DUPLICATE_SOURCE_TRANSACTION'
  ),
  2,
  'duplicate source evidence lists both transactions'
);

select is(
  (
    select jsonb_array_length(command_ids)
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where issue_code = 'DUPLICATE_SOURCE_TRANSACTION'
  ),
  2,
  'duplicate source evidence lists both commands'
);

insert into operations.manual_outbounds (
  id,
  organization_id,
  outbound_no,
  source_ref,
  reason_id,
  reason_code_snapshot,
  status_code,
  occurred_at,
  recorded_at,
  actor_user_id,
  process_name,
  transaction_id,
  idempotency_command_id,
  total_quantity,
  note,
  metadata,
  created_at
)
select
  '93000000-0000-4000-8000-000000000001'::uuid,
  receipt.organization_id,
  'OUT-20260728-CORR0001',
  'RECON-DUPLICATE-COMMAND-DOMAIN-001',
  stock_transaction.reason_id,
  stock_transaction.reason_code_snapshot,
  'POSTED',
  receipt.occurred_at,
  receipt.recorded_at,
  receipt.actor_user_id,
  receipt.process_name,
  receipt.transaction_id,
  receipt.idempotency_command_id,
  2,
  'Corrupted cross-domain command reuse.',
  '{"test": true, "corruption": "command-domain"}'::jsonb,
  receipt.created_at
from operations.receipts receipt
join inventory.stock_transactions stock_transaction
  on stock_transaction.id = receipt.transaction_id
where receipt.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and receipt.source_ref = 'RECON-DUPLICATE-SOURCE-001';

select is(
  (
    select count(*)
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where issue_code =
      'DUPLICATE_COMMAND_DOMAIN_EFFECT'
  ),
  1::bigint,
  'cross-domain command reuse creates one command mismatch'
);

select is(
  (
    select
      transaction_count::text
        || ':'
        || command_count::text
        || ':'
        || domain_effect_count::text
        || ':'
        || ledger_entry_count::text
        || ':'
        || absolute_quantity::text
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where issue_code =
      'DUPLICATE_COMMAND_DOMAIN_EFFECT'
  ),
  '1:1:2:1:2',
  'command mismatch reports two domain effects over one transaction'
);

select is(
  (
    select
      (domain_effects -> 0 ->> 'domainType')
        || ':'
        || (domain_effects -> 1 ->> 'domainType')
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where issue_code =
      'DUPLICATE_COMMAND_DOMAIN_EFFECT'
  ),
  'MANUAL_OUTBOUND:RECEIPT',
  'command mismatch lists both domain effect types'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
        '00000000-0000-4000-8000-000000000001'::uuid
      and transaction_type_code = 'RECEIPT'
      and source_type_code = 'RECEIPT'
      and source_ref_snapshot =
        'RECON-DUPLICATE-SOURCE-001'
  ),
  2::bigint,
  'duplicate source comparison does not alter transactions'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries ledger_entry
    join inventory.stock_transactions stock_transaction
      on stock_transaction.id = ledger_entry.transaction_id
    where stock_transaction.organization_id =
        '00000000-0000-4000-8000-000000000001'::uuid
      and stock_transaction.transaction_type_code = 'RECEIPT'
      and stock_transaction.source_type_code = 'RECEIPT'
      and stock_transaction.source_ref_snapshot =
        'RECON-DUPLICATE-SOURCE-001'
  ),
  2::bigint,
  'duplicate source comparison does not alter ledger entries'
);

select is(
  (
    select count(*)
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  2::bigint,
  'duplicate source comparison deterministically returns two violations'
);

select * from finish();

rollback;