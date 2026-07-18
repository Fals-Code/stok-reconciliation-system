begin;

create extension if not exists pgtap with schema extensions;

select plan(111);

-- Function contract and trusted execution.
select has_function(
  'notification'::name,
  'ensure_stocktake_recount_rule'::name,
  array['uuid', 'timestamp with time zone']::text[]
);

select has_function(
  'notification'::name,
  'ensure_stocktake_post_failed_rule'::name,
  array['uuid', 'timestamp with time zone']::text[]
);

select has_function(
  'notification'::name,
  'evaluate_stocktake_recounts'::name,
  array[
    'uuid',
    'text',
    'timestamp with time zone',
    'text',
    'uuid',
    'text'
  ]::text[]
);

select has_function(
  'notification'::name,
  'evaluate_stocktake_post_failures'::name,
  array[
    'uuid',
    'text',
    'timestamp with time zone',
    'text',
    'uuid',
    'text'
  ]::text[]
);

select function_returns(
  'notification',
  'ensure_stocktake_recount_rule',
  array['uuid', 'timestamptz']::text[],
  'uuid'
);

select function_returns(
  'notification',
  'ensure_stocktake_post_failed_rule',
  array['uuid', 'timestamptz']::text[],
  'uuid'
);

select function_returns(
  'notification',
  'evaluate_stocktake_recounts',
  array[
    'uuid',
    'text',
    'timestamptz',
    'text',
    'uuid',
    'text'
  ]::text[],
  'jsonb'
);

select function_returns(
  'notification',
  'evaluate_stocktake_post_failures',
  array[
    'uuid',
    'text',
    'timestamptz',
    'text',
    'uuid',
    'text'
  ]::text[],
  'jsonb'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.ensure_stocktake_recount_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'service role may provision stocktake recount rule'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.ensure_stocktake_recount_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'authenticated clients cannot provision recount rule'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.ensure_stocktake_post_failed_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'service role may provision stocktake post failure rule'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.ensure_stocktake_post_failed_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'authenticated clients cannot provision post failure rule'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.evaluate_stocktake_recounts(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'service role may evaluate stocktake recounts'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.evaluate_stocktake_recounts(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot evaluate stocktake recounts'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.evaluate_stocktake_post_failures(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'service role may evaluate stocktake post failures'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.evaluate_stocktake_post_failures(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot evaluate stocktake post failures'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.ensure_stocktake_recount_rule(uuid,timestamptz)'::regprocedure
  ),
  'recount rule provisioning is security definer'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.ensure_stocktake_post_failed_rule(uuid,timestamptz)'::regprocedure
  ),
  'post failure rule provisioning is security definer'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.evaluate_stocktake_recounts(uuid,text,timestamptz,text,uuid,text)'::regprocedure
  ),
  'recount evaluator is security definer'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.evaluate_stocktake_post_failures(uuid,text,timestamptz,text,uuid,text)'::regprocedure
  ),
  'post failure evaluator is security definer'
);

select ok(
  position(
    'pg_advisory_xact_lock'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_stocktake_recounts(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'recount evaluator serializes organization execution'
);

select ok(
  position(
    'pg_advisory_xact_lock'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_stocktake_post_failures(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'post failure evaluator serializes organization execution'
);

select ok(
  position(
    'stocktake_lines'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_stocktake_recounts(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'recount evaluator reads stocktake line state'
);

select ok(
  position(
    'reconciliation.runs'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_stocktake_post_failures(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'post failure evaluator reads linked reconciliation state'
);

select ok(
  position(
    'make_interval'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_stocktake_post_failures(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'post failure evaluator applies stale posting threshold'
);

select ok(
  position(
    'update operations.stocktakes'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_stocktake_post_failures(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) = 0,
  'post failure evaluator does not mutate stocktake source'
);

select ok(
  position(
    'update operations.stocktake_lines'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_stocktake_recounts(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) = 0,
  'recount evaluator does not mutate stocktake lines'
);

-- Deterministic commands used by source fixtures.
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
values
(
  'e7100000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP_STOCKTAKE_SOURCE',
  'RECOUNT-STOCKTAKE',
  repeat('a', 64),
  'SUCCEEDED',
  '2026-07-22 08:00:00+07'::timestamptz,
  '2026-07-22 08:01:00+07'::timestamptz,
  null,
  '{"status":"REVIEW"}'::jsonb,
  null,
  null
),
(
  'e7100000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP_STOCKTAKE_SOURCE',
  'EXCEPTION-STOCKTAKE',
  repeat('b', 64),
  'SUCCEEDED',
  '2026-07-22 09:00:00+07'::timestamptz,
  '2026-07-22 09:01:00+07'::timestamptz,
  null,
  '{"status":"EXCEPTION"}'::jsonb,
  null,
  null
),
(
  'e7100000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP_STOCKTAKE_SOURCE',
  'POSTING-STOCKTAKE',
  repeat('c', 64),
  'SUCCEEDED',
  '2026-07-22 10:00:00+07'::timestamptz,
  '2026-07-22 10:01:00+07'::timestamptz,
  null,
  '{"status":"DRAFT"}'::jsonb,
  null,
  null
),
(
  'e7100000-0000-4000-8000-000000000004'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP_STOCKTAKE_APPROVAL',
  'POSTING-STOCKTAKE-APPROVAL',
  repeat('d', 64),
  'SUCCEEDED',
  '2026-07-22 10:10:00+07'::timestamptz,
  '2026-07-22 10:11:00+07'::timestamptz,
  null,
  '{"status":"APPROVED"}'::jsonb,
  null,
  null
),
(
  'e7100000-0000-4000-8000-000000000005'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP_STOCKTAKE_RECONCILIATION',
  'FAILED-POST-RECONCILIATION',
  repeat('e', 64),
  'FAILED',
  '2026-07-24 08:00:00+07'::timestamptz,
  '2026-07-24 08:05:00+07'::timestamptz,
  null,
  '{}'::jsonb,
  'POST_STOCKTAKE_RECONCILIATION_FAILED',
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
  version_no,
  current_approval_id,
  approval_version_no,
  approved_by,
  approval_process_name
)
values
(
  'e8200000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'STK-PGTAP-RECOUNT-001',
  'Recount notification fixture',
  'AD_HOC',
  'CONTINUOUS',
  'NON_BLIND',
  'REVIEW',
  '{"mode":"BATCHES","batchIds":["40000000-0000-4000-8000-000000000001"],"bucketCodes":["SELLABLE"]}'::jsonb,
  '{"units":0,"percent":0}'::jsonb,
  'stocktake-continuous-v1',
  'Asia/Jakarta',
  null,
  100,
  '2026-07-22 08:02:00+07'::timestamptz,
  '2026-07-22 08:20:00+07'::timestamptz,
  null,
  null,
  null,
  null,
  null,
  'pgtap.stocktake_source',
  'e7100000-0000-4000-8000-000000000001'::uuid,
  'Fixture for stocktake recount notification.',
  '{"fixture":"notification-stocktake"}'::jsonb,
  '2026-07-22 08:00:00+07'::timestamptz,
  '2026-07-22 08:30:00+07'::timestamptz,
  1,
  null,
  null,
  null,
  null
),
(
  'e8200000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'STK-PGTAP-EXCEPTION-001',
  'Exception notification fixture',
  'AD_HOC',
  'CONTINUOUS',
  'NON_BLIND',
  'EXCEPTION',
  '{"mode":"BATCHES","batchIds":["40000000-0000-4000-8000-000000000001"],"bucketCodes":["SELLABLE"]}'::jsonb,
  '{"units":0,"percent":0}'::jsonb,
  'stocktake-continuous-v1',
  'Asia/Jakarta',
  null,
  100,
  '2026-07-22 09:02:00+07'::timestamptz,
  null,
  null,
  null,
  null,
  null,
  null,
  'pgtap.stocktake_source',
  'e7100000-0000-4000-8000-000000000002'::uuid,
  'Fixture for uncertain posting result.',
  '{"fixture":"notification-stocktake","errorCode":"POST_RESULT_UNCERTAIN"}'::jsonb,
  '2026-07-22 09:00:00+07'::timestamptz,
  '2026-07-22 09:10:00+07'::timestamptz,
  1,
  null,
  null,
  null,
  null
),
(
  'e8200000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'STK-PGTAP-POSTING-001',
  'Stale posting notification fixture',
  'CYCLE',
  'CONTINUOUS',
  'BLIND',
  'DRAFT',
  '{"mode":"BATCHES","batchIds":["40000000-0000-4000-8000-000000000001"],"bucketCodes":["SELLABLE"]}'::jsonb,
  '{"units":0,"percent":0}'::jsonb,
  'stocktake-continuous-v1',
  'Asia/Jakarta',
  null,
  100,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  'pgtap.stocktake_source',
  'e7100000-0000-4000-8000-000000000003'::uuid,
  'Fixture for stale POSTING state.',
  '{"fixture":"notification-stocktake"}'::jsonb,
  '2026-07-22 10:00:00+07'::timestamptz,
  '2026-07-22 10:01:00+07'::timestamptz,
  1,
  null,
  null,
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
  version_no,
  review_decision_code
)
values (
  'e8300000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'e8200000-0000-4000-8000-000000000001'::uuid,
  1,
  '30000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'SELLABLE',
  'SER-NIA-30',
  'Serum Niacinamide 30 ml',
  'SER-2608-A',
  '2026-08-01'::date,
  25,
  null,
  null,
  null,
  null,
  null,
  null,
  1,
  'RECOUNT_REQUESTED',
  'PENDING',
  null,
  'Count again before approval.',
  null,
  '2026-07-22 08:05:00+07'::timestamptz,
  '2026-07-22 08:25:00+07'::timestamptz,
  1,
  'RECOUNT_REQUIRED'
);

insert into operations.stocktake_approvals (
  id,
  organization_id,
  stocktake_id,
  approval_version_no,
  approval_hash,
  approved_at,
  approved_by,
  process_name,
  stocktake_version_no,
  snapshot_ledger_seq,
  tolerance_policy_snapshot,
  rule_version,
  line_count,
  variance_line_count,
  total_variance_qty,
  idempotency_command_id,
  note,
  metadata,
  created_at
)
values (
  'e8400000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'e8200000-0000-4000-8000-000000000003'::uuid,
  1,
  repeat('f', 64),
  '2026-07-22 10:10:00+07'::timestamptz,
  null,
  'pgtap.stocktake_approval',
  1,
  100,
  '{"units":0,"percent":0}'::jsonb,
  'stocktake-continuous-v1',
  1,
  0,
  0,
  'e7100000-0000-4000-8000-000000000004'::uuid,
  'Approval fixture for stale posting.',
  '{"fixture":"notification-stocktake"}'::jsonb,
  '2026-07-22 10:10:00+07'::timestamptz
);

update operations.stocktakes
set
  status_code = 'POSTING',
  current_approval_id =
    'e8400000-0000-4000-8000-000000000001'::uuid,
  approval_version_no = 1,
  approved_at = '2026-07-22 10:10:00+07'::timestamptz,
  approved_by = null,
  approval_process_name = 'pgtap.stocktake_approval',
  version_no = 3
where id =
  'e8200000-0000-4000-8000-000000000003'::uuid;

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
  'e8500000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'RCN-PGTAP-STOCKTAKE-FAILED-001',
  'POST_STOCKTAKE',
  'SYSTEM',
  'FAILED',
  '{}'::jsonb,
  array['LEDGER_BATCH_PROJECTION']::text[],
  'core-integrity-v7',
  0,
  100,
  '2026-07-24 08:00:00+07'::timestamptz,
  '2026-07-24 08:05:00+07'::timestamptz,
  null,
  'pgtap.stocktake_reconciliation',
  'e7100000-0000-4000-8000-000000000005'::uuid,
  '{"integrityStatus":"UNKNOWN"}'::jsonb,
  'POST_STOCKTAKE_RECONCILIATION_FAILED',
  '{"message":"projection verification failed"}'::jsonb,
  jsonb_build_object(
    'fixture',
    'notification-stocktake',
    'stocktakeId',
    'e8200000-0000-4000-8000-000000000002'
  ),
  '2026-07-24 08:00:00+07'::timestamptz,
  '2026-07-24 08:05:00+07'::timestamptz
);

create temporary table stocktake_source_before as
select
  recount.status_code as recount_status_code,
  recount_line.count_status_code
    as recount_line_count_status_code,
  recount_line.review_decision_code
    as recount_line_review_decision_code,
  exception_stocktake.status_code
    as exception_status_code,
  posting_stocktake.status_code
    as posting_status_code,
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  )::bigint as transaction_count,
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  )::bigint as ledger_count
from operations.stocktakes recount
join operations.stocktake_lines recount_line
  on recount_line.stocktake_id = recount.id
cross join operations.stocktakes exception_stocktake
cross join operations.stocktakes posting_stocktake
where recount.id =
      'e8200000-0000-4000-8000-000000000001'::uuid
  and exception_stocktake.id =
      'e8200000-0000-4000-8000-000000000002'::uuid
  and posting_stocktake.id =
      'e8200000-0000-4000-8000-000000000003'::uuid;

create temporary table recount_initial_evaluation as
select notification.evaluate_stocktake_recounts(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-recount:initial',
  '2026-07-25 08:00:00+07'::timestamptz,
  'SCHEDULED',
  'e9600000-0000-4000-8000-000000000001'::uuid,
  'pgtap.stocktake_recount_evaluator'
) as result;

-- Initial recount episode.
select is(
  (select result ->> 'action' from recount_initial_evaluation),
  'COMPLETED',
  'initial recount evaluation completes'
);

select is(
  (select result ->> 'status' from recount_initial_evaluation),
  'SUCCEEDED',
  'initial recount evaluation succeeds'
);

select is(
  (
    select (result ->> 'evaluatedCount')::integer
    from recount_initial_evaluation
  ),
  3,
  'recount evaluator examines three stocktakes'
);

select is(
  (
    select (result ->> 'createdCount')::integer
    from recount_initial_evaluation
  ),
  1,
  'recount evaluator creates one notification'
);

select is(
  (
    select (result ->> 'skippedCount')::integer
    from recount_initial_evaluation
  ),
  2,
  'recount evaluator skips unaffected stocktakes'
);

select is(
  (
    select category_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'STOCKTAKE_RECOUNT_REQUIRED'
  ),
  'STOCKTAKE',
  'recount rule belongs to stocktake category'
);

select is(
  (
    select trigger_mode_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'STOCKTAKE_RECOUNT_REQUIRED'
  ),
  'HYBRID',
  'recount rule is hybrid'
);

select is(
  (
    select action_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'STOCKTAKE_RECOUNT_REQUIRED'
  ),
  'OPEN_STOCKTAKE_RECOUNT_LINES',
  'recount rule recommends recount line view'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  1::bigint,
  'one active recount notification is created'
);

select is(
  (
    select stage_code
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'RECOUNT_REQUIRED',
  'recount notification uses recount stage'
);

select is(
  (
    select severity_code
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'HIGH',
  'recount notification uses HIGH severity'
);

select is(
  (
    select condition_started_at
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  (
    select updated_at
    from operations.stocktake_lines
    where id =
      'e8300000-0000-4000-8000-000000000001'::uuid
  ),
  'recount episode starts from earliest matching line update'
);

select is(
  (
    select action_route
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  '/stocktakes/e8200000-0000-4000-8000-000000000001?filter=recount-required',
  'recount notification deep-links with recount filter'
);

select is(
  (
    select (
      source_snapshot ->> 'recountRequiredLineCount'
    )::bigint
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  1::bigint,
  'recount source snapshot stores matching line count'
);

select is(
  (
    select episode_no
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  1,
  'initial recount condition creates episode one'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select id
      from notification.notifications
      where rule_code_snapshot =
        'STOCKTAKE_RECOUNT_REQUIRED'
        and entity_id =
          'e8200000-0000-4000-8000-000000000001'::uuid
    )
      and event_type_code = 'CREATED'
  ),
  1::bigint,
  'recount episode records CREATED event'
);

select is(
  (
    select status_code
    from operations.stocktakes
    where id =
      'e8200000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select recount_status_code
    from stocktake_source_before
  ),
  'recount evaluator does not change stocktake status'
);

select is(
  (
    select count_status_code
    from operations.stocktake_lines
    where id =
      'e8300000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select recount_line_count_status_code
    from stocktake_source_before
  ),
  'recount evaluator does not change line count state'
);

select is(
  (
    select review_decision_code
    from operations.stocktake_lines
    where id =
      'e8300000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select recount_line_review_decision_code
    from stocktake_source_before
  ),
  'recount evaluator does not change review decision'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select transaction_count
    from stocktake_source_before
  ),
  'recount evaluator creates no stock transaction'
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
    from stocktake_source_before
  ),
  'recount evaluator creates no ledger movement'
);

create temporary table recount_replay_evaluation as
select notification.evaluate_stocktake_recounts(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-recount:initial',
  '2026-07-25 09:00:00+07'::timestamptz,
  'MANUAL',
  'e9600000-0000-4000-8000-000000000099'::uuid,
  'pgtap.stocktake_recount_evaluator'
) as result;

select is(
  (select result ->> 'action' from recount_replay_evaluation),
  'REPLAYED',
  'recount evaluator replays idempotency key'
);

select is(
  (
    select occurrence_count
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  1,
  'recount replay does not increment occurrence'
);

-- Clear recount and resolve episode one.
update operations.stocktake_lines
set
  count_status_code = 'COUNTED',
  review_status_code = 'REVIEWED',
  review_decision_code = 'MATCHED',
  review_note = null,
  version_no = version_no + 1
where id =
  'e8300000-0000-4000-8000-000000000001'::uuid;

create temporary table recount_resolved_evaluation as
select notification.evaluate_stocktake_recounts(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-recount:resolved',
  '2026-07-25 10:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  'e9600000-0000-4000-8000-000000000002'::uuid,
  'pgtap.stocktake_recount_evaluator'
) as result;

select is(
  (
    select (result ->> 'resolvedCount')::integer
    from recount_resolved_evaluation
  ),
  1,
  'zero recount lines resolves one notification'
);

select is(
  (
    select lifecycle_status_code
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and episode_no = 1
  ),
  'RESOLVED',
  'recount episode one becomes resolved'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and episode_no = 1
  ),
  'RECOUNT_REQUIRED_LINE_COUNT_ZERO',
  'recount resolution records zero-line reason'
);

select is(
  (
    select status_code
    from operations.stocktakes
    where id =
      'e8200000-0000-4000-8000-000000000001'::uuid
  ),
  'REVIEW',
  'notification resolution does not advance stocktake'
);

-- Recount returns and creates episode two.
update operations.stocktake_lines
set
  count_status_code = 'RECOUNT_REQUESTED',
  review_status_code = 'PENDING',
  review_decision_code = 'RECOUNT_REQUIRED',
  review_note = 'Second recount requested.',
  version_no = version_no + 1
where id =
  'e8300000-0000-4000-8000-000000000001'::uuid;

create temporary table recount_recurrence_evaluation as
select notification.evaluate_stocktake_recounts(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-recount:recurrence',
  '2026-07-25 11:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  'e9600000-0000-4000-8000-000000000003'::uuid,
  'pgtap.stocktake_recount_evaluator'
) as result;

select is(
  (
    select (result ->> 'createdCount')::integer
    from recount_recurrence_evaluation
  ),
  1,
  'recount recurrence creates one new episode'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'recount recurrence preserves two episodes'
);

select is(
  (
    select episode_no
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  2,
  'recount recurrence creates episode two'
);

select is(
  (
    select previous_notification_id
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and episode_no = 2
  ),
  (
    select id
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and episode_no = 1
  ),
  'recount episode two links to episode one'
);

select is(
  (
    select condition_started_at
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and episode_no = 2
  ),
  (
    select updated_at
    from operations.stocktake_lines
    where id =
      'e8300000-0000-4000-8000-000000000001'::uuid
  ),
  'recount recurrence starts from refreshed line state'
);

update operations.stocktakes
set
  status_code = 'CANCELLED',
  version_no = version_no + 1
where id =
  'e8200000-0000-4000-8000-000000000001'::uuid;

create temporary table recount_cancelled_evaluation as
select notification.evaluate_stocktake_recounts(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-recount:cancelled',
  '2026-07-25 12:00:00+07'::timestamptz,
  'SCHEDULED',
  'e9600000-0000-4000-8000-000000000004'::uuid,
  'pgtap.stocktake_recount_evaluator'
) as result;

select is(
  (
    select (result ->> 'resolvedCount')::integer
    from recount_cancelled_evaluation
  ),
  1,
  'cancelled stocktake resolves recount episode'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000001'::uuid
      and episode_no = 2
  ),
  'SESSION_CANCELLED',
  'recount cancellation resolution is explicit'
);

-- Initial post failure evaluation finds EXCEPTION and stale POSTING.
create temporary table post_failure_initial_evaluation as
select notification.evaluate_stocktake_post_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-post-failure:initial',
  '2026-07-25 13:00:00+07'::timestamptz,
  'SCHEDULED',
  'e9700000-0000-4000-8000-000000000001'::uuid,
  'pgtap.stocktake_post_failure_evaluator'
) as result;

select is(
  (select result ->> 'action' from post_failure_initial_evaluation),
  'COMPLETED',
  'initial post failure evaluation completes'
);

select is(
  (select result ->> 'status' from post_failure_initial_evaluation),
  'SUCCEEDED',
  'initial post failure evaluation succeeds'
);

select is(
  (
    select (result ->> 'evaluatedCount')::integer
    from post_failure_initial_evaluation
  ),
  3,
  'post failure evaluator examines three stocktakes'
);

select is(
  (
    select (result ->> 'createdCount')::integer
    from post_failure_initial_evaluation
  ),
  2,
  'post failure evaluator creates two notifications'
);

select is(
  (
    select (result ->> 'skippedCount')::integer
    from post_failure_initial_evaluation
  ),
  1,
  'post failure evaluator skips unaffected recount stocktake'
);

select is(
  (
    select config ->> 'postingStaleMinutes'
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'STOCKTAKE_POST_FAILED'
  ),
  '30',
  'post failure rule snapshots thirty-minute stale threshold'
);

select is(
  (
    select action_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'STOCKTAKE_POST_FAILED'
  ),
  'OPEN_STOCKTAKE_DETAIL',
  'post failure rule recommends stocktake detail'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  2::bigint,
  'two active post failure notifications are created'
);

select is(
  (
    select stage_code
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'RESULT_UNCERTAIN',
  'EXCEPTION stocktake uses RESULT_UNCERTAIN stage'
);

select is(
  (
    select stage_code
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000003'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'RESULT_UNCERTAIN',
  'stale POSTING stocktake uses RESULT_UNCERTAIN stage'
);

select is(
  (
    select severity_code
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'CRITICAL',
  'stocktake post failure uses CRITICAL severity'
);

select is(
  (
    select condition_started_at
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000003'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  (
    select updated_at
    from operations.stocktakes
    where id =
      'e8200000-0000-4000-8000-000000000003'::uuid
  ),
  'stale posting condition starts from source update time'
);

select is(
  (
    select action_route
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  '/stocktakes/e8200000-0000-4000-8000-000000000002',
  'post failure notification deep-links to stocktake'
);

select is(
  (
    select source_snapshot ->> 'statusCode'
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'EXCEPTION',
  'post failure snapshot stores source status'
);

select is(
  (
    select (
      source_snapshot ->> 'postingStaleMinutes'
    )::integer
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000003'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  30,
  'post failure snapshot stores threshold'
);

select is(
  (
    select status_code
    from operations.stocktakes
    where id =
      'e8200000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select exception_status_code
    from stocktake_source_before
  ),
  'post failure evaluator does not change exception status'
);

select is(
  (
    select status_code
    from operations.stocktakes
    where id =
      'e8200000-0000-4000-8000-000000000003'::uuid
  ),
  (
    select posting_status_code
    from stocktake_source_before
  ),
  'post failure evaluator does not change posting status'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select transaction_count
    from stocktake_source_before
  ),
  'post failure evaluator creates no stock transaction'
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
    from stocktake_source_before
  ),
  'post failure evaluator creates no ledger movement'
);

create temporary table post_failure_replay_evaluation as
select notification.evaluate_stocktake_post_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-post-failure:initial',
  '2026-07-25 14:00:00+07'::timestamptz,
  'MANUAL',
  'e9700000-0000-4000-8000-000000000099'::uuid,
  'pgtap.stocktake_post_failure_evaluator'
) as result;

select is(
  (select result ->> 'action' from post_failure_replay_evaluation),
  'REPLAYED',
  'post failure evaluator replays idempotency key'
);

select is(
  (
    select sum(occurrence_count)
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and lifecycle_status_code = 'OPEN'
  ),
  2::bigint,
  'post failure replay does not increment occurrences'
);

-- Link failed post-reconciliation and escalate the same episode.
update operations.stocktakes
set
  reconciliation_run_id =
    'e8500000-0000-4000-8000-000000000001'::uuid,
  version_no = version_no + 1
where id =
  'e8200000-0000-4000-8000-000000000002'::uuid;

create temporary table post_reconciliation_failed_evaluation as
select notification.evaluate_stocktake_post_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-post-failure:reconciliation-failed',
  '2026-07-25 15:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  'e9700000-0000-4000-8000-000000000002'::uuid,
  'pgtap.stocktake_post_failure_evaluator'
) as result;

select is(
  (
    select (result ->> 'updatedCount')::integer
    from post_reconciliation_failed_evaluation
  ),
  2,
  'reconciliation failure evaluation updates both active episodes'
);

select is(
  (
    select stage_code
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'RECONCILIATION_FAILED',
  'linked failed run escalates stocktake stage'
);

select is(
  (
    select source_snapshot ->> 'reconciliationRunNo'
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'RCN-PGTAP-STOCKTAKE-FAILED-001',
  'post failure snapshot stores failed run number'
);

select is(
  (
    select source_snapshot ->> 'reconciliationErrorCode'
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'POST_STOCKTAKE_RECONCILIATION_FAILED',
  'post failure snapshot stores reconciliation error'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
  ),
  1::bigint,
  'reconciliation escalation creates no duplicate episode'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select id
      from notification.notifications
      where rule_code_snapshot =
        'STOCKTAKE_POST_FAILED'
        and entity_id =
          'e8200000-0000-4000-8000-000000000002'::uuid
    )
      and event_type_code = 'STAGE_ESCALATED'
  ),
  1::bigint,
  'reconciliation failure records stage escalation'
);

-- Recover both sources.
update reconciliation.runs
set
  status_code = 'SUCCEEDED',
  summary = '{"integrityStatus":"CLEAN"}'::jsonb,
  error_code = null,
  error_detail = null
where id =
  'e8500000-0000-4000-8000-000000000001'::uuid;

update operations.stocktakes
set
  status_code = 'CANCELLED',
  reconciliation_run_id = null,
  version_no = version_no + 1
where id =
  'e8200000-0000-4000-8000-000000000002'::uuid;

update operations.stocktakes
set
  status_code = 'APPROVED',
  version_no = version_no + 1
where id =
  'e8200000-0000-4000-8000-000000000003'::uuid;

create temporary table post_failure_recovered_evaluation as
select notification.evaluate_stocktake_post_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-post-failure:recovered',
  '2026-07-25 16:00:00+07'::timestamptz,
  'SCHEDULED',
  'e9700000-0000-4000-8000-000000000003'::uuid,
  'pgtap.stocktake_post_failure_evaluator'
) as result;

select is(
  (
    select (result ->> 'resolvedCount')::integer
    from post_failure_recovered_evaluation
  ),
  2,
  'source recovery resolves both post failure notifications'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and episode_no = 1
  ),
  'SESSION_CANCELLED',
  'cancelled exception records cancellation resolution'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000003'::uuid
      and episode_no = 1
  ),
  'SESSION_RETURNED_TO_APPROVED',
  'rolled-back posting state records approved recovery'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  0::bigint,
  'no active post failure notification remains after recovery'
);

select is(
  (
    select status_code
    from operations.stocktakes
    where id =
      'e8200000-0000-4000-8000-000000000003'::uuid
  ),
  'APPROVED',
  'evaluator preserves recovered APPROVED status'
);

-- Failure condition returns and creates a second episode.
update operations.stocktakes
set
  status_code = 'EXCEPTION',
  version_no = version_no + 1
where id =
  'e8200000-0000-4000-8000-000000000002'::uuid;

create temporary table post_failure_recurrence_evaluation as
select notification.evaluate_stocktake_post_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-post-failure:recurrence',
  '2026-07-25 17:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  'e9700000-0000-4000-8000-000000000004'::uuid,
  'pgtap.stocktake_post_failure_evaluator'
) as result;

select is(
  (
    select (result ->> 'createdCount')::integer
    from post_failure_recurrence_evaluation
  ),
  1,
  'post failure recurrence creates one new episode'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
  ),
  2::bigint,
  'post failure recurrence preserves two episodes'
);

select is(
  (
    select episode_no
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  2,
  'post failure recurrence creates episode two'
);

select is(
  (
    select previous_notification_id
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and episode_no = 2
  ),
  (
    select id
    from notification.notifications
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and entity_id =
        'e8200000-0000-4000-8000-000000000002'::uuid
      and episode_no = 1
  ),
  'post failure episode two links to predecessor'
);

-- Structural configuration failures are audited.
update notification.rules
set config = jsonb_set(
  config,
  '{stageCode}',
  '"INVALID"'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'STOCKTAKE_RECOUNT_REQUIRED';

create temporary table invalid_recount_config_evaluation as
select notification.evaluate_stocktake_recounts(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-recount:invalid-config',
  '2026-07-25 18:00:00+07'::timestamptz,
  'SCHEDULED',
  'e9600000-0000-4000-8000-000000000005'::uuid,
  'pgtap.stocktake_recount_evaluator'
) as result;

select is(
  (select result ->> 'status' from invalid_recount_config_evaluation),
  'FAILED',
  'invalid recount rule config returns FAILED'
);

select is(
  (
    select result ->> 'errorCode'
    from invalid_recount_config_evaluation
  ),
  'STOCKTAKE_RECOUNT_EVALUATION_FAILED',
  'invalid recount config exposes stable error code'
);

select is(
  (
    select status_code
    from notification.rule_runs
    where id = (
      select (result ->> 'ruleRunId')::uuid
      from invalid_recount_config_evaluation
    )
  ),
  'FAILED',
  'invalid recount config persists failed rule run'
);

update notification.rules
set config = jsonb_set(
  config,
  '{stageCode}',
  '"RECOUNT_REQUIRED"'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'STOCKTAKE_RECOUNT_REQUIRED';

update notification.rules
set config = jsonb_set(
  config,
  '{postingStaleMinutes}',
  '0'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'STOCKTAKE_POST_FAILED';

create temporary table invalid_post_config_evaluation as
select notification.evaluate_stocktake_post_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'stocktake-post-failure:invalid-config',
  '2026-07-25 18:00:00+07'::timestamptz,
  'SCHEDULED',
  'e9700000-0000-4000-8000-000000000005'::uuid,
  'pgtap.stocktake_post_failure_evaluator'
) as result;

select is(
  (select result ->> 'status' from invalid_post_config_evaluation),
  'FAILED',
  'invalid post failure rule config returns FAILED'
);

select is(
  (
    select result ->> 'errorCode'
    from invalid_post_config_evaluation
  ),
  'STOCKTAKE_POST_FAILURE_EVALUATION_FAILED',
  'invalid post failure config exposes stable error code'
);

select is(
  (
    select status_code
    from notification.rule_runs
    where id = (
      select (result ->> 'ruleRunId')::uuid
      from invalid_post_config_evaluation
    )
  ),
  'FAILED',
  'invalid post failure config persists failed rule run'
);

update notification.rules
set config = jsonb_set(
  config,
  '{postingStaleMinutes}',
  '30'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'STOCKTAKE_POST_FAILED';

-- Input validation and disabled rules.
select throws_ok(
  $sql$
    select notification.evaluate_stocktake_recounts(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'stocktake-recount:invalid-trigger',
      '2026-07-25 19:00:00+07'::timestamptz,
      'OUTBOX',
      'e9600000-0000-4000-8000-000000000006'::uuid,
      'pgtap.stocktake_recount_evaluator'
    )
  $sql$,
  'P0001',
  'STOCKTAKE_RECOUNT_TRIGGER_TYPE_INVALID',
  'recount evaluator rejects unsupported direct trigger'
);

select throws_ok(
  $sql$
    select notification.evaluate_stocktake_post_failures(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'stocktake-post-failure:invalid-trigger',
      '2026-07-25 19:00:00+07'::timestamptz,
      'OUTBOX',
      'e9700000-0000-4000-8000-000000000006'::uuid,
      'pgtap.stocktake_post_failure_evaluator'
    )
  $sql$,
  'P0001',
  'STOCKTAKE_POST_FAILURE_TRIGGER_TYPE_INVALID',
  'post failure evaluator rejects unsupported direct trigger'
);

select throws_ok(
  $sql$
    select notification.evaluate_stocktake_recounts(
      '00000000-0000-4000-8000-000000000001'::uuid,
      '   ',
      '2026-07-25 19:00:00+07'::timestamptz,
      'SCHEDULED',
      'e9600000-0000-4000-8000-000000000007'::uuid,
      'pgtap.stocktake_recount_evaluator'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_RULE_RUN_IDEMPOTENCY_REQUIRED',
  'recount evaluator rejects blank idempotency key'
);

select throws_ok(
  $sql$
    select notification.evaluate_stocktake_post_failures(
      '00000000-0000-4000-8000-000000000001'::uuid,
      '   ',
      '2026-07-25 19:00:00+07'::timestamptz,
      'SCHEDULED',
      'e9700000-0000-4000-8000-000000000007'::uuid,
      'pgtap.stocktake_post_failure_evaluator'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_RULE_RUN_IDEMPOTENCY_REQUIRED',
  'post failure evaluator rejects blank idempotency key'
);

update notification.rules
set is_active = false
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'STOCKTAKE_RECOUNT_REQUIRED';

select throws_ok(
  $sql$
    select notification.evaluate_stocktake_recounts(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'stocktake-recount:disabled',
      '2026-07-25 20:00:00+07'::timestamptz,
      'SCHEDULED',
      'e9600000-0000-4000-8000-000000000008'::uuid,
      'pgtap.stocktake_recount_evaluator'
    )
  $sql$,
  'P0001',
  'STOCKTAKE_RECOUNT_RULE_NOT_ACTIVE',
  'disabled recount rule cannot be evaluated'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where rule_code_snapshot =
      'STOCKTAKE_RECOUNT_REQUIRED'
      and idempotency_key = 'stocktake-recount:disabled'
  ),
  0::bigint,
  'disabled recount rule creates no phantom run'
);

update notification.rules
set is_active = true
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'STOCKTAKE_RECOUNT_REQUIRED';

update notification.rules
set is_active = false
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'STOCKTAKE_POST_FAILED';

select throws_ok(
  $sql$
    select notification.evaluate_stocktake_post_failures(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'stocktake-post-failure:disabled',
      '2026-07-25 20:00:00+07'::timestamptz,
      'SCHEDULED',
      'e9700000-0000-4000-8000-000000000008'::uuid,
      'pgtap.stocktake_post_failure_evaluator'
    )
  $sql$,
  'P0001',
  'STOCKTAKE_POST_FAILURE_RULE_NOT_ACTIVE',
  'disabled post failure rule cannot be evaluated'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where rule_code_snapshot =
      'STOCKTAKE_POST_FAILED'
      and idempotency_key =
        'stocktake-post-failure:disabled'
  ),
  0::bigint,
  'disabled post failure rule creates no phantom run'
);

select * from finish();
rollback;
