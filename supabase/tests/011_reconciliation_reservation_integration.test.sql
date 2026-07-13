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

create temp table reservation_integration_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temp table reservation_integration_snapshots (
  stage text primary key,
  transaction_count bigint not null,
  ledger_count bigint not null
) on commit drop;

insert into reservation_integration_snapshots (
  stage,
  transaction_count,
  ledger_count
)
select
  'BEFORE',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries);

insert into reservation_integration_results (
  kind,
  result
)
select
  'DEFAULT_CLEAN',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-DEFAULT-V2-001'
  );

select is(
  (
    select result ->> 'status'
    from reservation_integration_results
    where kind = 'DEFAULT_CLEAN'
  ),
  'SUCCEEDED',
  'default reconciliation executes successfully'
);

select is(
  (
    select result ->> 'integrityStatus'
    from reservation_integration_results
    where kind = 'DEFAULT_CLEAN'
  ),
  'CLEAN',
  'default clean baseline reports clean integrity'
);

select is(
  (
    select result ->> 'checkCount'
    from reservation_integration_results
    where kind = 'DEFAULT_CLEAN'
  ),
  '3',
  'default reconciliation executes three checks'
);

select is(
  (
    select count(*)
    from reconciliation.run_checks run_check
    where run_check.run_id = (
      select (result ->> 'runId')::uuid
      from reservation_integration_results
      where kind = 'DEFAULT_CLEAN'
    )
  ),
  3::bigint,
  'default run persists three check results'
);

select is(
  (
    select
      run_check.status_code
        || ':'
        || run_check.checked_count::text
        || ':'
        || run_check.issue_count::text
    from reconciliation.run_checks run_check
    where run_check.run_id = (
      select (result ->> 'runId')::uuid
      from reservation_integration_results
      where kind = 'DEFAULT_CLEAN'
    )
      and run_check.check_code =
        'RESERVATION_CONSISTENCY'
  ),
  'PASSED:3:0',
  'default reservation consistency check passes'
);

insert into reservation_integration_results (
  kind,
  result
)
select
  'RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INTEGRATION-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'RECON-INTEGRATION-RESERVE-EVENT-001',
    'RECON-INTEGRATION-RESERVE-ORDER-001',
    '2026-07-21 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        3,
        'sourceLineRef',
        'RECON-INTEGRATION-ITEM-001'
      )
    ),
    'Reservation reconciliation integration fixture.',
    '{"test": true, "fixture": "reservation-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from reservation_integration_results
    where kind = 'RESERVE'
  ),
  'APPLIED',
  'reservation integration fixture is applied'
);

insert into reservation_integration_results (
  kind,
  result
)
select
  'RESERVATION_CLEAN',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RESERVATION-CLEAN-001',
    array['RESERVATION_CONSISTENCY']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "reservation-clean"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from reservation_integration_results
    where kind = 'RESERVATION_CLEAN'
  ),
  'CLEAN',
  'valid reservation reports clean integrity'
);

select is(
  (
    select
      run_check.status_code
        || ':'
        || run_check.checked_count::text
        || ':'
        || run_check.issue_count::text
    from reconciliation.run_checks run_check
    where run_check.run_id = (
      select (result ->> 'runId')::uuid
      from reservation_integration_results
      where kind = 'RESERVATION_CLEAN'
    )
      and run_check.check_code =
        'RESERVATION_CONSISTENCY'
  ),
  'PASSED:3:0',
  'valid reservation check passes'
);

update inventory.stock_product_positions position
set
  reserved_qty = position.reserved_qty + 1,
  version = position.version + 1
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

insert into reservation_integration_results (
  kind,
  result
)
select
  'RESERVATION_DRIFT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RESERVATION-DRIFT-001',
    array['RESERVATION_CONSISTENCY']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "reservation-drift"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from reservation_integration_results
    where kind = 'RESERVATION_DRIFT'
  ),
  'SUCCEEDED',
  'reservation mismatch is a successful reconciliation execution'
);

select is(
  (
    select result ->> 'integrityStatus'
    from reservation_integration_results
    where kind = 'RESERVATION_DRIFT'
  ),
  'ISSUES_FOUND',
  'reservation drift reports issues found'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code = 'RESERVATION_CONSISTENCY'
      and issue.status_code = 'OPEN'
      and issue.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'reservation drift creates one open logical issue'
);

select is(
  (
    select
      issue.severity_code
        || ':'
        || issue.entity_type_code
    from reconciliation.issues issue
    where issue.check_code = 'RESERVATION_CONSISTENCY'
      and issue.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  'HIGH:PRODUCT_RESERVATION',
  'reservation projection drift has the expected classification'
);

select is(
  (
    select
      (issue.expected_value ->> 'reservedQty')
        || ':'
        || (issue.actual_value ->> 'reservedQty')
        || ':'
        || (issue.expected_value ->> 'sellableQty')
        || ':'
        || (issue.expected_value ->> 'availableQty')
        || ':'
        || (issue.actual_value ->> 'availableQty')
        || ':'
        || (issue.difference_value ->> 'reservedQty')
        || ':'
        || (issue.difference_value ->> 'availableQty')
    from reconciliation.issues issue
    where issue.check_code = 'RESERVATION_CONSISTENCY'
      and issue.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  '3:4:25:22:21:1:-1',
  'reservation issue explains reserved and available quantities'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code = 'RESERVATION_CONSISTENCY'
      and issue.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'reservation drift stores one evidence row'
);

select is(
  (
    select evidence.detail ->> 'issueCode'
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code = 'RESERVATION_CONSISTENCY'
      and issue.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  'RESERVATION_PROJECTION_MISMATCH',
  'reservation evidence stores the mismatch code'
);

select is(
  (
    select
      run_check.status_code
        || ':'
        || run_check.checked_count::text
        || ':'
        || run_check.issue_count::text
    from reconciliation.run_checks run_check
    where run_check.run_id = (
      select (result ->> 'runId')::uuid
      from reservation_integration_results
      where kind = 'RESERVATION_DRIFT'
    )
      and run_check.check_code =
        'RESERVATION_CONSISTENCY'
  ),
  'FAILED:3:1',
  'reservation check fails with one issue'
);

select is(
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RESERVATION-DRIFT-001',
    array['RESERVATION_CONSISTENCY']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "reservation-drift"}'::jsonb
  ),
  (
    select result
    from reservation_integration_results
    where kind = 'RESERVATION_DRIFT'
  ),
  'reservation reconciliation replay is idempotent'
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
      and command.key =
        'PGTAP-RECON-RESERVATION-DRIFT-001'
  ),
  1::bigint,
  'idempotent reservation replay creates one run'
);

insert into reservation_integration_results (
  kind,
  result
)
select
  'RESERVATION_REPEAT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RESERVATION-DRIFT-002',
    array['RESERVATION_CONSISTENCY']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "reservation-drift-repeat"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from reservation_integration_results
    where kind = 'RESERVATION_REPEAT'
  ),
  'ISSUES_FOUND',
  'repeated reservation drift remains detectable'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code = 'RESERVATION_CONSISTENCY'
      and issue.status_code = 'OPEN'
      and issue.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'repeated drift keeps one logical issue'
);

select is(
  (
    select issue.recurrence_count
    from reconciliation.issues issue
    where issue.check_code = 'RESERVATION_CONSISTENCY'
      and issue.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'repeated drift increments issue recurrence'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code = 'RESERVATION_CONSISTENCY'
      and issue.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'repeated drift appends evidence without duplicating the issue'
);

update inventory.stock_product_positions position
set
  reserved_qty = position.reserved_qty - 1,
  version = position.version + 1
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

insert into reservation_integration_results (
  kind,
  result
)
select
  'RESERVATION_RESTORED',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RESERVATION-RESTORED-001',
    array['RESERVATION_CONSISTENCY']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "reservation-restored"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from reservation_integration_results
    where kind = 'RESERVATION_RESTORED'
  ),
  'CLEAN',
  'restored reservation projection reports clean integrity'
);

select is(
  (
    select issue.status_code
    from reconciliation.issues issue
    where issue.check_code = 'RESERVATION_CONSISTENCY'
      and issue.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  'RESOLVED',
  'clean rerun resolves the prior reservation issue'
);

select is(
  (select count(*) from inventory.stock_ledger_entries),
  (
    select ledger_count
    from reservation_integration_snapshots
    where stage = 'BEFORE'
  ),
  'reservation reconciliation leaves the ledger unchanged'
);

select is(
  (select count(*) from inventory.stock_transactions),
  (
    select transaction_count
    from reservation_integration_snapshots
    where stage = 'BEFORE'
  ),
  'reservation reconciliation creates no stock transaction'
);

select * from finish();

rollback;