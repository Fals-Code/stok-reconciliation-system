begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

select has_function(
  'reconciliation'::name,
  'find_marketplace_allocation_mismatches'::name,
  array['uuid']::text[]
);

select ok(
  not has_function_privilege(
    'authenticated',
    'reconciliation.find_marketplace_allocation_mismatches(uuid)',
    'EXECUTE'
  ),
  'authenticated users cannot execute the internal comparison directly'
);

select ok(
  not has_function_privilege(
    'anon',
    'reconciliation.find_marketplace_allocation_mismatches(uuid)',
    'EXECUTE'
  ),
  'anonymous users cannot execute the internal comparison'
);

select ok(
  not has_function_privilege(
    'service_role',
    'reconciliation.find_marketplace_allocation_mismatches(uuid)',
    'EXECUTE'
  ),
  'service role cannot bypass the public reconciliation command'
);

select is(
  (
    select count(*)
    from reconciliation.find_marketplace_allocation_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'clean seed has no marketplace allocation mismatch'
);

create temp table marketplace_comparison_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

insert into marketplace_comparison_results (
  kind,
  result
)
select
  'RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-MKT-COMPARE-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'RECON-MKT-COMPARE-RESERVE-EVENT-001',
    'RECON-MKT-COMPARE-ORDER-001',
    '2026-07-22 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        8,
        'sourceLineRef',
        'RECON-MKT-COMPARE-ITEM-001'
      )
    ),
    'Marketplace allocation comparison reserve fixture.',
    '{"test": true, "fixture": "marketplace-allocation-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from marketplace_comparison_results
    where kind = 'RESERVE'
  ),
  'APPLIED',
  'marketplace reserve fixture is applied'
);

insert into marketplace_comparison_results (
  kind,
  result
)
select
  'SHIP',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-MKT-COMPARE-SHIP-001',
    'SHOPEE',
    'SHIP',
    'RECON-MKT-COMPARE-SHIP-EVENT-001',
    'RECON-MKT-COMPARE-ORDER-001',
    '2026-07-22 09:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        8,
        'sourceLineRef',
        'RECON-MKT-COMPARE-ITEM-001'
      )
    ),
    'Marketplace allocation comparison shipment fixture.',
    '{"test": true, "fixture": "marketplace-allocation-comparison"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from marketplace_comparison_results
    where kind = 'SHIP'
  ),
  'APPLIED',
  'marketplace shipment fixture is applied'
);

select is(
  (
    select result ->> 'allocationCount'
    from marketplace_comparison_results
    where kind = 'SHIP'
  ),
  '2',
  'shipment fixture creates two FEFO allocations'
);

select is(
  (
    select sum(event_line.quantity)
    from operations.marketplace_event_lines event_line
    join operations.marketplace_events marketplace_event
      on marketplace_event.organization_id =
          event_line.organization_id
     and marketplace_event.id = event_line.event_id
    where marketplace_event.external_event_ref =
      'RECON-MKT-COMPARE-SHIP-EVENT-001'
  ),
  8::numeric,
  'shipment fixture records eight event-line units'
);

select is(
  (
    select count(*)
    from reconciliation.find_marketplace_allocation_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'valid marketplace shipment agrees with allocations and ledger'
);

create temp table marketplace_comparison_snapshots (
  transaction_count bigint not null,
  ledger_count bigint not null
) on commit drop;

insert into marketplace_comparison_snapshots (
  transaction_count,
  ledger_count
)
select
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
    'RECON-MKT-COMPARE-SHIP-EVENT-001'
  and allocation.allocation_no = 1;

alter table operations.marketplace_ship_allocations
  enable trigger trg_marketplace_ship_allocations_immutable;

select is(
  (
    select count(*)
    from reconciliation.find_marketplace_allocation_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  1::bigint,
  'corrupted marketplace allocation creates one mismatch'
);

select is(
  (
    select
      event_line_quantity::text
      || ':'
      || allocation_quantity::text
      || ':'
      || ledger_outbound_quantity::text
      || ':'
      || event_line_count::text
      || ':'
      || allocation_count::text
      || ':'
      || ledger_entry_count::text
      || ':'
      || invalid_allocation_count::text
      || ':'
      || invalid_ledger_count::text
      || ':'
      || orphan_ledger_count::text
      || ':'
      || issue_code
    from reconciliation.find_marketplace_allocation_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  '8:7:8:1:2:2:1:0:0:MARKETPLACE_ALLOCATION_LINK_INVALID',
  'mismatch explains event, allocation, ledger, and traceability totals'
);

select is(
  (select count(*) from inventory.stock_transactions),
  (
    select transaction_count
    from marketplace_comparison_snapshots
  ),
  'marketplace comparison creates no stock transaction'
);

select is(
  (select count(*) from inventory.stock_ledger_entries),
  (
    select ledger_count
    from marketplace_comparison_snapshots
  ),
  'marketplace comparison leaves the ledger unchanged'
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
    'RECON-MKT-COMPARE-SHIP-EVENT-001'
  and allocation.allocation_no = 1;

alter table operations.marketplace_ship_allocations
  enable trigger trg_marketplace_ship_allocations_immutable;

select is(
  (
    select count(*)
    from reconciliation.find_marketplace_allocation_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'restored marketplace allocation clears the mismatch'
);

select is(
  (
    select sum(allocation.quantity_allocated)
    from operations.marketplace_ship_allocations allocation
    join operations.marketplace_events marketplace_event
      on marketplace_event.organization_id =
          allocation.organization_id
     and marketplace_event.id = allocation.event_id
    where marketplace_event.external_event_ref =
      'RECON-MKT-COMPARE-SHIP-EVENT-001'
  ),
  8::numeric,
  'restored allocation total remains equal to shipment quantity'
);

select * from finish();

rollback;