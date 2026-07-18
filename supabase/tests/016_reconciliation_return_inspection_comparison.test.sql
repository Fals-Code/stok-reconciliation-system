begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

select has_function(
  'reconciliation',
  'find_return_inspection_consistency_mismatches',
  array['uuid']::text[],
  'return inspection comparison helper exists'
);

select is(
  (
    select procedure.prosecdef
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'reconciliation'
      and procedure.proname =
        'find_return_inspection_consistency_mismatches'
      and pg_get_function_identity_arguments(procedure.oid) =
        'p_organization_id uuid'
  ),
  true,
  'return inspection helper uses security definer'
);

select is(
  (
    select array_to_string(procedure.proconfig, ',')
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'reconciliation'
      and procedure.proname =
        'find_return_inspection_consistency_mismatches'
      and pg_get_function_identity_arguments(procedure.oid) =
        'p_organization_id uuid'
  ),
  'search_path=pg_catalog, catalog, inventory, operations, reconciliation',
  'return inspection helper has a fixed search path'
);

select ok(
  position(
    '''LEGACY_QUARANTINE_TRANSFER'''
    in (
      select pg_get_functiondef(procedure.oid)
      from pg_proc procedure
      join pg_namespace namespace
        on namespace.oid = procedure.pronamespace
      where namespace.nspname = 'reconciliation'
        and procedure.proname =
          'find_return_inspection_consistency_mismatches'
        and pg_get_function_identity_arguments(procedure.oid) =
          'p_organization_id uuid'
    )
  ) > 0,
  'return inspection helper recognizes the legacy quarantine-transfer contract'
);

select ok(
  position(
    '''LEGACY_TRANSFER'''
    in (
      select pg_get_functiondef(procedure.oid)
      from pg_proc procedure
      join pg_namespace namespace
        on namespace.oid = procedure.pronamespace
      where namespace.nspname = 'reconciliation'
        and procedure.proname =
          'find_return_inspection_consistency_mismatches'
        and pg_get_function_identity_arguments(procedure.oid) =
          'p_organization_id uuid'
    )
  ) = 0,
  'return inspection helper does not use an undefined legacy effect code'
);

select is(
  (
    select count(*)
    from information_schema.routine_privileges privilege
    where privilege.specific_schema = 'reconciliation'
      and privilege.routine_name =
        'find_return_inspection_consistency_mismatches'
      and privilege.grantee in (
        'PUBLIC',
        'anon',
        'authenticated',
        'service_role'
      )
      and privilege.privilege_type = 'EXECUTE'
  ),
  0::bigint,
  'return inspection helper is not executable by client roles'
);

select is(
  (
    select count(*)
    from reconciliation.find_return_inspection_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'clean seed has no return inspection mismatch'
);

create temp table return_inspection_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

insert into return_inspection_results (kind, result)
select
  'RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'RECON-INSPECTION-RESERVE-EVENT-001',
    'RECON-INSPECTION-ORDER-001',
    '2026-07-26 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        3,
        'sourceLineRef',
        'RECON-INSPECTION-ORDER-LINE-001'
      )
    ),
    'Return inspection comparison reserve fixture.',
    '{"test": true, "fixture": "inspection-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_inspection_results
    where kind = 'RESERVE'
  ),
  'APPLIED',
  'inspection comparison reserve fixture is applied'
);

insert into return_inspection_results (kind, result)
select
  'SHIP',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-SHIP-001',
    'SHOPEE',
    'SHIP',
    'RECON-INSPECTION-SHIP-EVENT-001',
    'RECON-INSPECTION-ORDER-001',
    '2026-07-26 09:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        3,
        'sourceLineRef',
        'RECON-INSPECTION-ORDER-LINE-001'
      )
    ),
    'Return inspection comparison shipment fixture.',
    '{"test": true, "fixture": "inspection-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_inspection_results
    where kind = 'SHIP'
  ),
  'APPLIED',
  'inspection comparison shipment fixture is applied'
);

insert into return_inspection_results (kind, result)
select
  'EXPECTED',
  api.create_expected_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-EXPECTED-001',
    'SHOPEE',
    'RECON-INSPECTION-RETURN-001',
    'RECON-INSPECTION-ORDER-001',
    '2026-07-26 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        3,
        'sourceLineRef',
        'RECON-INSPECTION-ORDER-LINE-001'
      )
    ),
    'RETURN_REQUESTED',
    'Return inspection comparison expected fixture.',
    '{"test": true, "fixture": "inspection-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_inspection_results
    where kind = 'EXPECTED'
  ),
  'EXPECTED',
  'inspection comparison expected return is created'
);

insert into return_inspection_results (kind, result)
select
  'RECEIPT',
  api.confirm_return_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-RECEIPT-001',
    'RECON-INSPECTION-RETURN-001',
    'RECON-INSPECTION-RECEIPT-001',
    '2026-07-26 11:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header
            on return_header.id = item.return_id
          where return_header.external_return_ref =
            'RECON-INSPECTION-RETURN-001'
        ),
        'marketplaceShipAllocationId',
        (
          select allocation.id::text
          from operations.marketplace_ship_allocations allocation
          join operations.marketplace_events marketplace_event
            on marketplace_event.id = allocation.event_id
          where marketplace_event.external_event_ref =
            'RECON-INSPECTION-SHIP-EVENT-001'
        ),
        'quantity',
        3,
        'sourceLineRef',
        'RECON-INSPECTION-RECEIPT-LINE-001'
      )
    ),
    'Return inspection comparison receipt fixture.',
    '{"test": true, "fixture": "inspection-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_inspection_results
    where kind = 'RECEIPT'
  ),
  'RECEIVED_PENDING_INSPECTION',
  'inspection comparison receipt stays stock-neutral pending inspection'
);

insert into return_inspection_results (kind, result)
select
  'INSPECTION',
  api.inspect_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-INSPECTION-INSPECT-001',
    'RECON-INSPECTION-RETURN-001',
    'RECON-INSPECTION-INSPECTION-001',
    '2026-07-26 12:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'receiptLineId',
        (
          select receipt_line.id::text
          from operations.return_receipt_lines receipt_line
          join operations.return_receipts receipt
            on receipt.id = receipt_line.receipt_id
          where receipt.receipt_ref =
            'RECON-INSPECTION-RECEIPT-001'
        ),
        'sellableQuantity',
        2,
        'damagedQuantity',
        1,
        'sourceLineRef',
        'RECON-INSPECTION-LINE-001'
      )
    ),
    'Return inspection comparison mixed result.',
    '{"test": true, "fixture": "inspection-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_inspection_results
    where kind = 'INSPECTION'
  ),
  'COMPLETED_MIXED',
  'inspection comparison fixture completes as mixed'
);

create temp table return_inspection_snapshots (
  stage text primary key,
  transaction_count bigint not null,
  ledger_count bigint not null,
  sellable_qty bigint not null,
  quarantine_qty bigint not null,
  damaged_qty bigint not null
) on commit drop;

insert into return_inspection_snapshots
select
  'POST_INSPECTION',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries),
  position.sellable_qty,
  position.quarantine_qty,
  position.damaged_qty
from inventory.stock_product_positions position
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

select is(
  (
    select count(*)
    from reconciliation.find_return_inspection_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'valid mixed inspection posts only the sellable inbound effect'
);

select is(
  (
    select count(*)
    from reconciliation.find_return_inspection_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'return inspection comparison is deterministic on a clean state'
);

alter table operations.return_inspection_allocations
  disable trigger trg_return_inspection_allocations_immutable;

update operations.return_inspection_allocations allocation
set quantity_allocated = allocation.quantity_allocated - 1
from operations.return_inspections inspection
where inspection.organization_id = allocation.organization_id
  and inspection.id = allocation.inspection_id
  and inspection.inspection_ref =
    'RECON-INSPECTION-INSPECTION-001'
  and allocation.destination_bucket_code = 'SELLABLE';

alter table operations.return_inspection_allocations
  enable trigger trg_return_inspection_allocations_immutable;

select is(
  (
    select count(*)
    from reconciliation.find_return_inspection_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where inspection_ref =
      'RECON-INSPECTION-INSPECTION-001'
  ),
  1::bigint,
  'corrupted inspection allocation creates one mismatch'
);

select is(
  (
    select
      event_line_quantity::text
        || ':'
        || allocation_quantity::text
        || ':'
        || source_quarantine_quantity::text
        || ':'
        || destination_quantity::text
        || ':'
        || net_quantity::text
        || ':'
        || event_line_count::text
        || ':'
        || allocation_count::text
        || ':'
        || source_ledger_count::text
        || ':'
        || destination_ledger_count::text
        || ':'
        || invalid_header_count::text
        || ':'
        || line_total_mismatch_count::text
        || ':'
        || invalid_allocation_count::text
        || ':'
        || invalid_source_ledger_count::text
        || ':'
        || invalid_destination_ledger_count::text
        || ':'
        || orphan_ledger_count::text
    from reconciliation.find_return_inspection_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where inspection_ref =
      'RECON-INSPECTION-INSPECTION-001'
  ),
  '3:2:0:2:2:1:2:0:1:0:1:0:0:1:0',
  'inspection mismatch reports allocation and sellable inbound diagnostics'
);

select is(
  (
    select issue_code
    from reconciliation.find_return_inspection_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where inspection_ref =
      'RECON-INSPECTION-INSPECTION-001'
  ),
  'RETURN_INSPECTION_ALLOCATION_LINK_INVALID',
  'inspection mismatch uses the allocation link issue code'
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
    from return_inspection_snapshots snapshot
    where snapshot.stage = 'POST_INSPECTION'
  ),
  'inspection comparison creates no transaction or ledger effect'
);

select is(
  (
    select
      position.sellable_qty::text
        || ':'
        || position.quarantine_qty::text
        || ':'
        || position.damaged_qty::text
    from inventory.stock_product_positions position
    where position.organization_id =
        '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select
      snapshot.sellable_qty::text
        || ':'
        || snapshot.quarantine_qty::text
        || ':'
        || snapshot.damaged_qty::text
    from return_inspection_snapshots snapshot
    where snapshot.stage = 'POST_INSPECTION'
  ),
  'inspection comparison does not mutate stock projections'
);

alter table operations.return_inspection_allocations
  disable trigger trg_return_inspection_allocations_immutable;

update operations.return_inspection_allocations allocation
set quantity_allocated = allocation.quantity_allocated + 1
from operations.return_inspections inspection
where inspection.organization_id = allocation.organization_id
  and inspection.id = allocation.inspection_id
  and inspection.inspection_ref =
    'RECON-INSPECTION-INSPECTION-001'
  and allocation.destination_bucket_code = 'SELLABLE';

alter table operations.return_inspection_allocations
  enable trigger trg_return_inspection_allocations_immutable;

select is(
  (
    select count(*)
    from reconciliation.find_return_inspection_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where inspection_ref =
      'RECON-INSPECTION-INSPECTION-001'
  ),
  0::bigint,
  'restored inspection allocation clears the mismatch'
);

select * from finish();

rollback;