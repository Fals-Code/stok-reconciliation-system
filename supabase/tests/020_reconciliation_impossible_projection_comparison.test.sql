begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

select has_function(
  'reconciliation'::name,
  'find_impossible_projection_states'::name,
  array['uuid', 'bigint']::text[]
);

select ok(
  not has_function_privilege(
    'authenticated',
    'reconciliation.find_impossible_projection_states(uuid,bigint)',
    'EXECUTE'
  ),
  'authenticated users cannot execute the internal impossible-state comparison'
);

select ok(
  not has_function_privilege(
    'anon',
    'reconciliation.find_impossible_projection_states(uuid,bigint)',
    'EXECUTE'
  ),
  'anonymous users cannot execute the internal impossible-state comparison'
);

select ok(
  not has_function_privilege(
    'service_role',
    'reconciliation.find_impossible_projection_states(uuid,bigint)',
    'EXECUTE'
  ),
  'service role cannot bypass the public reconciliation command'
);

create temp table impossible_projection_baseline (
  id boolean primary key default true,
  ledger_seq_to bigint not null,
  ledger_count bigint not null,
  batch_count bigint not null,
  product_count bigint not null,
  batch_last_ledger_seq bigint not null,
  product_last_ledger_seq bigint not null,
  batch_quarantine_qty bigint not null,
  product_damaged_qty bigint not null,
  constraint impossible_projection_baseline_singleton
    check (id)
) on commit drop;

insert into impossible_projection_baseline (
  ledger_seq_to,
  ledger_count,
  batch_count,
  product_count,
  batch_last_ledger_seq,
  product_last_ledger_seq,
  batch_quarantine_qty,
  product_damaged_qty
)
select
  (
    select coalesce(max(entry.ledger_seq), 0)
    from inventory.stock_ledger_entries entry
    where entry.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (select count(*) from inventory.stock_ledger_entries),
  (select count(*) from inventory.stock_batch_balances),
  (select count(*) from inventory.stock_product_positions),
  (
    select balance.last_ledger_seq
    from inventory.stock_batch_balances balance
    where balance.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and balance.batch_id =
        '40000000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select position.last_ledger_seq
    from inventory.stock_product_positions position
    where position.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select balance.quarantine_qty
    from inventory.stock_batch_balances balance
    where balance.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and balance.batch_id =
        '40000000-0000-4000-8000-000000000003'::uuid
  ),
  (
    select position.damaged_qty
    from inventory.stock_product_positions position
    where position.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and position.product_id =
        '30000000-0000-4000-8000-000000000002'::uuid
  );

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    )
  ),
  0::bigint,
  'clean seed has no impossible projection state'
);

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      (
        select baseline.ledger_seq_to
        from impossible_projection_baseline baseline
      )
    )
  ),
  0::bigint,
  'clean seed is valid at the explicit ledger boundary'
);

update inventory.stock_batch_balances balance
set
  last_ledger_seq = 0,
  version = balance.version + 1
where balance.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and balance.batch_id =
    '40000000-0000-4000-8000-000000000002'::uuid;

update inventory.stock_product_positions position
set
  last_ledger_seq = 0,
  version = position.version + 1
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    )
  ),
  2::bigint,
  'stale batch and product boundaries create two violations'
);

select is(
  (
    select string_agg(
      state.issue_code,
      ':'
      order by state.issue_code
    )
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    ) state
  ),
  'BATCH_LEDGER_BOUNDARY_MISMATCH:PRODUCT_LEDGER_BOUNDARY_MISMATCH',
  'boundary violations use distinct batch and product issue codes'
);

select is(
  (
    select
      state.expected_last_ledger_seq::text
        || ':'
        || state.actual_last_ledger_seq::text
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    ) state
    where state.issue_code =
      'BATCH_LEDGER_BOUNDARY_MISMATCH'
      and state.batch_id =
        '40000000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select
      baseline.batch_last_ledger_seq::text
        || ':0'
    from impossible_projection_baseline baseline
  ),
  'batch boundary mismatch explains expected and actual ledger sequence'
);

select is(
  (
    select
      state.expected_last_ledger_seq::text
        || ':'
        || state.actual_last_ledger_seq::text
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    ) state
    where state.issue_code =
      'PRODUCT_LEDGER_BOUNDARY_MISMATCH'
      and state.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select
      baseline.product_last_ledger_seq::text
        || ':0'
    from impossible_projection_baseline baseline
  ),
  'product boundary mismatch explains expected and actual ledger sequence'
);

select is(
  (
    select
      (select count(*) from inventory.stock_ledger_entries)::text
        || ':'
        || (select count(*) from inventory.stock_batch_balances)::text
        || ':'
        || (select count(*) from inventory.stock_product_positions)::text
  ),
  (
    select
      baseline.ledger_count::text
        || ':'
        || baseline.batch_count::text
        || ':'
        || baseline.product_count::text
    from impossible_projection_baseline baseline
  ),
  'boundary comparison does not create or delete stock rows'
);

update inventory.stock_batch_balances balance
set
  last_ledger_seq = baseline.batch_last_ledger_seq,
  version = balance.version + 1
from impossible_projection_baseline baseline
where balance.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and balance.batch_id =
    '40000000-0000-4000-8000-000000000002'::uuid;

update inventory.stock_product_positions position
set
  last_ledger_seq = baseline.product_last_ledger_seq,
  version = position.version + 1
from impossible_projection_baseline baseline
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000001'::uuid;

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    )
  ),
  0::bigint,
  'restoring projection watermarks clears boundary violations'
);

insert into inventory.idempotency_commands (
  id,
  organization_id,
  scope,
  key,
  request_hash,
  status_code,
  started_at,
  completed_at,
  response_snapshot
)
values (
  '97000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'RECONCILIATION_CORRUPTION_TEST',
  'PGTAP-IMPOSSIBLE-PROJECTION-NEGATIVE-LEDGER-001',
  repeat('c', 64),
  'STARTED',
  '2026-07-30 10:00:00+07'::timestamptz,
  null,
  '{}'::jsonb
);

insert into inventory.stock_transactions (
  id,
  organization_id,
  transaction_no,
  transaction_type_code,
  reason_id,
  reason_code_snapshot,
  channel_id,
  channel_code_snapshot,
  source_type_code,
  source_id,
  source_ref_snapshot,
  occurred_at,
  recorded_at,
  effective_local_date,
  actor_user_id,
  process_name,
  created_by_role_code,
  correlation_id,
  idempotency_command_id,
  reversal_of_transaction_id,
  note,
  metadata,
  schema_version
)
select
  '98000000-0000-4000-8000-000000000001'::uuid,
  stock_transaction.organization_id,
  'REC-IMPOSSIBLE-NEGATIVE-0001',
  stock_transaction.transaction_type_code,
  stock_transaction.reason_id,
  stock_transaction.reason_code_snapshot,
  stock_transaction.channel_id,
  stock_transaction.channel_code_snapshot,
  stock_transaction.source_type_code,
  gen_random_uuid(),
  'PGTAP-IMPOSSIBLE-NEGATIVE-LEDGER-001',
  '2026-07-30 10:00:00+07'::timestamptz,
  '2026-07-30 10:00:00+07'::timestamptz,
  '2026-07-30'::date,
  null,
  'pgTAP impossible projection corruption fixture',
  'SYSTEM_PROCESS',
  gen_random_uuid(),
  '97000000-0000-4000-8000-000000000001'::uuid,
  null,
  'Deliberate negative-ledger corruption fixture.',
  '{"test": true, "corruption": "negative-ledger"}'::jsonb,
  stock_transaction.schema_version
from inventory.stock_transactions stock_transaction
where stock_transaction.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
order by stock_transaction.recorded_at, stock_transaction.id
limit 1;

insert into inventory.stock_ledger_entries (
  organization_id,
  transaction_id,
  line_no,
  product_id,
  batch_id,
  product_sku_snapshot,
  batch_code_snapshot,
  expiry_date_snapshot,
  bucket_code,
  quantity_delta,
  entry_role_code,
  pair_no,
  source_line_ref,
  occurred_at,
  recorded_at,
  created_at
)
select
  '00000000-0000-4000-8000-000000000001'::uuid,
  '98000000-0000-4000-8000-000000000001'::uuid,
  1,
  product.id,
  batch.id,
  product.sku,
  batch.batch_code,
  batch.expiry_date,
  'SELLABLE',
  -(
    coalesce(
      (
        select sum(entry.quantity_delta)
        from inventory.stock_ledger_entries entry
        where entry.organization_id =
          '00000000-0000-4000-8000-000000000001'::uuid
          and entry.product_id = product.id
          and entry.batch_id = batch.id
          and entry.bucket_code = 'SELLABLE'
      ),
      0
    ) + 1
  ),
  'ADJUSTMENT',
  null,
  'PGTAP-IMPOSSIBLE-NEGATIVE-LEDGER-001',
  '2026-07-30 10:00:00+07'::timestamptz,
  '2026-07-30 10:00:00+07'::timestamptz,
  '2026-07-30 10:00:00+07'::timestamptz
from catalog.products product
join catalog.product_batches batch
  on batch.organization_id = product.organization_id
 and batch.product_id = product.id
where product.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and product.id =
    '30000000-0000-4000-8000-000000000003'::uuid
  and batch.id =
    '40000000-0000-4000-8000-000000000004'::uuid;

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      (
        select baseline.ledger_seq_to
        from impossible_projection_baseline baseline
      )
    )
  ),
  0::bigint,
  'a captured ledger boundary excludes later corruption'
);

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    )
  ),
  3::bigint,
  'negative ledger corruption creates one negative and two boundary violations'
);

select is(
  (
    select string_agg(
      state.issue_code,
      ':'
      order by state.issue_code
    )
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    ) state
  ),
  'BATCH_LEDGER_BOUNDARY_MISMATCH:NEGATIVE_LEDGER_BUCKET:PRODUCT_LEDGER_BOUNDARY_MISMATCH',
  'negative ledger corruption is classified separately from stale boundaries'
);

select is(
  (
    select
      state.expected_quantity::text
        || ':'
        || state.actual_quantity::text
        || ':'
        || state.bucket_code
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    ) state
    where state.issue_code = 'NEGATIVE_LEDGER_BUCKET'
      and state.product_id =
        '30000000-0000-4000-8000-000000000003'::uuid
      and state.batch_id =
        '40000000-0000-4000-8000-000000000004'::uuid
  ),
  '0:-1:SELLABLE',
  'negative ledger violation explains the impossible bucket quantity'
);

select ok(
  (
    select bool_and(
      state.expected_last_ledger_seq
        > state.actual_last_ledger_seq
    )
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    ) state
    where state.issue_code in (
      'BATCH_LEDGER_BOUNDARY_MISMATCH',
      'PRODUCT_LEDGER_BOUNDARY_MISMATCH'
    )
      and state.product_id =
        '30000000-0000-4000-8000-000000000003'::uuid
  ),
  'negative ledger fixture also exposes stale projection watermarks'
);

select ok(
  (
    select
      balance.sellable_qty >= 0
    from inventory.stock_batch_balances balance
    where balance.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and balance.batch_id =
        '40000000-0000-4000-8000-000000000004'::uuid
  ),
  'negative ledger is distinguished from a nonnegative batch projection'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries
  ),
  (
    select baseline.ledger_count + 1
    from impossible_projection_baseline baseline
  ),
  'comparison does not add another ledger entry'
);

alter table inventory.stock_ledger_entries
  disable trigger trg_stock_ledger_entries_immutable;

delete from inventory.stock_ledger_entries ledger_entry
where ledger_entry.transaction_id =
  '98000000-0000-4000-8000-000000000001'::uuid;

alter table inventory.stock_ledger_entries
  enable trigger trg_stock_ledger_entries_immutable;

alter table inventory.stock_transactions
  disable trigger trg_stock_transactions_immutable;

delete from inventory.stock_transactions stock_transaction
where stock_transaction.id =
  '98000000-0000-4000-8000-000000000001'::uuid;

alter table inventory.stock_transactions
  enable trigger trg_stock_transactions_immutable;

delete from inventory.idempotency_commands command
where command.id =
  '97000000-0000-4000-8000-000000000001'::uuid;

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    )
  ),
  0::bigint,
  'removing the deliberate ledger corruption restores a clean state'
);

alter table inventory.stock_batch_balances
  drop constraint ck_stock_batch_balances_quarantine_nonnegative;

update inventory.stock_batch_balances balance
set
  quarantine_qty = -1,
  version = balance.version + 1
where balance.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and balance.batch_id =
    '40000000-0000-4000-8000-000000000003'::uuid;

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    )
  ),
  1::bigint,
  'negative batch projection creates one impossible-state violation'
);

select is(
  (
    select
      state.issue_code
        || ':'
        || state.entity_type_code
        || ':'
        || state.bucket_code
        || ':'
        || state.actual_quantity::text
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    ) state
  ),
  'NEGATIVE_BATCH_PROJECTION_BUCKET:BATCH_PROJECTION_BUCKET:QUARANTINE:-1',
  'negative batch projection evidence identifies its layer and bucket'
);

update inventory.stock_batch_balances balance
set
  quarantine_qty = baseline.batch_quarantine_qty,
  version = balance.version + 1
from impossible_projection_baseline baseline
where balance.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and balance.batch_id =
    '40000000-0000-4000-8000-000000000003'::uuid;

alter table inventory.stock_batch_balances
  add constraint ck_stock_batch_balances_quarantine_nonnegative
  check (quarantine_qty >= 0);

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    )
  ),
  0::bigint,
  'restoring the batch projection clears its negative-state violation'
);

alter table inventory.stock_product_positions
  drop constraint ck_stock_product_positions_damaged_nonnegative;

update inventory.stock_product_positions position
set
  damaged_qty = -1,
  version = position.version + 1
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000002'::uuid;

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    )
  ),
  1::bigint,
  'negative product projection creates one impossible-state violation'
);

select is(
  (
    select
      state.issue_code
        || ':'
        || state.entity_type_code
        || ':'
        || state.bucket_code
        || ':'
        || state.actual_quantity::text
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    ) state
  ),
  'NEGATIVE_PRODUCT_PROJECTION_BUCKET:PRODUCT_PROJECTION_BUCKET:DAMAGED:-1',
  'negative product projection evidence identifies its layer and bucket'
);

update inventory.stock_product_positions position
set
  damaged_qty = baseline.product_damaged_qty,
  version = position.version + 1
from impossible_projection_baseline baseline
where position.organization_id =
    '00000000-0000-4000-8000-000000000001'::uuid
  and position.product_id =
    '30000000-0000-4000-8000-000000000002'::uuid;

alter table inventory.stock_product_positions
  add constraint ck_stock_product_positions_damaged_nonnegative
  check (damaged_qty >= 0);

select is(
  (
    select count(*)
    from reconciliation.find_impossible_projection_states(
      '00000000-0000-4000-8000-000000000001'::uuid,
      null
    )
  ),
  0::bigint,
  'restoring the product projection clears its negative-state violation'
);

select * from finish();

rollback;