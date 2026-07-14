begin;

create extension if not exists pgtap with schema extensions;

select plan(25);

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

create temp table return_integration_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temp table return_integration_snapshots (
  stage text primary key,
  transaction_count bigint not null,
  ledger_count bigint not null
) on commit drop;

insert into return_integration_results (kind, result)
select
  'CLEAN_EMPTY',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-CLEAN-001',
    array['RETURN_RECEIPT_QUARANTINE']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "return-integration-empty"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from return_integration_results
    where kind = 'CLEAN_EMPTY'
  ),
  'CLEAN',
  'empty return receipt reconciliation is clean'
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
      from return_integration_results
      where kind = 'CLEAN_EMPTY'
    )
      and run_check.check_code =
        'RETURN_RECEIPT_QUARANTINE'
  ),
  'PASSED:0:0',
  'empty return check persists a clean zero-entity result'
);

insert into return_integration_results (kind, result)
select
  'RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'RECON-RETURN-INTEGRATION-RESERVE-EVENT-001',
    'RECON-RETURN-INTEGRATION-ORDER-001',
    '2026-07-25 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        4,
        'sourceLineRef',
        'RECON-RETURN-INTEGRATION-ITEM-001'
      )
    ),
    'Return integration reserve fixture.',
    '{"test": true, "fixture": "return-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_integration_results
    where kind = 'RESERVE'
  ),
  'APPLIED',
  'return integration reserve fixture is applied'
);

insert into return_integration_results (kind, result)
select
  'SHIP',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-SHIP-001',
    'SHOPEE',
    'SHIP',
    'RECON-RETURN-INTEGRATION-SHIP-EVENT-001',
    'RECON-RETURN-INTEGRATION-ORDER-001',
    '2026-07-25 09:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        4,
        'sourceLineRef',
        'RECON-RETURN-INTEGRATION-ITEM-001'
      )
    ),
    'Return integration shipment fixture.',
    '{"test": true, "fixture": "return-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_integration_results
    where kind = 'SHIP'
  ),
  'APPLIED',
  'return integration shipment fixture is applied'
);

insert into return_integration_results (kind, result)
select
  'EXPECTED',
  api.create_expected_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-EXPECTED-001',
    'SHOPEE',
    'RECON-RETURN-INTEGRATION-RETURN-001',
    'RECON-RETURN-INTEGRATION-ORDER-001',
    '2026-07-25 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        4,
        'sourceLineRef',
        'RECON-RETURN-INTEGRATION-ITEM-001'
      )
    ),
    'RETURN_REQUESTED',
    'Expected return integration fixture.',
    '{"test": true, "fixture": "return-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_integration_results
    where kind = 'EXPECTED'
  ),
  'EXPECTED',
  'return integration expected fixture is created'
);

insert into return_integration_results (kind, result)
select
  'LOST',
  api.mark_return_lost(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-LOST-001',
    'RECON-RETURN-INTEGRATION-RETURN-001',
    'RECON-RETURN-INTEGRATION-LOST-EVENT-001',
    '2026-07-25 10:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header
            on return_header.id = item.return_id
          where return_header.external_return_ref =
            'RECON-RETURN-INTEGRATION-RETURN-001'
        ),
        'quantity',
        1,
        'sourceLineRef',
        'RECON-RETURN-INTEGRATION-LOST-LINE-001'
      )
    ),
    'One expected unit is lost.',
    '{"test": true, "fixture": "return-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'eventType'
    from return_integration_results
    where kind = 'LOST'
  ),
  'LOST',
  'return integration lost fixture is applied'
);

insert into return_integration_results (kind, result)
select
  'RECEIPT',
  api.confirm_return_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-RECEIPT-001',
    'RECON-RETURN-INTEGRATION-RETURN-001',
    'RECON-RETURN-INTEGRATION-RECEIPT-001',
    '2026-07-25 11:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header
            on return_header.id = item.return_id
          where return_header.external_return_ref =
            'RECON-RETURN-INTEGRATION-RETURN-001'
        ),
        'marketplaceShipAllocationId',
        (
          select allocation.id::text
          from operations.marketplace_ship_allocations allocation
          join operations.marketplace_events marketplace_event
            on marketplace_event.id = allocation.event_id
          where marketplace_event.external_event_ref =
            'RECON-RETURN-INTEGRATION-SHIP-EVENT-001'
        ),
        'quantity',
        3,
        'sourceLineRef',
        'RECON-RETURN-INTEGRATION-RECEIPT-LINE-001'
      )
    ),
    'Physical return integration receipt.',
    '{"test": true, "fixture": "return-integration"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_integration_results
    where kind = 'RECEIPT'
  ),
  'RECEIVED_PENDING_INSPECTION',
  'return integration receipt enters pending inspection'
);

insert into return_integration_snapshots (
  stage,
  transaction_count,
  ledger_count
)
select
  'AFTER_RECEIPT',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries);

insert into return_integration_results (kind, result)
select
  'RECEIPT_CLEAN',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-VALID-001',
    array['RETURN_RECEIPT_QUARANTINE']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "return-integration-valid"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from return_integration_results
    where kind = 'RECEIPT_CLEAN'
  ),
  'CLEAN',
  'valid return receipt reconciliation is clean'
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
      from return_integration_results
      where kind = 'RECEIPT_CLEAN'
    )
      and run_check.check_code =
        'RETURN_RECEIPT_QUARANTINE'
  ),
  'PASSED:3:0',
  'valid return check covers expected, lost, and receipt events'
);

alter table operations.return_receipt_lines
  disable trigger trg_return_receipt_lines_immutable;

update operations.return_receipt_lines line
set quantity_received = line.quantity_received - 1
from operations.return_receipts receipt
where receipt.organization_id = line.organization_id
  and receipt.id = line.receipt_id
  and receipt.receipt_ref =
    'RECON-RETURN-INTEGRATION-RECEIPT-001';

alter table operations.return_receipt_lines
  enable trigger trg_return_receipt_lines_immutable;

insert into return_integration_results (kind, result)
select
  'RECEIPT_DRIFT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-DRIFT-001',
    array['RETURN_RECEIPT_QUARANTINE']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "return-integration-drift"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from return_integration_results
    where kind = 'RECEIPT_DRIFT'
  ),
  'ISSUES_FOUND',
  'return receipt drift is detected'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'RETURN_RECEIPT_QUARANTINE'
      and issue.status_code = 'OPEN'
      and issue.source_ref =
        'RECON-RETURN-INTEGRATION-RECEIPT-001'
  ),
  1::bigint,
  'return drift creates one open logical issue'
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
        'RETURN_RECEIPT_QUARANTINE'
      and issue.source_ref =
        'RECON-RETURN-INTEGRATION-RECEIPT-001'
  ),
  'HIGH:RETURN:RETURN_EVENT',
  'return receipt issue has high return-event classification'
);

select is(
  (
    select
      (issue.expected_value ->> 'eventLineQuantity')
        || ':'
        || (issue.actual_value ->> 'receiptQuantity')
        || ':'
        || (issue.actual_value ->> 'ledgerQuarantineQuantity')
        || ':'
        || (issue.actual_value ->> 'receiptLineCount')
        || ':'
        || (issue.actual_value ->> 'ledgerEntryCount')
        || ':'
        || (issue.actual_value ->> 'invalidReceiptLineCount')
        || ':'
        || (issue.actual_value ->> 'invalidLedgerCount')
        || ':'
        || (issue.actual_value ->> 'orphanLedgerCount')
        || ':'
        || (issue.actual_value ->> 'unexpectedTransactionCount')
        || ':'
        || (issue.difference_value ->> 'receiptQuantity')
        || ':'
        || (issue.difference_value ->> 'ledgerQuarantineQuantity')
    from reconciliation.issues issue
    where issue.check_code =
        'RETURN_RECEIPT_QUARANTINE'
      and issue.source_ref =
        'RECON-RETURN-INTEGRATION-RECEIPT-001'
  ),
  '3:2:3:1:1:1:0:0:0:-1:0',
  'return issue explains receipt and quarantine ledger quantities'
);

select is(
  (
    select evidence.detail ->> 'issueCode'
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'RETURN_RECEIPT_QUARANTINE'
      and issue.source_ref =
        'RECON-RETURN-INTEGRATION-RECEIPT-001'
  ),
  'RETURN_RECEIPT_LINE_LINK_INVALID',
  'return evidence stores the helper mismatch code'
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
      from return_integration_results
      where kind = 'RECEIPT_DRIFT'
    )
      and run_check.check_code =
        'RETURN_RECEIPT_QUARANTINE'
  ),
  'FAILED:3:1',
  'return check fails with one issue'
);

select is(
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-DRIFT-001',
    array['RETURN_RECEIPT_QUARANTINE']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "return-integration-drift"}'::jsonb
  ),
  (
    select result
    from return_integration_results
    where kind = 'RECEIPT_DRIFT'
  ),
  'return reconciliation replay is idempotent'
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
          'PGTAP-RECON-RETURN-INTEGRATION-DRIFT-001'
    )
  ),
  1::bigint,
  'return reconciliation replay keeps one run'
);

insert into return_integration_results (kind, result)
select
  'RECEIPT_DRIFT_REPEAT',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-DRIFT-002',
    array['RETURN_RECEIPT_QUARANTINE']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "return-integration-drift-repeat"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from return_integration_results
    where kind = 'RECEIPT_DRIFT_REPEAT'
  ),
  'ISSUES_FOUND',
  'repeated return receipt drift remains detected'
);

select is(
  (
    select count(*)
    from reconciliation.issues issue
    where issue.check_code =
        'RETURN_RECEIPT_QUARANTINE'
      and issue.source_ref =
        'RECON-RETURN-INTEGRATION-RECEIPT-001'
  ),
  1::bigint,
  'repeated return drift keeps one logical issue'
);

select is(
  (
    select issue.recurrence_count
    from reconciliation.issues issue
    where issue.check_code =
        'RETURN_RECEIPT_QUARANTINE'
      and issue.source_ref =
        'RECON-RETURN-INTEGRATION-RECEIPT-001'
  ),
  2::bigint,
  'repeated return drift increments issue recurrence'
);

select is(
  (
    select count(*)
    from reconciliation.issue_evidence evidence
    join reconciliation.issues issue
      on issue.organization_id = evidence.organization_id
     and issue.id = evidence.issue_id
    where issue.check_code =
        'RETURN_RECEIPT_QUARANTINE'
      and issue.source_ref =
        'RECON-RETURN-INTEGRATION-RECEIPT-001'
  ),
  2::bigint,
  'repeated return drift appends evidence'
);

alter table operations.return_receipt_lines
  disable trigger trg_return_receipt_lines_immutable;

update operations.return_receipt_lines line
set quantity_received = line.quantity_received + 1
from operations.return_receipts receipt
where receipt.organization_id = line.organization_id
  and receipt.id = line.receipt_id
  and receipt.receipt_ref =
    'RECON-RETURN-INTEGRATION-RECEIPT-001';

alter table operations.return_receipt_lines
  enable trigger trg_return_receipt_lines_immutable;

insert into return_integration_results (kind, result)
select
  'RECEIPT_RESTORED',
  api.run_reconciliation(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-INTEGRATION-RESTORED-001',
    array['RETURN_RECEIPT_QUARANTINE']::text[],
    '{}'::jsonb,
    '{"test": true, "fixture": "return-integration-restored"}'::jsonb
  );

select is(
  (
    select result ->> 'integrityStatus'
    from return_integration_results
    where kind = 'RECEIPT_RESTORED'
  ),
  'CLEAN',
  'restored return receipt reports clean integrity'
);

select is(
  (
    select issue.status_code
    from reconciliation.issues issue
    where issue.check_code =
        'RETURN_RECEIPT_QUARANTINE'
      and issue.source_ref =
        'RECON-RETURN-INTEGRATION-RECEIPT-001'
  ),
  'RESOLVED',
  'clean rerun resolves the prior return issue'
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
    from return_integration_snapshots snapshot
    where snapshot.stage = 'AFTER_RECEIPT'
  ),
  'return reconciliation creates no physical stock effect'
);

select * from finish();

rollback;