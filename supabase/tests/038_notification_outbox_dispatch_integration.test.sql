begin;

create extension if not exists pgtap with schema extensions;

select plan(71);

-- Function contract, security, and supported dispatch branches.
select has_function(
  'notification'::name,
  'dispatch_outbox_event'::name,
  array['uuid', 'text']::text[]
);

select function_returns(
  'notification',
  'dispatch_outbox_event',
  array['uuid', 'text']::text[],
  'jsonb'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.dispatch_outbox_event(uuid,text)',
    'EXECUTE'
  ),
  'service role may dispatch claimed outbox events'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.dispatch_outbox_event(uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot dispatch outbox events'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.dispatch_outbox_event(uuid,text)'::regprocedure
  ),
  'outbox dispatcher is security definer'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.process_outbox(text,integer,timestamptz,interval,integer,integer,integer,text)'::regprocedure
  ),
  'integrated outbox processor remains security definer'
);

select ok(
  position(
    'notification_return_inspection_evaluation_requested'
    in lower(
      pg_get_functiondef(
        'notification.dispatch_outbox_event(uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'dispatcher supports return inspection evaluation'
);

select ok(
  position(
    'notification_reconciliation_evaluation_requested'
    in lower(
      pg_get_functiondef(
        'notification.dispatch_outbox_event(uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'dispatcher supports reconciliation family evaluation'
);

select ok(
  position(
    'notification_reconciliation_issue_evaluation_requested'
    in lower(
      pg_get_functiondef(
        'notification.dispatch_outbox_event(uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'dispatcher supports granular reconciliation issue evaluation'
);

select ok(
  position(
    'notification_reconciliation_failure_evaluation_requested'
    in lower(
      pg_get_functiondef(
        'notification.dispatch_outbox_event(uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'dispatcher supports granular reconciliation failure evaluation'
);

select ok(
  position(
    'notification_stocktake_evaluation_requested'
    in lower(
      pg_get_functiondef(
        'notification.dispatch_outbox_event(uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'dispatcher supports stocktake family evaluation'
);

select ok(
  position(
    'notification_stocktake_recount_evaluation_requested'
    in lower(
      pg_get_functiondef(
        'notification.dispatch_outbox_event(uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'dispatcher supports granular stocktake recount evaluation'
);

select ok(
  position(
    'notification_stocktake_post_failure_evaluation_requested'
    in lower(
      pg_get_functiondef(
        'notification.dispatch_outbox_event(uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'dispatcher supports granular stocktake post failure evaluation'
);

select ok(
  position(
    'triggered_by_outbox_event_id'
    in lower(
      pg_get_functiondef(
        'notification.dispatch_outbox_event(uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'dispatcher links every evaluator run to its outbox event'
);

select ok(
  position(
    'outbox_event_type_unsupported'
    in lower(
      pg_get_functiondef(
        'notification.process_outbox(text,integer,timestamptz,interval,integer,integer,integer,text)'::regprocedure
      )
    )
  ) > 0,
  'processor preserves stable unsupported-event handling'
);

-- Isolated organization with evaluator settings and no source entities.
insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active,
  created_at
)
values (
  '00000000-0000-4000-8000-000000000010'::uuid,
  'PGTAP_OUTBOX_DISPATCH',
  'pgTAP Outbox Dispatch Organization',
  'Asia/Jakarta',
  true,
  '2026-07-26 07:00:00+07'::timestamptz
);

insert into app.settings (
  id,
  organization_id,
  key,
  value,
  version,
  effective_from,
  effective_to,
  created_at
)
values
(
  'f6090000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000010'::uuid,
  'expiry.warning_days',
  '[90,60,30,0]'::jsonb,
  1,
  '2026-07-26 00:00:00+07'::timestamptz,
  null,
  '2026-07-26 07:00:00+07'::timestamptz
),
(
  'f6090000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000010'::uuid,
  'return.inspection_sla_hours',
  '[24,72]'::jsonb,
  1,
  '2026-07-26 00:00:00+07'::timestamptz,
  null,
  '2026-07-26 07:00:00+07'::timestamptz
);

create temporary table dispatch_domain_counts_before as
select
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  )::bigint as transaction_count,
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  )::bigint as ledger_count,
  (
    select count(*)
    from operations.returns
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  )::bigint as return_count,
  (
    select count(*)
    from reconciliation.issues
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  )::bigint as issue_count,
  (
    select count(*)
    from reconciliation.runs
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  )::bigint as reconciliation_run_count,
  (
    select count(*)
    from operations.stocktakes
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  )::bigint as stocktake_count;

create temporary table broad_events (
  event_type_code text primary key,
  outbox_event_id uuid not null
);

insert into broad_events (
  event_type_code,
  outbox_event_id
)
select
  event_type_code,
  (enqueue_result ->> 'outboxEventId')::uuid
from (
  values
  (
    'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
    notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000010'::uuid,
      'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
      'dispatch:expiry:2026-07-26',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000010'::uuid,
      '2026-07-26 08:00:00+07'::timestamptz,
      '{"reason":"SCHEDULED"}'::jsonb,
      'f9700000-0000-4000-8000-000000000001'::uuid,
      null,
      'pgtap.outbox_dispatch_producer'
    )
  ),
  (
    'NOTIFICATION_RETURN_INSPECTION_EVALUATION_REQUESTED',
    notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000010'::uuid,
      'NOTIFICATION_RETURN_INSPECTION_EVALUATION_REQUESTED',
      'dispatch:return:2026-07-26',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000010'::uuid,
      '2026-07-26 08:01:00+07'::timestamptz,
      '{"reason":"RETURN_SOURCE_CHANGED"}'::jsonb,
      'f9700000-0000-4000-8000-000000000002'::uuid,
      null,
      'pgtap.outbox_dispatch_producer'
    )
  ),
  (
    'NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED',
    notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000010'::uuid,
      'NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED',
      'dispatch:reconciliation:2026-07-26',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000010'::uuid,
      '2026-07-26 08:02:00+07'::timestamptz,
      '{"reason":"RECONCILIATION_COMPLETED"}'::jsonb,
      'f9700000-0000-4000-8000-000000000003'::uuid,
      null,
      'pgtap.outbox_dispatch_producer'
    )
  ),
  (
    'NOTIFICATION_STOCKTAKE_EVALUATION_REQUESTED',
    notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000010'::uuid,
      'NOTIFICATION_STOCKTAKE_EVALUATION_REQUESTED',
      'dispatch:stocktake:2026-07-26',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000010'::uuid,
      '2026-07-26 08:03:00+07'::timestamptz,
      '{"reason":"STOCKTAKE_SOURCE_CHANGED"}'::jsonb,
      'f9700000-0000-4000-8000-000000000004'::uuid,
      null,
      'pgtap.outbox_dispatch_producer'
    )
  )
) enqueued(event_type_code, enqueue_result);

create temporary table broad_process as
select notification.process_outbox(
  'worker-dispatch-broad',
  10,
  '2026-07-26 09:00:00+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox_dispatch'
) as result;

-- Broad family dispatch and multi-evaluator linkage.
select is(
  (select (result ->> 'claimedCount')::integer from broad_process),
  4,
  'processor claims four broad family events'
);

select is(
  (select (result ->> 'completedCount')::integer from broad_process),
  4,
  'all broad family events complete'
);

select is(
  (
    select (result ->> 'retryableFailureCount')::integer
    from broad_process
  ),
  0,
  'broad dispatch has no retryable failures'
);

select is(
  (
    select (result ->> 'finalFailureCount')::integer
    from broad_process
  ),
  0,
  'broad dispatch has no final failures'
);

select is(
  (
    select count(*)
    from notification.outbox_events event_row
    join broad_events broad
      on broad.outbox_event_id = event_row.id
    where event_row.status_code = 'COMPLETED'
  ),
  4::bigint,
  'all broad events reach COMPLETED'
);

select is(
  (
    select sum(event_row.attempt_count)::bigint
    from notification.outbox_events event_row
    join broad_events broad
      on broad.outbox_event_id = event_row.id
  ),
  4::bigint,
  'each broad event records one attempt'
);

select is(
  (
    select count(*)
    from notification.rule_runs run
    join broad_events broad
      on broad.outbox_event_id =
         run.triggered_by_outbox_event_id
  ),
  6::bigint,
  'four broad events link six evaluator runs'
);

select is(
  (
    select count(*)
    from notification.rule_runs run
    join broad_events broad
      on broad.outbox_event_id =
         run.triggered_by_outbox_event_id
    where run.trigger_type_code = 'OUTBOX'
  ),
  6::bigint,
  'all broad evaluator runs are classified OUTBOX'
);

select is(
  (
    select count(*)
    from notification.rule_runs run
    join broad_events broad
      on broad.outbox_event_id =
         run.triggered_by_outbox_event_id
    where run.status_code = 'SUCCEEDED'
  ),
  6::bigint,
  'all broad evaluator runs succeed'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select outbox_event_id
      from broad_events
      where event_type_code =
        'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED'
    )
  ),
  1::bigint,
  'expiry broad event links one evaluator run'
);

select is(
  (
    select rule_code_snapshot
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select outbox_event_id
      from broad_events
      where event_type_code =
        'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED'
    )
  ),
  'EXPIRY_RISK',
  'expiry event dispatches expiry evaluator'
);

select is(
  (
    select rule_code_snapshot
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select outbox_event_id
      from broad_events
      where event_type_code =
        'NOTIFICATION_RETURN_INSPECTION_EVALUATION_REQUESTED'
    )
  ),
  'RETURN_INSPECTION_PENDING',
  'return event dispatches return inspection evaluator'
);

select is(
  (
    select array_agg(rule_code_snapshot order by rule_code_snapshot)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select outbox_event_id
      from broad_events
      where event_type_code =
        'NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED'
    )
  ),
  array[
    'RECONCILIATION_ISSUE_HIGH_CRITICAL',
    'RECONCILIATION_RUN_FAILED'
  ]::text[],
  'reconciliation family event dispatches both evaluators'
);

select is(
  (
    select array_agg(rule_code_snapshot order by rule_code_snapshot)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select outbox_event_id
      from broad_events
      where event_type_code =
        'NOTIFICATION_STOCKTAKE_EVALUATION_REQUESTED'
    )
  ),
  array[
    'STOCKTAKE_POST_FAILED',
    'STOCKTAKE_RECOUNT_REQUIRED'
  ]::text[],
  'stocktake family event dispatches both evaluators'
);

select is(
  (
    select (
      item.value -> 'dispatchResult' ->> 'evaluatorCount'
    )::integer
    from broad_process process_row
    cross join lateral jsonb_array_elements(
      process_row.result -> 'items'
    ) item(value)
    where item.value ->> 'eventTypeCode' =
      'NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED'
  ),
  2,
  'reconciliation dispatch result reports two evaluators'
);

select is(
  (
    select (
      item.value -> 'dispatchResult' ->> 'evaluatorCount'
    )::integer
    from broad_process process_row
    cross join lateral jsonb_array_elements(
      process_row.result -> 'items'
    ) item(value)
    where item.value ->> 'eventTypeCode' =
      'NOTIFICATION_STOCKTAKE_EVALUATION_REQUESTED'
  ),
  2,
  'stocktake dispatch result reports two evaluators'
);

select is(
  (
    select item.value -> 'dispatchResult' ->> 'status'
    from broad_process process_row
    cross join lateral jsonb_array_elements(
      process_row.result -> 'items'
    ) item(value)
    where item.value ->> 'eventTypeCode' =
      'NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED'
  ),
  'SUCCEEDED',
  'multi-evaluator reconciliation status is aggregated'
);

select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  ),
  0::bigint,
  'empty organization creates no fabricated notifications'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  ),
  (
    select transaction_count
    from dispatch_domain_counts_before
  ),
  'broad dispatch creates no stock transaction'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  ),
  (
    select ledger_count
    from dispatch_domain_counts_before
  ),
  'broad dispatch creates no ledger movement'
);

select is(
  (
    notification.process_outbox(
      'worker-dispatch-broad-replay',
      10,
      '2026-07-26 09:01:00+07'::timestamptz,
      interval '5 minutes',
      3,
      10,
      30,
      'pgtap.notification_outbox_dispatch'
    ) ->> 'claimedCount'
  )::integer,
  0,
  'completed broad events are not claimed again'
);

select is(
  (
    select count(*)
    from notification.rule_runs run
    join broad_events broad
      on broad.outbox_event_id =
         run.triggered_by_outbox_event_id
  ),
  6::bigint,
  'broad replay creates no duplicate rule run'
);

-- Granular event codes each dispatch exactly one evaluator.
create temporary table granular_events (
  event_type_code text primary key,
  expected_rule_code text not null,
  outbox_event_id uuid not null
);

insert into granular_events (
  event_type_code,
  expected_rule_code,
  outbox_event_id
)
select
  event_type_code,
  expected_rule_code,
  (enqueue_result ->> 'outboxEventId')::uuid
from (
  values
  (
    'NOTIFICATION_RECONCILIATION_ISSUE_EVALUATION_REQUESTED',
    'RECONCILIATION_ISSUE_HIGH_CRITICAL',
    notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000010'::uuid,
      'NOTIFICATION_RECONCILIATION_ISSUE_EVALUATION_REQUESTED',
      'dispatch:reconciliation-issue:2026-07-27',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000010'::uuid,
      '2026-07-27 08:00:00+07'::timestamptz,
      '{}'::jsonb,
      'f9700000-0000-4000-8000-000000000005'::uuid,
      null,
      'pgtap.outbox_dispatch_producer'
    )
  ),
  (
    'NOTIFICATION_RECONCILIATION_FAILURE_EVALUATION_REQUESTED',
    'RECONCILIATION_RUN_FAILED',
    notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000010'::uuid,
      'NOTIFICATION_RECONCILIATION_FAILURE_EVALUATION_REQUESTED',
      'dispatch:reconciliation-failure:2026-07-27',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000010'::uuid,
      '2026-07-27 08:01:00+07'::timestamptz,
      '{}'::jsonb,
      'f9700000-0000-4000-8000-000000000006'::uuid,
      null,
      'pgtap.outbox_dispatch_producer'
    )
  ),
  (
    'NOTIFICATION_STOCKTAKE_RECOUNT_EVALUATION_REQUESTED',
    'STOCKTAKE_RECOUNT_REQUIRED',
    notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000010'::uuid,
      'NOTIFICATION_STOCKTAKE_RECOUNT_EVALUATION_REQUESTED',
      'dispatch:stocktake-recount:2026-07-27',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000010'::uuid,
      '2026-07-27 08:02:00+07'::timestamptz,
      '{}'::jsonb,
      'f9700000-0000-4000-8000-000000000007'::uuid,
      null,
      'pgtap.outbox_dispatch_producer'
    )
  ),
  (
    'NOTIFICATION_STOCKTAKE_POST_FAILURE_EVALUATION_REQUESTED',
    'STOCKTAKE_POST_FAILED',
    notification.enqueue_outbox_event(
      '00000000-0000-4000-8000-000000000010'::uuid,
      'NOTIFICATION_STOCKTAKE_POST_FAILURE_EVALUATION_REQUESTED',
      'dispatch:stocktake-post-failure:2026-07-27',
      'ORGANIZATION',
      '00000000-0000-4000-8000-000000000010'::uuid,
      '2026-07-27 08:03:00+07'::timestamptz,
      '{}'::jsonb,
      'f9700000-0000-4000-8000-000000000008'::uuid,
      null,
      'pgtap.outbox_dispatch_producer'
    )
  )
) enqueued(event_type_code, expected_rule_code, enqueue_result);

create temporary table granular_process as
select notification.process_outbox(
  'worker-dispatch-granular',
  10,
  '2026-07-27 09:00:00+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox_dispatch'
) as result;

select is(
  (select (result ->> 'claimedCount')::integer from granular_process),
  4,
  'processor claims four granular events'
);

select is(
  (select (result ->> 'completedCount')::integer from granular_process),
  4,
  'all granular events complete'
);

select is(
  (
    select count(*)
    from notification.rule_runs run
    join granular_events event_fixture
      on event_fixture.outbox_event_id =
         run.triggered_by_outbox_event_id
  ),
  4::bigint,
  'granular events create one rule run each'
);

select is(
  (
    select count(*)
    from notification.rule_runs run
    join granular_events event_fixture
      on event_fixture.outbox_event_id =
         run.triggered_by_outbox_event_id
     and event_fixture.expected_rule_code =
         run.rule_code_snapshot
  ),
  4::bigint,
  'each granular event maps to its expected evaluator'
);

select is(
  (
    select count(*)
    from notification.rule_runs run
    join granular_events event_fixture
      on event_fixture.outbox_event_id =
         run.triggered_by_outbox_event_id
    where run.trigger_type_code = 'OUTBOX'
  ),
  4::bigint,
  'granular evaluator runs are classified OUTBOX'
);

select is(
  (
    select count(*)
    from notification.outbox_events event_row
    join granular_events event_fixture
      on event_fixture.outbox_event_id = event_row.id
    where event_row.status_code = 'COMPLETED'
  ),
  4::bigint,
  'all granular events reach COMPLETED'
);

select is(
  (
    select sum(
      (
        item.value -> 'dispatchResult' ->> 'evaluatorCount'
      )::integer
    )::bigint
    from granular_process process_row
    cross join lateral jsonb_array_elements(
      process_row.result -> 'items'
    ) item(value)
  ),
  4::bigint,
  'granular dispatch results report four total evaluators'
);

-- Direct dispatch requires an event already claimed by a worker.
create temporary table pending_direct_dispatch as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000010'::uuid,
  'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
  'dispatch:pending-direct',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000010'::uuid,
  '2026-08-20 08:00:00+07'::timestamptz,
  '{}'::jsonb,
  'f9700000-0000-4000-8000-000000000009'::uuid,
  null,
  'pgtap.outbox_dispatch_producer'
) as result;

select throws_ok(
  format(
    'select notification.dispatch_outbox_event(%L::uuid, %L)',
    (
      select result ->> 'outboxEventId'
      from pending_direct_dispatch
    ),
    'pgtap.direct_dispatch'
  ),
  'P0001',
  'OUTBOX_DISPATCH_EVENT_NOT_PROCESSING',
  'dispatcher rejects an event that has not been claimed'
);

-- Multi-evaluator failure is aggregated and safely retried.
update notification.rules
set config = jsonb_set(
  config,
  '{postingStaleMinutes}',
  '0'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000010'::uuid
  and code = 'STOCKTAKE_POST_FAILED';

create temporary table retry_event as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000010'::uuid,
  'NOTIFICATION_STOCKTAKE_EVALUATION_REQUESTED',
  'dispatch:stocktake:retry',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000010'::uuid,
  '2026-07-28 08:00:00+07'::timestamptz,
  '{"reason":"CONFIG_FAILURE_TEST"}'::jsonb,
  'f9700000-0000-4000-8000-000000000010'::uuid,
  null,
  'pgtap.outbox_dispatch_producer'
) as result;

create temporary table failed_multi_process as
select notification.process_outbox(
  'worker-dispatch-failed-multi',
  10,
  '2026-07-28 09:00:00+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox_dispatch'
) as result;

select is(
  (
    select (result ->> 'claimedCount')::integer
    from failed_multi_process
  ),
  1,
  'processor claims multi-evaluator event'
);

select is(
  (
    select (result ->> 'retryableFailureCount')::integer
    from failed_multi_process
  ),
  1,
  'one failed evaluator makes family event retryable'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
  ),
  'FAILED_RETRYABLE',
  'failed family event reaches FAILED_RETRYABLE'
);

select is(
  (
    select last_error_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
  ),
  'OUTBOX_EVALUATOR_FAILED',
  'failed family event exposes stable evaluator failure'
);

select is(
  (
    select available_at
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
  ),
  '2026-07-28 09:00:10+07'::timestamptz,
  'failed family event receives configured retry delay'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
  ),
  2::bigint,
  'failed family attempt links both evaluator runs'
);

select is(
  (
    select array_agg(status_code order by rule_code_snapshot)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
  ),
  array['FAILED', 'SUCCEEDED']::text[],
  'failed family attempt preserves one failed and one successful run'
);

select is(
  (
    select item.value -> 'dispatchResult' ->> 'status'
    from failed_multi_process process_row
    cross join lateral jsonb_array_elements(
      process_row.result -> 'items'
    ) item(value)
    where item.value ->> 'eventTypeCode' =
      'NOTIFICATION_STOCKTAKE_EVALUATION_REQUESTED'
  ),
  'FAILED',
  'family dispatch aggregates FAILED status'
);

update notification.rules
set config = jsonb_set(
  config,
  '{postingStaleMinutes}',
  '30'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000010'::uuid
  and code = 'STOCKTAKE_POST_FAILED';

create temporary table successful_retry_process as
select notification.process_outbox(
  'worker-dispatch-retry-success',
  10,
  '2026-07-28 09:00:10+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox_dispatch'
) as result;

select is(
  (
    select (result ->> 'completedCount')::integer
    from successful_retry_process
  ),
  1,
  'family event completes after evaluator repair'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
  ),
  'COMPLETED',
  'successful retry completes family event'
);

select is(
  (
    select attempt_count
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
  ),
  2,
  'family retry records second attempt'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
  ),
  4::bigint,
  'two family attempts preserve four evaluator runs'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
      and status_code = 'SUCCEEDED'
  ),
  3::bigint,
  'retry history preserves three successful runs'
);

select is(
  (
    select count(distinct idempotency_key)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
  ),
  4::bigint,
  'every evaluator attempt receives a distinct idempotency key'
);

select is(
  (
    notification.process_outbox(
      'worker-dispatch-retry-replay',
      10,
      '2026-07-28 09:01:00+07'::timestamptz,
      interval '5 minutes',
      3,
      10,
      30,
      'pgtap.notification_outbox_dispatch'
    ) ->> 'claimedCount'
  )::integer,
  0,
  'completed family retry is not claimed again'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from retry_event
    )
  ),
  4::bigint,
  'completed family replay creates no duplicate run'
);

-- Unsupported event remains a visible poison event.
create temporary table unsupported_event as
select notification.enqueue_outbox_event(
  '00000000-0000-4000-8000-000000000010'::uuid,
  'NOTIFICATION_UNKNOWN_EVALUATION_REQUESTED',
  'dispatch:unsupported',
  'ORGANIZATION',
  '00000000-0000-4000-8000-000000000010'::uuid,
  '2026-07-29 08:00:00+07'::timestamptz,
  '{}'::jsonb,
  'f9700000-0000-4000-8000-000000000011'::uuid,
  null,
  'pgtap.outbox_dispatch_producer'
) as result;

create temporary table unsupported_process as
select notification.process_outbox(
  'worker-dispatch-unsupported',
  10,
  '2026-07-29 09:00:00+07'::timestamptz,
  interval '5 minutes',
  3,
  10,
  30,
  'pgtap.notification_outbox_dispatch'
) as result;

select is(
  (
    select (result ->> 'finalFailureCount')::integer
    from unsupported_process
  ),
  1,
  'unsupported event is counted as final failure'
);

select is(
  (
    select status_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from unsupported_event
    )
  ),
  'FAILED_FINAL',
  'unsupported event reaches FAILED_FINAL'
);

select is(
  (
    select last_error_code
    from notification.outbox_events
    where id = (
      select (result ->> 'outboxEventId')::uuid
      from unsupported_event
    )
  ),
  'OUTBOX_EVENT_TYPE_UNSUPPORTED',
  'unsupported event exposes stable error code'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where triggered_by_outbox_event_id = (
      select (result ->> 'outboxEventId')::uuid
      from unsupported_event
    )
  ),
  0::bigint,
  'unsupported event fabricates no evaluator run'
);

-- Final source isolation checks.
select is(
  (
    select count(*)
    from operations.returns
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  ),
  (
    select return_count
    from dispatch_domain_counts_before
  ),
  'dispatcher does not create or mutate returns'
);

select is(
  (
    select count(*)
    from reconciliation.issues
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  ),
  (
    select issue_count
    from dispatch_domain_counts_before
  ),
  'dispatcher does not create reconciliation issues'
);

select is(
  (
    select count(*)
    from reconciliation.runs
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  ),
  (
    select reconciliation_run_count
    from dispatch_domain_counts_before
  ),
  'dispatcher does not create domain reconciliation runs'
);

select is(
  (
    select count(*)
    from operations.stocktakes
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  ),
  (
    select stocktake_count
    from dispatch_domain_counts_before
  ),
  'dispatcher does not create or mutate stocktakes'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  ),
  (
    select transaction_count
    from dispatch_domain_counts_before
  ),
  'dispatcher remains stock-transaction neutral'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  ),
  (
    select ledger_count
    from dispatch_domain_counts_before
  ),
  'dispatcher remains ledger neutral'
);

select * from finish();
rollback;
