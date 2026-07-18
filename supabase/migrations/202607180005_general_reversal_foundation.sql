begin;

create table inventory.stock_reversal_applications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  original_transaction_id uuid not null
    references inventory.stock_transactions(id) on delete restrict,
  reversal_transaction_id uuid not null
    references inventory.stock_transactions(id) on delete restrict,
  original_entry_id uuid not null
    references inventory.stock_ledger_entries(id) on delete restrict,
  reversal_entry_id uuid not null
    references inventory.stock_ledger_entries(id) on delete restrict,
  quantity_applied bigint not null,
  created_at timestamptz not null default clock_timestamp(),

  constraint uq_stock_reversal_applications_reversal_entry
    unique (reversal_entry_id),

  constraint uq_stock_reversal_applications_pair
    unique (original_entry_id, reversal_entry_id),

  constraint ck_stock_reversal_applications_quantity
    check (quantity_applied > 0),

  constraint ck_stock_reversal_applications_entries_distinct
    check (original_entry_id <> reversal_entry_id),

  constraint ck_stock_reversal_applications_transactions_distinct
    check (original_transaction_id <> reversal_transaction_id)
);

create index idx_stock_reversal_applications_original_transaction
on inventory.stock_reversal_applications (
  organization_id,
  original_transaction_id,
  created_at,
  id
);

create index idx_stock_reversal_applications_reversal_transaction
on inventory.stock_reversal_applications (
  organization_id,
  reversal_transaction_id,
  created_at,
  id
);

create index idx_stock_reversal_applications_original_entry
on inventory.stock_reversal_applications (
  original_entry_id,
  created_at,
  id
);

create or replace function inventory.validate_stock_reversal_application()
returns trigger
language plpgsql
set search_path = pg_catalog, inventory
as $$
declare
  v_original_transaction inventory.stock_transactions%rowtype;
  v_reversal_transaction inventory.stock_transactions%rowtype;
  v_original_entry inventory.stock_ledger_entries%rowtype;
  v_reversal_entry inventory.stock_ledger_entries%rowtype;
  v_applied_before bigint;
begin
  select transaction.*
  into v_original_transaction
  from inventory.stock_transactions transaction
  where transaction.id = new.original_transaction_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'REVERSAL_ORIGINAL_TRANSACTION_NOT_FOUND';
  end if;

  select transaction.*
  into v_reversal_transaction
  from inventory.stock_transactions transaction
  where transaction.id = new.reversal_transaction_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'REVERSAL_TRANSACTION_NOT_FOUND';
  end if;

  if v_original_transaction.organization_id <> new.organization_id
     or v_reversal_transaction.organization_id <> new.organization_id then
    raise exception using errcode = 'P0001', message = 'REVERSAL_APPLICATION_ORGANIZATION_MISMATCH';
  end if;

  if v_original_transaction.transaction_type_code = 'REVERSAL' then
    raise exception using errcode = 'P0001', message = 'REVERSAL_OF_REVERSAL_NOT_ALLOWED';
  end if;

  if v_reversal_transaction.transaction_type_code <> 'REVERSAL'
     or v_reversal_transaction.reversal_of_transaction_id
        is distinct from v_original_transaction.id then
    raise exception using errcode = 'P0001', message = 'REVERSAL_TRANSACTION_LINK_MISMATCH';
  end if;

  select entry.*
  into v_original_entry
  from inventory.stock_ledger_entries entry
  where entry.id = new.original_entry_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'REVERSAL_ORIGINAL_ENTRY_NOT_FOUND';
  end if;

  select entry.*
  into v_reversal_entry
  from inventory.stock_ledger_entries entry
  where entry.id = new.reversal_entry_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'REVERSAL_ENTRY_NOT_FOUND';
  end if;

  if v_original_entry.organization_id <> new.organization_id
     or v_reversal_entry.organization_id <> new.organization_id then
    raise exception using errcode = 'P0001', message = 'REVERSAL_ENTRY_ORGANIZATION_MISMATCH';
  end if;

  if v_original_entry.transaction_id <> v_original_transaction.id
     or v_reversal_entry.transaction_id <> v_reversal_transaction.id then
    raise exception using errcode = 'P0001', message = 'REVERSAL_ENTRY_TRANSACTION_MISMATCH';
  end if;

  if v_original_entry.product_id <> v_reversal_entry.product_id
     or v_original_entry.batch_id <> v_reversal_entry.batch_id
     or v_original_entry.bucket_code <> v_reversal_entry.bucket_code then
    raise exception using errcode = 'P0001', message = 'REVERSAL_ENTRY_STOCK_IDENTITY_MISMATCH';
  end if;

  if sign(v_original_entry.quantity_delta) = sign(v_reversal_entry.quantity_delta)
     or abs(v_reversal_entry.quantity_delta) <> new.quantity_applied then
    raise exception using errcode = 'P0001', message = 'REVERSAL_ENTRY_QUANTITY_MISMATCH';
  end if;

  select coalesce(sum(application.quantity_applied), 0)::bigint
  into v_applied_before
  from inventory.stock_reversal_applications application
  where application.original_entry_id = new.original_entry_id;

  if v_applied_before + new.quantity_applied
     > abs(v_original_entry.quantity_delta) then
    raise exception using errcode = 'P0001', message = 'REVERSAL_APPLICATION_OVER_APPLIED';
  end if;

  return new;
end;
$$;

create trigger trg_stock_reversal_applications_validate
before insert on inventory.stock_reversal_applications
for each row
execute function inventory.validate_stock_reversal_application();

create trigger trg_stock_reversal_applications_immutable
before update or delete on inventory.stock_reversal_applications
for each row
execute function inventory.reject_immutable_mutation();

alter table inventory.stock_reversal_applications enable row level security;

create policy stock_reversal_applications_read_current_org
on inventory.stock_reversal_applications
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all
on inventory.stock_reversal_applications
from public, anon, authenticated;

grant select
on inventory.stock_reversal_applications
to authenticated, service_role;

create or replace function inventory.build_stock_transaction_reversal_preview(
  p_organization_id uuid,
  p_original_transaction_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
declare
  v_original inventory.stock_transactions%rowtype;
  v_lines jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_basis jsonb;
  v_basis_hash text;
  v_line_count bigint := 0;
  v_total_absolute_quantity bigint := 0;
begin
  select transaction.*
  into v_original
  from inventory.stock_transactions transaction
  where transaction.organization_id = p_organization_id
    and transaction.id = p_original_transaction_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'ORIGINAL_TRANSACTION_NOT_FOUND';
  end if;

  if v_original.transaction_type_code not in ('RECEIPT', 'MANUAL_OUTBOUND') then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'REVERSAL_TRANSACTION_TYPE_NOT_SUPPORTED',
        'message', 'Jenis transaksi belum didukung oleh koreksi entri generik.'
      )
    );
  end if;

  select
    count(*),
    coalesce(sum(abs(entry.quantity_delta)), 0)::bigint
  into
    v_line_count,
    v_total_absolute_quantity
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id
    and entry.transaction_id = p_original_transaction_id;

  if v_line_count = 0 then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'REVERSAL_ORIGINAL_ENTRIES_REQUIRED',
        'message', 'Transaksi asal tidak memiliki ledger entry.'
      )
    );
  end if;

  if exists (
    select 1
    from inventory.stock_transactions reversal
    where reversal.organization_id = p_organization_id
      and reversal.transaction_type_code = 'REVERSAL'
      and reversal.reversal_of_transaction_id = p_original_transaction_id
  ) or exists (
    select 1
    from inventory.stock_reversal_applications application
    where application.organization_id = p_organization_id
      and application.original_transaction_id = p_original_transaction_id
  ) then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'ORIGINAL_TRANSACTION_ALREADY_REVERSED',
        'message', 'Transaksi asal sudah memiliki pembalikan.'
      )
    );
  end if;

  if exists (
    select 1
    from inventory.stock_ledger_entries entry
    left join lateral (
      select coalesce(sum(application.quantity_applied), 0)::bigint as applied_qty
      from inventory.stock_reversal_applications application
      where application.original_entry_id = entry.id
    ) applied on true
    where entry.organization_id = p_organization_id
      and entry.transaction_id = p_original_transaction_id
      and applied.applied_qty > abs(entry.quantity_delta)
  ) then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'REVERSAL_APPLICATION_OVER_APPLIED',
        'message', 'Riwayat pembalikan entry melebihi kuantitas asal.'
      )
    );
  end if;

  if exists (
    with affected as (
      select distinct
        entry.product_id,
        entry.batch_id
      from inventory.stock_ledger_entries entry
      where entry.organization_id = p_organization_id
        and entry.transaction_id = p_original_transaction_id
    ),
    ledger as (
      select
        affected.product_id,
        affected.batch_id,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'SELLABLE'
          ),
          0
        )::bigint as sellable_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'QUARANTINE'
          ),
          0
        )::bigint as quarantine_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'DAMAGED'
          ),
          0
        )::bigint as damaged_qty
      from affected
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = p_organization_id
       and entry.product_id = affected.product_id
       and entry.batch_id = affected.batch_id
      group by affected.product_id, affected.batch_id
    )
    select 1
    from ledger
    left join inventory.stock_batch_balances balance
      on balance.organization_id = p_organization_id
     and balance.product_id = ledger.product_id
     and balance.batch_id = ledger.batch_id
    where balance.batch_id is null
       or balance.sellable_qty <> ledger.sellable_qty
       or balance.quarantine_qty <> ledger.quarantine_qty
       or balance.damaged_qty <> ledger.damaged_qty
  ) then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'REVERSAL_PROJECTION_DRIFT',
        'message', 'Projection batch tidak sama dengan ledger.'
      )
    );
  end if;

  if exists (
    with affected as (
      select distinct entry.product_id
      from inventory.stock_ledger_entries entry
      where entry.organization_id = p_organization_id
        and entry.transaction_id = p_original_transaction_id
    ),
    ledger as (
      select
        affected.product_id,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'SELLABLE'
          ),
          0
        )::bigint as sellable_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'QUARANTINE'
          ),
          0
        )::bigint as quarantine_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'DAMAGED'
          ),
          0
        )::bigint as damaged_qty
      from affected
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = p_organization_id
       and entry.product_id = affected.product_id
      group by affected.product_id
    )
    select 1
    from ledger
    left join inventory.stock_product_positions position
      on position.organization_id = p_organization_id
     and position.product_id = ledger.product_id
    where position.product_id is null
       or position.sellable_qty <> ledger.sellable_qty
       or position.quarantine_qty <> ledger.quarantine_qty
       or position.damaged_qty <> ledger.damaged_qty
  ) then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'REVERSAL_PROJECTION_DRIFT',
        'message', 'Projection produk tidak sama dengan ledger.'
      )
    );
  end if;

  if exists (
    with reversal_effect as (
      select
        entry.product_id,
        entry.batch_id,
        entry.bucket_code,
        sum(
          case
            when entry.quantity_delta > 0
              then -(
                abs(entry.quantity_delta)
                - coalesce(applied.applied_qty, 0)
              )
            else
              abs(entry.quantity_delta)
              - coalesce(applied.applied_qty, 0)
          end
        )::bigint as reversal_delta
      from inventory.stock_ledger_entries entry
      left join lateral (
        select coalesce(sum(application.quantity_applied), 0)::bigint as applied_qty
        from inventory.stock_reversal_applications application
        where application.original_entry_id = entry.id
      ) applied on true
      where entry.organization_id = p_organization_id
        and entry.transaction_id = p_original_transaction_id
      group by entry.product_id, entry.batch_id, entry.bucket_code
    )
    select 1
    from reversal_effect effect
    join inventory.stock_batch_balances balance
      on balance.organization_id = p_organization_id
     and balance.product_id = effect.product_id
     and balance.batch_id = effect.batch_id
    where (
      case effect.bucket_code
        when 'SELLABLE' then balance.sellable_qty
        when 'QUARANTINE' then balance.quarantine_qty
        when 'DAMAGED' then balance.damaged_qty
      end
    ) + effect.reversal_delta < 0
  ) then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'REVERSAL_NEGATIVE_BUCKET',
        'message', 'Pembalikan akan membuat saldo bucket batch menjadi negatif.'
      )
    );
  end if;

  if exists (
    with reversal_effect as (
      select
        entry.product_id,
        sum(
          case
            when entry.bucket_code <> 'SELLABLE' then 0
            when entry.quantity_delta > 0
              then -(
                abs(entry.quantity_delta)
                - coalesce(applied.applied_qty, 0)
              )
            else
              abs(entry.quantity_delta)
              - coalesce(applied.applied_qty, 0)
          end
        )::bigint as sellable_delta
      from inventory.stock_ledger_entries entry
      left join lateral (
        select coalesce(sum(application.quantity_applied), 0)::bigint as applied_qty
        from inventory.stock_reversal_applications application
        where application.original_entry_id = entry.id
      ) applied on true
      where entry.organization_id = p_organization_id
        and entry.transaction_id = p_original_transaction_id
      group by entry.product_id
    )
    select 1
    from reversal_effect effect
    join inventory.stock_product_positions position
      on position.organization_id = p_organization_id
     and position.product_id = effect.product_id
    where position.sellable_qty + effect.sellable_delta
          < position.reserved_qty
  ) then
    v_blockers := v_blockers || jsonb_build_array(
      jsonb_build_object(
        'code', 'REVERSAL_RESERVED_CONFLICT',
        'message', 'Pembalikan akan membuat reserved melebihi sellable.'
      )
    );
  end if;

  with entry_state as (
    select
      entry.*,
      coalesce(applied.applied_qty, 0)::bigint as applied_qty,
      greatest(
        abs(entry.quantity_delta) - coalesce(applied.applied_qty, 0),
        0
      )::bigint as remaining_qty,
      case
        when entry.quantity_delta > 0 then
          -greatest(
            abs(entry.quantity_delta) - coalesce(applied.applied_qty, 0),
            0
          )
        else
          greatest(
            abs(entry.quantity_delta) - coalesce(applied.applied_qty, 0),
            0
          )
      end::bigint as reversal_delta,
      balance.sellable_qty as batch_sellable_qty,
      balance.quarantine_qty as batch_quarantine_qty,
      balance.damaged_qty as batch_damaged_qty,
      balance.version as batch_balance_version,
      position.sellable_qty as product_sellable_qty,
      position.quarantine_qty as product_quarantine_qty,
      position.damaged_qty as product_damaged_qty,
      position.reserved_qty as product_reserved_qty,
      position.version as product_position_version
    from inventory.stock_ledger_entries entry
    left join lateral (
      select coalesce(sum(application.quantity_applied), 0)::bigint as applied_qty
      from inventory.stock_reversal_applications application
      where application.original_entry_id = entry.id
    ) applied on true
    left join inventory.stock_batch_balances balance
      on balance.organization_id = entry.organization_id
     and balance.product_id = entry.product_id
     and balance.batch_id = entry.batch_id
    left join inventory.stock_product_positions position
      on position.organization_id = entry.organization_id
     and position.product_id = entry.product_id
    where entry.organization_id = p_organization_id
      and entry.transaction_id = p_original_transaction_id
  ),
  product_effect as (
    select
      state.product_id,
      coalesce(
        sum(state.reversal_delta) filter (
          where state.bucket_code = 'SELLABLE'
        ),
        0
      )::bigint as sellable_delta,
      coalesce(
        sum(state.reversal_delta) filter (
          where state.bucket_code = 'QUARANTINE'
        ),
        0
      )::bigint as quarantine_delta,
      coalesce(
        sum(state.reversal_delta) filter (
          where state.bucket_code = 'DAMAGED'
        ),
        0
      )::bigint as damaged_delta
    from entry_state state
    group by state.product_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'originalEntryId', state.id,
        'lineNo', state.line_no,
        'productId', state.product_id,
        'batchId', state.batch_id,
        'productSku', state.product_sku_snapshot,
        'batchCode', state.batch_code_snapshot,
        'expiryDate', state.expiry_date_snapshot,
        'bucketCode', state.bucket_code,
        'originalDelta', state.quantity_delta,
        'quantityAlreadyReversed', state.applied_qty,
        'quantityToReverse', state.remaining_qty,
        'reversalDelta', state.reversal_delta,
        'currentBatchBucketQty',
          case state.bucket_code
            when 'SELLABLE' then state.batch_sellable_qty
            when 'QUARANTINE' then state.batch_quarantine_qty
            when 'DAMAGED' then state.batch_damaged_qty
          end,
        'resultingBatchBucketQty',
          case state.bucket_code
            when 'SELLABLE' then state.batch_sellable_qty
            when 'QUARANTINE' then state.batch_quarantine_qty
            when 'DAMAGED' then state.batch_damaged_qty
          end + state.reversal_delta,
        'currentProductSellableQty', state.product_sellable_qty,
        'currentProductQuarantineQty', state.product_quarantine_qty,
        'currentProductDamagedQty', state.product_damaged_qty,
        'currentProductReservedQty', state.product_reserved_qty,
        'resultingProductSellableQty',
          state.product_sellable_qty + effect.sellable_delta,
        'resultingProductQuarantineQty',
          state.product_quarantine_qty + effect.quarantine_delta,
        'resultingProductDamagedQty',
          state.product_damaged_qty + effect.damaged_delta,
        'batchBalanceVersion', state.batch_balance_version,
        'productPositionVersion', state.product_position_version
      )
      order by state.ledger_seq
    ),
    '[]'::jsonb
  )
  into v_lines
  from entry_state state
  join product_effect effect
    on effect.product_id = state.product_id;

  v_basis := jsonb_build_object(
    'schemaVersion', 1,
    'organizationId', p_organization_id,
    'originalTransactionId', v_original.id,
    'originalTransactionNo', v_original.transaction_no,
    'originalTransactionType', v_original.transaction_type_code,
    'originalReasonCode', v_original.reason_code_snapshot,
    'originalChannelCode', v_original.channel_code_snapshot,
    'originalSourceType', v_original.source_type_code,
    'originalSourceId', v_original.source_id,
    'originalSourceRef', v_original.source_ref_snapshot,
    'originalOccurredAt', v_original.occurred_at,
    'originalRecordedAt', v_original.recorded_at,
    'lines', v_lines
  );

  v_basis_hash := encode(
    extensions.digest(
      convert_to(v_basis::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  return jsonb_build_object(
    'status',
      case
        when jsonb_array_length(v_blockers) = 0
          then 'PREVIEW_READY'
        else 'BLOCKED'
      end,
    'eligible', jsonb_array_length(v_blockers) = 0,
    'basisHash', v_basis_hash,
    'schemaVersion', 1,
    'originalTransaction', jsonb_build_object(
      'transactionId', v_original.id,
      'transactionNo', v_original.transaction_no,
      'transactionTypeCode', v_original.transaction_type_code,
      'reasonCode', v_original.reason_code_snapshot,
      'channelCode', v_original.channel_code_snapshot,
      'sourceTypeCode', v_original.source_type_code,
      'sourceId', v_original.source_id,
      'sourceRef', v_original.source_ref_snapshot,
      'occurredAt', v_original.occurred_at,
      'recordedAt', v_original.recorded_at,
      'actorUserId', v_original.actor_user_id,
      'processName', v_original.process_name,
      'note', v_original.note
    ),
    'lineCount', v_line_count,
    'totalAbsoluteQuantity', v_total_absolute_quantity,
    'lines', v_lines,
    'blockers', v_blockers
  );
end;
$$;

revoke all
on function inventory.build_stock_transaction_reversal_preview(uuid, uuid)
from public, anon, authenticated, service_role;

create or replace function api.preview_stock_transaction_reversal(
  p_organization_id uuid,
  p_original_transaction_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
declare
  v_actor_user_id uuid := auth.uid();
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_original_transaction_id is null then
    raise exception using errcode = 'P0001', message = 'ORIGINAL_TRANSACTION_ID_REQUIRED';
  end if;

  if v_actor_user_id is null then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if not app.is_admin()
     or app.current_organization_id() is distinct from p_organization_id then
    raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  return inventory.build_stock_transaction_reversal_preview(
    p_organization_id,
    p_original_transaction_id
  );
end;
$$;

create or replace function api.reverse_stock_transaction(
  p_organization_id uuid,
  p_idempotency_key text,
  p_original_transaction_id uuid,
  p_preview_basis_hash text,
  p_confirmation boolean,
  p_note text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations,
  extensions
as $$
declare
  v_scope constant text := 'REVERSE_STOCK_TRANSACTION';
  v_idempotency_key text;
  v_preview_basis_hash text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_original inventory.stock_transactions%rowtype;
  v_preview jsonb;
  v_blocker_code text;
  v_reason_id uuid;
  v_channel_id uuid;
  v_command_id uuid := gen_random_uuid();
  v_reversal_transaction_id uuid := gen_random_uuid();
  v_correlation_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_effective_local_date date;
  v_organization_timezone text;
  v_transaction_no text;
  v_actor_user_id uuid := auth.uid();
  v_line record;
  v_reversal_entry_id uuid;
  v_ledger_seq bigint;
  v_applied_qty bigint;
  v_remaining_qty bigint;
  v_reversal_delta bigint;
  v_line_count bigint := 0;
  v_total_absolute_quantity bigint := 0;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_original_transaction_id is null then
    raise exception using errcode = 'P0001', message = 'ORIGINAL_TRANSACTION_ID_REQUIRED';
  end if;

  if not coalesce(p_confirmation, false) then
    raise exception using errcode = 'P0001', message = 'REVERSAL_CONFIRMATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_preview_basis_hash := lower(btrim(coalesce(p_preview_basis_hash, '')));

  if v_preview_basis_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = 'P0001', message = 'REVERSAL_PREVIEW_HASH_INVALID';
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');

  if v_note is null then
    raise exception using errcode = 'P0001', message = 'REVERSAL_NOTE_REQUIRED';
  end if;

  if length(v_note) > 2000 then
    raise exception using errcode = 'P0001', message = 'REVERSAL_NOTE_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'REVERSAL_METADATA_MUST_BE_OBJECT';
  end if;

  if v_actor_user_id is null then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if not app.is_admin()
     or app.current_organization_id() is distinct from p_organization_id then
    raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
  end if;

  select organization.timezone
  into v_organization_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_NOT_FOUND';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'originalTransactionId', p_original_transaction_id,
          'previewBasisHash', v_preview_basis_hash,
          'confirmation', true,
          'note', v_note,
          'metadata', v_metadata,
          'schemaVersion', 1
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text ||
      ':' ||
      v_scope ||
      ':' ||
      v_idempotency_key,
      0::bigint
    )
  );

  select command.*
  into v_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id
    and command.scope = v_scope
    and command.key = v_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> v_request_hash then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REUSED';
    end if;

    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot;
    end if;

    if v_existing.status_code = 'STARTED' then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;

    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text ||
      ':STOCK_TRANSACTION_REVERSAL:' ||
      p_original_transaction_id::text,
      0::bigint
    )
  );

  select transaction.*
  into v_original
  from inventory.stock_transactions transaction
  where transaction.organization_id = p_organization_id
    and transaction.id = p_original_transaction_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'ORIGINAL_TRANSACTION_NOT_FOUND';
  end if;

  perform product.id
  from catalog.products product
  join (
    select distinct entry.product_id
    from inventory.stock_ledger_entries entry
    where entry.organization_id = p_organization_id
      and entry.transaction_id = p_original_transaction_id
  ) affected
    on affected.product_id = product.id
  where product.organization_id = p_organization_id
  order by product.id
  for update of product;

  perform batch.id
  from catalog.product_batches batch
  join (
    select distinct
      entry.product_id,
      entry.batch_id
    from inventory.stock_ledger_entries entry
    where entry.organization_id = p_organization_id
      and entry.transaction_id = p_original_transaction_id
  ) affected
    on affected.product_id = batch.product_id
   and affected.batch_id = batch.id
  where batch.organization_id = p_organization_id
  order by batch.product_id, batch.id
  for update of batch;

  perform balance.batch_id
  from inventory.stock_batch_balances balance
  join (
    select distinct
      entry.product_id,
      entry.batch_id
    from inventory.stock_ledger_entries entry
    where entry.organization_id = p_organization_id
      and entry.transaction_id = p_original_transaction_id
  ) affected
    on affected.product_id = balance.product_id
   and affected.batch_id = balance.batch_id
  where balance.organization_id = p_organization_id
  order by balance.product_id, balance.batch_id
  for update of balance;

  perform position.product_id
  from inventory.stock_product_positions position
  join (
    select distinct entry.product_id
    from inventory.stock_ledger_entries entry
    where entry.organization_id = p_organization_id
      and entry.transaction_id = p_original_transaction_id
  ) affected
    on affected.product_id = position.product_id
  where position.organization_id = p_organization_id
  order by position.product_id
  for update of position;

  v_preview := inventory.build_stock_transaction_reversal_preview(
    p_organization_id,
    p_original_transaction_id
  );

  if v_preview ->> 'basisHash' <> v_preview_basis_hash then
    raise exception using errcode = 'P0001', message = 'STALE_REVERSAL_PREVIEW';
  end if;

  if not coalesce((v_preview ->> 'eligible')::boolean, false) then
    v_blocker_code := v_preview #>> '{blockers,0,code}';

    raise exception using
      errcode = 'P0001',
      message = coalesce(v_blocker_code, 'REVERSAL_NOT_ALLOWED');
  end if;

  select reason.id
  into v_reason_id
  from catalog.movement_reasons reason
  where reason.code = 'REVERSAL'
    and reason.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'REVERSAL_REASON_NOT_CONFIGURED';
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = 'MANUAL'
    and channel.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'REVERSAL_CHANNEL_NOT_CONFIGURED';
  end if;

  insert into inventory.idempotency_commands (
    id,
    organization_id,
    scope,
    key,
    request_hash,
    status_code,
    started_at,
    completed_at,
    result_transaction_id,
    response_snapshot,
    error_code,
    expires_at
  )
  values (
    v_command_id,
    p_organization_id,
    v_scope,
    v_idempotency_key,
    v_request_hash,
    'STARTED',
    v_recorded_at,
    null,
    null,
    '{}'::jsonb,
    null,
    null
  );

  v_effective_local_date :=
    (v_recorded_at at time zone v_organization_timezone)::date;

  v_transaction_no :=
    'REV-' ||
    to_char(v_effective_local_date, 'YYYYMMDD') ||
    '-' ||
    upper(
      substr(
        replace(v_reversal_transaction_id::text, '-', ''),
        1,
        8
      )
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
  values (
    v_reversal_transaction_id,
    p_organization_id,
    v_transaction_no,
    'REVERSAL',
    v_reason_id,
    'REVERSAL',
    v_channel_id,
    'MANUAL',
    'STOCK_TRANSACTION_REVERSAL',
    v_original.id,
    v_original.transaction_no,
    v_recorded_at,
    v_recorded_at,
    v_effective_local_date,
    v_actor_user_id,
    null,
    'ADMIN',
    v_correlation_id,
    v_command_id,
    v_original.id,
    v_note,
    v_metadata || jsonb_build_object(
      'originalTransactionId', v_original.id,
      'originalTransactionNo', v_original.transaction_no,
      'originalTransactionType', v_original.transaction_type_code,
      'originalSourceType', v_original.source_type_code,
      'originalSourceRef', v_original.source_ref_snapshot,
      'previewBasisHash', v_preview_basis_hash
    ),
    1
  );

  for v_line in
    select entry.*
    from inventory.stock_ledger_entries entry
    where entry.organization_id = p_organization_id
      and entry.transaction_id = p_original_transaction_id
    order by entry.ledger_seq
  loop
    select coalesce(sum(application.quantity_applied), 0)::bigint
    into v_applied_qty
    from inventory.stock_reversal_applications application
    where application.original_entry_id = v_line.id;

    v_remaining_qty := abs(v_line.quantity_delta) - v_applied_qty;

    if v_remaining_qty <= 0
       or v_remaining_qty <> abs(v_line.quantity_delta) then
      raise exception using errcode = 'P0001', message = 'ORIGINAL_TRANSACTION_ALREADY_REVERSED';
    end if;

    v_reversal_delta :=
      case
        when v_line.quantity_delta > 0 then -v_remaining_qty
        else v_remaining_qty
      end;

    v_reversal_entry_id := gen_random_uuid();

    insert into inventory.stock_ledger_entries (
      id,
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
    values (
      v_reversal_entry_id,
      p_organization_id,
      v_reversal_transaction_id,
      v_line.line_no,
      v_line.product_id,
      v_line.batch_id,
      v_line.product_sku_snapshot,
      v_line.batch_code_snapshot,
      v_line.expiry_date_snapshot,
      v_line.bucket_code,
      v_reversal_delta,
      'REVERSAL',
      v_line.pair_no,
      v_line.id::text,
      v_recorded_at,
      v_recorded_at,
      v_recorded_at
    )
    returning ledger_seq into v_ledger_seq;

    update inventory.stock_batch_balances balance
    set
      sellable_qty =
        balance.sellable_qty
        + case
            when v_line.bucket_code = 'SELLABLE'
              then v_reversal_delta
            else 0
          end,
      quarantine_qty =
        balance.quarantine_qty
        + case
            when v_line.bucket_code = 'QUARANTINE'
              then v_reversal_delta
            else 0
          end,
      damaged_qty =
        balance.damaged_qty
        + case
            when v_line.bucket_code = 'DAMAGED'
              then v_reversal_delta
            else 0
          end,
      last_ledger_seq = greatest(balance.last_ledger_seq, v_ledger_seq),
      updated_at = v_recorded_at,
      version = balance.version + 1
    where balance.organization_id = p_organization_id
      and balance.product_id = v_line.product_id
      and balance.batch_id = v_line.batch_id
      and (
        case v_line.bucket_code
          when 'SELLABLE' then balance.sellable_qty
          when 'QUARANTINE' then balance.quarantine_qty
          when 'DAMAGED' then balance.damaged_qty
        end
      ) + v_reversal_delta >= 0;

    if not found then
      raise exception using errcode = 'P0001', message = 'REVERSAL_NEGATIVE_BUCKET';
    end if;

    update inventory.stock_product_positions position
    set
      sellable_qty =
        position.sellable_qty
        + case
            when v_line.bucket_code = 'SELLABLE'
              then v_reversal_delta
            else 0
          end,
      quarantine_qty =
        position.quarantine_qty
        + case
            when v_line.bucket_code = 'QUARANTINE'
              then v_reversal_delta
            else 0
          end,
      damaged_qty =
        position.damaged_qty
        + case
            when v_line.bucket_code = 'DAMAGED'
              then v_reversal_delta
            else 0
          end,
      last_ledger_seq = greatest(position.last_ledger_seq, v_ledger_seq),
      updated_at = v_recorded_at,
      version = position.version + 1
    where position.organization_id = p_organization_id
      and position.product_id = v_line.product_id
      and position.sellable_qty
          + case
              when v_line.bucket_code = 'SELLABLE'
                then v_reversal_delta
              else 0
            end
          >= position.reserved_qty
      and position.quarantine_qty
          + case
              when v_line.bucket_code = 'QUARANTINE'
                then v_reversal_delta
              else 0
            end
          >= 0
      and position.damaged_qty
          + case
              when v_line.bucket_code = 'DAMAGED'
                then v_reversal_delta
              else 0
            end
          >= 0;

    if not found then
      raise exception using errcode = 'P0001', message = 'REVERSAL_RESERVED_CONFLICT';
    end if;

    insert into inventory.stock_reversal_applications (
      organization_id,
      original_transaction_id,
      reversal_transaction_id,
      original_entry_id,
      reversal_entry_id,
      quantity_applied,
      created_at
    )
    values (
      p_organization_id,
      v_original.id,
      v_reversal_transaction_id,
      v_line.id,
      v_reversal_entry_id,
      v_remaining_qty,
      v_recorded_at
    );

    v_line_count := v_line_count + 1;
    v_total_absolute_quantity :=
      v_total_absolute_quantity + v_remaining_qty;
  end loop;

  if v_line_count = 0 then
    raise exception using errcode = 'P0001', message = 'REVERSAL_ORIGINAL_ENTRIES_REQUIRED';
  end if;

  if exists (
    with affected as (
      select distinct
        entry.product_id,
        entry.batch_id
      from inventory.stock_ledger_entries entry
      where entry.organization_id = p_organization_id
        and entry.transaction_id = p_original_transaction_id
    ),
    ledger as (
      select
        affected.product_id,
        affected.batch_id,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'SELLABLE'
          ),
          0
        )::bigint as sellable_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'QUARANTINE'
          ),
          0
        )::bigint as quarantine_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'DAMAGED'
          ),
          0
        )::bigint as damaged_qty
      from affected
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = p_organization_id
       and entry.product_id = affected.product_id
       and entry.batch_id = affected.batch_id
      group by affected.product_id, affected.batch_id
    )
    select 1
    from ledger
    join inventory.stock_batch_balances balance
      on balance.organization_id = p_organization_id
     and balance.product_id = ledger.product_id
     and balance.batch_id = ledger.batch_id
    where balance.sellable_qty <> ledger.sellable_qty
       or balance.quarantine_qty <> ledger.quarantine_qty
       or balance.damaged_qty <> ledger.damaged_qty
  ) then
    raise exception using errcode = 'P0001', message = 'REVERSAL_PROJECTION_DRIFT';
  end if;

  if exists (
    with affected as (
      select distinct entry.product_id
      from inventory.stock_ledger_entries entry
      where entry.organization_id = p_organization_id
        and entry.transaction_id = p_original_transaction_id
    ),
    ledger as (
      select
        affected.product_id,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'SELLABLE'
          ),
          0
        )::bigint as sellable_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'QUARANTINE'
          ),
          0
        )::bigint as quarantine_qty,
        coalesce(
          sum(entry.quantity_delta) filter (
            where entry.bucket_code = 'DAMAGED'
          ),
          0
        )::bigint as damaged_qty
      from affected
      left join inventory.stock_ledger_entries entry
        on entry.organization_id = p_organization_id
       and entry.product_id = affected.product_id
      group by affected.product_id
    )
    select 1
    from ledger
    join inventory.stock_product_positions position
      on position.organization_id = p_organization_id
     and position.product_id = ledger.product_id
    where position.sellable_qty <> ledger.sellable_qty
       or position.quarantine_qty <> ledger.quarantine_qty
       or position.damaged_qty <> ledger.damaged_qty
  ) then
    raise exception using errcode = 'P0001', message = 'REVERSAL_PROJECTION_DRIFT';
  end if;

  v_response := jsonb_build_object(
    'status', 'REVERSED',
    'originalTransactionId', v_original.id,
    'originalTransactionNo', v_original.transaction_no,
    'originalTransactionType', v_original.transaction_type_code,
    'reversalTransactionId', v_reversal_transaction_id,
    'reversalTransactionNo', v_transaction_no,
    'lineCount', v_line_count,
    'totalAbsoluteQuantity', v_total_absolute_quantity,
    'previewBasisHash', v_preview_basis_hash,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'recordedAt', v_recorded_at,
    'actorUserId', v_actor_user_id
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    result_transaction_id = v_reversal_transaction_id,
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

grant usage on schema api to authenticated;

revoke all
on function api.preview_stock_transaction_reversal(uuid, uuid)
from public, anon, service_role;

grant execute
on function api.preview_stock_transaction_reversal(uuid, uuid)
to authenticated;

revoke all
on function api.reverse_stock_transaction(
  uuid,
  text,
  uuid,
  text,
  boolean,
  text,
  jsonb
)
from public, anon, service_role;

grant execute
on function api.reverse_stock_transaction(
  uuid,
  text,
  uuid,
  text,
  boolean,
  text,
  jsonb
)
to authenticated;

create or replace view api.stock_reversal_applications
with (security_invoker = true, security_barrier = true)
as
select
  application.id as reversal_application_id,
  application.organization_id,
  application.original_transaction_id,
  original_transaction.transaction_no as original_transaction_no,
  original_transaction.transaction_type_code as original_transaction_type_code,
  original_transaction.source_type_code as original_source_type_code,
  original_transaction.source_ref_snapshot as original_source_ref,
  application.reversal_transaction_id,
  reversal_transaction.transaction_no as reversal_transaction_no,
  application.original_entry_id,
  application.reversal_entry_id,
  original_entry.product_id,
  original_entry.batch_id,
  original_entry.product_sku_snapshot,
  original_entry.batch_code_snapshot,
  original_entry.expiry_date_snapshot,
  original_entry.bucket_code,
  original_entry.quantity_delta as original_quantity_delta,
  reversal_entry.quantity_delta as reversal_quantity_delta,
  application.quantity_applied,
  reversal_transaction.actor_user_id,
  reversal_transaction.process_name,
  reversal_transaction.note,
  application.created_at
from inventory.stock_reversal_applications application
join inventory.stock_transactions original_transaction
  on original_transaction.id = application.original_transaction_id
 and original_transaction.organization_id = application.organization_id
join inventory.stock_transactions reversal_transaction
  on reversal_transaction.id = application.reversal_transaction_id
 and reversal_transaction.organization_id = application.organization_id
join inventory.stock_ledger_entries original_entry
  on original_entry.id = application.original_entry_id
 and original_entry.organization_id = application.organization_id
join inventory.stock_ledger_entries reversal_entry
  on reversal_entry.id = application.reversal_entry_id
 and reversal_entry.organization_id = application.organization_id;

revoke all
on api.stock_reversal_applications
from public, anon;

grant select
on api.stock_reversal_applications
to authenticated, service_role;

alter default privileges in schema inventory
revoke all on tables from anon, authenticated;

commit;
