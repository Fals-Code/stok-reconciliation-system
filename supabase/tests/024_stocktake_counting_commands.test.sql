begin;

create extension if not exists pgtap with schema extensions;

select plan(76);

-- 1-11: function and privilege contracts
select function_returns(
  'api',
  'submit_stocktake_count',
  array[
    'uuid',
    'text',
    'uuid',
    'uuid',
    'bigint',
    'boolean',
    'text',
    'text',
    'jsonb'
  ]::text[],
  'jsonb'
);
select function_returns(
  'api',
  'request_stocktake_recount',
  array['uuid', 'text', 'uuid', 'uuid', 'text', 'jsonb']::text[],
  'jsonb'
);
select function_returns(
  'api',
  'complete_stocktake_counting',
  array['uuid', 'text', 'uuid', 'jsonb']::text[],
  'jsonb'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.submit_stocktake_count(uuid,text,uuid,uuid,bigint,boolean,text,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may submit stocktake counts'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.request_stocktake_recount(uuid,text,uuid,uuid,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may request stocktake recounts'
);
select ok(
  has_function_privilege(
    'authenticated',
    'api.complete_stocktake_counting(uuid,text,uuid,jsonb)',
    'EXECUTE'
  ),
  'authenticated Admin may complete stocktake counting'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.submit_stocktake_count(uuid,text,uuid,uuid,bigint,boolean,text,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot submit stocktake counts'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.request_stocktake_recount(uuid,text,uuid,uuid,text,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot request stocktake recounts'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.complete_stocktake_counting(uuid,text,uuid,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot complete stocktake counting'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'operations.calculate_stocktake_expected(uuid,uuid,uuid,bigint)',
    'EXECUTE'
  ),
  'authenticated users cannot execute the expected-quantity helper'
);
select ok(
  not has_function_privilege(
    'anon',
    'operations.calculate_stocktake_expected(uuid,uuid,uuid,bigint)',
    'EXECUTE'
  ),
  'anonymous users cannot execute the expected-quantity helper'
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
  '92000000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.stocktake.counting@glowlab.invalid',
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
  '92000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Stocktake Counting Admin',
  'PGTAP-STK-COUNT',
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
  '00000000-0000-4000-8000-000000000003'::uuid,
  'PGTAP_STOCKTAKE_COUNT_OTHER',
  'pgTAP Stocktake Counting Other Organization',
  'Asia/Jakarta',
  true,
  '2026-07-16 07:00:00+07'::timestamptz,
  null
);

create temp table stocktake_counting_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

grant select, insert, update
on stocktake_counting_results
to authenticated;

create temp table stocktake_counting_stock_baseline (
  transaction_count bigint not null,
  ledger_count bigint not null,
  batch_sellable bigint not null,
  product_sellable bigint not null
) on commit drop;

select set_config(
  'request.jwt.claim.sub',
  '92000000-0000-4000-8000-000000000001',
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
    '92000000-0000-4000-8000-000000000001',
    'role',
    'authenticated',
    'email',
    'pgtap.stocktake.counting@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

insert into stocktake_counting_results (kind, result)
select
  'MAIN_CREATE',
  api.create_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNTING-CREATE-001',
    'Blind continuous counting contract',
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
    'Counting lifecycle fixture.',
    '{"fixture": "stocktake-counting"}'::jsonb
  );

insert into stocktake_counting_results (kind, result)
select
  'MAIN_PREPARE',
  api.prepare_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNTING-PREPARE-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    '{"fixture": "stocktake-counting-prepare"}'::jsonb
  );

insert into stocktake_counting_results (kind, result)
select
  'MAIN_START',
  api.start_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNTING-START-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    '{"fixture": "stocktake-counting-start"}'::jsonb
  );

reset role;

-- 12-15: count input validation
set local role authenticated;

select throws_ok(
  format(
    $sql$
      select api.submit_stocktake_count(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-COUNT-NULL-001',
        %L::uuid,
        %L::uuid,
        null::bigint,
        false,
        'MANUAL_ENTRY',
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select line.id::text
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_counting_results
        where kind = 'MAIN_CREATE'
      )
    )
  ),
  'P0001',
  'STOCKTAKE_INVALID_PHYSICAL_QTY',
  'null physical quantity is rejected'
);
select throws_ok(
  format(
    $sql$
      select api.submit_stocktake_count(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-COUNT-NEGATIVE-001',
        %L::uuid,
        %L::uuid,
        -1,
        false,
        'MANUAL_ENTRY',
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select line.id::text
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_counting_results
        where kind = 'MAIN_CREATE'
      )
    )
  ),
  'P0001',
  'STOCKTAKE_INVALID_PHYSICAL_QTY',
  'negative physical quantity is rejected'
);
select throws_ok(
  format(
    $sql$
      select api.submit_stocktake_count(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-COUNT-ZERO-001',
        %L::uuid,
        %L::uuid,
        0,
        false,
        'MANUAL_ENTRY',
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select line.id::text
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_counting_results
        where kind = 'MAIN_CREATE'
      )
    )
  ),
  'P0001',
  'STOCKTAKE_ZERO_CONFIRMATION_REQUIRED',
  'zero physical quantity requires confirmation'
);
select throws_ok(
  format(
    $sql$
      select api.submit_stocktake_count(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-COUNT-METHOD-001',
        %L::uuid,
        %L::uuid,
        1,
        false,
        'MAGIC_WAND',
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select line.id::text
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_counting_results
        where kind = 'MAIN_CREATE'
      )
    )
  ),
  'P0001',
  'STOCKTAKE_COUNT_METHOD_NOT_SUPPORTED',
  'unsupported count method is rejected'
);

insert into stocktake_counting_results (kind, result)
select
  'RECEIPT_AFTER_SNAPSHOT',
  api.post_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNTING-RECEIPT-001',
    'PGTAP-STOCKTAKE-COUNTING-RECEIPT-SOURCE-001',
    '2026-07-16 08:30:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'batchId',
        '40000000-0000-4000-8000-000000000001',
        'quantity',
        2,
        'sourceLineRef',
        'PGTAP-STOCKTAKE-COUNTING-RECEIPT-LINE-001'
      )
    ),
    'Movement after stocktake snapshot.',
    '{"fixture": "stocktake-counting-cutoff"}'::jsonb
  );

reset role;

-- 16: continuous movement fixture
select is(
  (
    select result ->> 'status'
    from stocktake_counting_results
    where kind = 'RECEIPT_AFTER_SNAPSHOT'
  ),
  'POSTED',
  'receipt after snapshot is posted'
);

insert into stocktake_counting_stock_baseline (
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

set local role authenticated;

insert into stocktake_counting_results (kind, result)
select
  'COUNT_ONE',
  api.submit_stocktake_count(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNT-SUBMIT-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select line.id
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_counting_results
        where kind = 'MAIN_CREATE'
      )
    ),
    (
      select line.system_qty_at_snapshot + 3
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_counting_results
        where kind = 'MAIN_CREATE'
      )
    ),
    false,
    'MANUAL_ENTRY',
    'First physical count.',
    '{"fixture": "count-one"}'::jsonb
  );

reset role;

-- 17-32: first append-only count and server calculation
select is(
  (
    select result ->> 'status'
    from stocktake_counting_results
    where kind = 'COUNT_ONE'
  ),
  'COUNTED',
  'first count returns counted status'
);
select is(
  (
    select result ->> 'countStatusCode'
    from stocktake_counting_results
    where kind = 'COUNT_ONE'
  ),
  'COUNTED',
  'first count response exposes counted line status'
);
select ok(
  not (
    (
      select result
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    ) ? 'expectedQty'
  ),
  'blind count response omits expected quantity'
);
select ok(
  not (
    (
      select result
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    ) ? 'varianceQty'
  ),
  'blind count response omits variance'
);
select is(
  (
    select count(*)
    from operations.stocktake_count_attempts attempt
    where attempt.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    )
  ),
  1::bigint,
  'first count creates one attempt'
);
select is(
  (
    select attempt.attempt_no
    from operations.stocktake_count_attempts attempt
    where attempt.id = (
      select (result ->> 'countAttemptId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  1,
  'first count uses attempt number one'
);
select ok(
  (
    select attempt.count_cutoff_ledger_seq
    from operations.stocktake_count_attempts attempt
    where attempt.id = (
      select (result ->> 'countAttemptId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ) > (
    select stocktake.snapshot_ledger_seq
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    )
  ),
  'count cutoff advances beyond the start snapshot'
);
select is(
  (
    select attempt.expected_qty_at_count
    from operations.stocktake_count_attempts attempt
    where attempt.id = (
      select (result ->> 'countAttemptId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  (
    select
      line.system_qty_at_snapshot
      + coalesce(sum(entry.quantity_delta), 0)::bigint
    from operations.stocktake_lines line
    join operations.stocktakes stocktake
      on stocktake.id = line.stocktake_id
    join operations.stocktake_count_attempts attempt
      on attempt.stocktake_line_id = line.id
     and attempt.id = (
       select (result ->> 'countAttemptId')::uuid
       from stocktake_counting_results
       where kind = 'COUNT_ONE'
     )
    left join inventory.stock_ledger_entries entry
      on entry.organization_id = line.organization_id
     and entry.product_id = line.product_id
     and entry.batch_id = line.batch_id
     and entry.bucket_code = line.bucket_code
     and entry.ledger_seq > stocktake.snapshot_ledger_seq
     and entry.ledger_seq <= attempt.count_cutoff_ledger_seq
    group by line.system_qty_at_snapshot
  ),
  'expected quantity includes ledger movement through the cutoff'
);
select is(
  (
    select attempt.variance_qty
    from operations.stocktake_count_attempts attempt
    where attempt.id = (
      select (result ->> 'countAttemptId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  (
    select attempt.physical_qty - attempt.expected_qty_at_count
    from operations.stocktake_count_attempts attempt
    where attempt.id = (
      select (result ->> 'countAttemptId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'variance equals physical minus expected'
);
select is(
  (
    select line.final_attempt_id::text
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  (
    select result ->> 'countAttemptId'
    from stocktake_counting_results
    where kind = 'COUNT_ONE'
  ),
  'line points to the first final attempt'
);
select is(
  (
    select line.final_physical_qty
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  (
    select attempt.physical_qty
    from operations.stocktake_count_attempts attempt
    where attempt.id = (
      select (result ->> 'countAttemptId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'line stores the first final physical quantity'
);
select is(
  (
    select line.count_status_code
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'COUNTED',
  'first count marks the line counted'
);
select is(
  (
    select line.review_status_code
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'READY',
  'first count makes the line ready for review'
);
select is(
  (
    select attempt.counted_by::text
    from operations.stocktake_count_attempts attempt
    where attempt.id = (
      select (result ->> 'countAttemptId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  '92000000-0000-4000-8000-000000000001',
  'count attempt stores the authenticated Admin'
);
select is(
  (
    select attempt.process_name
    from operations.stocktake_count_attempts attempt
    where attempt.id = (
      select (result ->> 'countAttemptId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  null,
  'authenticated count does not use a system process actor'
);
select is(
  (
    select command.status_code
    from inventory.idempotency_commands command
    where command.scope = 'SUBMIT_STOCKTAKE_COUNT'
      and command.key = 'PGTAP-STOCKTAKE-COUNT-SUBMIT-001'
  ),
  'SUCCEEDED',
  'count idempotency command succeeds'
);

set local role authenticated;

insert into stocktake_counting_results (kind, result)
select
  'COUNT_ONE_REPLAY',
  api.submit_stocktake_count(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNT-SUBMIT-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    ),
    (
      select line.system_qty_at_snapshot + 3
      from operations.stocktake_lines line
      where line.id = (
        select (result ->> 'stocktakeLineId')::uuid
        from stocktake_counting_results
        where kind = 'COUNT_ONE'
      )
    ),
    false,
    'MANUAL_ENTRY',
    'First physical count.',
    '{"fixture": "count-one"}'::jsonb
  );

reset role;

-- 33-40: count idempotency and blind read boundary
select is(
  (
    select result
    from stocktake_counting_results
    where kind = 'COUNT_ONE_REPLAY'
  ),
  (
    select result
    from stocktake_counting_results
    where kind = 'COUNT_ONE'
  ),
  'count replay returns the stored response'
);
select is(
  (
    select count(*)
    from operations.stocktake_count_attempts attempt
    where attempt.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    )
  ),
  1::bigint,
  'count replay creates no duplicate attempt'
);

set local role authenticated;

select throws_ok(
  format(
    $sql$
      select api.submit_stocktake_count(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-COUNT-SUBMIT-001',
        %L::uuid,
        %L::uuid,
        %s,
        false,
        'MANUAL_ENTRY',
        'Changed count payload.',
        '{"fixture": "count-one"}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select result ->> 'stocktakeLineId'
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    ),
    (
      select line.system_qty_at_snapshot + 4
      from operations.stocktake_lines line
      where line.id = (
        select (result ->> 'stocktakeLineId')::uuid
        from stocktake_counting_results
        where kind = 'COUNT_ONE'
      )
    )
  ),
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'count key cannot be reused with another payload'
);

select throws_ok(
  format(
    $sql$
      select api.submit_stocktake_count(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-COUNT-FRESH-CONFLICT-001',
        %L::uuid,
        %L::uuid,
        1,
        false,
        'MANUAL_ENTRY',
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select result ->> 'stocktakeLineId'
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'P0001',
  'STOCKTAKE_COUNT_CONFLICT',
  'a counted line requires an explicit recount before another attempt'
);

reset role;

select ok(
  not (
    (
      select to_jsonb(blind_line)
      from api.stocktake_blind_lines blind_line
      where blind_line.stocktake_line_id = (
        select (result ->> 'stocktakeLineId')::uuid
        from stocktake_counting_results
        where kind = 'COUNT_ONE'
      )
    ) ? 'expected_qty_at_count'
  ),
  'blind line view still omits expected quantity after counting'
);
select ok(
  (
    select stocktake.variance_line_count is null
    from api.stocktake_list stocktake
    where stocktake.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    )
  ),
  'blind counting hides the session variance summary'
);

set local role authenticated;

insert into stocktake_counting_results (kind, result)
select
  'RECOUNT_REQUEST',
  api.request_stocktake_recount(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-RECOUNT-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    ),
    'Physical count requires verification.',
    '{"fixture": "recount"}'::jsonb
  );

reset role;

-- 41-45: recount request preserves prior attempt
select is(
  (
    select result ->> 'status'
    from stocktake_counting_results
    where kind = 'RECOUNT_REQUEST'
  ),
  'RECOUNT_REQUESTED',
  'recount request returns the requested status'
);
select is(
  (
    select line.count_status_code
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'RECOUNT_REQUESTED',
  'recount request changes the line count status'
);
select is(
  (
    select line.review_status_code
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'PENDING',
  'recount request returns the line to pending review'
);
select is(
  (
    select count(*)
    from operations.stocktake_count_attempts attempt
    where attempt.stocktake_line_id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  1::bigint,
  'recount request preserves the first attempt'
);
select is(
  (
    select line.final_attempt_id::text
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  (
    select result ->> 'countAttemptId'
    from stocktake_counting_results
    where kind = 'COUNT_ONE'
  ),
  'recount request preserves the previous final attempt reference'
);

set local role authenticated;

insert into stocktake_counting_results (kind, result)
select
  'RECOUNT_REPLAY',
  api.request_stocktake_recount(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-RECOUNT-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    ),
    'Physical count requires verification.',
    '{"fixture": "recount"}'::jsonb
  );

reset role;

-- 46-48: recount idempotency
select is(
  (
    select result
    from stocktake_counting_results
    where kind = 'RECOUNT_REPLAY'
  ),
  (
    select result
    from stocktake_counting_results
    where kind = 'RECOUNT_REQUEST'
  ),
  'recount replay returns the stored response'
);
select is(
  (
    select line.count_status_code
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'RECOUNT_REQUESTED',
  'recount replay leaves the line awaiting recount'
);

set local role authenticated;

select throws_ok(
  format(
    $sql$
      select api.request_stocktake_recount(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-RECOUNT-001',
        %L::uuid,
        %L::uuid,
        'Changed recount reason.',
        '{"fixture": "recount"}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select result ->> 'stocktakeLineId'
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'recount key cannot be reused with another payload'
);

insert into stocktake_counting_results (kind, result)
select
  'COUNT_TWO',
  api.submit_stocktake_count(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNT-SUBMIT-002',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    ),
    (
      select line.system_qty_at_snapshot + 1
      from operations.stocktake_lines line
      where line.id = (
        select (result ->> 'stocktakeLineId')::uuid
        from stocktake_counting_results
        where kind = 'COUNT_ONE'
      )
    ),
    false,
    'SCANNER',
    'Second physical count.',
    '{"fixture": "count-two"}'::jsonb
  );

reset role;

-- 49-58: recount creates a second append-only attempt
select is(
  (
    select result ->> 'status'
    from stocktake_counting_results
    where kind = 'COUNT_TWO'
  ),
  'COUNTED',
  'second count returns counted status'
);
select is(
  (
    select count(*)
    from operations.stocktake_count_attempts attempt
    where attempt.stocktake_line_id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  2::bigint,
  'second count creates a second attempt'
);
select is(
  (
    select array_agg(attempt.attempt_no order by attempt.attempt_no)
    from operations.stocktake_count_attempts attempt
    where attempt.stocktake_line_id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  array[1, 2]::integer[],
  'attempt history preserves attempts one and two'
);
select is(
  (
    select attempt.physical_qty
    from operations.stocktake_count_attempts attempt
    where attempt.stocktake_line_id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
      and attempt.attempt_no = 1
  ),
  (
    select line.system_qty_at_snapshot + 3
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'first attempt remains unchanged'
);
select is(
  (
    select line.final_attempt_id::text
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  (
    select result ->> 'countAttemptId'
    from stocktake_counting_results
    where kind = 'COUNT_TWO'
  ),
  'line points to the second final attempt'
);
select is(
  (
    select line.count_attempt_no
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  2,
  'line stores the second attempt number'
);
select is(
  (
    select line.count_status_code
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'COUNTED',
  'second count restores counted status'
);
select is(
  (
    select line.review_status_code
    from operations.stocktake_lines line
    where line.id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  'READY',
  'second count restores ready review status'
);
select is(
  (
    select attempt.expected_qty_at_count
    from operations.stocktake_count_attempts attempt
    where attempt.id = (
      select (result ->> 'countAttemptId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_TWO'
    )
  ),
  (
    select operations.calculate_stocktake_expected(
      line.organization_id,
      line.stocktake_id,
      line.id,
      attempt.count_cutoff_ledger_seq
    )
    from operations.stocktake_lines line
    join operations.stocktake_count_attempts attempt
      on attempt.stocktake_line_id = line.id
    where attempt.id = (
      select (result ->> 'countAttemptId')::uuid
      from stocktake_counting_results
      where kind = 'COUNT_TWO'
    )
  ),
  'second attempt uses the server ledger formula'
);
select ok(
  not (
    (
      select result
      from stocktake_counting_results
      where kind = 'COUNT_TWO'
    ) ? 'expectedQty'
  ),
  'blind recount response still omits expected quantity'
);

-- 59: organization isolation
set local role authenticated;

select throws_ok(
  format(
    $sql$
      select api.submit_stocktake_count(
        '00000000-0000-4000-8000-000000000003'::uuid,
        'PGTAP-STOCKTAKE-COUNT-CROSS-ORG-001',
        %L::uuid,
        %L::uuid,
        1,
        false,
        'MANUAL_ENTRY',
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'MAIN_CREATE'
    ),
    (
      select result ->> 'stocktakeLineId'
      from stocktake_counting_results
      where kind = 'COUNT_ONE'
    )
  ),
  '42501',
  'ORGANIZATION_ACCESS_DENIED',
  'cross-organization count is denied'
);

-- Second non-blind session for completion lifecycle.
insert into stocktake_counting_results (kind, result)
select
  'SECOND_CREATE',
  api.create_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNTING-CREATE-002',
    'Non-blind completion contract',
    'AD_HOC',
    'CONTINUOUS',
    'NON_BLIND',
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
    '2026-07-16 09:00:00+07'::timestamptz,
    'Completion lifecycle fixture.',
    '{"fixture": "stocktake-completion"}'::jsonb
  );

insert into stocktake_counting_results (kind, result)
select
  'SECOND_PREPARE',
  api.prepare_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNTING-PREPARE-002',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    ),
    '{"fixture": "stocktake-completion-prepare"}'::jsonb
  );

insert into stocktake_counting_results (kind, result)
select
  'SECOND_START',
  api.start_stocktake(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNTING-START-002',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    ),
    '{"fixture": "stocktake-completion-start"}'::jsonb
  );

select throws_ok(
  format(
    $sql$
      select api.complete_stocktake_counting(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-COMPLETE-001',
        %L::uuid,
        '{"fixture": "stocktake-completion"}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    )
  ),
  'P0001',
  'STOCKTAKE_COUNT_REQUIRED',
  'counting cannot complete while a line is uncounted'
);

insert into stocktake_counting_results (kind, result)
select
  'SECOND_COUNT',
  api.submit_stocktake_count(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COUNT-SUBMIT-003',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    ),
    (
      select line.id
      from operations.stocktake_lines line
      where line.stocktake_id = (
        select (result ->> 'stocktakeId')::uuid
        from stocktake_counting_results
        where kind = 'SECOND_CREATE'
      )
    ),
    0,
    true,
    'MANUAL_ENTRY',
    'Completion count.',
    '{"fixture": "stocktake-completion-count"}'::jsonb
  );

reset role;

-- 60-65: completion precondition and non-blind count response
select is(
  (
    select result ->> 'status'
    from stocktake_counting_results
    where kind = 'SECOND_COUNT'
  ),
  'COUNTED',
  'non-blind line can be counted'
);
select ok(
  (
    select result
    from stocktake_counting_results
    where kind = 'SECOND_COUNT'
  ) ? 'expectedQty',
  'non-blind count response includes expected quantity'
);
select ok(
  (
    select result
    from stocktake_counting_results
    where kind = 'SECOND_COUNT'
  ) ? 'varianceQty',
  'non-blind count response includes variance'
);
select is(
  (
    select result ->> 'zeroConfirmed'
    from stocktake_counting_results
    where kind = 'SECOND_COUNT'
  ),
  'true',
  'explicit zero count is accepted and confirmed'
);
select is(
  (
    select count(*)
    from api.stocktake_count_attempts attempt
    where attempt.stocktake_line_id = (
      select (result ->> 'stocktakeLineId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_COUNT'
    )
  ),
  1::bigint,
  'non-blind counting exposes its attempt history'
);

set local role authenticated;

insert into stocktake_counting_results (kind, result)
select
  'SECOND_COMPLETE',
  api.complete_stocktake_counting(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COMPLETE-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    ),
    '{"fixture": "stocktake-completion"}'::jsonb
  );

reset role;

-- 66-70: counting completion reaches review
select is(
  (
    select result ->> 'status'
    from stocktake_counting_results
    where kind = 'SECOND_COMPLETE'
  ),
  'REVIEW',
  'complete counting returns review status'
);
select is(
  (
    select stocktake.status_code
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    )
  ),
  'REVIEW',
  'complete counting transitions the session to review'
);
select ok(
  (
    select stocktake.counting_completed_at is not null
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    )
  ),
  'complete counting stores the completion timestamp'
);
select is(
  (
    select count(*)
    from api.stocktake_review_lines review_line
    where review_line.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    )
  ),
  1::bigint,
  'review lines become visible after counting completes'
);
select is(
  (
    select count(*)
    from api.stocktake_count_attempts attempt
    where attempt.stocktake_id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    )
  ),
  1::bigint,
  'attempt details remain available in review'
);

set local role authenticated;

insert into stocktake_counting_results (kind, result)
select
  'SECOND_COMPLETE_REPLAY',
  api.complete_stocktake_counting(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-STOCKTAKE-COMPLETE-001',
    (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    ),
    '{"fixture": "stocktake-completion"}'::jsonb
  );

reset role;

-- 71-74: completion idempotency and terminal state guards
select is(
  (
    select result
    from stocktake_counting_results
    where kind = 'SECOND_COMPLETE_REPLAY'
  ),
  (
    select result
    from stocktake_counting_results
    where kind = 'SECOND_COMPLETE'
  ),
  'complete-counting replay returns the stored response'
);
select is(
  (
    select stocktake.status_code
    from operations.stocktakes stocktake
    where stocktake.id = (
      select (result ->> 'stocktakeId')::uuid
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    )
  ),
  'REVIEW',
  'complete-counting replay leaves the session in review'
);

set local role authenticated;

select throws_ok(
  format(
    $sql$
      select api.submit_stocktake_count(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-COUNT-AFTER-REVIEW-001',
        %L::uuid,
        %L::uuid,
        1,
        false,
        'MANUAL_ENTRY',
        null,
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    ),
    (
      select result ->> 'stocktakeLineId'
      from stocktake_counting_results
      where kind = 'SECOND_COUNT'
    )
  ),
  'P0001',
  'STOCKTAKE_INVALID_STATE',
  'count submission is rejected after review'
);
select throws_ok(
  format(
    $sql$
      select api.request_stocktake_recount(
        '00000000-0000-4000-8000-000000000001'::uuid,
        'PGTAP-STOCKTAKE-RECOUNT-AFTER-REVIEW-001',
        %L::uuid,
        %L::uuid,
        'Too late for recount.',
        '{}'::jsonb
      )
    $sql$,
    (
      select result ->> 'stocktakeId'
      from stocktake_counting_results
      where kind = 'SECOND_CREATE'
    ),
    (
      select result ->> 'stocktakeLineId'
      from stocktake_counting_results
      where kind = 'SECOND_COUNT'
    )
  ),
  'P0001',
  'STOCKTAKE_INVALID_STATE',
  'recount request is rejected after review'
);

reset role;

-- 75-78: counting lifecycle remains stock-neutral
select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select transaction_count
    from stocktake_counting_stock_baseline
  ),
  'counting commands create no stock transaction'
);
select is(
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select ledger_count
    from stocktake_counting_stock_baseline
  ),
  'counting commands create no ledger entry'
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
  (
    select batch_sellable
    from stocktake_counting_stock_baseline
  ),
  'counting commands do not change the batch projection'
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
  (
    select product_sellable
    from stocktake_counting_stock_baseline
  ),
  'counting commands do not change the product projection'
);

select * from finish();

rollback;
