begin;

create or replace function inventory.enforce_new_stock_master_guardrails()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog, inventory
as $$
declare
  v_transaction inventory.stock_transactions%rowtype;
  v_command_scope text;
  v_product catalog.products%rowtype;
  v_batch catalog.product_batches%rowtype;
begin
  select transaction.*
  into v_transaction
  from inventory.stock_transactions transaction
  where transaction.id = new.transaction_id;

  if not found then
    return new;
  end if;

  select command.scope
  into v_command_scope
  from inventory.idempotency_commands command
  where command.organization_id = v_transaction.organization_id
    and command.id = v_transaction.idempotency_command_id;

  if not found then
    return new;
  end if;

  if (
       v_transaction.transaction_type_code = 'RECEIPT'
       and v_command_scope <> 'POST_RECEIPT'
     )
     or (
       v_transaction.transaction_type_code = 'INITIAL_BALANCE'
       and v_command_scope <> 'POST_OPENING_BALANCE'
     )
     or v_transaction.transaction_type_code
        not in ('RECEIPT', 'INITIAL_BALANCE') then
    return new;
  end if;

  select product.*
  into v_product
  from catalog.products product
  where product.organization_id = new.organization_id
    and product.id = new.product_id;

  select batch.*
  into v_batch
  from catalog.product_batches batch
  where batch.organization_id = new.organization_id
    and batch.product_id = new.product_id
    and batch.id = new.batch_id;

  if v_product.id is null or v_batch.id is null then
    raise exception using
      errcode = 'P0001',
      message = case v_transaction.transaction_type_code
        when 'RECEIPT' then 'RECEIPT_LINE_MASTER_NOT_FOUND'
        else 'OPENING_BALANCE_LINE_MASTER_NOT_FOUND'
      end;
  end if;

  if not v_product.is_active then
    raise exception using
      errcode = 'P0001',
      message = case v_transaction.transaction_type_code
        when 'RECEIPT' then 'RECEIPT_PRODUCT_INACTIVE'
        else 'OPENING_BALANCE_PRODUCT_INACTIVE'
      end;
  end if;

  if v_transaction.transaction_type_code = 'RECEIPT' then
    if v_batch.status_code <> 'ACTIVE' then
      raise exception using
        errcode = 'P0001',
        message = 'RECEIPT_BATCH_NOT_ACTIVE';
    end if;

    if v_batch.expiry_date < v_transaction.effective_local_date then
      raise exception using
        errcode = 'P0001',
        message = 'RECEIPT_BATCH_EXPIRED';
    end if;

    if v_batch.batch_kind_code <> 'STANDARD' then
      raise exception using
        errcode = 'P0001',
        message = 'RECEIPT_BATCH_KIND_INVALID';
    end if;
  else
    if v_batch.status_code = 'ARCHIVED' then
      raise exception using
        errcode = 'P0001',
        message = 'OPENING_BALANCE_BATCH_ARCHIVED';
    end if;

    if v_batch.expiry_date < v_transaction.effective_local_date then
      raise exception using
        errcode = 'P0001',
        message = 'OPENING_BALANCE_BATCH_EXPIRED';
    end if;

    if v_batch.batch_kind_code = 'RETURN' then
      raise exception using
        errcode = 'P0001',
        message = 'OPENING_BALANCE_RETURN_BATCH_FORBIDDEN';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function inventory.enforce_new_stock_master_guardrails()
from public, anon, authenticated, service_role;

drop trigger if exists trg_stock_ledger_entries_master_guardrails
on inventory.stock_ledger_entries;

create trigger trg_stock_ledger_entries_master_guardrails
before insert on inventory.stock_ledger_entries
for each row
execute function inventory.enforce_new_stock_master_guardrails();

create or replace function operations.enforce_opening_balance_line_master_guardrails()
returns trigger
language plpgsql
set search_path = pg_catalog, catalog, operations
as $$
declare
  v_effective_local_date date;
  v_product catalog.products%rowtype;
  v_batch catalog.product_batches%rowtype;
begin
  select cutover.effective_local_date
  into v_effective_local_date
  from operations.opening_balance_cutovers cutover
  where cutover.organization_id = new.organization_id
    and cutover.id = new.cutover_id;

  select product.*
  into v_product
  from catalog.products product
  where product.organization_id = new.organization_id
    and product.id = new.product_id;

  select batch.*
  into v_batch
  from catalog.product_batches batch
  where batch.organization_id = new.organization_id
    and batch.product_id = new.product_id
    and batch.id = new.batch_id;

  if v_effective_local_date is null
     or v_product.id is null
     or v_batch.id is null then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_LINE_MASTER_NOT_FOUND';
  end if;

  if not v_product.is_active then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_PRODUCT_INACTIVE';
  end if;

  if v_batch.status_code = 'ARCHIVED' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_BATCH_ARCHIVED';
  end if;

  if v_batch.expiry_date < v_effective_local_date then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_BATCH_EXPIRED';
  end if;

  if v_batch.batch_kind_code = 'RETURN' then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_RETURN_BATCH_FORBIDDEN';
  end if;

  if v_batch.batch_kind_code = 'UNIDENTIFIED_RETURN'
     and (
       new.bucket_code <> 'QUARANTINE'
       or new.batch_identity_verified
       or new.exception_reference is null
       or btrim(new.exception_reference) = ''
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_UNIDENTIFIED_BATCH_SCOPE_INVALID';
  end if;

  return new;
end;
$$;

revoke all
on function operations.enforce_opening_balance_line_master_guardrails()
from public, anon, authenticated, service_role;

drop trigger if exists trg_opening_balance_lines_master_guardrails
on operations.opening_balance_cutover_lines;

create trigger trg_opening_balance_lines_master_guardrails
before insert or update on operations.opening_balance_cutover_lines
for each row
execute function operations.enforce_opening_balance_line_master_guardrails();

create or replace function operations.resolve_stocktake_scope(
  p_organization_id uuid,
  p_scope jsonb,
  p_as_of_date date,
  p_ledger_seq bigint
)
returns table (
  product_id uuid,
  batch_id uuid,
  bucket_code text,
  product_sku_snapshot text,
  product_name_snapshot text,
  batch_code_snapshot text,
  expiry_date_snapshot date,
  system_qty_at_snapshot bigint
)
language sql
stable
security invoker
set search_path = pg_catalog, catalog, inventory
as $$
  with scope_parameters as (
    select
      upper(btrim(p_scope ->> 'mode')) as scope_mode,
      coalesce(
        (p_scope ->> 'includeZeroSystemBalance')::boolean,
        false
      ) as include_zero_system_balance,
      coalesce(
        (p_scope ->> 'includeInactiveWithBalance')::boolean,
        false
      ) as include_inactive_with_balance,
      coalesce(
        (p_scope ->> 'includeBlockedBatches')::boolean,
        false
      ) as include_blocked_batches,
      coalesce(
        (p_scope ->> 'includeExpiredBatches')::boolean,
        false
      ) as include_expired_batches
  ),
  requested_products as (
    select item.value::uuid as product_id
    from jsonb_array_elements_text(
      coalesce(p_scope -> 'productIds', '[]'::jsonb)
    ) as item(value)
  ),
  requested_batches as (
    select item.value::uuid as batch_id
    from jsonb_array_elements_text(
      coalesce(p_scope -> 'batchIds', '[]'::jsonb)
    ) as item(value)
  ),
  requested_buckets as (
    select upper(btrim(item.value)) as bucket_code
    from jsonb_array_elements_text(
      coalesce(p_scope -> 'bucketCodes', '[]'::jsonb)
    ) as item(value)
  ),
  scoped_batches as (
    select
      product.id as product_id,
      product.sku,
      product.name,
      product.is_active as product_is_active,
      batch.id as batch_id,
      batch.batch_code,
      batch.expiry_date,
      batch.status_code
    from catalog.products product
    join catalog.product_batches batch
      on batch.organization_id = product.organization_id
     and batch.product_id = product.id
    cross join scope_parameters parameters
    where product.organization_id = p_organization_id
      and (
        parameters.scope_mode = 'ALL_ACTIVE_INVENTORY'
        or (
          parameters.scope_mode = 'PRODUCTS'
          and exists (
            select 1
            from requested_products requested
            where requested.product_id = product.id
          )
        )
        or (
          parameters.scope_mode = 'BATCHES'
          and exists (
            select 1
            from requested_batches requested
            where requested.batch_id = batch.id
          )
        )
      )
  ),
  scoped_lines as (
    select
      scoped.product_id,
      scoped.batch_id,
      bucket.bucket_code,
      scoped.sku,
      scoped.name,
      scoped.product_is_active,
      scoped.batch_code,
      scoped.expiry_date,
      scoped.status_code,
      parameters.include_zero_system_balance,
      parameters.include_inactive_with_balance,
      parameters.include_blocked_batches,
      parameters.include_expired_batches,
      coalesce(ledger.quantity, 0)::bigint as system_quantity
    from scoped_batches scoped
    cross join requested_buckets bucket
    cross join scope_parameters parameters
    left join lateral (
      select sum(entry.quantity_delta)::bigint as quantity
      from inventory.stock_ledger_entries entry
      where entry.organization_id = p_organization_id
        and entry.product_id = scoped.product_id
        and entry.batch_id = scoped.batch_id
        and entry.bucket_code = bucket.bucket_code
        and entry.ledger_seq <= p_ledger_seq
    ) ledger on true
  )
  select
    line.product_id,
    line.batch_id,
    line.bucket_code,
    line.sku,
    line.name,
    line.batch_code,
    line.expiry_date,
    line.system_quantity
  from scoped_lines line
  where (
      line.product_is_active
      or (
        line.include_inactive_with_balance
        and line.system_quantity <> 0
      )
    )
    and (
      line.status_code = 'ACTIVE'
      or (
        line.status_code = 'BLOCKED'
        and line.include_blocked_batches
      )
      or (
        line.status_code = 'ARCHIVED'
        and line.include_inactive_with_balance
        and line.system_quantity <> 0
      )
    )
    and (
      line.expiry_date >= p_as_of_date
      or line.include_expired_batches
      or (
        line.status_code = 'ARCHIVED'
        and line.include_inactive_with_balance
        and line.system_quantity <> 0
      )
    )
    and (
      line.include_zero_system_balance
      or line.system_quantity <> 0
    )
  order by
    line.sku,
    line.expiry_date,
    line.batch_code,
    case line.bucket_code
      when 'SELLABLE' then 1
      when 'QUARANTINE' then 2
      when 'DAMAGED' then 3
      else 99
    end,
    line.batch_id;
$$;

revoke all on function operations.resolve_stocktake_scope(
  uuid,
  jsonb,
  date,
  bigint
) from public, anon, authenticated, service_role;

commit;
