begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

select has_function(
  'reconciliation'::name,
  'find_return_receipt_quarantine_mismatches'::name,
  array['uuid']::text[]
);

select ok(
  not has_function_privilege(
    'authenticated',
    'reconciliation.find_return_receipt_quarantine_mismatches(uuid)',
    'EXECUTE'
  ),
  'authenticated users cannot execute the internal return comparison'
);

select ok(
  not has_function_privilege(
    'anon',
    'reconciliation.find_return_receipt_quarantine_mismatches(uuid)',
    'EXECUTE'
  ),
  'anonymous users cannot execute the internal return comparison'
);

select ok(
  not has_function_privilege(
    'service_role',
    'reconciliation.find_return_receipt_quarantine_mismatches(uuid)',
    'EXECUTE'
  ),
  'service role cannot bypass the public reconciliation command'
);

select is(
  (
    select count(*)
    from reconciliation.find_return_receipt_quarantine_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'clean seed has no return receipt or nonphysical-event mismatch'
);

create temp table return_comparison_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temp table return_comparison_snapshots (
  stage text primary key,
  transaction_count bigint not null,
  ledger_count bigint not null
) on commit drop;

insert into return_comparison_results (kind, result)
select
  'RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-COMPARE-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'RECON-RETURN-COMPARE-RESERVE-EVENT-001',
    'RECON-RETURN-COMPARE-ORDER-001',
    '2026-07-24 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        4,
        'sourceLineRef',
        'RECON-RETURN-COMPARE-ITEM-001'
      )
    ),
    'Return receipt reconciliation reserve fixture.',
    '{"test": true, "fixture": "return-receipt-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_comparison_results
    where kind = 'RESERVE'
  ),
  'APPLIED',
  'return comparison reserve fixture is applied'
);

insert into return_comparison_results (kind, result)
select
  'SHIP',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-COMPARE-SHIP-001',
    'SHOPEE',
    'SHIP',
    'RECON-RETURN-COMPARE-SHIP-EVENT-001',
    'RECON-RETURN-COMPARE-ORDER-001',
    '2026-07-24 09:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        4,
        'sourceLineRef',
        'RECON-RETURN-COMPARE-ITEM-001'
      )
    ),
    'Return receipt reconciliation shipment fixture.',
    '{"test": true, "fixture": "return-receipt-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_comparison_results
    where kind = 'SHIP'
  ),
  'APPLIED',
  'return comparison shipment fixture is applied'
);

insert into return_comparison_snapshots (
  stage,
  transaction_count,
  ledger_count
)
select
  'POST_SHIP',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries);

insert into return_comparison_results (kind, result)
select
  'EXPECTED',
  api.create_expected_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-COMPARE-EXPECTED-001',
    'SHOPEE',
    'RECON-RETURN-COMPARE-RETURN-001',
    'RECON-RETURN-COMPARE-ORDER-001',
    '2026-07-24 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        4,
        'sourceLineRef',
        'RECON-RETURN-COMPARE-ITEM-001'
      )
    ),
    'RETURN_REQUESTED',
    'Expected return comparison fixture.',
    '{"test": true, "fixture": "return-receipt-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_comparison_results
    where kind = 'EXPECTED'
  ),
  'EXPECTED',
  'expected return fixture is created'
);

select is(
  (
    select count(*)
    from reconciliation.find_return_receipt_quarantine_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'expected return remains stock-neutral'
);

insert into return_comparison_results (kind, result)
select
  'LOST',
  api.mark_return_lost(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-COMPARE-LOST-001',
    'RECON-RETURN-COMPARE-RETURN-001',
    'RECON-RETURN-COMPARE-LOST-EVENT-001',
    '2026-07-24 10:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header
            on return_header.id = item.return_id
          where return_header.external_return_ref =
            'RECON-RETURN-COMPARE-RETURN-001'
        ),
        'quantity',
        1,
        'sourceLineRef',
        'RECON-RETURN-COMPARE-LOST-LINE-001'
      )
    ),
    'One expected unit is lost.',
    '{"test": true, "fixture": "return-receipt-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'eventType'
    from return_comparison_results
    where kind = 'LOST'
  ),
  'LOST',
  'lost return fixture is applied'
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
    from return_comparison_snapshots snapshot
    where snapshot.stage = 'POST_SHIP'
  ),
  'expected and lost return events create no physical stock effect'
);

insert into return_comparison_results (kind, result)
select
  'RECEIPT',
  api.confirm_return_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RETURN-COMPARE-RECEIPT-001',
    'RECON-RETURN-COMPARE-RETURN-001',
    'RECON-RETURN-COMPARE-RECEIPT-001',
    '2026-07-24 11:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header
            on return_header.id = item.return_id
          where return_header.external_return_ref =
            'RECON-RETURN-COMPARE-RETURN-001'
        ),
        'marketplaceShipAllocationId',
        (
          select allocation.id::text
          from operations.marketplace_ship_allocations allocation
          join operations.marketplace_events event
            on event.id = allocation.event_id
          where event.external_event_ref =
            'RECON-RETURN-COMPARE-SHIP-EVENT-001'
        ),
        'quantity',
        3,
        'sourceLineRef',
        'RECON-RETURN-COMPARE-RECEIPT-LINE-001'
      )
    ),
    'Physical return receipt comparison fixture.',
    '{"test": true, "fixture": "return-receipt-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_comparison_results
    where kind = 'RECEIPT'
  ),
  'RECEIVED_PENDING_INSPECTION',
  'physical receipt closes pending arrival and enters inspection queue'
);

select is(
  (
    select count(*)
    from reconciliation.find_return_receipt_quarantine_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'valid physical return receipt agrees with quarantine ledger'
);

insert into return_comparison_snapshots (
  stage,
  transaction_count,
  ledger_count
)
select
  'POST_RECEIPT',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries);

alter table operations.return_receipt_lines
  disable trigger trg_return_receipt_lines_immutable;

update operations.return_receipt_lines line
set quantity_received = line.quantity_received - 1
from operations.return_receipts receipt
where receipt.organization_id = line.organization_id
  and receipt.id = line.receipt_id
  and receipt.receipt_ref =
    'RECON-RETURN-COMPARE-RECEIPT-001';

alter table operations.return_receipt_lines
  enable trigger trg_return_receipt_lines_immutable;

select is(
  (
    select count(*)
    from reconciliation.find_return_receipt_quarantine_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  1::bigint,
  'corrupted return receipt line creates one mismatch'
);

select is(
  (
    select
      event_line_quantity::text
        || ':'
        || receipt_quantity::text
        || ':'
        || ledger_quarantine_quantity::text
        || ':'
        || event_line_count::text
        || ':'
        || receipt_line_count::text
        || ':'
        || ledger_entry_count::text
        || ':'
        || invalid_receipt_line_count::text
        || ':'
        || invalid_ledger_count::text
        || ':'
        || orphan_ledger_count::text
        || ':'
        || unexpected_transaction_count::text
        || ':'
        || issue_code
    from reconciliation.find_return_receipt_quarantine_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  '3:2:3:1:1:1:1:0:0:0:RETURN_RECEIPT_LINE_LINK_INVALID',
  'return mismatch explains receipt, event-line, and quarantine ledger totals'
);

select is(
  (select count(*) from inventory.stock_transactions),
  (
    select transaction_count
    from return_comparison_snapshots
    where stage = 'POST_RECEIPT'
  ),
  'return comparison creates no stock transaction'
);

select is(
  (select count(*) from inventory.stock_ledger_entries),
  (
    select ledger_count
    from return_comparison_snapshots
    where stage = 'POST_RECEIPT'
  ),
  'return comparison leaves the ledger unchanged'
);

alter table operations.return_receipt_lines
  disable trigger trg_return_receipt_lines_immutable;

update operations.return_receipt_lines line
set quantity_received = line.quantity_received + 1
from operations.return_receipts receipt
where receipt.organization_id = line.organization_id
  and receipt.id = line.receipt_id
  and receipt.receipt_ref =
    'RECON-RETURN-COMPARE-RECEIPT-001';

alter table operations.return_receipt_lines
  enable trigger trg_return_receipt_lines_immutable;

select is(
  (
    select count(*)
    from reconciliation.find_return_receipt_quarantine_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'restored return receipt line clears the mismatch'
);

select * from finish();

rollback;