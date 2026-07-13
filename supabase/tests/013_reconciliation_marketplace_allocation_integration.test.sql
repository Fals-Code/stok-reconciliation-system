begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

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

create temp table marketplace_integration_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temp table marketplace_integration_snapshots (
  stage text primary key,
  transaction_count bigint not null,
  ledger_count bigint not null
) on commit drop;

insert into marketplace_integration_results (
  kind,
  result
)
select
  'CLEAN_EMPTY',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-MKT-INTEGRATION-CLEAN-001',
    array[
      'MARKETPLACE_ALLOCATION_CONSISTENCY'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "marketplace-empty"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from marketplace_integration_results
    where kind = 'CLEAN_EMPTY'
  ),
  'CLEAN',
  'empty marketplace allocation reconciliation is clean'
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
      from marketplace_integration_results
      where kind = 'CLEAN_EMPTY'
    )
      and run_check.check_code =
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
  ),
  'PASSED:0:0',
  'empty marketplace check persists a clean zero-entity result'
);

insert into marketplace_integration_results (
  kind,
  result
)
select
  'RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-MKT-INTEGRATION-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'RECON-MKT-INTEGRATION-RESERVE-EVENT-001',
    'RECON-MKT-INTEGRATION-ORDER-001',
    '2026-07-23 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        8,
        'sourceLineRef',
        'RECON-MKT-INTEGRATION-ITEM-001'
      )
    ),
    'Marketplace reconciliation integration reserve fixture.',
    '{"test": true, "fixture": "marketplace-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from marketplace_integration_results
    where kind = 'RESERVE'
  ),
  'APPLIED',
  'marketplace reserve fixture is applied'
);

insert into marketplace_integration_results (
  kind,
  result
)
select
  'SHIP',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-MKT-INTEGRATION-SHIP-001',
    'SHOPEE',
    'SHIP',
    'RECON-MKT-INTEGRATION-SHIP-EVENT-001',
    'RECON-MKT-INTEGRATION-ORDER-001',
    '2026-07-23 09:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        8,
        'sourceLineRef',
        'RECON-MKT-INTEGRATION-ITEM-001'
      )
    ),
    'Marketplace reconciliation integration shipment fixture.',
    '{"test": true, "fixture": "marketplace-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'allocationCount'
    from marketplace_integration_results
    where kind = 'SHIP'
  ),
  '2',
  'marketplace shipment fixture creates two FEFO allocations'
);

insert into marketplace_integration_results (
  kind,
  result
)
select
  'VALID_SHIPMENT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-MKT-INTEGRATION-VALID-001',
    array[
      'MARKETPLACE_ALLOCATION_CONSISTENCY'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "marketplace-valid"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from marketplace_integration_results
    where kind = 'VALID_SHIPMENT'
  ),
  'CLEAN',
  'valid marketplace shipment reconciliation is clean'
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
      from marketplace_integration_results
      where kind = 'VALID_SHIPMENT'
    )
      and run_check.check_code =
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
  ),
  'PASSED:1:0',
  'valid marketplace check examines one shipment with no issue'
);

insert into marketplace_integration_snapshots (
  stage,
  transaction_count,
  ledger_count
)
select
  'AFTER_SHIPMENT',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries);

alter table operations.marketplace_ship_allocations
  disable trigger trg_marketplace_ship_allocations_immutable;

update operations.marketplace_ship_allocations allocation
set quantity_allocated = allocation.quantity_allocated - 1
from operations.marketplace_events marketplace_event
where marketplace_event.organization_id =
    allocation.organization_id
  and marketplace_event.id = allocation.event_id
  and marketplace_event.external_event_ref =
    'RECON-MKT-INTEGRATION-SHIP-EVENT-001'
  and allocation.allocation_no = 1;

alter table operations.marketplace_ship_allocations
  enable trigger trg_marketplace_ship_allocations_immutable;

insert into marketplace_integration_results (
  kind,
  result
)
select
  'ALLOCATION_DRIFT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-MKT-INTEGRATION-DRIFT-001',
    array[
      'MARKETPLACE_ALLOCATION_CONSISTENCY'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "marketplace-allocation-drift"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from marketplace_integration_results
    where kind = 'ALLOCATION_DRIFT'
  ),
  'ISSUES_FOUND',
  'marketplace allocation drift is detected'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
      and issue.status_code = 'OPEN'
      and issue.source_ref =
        'RECON-MKT-INTEGRATION-SHIP-EVENT-001'
  ),
  1::bigint,
  'allocation drift creates one open logical issue'
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
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
      and issue.source_ref =
        'RECON-MKT-INTEGRATION-SHIP-EVENT-001'
  ),
  'CRITICAL:MARKETPLACE_SHIPMENT:MARKETPLACE_EVENT',
  'marketplace allocation issue has critical shipment classification'
);

select is(
  (
    select
      (issue.expected_value ->> 'eventLineQuantity')
        || ':'
        || (issue.actual_value ->> 'allocationQuantity')
        || ':'
        || (issue.actual_value ->> 'ledgerOutboundQuantity')
        || ':'
        || (issue.actual_value ->> 'allocationCount')
        || ':'
        || (issue.actual_value ->> 'ledgerEntryCount')
        || ':'
        || (issue.actual_value ->> 'invalidAllocationCount')
        || ':'
        || (issue.actual_value ->> 'invalidLedgerCount')
        || ':'
        || (issue.actual_value ->> 'orphanLedgerCount')
        || ':'
        || (issue.difference_value ->> 'allocationQuantity')
        || ':'
        || (issue.difference_value ->> 'ledgerOutboundQuantity')
    from reconciliation.issues issue
    where issue.check_code =
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
      and issue.source_ref =
        'RECON-MKT-INTEGRATION-SHIP-EVENT-001'
  ),
  '8:7:8:2:2:1:0:0:-1:0',
  'marketplace issue explains event, allocation, and ledger quantities'
);

select is(
  (
    select evidence.detail ->> 'issueCode'
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
      and issue.source_ref =
        'RECON-MKT-INTEGRATION-SHIP-EVENT-001'
  ),
  'MARKETPLACE_ALLOCATION_LINK_INVALID',
  'marketplace evidence stores the helper mismatch code'
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
      from marketplace_integration_results
      where kind = 'ALLOCATION_DRIFT'
    )
      and run_check.check_code =
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
  ),
  'FAILED:1:1',
  'marketplace check fails with one issue'
);

select is(
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-MKT-INTEGRATION-DRIFT-001',
    array[
      'MARKETPLACE_ALLOCATION_CONSISTENCY'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "marketplace-allocation-drift"}'::jsonb
  ),
  (
    select result
    from marketplace_integration_results
    where kind = 'ALLOCATION_DRIFT'
  ),
  'marketplace reconciliation replay is idempotent'
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
        'PGTAP-RECON-MKT-INTEGRATION-DRIFT-001'
  ),
  1::bigint,
  'idempotent marketplace replay creates one run'
);

insert into marketplace_integration_results (
  kind,
  result
)
select
  'ALLOCATION_REPEAT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-MKT-INTEGRATION-DRIFT-002',
    array[
      'MARKETPLACE_ALLOCATION_CONSISTENCY'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "marketplace-allocation-repeat"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from marketplace_integration_results
    where kind = 'ALLOCATION_REPEAT'
  ),
  'ISSUES_FOUND',
  'repeated marketplace allocation drift remains detectable'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
      and issue.source_ref =
        'RECON-MKT-INTEGRATION-SHIP-EVENT-001'
  ),
  1::bigint,
  'repeated marketplace drift keeps one logical issue'
);

select is(
  (
    select issue.recurrence_count
    from reconciliation.issues issue
    where issue.check_code =
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
      and issue.source_ref =
        'RECON-MKT-INTEGRATION-SHIP-EVENT-001'
  ),
  2::bigint,
  'repeated marketplace drift increments issue recurrence'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
      and issue.source_ref =
        'RECON-MKT-INTEGRATION-SHIP-EVENT-001'
  ),
  2::bigint,
  'repeated marketplace drift appends evidence'
);

alter table operations.marketplace_ship_allocations
  disable trigger trg_marketplace_ship_allocations_immutable;

update operations.marketplace_ship_allocations allocation
set quantity_allocated = allocation.quantity_allocated + 1
from operations.marketplace_events marketplace_event
where marketplace_event.organization_id =
    allocation.organization_id
  and marketplace_event.id = allocation.event_id
  and marketplace_event.external_event_ref =
    'RECON-MKT-INTEGRATION-SHIP-EVENT-001'
  and allocation.allocation_no = 1;

alter table operations.marketplace_ship_allocations
  enable trigger trg_marketplace_ship_allocations_immutable;

insert into marketplace_integration_results (
  kind,
  result
)
select
  'ALLOCATION_RESTORED',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-MKT-INTEGRATION-RESTORED-001',
    array[
      'MARKETPLACE_ALLOCATION_CONSISTENCY'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "marketplace-allocation-restored"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from marketplace_integration_results
    where kind = 'ALLOCATION_RESTORED'
  ),
  'CLEAN',
  'restored marketplace allocation reports clean integrity'
);

select is(
  (
    select issue.status_code
    from reconciliation.issues issue
    where issue.check_code =
        'MARKETPLACE_ALLOCATION_CONSISTENCY'
      and issue.source_ref =
        'RECON-MKT-INTEGRATION-SHIP-EVENT-001'
  ),
  'RESOLVED',
  'clean rerun resolves the prior marketplace issue'
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
    from marketplace_integration_snapshots snapshot
    where snapshot.stage = 'AFTER_SHIPMENT'
  ),
  'marketplace reconciliation creates no physical stock effect'
);

select * from finish();

rollback;