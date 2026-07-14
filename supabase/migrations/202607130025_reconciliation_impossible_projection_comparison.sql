begin;

create or replace function reconciliation.find_impossible_projection_states(
  p_organization_id uuid,
  p_ledger_seq_to bigint default null
)
returns table (
  issue_code text,
  entity_type_code text,
  product_id uuid,
  batch_id uuid,
  bucket_code text,
  expected_quantity bigint,
  actual_quantity bigint,
  expected_last_ledger_seq bigint,
  actual_last_ledger_seq bigint,
  projection_version bigint,
  violation_key text
)
language sql
stable
security definer
set search_path = pg_catalog, inventory
as $$
  with boundary as (
    select
      coalesce(
        p_ledger_seq_to,
        (
          select max(entry.ledger_seq)
          from inventory.stock_ledger_entries entry
          where entry.organization_id = p_organization_id
        ),
        0
      )::bigint as ledger_seq_to
  ),
  ledger_bucket as (
    select
      entry.product_id,
      entry.batch_id,
      entry.bucket_code,
      sum(entry.quantity_delta)::bigint as quantity,
      max(entry.ledger_seq)::bigint as last_ledger_seq
    from inventory.stock_ledger_entries entry
    cross join boundary
    where entry.organization_id = p_organization_id
      and entry.ledger_seq <= boundary.ledger_seq_to
    group by
      entry.product_id,
      entry.batch_id,
      entry.bucket_code
  ),
  ledger_batch as (
    select
      entry.product_id,
      entry.batch_id,
      max(entry.ledger_seq)::bigint as last_ledger_seq
    from inventory.stock_ledger_entries entry
    cross join boundary
    where entry.organization_id = p_organization_id
      and entry.ledger_seq <= boundary.ledger_seq_to
    group by
      entry.product_id,
      entry.batch_id
  ),
  ledger_product as (
    select
      entry.product_id,
      max(entry.ledger_seq)::bigint as last_ledger_seq
    from inventory.stock_ledger_entries entry
    cross join boundary
    where entry.organization_id = p_organization_id
      and entry.ledger_seq <= boundary.ledger_seq_to
    group by entry.product_id
  ),
  batch_bucket as (
    select
      balance.product_id,
      balance.batch_id,
      bucket.bucket_code,
      bucket.quantity,
      balance.last_ledger_seq,
      balance.version
    from inventory.stock_batch_balances balance
    cross join lateral (
      values
        ('SELLABLE'::text, balance.sellable_qty),
        ('QUARANTINE'::text, balance.quarantine_qty),
        ('DAMAGED'::text, balance.damaged_qty)
    ) as bucket(bucket_code, quantity)
    where balance.organization_id = p_organization_id
  ),
  product_bucket as (
    select
      position.product_id,
      bucket.bucket_code,
      bucket.quantity,
      position.last_ledger_seq,
      position.version
    from inventory.stock_product_positions position
    cross join lateral (
      values
        ('SELLABLE'::text, position.sellable_qty),
        ('QUARANTINE'::text, position.quarantine_qty),
        ('DAMAGED'::text, position.damaged_qty)
    ) as bucket(bucket_code, quantity)
    where position.organization_id = p_organization_id
  ),
  batch_aggregate as (
    select
      balance.product_id,
      bucket.bucket_code,
      sum(bucket.quantity)::bigint as quantity
    from inventory.stock_batch_balances balance
    cross join lateral (
      values
        ('SELLABLE'::text, balance.sellable_qty),
        ('QUARANTINE'::text, balance.quarantine_qty),
        ('DAMAGED'::text, balance.damaged_qty)
    ) as bucket(bucket_code, quantity)
    where balance.organization_id = p_organization_id
    group by
      balance.product_id,
      bucket.bucket_code
  ),
  violations as (
    select
      'NEGATIVE_LEDGER_BUCKET'::text as issue_code,
      'LEDGER_BUCKET'::text as entity_type_code,
      ledger.product_id,
      ledger.batch_id,
      ledger.bucket_code,
      0::bigint as expected_quantity,
      ledger.quantity as actual_quantity,
      ledger.last_ledger_seq as expected_last_ledger_seq,
      balance.last_ledger_seq as actual_last_ledger_seq,
      balance.version as projection_version,
      ledger.product_id::text
        || ':'
        || ledger.batch_id::text
        || ':'
        || ledger.bucket_code as violation_key
    from ledger_bucket ledger
    left join inventory.stock_batch_balances balance
      on balance.organization_id = p_organization_id
     and balance.product_id = ledger.product_id
     and balance.batch_id = ledger.batch_id
    where ledger.quantity < 0

    union all

    select
      'NEGATIVE_BATCH_PROJECTION_BUCKET'::text,
      'BATCH_PROJECTION_BUCKET'::text,
      projection.product_id,
      projection.batch_id,
      projection.bucket_code,
      coalesce(ledger.quantity, 0)::bigint,
      projection.quantity,
      coalesce(
        ledger_batch_state.last_ledger_seq,
        0
      )::bigint,
      projection.last_ledger_seq,
      projection.version,
      projection.product_id::text
        || ':'
        || projection.batch_id::text
        || ':'
        || projection.bucket_code
    from batch_bucket projection
    left join ledger_bucket ledger
      on ledger.product_id = projection.product_id
     and ledger.batch_id = projection.batch_id
     and ledger.bucket_code = projection.bucket_code
    left join ledger_batch ledger_batch_state
      on ledger_batch_state.product_id = projection.product_id
     and ledger_batch_state.batch_id = projection.batch_id
    where projection.quantity < 0

    union all

    select
      'NEGATIVE_PRODUCT_PROJECTION_BUCKET'::text,
      'PRODUCT_PROJECTION_BUCKET'::text,
      projection.product_id,
      null::uuid,
      projection.bucket_code,
      coalesce(batch.quantity, 0)::bigint,
      projection.quantity,
      coalesce(
        ledger_product_state.last_ledger_seq,
        0
      )::bigint,
      projection.last_ledger_seq,
      projection.version,
      projection.product_id::text
        || ':'
        || projection.bucket_code
    from product_bucket projection
    left join batch_aggregate batch
      on batch.product_id = projection.product_id
     and batch.bucket_code = projection.bucket_code
    left join ledger_product ledger_product_state
      on ledger_product_state.product_id = projection.product_id
    where projection.quantity < 0

    union all

    select
      case
        when balance.batch_id is null
          then 'BATCH_PROJECTION_MISSING'
        else 'BATCH_LEDGER_BOUNDARY_MISMATCH'
      end::text,
      'BATCH_PROJECTION_BOUNDARY'::text,
      ledger.product_id,
      ledger.batch_id,
      null::text,
      null::bigint,
      null::bigint,
      ledger.last_ledger_seq,
      balance.last_ledger_seq,
      balance.version,
      ledger.product_id::text
        || ':'
        || ledger.batch_id::text
    from ledger_batch ledger
    left join inventory.stock_batch_balances balance
      on balance.organization_id = p_organization_id
     and balance.product_id = ledger.product_id
     and balance.batch_id = ledger.batch_id
    where balance.batch_id is null
       or balance.last_ledger_seq <> ledger.last_ledger_seq

    union all

    select
      'BATCH_LEDGER_BOUNDARY_MISMATCH'::text,
      'BATCH_PROJECTION_BOUNDARY'::text,
      balance.product_id,
      balance.batch_id,
      null::text,
      null::bigint,
      null::bigint,
      0::bigint,
      balance.last_ledger_seq,
      balance.version,
      balance.product_id::text
        || ':'
        || balance.batch_id::text
    from inventory.stock_batch_balances balance
    left join ledger_batch ledger
      on ledger.product_id = balance.product_id
     and ledger.batch_id = balance.batch_id
    where balance.organization_id = p_organization_id
      and ledger.batch_id is null
      and balance.last_ledger_seq <> 0

    union all

    select
      case
        when position.product_id is null
          then 'PRODUCT_PROJECTION_MISSING'
        else 'PRODUCT_LEDGER_BOUNDARY_MISMATCH'
      end::text,
      'PRODUCT_PROJECTION_BOUNDARY'::text,
      ledger.product_id,
      null::uuid,
      null::text,
      null::bigint,
      null::bigint,
      ledger.last_ledger_seq,
      position.last_ledger_seq,
      position.version,
      ledger.product_id::text
    from ledger_product ledger
    left join inventory.stock_product_positions position
      on position.organization_id = p_organization_id
     and position.product_id = ledger.product_id
    where position.product_id is null
       or position.last_ledger_seq <> ledger.last_ledger_seq

    union all

    select
      'PRODUCT_LEDGER_BOUNDARY_MISMATCH'::text,
      'PRODUCT_PROJECTION_BOUNDARY'::text,
      position.product_id,
      null::uuid,
      null::text,
      null::bigint,
      null::bigint,
      0::bigint,
      position.last_ledger_seq,
      position.version,
      position.product_id::text
    from inventory.stock_product_positions position
    left join ledger_product ledger
      on ledger.product_id = position.product_id
    where position.organization_id = p_organization_id
      and ledger.product_id is null
      and position.last_ledger_seq <> 0
  )
  select
    violation.issue_code,
    violation.entity_type_code,
    violation.product_id,
    violation.batch_id,
    violation.bucket_code,
    violation.expected_quantity,
    violation.actual_quantity,
    violation.expected_last_ledger_seq,
    violation.actual_last_ledger_seq,
    violation.projection_version,
    violation.violation_key
  from violations violation
  order by
    violation.issue_code,
    violation.entity_type_code,
    violation.product_id,
    violation.batch_id nulls first,
    violation.bucket_code nulls first
$$;

revoke all on function
  reconciliation.find_impossible_projection_states(uuid, bigint)
from public, anon, authenticated, service_role;

commit;