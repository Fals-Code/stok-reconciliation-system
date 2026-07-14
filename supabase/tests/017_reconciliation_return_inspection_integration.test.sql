begin;

create extension if not exists pgtap with schema extensions;

select plan(25);

create temp table inspection_integration_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temp table inspection_integration_snapshots (
  stage text primary key,
  transaction_count bigint not null,
  ledger_count bigint not null
) on commit drop;

insert into inspection_integration_results (
  kind,
  result
)
select
  'CLEAN_EMPTY',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-CLEAN-001',
    array[
      'RETURN_INSPECTION_TRANSFER'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "inspection-integration-empty"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from inspection_integration_results
    where kind = 'CLEAN_EMPTY'
  ),
  'CLEAN',
  'empty return inspection reconciliation is clean'
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
      from inspection_integration_results
      where kind = 'CLEAN_EMPTY'
    )
      and run_check.check_code =
        'RETURN_INSPECTION_TRANSFER'
  ),
  'PASSED:0:0',
  'empty return inspection check persists a clean result'
);

insert into inspection_integration_results (
  kind,
  result
)
select
  'RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'RECON-INSPECTION-INTEGRATION-RESERVE-EVENT-001',
    'RECON-INSPECTION-INTEGRATION-ORDER-001',
    '2026-07-27 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        3,
        'sourceLineRef',
        'RECON-INSPECTION-INTEGRATION-ORDER-LINE-001'
      )
    ),
    'Return inspection integration reserve fixture.',
    '{"test": true, "fixture": "inspection-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from inspection_integration_results
    where kind = 'RESERVE'
  ),
  'APPLIED',
  'inspection integration reserve fixture is applied'
);

insert into inspection_integration_results (
  kind,
  result
)
select
  'SHIP',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-SHIP-001',
    'SHOPEE',
    'SHIP',
    'RECON-INSPECTION-INTEGRATION-SHIP-EVENT-001',
    'RECON-INSPECTION-INTEGRATION-ORDER-001',
    '2026-07-27 09:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        3,
        'sourceLineRef',
        'RECON-INSPECTION-INTEGRATION-ORDER-LINE-001'
      )
    ),
    'Return inspection integration shipment fixture.',
    '{"test": true, "fixture": "inspection-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from inspection_integration_results
    where kind = 'SHIP'
  ),
  'APPLIED',
  'inspection integration shipment fixture is applied'
);

insert into inspection_integration_results (
  kind,
  result
)
select
  'EXPECTED',
  api.create_expected_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-EXPECTED-001',
    'SHOPEE',
    'RECON-INSPECTION-INTEGRATION-RETURN-001',
    'RECON-INSPECTION-INTEGRATION-ORDER-001',
    '2026-07-27 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        3,
        'sourceLineRef',
        'RECON-INSPECTION-INTEGRATION-ORDER-LINE-001'
      )
    ),
    'RETURN_REQUESTED',
    'Return inspection integration expected fixture.',
    '{"test": true, "fixture": "inspection-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from inspection_integration_results
    where kind = 'EXPECTED'
  ),
  'EXPECTED',
  'inspection integration expected return is created'
);

insert into inspection_integration_results (
  kind,
  result
)
select
  'RECEIPT',
  api.confirm_return_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-RECEIPT-001',
    'RECON-INSPECTION-INTEGRATION-RETURN-001',
    'RECON-INSPECTION-INTEGRATION-RECEIPT-001',
    '2026-07-27 11:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header
            on return_header.id = item.return_id
          where return_header.external_return_ref =
            'RECON-INSPECTION-INTEGRATION-RETURN-001'
        ),
        'marketplaceShipAllocationId',
        (
          select allocation.id::text
          from operations.marketplace_ship_allocations allocation
          join operations.marketplace_events marketplace_event
            on marketplace_event.id = allocation.event_id
          where marketplace_event.external_event_ref =
            'RECON-INSPECTION-INTEGRATION-SHIP-EVENT-001'
        ),
        'quantity',
        3,
        'sourceLineRef',
        'RECON-INSPECTION-INTEGRATION-RECEIPT-LINE-001'
      )
    ),
    'Return inspection integration receipt fixture.',
    '{"test": true, "fixture": "inspection-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from inspection_integration_results
    where kind = 'RECEIPT'
  ),
  'RECEIVED_PENDING_INSPECTION',
  'inspection integration receipt enters quarantine'
);

insert into inspection_integration_results (
  kind,
  result
)
select
  'INSPECTION',
  api.inspect_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-INSPECT-001',
    'RECON-INSPECTION-INTEGRATION-RETURN-001',
    'RECON-INSPECTION-INTEGRATION-INSPECTION-001',
    '2026-07-27 12:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'receiptLineId',
        (
          select receipt_line.id::text
          from operations.return_receipt_lines receipt_line
          join operations.return_receipts receipt
            on receipt.id = receipt_line.receipt_id
          where receipt.receipt_ref =
            'RECON-INSPECTION-INTEGRATION-RECEIPT-001'
        ),
        'sellableQuantity',
        2,
        'damagedQuantity',
        1,
        'sourceLineRef',
        'RECON-INSPECTION-INTEGRATION-LINE-001'
      )
    ),
    'Return inspection integration mixed fixture.',
    '{"test": true, "fixture": "inspection-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from inspection_integration_results
    where kind = 'INSPECTION'
  ),
  'COMPLETED_MIXED',
  'inspection integration fixture completes as mixed'
);

insert into inspection_integration_snapshots (
  stage,
  transaction_count,
  ledger_count
)
select
  'AFTER_INSPECTION',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries);

insert into inspection_integration_results (
  kind,
  result
)
select
  'INSPECTION_CLEAN',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-VALID-001',
    array[
      'RETURN_INSPECTION_TRANSFER'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "inspection-integration-valid"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from inspection_integration_results
    where kind = 'INSPECTION_CLEAN'
  ),
  'CLEAN',
  'valid return inspection reconciliation is clean'
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
      from inspection_integration_results
      where kind = 'INSPECTION_CLEAN'
    )
      and run_check.check_code =
        'RETURN_INSPECTION_TRANSFER'
  ),
  'PASSED:1:0',
  'valid return inspection check covers one inspection'
);

alter table operations.return_inspection_allocations
  disable trigger trg_return_inspection_allocations_immutable;

update operations.return_inspection_allocations allocation
set quantity_allocated = allocation.quantity_allocated - 1
from operations.return_inspections inspection
where inspection.organization_id = allocation.organization_id
  and inspection.id = allocation.inspection_id
  and inspection.inspection_ref =
    'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  and allocation.destination_bucket_code = 'SELLABLE';

alter table operations.return_inspection_allocations
  enable trigger trg_return_inspection_allocations_immutable;

insert into inspection_integration_results (
  kind,
  result
)
select
  'INSPECTION_DRIFT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-DRIFT-001',
    array[
      'RETURN_INSPECTION_TRANSFER'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "inspection-integration-drift"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from inspection_integration_results
    where kind = 'INSPECTION_DRIFT'
  ),
  'ISSUES_FOUND',
  'return inspection drift is detected'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'RETURN_INSPECTION_TRANSFER'
      and issue.status_code = 'OPEN'
      and issue.source_ref =
        'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  ),
  1::bigint,
  'return inspection drift creates one open logical issue'
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
        'RETURN_INSPECTION_TRANSFER'
      and issue.source_ref =
        'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  ),
  'CRITICAL:RETURN:RETURN_EVENT',
  'return inspection issue has critical return-event classification'
);

select is(
  (
    select
      (issue.expected_value ->> 'eventLineQuantity')
        || ':'
        || (issue.actual_value ->> 'allocationQuantity')
        || ':'
        || (
          issue.actual_value
            ->> 'sourceQuarantineQuantity'
        )
        || ':'
        || (issue.actual_value ->> 'destinationQuantity')
        || ':'
        || (issue.actual_value ->> 'netQuantity')
        || ':'
        || (issue.actual_value ->> 'eventLineCount')
        || ':'
        || (issue.actual_value ->> 'allocationCount')
        || ':'
        || (issue.actual_value ->> 'sourceLedgerCount')
        || ':'
        || (
          issue.actual_value
            ->> 'destinationLedgerCount'
        )
        || ':'
        || (issue.actual_value ->> 'invalidHeaderCount')
        || ':'
        || (
          issue.actual_value
            ->> 'lineTotalMismatchCount'
        )
        || ':'
        || (
          issue.actual_value
            ->> 'invalidAllocationCount'
        )
        || ':'
        || (
          issue.actual_value
            ->> 'invalidSourceLedgerCount'
        )
        || ':'
        || (
          issue.actual_value
            ->> 'invalidDestinationLedgerCount'
        )
        || ':'
        || (issue.actual_value ->> 'orphanLedgerCount')
        || ':'
        || (
          issue.difference_value
            ->> 'allocationQuantity'
        )
        || ':'
        || (
          issue.difference_value
            ->> 'sourceQuarantineQuantity'
        )
        || ':'
        || (
          issue.difference_value
            ->> 'destinationQuantity'
        )
        || ':'
        || (issue.difference_value ->> 'netQuantity')
    from reconciliation.issues issue
    where issue.check_code =
        'RETURN_INSPECTION_TRANSFER'
      and issue.source_ref =
        'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  ),
  '3:2:3:3:0:1:2:2:2:0:1:0:1:1:0:-1:0:0:0',
  'return inspection issue explains allocation and paired ledger drift'
);

select is(
  (
    select evidence.detail ->> 'issueCode'
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'RETURN_INSPECTION_TRANSFER'
      and issue.source_ref =
        'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  ),
  'RETURN_INSPECTION_ALLOCATION_LINK_INVALID',
  'return inspection evidence stores the helper mismatch code'
);

select is(
  (
    select evidence.detail ->> 'ruleSetVersion'
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'RETURN_INSPECTION_TRANSFER'
      and issue.source_ref =
        'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  ),
  'core-integrity-v6',
  'return inspection evidence records the v6 rule set'
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
      from inspection_integration_results
      where kind = 'INSPECTION_DRIFT'
    )
      and run_check.check_code =
        'RETURN_INSPECTION_TRANSFER'
  ),
  'FAILED:1:1',
  'return inspection check fails with one issue'
);

select is(
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-DRIFT-001',
    array[
      'RETURN_INSPECTION_TRANSFER'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "inspection-integration-drift"}'::jsonb
  ),
  (
    select result
    from inspection_integration_results
    where kind = 'INSPECTION_DRIFT'
  ),
  'return inspection reconciliation replay is idempotent'
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
          'PGTAP-RECON-INSPECTION-INTEGRATION-DRIFT-001'
    )
  ),
  1::bigint,
  'return inspection reconciliation replay keeps one run'
);

insert into inspection_integration_results (
  kind,
  result
)
select
  'INSPECTION_DRIFT_REPEAT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-DRIFT-002',
    array[
      'RETURN_INSPECTION_TRANSFER'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "inspection-integration-drift-repeat"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from inspection_integration_results
    where kind = 'INSPECTION_DRIFT_REPEAT'
  ),
  'ISSUES_FOUND',
  'repeated return inspection drift remains detected'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'RETURN_INSPECTION_TRANSFER'
      and issue.source_ref =
        'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  ),
  1::bigint,
  'repeated return inspection drift keeps one logical issue'
);

select is(
  (
    select issue.recurrence_count
    from reconciliation.issues issue
    where issue.check_code =
        'RETURN_INSPECTION_TRANSFER'
      and issue.source_ref =
        'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  ),
  2::bigint,
  'repeated return inspection drift increments recurrence'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'RETURN_INSPECTION_TRANSFER'
      and issue.source_ref =
        'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  ),
  2::bigint,
  'repeated return inspection drift appends evidence'
);

alter table operations.return_inspection_allocations
  disable trigger trg_return_inspection_allocations_immutable;

update operations.return_inspection_allocations allocation
set quantity_allocated = allocation.quantity_allocated + 1
from operations.return_inspections inspection
where inspection.organization_id = allocation.organization_id
  and inspection.id = allocation.inspection_id
  and inspection.inspection_ref =
    'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  and allocation.destination_bucket_code = 'SELLABLE';

alter table operations.return_inspection_allocations
  enable trigger trg_return_inspection_allocations_immutable;

insert into inspection_integration_results (
  kind,
  result
)
select
  'INSPECTION_RESTORED',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INTEGRATION-RESTORED-001',
    array[
      'RETURN_INSPECTION_TRANSFER'
    ]::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "inspection-integration-restored"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from inspection_integration_results
    where kind = 'INSPECTION_RESTORED'
  ),
  'CLEAN',
  'restored return inspection reports clean integrity'
);

select is(
  (
    select issue.status_code
    from reconciliation.issues issue
    where issue.check_code =
        'RETURN_INSPECTION_TRANSFER'
      and issue.source_ref =
        'RECON-INSPECTION-INTEGRATION-INSPECTION-001'
  ),
  'RESOLVED',
  'clean rerun resolves the prior return inspection issue'
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
    from inspection_integration_snapshots snapshot
    where snapshot.stage = 'AFTER_INSPECTION'
  ),
  'return inspection reconciliation creates no physical stock effect'
);

select * from finish();

rollback;