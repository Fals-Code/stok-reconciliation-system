begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

select has_function(
  'reconciliation'::name,
  'find_reservation_consistency_mismatches'::name,
  array['uuid']::text[]
);

select ok(
  not has_function_privilege(
    'authenticated',
    'reconciliation.find_reservation_consistency_mismatches(uuid)',
    'EXECUTE'
  ),
  'authenticated users cannot execute the internal comparison directly'
);

select ok(
  not has_function_privilege(
    'anon',
    'reconciliation.find_reservation_consistency_mismatches(uuid)',
    'EXECUTE'
  ),
  'anonymous users cannot execute the internal comparison'
);

select ok(
  not has_function_privilege(
    'service_role',
    'reconciliation.find_reservation_consistency_mismatches(uuid)',
    'EXECUTE'
  ),
  'service role cannot bypass the public reconciliation command'
);

select is(
  (
    select count(*)
    from reconciliation.find_reservation_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'clean seed has no reservation consistency mismatch'
);

create temp table reservation_comparison_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

create temp table reservation_comparison_snapshots (
  stage text primary key,
  transaction_count bigint not null,
  ledger_count bigint not null
) on commit drop;

insert into reservation_comparison_snapshots (
  stage,
  transaction_count,
  ledger_count
)
select
  'BEFORE',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries);

insert into reservation_comparison_results (
  kind,
  result
)
select
  'RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-RECON-RESERVATION-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'RECON-RESERVATION-EVENT-001',
    'RECON-RESERVATION-ORDER-001',
    '2026-07-20 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        3,
        'sourceLineRef',
        'RECON-RESERVATION-ITEM-001'
      )
    ),
    'Reservation consistency fixture.',
    '{"test": true, "fixture": "reservation-consistency"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from reservation_comparison_results
    where kind = 'RESERVE'
  ),
  'APPLIED',
  'reservation fixture is applied'
);

select is(
  (
    select count(*)
    from inventory.stock_reservations reservation
    where reservation.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and reservation.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
      and reservation.reserved_qty = 3
  ),
  1::bigint,
  'fixture creates one reservation'
);

select is(
  (
    select open_qty
    from api.marketplace_reservations
    where external_order_ref =
      'RECON-RESERVATION-ORDER-001'
  ),
  3::bigint,
  'reservation exposes three open units'
);

select is(
  (select count(*) from inventory.stock_ledger_entries),
  (
    select ledger_count
    from reservation_comparison_snapshots
    where stage = 'BEFORE'
  ),
  'reservation creates no physical ledger movement'
);

select is(
  (
    select count(*)
    from reconciliation.find_reservation_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'valid reservation agrees with product projection'
);

update inventory.stock_product_positions position
set
  reserved_qty = position.reserved_qty + 1,
  version = position.version + 1
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

select is(
  (
    select count(*)
    from reconciliation.find_reservation_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  1::bigint,
  'reserved projection drift creates one mismatch'
);

select is(
  (
    select
      expected_reserved_qty::text
      || ':'
      || actual_reserved_qty::text
      || ':'
      || sellable_qty::text
      || ':'
      || expected_available_qty::text
      || ':'
      || actual_available_qty::text
      || ':'
      || reservation_difference::text
      || ':'
      || issue_code
    from reconciliation.find_reservation_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
    where product_id =
      '30000000-0000-4000-8000-000000000001'::uuid
  ),
  '3:4:25:22:21:1:RESERVATION_PROJECTION_MISMATCH',
  'mismatch explains reserved and available quantities'
);

update inventory.stock_product_positions position
set
  reserved_qty = position.reserved_qty - 1,
  version = position.version + 1
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

select is(
  (
    select count(*)
    from reconciliation.find_reservation_consistency_mismatches(
      '00000000-0000-4000-8000-000000000001'::uuid
    )
  ),
  0::bigint,
  'restored projection clears the mismatch'
);

select is(
  (select count(*) from inventory.stock_transactions),
  (
    select transaction_count
    from reservation_comparison_snapshots
    where stage = 'BEFORE'
  ),
  'reservation comparison creates no stock transaction'
);

select is(
  (select count(*) from inventory.stock_ledger_entries),
  (
    select ledger_count
    from reservation_comparison_snapshots
    where stage = 'BEFORE'
  ),
  'reservation comparison leaves the ledger unchanged'
);

select * from finish();

rollback;