begin;

create extension if not exists pgtap with schema extensions;

select plan(133);

-- 1-24: function contract, trusted execution, and concurrency guard.
select has_function(
  'notification'::name,
  'ensure_reconciliation_issue_rule'::name,
  array['uuid', 'timestamp with time zone']::text[]
);

select has_function(
  'notification'::name,
  'ensure_reconciliation_run_failed_rule'::name,
  array['uuid', 'timestamp with time zone']::text[]
);

select has_function(
  'notification'::name,
  'evaluate_reconciliation_issues'::name,
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
  'evaluate_reconciliation_failures'::name,
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
  'ensure_reconciliation_issue_rule',
  array['uuid', 'timestamptz']::text[],
  'uuid'
);

select function_returns(
  'notification',
  'ensure_reconciliation_run_failed_rule',
  array['uuid', 'timestamptz']::text[],
  'uuid'
);

select function_returns(
  'notification',
  'evaluate_reconciliation_issues',
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
  'evaluate_reconciliation_failures',
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
    'notification.ensure_reconciliation_issue_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'service role may provision reconciliation issue rule'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.ensure_reconciliation_issue_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'authenticated clients cannot provision issue rule'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.ensure_reconciliation_run_failed_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'service role may provision reconciliation failure rule'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.ensure_reconciliation_run_failed_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'authenticated clients cannot provision failure rule'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.evaluate_reconciliation_issues(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'service role may evaluate reconciliation issues'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.evaluate_reconciliation_issues(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot evaluate reconciliation issues'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.evaluate_reconciliation_failures(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'service role may evaluate reconciliation failures'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.evaluate_reconciliation_failures(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot evaluate reconciliation failures'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.ensure_reconciliation_issue_rule(uuid,timestamptz)'::regprocedure
  ),
  'issue rule provisioning is security definer'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.ensure_reconciliation_run_failed_rule(uuid,timestamptz)'::regprocedure
  ),
  'failure rule provisioning is security definer'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.evaluate_reconciliation_issues(uuid,text,timestamptz,text,uuid,text)'::regprocedure
  ),
  'issue evaluator is security definer'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.evaluate_reconciliation_failures(uuid,text,timestamptz,text,uuid,text)'::regprocedure
  ),
  'failure evaluator is security definer'
);

select ok(
  position(
    'pg_advisory_xact_lock'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_reconciliation_issues(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'issue evaluator serializes organization-level execution'
);

select ok(
  position(
    'pg_advisory_xact_lock'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_reconciliation_failures(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'failure evaluator serializes organization-level execution'
);

select ok(
  position(
    'severity_code'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_reconciliation_issues(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'issue evaluator reads source severity'
);

select ok(
  position(
    'retryofrunid'
    in lower(
      pg_get_functiondef(
        'notification.ensure_reconciliation_run_failed_rule(uuid,timestamptz)'::regprocedure
      )
    )
  ) > 0,
  'failure rule defines explicit retry linkage'
);

-- Stable source fixtures.
insert into inventory.idempotency_commands (
  id,
  organization_id,
  scope,
  key,
  request_hash,
  status_code,
  started_at,
  completed_at,
  response_snapshot,
  error_code
)
values
(
  'c7100000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP_RECONCILIATION_SOURCE',
  'ISSUE-SOURCE-RUN',
  repeat('a', 64),
  'SUCCEEDED',
  '2026-07-19 08:00:00+07'::timestamptz,
  '2026-07-19 08:05:00+07'::timestamptz,
  '{"status":"SUCCEEDED"}'::jsonb,
  null
),
(
  'c7100000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP_RECONCILIATION_SOURCE',
  'FAILED-RUN',
  repeat('b', 64),
  'FAILED',
  '2026-07-19 09:00:00+07'::timestamptz,
  '2026-07-19 09:10:00+07'::timestamptz,
  '{}'::jsonb,
  'RECONCILIATION_WORKER_CRASHED'
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
values
(
  'c8200000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'RCN-PGTAP-ISSUE-SOURCE',
  'MANUAL',
  'SYSTEM',
  'SUCCEEDED',
  '{}'::jsonb,
  array['LEDGER_BATCH_PROJECTION']::text[],
  'core-integrity-v7',
  0,
  100,
  '2026-07-19 08:00:00+07'::timestamptz,
  '2026-07-19 08:05:00+07'::timestamptz,
  null,
  'pgtap.reconciliation_source',
  'c7100000-0000-4000-8000-000000000001'::uuid,
  '{"integrityStatus":"ISSUES_FOUND","issueCount":1}'::jsonb,
  null,
  null,
  '{"fixture":"notification-reconciliation"}'::jsonb,
  '2026-07-19 08:00:00+07'::timestamptz,
  '2026-07-19 08:05:00+07'::timestamptz
),
(
  'c8200000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'RCN-PGTAP-FAILED-001',
  'DAILY',
  'SYSTEM',
  'FAILED',
  '{}'::jsonb,
  array['IMPOSSIBLE_PROJECTION_STATE']::text[],
  'core-integrity-v7',
  0,
  100,
  '2026-07-19 09:00:00+07'::timestamptz,
  '2026-07-19 09:10:00+07'::timestamptz,
  null,
  'pgtap.reconciliation_worker',
  'c7100000-0000-4000-8000-000000000002'::uuid,
  '{"completedChecks":0}'::jsonb,
  'RECONCILIATION_WORKER_CRASHED',
  '{"message":"worker terminated"}'::jsonb,
  '{"fixture":"notification-reconciliation"}'::jsonb,
  '2026-07-19 09:00:00+07'::timestamptz,
  '2026-07-19 09:10:00+07'::timestamptz
);

insert into reconciliation.issues (
  id,
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
  'c8300000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  repeat('c', 64),
  'LEDGER_BATCH_PROJECTION',
  '1',
  'OPEN',
  'HIGH',
  'PRODUCT_POSITION',
  jsonb_build_object(
    'productId',
    '30000000-0000-4000-8000-000000000001'
  ),
  '30000000-0000-4000-8000-000000000001'::uuid,
  null,
  null,
  null,
  '{"sellableQty":25}'::jsonb,
  '{"sellableQty":24}'::jsonb,
  '{"sellableQty":-1}'::jsonb,
  'c8200000-0000-4000-8000-000000000001'::uuid,
  'c8200000-0000-4000-8000-000000000001'::uuid,
  '2026-07-19 08:05:00+07'::timestamptz,
  '2026-07-19 08:05:00+07'::timestamptz,
  1,
  null,
  null,
  null,
  null,
  null,
  '2026-07-19 08:05:00+07'::timestamptz,
  '2026-07-19 08:05:00+07'::timestamptz
);

create temporary table reconciliation_source_before as
select
  issue.status_code as issue_status_code,
  issue.severity_code as issue_severity_code,
  issue.recurrence_count,
  issue.last_seen_at,
  failed_run.status_code as failed_run_status_code,
  failed_run.error_code as failed_run_error_code,
  failed_run.completed_at as failed_run_completed_at,
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
from reconciliation.issues issue
cross join reconciliation.runs failed_run
where issue.id =
      'c8300000-0000-4000-8000-000000000001'::uuid
  and failed_run.id =
      'c8200000-0000-4000-8000-000000000002'::uuid;

create temporary table issue_initial_evaluation as
select notification.evaluate_reconciliation_issues(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-issue:initial',
  '2026-07-20 08:00:00+07'::timestamptz,
  'SCHEDULED',
  'c9760000-0000-4000-8000-000000000001'::uuid,
  'pgtap.reconciliation_issue_evaluator'
) as result;

-- 25-51: initial HIGH issue creates one active episode without source mutation.
select is(
  (select result ->> 'action' from issue_initial_evaluation),
  'COMPLETED',
  'initial issue evaluation completes'
);

select is(
  (select result ->> 'status' from issue_initial_evaluation),
  'SUCCEEDED',
  'initial issue evaluation succeeds'
);

select is(
  (
    select (result ->> 'evaluatedCount')::integer
    from issue_initial_evaluation
  ),
  1,
  'initial issue evaluation examines one issue'
);

select is(
  (
    select (result ->> 'createdCount')::integer
    from issue_initial_evaluation
  ),
  1,
  'initial issue evaluation creates one episode'
);

select is(
  (
    select (result ->> 'errorCount')::integer
    from issue_initial_evaluation
  ),
  0,
  'initial issue evaluation records no error'
);

select is(
  (
    select category_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
  ),
  'RECONCILIATION',
  'issue rule belongs to reconciliation category'
);

select is(
  (
    select trigger_mode_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
  ),
  'HYBRID',
  'issue rule is hybrid'
);

select is(
  (
    select entity_type_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
  ),
  'RECONCILIATION_ISSUE',
  'issue rule targets issue entities'
);

select is(
  (
    select action_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
  ),
  'OPEN_RECONCILIATION_ISSUE_DETAIL',
  'issue rule recommends opening issue detail'
);

select ok(
  (
    select config -> 'eligibleSeverities' =
      '["HIGH","CRITICAL"]'::jsonb
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
  ),
  'issue rule snapshots HIGH and CRITICAL eligibility'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  1::bigint,
  'one active issue notification is created'
);

select is(
  (
    select stage_code
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'HIGH',
  'HIGH source issue uses HIGH stage'
);

select is(
  (
    select severity_code
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'HIGH',
  'HIGH source issue uses HIGH notification severity'
);

select is(
  (
    select condition_started_at
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  '2026-07-19 08:05:00+07'::timestamptz,
  'issue episode starts at first source observation'
);

select is(
  (
    select action_route
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  '/reconciliation?issueId=c8300000-0000-4000-8000-000000000001',
  'issue notification deep-links to source issue'
);

select is(
  (
    select source_snapshot ->> 'checkCode'
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'LEDGER_BATCH_PROJECTION',
  'issue source snapshot stores check code'
);

select is(
  (
    select source_snapshot ->> 'productSku'
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'SER-NIA-30',
  'issue source snapshot includes product SKU'
);

select is(
  (
    select source_snapshot ->> 'lastSeenRunNo'
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'RCN-PGTAP-ISSUE-SOURCE',
  'issue source snapshot includes source run number'
);

select is(
  (
    select episode_no
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  1,
  'initial issue condition creates episode one'
);

select is(
  (
    select count(*)
    from notification.notification_events event_row
    where event_row.notification_id = (
      select id
      from notification.notifications
      where rule_code_snapshot =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
        and entity_id =
          'c8300000-0000-4000-8000-000000000001'::uuid
    )
      and event_row.event_type_code = 'CREATED'
  ),
  1::bigint,
  'initial issue episode records CREATED event'
);

select is(
  (
    select status_code
    from reconciliation.issues
    where id =
      'c8300000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select issue_status_code
    from reconciliation_source_before
  ),
  'issue evaluator does not change issue status'
);

select is(
  (
    select severity_code
    from reconciliation.issues
    where id =
      'c8300000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select issue_severity_code
    from reconciliation_source_before
  ),
  'issue evaluator does not change source severity'
);

select is(
  (
    select recurrence_count
    from reconciliation.issues
    where id =
      'c8300000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select recurrence_count
    from reconciliation_source_before
  ),
  'issue evaluator does not change recurrence count'
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
    from reconciliation_source_before
  ),
  'issue evaluator creates no stock transaction'
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
    from reconciliation_source_before
  ),
  'issue evaluator creates no ledger movement'
);

create temporary table issue_replay_evaluation as
select notification.evaluate_reconciliation_issues(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-issue:initial',
  '2026-07-20 09:00:00+07'::timestamptz,
  'MANUAL',
  'c9760000-0000-4000-8000-000000000099'::uuid,
  'pgtap.reconciliation_issue_evaluator'
) as result;

select is(
  (select result ->> 'action' from issue_replay_evaluation),
  'REPLAYED',
  'issue evaluator replays the same idempotency key'
);

select is(
  (
    select result ->> 'ruleRunId'
    from issue_replay_evaluation
  ),
  (
    select result ->> 'ruleRunId'
    from issue_initial_evaluation
  ),
  'issue replay returns original rule run'
);

select is(
  (
    select occurrence_count
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  1,
  'issue replay does not increment occurrence'
);

-- Escalation HIGH -> CRITICAL.
update reconciliation.issues
set
  severity_code = 'CRITICAL',
  last_seen_at = '2026-07-20 10:00:00+07'::timestamptz
where id =
  'c8300000-0000-4000-8000-000000000001'::uuid;

create temporary table issue_critical_evaluation as
select notification.evaluate_reconciliation_issues(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-issue:critical',
  '2026-07-20 11:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  'c9760000-0000-4000-8000-000000000002'::uuid,
  'pgtap.reconciliation_issue_evaluator'
) as result;

-- 52-62: severity escalation updates the same episode.
select is(
  (select result ->> 'status' from issue_critical_evaluation),
  'SUCCEEDED',
  'critical issue evaluation succeeds'
);

select is(
  (
    select (result ->> 'updatedCount')::integer
    from issue_critical_evaluation
  ),
  1,
  'critical issue updates one active episode'
);

select is(
  (
    select stage_code
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'CRITICAL',
  'source escalation changes stage to CRITICAL'
);

select is(
  (
    select severity_code
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'CRITICAL',
  'source escalation changes notification severity'
);

select is(
  (
    select occurrence_count
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  2,
  'critical observation increments occurrence'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'critical escalation creates no duplicate episode'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select id
      from notification.notifications
      where rule_code_snapshot =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
        and entity_id =
          'c8300000-0000-4000-8000-000000000001'::uuid
    )
      and event_type_code = 'STAGE_ESCALATED'
  ),
  1::bigint,
  'critical escalation records stage event'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select id
      from notification.notifications
      where rule_code_snapshot =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
        and entity_id =
          'c8300000-0000-4000-8000-000000000001'::uuid
    )
      and event_type_code = 'SEVERITY_CHANGED'
  ),
  1::bigint,
  'critical escalation records severity event'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  1::bigint,
  'critical issue retains one active episode'
);

-- De-escalation CRITICAL -> HIGH.
update reconciliation.issues
set
  severity_code = 'HIGH',
  last_seen_at = '2026-07-20 12:00:00+07'::timestamptz
where id =
  'c8300000-0000-4000-8000-000000000001'::uuid;

create temporary table issue_high_again_evaluation as
select notification.evaluate_reconciliation_issues(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-issue:high-again',
  '2026-07-20 13:00:00+07'::timestamptz,
  'SCHEDULED',
  'c9760000-0000-4000-8000-000000000003'::uuid,
  'pgtap.reconciliation_issue_evaluator'
) as result;

select is(
  (
    select (result ->> 'updatedCount')::integer
    from issue_high_again_evaluation
  ),
  1,
  'de-escalation updates the active issue episode'
);

select is(
  (
    select stage_code
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'HIGH',
  'de-escalation returns stage to HIGH'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select id
      from notification.notifications
      where rule_code_snapshot =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
        and entity_id =
          'c8300000-0000-4000-8000-000000000001'::uuid
    )
      and event_type_code = 'STAGE_DEESCALATED'
  ),
  1::bigint,
  'de-escalation records stage history'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select id
      from notification.notifications
      where rule_code_snapshot =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
        and entity_id =
          'c8300000-0000-4000-8000-000000000001'::uuid
    )
      and event_type_code = 'SEVERITY_CHANGED'
  ),
  2::bigint,
  'de-escalation preserves both severity changes'
);

-- Severity falls below HIGH, so notification resolves while source issue remains OPEN.
update reconciliation.issues
set
  severity_code = 'MEDIUM',
  last_seen_at = '2026-07-20 14:00:00+07'::timestamptz
where id =
  'c8300000-0000-4000-8000-000000000001'::uuid;

create temporary table issue_below_high_evaluation as
select notification.evaluate_reconciliation_issues(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-issue:below-high',
  '2026-07-20 15:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  'c9760000-0000-4000-8000-000000000004'::uuid,
  'pgtap.reconciliation_issue_evaluator'
) as result;

-- 67-75: severity below threshold resolves notification only.
select is(
  (
    select (result ->> 'resolvedCount')::integer
    from issue_below_high_evaluation
  ),
  1,
  'below-HIGH evaluation resolves one notification'
);

select is(
  (
    select lifecycle_status_code
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and episode_no = 1
  ),
  'RESOLVED',
  'episode one is resolved below HIGH'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and episode_no = 1
  ),
  'SEVERITY_BELOW_HIGH',
  'resolution records severity threshold reason'
);

select is(
  (
    select status_code
    from reconciliation.issues
    where id =
      'c8300000-0000-4000-8000-000000000001'::uuid
  ),
  'OPEN',
  'notification resolution does not resolve source issue'
);

select is(
  (
    select severity_code
    from reconciliation.issues
    where id =
      'c8300000-0000-4000-8000-000000000001'::uuid
  ),
  'MEDIUM',
  'notification resolution does not rewrite source severity'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select id
      from notification.notifications
      where rule_code_snapshot =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
        and entity_id =
          'c8300000-0000-4000-8000-000000000001'::uuid
        and episode_no = 1
    )
      and event_type_code = 'RESOLVED'
  ),
  1::bigint,
  'below-HIGH resolution appends history event'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  0::bigint,
  'no active issue episode remains below HIGH'
);

-- The same source issue becomes HIGH again, creating episode two.
update reconciliation.issues
set
  severity_code = 'HIGH',
  recurrence_count = recurrence_count + 1,
  last_seen_at = '2026-07-21 10:00:00+07'::timestamptz
where id =
  'c8300000-0000-4000-8000-000000000001'::uuid;

create temporary table issue_recurrence_evaluation as
select notification.evaluate_reconciliation_issues(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-issue:recurrence',
  '2026-07-21 11:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  'c9760000-0000-4000-8000-000000000005'::uuid,
  'pgtap.reconciliation_issue_evaluator'
) as result;

-- 76-86: recurrence creates a fresh episode with predecessor linkage.
select is(
  (
    select (result ->> 'createdCount')::integer
    from issue_recurrence_evaluation
  ),
  1,
  'issue recurrence creates one episode'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'issue recurrence preserves two historical episodes'
);

select is(
  (
    select episode_no
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  2,
  'issue recurrence creates episode two'
);

select is(
  (
    select previous_notification_id
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and episode_no = 2
  ),
  (
    select id
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and episode_no = 1
  ),
  'issue episode two links to episode one'
);

select is(
  (
    select condition_started_at
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and episode_no = 2
  ),
  '2026-07-21 10:00:00+07'::timestamptz,
  'recurrence starts from new source observation'
);

select is(
  (
    select stage_code
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and episode_no = 2
  ),
  'HIGH',
  'recurrence begins at current HIGH stage'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select id
      from notification.notifications
      where rule_code_snapshot =
        'RECONCILIATION_ISSUE_HIGH_CRITICAL'
        and entity_id =
          'c8300000-0000-4000-8000-000000000001'::uuid
        and episode_no = 2
    )
      and event_type_code =
        'REOPENED_AS_NEW_EPISODE'
  ),
  1::bigint,
  'recurrence records reopened event'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  1::bigint,
  'recurrence still has one active episode'
);

-- Source issue is explicitly resolved.
update reconciliation.issues
set
  status_code = 'RESOLVED',
  resolved_at = '2026-07-21 12:00:00+07'::timestamptz,
  resolution_code = 'CORRECTED',
  resolution_note = 'Projection corrected.',
  resolved_by_user_id = null,
  resolved_by_process_name = 'pgtap.reconciliation_resolution'
where id =
  'c8300000-0000-4000-8000-000000000001'::uuid;

create temporary table issue_source_resolved_evaluation as
select notification.evaluate_reconciliation_issues(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-issue:source-resolved',
  '2026-07-21 13:00:00+07'::timestamptz,
  'SCHEDULED',
  'c9760000-0000-4000-8000-000000000006'::uuid,
  'pgtap.reconciliation_issue_evaluator'
) as result;

select is(
  (
    select (result ->> 'resolvedCount')::integer
    from issue_source_resolved_evaluation
  ),
  1,
  'resolved source issue resolves episode two'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and entity_id =
        'c8300000-0000-4000-8000-000000000001'::uuid
      and episode_no = 2
  ),
  'ISSUE_RESOLVED',
  'episode two records explicit issue resolution'
);

select is(
  (
    select status_code
    from reconciliation.issues
    where id =
      'c8300000-0000-4000-8000-000000000001'::uuid
  ),
  'RESOLVED',
  'evaluator preserves resolved source issue'
);

-- Failure evaluator.
create temporary table failure_initial_evaluation as
select notification.evaluate_reconciliation_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-failure:initial',
  '2026-07-20 10:00:00+07'::timestamptz,
  'SCHEDULED',
  'c9770000-0000-4000-8000-000000000001'::uuid,
  'pgtap.reconciliation_failure_evaluator'
) as result;

-- 89-111: failed run creates a deep-linked critical notification.
select is(
  (select result ->> 'status' from failure_initial_evaluation),
  'SUCCEEDED',
  'initial failure evaluation succeeds'
);

select is(
  (
    select (result ->> 'createdCount')::integer
    from failure_initial_evaluation
  ),
  1,
  'initial failure evaluation creates one notification'
);

select is(
  (
    select (result ->> 'errorCount')::integer
    from failure_initial_evaluation
  ),
  0,
  'initial failure evaluation has no entity error'
);

select is(
  (
    select category_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'RECONCILIATION_RUN_FAILED'
  ),
  'RECONCILIATION',
  'failure rule belongs to reconciliation category'
);

select is(
  (
    select entity_type_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'RECONCILIATION_RUN_FAILED'
  ),
  'RECONCILIATION_RUN',
  'failure rule targets run entities'
);

select is(
  (
    select action_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'RECONCILIATION_RUN_FAILED'
  ),
  'OPEN_RECONCILIATION_RUN_DETAIL',
  'failure rule recommends opening run detail'
);

select is(
  (
    select config ->> 'successfulRetryMetadataKey'
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'RECONCILIATION_RUN_FAILED'
  ),
  'retryOfRunId',
  'failure rule snapshots retry linkage key'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  1::bigint,
  'failed run creates one active notification'
);

select is(
  (
    select stage_code
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'FAILED',
  'failed run uses FAILED stage'
);

select is(
  (
    select severity_code
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'CRITICAL',
  'failed run uses CRITICAL severity'
);

select is(
  (
    select condition_started_at
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  '2026-07-19 09:10:00+07'::timestamptz,
  'failure condition starts when run completed as failed'
);

select is(
  (
    select action_route
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  '/reconciliation?runId=c8200000-0000-4000-8000-000000000002',
  'failure notification deep-links to failed run'
);

select is(
  (
    select source_snapshot ->> 'runNo'
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'RCN-PGTAP-FAILED-001',
  'failure snapshot stores run number'
);

select is(
  (
    select source_snapshot ->> 'errorCode'
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  'RECONCILIATION_WORKER_CRASHED',
  'failure snapshot stores source error code'
);

select is(
  (
    select episode_no
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  1,
  'failed run creates episode one'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select id
      from notification.notifications
      where rule_code_snapshot =
        'RECONCILIATION_RUN_FAILED'
        and entity_id =
          'c8200000-0000-4000-8000-000000000002'::uuid
    )
      and event_type_code = 'CREATED'
  ),
  1::bigint,
  'failed run records CREATED event'
);

select is(
  (
    select status_code
    from reconciliation.runs
    where id =
      'c8200000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select failed_run_status_code
    from reconciliation_source_before
  ),
  'failure evaluator does not change source run status'
);

select is(
  (
    select error_code
    from reconciliation.runs
    where id =
      'c8200000-0000-4000-8000-000000000002'::uuid
  ),
  (
    select failed_run_error_code
    from reconciliation_source_before
  ),
  'failure evaluator does not change source error'
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
    from reconciliation_source_before
  ),
  'failure evaluator creates no stock transaction'
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
    from reconciliation_source_before
  ),
  'failure evaluator creates no ledger movement'
);

create temporary table failure_replay_evaluation as
select notification.evaluate_reconciliation_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-failure:initial',
  '2026-07-20 11:00:00+07'::timestamptz,
  'MANUAL',
  'c9770000-0000-4000-8000-000000000099'::uuid,
  'pgtap.reconciliation_failure_evaluator'
) as result;

select is(
  (select result ->> 'action' from failure_replay_evaluation),
  'REPLAYED',
  'failure evaluator replays idempotency key'
);

select is(
  (
    select occurrence_count
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and lifecycle_status_code = 'OPEN'
  ),
  1,
  'failure replay does not increment occurrence'
);

-- Explicit successful retry resolves the failed-run notification.
insert into inventory.idempotency_commands (
  id,
  organization_id,
  scope,
  key,
  request_hash,
  status_code,
  started_at,
  completed_at,
  response_snapshot,
  error_code
)
values (
  'c7100000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP_RECONCILIATION_SOURCE',
  'SUCCESSFUL-RETRY-RUN',
  repeat('d', 64),
  'SUCCEEDED',
  '2026-07-20 12:00:00+07'::timestamptz,
  '2026-07-20 12:05:00+07'::timestamptz,
  '{"status":"SUCCEEDED"}'::jsonb,
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
  'c8200000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'RCN-PGTAP-RETRY-001',
  'DAILY',
  'SYSTEM',
  'SUCCEEDED',
  '{}'::jsonb,
  array['IMPOSSIBLE_PROJECTION_STATE']::text[],
  'core-integrity-v7',
  0,
  101,
  '2026-07-20 12:00:00+07'::timestamptz,
  '2026-07-20 12:05:00+07'::timestamptz,
  null,
  'pgtap.reconciliation_worker',
  'c7100000-0000-4000-8000-000000000003'::uuid,
  '{"integrityStatus":"CLEAN","issueCount":0}'::jsonb,
  null,
  null,
  jsonb_build_object(
    'fixture',
    'notification-reconciliation',
    'retryOfRunId',
    'c8200000-0000-4000-8000-000000000002'
  ),
  '2026-07-20 12:00:00+07'::timestamptz,
  '2026-07-20 12:05:00+07'::timestamptz
);

create temporary table failure_retry_evaluation as
select notification.evaluate_reconciliation_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-failure:retry-success',
  '2026-07-20 13:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  'c9770000-0000-4000-8000-000000000002'::uuid,
  'pgtap.reconciliation_failure_evaluator'
) as result;

-- 112-120: successful retry resolves only the linked failed run.
select is(
  (
    select (result ->> 'resolvedCount')::integer
    from failure_retry_evaluation
  ),
  1,
  'successful retry resolves one failed-run notification'
);

select is(
  (
    select lifecycle_status_code
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and episode_no = 1
  ),
  'RESOLVED',
  'failed-run notification becomes resolved'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and episode_no = 1
  ),
  'SUCCESSFUL_RETRY_FOUND',
  'resolution records successful retry reason'
);

select is(
  (
    select resolution_snapshot ->> 'successfulRetryRunId'
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000002'::uuid
      and episode_no = 1
  ),
  'c8200000-0000-4000-8000-000000000003',
  'resolution snapshot links successful retry'
);

select is(
  (
    select status_code
    from reconciliation.runs
    where id =
      'c8200000-0000-4000-8000-000000000002'::uuid
  ),
  'FAILED',
  'successful retry does not rewrite failed source run'
);

select is(
  (
    select status_code
    from reconciliation.runs
    where id =
      'c8200000-0000-4000-8000-000000000003'::uuid
  ),
  'SUCCEEDED',
  'successful retry source remains succeeded'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000003'::uuid
  ),
  0::bigint,
  'successful run itself creates no failure notification'
);

-- A second failed run is independent.
insert into inventory.idempotency_commands (
  id,
  organization_id,
  scope,
  key,
  request_hash,
  status_code,
  started_at,
  completed_at,
  response_snapshot,
  error_code
)
values (
  'c7100000-0000-4000-8000-000000000004'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'PGTAP_RECONCILIATION_SOURCE',
  'SECOND-FAILED-RUN',
  repeat('e', 64),
  'FAILED',
  '2026-07-21 08:00:00+07'::timestamptz,
  '2026-07-21 08:05:00+07'::timestamptz,
  '{}'::jsonb,
  'RECONCILIATION_TIMEOUT'
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
  'c8200000-0000-4000-8000-000000000004'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'RCN-PGTAP-FAILED-002',
  'DAILY',
  'SYSTEM',
  'FAILED',
  '{}'::jsonb,
  array['DUPLICATE_SOURCE_EFFECT']::text[],
  'core-integrity-v7',
  0,
  101,
  '2026-07-21 08:00:00+07'::timestamptz,
  '2026-07-21 08:05:00+07'::timestamptz,
  null,
  'pgtap.reconciliation_worker',
  'c7100000-0000-4000-8000-000000000004'::uuid,
  '{"completedChecks":0}'::jsonb,
  'RECONCILIATION_TIMEOUT',
  '{"timeoutSeconds":30}'::jsonb,
  '{"fixture":"notification-reconciliation"}'::jsonb,
  '2026-07-21 08:00:00+07'::timestamptz,
  '2026-07-21 08:05:00+07'::timestamptz
);

create temporary table second_failure_evaluation as
select notification.evaluate_reconciliation_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-failure:second',
  '2026-07-21 09:00:00+07'::timestamptz,
  'SCHEDULED',
  'c9770000-0000-4000-8000-000000000003'::uuid,
  'pgtap.reconciliation_failure_evaluator'
) as result;

select is(
  (
    select (result ->> 'createdCount')::integer
    from second_failure_evaluation
  ),
  1,
  'second failed run creates one notification'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
  ),
  2::bigint,
  'failure rule preserves two run-specific histories'
);

select is(
  (
    select count(*)
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  1::bigint,
  'only second failed run remains active'
);

select is(
  (
    select entity_id
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and lifecycle_status_code = 'OPEN'
  ),
  'c8200000-0000-4000-8000-000000000004'::uuid,
  'active failure notification belongs to second run'
);

-- Same run status recovers without a retry row.
update reconciliation.runs
set
  status_code = 'SUCCEEDED',
  summary = '{"integrityStatus":"CLEAN"}'::jsonb,
  error_code = null,
  error_detail = null
where id =
  'c8200000-0000-4000-8000-000000000004'::uuid;

create temporary table recovered_failure_evaluation as
select notification.evaluate_reconciliation_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-failure:recovered',
  '2026-07-21 10:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  'c9770000-0000-4000-8000-000000000004'::uuid,
  'pgtap.reconciliation_failure_evaluator'
) as result;

select is(
  (
    select (result ->> 'resolvedCount')::integer
    from recovered_failure_evaluation
  ),
  1,
  'recovered run status resolves one notification'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and entity_id =
        'c8200000-0000-4000-8000-000000000004'::uuid
      and episode_no = 1
  ),
  'RUN_STATUS_RECOVERED',
  'same-row recovery records status resolution'
);

select is(
  (
    select status_code
    from reconciliation.runs
    where id =
      'c8200000-0000-4000-8000-000000000004'::uuid
  ),
  'SUCCEEDED',
  'evaluator preserves recovered source status'
);

-- Structural configuration failures are audited.
update notification.rules
set config = jsonb_set(
  config,
  '{eligibleSeverities}',
  '["HIGH","MEDIUM"]'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code =
    'RECONCILIATION_ISSUE_HIGH_CRITICAL';

create temporary table invalid_issue_config_evaluation as
select notification.evaluate_reconciliation_issues(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-issue:invalid-config',
  '2026-07-21 11:00:00+07'::timestamptz,
  'SCHEDULED',
  'c9760000-0000-4000-8000-000000000007'::uuid,
  'pgtap.reconciliation_issue_evaluator'
) as result;

select is(
  (select result ->> 'status' from invalid_issue_config_evaluation),
  'FAILED',
  'invalid issue rule config returns FAILED'
);

select is(
  (
    select result ->> 'errorCode'
    from invalid_issue_config_evaluation
  ),
  'RECONCILIATION_ISSUE_EVALUATION_FAILED',
  'invalid issue config exposes stable error code'
);

select is(
  (
    select status_code
    from notification.rule_runs
    where id = (
      select (result ->> 'ruleRunId')::uuid
      from invalid_issue_config_evaluation
    )
  ),
  'FAILED',
  'invalid issue config persists failed rule run'
);

update notification.rules
set config = jsonb_set(
  config,
  '{eligibleSeverities}',
  '["HIGH","CRITICAL"]'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code =
    'RECONCILIATION_ISSUE_HIGH_CRITICAL';

update notification.rules
set config = jsonb_set(
  config,
  '{successfulRetryMetadataKey}',
  '""'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'RECONCILIATION_RUN_FAILED';

create temporary table invalid_failure_config_evaluation as
select notification.evaluate_reconciliation_failures(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'reconciliation-failure:invalid-config',
  '2026-07-21 12:00:00+07'::timestamptz,
  'SCHEDULED',
  'c9770000-0000-4000-8000-000000000005'::uuid,
  'pgtap.reconciliation_failure_evaluator'
) as result;

select is(
  (select result ->> 'status' from invalid_failure_config_evaluation),
  'FAILED',
  'invalid failure rule config returns FAILED'
);

select is(
  (
    select result ->> 'errorCode'
    from invalid_failure_config_evaluation
  ),
  'RECONCILIATION_FAILURE_EVALUATION_FAILED',
  'invalid failure config exposes stable error code'
);

select is(
  (
    select status_code
    from notification.rule_runs
    where id = (
      select (result ->> 'ruleRunId')::uuid
      from invalid_failure_config_evaluation
    )
  ),
  'FAILED',
  'invalid failure config persists failed rule run'
);

update notification.rules
set config = jsonb_set(
  config,
  '{successfulRetryMetadataKey}',
  '"retryOfRunId"'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'RECONCILIATION_RUN_FAILED';

-- Input validation and disabled-rule behavior.
select throws_ok(
  $sql$
    select notification.evaluate_reconciliation_issues(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'reconciliation-issue:invalid-trigger',
      '2026-07-21 13:00:00+07'::timestamptz,
      'OUTBOX',
      'c9760000-0000-4000-8000-000000000008'::uuid,
      'pgtap.reconciliation_issue_evaluator'
    )
  $sql$,
  'P0001',
  'RECONCILIATION_ISSUE_TRIGGER_TYPE_INVALID',
  'issue evaluator rejects unsupported direct trigger'
);

select throws_ok(
  $sql$
    select notification.evaluate_reconciliation_failures(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'reconciliation-failure:invalid-trigger',
      '2026-07-21 13:00:00+07'::timestamptz,
      'OUTBOX',
      'c9770000-0000-4000-8000-000000000006'::uuid,
      'pgtap.reconciliation_failure_evaluator'
    )
  $sql$,
  'P0001',
  'RECONCILIATION_FAILURE_TRIGGER_TYPE_INVALID',
  'failure evaluator rejects unsupported direct trigger'
);

select throws_ok(
  $sql$
    select notification.evaluate_reconciliation_issues(
      '00000000-0000-4000-8000-000000000001'::uuid,
      '   ',
      '2026-07-21 13:00:00+07'::timestamptz,
      'SCHEDULED',
      'c9760000-0000-4000-8000-000000000009'::uuid,
      'pgtap.reconciliation_issue_evaluator'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_RULE_RUN_IDEMPOTENCY_REQUIRED',
  'issue evaluator rejects blank idempotency key'
);

select throws_ok(
  $sql$
    select notification.evaluate_reconciliation_failures(
      '00000000-0000-4000-8000-000000000001'::uuid,
      '   ',
      '2026-07-21 13:00:00+07'::timestamptz,
      'SCHEDULED',
      'c9770000-0000-4000-8000-000000000007'::uuid,
      'pgtap.reconciliation_failure_evaluator'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_RULE_RUN_IDEMPOTENCY_REQUIRED',
  'failure evaluator rejects blank idempotency key'
);

update notification.rules
set is_active = false
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code =
    'RECONCILIATION_ISSUE_HIGH_CRITICAL';

select throws_ok(
  $sql$
    select notification.evaluate_reconciliation_issues(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'reconciliation-issue:disabled',
      '2026-07-21 14:00:00+07'::timestamptz,
      'SCHEDULED',
      'c9760000-0000-4000-8000-000000000010'::uuid,
      'pgtap.reconciliation_issue_evaluator'
    )
  $sql$,
  'P0001',
  'RECONCILIATION_ISSUE_RULE_NOT_ACTIVE',
  'disabled issue rule cannot be evaluated'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where rule_code_snapshot =
      'RECONCILIATION_ISSUE_HIGH_CRITICAL'
      and idempotency_key =
        'reconciliation-issue:disabled'
  ),
  0::bigint,
  'disabled issue rule creates no phantom rule run'
);

update notification.rules
set is_active = true
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code =
    'RECONCILIATION_ISSUE_HIGH_CRITICAL';

update notification.rules
set is_active = false
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'RECONCILIATION_RUN_FAILED';

select throws_ok(
  $sql$
    select notification.evaluate_reconciliation_failures(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'reconciliation-failure:disabled',
      '2026-07-21 14:00:00+07'::timestamptz,
      'SCHEDULED',
      'c9770000-0000-4000-8000-000000000008'::uuid,
      'pgtap.reconciliation_failure_evaluator'
    )
  $sql$,
  'P0001',
  'RECONCILIATION_FAILURE_RULE_NOT_ACTIVE',
  'disabled failure rule cannot be evaluated'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where rule_code_snapshot =
      'RECONCILIATION_RUN_FAILED'
      and idempotency_key =
        'reconciliation-failure:disabled'
  ),
  0::bigint,
  'disabled failure rule creates no phantom rule run'
);

select * from finish();
rollback;
