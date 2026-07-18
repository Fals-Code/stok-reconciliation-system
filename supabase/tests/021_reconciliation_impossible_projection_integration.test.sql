begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

select function_returns(
  'api',
  'run_reconciliation',
  array[
    'uuid',
    'text',
    'text[]',
    'jsonb',
    'jsonb'
  ]::text[],
  'jsonb'
);

create temp table impossible_integration_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temp table impossible_integration_baseline (
  id boolean primary key default true,
  transaction_count bigint not null,
  ledger_count bigint not null,
  batch_sellable_qty bigint not null,
  batch_quarantine_qty bigint not null,
  batch_damaged_qty bigint not null,
  product_sellable_qty bigint not null,
  product_quarantine_qty bigint not null,
  product_damaged_qty bigint not null,
  boundary_batch_last_ledger_seq bigint not null,
  boundary_product_last_ledger_seq bigint not null,
  constraint impossible_integration_baseline_singleton
    check (id)
) on commit drop;

insert into impossible_integration_baseline (
  transaction_count,
  ledger_count,
  batch_sellable_qty,
  batch_quarantine_qty,
  batch_damaged_qty,
  product_sellable_qty,
  product_quarantine_qty,
  product_damaged_qty,
  boundary_batch_last_ledger_seq,
  boundary_product_last_ledger_seq
)
select
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries),
  boundary_batch.sellable_qty,
  boundary_batch.quarantine_qty,
  boundary_batch.damaged_qty,
  boundary_product.sellable_qty,
  boundary_product.quarantine_qty,
  boundary_product.damaged_qty,
  boundary_batch.last_ledger_seq,
  boundary_product.last_ledger_seq
from inventory.stock_batch_balances boundary_batch
join inventory.stock_product_positions boundary_product
  on boundary_product.organization_id =
      boundary_batch.organization_id
 and boundary_product.product_id =
      boundary_batch.product_id
where boundary_batch.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and boundary_batch.batch_id =
    '40000000-0000-4000-8000-000000000002'::uuid
  and boundary_product.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

insert into impossible_integration_results (
  kind,
  result
)
select
  'CLEAN',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-IMPOSSIBLE-INTEGRATION-CLEAN-001',
    array[
      'IMPOSSIBLE_PROJECTION_STATE'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "impossible-clean"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from impossible_integration_results
    where kind = 'CLEAN'
  ),
  'SUCCEEDED',
  'clean impossible-state reconciliation succeeds'
);

select is(
  (
    select result ->> 'integrityStatus'
    from impossible_integration_results
    where kind = 'CLEAN'
  ),
  'CLEAN',
  'clean impossible-state reconciliation reports clean integrity'
);

select is(
  (
    select result ->> 'issueCount'
    from impossible_integration_results
    where kind = 'CLEAN'
  ),
  '0',
  'clean impossible-state reconciliation has no issues'
);

select is(
  (
    select
      run_check.status_code
        || ':'
        || run_check.issue_count::text
    from reconciliation.run_checks run_check
    join reconciliation.runs run
      on run.organization_id = run_check.organization_id
     and run.id = run_check.run_id
    where run.idempotency_command_id = (
      select command.id
      from inventory.idempotency_commands command
      where command.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
        and command.scope = 'RUN_RECONCILIATION'
        and command.key =
          'PGTAP-RECON-IMPOSSIBLE-INTEGRATION-CLEAN-001'
    )
      and run_check.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
  ),
  'PASSED:0',
  'clean impossible-state check is persisted as passed'
);

update inventory.stock_batch_balances balance
set
  last_ledger_seq = 0,
  version = balance.version + 1
where balance.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and balance.batch_id =
    '40000000-0000-4000-8000-000000000002'::uuid;

update inventory.stock_product_positions position
set
  last_ledger_seq = 0,
  version = position.version + 1
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

insert into impossible_integration_results (
  kind,
  result
)
select
  'BOUNDARY_DRIFT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-IMPOSSIBLE-INTEGRATION-BOUNDARY-001',
    array[
      'IMPOSSIBLE_PROJECTION_STATE'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "impossible-boundary"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from impossible_integration_results
    where kind = 'BOUNDARY_DRIFT'
  ),
  'ISSUES_FOUND',
  'stale projection boundaries are reported as issues'
);

select is(
  (
    select result ->> 'issueCount'
    from impossible_integration_results
    where kind = 'BOUNDARY_DRIFT'
  ),
  '2',
  'stale batch and product boundaries create two issues'
);

select is(
  (
    select
      run_check.status_code
        || ':'
        || run_check.issue_count::text
    from reconciliation.run_checks run_check
    join reconciliation.runs run
      on run.organization_id = run_check.organization_id
     and run.id = run_check.run_id
    where run.idempotency_command_id = (
      select command.id
      from inventory.idempotency_commands command
      where command.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
        and command.scope = 'RUN_RECONCILIATION'
        and command.key =
          'PGTAP-RECON-IMPOSSIBLE-INTEGRATION-BOUNDARY-001'
    )
      and run_check.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
  ),
  'FAILED:2',
  'impossible-state run check persists both boundary issues'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
  ),
  2::bigint,
  'boundary drift creates two open logical issues'
);

select is(
  (
    select string_agg(
      issue.entity_key ->> 'issueCode',
      ':'
      order by issue.entity_key ->> 'issueCode'
    )
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
  ),
  'BATCH_LEDGER_BOUNDARY_MISMATCH:PRODUCT_LEDGER_BOUNDARY_MISMATCH',
  'boundary issues preserve helper classifications'
);

select is(
  (
    select string_agg(
      issue.entity_type_code,
      ':'
      order by issue.entity_type_code
    )
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
  ),
  'BATCH_PROJECTION_BOUNDARY:PRODUCT_PROJECTION_BOUNDARY',
  'boundary issues identify the affected projection layers'
);

select ok(
  (
    select bool_and(issue.severity_code = 'CRITICAL')
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
  ),
  'all impossible projection states are critical'
);

select ok(
  (
    select bool_and(
      (issue.expected_value ->> 'lastLedgerSeq')::bigint
        >
      (issue.actual_value ->> 'lastLedgerSeq')::bigint
    )
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
  ),
  'boundary issues explain expected and actual ledger watermarks'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and evidence.evidence_type_code =
        'IMPOSSIBLE_PROJECTION_STATE_MISMATCH'
  ),
  2::bigint,
  'boundary issues each persist typed evidence'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and evidence.detail ->> 'ruleSetVersion' =
        'core-integrity-v8'
  ),
  2::bigint,
  'impossible-state evidence records the v8 rule set'
);

select is(
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-IMPOSSIBLE-INTEGRATION-BOUNDARY-001',
    array[
      'IMPOSSIBLE_PROJECTION_STATE'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "impossible-boundary"}'::jsonb
  ),
  (
    select result
    from impossible_integration_results
    where kind = 'BOUNDARY_DRIFT'
  ),
  'impossible-state reconciliation replay is idempotent'
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
          'PGTAP-RECON-IMPOSSIBLE-INTEGRATION-BOUNDARY-001'
    )
  ),
  1::bigint,
  'idempotent impossible-state replay creates one run'
);

insert into impossible_integration_results (
  kind,
  result
)
select
  'BOUNDARY_REPEAT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-IMPOSSIBLE-INTEGRATION-BOUNDARY-002',
    array[
      'IMPOSSIBLE_PROJECTION_STATE'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "impossible-boundary-repeat"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from impossible_integration_results
    where kind = 'BOUNDARY_REPEAT'
  ),
  'ISSUES_FOUND',
  'repeated boundary drift remains visible'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
  ),
  2::bigint,
  'repeated boundary drift keeps two logical issues'
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
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
  ),
  '2:2',
  'repeated boundary drift increments both recurrences'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
  ),
  4::bigint,
  'repeated boundary drift appends evidence'
);

select is(
  (
    select
      boundary_batch.sellable_qty::text
        || ':'
        || boundary_batch.quarantine_qty::text
        || ':'
        || boundary_batch.damaged_qty::text
        || ':'
        || boundary_product.sellable_qty::text
        || ':'
        || boundary_product.quarantine_qty::text
        || ':'
        || boundary_product.damaged_qty::text
    from inventory.stock_batch_balances boundary_batch
    join inventory.stock_product_positions boundary_product
      on boundary_product.organization_id =
          boundary_batch.organization_id
     and boundary_product.product_id =
          boundary_batch.product_id
    where boundary_batch.organization_id =
        '00000000-0000-4000-8000-000000000001'::uuid
      and boundary_batch.batch_id =
        '40000000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select
      baseline.batch_sellable_qty::text
        || ':'
        || baseline.batch_quarantine_qty::text
        || ':'
        || baseline.batch_damaged_qty::text
        || ':'
        || baseline.product_sellable_qty::text
        || ':'
        || baseline.product_quarantine_qty::text
        || ':'
        || baseline.product_damaged_qty::text
    from impossible_integration_baseline baseline
  ),
  'impossible-state reconciliation does not mutate stock quantities'
);

update inventory.stock_batch_balances balance
set
  last_ledger_seq =
    baseline.boundary_batch_last_ledger_seq,
  version = balance.version + 1
from impossible_integration_baseline baseline
where balance.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and balance.batch_id =
    '40000000-0000-4000-8000-000000000002'::uuid;

update inventory.stock_product_positions position
set
  last_ledger_seq =
    baseline.boundary_product_last_ledger_seq,
  version = position.version + 1
from impossible_integration_baseline baseline
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

insert into impossible_integration_results (
  kind,
  result
)
select
  'BOUNDARY_RESTORED',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-IMPOSSIBLE-INTEGRATION-RESTORED-001',
    array[
      'IMPOSSIBLE_PROJECTION_STATE'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "impossible-boundary-restored"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from impossible_integration_results
    where kind = 'BOUNDARY_RESTORED'
  ),
  'CLEAN',
  'restoring projection watermarks returns clean integrity'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'RESOLVED'
      and issue.resolution_code = 'NOT_REDETECTED'
  ),
  2::bigint,
  'clean rerun resolves both boundary issues'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
  ),
  0::bigint,
  'no impossible-state boundary issue remains open'
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
  '9a000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'RECONCILIATION_CORRUPTION_TEST',
  'PGTAP-IMPOSSIBLE-INTEGRATION-NEGATIVE-001',
  repeat('d', 64),
  'STARTED',
  '2026-07-30 11:00:00+07'::timestamptz,
  null,
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
  '9b000000-0000-4000-8000-000000000001'::uuid,
  stock_transaction.organization_id,
  'REC-IMPOSSIBLE-INTEGRATION-NEGATIVE-0001',
  stock_transaction.transaction_type_code,
  stock_transaction.reason_id,
  stock_transaction.reason_code_snapshot,
  stock_transaction.channel_id,
  stock_transaction.channel_code_snapshot,
  stock_transaction.source_type_code,
  gen_random_uuid(),
  'PGTAP-IMPOSSIBLE-INTEGRATION-NEGATIVE-001',
  '2026-07-30 11:00:00+07'::timestamptz,
  '2026-07-30 11:00:00+07'::timestamptz,
  '2026-07-30'::date,
  null,
  'pgTAP impossible projection integration fixture',
  'SYSTEM_PROCESS',
  gen_random_uuid(),
  '9a000000-0000-4000-8000-000000000001'::uuid,
  null,
  'Deliberate negative-ledger integration fixture.',
  '{"test": true, "corruption": "negative-ledger"}'::jsonb,
  stock_transaction.schema_version
from inventory.stock_transactions stock_transaction
where stock_transaction.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
order by stock_transaction.recorded_at, stock_transaction.id
limit 1;

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
  '00000000-0000-4000-8000-000000000001'::uuid,
  '9b000000-0000-4000-8000-000000000001'::uuid,
  1,
  product.id,
  batch.id,
  product.sku,
  batch.batch_code,
  batch.expiry_date,
  'SELLABLE',
  -(
    coalesce(
      (
        select sum(entry.quantity_delta)
        from inventory.stock_ledger_entries entry
        where entry.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
          and entry.product_id = product.id
          and entry.batch_id = batch.id
          and entry.bucket_code = 'SELLABLE'
      ),
      0
    ) + 1
  ),
  'ADJUSTMENT',
  null,
  'PGTAP-IMPOSSIBLE-INTEGRATION-NEGATIVE-001',
  '2026-07-30 11:00:00+07'::timestamptz,
  '2026-07-30 11:00:00+07'::timestamptz,
  '2026-07-30 11:00:00+07'::timestamptz
from catalog.products product
join catalog.product_batches batch
  on batch.organization_id = product.organization_id
 and batch.product_id = product.id
where product.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and product.id =
    '30000000-0000-4000-8000-000000000003'::uuid
  and batch.id =
    '40000000-0000-4000-8000-000000000004'::uuid;

insert into impossible_integration_results (
  kind,
  result
)
select
  'NEGATIVE_LEDGER',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-IMPOSSIBLE-INTEGRATION-NEGATIVE-001',
    array[
      'IMPOSSIBLE_PROJECTION_STATE'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "impossible-negative-ledger"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from impossible_integration_results
    where kind = 'NEGATIVE_LEDGER'
  ),
  'ISSUES_FOUND',
  'negative ledger aggregate is reported as an impossible state'
);

select is(
  (
    select result ->> 'issueCount'
    from impossible_integration_results
    where kind = 'NEGATIVE_LEDGER'
  ),
  '3',
  'negative ledger corruption creates one negative and two boundary issues'
);

select is(
  (
    select string_agg(
      issue.entity_key ->> 'issueCode',
      ':'
      order by issue.entity_key ->> 'issueCode'
    )
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
  ),
  'BATCH_LEDGER_BOUNDARY_MISMATCH:NEGATIVE_LEDGER_BUCKET:PRODUCT_LEDGER_BOUNDARY_MISMATCH',
  'negative ledger run preserves all helper classifications'
);

select is(
  (
    select issue.actual_value ->> 'quantity'
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
      and issue.entity_key ->> 'issueCode' =
        'NEGATIVE_LEDGER_BUCKET'
  ),
  '-1',
  'negative ledger issue persists the impossible quantity'
);

select ok(
  (
    select bool_and(issue.severity_code = 'CRITICAL')
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
  ),
  'negative ledger and stale boundary issues are critical'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'OPEN'
      and evidence.evidence_type_code =
        'IMPOSSIBLE_PROJECTION_STATE_MISMATCH'
  ),
  3::bigint,
  'negative ledger run stores typed evidence for all three issues'
);

select ok(
  (
    select
      balance.sellable_qty >= 0
    from inventory.stock_batch_balances balance
    where balance.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and balance.batch_id =
        '40000000-0000-4000-8000-000000000004'::uuid
  ),
  'negative ledger corruption remains distinct from projection quantity'
);

alter table inventory.stock_ledger_entries
  disable trigger trg_stock_ledger_entries_immutable;

delete from inventory.stock_ledger_entries ledger_entry
where ledger_entry.transaction_id =
  '9b000000-0000-4000-8000-000000000001'::uuid;

alter table inventory.stock_ledger_entries
  enable trigger trg_stock_ledger_entries_immutable;

alter table inventory.stock_transactions
  disable trigger trg_stock_transactions_immutable;

delete from inventory.stock_transactions stock_transaction
where stock_transaction.id =
  '9b000000-0000-4000-8000-000000000001'::uuid;

alter table inventory.stock_transactions
  enable trigger trg_stock_transactions_immutable;

delete from inventory.idempotency_commands command
where command.id =
  '9a000000-0000-4000-8000-000000000001'::uuid;

insert into impossible_integration_results (
  kind,
  result
)
select
  'NEGATIVE_RESTORED',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-IMPOSSIBLE-INTEGRATION-NEGATIVE-RESTORED-001',
    array[
      'IMPOSSIBLE_PROJECTION_STATE'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "impossible-negative-restored"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from impossible_integration_results
    where kind = 'NEGATIVE_RESTORED'
  ),
  'CLEAN',
  'removing negative-ledger corruption restores clean integrity'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'IMPOSSIBLE_PROJECTION_STATE'
      and issue.status_code = 'RESOLVED'
      and issue.resolution_code = 'NOT_REDETECTED'
  ),
  5::bigint,
  'clean rerun resolves boundary and negative-ledger issues'
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
      baseline.transaction_count::text
        || ':'
        || baseline.ledger_count::text
    from impossible_integration_baseline baseline
  ),
  'integration cleanup restores stock transaction and ledger counts'
);

select * from finish();

rollback;