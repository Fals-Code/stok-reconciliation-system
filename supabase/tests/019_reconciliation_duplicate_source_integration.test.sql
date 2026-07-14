begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

create temp table duplicate_integration_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temp table duplicate_integration_snapshots (
  stage text primary key,
  transaction_count bigint not null,
  ledger_count bigint not null
) on commit drop;

insert into duplicate_integration_results (
  kind,
  result
)
select
  'CLEAN_EMPTY',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-DUPLICATE-INTEGRATION-CLEAN-001',
    array[
      'DUPLICATE_SOURCE_EFFECT'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "duplicate-integration-empty"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from duplicate_integration_results
    where kind = 'CLEAN_EMPTY'
  ),
  'CLEAN',
  'empty duplicate source reconciliation is clean'
);

select is(
  (
    select
      run_check.status_code
        || ':'
        || run_check.issue_count::text
    from reconciliation.run_checks run_check
    where run_check.run_id = (
      select (result ->> 'runId')::uuid
      from duplicate_integration_results
      where kind = 'CLEAN_EMPTY'
    )
      and run_check.check_code =
        'DUPLICATE_SOURCE_EFFECT'
  ),
  'PASSED:0',
  'empty duplicate source check persists a clean result'
);

insert into duplicate_integration_results (
  kind,
  result
)
select
  'RECEIPT',
  api.post_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-DUPLICATE-INTEGRATION-RECEIPT-001',
    'RECON-DUPLICATE-INTEGRATION-SOURCE-001',
    '2026-07-29 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'batchId',
        '40000000-0000-4000-8000-000000000001',
        'quantity',
        2,
        'sourceLineRef',
        'RECON-DUPLICATE-INTEGRATION-LINE-001'
      )
    ),
    'Duplicate source integration fixture.',
    '{"test": true, "fixture": "duplicate-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from duplicate_integration_results
    where kind = 'RECEIPT'
  ),
  'POSTED',
  'duplicate integration receipt fixture is posted'
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
  '94000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'POST_RECEIPT',
  'PGTAP-RECON-DUPLICATE-INTEGRATION-CORRUPT-001',
  repeat('b', 64),
  'SUCCEEDED',
  '2026-07-29 10:01:00+07'::timestamptz,
  '2026-07-29 10:01:01+07'::timestamptz,
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
  '95000000-0000-4000-8000-000000000001'::uuid,
  stock_transaction.organization_id,
  'RCV-20260729-DUPL0001',
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
  '94000000-0000-4000-8000-000000000001'::uuid,
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
    'RECON-DUPLICATE-INTEGRATION-SOURCE-001';

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
  '95000000-0000-4000-8000-000000000001'::uuid,
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
    'RECON-DUPLICATE-INTEGRATION-SOURCE-001'
  and stock_transaction.id
    <> '95000000-0000-4000-8000-000000000001'::uuid;

update inventory.idempotency_commands command
set
  result_transaction_id =
    '95000000-0000-4000-8000-000000000001'::uuid,
  response_snapshot = jsonb_build_object(
    'transactionId',
    '95000000-0000-4000-8000-000000000001'::uuid
  )
where command.id =
  '94000000-0000-4000-8000-000000000001'::uuid;

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
  '96000000-0000-4000-8000-000000000001'::uuid,
  receipt.organization_id,
  'OUT-20260729-CORR0001',
  'RECON-DUPLICATE-INTEGRATION-COMMAND-001',
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
  and receipt.source_ref =
    'RECON-DUPLICATE-INTEGRATION-SOURCE-001';

select is(
  (
    select count(*)
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  2::bigint,
  'corrupted fixture exposes two duplicate source violations'
);

insert into duplicate_integration_snapshots (
  stage,
  transaction_count,
  ledger_count
)
select
  'BEFORE_RECONCILIATION',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries);

insert into duplicate_integration_results (
  kind,
  result
)
select
  'DRIFT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-DUPLICATE-INTEGRATION-DRIFT-001',
    array[
      'DUPLICATE_SOURCE_EFFECT'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "duplicate-integration-drift"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from duplicate_integration_results
    where kind = 'DRIFT'
  ),
  'ISSUES_FOUND',
  'duplicate source drift is detected'
);

select is(
  (
    select
      run_check.status_code
        || ':'
        || run_check.issue_count::text
    from reconciliation.run_checks run_check
    where run_check.run_id = (
      select (result ->> 'runId')::uuid
      from duplicate_integration_results
      where kind = 'DRIFT'
    )
      and run_check.check_code =
        'DUPLICATE_SOURCE_EFFECT'
  ),
  'FAILED:2',
  'duplicate source check fails with two issues'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
      and issue.status_code = 'OPEN'
  ),
  2::bigint,
  'duplicate source drift creates two open logical issues'
);

select is(
  (
    select count(distinct issue.fingerprint)
    from reconciliation.issues issue
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
  ),
  2::bigint,
  'duplicate source issues have distinct stable fingerprints'
);

select is(
  (
    select
      issue.severity_code
        || ':'
        || issue.entity_type_code
        || ':'
        || coalesce(issue.source_type_code, '')
    from reconciliation.issues issue
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
      and issue.entity_type_code = 'STOCK_SOURCE'
  ),
  'CRITICAL:STOCK_SOURCE:RECEIPT',
  'duplicate physical source issue has critical source classification'
);

select is(
  (
    select
      (issue.expected_value ->> 'transactionCount')
        || ':'
        || (issue.actual_value ->> 'transactionCount')
        || ':'
        || (issue.actual_value ->> 'commandCount')
        || ':'
        || (issue.actual_value ->> 'ledgerEntryCount')
        || ':'
        || (issue.actual_value ->> 'absoluteQuantity')
        || ':'
        || (
          issue.difference_value
            ->> 'transactionCount'
        )
    from reconciliation.issues issue
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
      and issue.entity_type_code = 'STOCK_SOURCE'
  ),
  '1:2:2:2:4:1',
  'duplicate physical source issue explains the extra transaction'
);

select is(
  (
    select evidence.detail ->> 'issueCode'
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
      and issue.entity_type_code = 'STOCK_SOURCE'
  ),
  'DUPLICATE_SOURCE_TRANSACTION',
  'duplicate physical source evidence stores the helper issue code'
);

select is(
  (
    select
      issue.severity_code
        || ':'
        || issue.entity_type_code
        || ':'
        || coalesce(issue.source_type_code, '')
    from reconciliation.issues issue
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
      and issue.entity_type_code =
        'IDEMPOTENCY_COMMAND'
  ),
  'CRITICAL:IDEMPOTENCY_COMMAND:IDEMPOTENCY_COMMAND',
  'duplicate command issue has critical command classification'
);

select is(
  (
    select
      (issue.expected_value ->> 'domainEffectCount')
        || ':'
        || (issue.actual_value ->> 'transactionCount')
        || ':'
        || (issue.actual_value ->> 'commandCount')
        || ':'
        || (issue.actual_value ->> 'domainEffectCount')
        || ':'
        || (issue.actual_value ->> 'ledgerEntryCount')
        || ':'
        || (issue.actual_value ->> 'absoluteQuantity')
        || ':'
        || (
          issue.difference_value
            ->> 'domainEffectCount'
        )
    from reconciliation.issues issue
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
      and issue.entity_type_code =
        'IDEMPOTENCY_COMMAND'
  ),
  '1:1:1:2:1:2:1',
  'duplicate command issue explains the extra domain effect'
);

select is(
  (
    select evidence.detail ->> 'issueCode'
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
      and issue.entity_type_code =
        'IDEMPOTENCY_COMMAND'
  ),
  'DUPLICATE_COMMAND_DOMAIN_EFFECT',
  'duplicate command evidence stores the helper issue code'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
      and evidence.evidence_type_code =
        'DUPLICATE_SOURCE_EFFECT_MISMATCH'
  ),
  2::bigint,
  'duplicate source issues each persist typed evidence'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
      and evidence.detail ->> 'ruleSetVersion' =
        'core-integrity-v6'
  ),
  2::bigint,
  'duplicate source evidence records the v6 rule set'
);

select is(
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-DUPLICATE-INTEGRATION-DRIFT-001',
    array[
      'DUPLICATE_SOURCE_EFFECT'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "duplicate-integration-drift"}'::jsonb
  ),
  (
    select result
    from duplicate_integration_results
    where kind = 'DRIFT'
  ),
  'duplicate source reconciliation replay is idempotent'
);

select is(
  (
    select count(*)
    from reconciliation.runs run
    where run.idempotency_command_id = (
      select command.id
      from inventory.idempotency_commands command
      where command.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
        and command.scope = 'RUN_RECONCILIATION'
        and command.key =
          'PGTAP-RECON-DUPLICATE-INTEGRATION-DRIFT-001'
    )
  ),
  1::bigint,
  'duplicate source reconciliation replay keeps one run'
);

insert into duplicate_integration_results (
  kind,
  result
)
select
  'DRIFT_REPEAT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-DUPLICATE-INTEGRATION-DRIFT-002',
    array[
      'DUPLICATE_SOURCE_EFFECT'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "duplicate-integration-repeat"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from duplicate_integration_results
    where kind = 'DRIFT_REPEAT'
  ),
  'ISSUES_FOUND',
  'repeated duplicate source drift remains detected'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
  ),
  2::bigint,
  'repeated duplicate source drift keeps two logical issues'
);

select is(
  (
    select string_agg(
      issue.recurrence_count::text,
      ':'
      order by issue.entity_type_code
    )
    from reconciliation.issues issue
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
  ),
  '2:2',
  'repeated duplicate source drift increments both recurrences'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
  ),
  4::bigint,
  'repeated duplicate source drift appends evidence'
);

select is(
  (
    select
      (select count(*) from inventory.stock_transactions)::text
        || ':'
        || (select count(*) from inventory.stock_ledger_entries)::text
  ),
  (
    select
      snapshot.transaction_count::text
        || ':'
        || snapshot.ledger_count::text
    from duplicate_integration_snapshots snapshot
    where snapshot.stage = 'BEFORE_RECONCILIATION'
  ),
  'duplicate source reconciliation creates no physical stock effect'
);

alter table operations.manual_outbounds
  disable trigger trg_manual_outbounds_immutable;

delete from operations.manual_outbounds outbound
where outbound.id =
  '96000000-0000-4000-8000-000000000001'::uuid;

alter table operations.manual_outbounds
  enable trigger trg_manual_outbounds_immutable;

alter table inventory.stock_ledger_entries
  disable trigger trg_stock_ledger_entries_immutable;

delete from inventory.stock_ledger_entries ledger_entry
where ledger_entry.transaction_id =
  '95000000-0000-4000-8000-000000000001'::uuid;

alter table inventory.stock_ledger_entries
  enable trigger trg_stock_ledger_entries_immutable;

update inventory.idempotency_commands command
set
  result_transaction_id = null,
  response_snapshot = command.response_snapshot - 'transactionId'
where command.id =
  '94000000-0000-4000-8000-000000000001'::uuid;

alter table inventory.stock_transactions
  disable trigger trg_stock_transactions_immutable;

delete from inventory.stock_transactions stock_transaction
where stock_transaction.id =
  '95000000-0000-4000-8000-000000000001'::uuid;

alter table inventory.stock_transactions
  enable trigger trg_stock_transactions_immutable;

select is(
  (
    select count(*)
    from reconciliation.find_duplicate_source_effects(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'removing corrupted rows clears helper mismatches'
);

insert into duplicate_integration_results (
  kind,
  result
)
select
  'RESTORED',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-DUPLICATE-INTEGRATION-RESTORED-001',
    array[
      'DUPLICATE_SOURCE_EFFECT'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "duplicate-integration-restored"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from duplicate_integration_results
    where kind = 'RESTORED'
  ),
  'CLEAN',
  'restored duplicate source reports clean integrity'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'DUPLICATE_SOURCE_EFFECT'
      and issue.status_code = 'RESOLVED'
      and issue.resolution_code = 'NOT_REDETECTED'
  ),
  2::bigint,
  'clean rerun resolves both duplicate source issues'
);

select * from finish();

rollback;