begin;

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
      and (
        batch.status_code = 'ACTIVE'
        or parameters.include_blocked_batches
      )
      and (
        batch.expiry_date >= p_as_of_date
        or parameters.include_expired_batches
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
      parameters.include_zero_system_balance,
      parameters.include_inactive_with_balance,
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
) from public, anon, authenticated;

create or replace function api.create_stocktake(
  p_organization_id uuid,
  p_idempotency_key text,
  p_title text,
  p_stocktake_type_code text,
  p_mode_code text,
  p_visibility_code text,
  p_scope jsonb,
  p_planned_at timestamptz default null,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_command_scope constant text := 'CREATE_STOCKTAKE';
  v_idempotency_key text;
  v_title text;
  v_stocktake_type_code text;
  v_mode_code text;
  v_visibility_code text;
  v_scope_input jsonb;
  v_scope_mode text;
  v_scope_normalized jsonb;
  v_bucket_codes jsonb;
  v_product_ids jsonb;
  v_batch_ids jsonb;
  v_include_zero boolean;
  v_include_inactive boolean;
  v_include_blocked boolean;
  v_include_expired boolean;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_organization_timezone text;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_command_id uuid := gen_random_uuid();
  v_stocktake_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_stocktake_no text;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_title := btrim(coalesce(p_title, ''));
  if v_title = '' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_TITLE_REQUIRED';
  end if;
  if length(v_title) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_TITLE_TOO_LONG';
  end if;

  v_stocktake_type_code :=
    upper(btrim(coalesce(p_stocktake_type_code, '')));
  if v_stocktake_type_code not in ('FULL', 'CYCLE', 'AD_HOC') then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_TYPE_NOT_SUPPORTED';
  end if;

  v_mode_code := upper(btrim(coalesce(p_mode_code, '')));
  if v_mode_code <> 'CONTINUOUS' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_MODE_NOT_SUPPORTED';
  end if;

  v_visibility_code :=
    upper(btrim(coalesce(p_visibility_code, '')));
  if v_visibility_code not in ('BLIND', 'NON_BLIND') then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_VISIBILITY_NOT_SUPPORTED';
  end if;

  v_scope_input := coalesce(p_scope, '{}'::jsonb);
  if jsonb_typeof(v_scope_input) is distinct from 'object'
     or v_scope_input = '{}'::jsonb then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_REQUIRED';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(v_scope_input) as scope_key(key)
    where scope_key.key not in (
      'mode',
      'productIds',
      'batchIds',
      'bucketCodes',
      'includeZeroSystemBalance',
      'includeInactiveWithBalance',
      'includeBlockedBatches',
      'includeExpiredBatches'
    )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_NOT_SUPPORTED';
  end if;

  if jsonb_typeof(v_scope_input -> 'mode') is distinct from 'string' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_REQUIRED';
  end if;

  v_scope_mode := upper(btrim(v_scope_input ->> 'mode'));
  if v_scope_mode not in (
    'ALL_ACTIVE_INVENTORY',
    'PRODUCTS',
    'BATCHES'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_NOT_SUPPORTED';
  end if;

  if jsonb_typeof(v_scope_input -> 'bucketCodes')
       is distinct from 'array'
     or jsonb_array_length(v_scope_input -> 'bucketCodes') = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_REQUIRED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_scope_input -> 'bucketCodes')
      as bucket(item)
    where jsonb_typeof(bucket.item) is distinct from 'string'
       or upper(btrim(bucket.item #>> '{}')) not in (
         'SELLABLE',
         'QUARANTINE',
         'DAMAGED'
       )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_NOT_SUPPORTED';
  end if;

  if (
    select count(*)
    from jsonb_array_elements_text(v_scope_input -> 'bucketCodes')
  ) <> (
    select count(distinct upper(btrim(bucket.value)))
    from jsonb_array_elements_text(v_scope_input -> 'bucketCodes')
      as bucket(value)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_DUPLICATE_ENTITY';
  end if;

  select jsonb_agg(bucket_code order by bucket_order)
  into v_bucket_codes
  from (
    select distinct
      upper(btrim(bucket.value)) as bucket_code,
      case upper(btrim(bucket.value))
        when 'SELLABLE' then 1
        when 'QUARANTINE' then 2
        when 'DAMAGED' then 3
      end as bucket_order
    from jsonb_array_elements_text(v_scope_input -> 'bucketCodes')
      as bucket(value)
  ) normalized_bucket;

  if v_scope_input ? 'productIds'
     and jsonb_typeof(v_scope_input -> 'productIds')
       is distinct from 'array' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_NOT_SUPPORTED';
  end if;

  if v_scope_input ? 'batchIds'
     and jsonb_typeof(v_scope_input -> 'batchIds')
       is distinct from 'array' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_NOT_SUPPORTED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(
      coalesce(v_scope_input -> 'productIds', '[]'::jsonb)
    ) as product(item)
    where jsonb_typeof(product.item) is distinct from 'string'
       or (product.item #>> '{}')
         !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_NOT_SUPPORTED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(
      coalesce(v_scope_input -> 'batchIds', '[]'::jsonb)
    ) as batch(item)
    where jsonb_typeof(batch.item) is distinct from 'string'
       or (batch.item #>> '{}')
         !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_NOT_SUPPORTED';
  end if;

  if (
    select count(*)
    from jsonb_array_elements_text(
      coalesce(v_scope_input -> 'productIds', '[]'::jsonb)
    )
  ) <> (
    select count(distinct lower(product.value))
    from jsonb_array_elements_text(
      coalesce(v_scope_input -> 'productIds', '[]'::jsonb)
    ) as product(value)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_DUPLICATE_ENTITY';
  end if;

  if (
    select count(*)
    from jsonb_array_elements_text(
      coalesce(v_scope_input -> 'batchIds', '[]'::jsonb)
    )
  ) <> (
    select count(distinct lower(batch.value))
    from jsonb_array_elements_text(
      coalesce(v_scope_input -> 'batchIds', '[]'::jsonb)
    ) as batch(value)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_DUPLICATE_ENTITY';
  end if;

  select coalesce(
    jsonb_agg(product_id order by product_id),
    '[]'::jsonb
  )
  into v_product_ids
  from (
    select lower(product.value) as product_id
    from jsonb_array_elements_text(
      coalesce(v_scope_input -> 'productIds', '[]'::jsonb)
    ) as product(value)
  ) normalized_product;

  select coalesce(
    jsonb_agg(batch_id order by batch_id),
    '[]'::jsonb
  )
  into v_batch_ids
  from (
    select lower(batch.value) as batch_id
    from jsonb_array_elements_text(
      coalesce(v_scope_input -> 'batchIds', '[]'::jsonb)
    ) as batch(value)
  ) normalized_batch;

  if v_scope_mode = 'ALL_ACTIVE_INVENTORY'
     and (
       jsonb_array_length(v_product_ids) > 0
       or jsonb_array_length(v_batch_ids) > 0
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_NOT_SUPPORTED';
  end if;

  if v_scope_mode = 'PRODUCTS'
     and (
       jsonb_array_length(v_product_ids) = 0
       or jsonb_array_length(v_batch_ids) > 0
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_REQUIRED';
  end if;

  if v_scope_mode = 'BATCHES'
     and (
       jsonb_array_length(v_batch_ids) = 0
       or jsonb_array_length(v_product_ids) > 0
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_REQUIRED';
  end if;

  if exists (
    select 1
    from (
      values
        ('includeZeroSystemBalance'),
        ('includeInactiveWithBalance'),
        ('includeBlockedBatches'),
        ('includeExpiredBatches')
    ) as boolean_key(key)
    where v_scope_input ? boolean_key.key
      and jsonb_typeof(v_scope_input -> boolean_key.key)
        is distinct from 'boolean'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_NOT_SUPPORTED';
  end if;

  v_include_zero :=
    coalesce(
      (v_scope_input ->> 'includeZeroSystemBalance')::boolean,
      false
    );
  v_include_inactive :=
    coalesce(
      (v_scope_input ->> 'includeInactiveWithBalance')::boolean,
      false
    );
  v_include_blocked :=
    coalesce(
      (v_scope_input ->> 'includeBlockedBatches')::boolean,
      false
    );
  v_include_expired :=
    coalesce(
      (v_scope_input ->> 'includeExpiredBatches')::boolean,
      false
    );

  v_scope_normalized := jsonb_build_object(
    'mode', v_scope_mode,
    'bucketCodes', v_bucket_codes,
    'includeZeroSystemBalance', v_include_zero,
    'includeInactiveWithBalance', v_include_inactive,
    'includeBlockedBatches', v_include_blocked,
    'includeExpiredBatches', v_include_expired
  );

  if v_scope_mode = 'PRODUCTS' then
    v_scope_normalized :=
      v_scope_normalized
      || jsonb_build_object('productIds', v_product_ids);
  elsif v_scope_mode = 'BATCHES' then
    v_scope_normalized :=
      v_scope_normalized
      || jsonb_build_object('batchIds', v_batch_ids);
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');
  if v_note is not null and length(v_note) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_NOTE_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_METADATA_MUST_BE_OBJECT';
  end if;

  select organization.timezone
  into v_organization_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_NOT_FOUND';
  end if;

  if v_jwt_role = 'anon'
     or (
       v_jwt_role = 'authenticated'
       and v_actor_user_id is null
     ) then
    raise exception using
      errcode = '42501',
      message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using
      errcode = '42501',
      message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id()
         is distinct from p_organization_id then
      raise exception using
        errcode = '42501',
        message = 'ORGANIZATION_ACCESS_DENIED';
    end if;
    v_process_name := null;
  else
    v_process_name := 'api.create_stocktake';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'title', v_title,
          'stocktakeTypeCode', v_stocktake_type_code,
          'modeCode', v_mode_code,
          'visibilityCode', v_visibility_code,
          'scope', v_scope_normalized,
          'plannedAt', p_planned_at,
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
      p_organization_id::text
        || ':'
        || v_command_scope
        || ':'
        || v_idempotency_key,
      0::bigint
    )
  );

  select command.*
  into v_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id
    and command.scope = v_command_scope
    and command.key = v_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> v_request_hash then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_KEY_REUSED';
    end if;

    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot;
    end if;

    if v_existing.status_code = 'STARTED' then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  v_stocktake_no :=
    'STK-'
    || to_char(
      v_recorded_at at time zone v_organization_timezone,
      'YYYYMMDD-HH24MISS'
    )
    || '-'
    || upper(
      substr(
        replace(v_stocktake_id::text, '-', ''),
        1,
        8
      )
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
    result_transaction_id,
    response_snapshot,
    error_code,
    expires_at
  )
  values (
    v_command_id,
    p_organization_id,
    v_command_scope,
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

  insert into operations.stocktakes (
    id,
    organization_id,
    stocktake_no,
    title,
    stocktake_type_code,
    mode_code,
    visibility_code,
    status_code,
    scope_definition,
    tolerance_policy_snapshot,
    rule_version,
    timezone_snapshot,
    planned_at,
    snapshot_ledger_seq,
    started_at,
    counting_completed_at,
    approved_at,
    posted_at,
    stock_transaction_id,
    reconciliation_run_id,
    created_by,
    process_name,
    create_idempotency_command_id,
    note,
    metadata,
    created_at,
    updated_at,
    version_no
  )
  values (
    v_stocktake_id,
    p_organization_id,
    v_stocktake_no,
    v_title,
    v_stocktake_type_code,
    v_mode_code,
    v_visibility_code,
    'DRAFT',
    v_scope_normalized,
    '{"units": 0, "percent": 0}'::jsonb,
    'stocktake-continuous-v1',
    v_organization_timezone,
    p_planned_at,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    v_actor_user_id,
    v_process_name,
    v_command_id,
    v_note,
    v_metadata,
    v_recorded_at,
    v_recorded_at,
    1
  );

  v_response := jsonb_build_object(
    'status', 'DRAFT',
    'stocktakeId', v_stocktake_id,
    'stocktakeNo', v_stocktake_no,
    'stocktakeTypeCode', v_stocktake_type_code,
    'modeCode', v_mode_code,
    'visibilityCode', v_visibility_code,
    'scope', v_scope_normalized,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'createdAt', v_recorded_at
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

create or replace function api.prepare_stocktake(
  p_organization_id uuid,
  p_idempotency_key text,
  p_stocktake_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_command_scope constant text := 'PREPARE_STOCKTAKE';
  v_idempotency_key text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_stocktake operations.stocktakes%rowtype;
  v_organization_timezone text;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_command_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_as_of_date date;
  v_validation_ledger_seq bigint;
  v_scope_line_count bigint;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_stocktake_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_ID_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_METADATA_MUST_BE_OBJECT';
  end if;

  select organization.timezone
  into v_organization_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_NOT_FOUND';
  end if;

  if v_jwt_role = 'anon'
     or (
       v_jwt_role = 'authenticated'
       and v_actor_user_id is null
     ) then
    raise exception using
      errcode = '42501',
      message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using
      errcode = '42501',
      message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id()
         is distinct from p_organization_id then
      raise exception using
        errcode = '42501',
        message = 'ORGANIZATION_ACCESS_DENIED';
    end if;
    v_process_name := null;
  else
    v_process_name := 'api.prepare_stocktake';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'stocktakeId', p_stocktake_id,
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
      p_organization_id::text
        || ':'
        || v_command_scope
        || ':'
        || v_idempotency_key,
      0::bigint
    )
  );

  select command.*
  into v_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id
    and command.scope = v_command_scope
    and command.key = v_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> v_request_hash then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_KEY_REUSED';
    end if;

    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot;
    end if;

    if v_existing.status_code = 'STARTED' then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
        || ':STOCKTAKE:'
        || p_stocktake_id::text,
      0::bigint
    )
  );

  select stocktake.*
  into v_stocktake
  from operations.stocktakes stocktake
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_NOT_FOUND';
  end if;

  if v_stocktake.status_code <> 'DRAFT' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_INVALID_STATE';
  end if;

  if v_stocktake.mode_code <> 'CONTINUOUS' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_MODE_NOT_SUPPORTED';
  end if;

  if v_stocktake.scope_definition ->> 'mode' = 'PRODUCTS'
     and exists (
       select 1
       from jsonb_array_elements_text(
         v_stocktake.scope_definition -> 'productIds'
       ) as requested(value)
       where not exists (
         select 1
         from catalog.products product
         where product.organization_id = p_organization_id
           and product.id = requested.value::uuid
       )
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_ENTITY_NOT_FOUND';
  end if;

  if v_stocktake.scope_definition ->> 'mode' = 'BATCHES'
     and exists (
       select 1
       from jsonb_array_elements_text(
         v_stocktake.scope_definition -> 'batchIds'
       ) as requested(value)
       where not exists (
         select 1
         from catalog.product_batches batch
         where batch.organization_id = p_organization_id
           and batch.id = requested.value::uuid
       )
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_ENTITY_NOT_FOUND';
  end if;

  select coalesce(max(entry.ledger_seq), 0)
  into v_validation_ledger_seq
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  v_as_of_date :=
    (
      coalesce(v_stocktake.planned_at, v_recorded_at)
      at time zone v_organization_timezone
    )::date;

  select count(*)
  into v_scope_line_count
  from operations.resolve_stocktake_scope(
    p_organization_id,
    v_stocktake.scope_definition,
    v_as_of_date,
    v_validation_ledger_seq
  );

  if v_scope_line_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SCOPE_EMPTY';
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
    v_command_scope,
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

  update operations.stocktakes stocktake
  set
    status_code = 'READY',
    metadata =
      stocktake.metadata
      || jsonb_build_object(
        'preparedAt', v_recorded_at,
        'prepareMetadata', v_metadata,
        'preparedByUserId', v_actor_user_id,
        'preparedByProcessName', v_process_name
      ),
    updated_at = v_recorded_at,
    version_no = stocktake.version_no + 1
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id;

  v_response := jsonb_build_object(
    'status', 'READY',
    'stocktakeId', p_stocktake_id,
    'stocktakeNo', v_stocktake.stocktake_no,
    'scopeLineCount', v_scope_line_count,
    'validationLedgerSeq', v_validation_ledger_seq,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'preparedAt', v_recorded_at
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

create or replace function api.start_stocktake(
  p_organization_id uuid,
  p_idempotency_key text,
  p_stocktake_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, extensions
as $$
declare
  v_command_scope constant text := 'START_STOCKTAKE';
  v_idempotency_key text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_stocktake operations.stocktakes%rowtype;
  v_organization_timezone text;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_command_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_as_of_date date;
  v_snapshot_ledger_seq bigint;
  v_line_count bigint;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_REQUIRED';
  end if;

  if p_stocktake_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_ID_REQUIRED';
  end if;

  v_idempotency_key := btrim(coalesce(p_idempotency_key, ''));
  if v_idempotency_key = '' then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_METADATA_MUST_BE_OBJECT';
  end if;

  select organization.timezone
  into v_organization_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'ORGANIZATION_NOT_FOUND';
  end if;

  if v_jwt_role = 'anon'
     or (
       v_jwt_role = 'authenticated'
       and v_actor_user_id is null
     ) then
    raise exception using
      errcode = '42501',
      message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using
      errcode = '42501',
      message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id()
         is distinct from p_organization_id then
      raise exception using
        errcode = '42501',
        message = 'ORGANIZATION_ACCESS_DENIED';
    end if;
    v_process_name := null;
  else
    v_process_name := 'api.start_stocktake';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'stocktakeId', p_stocktake_id,
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
      p_organization_id::text
        || ':'
        || v_command_scope
        || ':'
        || v_idempotency_key,
      0::bigint
    )
  );

  select command.*
  into v_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id
    and command.scope = v_command_scope
    and command.key = v_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> v_request_hash then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_KEY_REUSED';
    end if;

    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot;
    end if;

    if v_existing.status_code = 'STARTED' then
      raise exception using
        errcode = 'P0001',
        message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text || ':STOCKTAKE_START',
      0::bigint
    )
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
        || ':STOCKTAKE:'
        || p_stocktake_id::text,
      0::bigint
    )
  );

  select stocktake.*
  into v_stocktake
  from operations.stocktakes stocktake
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_NOT_FOUND';
  end if;

  if v_stocktake.status_code <> 'READY' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_INVALID_STATE';
  end if;

  if v_stocktake.mode_code <> 'CONTINUOUS' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_MODE_NOT_SUPPORTED';
  end if;

  if exists (
    select 1
    from operations.stocktake_lines line
    where line.organization_id = p_organization_id
      and line.stocktake_id = p_stocktake_id
  ) or exists (
    select 1
    from operations.stocktake_snapshots snapshot
    where snapshot.organization_id = p_organization_id
      and snapshot.stocktake_id = p_stocktake_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SNAPSHOT_INCOMPLETE';
  end if;

  lock table inventory.stock_ledger_entries in share mode;

  select coalesce(max(entry.ledger_seq), 0)
  into v_snapshot_ledger_seq
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  v_as_of_date :=
    (
      coalesce(v_stocktake.planned_at, v_recorded_at)
      at time zone v_organization_timezone
    )::date;

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
    v_command_scope,
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

  insert into operations.stocktake_lines (
    id,
    organization_id,
    stocktake_id,
    line_no,
    product_id,
    batch_id,
    bucket_code,
    product_sku_snapshot,
    product_name_snapshot,
    batch_code_snapshot,
    expiry_date_snapshot,
    system_qty_at_snapshot,
    final_attempt_id,
    final_physical_qty,
    expected_qty_at_count,
    variance_qty,
    count_cutoff_ledger_seq,
    expected_formula_version,
    count_attempt_no,
    count_status_code,
    review_status_code,
    reason_code,
    review_note,
    exception_code,
    created_at,
    updated_at,
    version_no
  )
  select
    gen_random_uuid(),
    p_organization_id,
    p_stocktake_id,
    row_number() over (
      order by
        resolved.product_sku_snapshot,
        resolved.expiry_date_snapshot,
        resolved.batch_code_snapshot,
        case resolved.bucket_code
          when 'SELLABLE' then 1
          when 'QUARANTINE' then 2
          when 'DAMAGED' then 3
          else 99
        end,
        resolved.batch_id
    )::integer,
    resolved.product_id,
    resolved.batch_id,
    resolved.bucket_code,
    resolved.product_sku_snapshot,
    resolved.product_name_snapshot,
    resolved.batch_code_snapshot,
    resolved.expiry_date_snapshot,
    resolved.system_qty_at_snapshot,
    null,
    null,
    null,
    null,
    null,
    null,
    0,
    'PENDING',
    'PENDING',
    null,
    null,
    null,
    v_recorded_at,
    v_recorded_at,
    1
  from operations.resolve_stocktake_scope(
    p_organization_id,
    v_stocktake.scope_definition,
    v_as_of_date,
    v_snapshot_ledger_seq
  ) resolved;

  get diagnostics v_line_count = row_count;

  if v_line_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SNAPSHOT_INCOMPLETE';
  end if;

  insert into operations.stocktake_snapshots (
    id,
    organization_id,
    stocktake_id,
    stocktake_line_id,
    product_id,
    batch_id,
    bucket_code,
    snapshot_ledger_seq,
    system_qty_at_snapshot,
    product_sku_snapshot,
    product_name_snapshot,
    batch_code_snapshot,
    expiry_date_snapshot,
    created_at
  )
  select
    gen_random_uuid(),
    line.organization_id,
    line.stocktake_id,
    line.id,
    line.product_id,
    line.batch_id,
    line.bucket_code,
    v_snapshot_ledger_seq,
    line.system_qty_at_snapshot,
    line.product_sku_snapshot,
    line.product_name_snapshot,
    line.batch_code_snapshot,
    line.expiry_date_snapshot,
    v_recorded_at
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
  order by line.line_no;

  if (
    select count(*)
    from operations.stocktake_snapshots snapshot
    where snapshot.organization_id = p_organization_id
      and snapshot.stocktake_id = p_stocktake_id
  ) <> v_line_count then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SNAPSHOT_INCOMPLETE';
  end if;

  update operations.stocktakes stocktake
  set
    status_code = 'COUNTING',
    snapshot_ledger_seq = v_snapshot_ledger_seq,
    started_at = v_recorded_at,
    metadata =
      stocktake.metadata
      || jsonb_build_object(
        'startedAt', v_recorded_at,
        'startMetadata', v_metadata,
        'startedByUserId', v_actor_user_id,
        'startedByProcessName', v_process_name,
        'snapshotSource', 'LEDGER'
      ),
    updated_at = v_recorded_at,
    version_no = stocktake.version_no + 1
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id;

  v_response := jsonb_build_object(
    'status', 'COUNTING',
    'stocktakeId', p_stocktake_id,
    'stocktakeNo', v_stocktake.stocktake_no,
    'snapshotLedgerSeq', v_snapshot_ledger_seq,
    'snapshotSource', 'LEDGER',
    'lineCount', v_line_count,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'startedAt', v_recorded_at
  );

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = clock_timestamp(),
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

grant usage on schema api to authenticated, service_role;

revoke all on function api.create_stocktake(
  uuid,
  text,
  text,
  text,
  text,
  text,
  jsonb,
  timestamptz,
  text,
  jsonb
) from public, anon;

grant execute on function api.create_stocktake(
  uuid,
  text,
  text,
  text,
  text,
  text,
  jsonb,
  timestamptz,
  text,
  jsonb
) to authenticated, service_role;

revoke all on function api.prepare_stocktake(
  uuid,
  text,
  uuid,
  jsonb
) from public, anon;

grant execute on function api.prepare_stocktake(
  uuid,
  text,
  uuid,
  jsonb
) to authenticated, service_role;

revoke all on function api.start_stocktake(
  uuid,
  text,
  uuid,
  jsonb
) from public, anon;

grant execute on function api.start_stocktake(
  uuid,
  text,
  uuid,
  jsonb
) to authenticated, service_role;

commit;
