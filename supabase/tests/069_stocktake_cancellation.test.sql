create extension if not exists pgtap with schema extensions;

begin;

select plan(38);

-- 1-7: public contract and least privilege.
select function_returns(
  'api',
  'cancel_stocktake',
  array['uuid', 'text', 'uuid', 'text', 'boolean', 'jsonb']::text[],
  'jsonb',
  'trusted stocktake cancellation command exists'
);
select has_table(
  'operations',
  'stocktake_cancellations',
  'stocktake cancellation has an append-only audit record'
);
select has_view(
  'api',
  'stocktake_cancellations',
  'stocktake cancellation audit has an organization-scoped read model'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.cancel_stocktake(uuid,text,uuid,text,boolean,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may execute cancel'
);
select ok(
  has_function_privilege(
    'service_role',
    'api.cancel_stocktake(uuid,text,uuid,text,boolean,jsonb)',
    'EXECUTE'
  ),
  'service role may execute cancel'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.cancel_stocktake(uuid,text,uuid,text,boolean,jsonb)',
    'EXECUTE'
  ),
  'anonymous callers cannot execute cancel'
);
select has_trigger(
  'operations',
  'stocktake_cancellations',
  'trg_stocktake_cancellations_immutable',
  'cancellation audit rows are immutable'
);
select ok(
  position(
    'pg_advisory_xact_lock'
    in lower(
      pg_get_functiondef(
        'api.cancel_stocktake(uuid,text,uuid,text,boolean,jsonb)'::regprocedure
      )
    )
  ) > 0,
  'cancel serializes command and stocktake work with transaction advisory locks'
);
select ok(
  position(
    ':stocktake:'
    in lower(
      pg_get_functiondef(
        'api.cancel_stocktake(uuid,text,uuid,text,boolean,jsonb)'::regprocedure
      )
    )
  ) > 0,
  'cancel shares the stocktake identity lock convention with lifecycle commands'
);
select ok(
  position(
    'operations.stocktake_postings'
    in lower(
      pg_get_functiondef(
        'api.cancel_stocktake(uuid,text,uuid,text,boolean,jsonb)'::regprocedure
      )
    )
  ) > 0
  and position(
    'inventory.stock_transactions'
    in lower(
      pg_get_functiondef(
        'api.cancel_stocktake(uuid,text,uuid,text,boolean,jsonb)'::regprocedure
      )
    )
  ) > 0,
  'cancel rejects a session with any posting or stock transaction linkage'
);

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous
)
values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  '99000000-0000-4000-8000-000000000069'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.stocktake.cancel@glowlab.invalid',
  '2026-08-12 19:00:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-08-12 19:00:00+07'::timestamptz,
  '2026-08-12 19:00:00+07'::timestamptz,
  false,
  false
);

insert into app.user_profiles (
  user_id, organization_id, display_name, employee_code, role_code, is_active
)
values (
  '99000000-0000-4000-8000-000000000069'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Stocktake Cancel Admin',
  'PGTAP-STK-CANCEL',
  'ADMIN',
  true
);

insert into app.organizations (
  id, code, name, timezone, is_active, created_at, created_by
)
values (
  '00000000-0000-4000-8000-000000000069'::uuid,
  'PGTAP_STOCKTAKE_CANCEL_OTHER',
  'pgTAP Stocktake Cancel Other',
  'Asia/Jakarta',
  true,
  '2026-08-12 19:00:00+07'::timestamptz,
  null
);

create temp table cancellation_results (
  kind text primary key,
  result jsonb not null
) on commit drop;
grant select, insert on cancellation_results to authenticated;

create temp table cancellation_baseline (
  transaction_count bigint,
  ledger_count bigint,
  batch_quantities jsonb,
  product_quantities jsonb,
  reservations jsonb,
  allocations jsonb
) on commit drop;
grant select on cancellation_baseline to authenticated;

select set_config(
  'request.jwt.claim.sub',
  '99000000-0000-4000-8000-000000000069',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99000000-0000-4000-8000-000000000069',
    'role', 'authenticated',
    'email', 'pgtap.stocktake.cancel@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

insert into cancellation_results (kind, result)
select
  status_code,
  api.create_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-CANCEL-CREATE-' || status_code,
    'Cancel contract ' || status_code,
    'CYCLE',
    'CONTINUOUS',
    'BLIND',
    jsonb_build_object(
      'mode', 'BATCHES',
      'batchIds', jsonb_build_array(
        '40000000-0000-4000-8000-000000000001'
      ),
      'bucketCodes', jsonb_build_array('SELLABLE'),
      'includeZeroSystemBalance', false,
      'includeInactiveWithBalance', false,
      'includeBlockedBatches', false,
      'includeExpiredBatches', true
    ),
    null,
    'Cancellation contract fixture.',
    jsonb_build_object('fixture', 'stocktake-cancellation')
  )
from unnest(array['DRAFT', 'READY', 'COUNTING', 'REVIEW']) status_code;

insert into cancellation_results (kind, result)
values (
  'EXCEPTION',
  api.create_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-CANCEL-CREATE-EXCEPTION',
    'Cancel contract EXCEPTION',
    'CYCLE',
    'CONTINUOUS',
    'BLIND',
    jsonb_build_object(
      'mode', 'BATCHES',
      'batchIds', jsonb_build_array(
        '40000000-0000-4000-8000-000000000001'
      ),
      'bucketCodes', jsonb_build_array('SELLABLE'),
      'includeZeroSystemBalance', false,
      'includeInactiveWithBalance', false,
      'includeBlockedBatches', false,
      'includeExpiredBatches', true
    ),
    null,
    'Cancellation forbidden fixture.',
    '{}'::jsonb
  )
);

reset role;

update operations.stocktakes stocktake
set status_code = result.kind
from cancellation_results result
where result.kind in ('READY', 'COUNTING', 'REVIEW', 'EXCEPTION')
  and stocktake.id = (result.result ->> 'stocktakeId')::uuid;

insert into operations.stocktake_lines (
  id, organization_id, stocktake_id, line_no, product_id, batch_id,
  bucket_code, product_sku_snapshot, product_name_snapshot,
  batch_code_snapshot, expiry_date_snapshot, system_qty_at_snapshot
)
select
  '69000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  (result ->> 'stocktakeId')::uuid,
  1,
  '30000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'SELLABLE',
  'SERUM-001',
  'Serum Fixture',
  'BATCH-001',
  '2027-12-31'::date,
  10
from cancellation_results
where kind = 'COUNTING';

insert into operations.stocktake_snapshots (
  organization_id, stocktake_id, stocktake_line_id, product_id, batch_id,
  bucket_code, snapshot_ledger_seq, system_qty_at_snapshot,
  product_sku_snapshot, product_name_snapshot, batch_code_snapshot,
  expiry_date_snapshot
)
select
  '00000000-0000-4000-8000-000000000001'::uuid,
  (result ->> 'stocktakeId')::uuid,
  '69000000-0000-4000-8000-000000000001'::uuid,
  '30000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'SELLABLE',
  0,
  10,
  'SERUM-001',
  'Serum Fixture',
  'BATCH-001',
  '2027-12-31'::date
from cancellation_results
where kind = 'COUNTING';

insert into operations.stocktake_count_attempts (
  organization_id, stocktake_id, stocktake_line_id, attempt_no,
  physical_qty, counted_at, count_cutoff_ledger_seq,
  expected_qty_at_count, variance_qty, expected_formula_version,
  counted_by, count_method_code, zero_confirmed, note,
  idempotency_key, request_hash
)
select
  '00000000-0000-4000-8000-000000000001'::uuid,
  (result ->> 'stocktakeId')::uuid,
  '69000000-0000-4000-8000-000000000001'::uuid,
  1,
  10,
  '2026-08-12 19:05:00+07'::timestamptz,
  0,
  10,
  0,
  'stocktake-continuous-expected-v1',
  '99000000-0000-4000-8000-000000000069'::uuid,
  'MANUAL_ENTRY',
  false,
  'Preserve this attempt.',
  'PGTAP-STOCKTAKE-CANCEL-ATTEMPT',
  repeat('a', 64)
from cancellation_results
where kind = 'COUNTING';

insert into cancellation_baseline
select
  (select count(*) from inventory.stock_transactions
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select count(*) from inventory.stock_ledger_entries
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select jsonb_build_object(
     'count', count(*),
     'sellable', coalesce(sum(sellable_qty), 0),
     'quarantine', coalesce(sum(quarantine_qty), 0),
     'damaged', coalesce(sum(damaged_qty), 0),
     'version', coalesce(sum(version), 0)
   ) from inventory.stock_batch_balances
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select jsonb_build_object(
     'count', count(*),
     'sellable', coalesce(sum(sellable_qty), 0),
     'quarantine', coalesce(sum(quarantine_qty), 0),
     'damaged', coalesce(sum(damaged_qty), 0),
     'reserved', coalesce(sum(reserved_qty), 0),
     'version', coalesce(sum(version), 0)
   ) from inventory.stock_product_positions
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select jsonb_build_object(
     'count', count(*),
     'reserved', coalesce(sum(reserved_qty), 0),
     'consumed', coalesce(sum(consumed_qty), 0),
     'released', coalesce(sum(released_qty), 0)
   ) from inventory.stock_reservations
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select jsonb_build_object(
     'count', count(*),
     'allocated', coalesce(sum(quantity_allocated), 0)
   ) from operations.marketplace_ship_allocations
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid);

set local role authenticated;

-- 8-11: input, confirmation, and organization boundaries.
select throws_ok(
  format(
    'select api.cancel_stocktake(%L::uuid,%L,%L::uuid,%L,true,%L::jsonb)',
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-CANCEL-NO-REASON',
    (select result ->> 'stocktakeId' from cancellation_results where kind = 'DRAFT'),
    '',
    '{}'
  ),
  'P0001',
  'STOCKTAKE_CANCEL_REASON_REQUIRED',
  'reason is mandatory'
);
select throws_ok(
  format(
    'select api.cancel_stocktake(%L::uuid,%L,%L::uuid,%L,false,%L::jsonb)',
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-CANCEL-NO-CONFIRM',
    (select result ->> 'stocktakeId' from cancellation_results where kind = 'DRAFT'),
    'Gudang belum siap.',
    '{}'
  ),
  'P0001',
  'STOCKTAKE_CANCEL_CONFIRMATION_REQUIRED',
  'explicit confirmation is mandatory'
);
select throws_ok(
  format(
    'select api.cancel_stocktake(%L::uuid,%L,%L::uuid,%L,true,%L::jsonb)',
    '00000000-0000-4000-8000-000000000069',
    'PGTAP-CANCEL-CROSS-ORG',
    (select result ->> 'stocktakeId' from cancellation_results where kind = 'DRAFT'),
    'Cross organization must fail.',
    '{}'
  ),
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'authenticated Admin cannot cancel across organizations'
);
select throws_ok(
  format(
    'select api.cancel_stocktake(%L::uuid,%L,%L::uuid,%L,true,%L::jsonb)',
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-CANCEL-EXCEPTION',
    (select result ->> 'stocktakeId' from cancellation_results where kind = 'EXCEPTION'),
    'Forbidden terminal state.',
    '{}'
  ),
  'P0001',
  'STOCKTAKE_CANCEL_INVALID_STATE',
  'EXCEPTION cannot be cancelled'
);

insert into cancellation_results (kind, result)
select
  'CANCEL_' || source.kind,
  api.cancel_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-CANCEL-' || source.kind,
    (source.result ->> 'stocktakeId')::uuid,
    'Area gudang belum siap: ' || source.kind,
    true,
    jsonb_build_object('fixture', 'stocktake-cancellation', 'from', source.kind)
  )
from cancellation_results source
where source.kind in ('DRAFT', 'READY', 'COUNTING', 'REVIEW');

reset role;

-- 12-19: allowed transitions and append-only audit metadata.
select is(
  (select count(*) from cancellation_results
   where kind like 'CANCEL_%' and result ->> 'status' = 'CANCELLED'),
  4::bigint,
  'DRAFT, READY, COUNTING, and REVIEW all cancel successfully'
);
select results_eq(
  $$select result ->> 'statusBefore'
    from cancellation_results
    where kind like 'CANCEL_%'
    order by 1$$,
  $$values ('COUNTING'::text), ('DRAFT'::text), ('READY'::text), ('REVIEW'::text)$$,
  'responses preserve each status before cancellation'
);
select is(
  (select count(*) from operations.stocktakes
   where id in (
     select (result ->> 'stocktakeId')::uuid
     from cancellation_results
     where kind in ('DRAFT', 'READY', 'COUNTING', 'REVIEW')
   ) and status_code = 'CANCELLED'),
  4::bigint,
  'all allowed sessions become CANCELLED'
);
select is(
  (select count(*) from operations.stocktake_cancellations
   where stocktake_id in (
     select (result ->> 'stocktakeId')::uuid
     from cancellation_results
     where kind in ('DRAFT', 'READY', 'COUNTING', 'REVIEW')
   )),
  4::bigint,
  'one audit row is stored per cancelled session'
);
select is(
  (select count(*) from operations.stocktake_cancellations
   where cancelled_by = '99000000-0000-4000-8000-000000000069'::uuid),
  4::bigint,
  'audit rows record the authenticated Admin'
);
select is(
  (select count(*) from operations.stocktake_cancellations
   where process_name is null
     and btrim(reason) <> ''
     and stocktake_id in (
       select (result ->> 'stocktakeId')::uuid
       from cancellation_results
       where kind in ('DRAFT', 'READY', 'COUNTING', 'REVIEW')
     )),
  4::bigint,
  'Admin cancellation stores a nonblank reason without process actor'
);
select is(
  (select count(distinct idempotency_command_id)
   from operations.stocktake_cancellations
   where stocktake_id in (
     select (result ->> 'stocktakeId')::uuid
     from cancellation_results
     where kind in ('DRAFT', 'READY', 'COUNTING', 'REVIEW')
   )),
  4::bigint,
  'each cancellation links one unique idempotency command'
);
select ok(
  (
    select bool_and(
      status_before_code in ('DRAFT', 'READY', 'COUNTING', 'REVIEW')
      and status_after_code = 'CANCELLED'
      and jsonb_typeof(metadata) = 'object'
    )
    from operations.stocktake_cancellations
    where stocktake_id in (
      select (result ->> 'stocktakeId')::uuid
      from cancellation_results
      where kind in ('DRAFT', 'READY', 'COUNTING', 'REVIEW')
    )
  ),
  'audit metadata records a valid before/after transition'
);

set local role authenticated;

insert into cancellation_results (kind, result)
select
  'REPLAY',
  api.cancel_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-CANCEL-DRAFT',
    (source.result ->> 'stocktakeId')::uuid,
    'Area gudang belum siap: DRAFT',
    true,
    jsonb_build_object('fixture', 'stocktake-cancellation', 'from', 'DRAFT')
  )
from cancellation_results source
where source.kind = 'DRAFT';

reset role;

-- 20-23: deterministic replay and terminal behavior.
select is(
  (select result from cancellation_results where kind = 'REPLAY'),
  (select result from cancellation_results where kind = 'CANCEL_DRAFT'),
  'identical duplicate returns the exact stored response'
);
select is(
  (select count(*) from operations.stocktake_cancellations
   where stocktake_id in (
     select (result ->> 'stocktakeId')::uuid
     from cancellation_results
     where kind in ('DRAFT', 'READY', 'COUNTING', 'REVIEW')
   )),
  4::bigint,
  'identical duplicate does not create a second audit effect'
);

set local role authenticated;
select throws_ok(
  format(
    'select api.cancel_stocktake(%L::uuid,%L,%L::uuid,%L,true,%L::jsonb)',
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-STOCKTAKE-CANCEL-DRAFT',
    (select result ->> 'stocktakeId' from cancellation_results where kind = 'DRAFT'),
    'Changed reason.',
    '{"fixture":"stocktake-cancellation","from":"DRAFT"}'
  ),
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'same idempotency key with changed payload is rejected'
);
select throws_ok(
  format(
    'select api.cancel_stocktake(%L::uuid,%L,%L::uuid,%L,true,%L::jsonb)',
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-STOCKTAKE-CANCEL-DRAFT-SECOND',
    (select result ->> 'stocktakeId' from cancellation_results where kind = 'DRAFT'),
    'Second cancellation.',
    '{}'
  ),
  'P0001',
  'STOCKTAKE_CANCEL_INVALID_STATE',
  'already CANCELLED is terminal for a new command'
);
reset role;

-- 24-29: cancellation is stock-neutral across all stock-bearing models.
select is(
  (select count(*) from inventory.stock_transactions
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select transaction_count from cancellation_baseline),
  'cancellation creates zero stock transactions'
);
select is(
  (select count(*) from inventory.stock_ledger_entries
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select ledger_count from cancellation_baseline),
  'cancellation creates zero ledger movements'
);
select is(
  (select jsonb_build_object(
     'count', count(*), 'sellable', coalesce(sum(sellable_qty), 0),
     'quarantine', coalesce(sum(quarantine_qty), 0),
     'damaged', coalesce(sum(damaged_qty), 0),
     'version', coalesce(sum(version), 0)
   ) from inventory.stock_batch_balances
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select batch_quantities from cancellation_baseline),
  'batch quantities and versions are unchanged'
);
select is(
  (select jsonb_build_object(
     'count', count(*), 'sellable', coalesce(sum(sellable_qty), 0),
     'quarantine', coalesce(sum(quarantine_qty), 0),
     'damaged', coalesce(sum(damaged_qty), 0),
     'reserved', coalesce(sum(reserved_qty), 0),
     'version', coalesce(sum(version), 0)
   ) from inventory.stock_product_positions
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select product_quantities from cancellation_baseline),
  'product projections and physical quantities are unchanged'
);
select is(
  (select jsonb_build_object(
     'count', count(*), 'reserved', coalesce(sum(reserved_qty), 0),
     'consumed', coalesce(sum(consumed_qty), 0),
     'released', coalesce(sum(released_qty), 0)
   ) from inventory.stock_reservations
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select reservations from cancellation_baseline),
  'reservations are unchanged'
);
select is(
  (select jsonb_build_object(
     'count', count(*), 'allocated', coalesce(sum(quantity_allocated), 0)
   ) from operations.marketplace_ship_allocations
   where organization_id = '00000000-0000-4000-8000-000000000001'::uuid),
  (select allocations from cancellation_baseline),
  'marketplace shipment allocations are unchanged'
);

-- 30-32: counting evidence is preserved.
select is(
  (select count(*) from operations.stocktake_lines
   where stocktake_id = (
     select (result ->> 'stocktakeId')::uuid
     from cancellation_results where kind = 'COUNTING'
   )),
  1::bigint,
  'stocktake line remains after cancellation'
);
select is(
  (select count(*) from operations.stocktake_snapshots
   where stocktake_id = (
     select (result ->> 'stocktakeId')::uuid
     from cancellation_results where kind = 'COUNTING'
   )),
  1::bigint,
  'stocktake snapshot remains after cancellation'
);
select is(
  (select count(*) from operations.stocktake_count_attempts
   where stocktake_id = (
     select (result ->> 'stocktakeId')::uuid
     from cancellation_results where kind = 'COUNTING'
   )),
  1::bigint,
  'count attempts remain after cancellation'
);

-- 33-35: audit immutability, RLS isolation, and next-command rejection.
select throws_ok(
  $$update operations.stocktake_cancellations set reason = 'Changed'$$,
  'P0001',
  'IMMUTABLE_LEDGER_RECORD',
  'cancellation audit rows cannot be updated'
);

set local role authenticated;
select is(
  (select count(*) from api.stocktake_cancellations
   where organization_id = '00000000-0000-4000-8000-000000000069'::uuid),
  0::bigint,
  'read model does not expose another organization'
);
select throws_ok(
  format(
    'select api.prepare_stocktake(%L::uuid,%L,%L::uuid,%L::jsonb)',
    '00000000-0000-4000-8000-000000000001',
    'PGTAP-CANCELLED-NEXT-COMMAND',
    (select result ->> 'stocktakeId' from cancellation_results where kind = 'DRAFT'),
    '{}'
  ),
  'P0001',
  'STOCKTAKE_INVALID_STATE',
  'cancelled session rejects the next lifecycle command'
);
reset role;

select * from finish();
rollback;
