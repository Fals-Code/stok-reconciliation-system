begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

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

select ok(
  has_function_privilege(
    'authenticated',
    'api.run_reconciliation(uuid,text,text[],jsonb,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may execute reconciliation'
);

select ok(
  has_function_privilege(
    'service_role',
    'api.run_reconciliation(uuid,text,text[],jsonb,jsonb)',
    'EXECUTE'
  ),
  'service role may execute reconciliation'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.run_reconciliation(uuid,text,text[],jsonb,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot execute reconciliation'
);

create temp table reconciliation_test_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temp table reconciliation_stock_snapshots (
  stage text primary key,
  transaction_count bigint not null,
  ledger_count bigint not null
) on commit drop;

insert into reconciliation_stock_snapshots (
  stage,
  transaction_count,
  ledger_count
)
select
  'BEFORE',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries);

insert into reconciliation_test_results (
  kind,
  result
)
select
  'CLEAN',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-CLEAN-001',
    array[
      'LEDGER_BATCH_PROJECTION',
      'BATCH_PRODUCT_PROJECTION'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "clean"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from reconciliation_test_results
    where kind = 'CLEAN'
  ),
  'SUCCEEDED',
  'clean reconciliation executes successfully'
);

select is(
  (
    select result ->> 'integrityStatus'
    from reconciliation_test_results
    where kind = 'CLEAN'
  ),
  'CLEAN',
  'clean baseline reports clean integrity'
);

select is(
  (
    select count(*)
    from reconciliation.runs run
    where run.id = (
      select (result ->> 'runId')::uuid
      from reconciliation_test_results
      where kind = 'CLEAN'
    )
  ),
  1::bigint,
  'clean reconciliation persists one run'
);

select is(
  (
    select count(*)
    from reconciliation.run_checks run_check
    where run_check.run_id = (
      select (result ->> 'runId')::uuid
      from reconciliation_test_results
      where kind = 'CLEAN'
    )
  ),
  2::bigint,
  'clean reconciliation persists two checks'
);

select is(
  (
    select count(*)
    from reconciliation.run_checks run_check
    where run_check.run_id = (
      select (result ->> 'runId')::uuid
      from reconciliation_test_results
      where kind = 'CLEAN'
    )
      and run_check.status_code = 'PASSED'
  ),
  2::bigint,
  'both clean projection checks pass'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.status_code = 'OPEN'
  ),
  0::bigint,
  'clean baseline creates no open issues'
);

select is(
  (select count(*) from inventory.stock_ledger_entries),
  (
    select ledger_count
    from reconciliation_stock_snapshots
    where stage = 'BEFORE'
  ),
  'clean reconciliation does not mutate ledger'
);

select is(
  (select count(*) from inventory.stock_transactions),
  (
    select transaction_count
    from reconciliation_stock_snapshots
    where stage = 'BEFORE'
  ),
  'clean reconciliation creates no stock transaction'
);

select is(
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-CLEAN-001',
    array[
      'LEDGER_BATCH_PROJECTION',
      'BATCH_PRODUCT_PROJECTION'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "clean"}'::jsonb
  ),
  (
    select result
    from reconciliation_test_results
    where kind = 'CLEAN'
  ),
  'idempotent replay returns the original response'
);

select is(
  (
    select count(*)
    from inventory.idempotency_commands command
    join reconciliation.runs run
      on run.idempotency_command_id = command.id
    where command.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and command.scope = 'RUN_RECONCILIATION'
      and command.key = 'PGTAP-RECON-CLEAN-001'
  ),
  1::bigint,
  'idempotent replay creates only one run'
);

select throws_ok(
  $sql$
    select api.run_reconciliation(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-RECON-CLEAN-001',
      array['LEDGER_BATCH_PROJECTION']::text[],
      '{}'::jsonb,
      '{"test": true, "fixture": "clean"}'::jsonb
    )
  $sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'same idempotency key rejects a different request'
);

update inventory.stock_batch_balances balance
set sellable_qty = balance.sellable_qty + 1
where balance.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and balance.batch_id =
    '40000000-0000-4000-8000-000000000001'::uuid;

insert into reconciliation_test_results (
  kind,
  result
)
select
  'BATCH_MISMATCH',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-BATCH-MISMATCH-001',
    array['LEDGER_BATCH_PROJECTION']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "batch-mismatch"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from reconciliation_test_results
    where kind = 'BATCH_MISMATCH'
  ),
  'SUCCEEDED',
  'mismatch detection is a successful reconciliation execution'
);

select is(
  (
    select result ->> 'integrityStatus'
    from reconciliation_test_results
    where kind = 'BATCH_MISMATCH'
  ),
  'ISSUES_FOUND',
  'batch projection mismatch reports issues found'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code = 'LEDGER_BATCH_PROJECTION'
      and issue.status_code = 'OPEN'
      and issue.batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'batch projection mismatch creates one open issue'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.id = evidence.issue_id
     and issue.organization_id = evidence.organization_id
    where issue.check_code = 'LEDGER_BATCH_PROJECTION'
      and issue.batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'batch projection mismatch stores evidence'
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
      from reconciliation_test_results
      where kind = 'BATCH_MISMATCH'
    )
      and run_check.check_code =
        'LEDGER_BATCH_PROJECTION'
  ),
  'FAILED:1',
  'batch projection check fails with one issue'
);

select is(
  (
    select issue.difference_value ->> 'sellableQty'
    from reconciliation.issues issue
    where issue.check_code = 'LEDGER_BATCH_PROJECTION'
      and issue.batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  '1',
  'batch projection issue records the quantity difference'
);

update inventory.stock_batch_balances balance
set sellable_qty = balance.sellable_qty - 1
where balance.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and balance.batch_id =
    '40000000-0000-4000-8000-000000000001'::uuid;

insert into reconciliation_test_results (
  kind,
  result
)
select
  'BATCH_RESTORED',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-BATCH-RESTORED-001',
    array['LEDGER_BATCH_PROJECTION']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "batch-restored"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from reconciliation_test_results
    where kind = 'BATCH_RESTORED'
  ),
  'CLEAN',
  'restored batch projection reports clean integrity'
);

select is(
  (
    select issue.status_code
    from reconciliation.issues issue
    where issue.check_code = 'LEDGER_BATCH_PROJECTION'
      and issue.batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  'RESOLVED',
  'clean rerun resolves the prior batch issue'
);

update inventory.stock_product_positions position
set sellable_qty = position.sellable_qty + 2
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

insert into reconciliation_test_results (
  kind,
  result
)
select
  'PRODUCT_MISMATCH',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-PRODUCT-MISMATCH-001',
    array['BATCH_PRODUCT_PROJECTION']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "product-mismatch"}'::jsonb
  );

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code = 'BATCH_PRODUCT_PROJECTION'
      and issue.status_code = 'OPEN'
      and issue.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'product projection mismatch creates one open issue'
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
      from reconciliation_test_results
      where kind = 'PRODUCT_MISMATCH'
    )
      and run_check.check_code =
        'BATCH_PRODUCT_PROJECTION'
  ),
  'FAILED:1',
  'product projection check fails with one issue'
);

select is(
  (select count(*) from inventory.stock_ledger_entries),
  (
    select ledger_count
    from reconciliation_stock_snapshots
    where stage = 'BEFORE'
  ),
  'all reconciliation runs leave ledger unchanged'
);

select is(
  (select count(*) from inventory.stock_transactions),
  (
    select transaction_count
    from reconciliation_stock_snapshots
    where stage = 'BEFORE'
  ),
  'all reconciliation runs create no stock transaction'
);

select * from finish();

rollback;