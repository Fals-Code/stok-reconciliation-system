begin;

create extension if not exists pgtap with schema extensions;

select plan(56);

-- 1-12: command and privilege contracts
select function_returns(
  'api',
  'create_stocktake',
  array[
    'uuid',
    'text',
    'text',
    'text',
    'text',
    'text',
    'jsonb',
    'timestamptz',
    'text',
    'jsonb'
  ]::text[],
  'jsonb'
);
select function_returns(
  'api',
  'prepare_stocktake',
  array['uuid', 'text', 'uuid', 'jsonb']::text[],
  'jsonb'
);
select function_returns(
  'api',
  'start_stocktake',
  array['uuid', 'text', 'uuid', 'jsonb']::text[],
  'jsonb'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.create_stocktake(uuid,text,text,text,text,text,jsonb,timestamptz,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may create stocktakes'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.prepare_stocktake(uuid,text,uuid,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may prepare stocktakes'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.start_stocktake(uuid,text,uuid,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may start stocktakes'
);
select ok(
  has_function_privilege(
    'service_role',
    'api.create_stocktake(uuid,text,text,text,text,text,jsonb,timestamptz,text,jsonb)',
    'EXECUTE'
  ),
  'service role may create stocktakes'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.create_stocktake(uuid,text,text,text,text,text,jsonb,timestamptz,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot create stocktakes'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.prepare_stocktake(uuid,text,uuid,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot prepare stocktakes'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.start_stocktake(uuid,text,uuid,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot start stocktakes'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'operations.resolve_stocktake_scope(uuid,jsonb,date,bigint)',
    'EXECUTE'
  ),
  'authenticated users cannot execute the internal scope resolver'
);
select ok(
  not has_function_privilege(
    'anon',
    'operations.resolve_stocktake_scope(uuid,jsonb,date,bigint)',
    'EXECUTE'
  ),
  'anonymous users cannot execute the internal scope resolver'
);

-- Authenticated Admin fixture.
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
)
values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  '91000000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.stocktake.admin@glowlab.invalid',
  '2026-07-16 07:00:00+07'::timestamptz,
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 07:00:00+07'::timestamptz,
  '2026-07-16 07:00:00+07'::timestamptz,
  false,
  false
);

insert into app.user_profiles (
  user_id,
  organization_id,
  display_name,
  employee_code,
  role_code,
  is_active
)
values (
  '91000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Stocktake Admin',
  'PGTAP-STK-ADMIN',
  'ADMIN',
  true
);

insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active,
  created_at,
  created_by
)
values (
  '00000000-0000-4000-8000-000000000002'::uuid,
  'PGTAP_STOCKTAKE_OTHER',
  'pgTAP Stocktake Other Organization',
  'Asia/Jakarta',
  true,
  '2026-07-16 07:00:00+07'::timestamptz,
  null
);

create temp table stocktake_command_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update
on stocktake_command_results
to authenticated;

create temp table stocktake_stock_baseline (
  transaction_count bigint not null,
  ledger_count bigint not null,
  batch_sellable bigint not null,
  product_sellable bigint not null
) on commit drop;

insert into stocktake_stock_baseline (
  transaction_count,
  ledger_count,
  batch_sellable,
  product_sellable
)
select
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select sellable_qty
    from inventory.stock_batch_balances
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select sellable_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  );

select set_config(
  'request.jwt.claim.sub',
  '91000000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '91000000-0000-4000-8000-000000000001',
    'role',
    'authenticated',
    'email',
    'pgtap.stocktake.admin@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

insert into stocktake_command_results (kind, result)
select
  'CREATE',
  api.create_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-CREATE-COMMAND-001',
    'Cycle count serum batch',
    'CYCLE',
    'CONTINUOUS',
    'BLIND',
    jsonb_build_object(
      'mode',
      'BATCHES',
      'batchIds',
      jsonb_build_array(
        '40000000-0000-4000-8000-000000000001'
      ),
      'bucketCodes',
      jsonb_build_array('SELLABLE'),
      'includeZeroSystemBalance',
      false,
      'includeInactiveWithBalance',
      false,
      'includeBlockedBatches',
      false,
      'includeExpiredBatches',
      true
    ),
    '2026-07-16 08:00:00+07'::timestamptz,
    'Session command contract.',
    '{"fixture": "stocktake-session-command"}'::jsonb
  );

reset role;

-- 13-21: create command
select is(
  (
    select result ->> 'status'
    from stocktake_command_results
    where kind = 'CREATE'
  ),
  'DRAFT',
  'create returns draft status'
);
select is(
  (
    select count(*)
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  1::bigint,
  'create stores one stocktake'
);
select is(
  (
    select stocktake.created_by::text
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  '91000000-0000-4000-8000-000000000001',
  'create snapshots the authenticated Admin'
);
select is(
  (
    select stocktake.process_name
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  null,
  'authenticated create does not use a system process actor'
);
select is(
  (
    select stocktake.mode_code
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  'CONTINUOUS',
  'create stores continuous mode'
);
select is(
  (
    select stocktake.scope_definition -> 'bucketCodes'
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  '["SELLABLE"]'::jsonb,
  'create stores normalized bucket scope'
);
select is(
  (
    select command.status_code
    from inventory.idempotency_commands command
    where command.scope = 'CREATE_STOCKTAKE'
      and command.key = 'PGTAP-STOCKTAKE-CREATE-COMMAND-001'
  ),
  'SUCCEEDED',
  'create idempotency command succeeds'
);
select is(
  (
    select count(*)
    from operations.stocktake_lines line
    where line.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  0::bigint,
  'create does not resolve lines before start'
);
select is(
  (
    select count(*)
    from operations.stocktake_snapshots snapshot
    where snapshot.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  0::bigint,
  'create does not capture a snapshot'
);

insert into stocktake_command_results (kind, result)
select
  'CREATE_REPLAY',
  api.create_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-CREATE-COMMAND-001',
    'Cycle count serum batch',
    'CYCLE',
    'CONTINUOUS',
    'BLIND',
    jsonb_build_object(
      'mode',
      'BATCHES',
      'batchIds',
      jsonb_build_array(
        '40000000-0000-4000-8000-000000000001'
      ),
      'bucketCodes',
      jsonb_build_array('SELLABLE'),
      'includeZeroSystemBalance',
      false,
      'includeInactiveWithBalance',
      false,
      'includeBlockedBatches',
      false,
      'includeExpiredBatches',
      true
    ),
    '2026-07-16 08:00:00+07'::timestamptz,
    'Session command contract.',
    '{"fixture": "stocktake-session-command"}'::jsonb
  );

-- 22-24: create idempotency
select is(
  (
    select result
    from stocktake_command_results
    where kind = 'CREATE_REPLAY'
  ),
  (
    select result
    from stocktake_command_results
    where kind = 'CREATE'
  ),
  'create replay returns the stored response'
);
select is(
  (
    select count(*)
    from operations.stocktakes stocktake
    where stocktake.stocktake_no = (
      select result ->> 'stocktakeNo'
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  1::bigint,
  'create replay does not duplicate the session'
);
select throws_ok(
  $sql$
    select api.create_stocktake(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-STOCKTAKE-CREATE-COMMAND-001',
      'Changed title',
      'CYCLE',
      'CONTINUOUS',
      'BLIND',
      jsonb_build_object(
        'mode',
        'BATCHES',
        'batchIds',
        jsonb_build_array(
          '40000000-0000-4000-8000-000000000001'
        ),
        'bucketCodes',
        jsonb_build_array('SELLABLE')
      ),
      '2026-07-16 08:00:00+07'::timestamptz,
      'Session command contract.',
      '{"fixture": "stocktake-session-command"}'::jsonb
    )
  $sql$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'create key cannot be reused with another payload'
);

insert into stocktake_command_results (kind, result)
select
  'PREPARE',
  api.prepare_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-PREPARE-COMMAND-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    ),
    '{"fixture": "prepare"}'::jsonb
  );

-- 25-30: prepare command
select is(
  (
    select result ->> 'status'
    from stocktake_command_results
    where kind = 'PREPARE'
  ),
  'READY',
  'prepare returns ready status'
);
select is(
  (
    select stocktake.status_code
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  'READY',
  'prepare transitions the session to ready'
);
select is(
  (
    select result ->> 'scopeLineCount'
    from stocktake_command_results
    where kind = 'PREPARE'
  ),
  '1',
  'prepare validates one scoped line'
);
select is(
  (
    select count(*)
    from operations.stocktake_lines line
    where line.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  0::bigint,
  'prepare remains stocktake-line neutral'
);
select is(
  (
    select count(*)
    from operations.stocktake_snapshots snapshot
    where snapshot.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  0::bigint,
  'prepare does not capture a snapshot'
);
select is(
  (
    select command.status_code
    from inventory.idempotency_commands command
    where command.scope = 'PREPARE_STOCKTAKE'
      and command.key = 'PGTAP-STOCKTAKE-PREPARE-COMMAND-001'
  ),
  'SUCCEEDED',
  'prepare idempotency command succeeds'
);

insert into stocktake_command_results (kind, result)
select
  'PREPARE_REPLAY',
  api.prepare_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-PREPARE-COMMAND-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    ),
    '{"fixture": "prepare"}'::jsonb
  );

-- 31-32: prepare idempotency and state guard
select is(
  (
    select result
    from stocktake_command_results
    where kind = 'PREPARE_REPLAY'
  ),
  (
    select result
    from stocktake_command_results
    where kind = 'PREPARE'
  ),
  'prepare replay returns the stored response'
);
select throws_ok(
  format(
    $sql$
      select api.prepare_stocktake(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-PREPARE-COMMAND-NEW',
        %L::uuid,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  'P0001',
  'STOCKTAKE_INVALID_STATE',
  'ready session cannot be prepared with a new command'
);

insert into stocktake_command_results (kind, result)
select
  'START',
  api.start_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-START-COMMAND-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    ),
    '{"fixture": "start"}'::jsonb
  );

-- 33-45: start and ledger snapshot
select is(
  (
    select result ->> 'status'
    from stocktake_command_results
    where kind = 'START'
  ),
  'COUNTING',
  'start returns counting status'
);
select is(
  (
    select stocktake.status_code
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  'COUNTING',
  'start transitions the session to counting'
);
select is(
  (
    select result ->> 'snapshotSource'
    from stocktake_command_results
    where kind = 'START'
  ),
  'LEDGER',
  'start reports ledger as snapshot source'
);
select is(
  (
    select result ->> 'lineCount'
    from stocktake_command_results
    where kind = 'START'
  ),
  '1',
  'start creates one deterministic line'
);
select is(
  (
    select count(*)
    from operations.stocktake_lines line
    where line.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  1::bigint,
  'start stores one stocktake line'
);
select is(
  (
    select count(*)
    from operations.stocktake_snapshots snapshot
    where snapshot.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  1::bigint,
  'start stores one immutable snapshot'
);
select is(
  (
    select line.line_no
    from operations.stocktake_lines line
    where line.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  1,
  'start numbers the deterministic line from one'
);
select is(
  (
    select line.bucket_code
    from operations.stocktake_lines line
    where line.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  'SELLABLE',
  'start resolves the requested physical bucket'
);
select is(
  (
    select line.system_qty_at_snapshot
    from operations.stocktake_lines line
    where line.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  (
    select coalesce(sum(entry.quantity_delta), 0)::bigint
    from inventory.stock_ledger_entries entry
    where entry.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and entry.product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
      and entry.batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
      and entry.bucket_code = 'SELLABLE'
      and entry.ledger_seq <= (
        select stocktake.snapshot_ledger_seq
        from operations.stocktakes stocktake
        where stocktake.id = (
          select (result ->> 'stocktakeId')::uuid
          from stocktake_command_results
          where kind = 'CREATE'
        )
      )
  ),
  'snapshot quantity equals ledger aggregation at the boundary'
);
select is(
  (
    select snapshot.system_qty_at_snapshot
    from operations.stocktake_snapshots snapshot
    where snapshot.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  (
    select line.system_qty_at_snapshot
    from operations.stocktake_lines line
    where line.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  'snapshot and line preserve the same ledger quantity'
);
select is(
  (
    select snapshot.snapshot_ledger_seq
    from operations.stocktake_snapshots snapshot
    where snapshot.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  (
    select stocktake.snapshot_ledger_seq
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  'snapshot row uses the session ledger boundary'
);
select is(
  (
    select line.count_status_code
    from operations.stocktake_lines line
    where line.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  'PENDING',
  'new snapshot line remains uncounted'
);
select is(
  (
    select command.status_code
    from inventory.idempotency_commands command
    where command.scope = 'START_STOCKTAKE'
      and command.key = 'PGTAP-STOCKTAKE-START-COMMAND-001'
  ),
  'SUCCEEDED',
  'start idempotency command succeeds'
);

insert into stocktake_command_results (kind, result)
select
  'START_REPLAY',
  api.start_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-START-COMMAND-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    ),
    '{"fixture": "start"}'::jsonb
  );

-- 46-48: start idempotency
select is(
  (
    select result
    from stocktake_command_results
    where kind = 'START_REPLAY'
  ),
  (
    select result
    from stocktake_command_results
    where kind = 'START'
  ),
  'start replay returns the stored response'
);
select is(
  (
    select count(*)
    from operations.stocktake_lines line
    where line.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  1::bigint,
  'start replay does not duplicate lines'
);
select is(
  (
    select count(*)
    from operations.stocktake_snapshots snapshot
    where snapshot.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  1::bigint,
  'start replay does not duplicate snapshots'
);

-- 49-52: lifecycle remains stock-neutral
select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (select transaction_count from stocktake_stock_baseline),
  'session commands do not create stock transactions'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (select ledger_count from stocktake_stock_baseline),
  'session commands do not create ledger entries'
);
select is(
  (
    select sellable_qty
    from inventory.stock_batch_balances
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and batch_id =
        '40000000-0000-4000-8000-000000000001'::uuid
  ),
  (select batch_sellable from stocktake_stock_baseline),
  'session commands do not change batch projection'
);
select is(
  (
    select sellable_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (select product_sellable from stocktake_stock_baseline),
  'session commands do not change product projection'
);

-- 53-56: authorization and unsupported scope contracts
select throws_ok(
  $sql$
    select api.create_stocktake(
      '00000000-0000-4000-8000-000000000002'::uuid,
      'PGTAP-STOCKTAKE-CROSS-ORG',
      'Cross organization attempt',
      'CYCLE',
      'CONTINUOUS',
      'BLIND',
      jsonb_build_object(
        'mode',
        'ALL_ACTIVE_INVENTORY',
        'bucketCodes',
        jsonb_build_array('SELLABLE')
      ),
      null,
      null,
      '{}'::jsonb
    )
  $sql$,
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'authenticated Admin cannot create for another organization'
);
select throws_ok(
  $sql$
    select api.create_stocktake(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-STOCKTAKE-FROZEN',
      'Frozen is deferred',
      'CYCLE',
      'FROZEN',
      'BLIND',
      jsonb_build_object(
        'mode',
        'ALL_ACTIVE_INVENTORY',
        'bucketCodes',
        jsonb_build_array('SELLABLE')
      ),
      null,
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'STOCKTAKE_MODE_NOT_SUPPORTED',
  'frozen mode is explicitly rejected'
);
select throws_ok(
  $sql$
    select api.create_stocktake(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'PGTAP-STOCKTAKE-DEFERRED-SCOPE',
      'Deferred scope',
      'CYCLE',
      'CONTINUOUS',
      'BLIND',
      jsonb_build_object(
        'mode',
        'RECONCILIATION_ISSUES',
        'issueIds',
        jsonb_build_array(
          '99000000-0000-4000-8000-000000000001'
        ),
        'bucketCodes',
        jsonb_build_array('SELLABLE')
      ),
      null,
      null,
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'STOCKTAKE_SCOPE_NOT_SUPPORTED',
  'deferred reconciliation issue scope is rejected'
);
select throws_ok(
  format(
    $sql$
      select api.start_stocktake(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-START-COMMAND-NEW',
        %L::uuid,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_command_results
      where kind = 'CREATE'
    )
  ),
  'P0001',
  'STOCKTAKE_INVALID_STATE',
  'counting session cannot be started with a new command'
);

select * from finish();
rollback;
