begin;

create or replace function api.run_reconciliation(
  p_organization_id uuid,
  p_idempotency_key text,
  p_check_codes text[] default array[
    'LEDGER_BATCH_PROJECTION',
    'BATCH_PRODUCT_PROJECTION'
  ]::text[],
  p_scope jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, reconciliation, extensions
as $$
declare
  v_scope constant text := 'RUN_RECONCILIATION';
  v_rule_set_version constant text := 'projection-v1';
  v_rule_version constant text := '1';

  v_idempotency_key text;
  v_check_codes text[];
  v_scope_json jsonb;
  v_metadata jsonb;
  v_request_hash text;

  v_existing inventory.idempotency_commands%rowtype;
  v_organization_timezone text;
  v_jwt_role text :=
    coalesce(
      auth.jwt() ->> 'role',
      current_setting('request.jwt.claim.role', true)
    );

  v_actor_user_id uuid := auth.uid();
  v_process_name text;

  v_command_id uuid := gen_random_uuid();
  v_run_id uuid := gen_random_uuid();
  v_run_check_id uuid;
  v_issue_id uuid;

  v_recorded_at timestamptz := clock_timestamp();
  v_completed_at timestamptz;
  v_run_no text;
  v_ledger_seq_to bigint;

  v_check_code text;
  v_check_started_at timestamptz;
  v_checked_count bigint;
  v_issue_count bigint;
  v_total_issue_count bigint := 0;
  v_seen_fingerprints text[];
  v_fingerprint text;
  v_mismatch record;

  v_check_results jsonb;
  v_integrity_status text;
  v_response jsonb;
begin
  if p_organization_id is null then
    raise exception
      using errcode = 'P0001',
            message = 'ORGANIZATION_REQUIRED';
  end if;

  v_idempotency_key :=
    btrim(coalesce(p_idempotency_key, ''));

  if v_idempotency_key = '' then
    raise exception
      using errcode = 'P0001',
            message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  if length(v_idempotency_key) > 200 then
    raise exception
      using errcode = 'P0001',
            message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;

  if p_check_codes is null
     or cardinality(p_check_codes) = 0 then
    raise exception
      using errcode = 'P0001',
            message = 'RECONCILIATION_CHECKS_REQUIRED';
  end if;

  if exists (
    select 1
    from unnest(p_check_codes) as item(code)
    where item.code is null
       or btrim(item.code) = ''
  ) then
    raise exception
      using errcode = 'P0001',
            message = 'RECONCILIATION_CHECK_CODE_INVALID';
  end if;

  if cardinality(p_check_codes) <> (
    select count(distinct upper(btrim(item.code)))
    from unnest(p_check_codes) as item(code)
  ) then
    raise exception
      using errcode = 'P0001',
            message = 'RECONCILIATION_CHECK_CODE_DUPLICATE';
  end if;

  select array_agg(
    upper(btrim(item.code))
    order by upper(btrim(item.code))
  )
  into v_check_codes
  from unnest(p_check_codes) as item(code);

  if exists (
    select 1
    from unnest(v_check_codes) as item(code)
    where item.code not in (
      'LEDGER_BATCH_PROJECTION',
      'BATCH_PRODUCT_PROJECTION'
    )
  ) then
    raise exception
      using errcode = 'P0001',
            message = 'RECONCILIATION_CHECK_NOT_SUPPORTED';
  end if;

  v_scope_json := coalesce(p_scope, '{}'::jsonb);

  if jsonb_typeof(v_scope_json) is distinct from 'object' then
    raise exception
      using errcode = 'P0001',
            message = 'RECONCILIATION_SCOPE_MUST_BE_OBJECT';
  end if;

  if v_scope_json <> '{}'::jsonb then
    raise exception
      using errcode = 'P0001',
            message = 'RECONCILIATION_SCOPE_NOT_SUPPORTED';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception
      using errcode = 'P0001',
            message = 'RECONCILIATION_METADATA_MUST_BE_OBJECT';
  end if;

  select organization.timezone
  into v_organization_timezone
  from app.organizations organization
  where organization.id = p_organization_id
    and organization.is_active;

  if not found then
    raise exception
      using errcode = 'P0001',
            message = 'ORGANIZATION_NOT_FOUND';
  end if;

  if v_jwt_role = 'anon'
     or (
       v_jwt_role = 'authenticated'
       and v_actor_user_id is null
     ) then
    raise exception
      using errcode = '42501',
            message = 'AUTHENTICATION_REQUIRED';
  end if;

  if v_actor_user_id is null
     and coalesce(v_jwt_role, '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception
      using errcode = '42501',
            message = 'TRUSTED_CALLER_REQUIRED';
  end if;

  if v_actor_user_id is not null then
    if not app.is_admin()
       or app.current_organization_id()
          is distinct from p_organization_id then
      raise exception
        using errcode = '42501',
              message = 'ORGANIZATION_ACCESS_DENIED';
    end if;

    v_process_name := null;
  else
    v_process_name := 'api.run_reconciliation';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'organizationId', p_organization_id,
          'checkCodes', to_jsonb(v_check_codes),
          'scope', v_scope_json,
          'metadata', v_metadata,
          'ruleSetVersion', v_rule_set_version,
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
        || v_scope
        || ':'
        || v_idempotency_key,
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
      raise exception
        using errcode = 'P0001',
              message = 'IDEMPOTENCY_KEY_REUSED';
    end if;

    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot;
    end if;

    if v_existing.status_code = 'STARTED' then
      raise exception
        using errcode = 'P0001',
              message = 'IDEMPOTENCY_COMMAND_IN_PROGRESS';
    end if;

    raise exception
      using errcode = 'P0001',
            message = 'IDEMPOTENCY_COMMAND_FAILED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
        || ':RECONCILIATION_EXECUTION',
      0::bigint
    )
  );

  lock table inventory.stock_ledger_entries
    in share mode;

  lock table inventory.stock_batch_balances
    in share mode;

  lock table inventory.stock_product_positions
    in share mode;

  select coalesce(max(entry.ledger_seq), 0)
  into v_ledger_seq_to
  from inventory.stock_ledger_entries entry
  where entry.organization_id = p_organization_id;

  v_run_no :=
    'RCN-'
    || to_char(
      v_recorded_at at time zone v_organization_timezone,
      'YYYYMMDD-HH24MISS'
    )
    || '-'
    || upper(
      substr(
        replace(v_run_id::text, '-', ''),
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

  insert into reconciliation.runs (
    id,
    organization_id,
    run_no,
    run_type_code,
    trigger_code,
    status_code,
    scope,
    check_codes,
    rule_set_version,
    ledger_seq_from,
    ledger_seq_to,
    started_at,
    completed_at,
    actor_user_id,
    process_name,
    idempotency_command_id,
    summary,
    error_code,
    error_detail,
    metadata,
    created_at,
    updated_at
  )
  values (
    v_run_id,
    p_organization_id,
    v_run_no,
    'MANUAL',
    'MANUAL',
    'RUNNING',
    v_scope_json,
    v_check_codes,
    v_rule_set_version,
    0,
    v_ledger_seq_to,
    v_recorded_at,
    null,
    v_actor_user_id,
    v_process_name,
    v_command_id,
    '{}'::jsonb,
    null,
    null,
    v_metadata,
    v_recorded_at,
    v_recorded_at
  );

  foreach v_check_code in array v_check_codes
  loop
    v_run_check_id := gen_random_uuid();
    v_check_started_at := clock_timestamp();
    v_checked_count := 0;
    v_issue_count := 0;
    v_seen_fingerprints := array[]::text[];

    insert into reconciliation.run_checks (
      id,
      organization_id,
      run_id,
      check_code,
      rule_version,
      status_code,
      checked_count,
      issue_count,
      started_at,
      completed_at,
      summary,
      error_code,
      error_detail,
      created_at,
      updated_at
    )
    values (
      v_run_check_id,
      p_organization_id,
      v_run_id,
      v_check_code,
      v_rule_version,
      'RUNNING',
      0,
      0,
      v_check_started_at,
      null,
      '{}'::jsonb,
      null,
      null,
      v_check_started_at,
      v_check_started_at
    );

    if v_check_code = 'LEDGER_BATCH_PROJECTION' then
      with ledger_aggregate as (
        select
          entry.product_id,
          entry.batch_id,
          coalesce(
            sum(entry.quantity_delta)
              filter (
                where entry.bucket_code = 'SELLABLE'
              ),
            0
          )::bigint as sellable_qty,
          coalesce(
            sum(entry.quantity_delta)
              filter (
                where entry.bucket_code = 'QUARANTINE'
              ),
            0
          )::bigint as quarantine_qty,
          coalesce(
            sum(entry.quantity_delta)
              filter (
                where entry.bucket_code = 'DAMAGED'
              ),
            0
          )::bigint as damaged_qty
        from inventory.stock_ledger_entries entry
        where entry.organization_id = p_organization_id
          and entry.ledger_seq <= v_ledger_seq_to
        group by
          entry.product_id,
          entry.batch_id
      ),
      entity_keys as (
        select
          ledger.product_id,
          ledger.batch_id
        from ledger_aggregate ledger

        union

        select
          balance.product_id,
          balance.batch_id
        from inventory.stock_batch_balances balance
        where balance.organization_id = p_organization_id
      )
      select count(*)
      into v_checked_count
      from entity_keys;

      for v_mismatch in
        with ledger_aggregate as (
          select
            entry.product_id,
            entry.batch_id,
            coalesce(
              sum(entry.quantity_delta)
                filter (
                  where entry.bucket_code = 'SELLABLE'
                ),
              0
            )::bigint as sellable_qty,
            coalesce(
              sum(entry.quantity_delta)
                filter (
                  where entry.bucket_code = 'QUARANTINE'
                ),
              0
            )::bigint as quarantine_qty,
            coalesce(
              sum(entry.quantity_delta)
                filter (
                  where entry.bucket_code = 'DAMAGED'
                ),
              0
            )::bigint as damaged_qty
          from inventory.stock_ledger_entries entry
          where entry.organization_id = p_organization_id
            and entry.ledger_seq <= v_ledger_seq_to
          group by
            entry.product_id,
            entry.batch_id
        ),
        entity_keys as (
          select
            ledger.product_id,
            ledger.batch_id
          from ledger_aggregate ledger

          union

          select
            balance.product_id,
            balance.batch_id
          from inventory.stock_batch_balances balance
          where balance.organization_id = p_organization_id
        ),
        comparison as (
          select
            entity.product_id,
            entity.batch_id,

            coalesce(
              ledger.sellable_qty,
              0
            )::bigint as expected_sellable_qty,

            coalesce(
              ledger.quarantine_qty,
              0
            )::bigint as expected_quarantine_qty,

            coalesce(
              ledger.damaged_qty,
              0
            )::bigint as expected_damaged_qty,

            coalesce(
              balance.sellable_qty,
              0
            )::bigint as actual_sellable_qty,

            coalesce(
              balance.quarantine_qty,
              0
            )::bigint as actual_quarantine_qty,

            coalesce(
              balance.damaged_qty,
              0
            )::bigint as actual_damaged_qty
          from entity_keys entity
          left join ledger_aggregate ledger
            on ledger.product_id = entity.product_id
           and ledger.batch_id = entity.batch_id
          left join inventory.stock_batch_balances balance
            on balance.organization_id = p_organization_id
           and balance.product_id = entity.product_id
           and balance.batch_id = entity.batch_id
        )
        select comparison.*
        from comparison
        where comparison.expected_sellable_qty
                <> comparison.actual_sellable_qty
           or comparison.expected_quarantine_qty
                <> comparison.actual_quarantine_qty
           or comparison.expected_damaged_qty
                <> comparison.actual_damaged_qty
        order by
          comparison.product_id,
          comparison.batch_id
      loop
        v_fingerprint := encode(
          extensions.digest(
            convert_to(
              p_organization_id::text
                || '|'
                || v_check_code
                || '|'
                || v_rule_version
                || '|'
                || v_mismatch.product_id::text
                || '|'
                || v_mismatch.batch_id::text,
              'UTF8'
            ),
            'sha256'
          ),
          'hex'
        );

        v_seen_fingerprints :=
          array_append(
            v_seen_fingerprints,
            v_fingerprint
          );

        insert into reconciliation.issues as existing_issue (
          organization_id,
          fingerprint,
          check_code,
          rule_version,
          status_code,
          severity_code,
          entity_type_code,
          entity_key,
          product_id,
          batch_id,
          source_type_code,
          source_ref,
          expected_value,
          actual_value,
          difference_value,
          first_seen_run_id,
          last_seen_run_id,
          first_seen_at,
          last_seen_at,
          recurrence_count,
          resolved_at,
          resolution_code,
          resolution_note,
          resolved_by_user_id,
          resolved_by_process_name,
          created_at,
          updated_at
        )
        values (
          p_organization_id,
          v_fingerprint,
          v_check_code,
          v_rule_version,
          'OPEN',
          'HIGH',
          'BATCH_BALANCE',
          jsonb_build_object(
            'productId',
            v_mismatch.product_id,
            'batchId',
            v_mismatch.batch_id
          ),
          v_mismatch.product_id,
          v_mismatch.batch_id,
          null,
          null,
          jsonb_build_object(
            'sellableQty',
            v_mismatch.expected_sellable_qty,
            'quarantineQty',
            v_mismatch.expected_quarantine_qty,
            'damagedQty',
            v_mismatch.expected_damaged_qty
          ),
          jsonb_build_object(
            'sellableQty',
            v_mismatch.actual_sellable_qty,
            'quarantineQty',
            v_mismatch.actual_quarantine_qty,
            'damagedQty',
            v_mismatch.actual_damaged_qty
          ),
          jsonb_build_object(
            'sellableQty',
            v_mismatch.actual_sellable_qty
              - v_mismatch.expected_sellable_qty,
            'quarantineQty',
            v_mismatch.actual_quarantine_qty
              - v_mismatch.expected_quarantine_qty,
            'damagedQty',
            v_mismatch.actual_damaged_qty
              - v_mismatch.expected_damaged_qty
          ),
          v_run_id,
          v_run_id,
          v_recorded_at,
          v_recorded_at,
          1,
          null,
          null,
          null,
          null,
          null,
          v_recorded_at,
          v_recorded_at
        )
        on conflict (
          organization_id,
          fingerprint
        )
        do update
        set
          check_code = excluded.check_code,
          rule_version = excluded.rule_version,
          status_code = 'OPEN',
          severity_code = excluded.severity_code,
          entity_type_code = excluded.entity_type_code,
          entity_key = excluded.entity_key,
          product_id = excluded.product_id,
          batch_id = excluded.batch_id,
          expected_value = excluded.expected_value,
          actual_value = excluded.actual_value,
          difference_value = excluded.difference_value,
          last_seen_run_id = excluded.last_seen_run_id,
          last_seen_at = excluded.last_seen_at,
          recurrence_count =
            existing_issue.recurrence_count + 1,
          resolved_at = null,
          resolution_code = null,
          resolution_note = null,
          resolved_by_user_id = null,
          resolved_by_process_name = null,
          updated_at = excluded.updated_at
        returning id
        into v_issue_id;

        insert into reconciliation.issue_evidence (
          organization_id,
          issue_id,
          run_id,
          run_check_id,
          evidence_no,
          evidence_type_code,
          entity_type_code,
          entity_key,
          expected_value,
          actual_value,
          difference_value,
          detail,
          created_at
        )
        values (
          p_organization_id,
          v_issue_id,
          v_run_id,
          v_run_check_id,
          1,
          'PROJECTION_MISMATCH',
          'BATCH_BALANCE',
          jsonb_build_object(
            'productId',
            v_mismatch.product_id,
            'batchId',
            v_mismatch.batch_id
          ),
          jsonb_build_object(
            'sellableQty',
            v_mismatch.expected_sellable_qty,
            'quarantineQty',
            v_mismatch.expected_quarantine_qty,
            'damagedQty',
            v_mismatch.expected_damaged_qty
          ),
          jsonb_build_object(
            'sellableQty',
            v_mismatch.actual_sellable_qty,
            'quarantineQty',
            v_mismatch.actual_quarantine_qty,
            'damagedQty',
            v_mismatch.actual_damaged_qty
          ),
          jsonb_build_object(
            'sellableQty',
            v_mismatch.actual_sellable_qty
              - v_mismatch.expected_sellable_qty,
            'quarantineQty',
            v_mismatch.actual_quarantine_qty
              - v_mismatch.expected_quarantine_qty,
            'damagedQty',
            v_mismatch.actual_damaged_qty
              - v_mismatch.expected_damaged_qty
          ),
          jsonb_build_object(
            'ledgerSeqTo',
            v_ledger_seq_to,
            'ruleSetVersion',
            v_rule_set_version
          ),
          v_recorded_at
        );

        v_issue_count := v_issue_count + 1;
      end loop;

    elsif v_check_code = 'BATCH_PRODUCT_PROJECTION' then
      with batch_aggregate as (
        select
          balance.product_id,
          coalesce(
            sum(balance.sellable_qty),
            0
          )::bigint as sellable_qty,
          coalesce(
            sum(balance.quarantine_qty),
            0
          )::bigint as quarantine_qty,
          coalesce(
            sum(balance.damaged_qty),
            0
          )::bigint as damaged_qty
        from inventory.stock_batch_balances balance
        where balance.organization_id = p_organization_id
        group by balance.product_id
      ),
      entity_keys as (
        select batch.product_id
        from batch_aggregate batch

        union

        select position.product_id
        from inventory.stock_product_positions position
        where position.organization_id = p_organization_id
      )
      select count(*)
      into v_checked_count
      from entity_keys;

      for v_mismatch in
        with batch_aggregate as (
          select
            balance.product_id,
            coalesce(
              sum(balance.sellable_qty),
              0
            )::bigint as sellable_qty,
            coalesce(
              sum(balance.quarantine_qty),
              0
            )::bigint as quarantine_qty,
            coalesce(
              sum(balance.damaged_qty),
              0
            )::bigint as damaged_qty
          from inventory.stock_batch_balances balance
          where balance.organization_id = p_organization_id
          group by balance.product_id
        ),
        entity_keys as (
          select batch.product_id
          from batch_aggregate batch

          union

          select position.product_id
          from inventory.stock_product_positions position
          where position.organization_id = p_organization_id
        ),
        comparison as (
          select
            entity.product_id,

            coalesce(
              batch.sellable_qty,
              0
            )::bigint as expected_sellable_qty,

            coalesce(
              batch.quarantine_qty,
              0
            )::bigint as expected_quarantine_qty,

            coalesce(
              batch.damaged_qty,
              0
            )::bigint as expected_damaged_qty,

            coalesce(
              position.sellable_qty,
              0
            )::bigint as actual_sellable_qty,

            coalesce(
              position.quarantine_qty,
              0
            )::bigint as actual_quarantine_qty,

            coalesce(
              position.damaged_qty,
              0
            )::bigint as actual_damaged_qty
          from entity_keys entity
          left join batch_aggregate batch
            on batch.product_id = entity.product_id
          left join inventory.stock_product_positions position
            on position.organization_id = p_organization_id
           and position.product_id = entity.product_id
        )
        select comparison.*
        from comparison
        where comparison.expected_sellable_qty
                <> comparison.actual_sellable_qty
           or comparison.expected_quarantine_qty
                <> comparison.actual_quarantine_qty
           or comparison.expected_damaged_qty
                <> comparison.actual_damaged_qty
        order by comparison.product_id
      loop
        v_fingerprint := encode(
          extensions.digest(
            convert_to(
              p_organization_id::text
                || '|'
                || v_check_code
                || '|'
                || v_rule_version
                || '|'
                || v_mismatch.product_id::text,
              'UTF8'
            ),
            'sha256'
          ),
          'hex'
        );

        v_seen_fingerprints :=
          array_append(
            v_seen_fingerprints,
            v_fingerprint
          );

        insert into reconciliation.issues as existing_issue (
          organization_id,
          fingerprint,
          check_code,
          rule_version,
          status_code,
          severity_code,
          entity_type_code,
          entity_key,
          product_id,
          batch_id,
          source_type_code,
          source_ref,
          expected_value,
          actual_value,
          difference_value,
          first_seen_run_id,
          last_seen_run_id,
          first_seen_at,
          last_seen_at,
          recurrence_count,
          resolved_at,
          resolution_code,
          resolution_note,
          resolved_by_user_id,
          resolved_by_process_name,
          created_at,
          updated_at
        )
        values (
          p_organization_id,
          v_fingerprint,
          v_check_code,
          v_rule_version,
          'OPEN',
          'HIGH',
          'PRODUCT_POSITION',
          jsonb_build_object(
            'productId',
            v_mismatch.product_id
          ),
          v_mismatch.product_id,
          null,
          null,
          null,
          jsonb_build_object(
            'sellableQty',
            v_mismatch.expected_sellable_qty,
            'quarantineQty',
            v_mismatch.expected_quarantine_qty,
            'damagedQty',
            v_mismatch.expected_damaged_qty
          ),
          jsonb_build_object(
            'sellableQty',
            v_mismatch.actual_sellable_qty,
            'quarantineQty',
            v_mismatch.actual_quarantine_qty,
            'damagedQty',
            v_mismatch.actual_damaged_qty
          ),
          jsonb_build_object(
            'sellableQty',
            v_mismatch.actual_sellable_qty
              - v_mismatch.expected_sellable_qty,
            'quarantineQty',
            v_mismatch.actual_quarantine_qty
              - v_mismatch.expected_quarantine_qty,
            'damagedQty',
            v_mismatch.actual_damaged_qty
              - v_mismatch.expected_damaged_qty
          ),
          v_run_id,
          v_run_id,
          v_recorded_at,
          v_recorded_at,
          1,
          null,
          null,
          null,
          null,
          null,
          v_recorded_at,
          v_recorded_at
        )
        on conflict (
          organization_id,
          fingerprint
        )
        do update
        set
          check_code = excluded.check_code,
          rule_version = excluded.rule_version,
          status_code = 'OPEN',
          severity_code = excluded.severity_code,
          entity_type_code = excluded.entity_type_code,
          entity_key = excluded.entity_key,
          product_id = excluded.product_id,
          batch_id = null,
          expected_value = excluded.expected_value,
          actual_value = excluded.actual_value,
          difference_value = excluded.difference_value,
          last_seen_run_id = excluded.last_seen_run_id,
          last_seen_at = excluded.last_seen_at,
          recurrence_count =
            existing_issue.recurrence_count + 1,
          resolved_at = null,
          resolution_code = null,
          resolution_note = null,
          resolved_by_user_id = null,
          resolved_by_process_name = null,
          updated_at = excluded.updated_at
        returning id
        into v_issue_id;

        insert into reconciliation.issue_evidence (
          organization_id,
          issue_id,
          run_id,
          run_check_id,
          evidence_no,
          evidence_type_code,
          entity_type_code,
          entity_key,
          expected_value,
          actual_value,
          difference_value,
          detail,
          created_at
        )
        values (
          p_organization_id,
          v_issue_id,
          v_run_id,
          v_run_check_id,
          1,
          'PROJECTION_MISMATCH',
          'PRODUCT_POSITION',
          jsonb_build_object(
            'productId',
            v_mismatch.product_id
          ),
          jsonb_build_object(
            'sellableQty',
            v_mismatch.expected_sellable_qty,
            'quarantineQty',
            v_mismatch.expected_quarantine_qty,
            'damagedQty',
            v_mismatch.expected_damaged_qty
          ),
          jsonb_build_object(
            'sellableQty',
            v_mismatch.actual_sellable_qty,
            'quarantineQty',
            v_mismatch.actual_quarantine_qty,
            'damagedQty',
            v_mismatch.actual_damaged_qty
          ),
          jsonb_build_object(
            'sellableQty',
            v_mismatch.actual_sellable_qty
              - v_mismatch.expected_sellable_qty,
            'quarantineQty',
            v_mismatch.actual_quarantine_qty
              - v_mismatch.expected_quarantine_qty,
            'damagedQty',
            v_mismatch.actual_damaged_qty
              - v_mismatch.expected_damaged_qty
          ),
          jsonb_build_object(
            'ledgerSeqTo',
            v_ledger_seq_to,
            'ruleSetVersion',
            v_rule_set_version
          ),
          v_recorded_at
        );

        v_issue_count := v_issue_count + 1;
      end loop;
    end if;

    update reconciliation.issues issue
    set
      status_code = 'RESOLVED',
      resolved_at = clock_timestamp(),
      resolution_code = 'NOT_REDETECTED',
      resolution_note =
        'Mismatch was not detected at ledger boundary '
        || v_ledger_seq_to::text,
      resolved_by_user_id = v_actor_user_id,
      resolved_by_process_name = v_process_name,
      updated_at = clock_timestamp()
    where issue.organization_id = p_organization_id
      and issue.check_code = v_check_code
      and issue.status_code = 'OPEN'
      and not (
        issue.fingerprint = any(v_seen_fingerprints)
      );

    update reconciliation.run_checks run_check
    set
      status_code =
        case
          when v_issue_count = 0 then 'PASSED'
          else 'FAILED'
        end,
      checked_count = v_checked_count,
      issue_count = v_issue_count,
      completed_at = clock_timestamp(),
      summary = jsonb_build_object(
        'checkedCount',
        v_checked_count,
        'issueCount',
        v_issue_count,
        'ledgerSeqTo',
        v_ledger_seq_to
      ),
      error_code = null,
      error_detail = null,
      updated_at = clock_timestamp()
    where run_check.id = v_run_check_id
      and run_check.organization_id = p_organization_id
      and run_check.run_id = v_run_id;

    v_total_issue_count :=
      v_total_issue_count + v_issue_count;
  end loop;

  v_completed_at := clock_timestamp();

  v_integrity_status :=
    case
      when v_total_issue_count = 0 then 'CLEAN'
      else 'ISSUES_FOUND'
    end;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'checkCode',
        run_check.check_code,
        'status',
        run_check.status_code,
        'checkedCount',
        run_check.checked_count,
        'issueCount',
        run_check.issue_count
      )
      order by run_check.check_code
    ),
    '[]'::jsonb
  )
  into v_check_results
  from reconciliation.run_checks run_check
  where run_check.organization_id = p_organization_id
    and run_check.run_id = v_run_id;

  v_response := jsonb_build_object(
    'status',
    'SUCCEEDED',
    'integrityStatus',
    v_integrity_status,
    'runId',
    v_run_id,
    'runNo',
    v_run_no,
    'idempotencyKey',
    v_idempotency_key,
    'requestHash',
    v_request_hash,
    'ruleSetVersion',
    v_rule_set_version,
    'ledgerSeqFrom',
    0,
    'ledgerSeqTo',
    v_ledger_seq_to,
    'checkCount',
    cardinality(v_check_codes),
    'issueCount',
    v_total_issue_count,
    'checks',
    v_check_results,
    'startedAt',
    v_recorded_at,
    'completedAt',
    v_completed_at
  );

  update reconciliation.runs run
  set
    status_code = 'SUCCEEDED',
    completed_at = v_completed_at,
    summary = jsonb_build_object(
      'integrityStatus',
      v_integrity_status,
      'checkCount',
      cardinality(v_check_codes),
      'issueCount',
      v_total_issue_count,
      'checks',
      v_check_results
    ),
    error_code = null,
    error_detail = null,
    updated_at = v_completed_at
  where run.id = v_run_id
    and run.organization_id = p_organization_id;

  update inventory.idempotency_commands command
  set
    status_code = 'SUCCEEDED',
    completed_at = v_completed_at,
    result_transaction_id = null,
    response_snapshot = v_response,
    error_code = null
  where command.id = v_command_id;

  return v_response;
end;
$$;

revoke all on function api.run_reconciliation(
  uuid,
  text,
  text[],
  jsonb,
  jsonb
) from public, anon;

grant execute on function api.run_reconciliation(
  uuid,
  text,
  text[],
  jsonb,
  jsonb
) to authenticated, service_role;

commit;