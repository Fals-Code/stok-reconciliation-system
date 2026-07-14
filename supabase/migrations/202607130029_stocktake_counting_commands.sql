begin;

create or replace function operations.calculate_stocktake_expected(
  p_organization_id uuid,
  p_stocktake_id uuid,
  p_stocktake_line_id uuid,
  p_count_cutoff_ledger_seq bigint
)
returns bigint
language sql
stable
security invoker
set search_path = pg_catalog, inventory, operations
as $$
  select
    line.system_qty_at_snapshot
    + coalesce(
        sum(entry.quantity_delta) filter (
          where entry.ledger_seq > stocktake.snapshot_ledger_seq
            and entry.ledger_seq <= p_count_cutoff_ledger_seq
        ),
        0
      )::bigint
  from operations.stocktake_lines line
  join operations.stocktakes stocktake
    on stocktake.organization_id = line.organization_id
   and stocktake.id = line.stocktake_id
  left join inventory.stock_ledger_entries entry
    on entry.organization_id = line.organization_id
   and entry.product_id = line.product_id
   and entry.batch_id = line.batch_id
   and entry.bucket_code = line.bucket_code
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
    and line.id = p_stocktake_line_id
    and stocktake.snapshot_ledger_seq is not null
    and p_count_cutoff_ledger_seq >= stocktake.snapshot_ledger_seq
  group by
    line.system_qty_at_snapshot,
    stocktake.snapshot_ledger_seq;
$$;

revoke all on function operations.calculate_stocktake_expected(
  uuid,
  uuid,
  uuid,
  bigint
) from public, anon, authenticated;

create or replace function api.submit_stocktake_count(
  p_organization_id uuid,
  p_idempotency_key text,
  p_stocktake_id uuid,
  p_stocktake_line_id uuid,
  p_physical_qty bigint,
  p_zero_confirmed boolean default false,
  p_count_method_code text default 'MANUAL_ENTRY',
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, inventory, operations, extensions
as $$
declare
  v_command_scope constant text := 'SUBMIT_STOCKTAKE_COUNT';
  v_formula_version constant text := 'continuous-ledger-cutoff-v1';
  v_idempotency_key text;
  v_count_method_code text;
  v_note text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_stocktake operations.stocktakes%rowtype;
  v_line operations.stocktake_lines%rowtype;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_command_id uuid := gen_random_uuid();
  v_attempt_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_count_cutoff_ledger_seq bigint;
  v_expected_qty bigint;
  v_variance_qty bigint;
  v_attempt_no integer;
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

  if p_stocktake_line_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_LINE_ID_REQUIRED';
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

  if p_physical_qty is null or p_physical_qty < 0 then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_INVALID_PHYSICAL_QTY';
  end if;

  if p_physical_qty = 0 and not coalesce(p_zero_confirmed, false) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_ZERO_CONFIRMATION_REQUIRED';
  end if;

  v_count_method_code :=
    upper(btrim(coalesce(p_count_method_code, '')));
  if v_count_method_code not in (
    'MANUAL_ENTRY',
    'SCANNER',
    'IMPORT'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_COUNT_METHOD_NOT_SUPPORTED';
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

  if not exists (
    select 1
    from app.organizations organization
    where organization.id = p_organization_id
      and organization.is_active
  ) then
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
    v_process_name := 'api.submit_stocktake_count';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'stocktakeId', p_stocktake_id,
          'stocktakeLineId', p_stocktake_line_id,
          'physicalQty', p_physical_qty,
          'zeroConfirmed', coalesce(p_zero_confirmed, false),
          'countMethodCode', v_count_method_code,
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

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
        || ':STOCKTAKE:'
        || p_stocktake_id::text,
      0::bigint
    )
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
        || ':STOCKTAKE_LINE:'
        || p_stocktake_line_id::text,
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

  if v_stocktake.status_code <> 'COUNTING' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_INVALID_STATE';
  end if;

  if v_stocktake.mode_code <> 'CONTINUOUS' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_MODE_NOT_SUPPORTED';
  end if;

  if v_stocktake.snapshot_ledger_seq is null then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SNAPSHOT_INCOMPLETE';
  end if;

  select line.*
  into v_line
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
    and line.id = p_stocktake_line_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_LINE_NOT_FOUND';
  end if;

  if v_line.count_status_code = 'COUNTED' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_COUNT_CONFLICT';
  end if;

  if v_line.count_status_code not in (
    'PENDING',
    'RECOUNT_REQUESTED'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_COUNT_CONFLICT';
  end if;

  lock table inventory.stock_ledger_entries in share mode;

  select coalesce(max(entry.ledger_seq), 0)
  into v_count_cutoff_ledger_seq
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  if v_count_cutoff_ledger_seq < v_stocktake.snapshot_ledger_seq then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_SNAPSHOT_INCOMPLETE';
  end if;

  select operations.calculate_stocktake_expected(
    p_organization_id,
    p_stocktake_id,
    p_stocktake_line_id,
    v_count_cutoff_ledger_seq
  )
  into v_expected_qty;

  if v_expected_qty is null then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_LINE_NOT_FOUND';
  end if;

  v_attempt_no := v_line.count_attempt_no + 1;
  v_variance_qty := p_physical_qty - v_expected_qty;

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

  insert into operations.stocktake_count_attempts (
    id,
    organization_id,
    stocktake_id,
    stocktake_line_id,
    attempt_no,
    physical_qty,
    counted_at,
    count_cutoff_ledger_seq,
    expected_qty_at_count,
    variance_qty,
    expected_formula_version,
    counted_by,
    process_name,
    count_method_code,
    zero_confirmed,
    note,
    idempotency_key,
    request_hash,
    status_code,
    created_at
  )
  values (
    v_attempt_id,
    p_organization_id,
    p_stocktake_id,
    p_stocktake_line_id,
    v_attempt_no,
    p_physical_qty,
    v_recorded_at,
    v_count_cutoff_ledger_seq,
    v_expected_qty,
    v_variance_qty,
    v_formula_version,
    v_actor_user_id,
    v_process_name,
    v_count_method_code,
    coalesce(p_zero_confirmed, false),
    v_note,
    v_idempotency_key,
    v_request_hash,
    'VALID',
    v_recorded_at
  );

  update operations.stocktake_lines line
  set
    final_attempt_id = v_attempt_id,
    final_physical_qty = p_physical_qty,
    expected_qty_at_count = v_expected_qty,
    variance_qty = v_variance_qty,
    count_cutoff_ledger_seq = v_count_cutoff_ledger_seq,
    expected_formula_version = v_formula_version,
    count_attempt_no = v_attempt_no,
    count_status_code = 'COUNTED',
    review_status_code = 'READY',
    reason_code = null,
    review_note = null,
    exception_code = null,
    updated_at = v_recorded_at,
    version_no = line.version_no + 1
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
    and line.id = p_stocktake_line_id;

  v_response := jsonb_build_object(
    'status', 'COUNTED',
    'stocktakeId', p_stocktake_id,
    'stocktakeLineId', p_stocktake_line_id,
    'countAttemptId', v_attempt_id,
    'attemptNo', v_attempt_no,
    'physicalQty', p_physical_qty,
    'countCutoffLedgerSeq', v_count_cutoff_ledger_seq,
    'countMethodCode', v_count_method_code,
    'zeroConfirmed', coalesce(p_zero_confirmed, false),
    'countStatusCode', 'COUNTED',
    'reviewStatusCode', 'READY',
    'visibilityCode', v_stocktake.visibility_code,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'countedAt', v_recorded_at
  );

  if v_stocktake.visibility_code = 'NON_BLIND' then
    v_response :=
      v_response
      || jsonb_build_object(
        'expectedQty', v_expected_qty,
        'varianceQty', v_variance_qty,
        'expectedFormulaVersion', v_formula_version
      );
  end if;

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

create or replace function api.request_stocktake_recount(
  p_organization_id uuid,
  p_idempotency_key text,
  p_stocktake_id uuid,
  p_stocktake_line_id uuid,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, inventory, operations, extensions
as $$
declare
  v_command_scope constant text := 'REQUEST_STOCKTAKE_RECOUNT';
  v_idempotency_key text;
  v_reason text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_stocktake operations.stocktakes%rowtype;
  v_line operations.stocktake_lines%rowtype;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_command_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
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

  if p_stocktake_line_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_LINE_ID_REQUIRED';
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

  v_reason := btrim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_RECOUNT_REASON_REQUIRED';
  end if;
  if length(v_reason) > 2000 then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_RECOUNT_REASON_TOO_LONG';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_METADATA_MUST_BE_OBJECT';
  end if;

  if not exists (
    select 1
    from app.organizations organization
    where organization.id = p_organization_id
      and organization.is_active
  ) then
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
    v_process_name := 'api.request_stocktake_recount';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'stocktakeId', p_stocktake_id,
          'stocktakeLineId', p_stocktake_line_id,
          'reason', v_reason,
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

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
        || ':STOCKTAKE_LINE:'
        || p_stocktake_line_id::text,
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

  if v_stocktake.status_code <> 'COUNTING' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_INVALID_STATE';
  end if;

  select line.*
  into v_line
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
    and line.id = p_stocktake_line_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_LINE_NOT_FOUND';
  end if;

  if v_line.count_status_code <> 'COUNTED'
     or v_line.final_attempt_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_COUNT_CONFLICT';
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

  update operations.stocktake_lines line
  set
    count_status_code = 'RECOUNT_REQUESTED',
    review_status_code = 'PENDING',
    reason_code = 'MANUAL_RECOUNT',
    review_note = v_reason,
    exception_code = null,
    updated_at = v_recorded_at,
    version_no = line.version_no + 1
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id
    and line.id = p_stocktake_line_id;

  v_response := jsonb_build_object(
    'status', 'RECOUNT_REQUESTED',
    'stocktakeId', p_stocktake_id,
    'stocktakeLineId', p_stocktake_line_id,
    'currentAttemptNo', v_line.count_attempt_no,
    'currentCountAttemptId', v_line.final_attempt_id,
    'reason', v_reason,
    'countStatusCode', 'RECOUNT_REQUESTED',
    'reviewStatusCode', 'PENDING',
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'requestedAt', v_recorded_at,
    'requestedByUserId', v_actor_user_id,
    'requestedByProcessName', v_process_name
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

create or replace function api.complete_stocktake_counting(
  p_organization_id uuid,
  p_idempotency_key text,
  p_stocktake_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, inventory, operations, extensions
as $$
declare
  v_command_scope constant text := 'COMPLETE_STOCKTAKE_COUNTING';
  v_idempotency_key text;
  v_metadata jsonb;
  v_request_hash text;
  v_existing inventory.idempotency_commands%rowtype;
  v_stocktake operations.stocktakes%rowtype;
  v_actor_user_id uuid := auth.uid();
  v_process_name text;
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );
  v_command_id uuid := gen_random_uuid();
  v_recorded_at timestamptz := clock_timestamp();
  v_line_count bigint;
  v_counted_line_count bigint;
  v_variance_line_count bigint;
  v_total_variance_qty bigint;
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

  if not exists (
    select 1
    from app.organizations organization
    where organization.id = p_organization_id
      and organization.is_active
  ) then
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
    v_process_name := 'api.complete_stocktake_counting';
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

  if v_stocktake.status_code <> 'COUNTING' then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_INVALID_STATE';
  end if;

  select
    count(*),
    count(*) filter (
      where line.count_status_code = 'COUNTED'
        and line.final_attempt_id is not null
    ),
    count(*) filter (
      where line.variance_qty is not null
        and line.variance_qty <> 0
    ),
    coalesce(sum(line.variance_qty), 0)::bigint
  into
    v_line_count,
    v_counted_line_count,
    v_variance_line_count,
    v_total_variance_qty
  from operations.stocktake_lines line
  where line.organization_id = p_organization_id
    and line.stocktake_id = p_stocktake_id;

  if v_line_count = 0
     or v_counted_line_count <> v_line_count then
    raise exception using
      errcode = 'P0001',
      message = 'STOCKTAKE_COUNT_REQUIRED';
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
    status_code = 'REVIEW',
    counting_completed_at = v_recorded_at,
    metadata =
      stocktake.metadata
      || jsonb_build_object(
        'countingCompletedAt', v_recorded_at,
        'completeCountingMetadata', v_metadata,
        'countingCompletedByUserId', v_actor_user_id,
        'countingCompletedByProcessName', v_process_name
      ),
    updated_at = v_recorded_at,
    version_no = stocktake.version_no + 1
  where stocktake.organization_id = p_organization_id
    and stocktake.id = p_stocktake_id;

  v_response := jsonb_build_object(
    'status', 'REVIEW',
    'stocktakeId', p_stocktake_id,
    'stocktakeNo', v_stocktake.stocktake_no,
    'lineCount', v_line_count,
    'countedLineCount', v_counted_line_count,
    'varianceLineCount', v_variance_line_count,
    'totalVarianceQty', v_total_variance_qty,
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'countingCompletedAt', v_recorded_at
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


create or replace view api.stocktake_list
with (
  security_invoker = true,
  security_barrier = true
)
as
select
  stocktake.id as stocktake_id,
  stocktake.organization_id,
  stocktake.stocktake_no,
  stocktake.title,
  stocktake.stocktake_type_code,
  stocktake.mode_code,
  stocktake.visibility_code,
  stocktake.status_code,
  stocktake.planned_at,
  stocktake.snapshot_ledger_seq,
  stocktake.started_at,
  stocktake.counting_completed_at,
  stocktake.created_at,
  stocktake.updated_at,
  stocktake.version_no,
  coalesce(summary.line_count, 0) as line_count,
  coalesce(summary.counted_line_count, 0) as counted_line_count,
  case
    when stocktake.visibility_code = 'BLIND'
     and stocktake.status_code = 'COUNTING'
    then null::bigint
    else coalesce(summary.variance_line_count, 0)
  end as variance_line_count
from operations.stocktakes stocktake
left join lateral (
  select
    count(*) as line_count,
    count(*) filter (
      where line.count_status_code = 'COUNTED'
    ) as counted_line_count,
    count(*) filter (
      where line.variance_qty is not null
        and line.variance_qty <> 0
    ) as variance_line_count
  from operations.stocktake_lines line
  where line.organization_id = stocktake.organization_id
    and line.stocktake_id = stocktake.id
) summary on true;

create or replace view api.stocktake_review_lines
with (security_invoker = true)
as
select
  line.id as stocktake_line_id,
  line.organization_id,
  line.stocktake_id,
  line.line_no,
  line.product_id,
  line.batch_id,
  line.bucket_code,
  line.product_sku_snapshot,
  line.product_name_snapshot,
  line.batch_code_snapshot,
  line.expiry_date_snapshot,
  line.system_qty_at_snapshot,
  line.final_attempt_id,
  line.final_physical_qty,
  line.expected_qty_at_count,
  line.variance_qty,
  line.count_cutoff_ledger_seq,
  line.expected_formula_version,
  line.count_attempt_no,
  line.count_status_code,
  line.review_status_code,
  line.reason_code,
  line.review_note,
  line.exception_code,
  line.created_at,
  line.updated_at,
  line.version_no
from operations.stocktake_lines line;

create or replace view api.stocktake_count_attempts
with (security_invoker = true)
as
select
  attempt.id as count_attempt_id,
  attempt.organization_id,
  attempt.stocktake_id,
  attempt.stocktake_line_id,
  attempt.attempt_no,
  attempt.physical_qty,
  attempt.counted_at,
  attempt.count_cutoff_ledger_seq,
  attempt.expected_qty_at_count,
  attempt.variance_qty,
  attempt.expected_formula_version,
  attempt.counted_by,
  attempt.process_name,
  attempt.count_method_code,
  attempt.zero_confirmed,
  attempt.note,
  attempt.idempotency_key,
  attempt.request_hash,
  attempt.status_code,
  attempt.created_at
from operations.stocktake_count_attempts attempt;

grant usage on schema api to authenticated, service_role;

grant select
on api.stocktake_list,
   api.stocktake_review_lines,
   api.stocktake_count_attempts
to authenticated, service_role;


revoke all on function api.submit_stocktake_count(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  boolean,
  text,
  text,
  jsonb
) from public, anon;

grant execute on function api.submit_stocktake_count(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  boolean,
  text,
  text,
  jsonb
) to authenticated, service_role;

revoke all on function api.request_stocktake_recount(
  uuid,
  text,
  uuid,
  uuid,
  text,
  jsonb
) from public, anon;

grant execute on function api.request_stocktake_recount(
  uuid,
  text,
  uuid,
  uuid,
  text,
  jsonb
) to authenticated, service_role;

revoke all on function api.complete_stocktake_counting(
  uuid,
  text,
  uuid,
  jsonb
) from public, anon;

grant execute on function api.complete_stocktake_counting(
  uuid,
  text,
  uuid,
  jsonb
) to authenticated, service_role;

commit;
