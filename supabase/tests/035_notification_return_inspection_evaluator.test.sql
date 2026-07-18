begin;

create extension if not exists pgtap with schema extensions;

select plan(121);

-- 1-12: evaluator contract and trusted execution surface.
select has_function(
  'notification'::name,
  'ensure_return_inspection_rule'::name,
  array[
    'uuid',
    'timestamp with time zone'
  ]::text[]
);

select has_function(
  'notification'::name,
  'evaluate_return_inspection'::name,
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
  'ensure_return_inspection_rule',
  array[
    'uuid',
    'timestamptz'
  ]::text[],
  'uuid'
);

select function_returns(
  'notification',
  'evaluate_return_inspection',
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
    'notification.ensure_return_inspection_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'service role may provision the return inspection rule'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.ensure_return_inspection_rule(uuid,timestamptz)',
    'EXECUTE'
  ),
  'authenticated clients cannot provision notification rules'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.evaluate_return_inspection(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'service role may evaluate pending return inspection'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.evaluate_return_inspection(uuid,text,timestamptz,text,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot run the return evaluator'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.ensure_return_inspection_rule(uuid,timestamptz)'::regprocedure
  ),
  'rule provisioning is security definer'
);

select ok(
  (
    select process.prosecdef
    from pg_proc process
    where process.oid =
      'notification.evaluate_return_inspection(uuid,text,timestamptz,text,uuid,text)'::regprocedure
  ),
  'return evaluator is security definer'
);

select ok(
  position(
    'received_qty'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_return_inspection(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'evaluator derives the source condition from return quantities'
);

select ok(
  position(
    'return_inspection_allocations'
    in lower(
      pg_get_functiondef(
        'notification.evaluate_return_inspection(uuid,text,timestamptz,text,uuid,text)'::regprocedure
      )
    )
  ) > 0,
  'evaluator reconciles receipt quantities with inspection allocations'
);

create temporary table return_notification_results (
  kind text primary key,
  result jsonb not null
) on commit drop;

-- Arrange one real shipped marketplace order and an expected return of four units.
insert into return_notification_results (kind, result)
select
  'RESERVE',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-NTF-RETURN-RESERVE-001',
    'SHOPEE',
    'RESERVE',
    'NTF-RET-MKT-EVT-RESERVE-001',
    'NTF-RET-ORDER-001',
    '2026-07-23 08:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        4,
        'sourceLineRef',
        'NTF-RET-ITEM-001'
      )
    ),
    'Reserve stock for notification evaluator test.',
    '{"test":true,"fixture":"return-notification"}'::jsonb
  );

insert into return_notification_results (kind, result)
select
  'SHIP',
  api.apply_marketplace_event(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-NTF-RETURN-SHIP-001',
    'SHOPEE',
    'SHIP',
    'NTF-RET-MKT-EVT-SHIP-001',
    'NTF-RET-ORDER-001',
    '2026-07-23 08:10:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        4,
        'sourceLineRef',
        'NTF-RET-ITEM-001'
      )
    ),
    'Ship stock for notification evaluator test.',
    '{"test":true,"fixture":"return-notification"}'::jsonb
  );

insert into return_notification_results (kind, result)
select
  'EXPECTED',
  api.create_expected_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-NTF-RETURN-EXPECTED-001',
    'SHOPEE',
    'NTF-RETURN-001',
    'NTF-RET-ORDER-001',
    '2026-07-23 09:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'productId',
        '30000000-0000-4000-8000-000000000001',
        'quantity',
        4,
        'sourceLineRef',
        'NTF-RET-ITEM-001'
      )
    ),
    'RETURN_REQUESTED',
    'Expected return for notification evaluator.',
    '{"test":true,"fixture":"return-notification"}'::jsonb
  );

insert into return_notification_results (kind, result)
select
  'RECEIPT_ONE',
  api.confirm_return_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-NTF-RETURN-RECEIPT-001',
    'NTF-RETURN-001',
    'NTF-RECEIPT-001',
    '2026-07-23 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header
            on return_header.id = item.return_id
          where return_header.external_return_ref =
            'NTF-RETURN-001'
        ),
        'marketplaceShipAllocationId',
        (
          select allocation.id::text
          from operations.marketplace_ship_allocations allocation
          join operations.marketplace_events event
            on event.id = allocation.event_id
          where event.external_event_ref =
            'NTF-RET-MKT-EVT-SHIP-001'
        ),
        'quantity',
        2,
        'sourceLineRef',
        'NTF-RECEIPT-LINE-001'
      )
    ),
    'First physical return receipt.',
    '{"test":true,"fixture":"return-notification"}'::jsonb
  );

-- 13-20: real domain fixture reaches pending inspection without shortcuts.
select is(
  (
    select result ->> 'status'
    from return_notification_results
    where kind = 'RESERVE'
  ),
  'APPLIED',
  'marketplace reservation is applied'
);

select is(
  (
    select result ->> 'status'
    from return_notification_results
    where kind = 'SHIP'
  ),
  'APPLIED',
  'marketplace shipment is applied'
);

select is(
  (
    select result ->> 'status'
    from return_notification_results
    where kind = 'EXPECTED'
  ),
  'EXPECTED',
  'expected return is created'
);

select is(
  (
    select result ->> 'status'
    from return_notification_results
    where kind = 'RECEIPT_ONE'
  ),
  'PARTIALLY_RECEIVED',
  'first receipt leaves the return partially received'
);

select is(
  (
    select pending_inspection_qty
    from api.returns
    where external_return_ref = 'NTF-RETURN-001'
  ),
  2::numeric,
  'two received units are pending inspection'
);

select is(
  (
    select pending_arrival_qty
    from api.returns
    where external_return_ref = 'NTF-RETURN-001'
  ),
  2::numeric,
  'two expected units are still pending arrival'
);

select is(
  (
    select count(*)
    from operations.return_receipts
    where return_id = (
      select id
      from operations.returns
      where external_return_ref = 'NTF-RETURN-001'
    )
  ),
  1::bigint,
  'one receipt exists before notification evaluation'
);

select is(
  (
    select quarantine_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'received units are physically held in quarantine'
);

create temporary table return_domain_before_first_eval as
select
  return_header.status_code,
  return_header.outcome_code,
  return_header.updated_at,
  item.received_qty,
  item.sellable_qty,
  item.damaged_qty,
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.organization_id =
      return_header.organization_id
  )::bigint as transaction_count,
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    where entry.organization_id =
      return_header.organization_id
  )::bigint as ledger_count,
  (
    select position.quarantine_qty
    from inventory.stock_product_positions position
    where position.organization_id =
      return_header.organization_id
      and position.product_id = item.product_id
  )::bigint as quarantine_qty
from operations.returns return_header
join operations.return_items item
  on item.organization_id = return_header.organization_id
 and item.return_id = return_header.id
where return_header.external_return_ref = 'NTF-RETURN-001';

create temporary table first_return_evaluation as
select notification.evaluate_return_inspection(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'return-inspection:initial',
  '2026-07-23 11:00:00+07'::timestamptz,
  'SCHEDULED',
  '97500000-0000-4000-8000-000000000001'::uuid,
  'pgtap.return_inspection_evaluator'
) as result;

-- 21-47: initial evaluation creates one warning episode and preserves source state.
select is(
  (select result ->> 'action' from first_return_evaluation),
  'COMPLETED',
  'initial evaluator run completes'
);

select is(
  (select result ->> 'status' from first_return_evaluation),
  'SUCCEEDED',
  'initial evaluator run succeeds'
);

select is(
  (
    select (result ->> 'evaluatedCount')::integer
    from first_return_evaluation
  ),
  1,
  'initial evaluator examines one return'
);

select is(
  (
    select (result ->> 'createdCount')::integer
    from first_return_evaluation
  ),
  1,
  'initial evaluator creates one episode'
);

select is(
  (
    select (result ->> 'updatedCount')::integer
    from first_return_evaluation
  ),
  0,
  'initial evaluator records no update'
);

select is(
  (
    select (result ->> 'resolvedCount')::integer
    from first_return_evaluation
  ),
  0,
  'initial evaluator records no resolution'
);

select is(
  (
    select (result ->> 'skippedCount')::integer
    from first_return_evaluation
  ),
  0,
  'initial evaluator skips no source return'
);

select is(
  (
    select (result ->> 'errorCount')::integer
    from first_return_evaluation
  ),
  0,
  'initial evaluator records no entity error'
);

select is(
  (
    select category_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'RETURN_INSPECTION_PENDING'
  ),
  'RETURN',
  'provisioned rule belongs to the RETURN category'
);

select is(
  (
    select trigger_mode_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'RETURN_INSPECTION_PENDING'
  ),
  'HYBRID',
  'return inspection rule is hybrid'
);

select is(
  (
    select entity_type_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'RETURN_INSPECTION_PENDING'
  ),
  'RETURN',
  'return inspection rule targets RETURN entities'
);

select is(
  (
    select action_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'RETURN_INSPECTION_PENDING'
  ),
  'OPEN_RETURN_INSPECTION_DETAIL',
  'rule recommends opening the return inspection detail'
);

select ok(
  (
    select config -> 'thresholdHours' = '[24,72]'::jsonb
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and code = 'RETURN_INSPECTION_PENDING'
  ),
  'default return inspection thresholds are 24 and 72 hours'
);

select is(
  (
    select count(*)
    from notification.notifications notification_row
    where notification_row.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and notification_row.rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  1::bigint,
  'one active notification is created for the return'
);

select is(
  (
    select stage_code
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  'PENDING',
  'one-hour-old pending inspection uses PENDING stage'
);

select is(
  (
    select severity_code
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  'WARNING',
  'initial pending inspection is WARNING severity'
);

select is(
  (
    select condition_started_at
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  '2026-07-23 10:00:00+07'::timestamptz,
  'condition starts at the earliest receipt with uninspected quantity'
);

select is(
  (
    select due_at
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  '2026-07-24 10:00:00+07'::timestamptz,
  'notification due time is the warning SLA boundary'
);

select is(
  (
    select action_route
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  (
    select '/returns?returnId=' || id::text
    from operations.returns
    where external_return_ref = 'NTF-RETURN-001'
  ),
  'notification deep-links to the source return'
);

select is(
  (
    select source_snapshot ->> 'pendingInspectionQty'
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  '2',
  'source snapshot records pending inspection quantity'
);

select is(
  (
    select source_snapshot ->> 'pendingReceiptCount'
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  '1',
  'source snapshot records one pending receipt'
);

select is(
  (
    select source_snapshot ->> 'ageHours'
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  '1',
  'source snapshot records one hour of pending age'
);

select is(
  (
    select episode_no
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  1,
  'initial condition creates episode one'
);

select is(
  (
    select count(*)
    from notification.notification_events event_row
    where event_row.notification_id = (
      select id
      from notification.notifications notification_row
      where notification_row.rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
        and notification_row.entity_id = (
          select id
          from operations.returns
          where external_return_ref = 'NTF-RETURN-001'
        )
    )
      and event_row.event_type_code = 'CREATED'
  ),
  1::bigint,
  'initial episode has one CREATED history event'
);

select is(
  (
    select status_code
    from operations.returns
    where external_return_ref = 'NTF-RETURN-001'
  ),
  (
    select status_code
    from return_domain_before_first_eval
  ),
  'evaluator does not change return status'
);

select is(
  (
    select received_qty
    from operations.return_items
    where return_id = (
      select id
      from operations.returns
      where external_return_ref = 'NTF-RETURN-001'
    )
  ),
  (
    select received_qty
    from return_domain_before_first_eval
  ),
  'evaluator does not change received quantity'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select transaction_count
    from return_domain_before_first_eval
  ),
  'evaluator creates no stock transaction'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    where entry.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select ledger_count
    from return_domain_before_first_eval
  ),
  'evaluator creates no ledger movement'
);

select is(
  (
    select quarantine_qty
    from inventory.stock_product_positions
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and product_id =
        '30000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select quarantine_qty
    from return_domain_before_first_eval
  ),
  'evaluator does not change quarantine projection'
);

create temporary table replay_return_evaluation as
select notification.evaluate_return_inspection(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'return-inspection:initial',
  '2026-07-23 12:00:00+07'::timestamptz,
  'MANUAL',
  '97500000-0000-4000-8000-000000000099'::uuid,
  'pgtap.return_inspection_evaluator'
) as result;

-- 48-52: idempotency replay returns the original run without touching the episode.
select is(
  (select result ->> 'action' from replay_return_evaluation),
  'REPLAYED',
  'same rule-run key is replayed'
);

select is(
  (
    select result ->> 'ruleRunId'
    from replay_return_evaluation
  ),
  (
    select result ->> 'ruleRunId'
    from first_return_evaluation
  ),
  'replay returns the original rule run'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
      and idempotency_key =
        'return-inspection:initial'
  ),
  1::bigint,
  'replay does not duplicate the rule run'
);

select is(
  (
    select occurrence_count
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  1,
  'replay does not increment episode occurrence'
);

select is(
  (
    select count(*)
    from notification.notification_events event_row
    where event_row.notification_id = (
      select id
      from notification.notifications notification_row
      where notification_row.rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
        and notification_row.entity_id = (
          select id
          from operations.returns
          where external_return_ref = 'NTF-RETURN-001'
        )
    )
  ),
  1::bigint,
  'replay appends no notification history'
);

create temporary table overdue_return_evaluation as
select notification.evaluate_return_inspection(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'return-inspection:overdue',
  '2026-07-24 11:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  '97500000-0000-4000-8000-000000000002'::uuid,
  'pgtap.return_inspection_evaluator'
) as result;

-- 53-62: the same episode escalates after 24 hours without duplication.
select is(
  (select result ->> 'status' from overdue_return_evaluation),
  'SUCCEEDED',
  'overdue evaluator run succeeds'
);

select is(
  (
    select (result ->> 'updatedCount')::integer
    from overdue_return_evaluation
  ),
  1,
  'overdue evaluator updates the active episode'
);

select is(
  (
    select stage_code
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  'PENDING_24H',
  'twenty-five-hour-old condition uses PENDING_24H stage'
);

select is(
  (
    select severity_code
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  'HIGH',
  'overdue pending inspection becomes HIGH severity'
);

select is(
  (
    select occurrence_count
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  2,
  'overdue observation increments occurrence on the same episode'
);

select is(
  (
    select count(*)
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
  ),
  1::bigint,
  'overdue escalation creates no duplicate notification row'
);

select is(
  (
    select count(*)
    from notification.notification_events event_row
    where event_row.notification_id = (
      select id
      from notification.notifications notification_row
      where notification_row.rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
        and notification_row.entity_id = (
          select id
          from operations.returns
          where external_return_ref = 'NTF-RETURN-001'
        )
    )
      and event_row.event_type_code = 'STAGE_ESCALATED'
  ),
  1::bigint,
  'overdue transition appends one stage escalation event'
);

select is(
  (
    select count(*)
    from notification.notification_events event_row
    where event_row.notification_id = (
      select id
      from notification.notifications notification_row
      where notification_row.rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
        and notification_row.entity_id = (
          select id
          from operations.returns
          where external_return_ref = 'NTF-RETURN-001'
        )
    )
      and event_row.event_type_code = 'SEVERITY_CHANGED'
  ),
  1::bigint,
  'overdue transition appends one severity change event'
);

select is(
  (
    select due_at
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  '2026-07-24 10:00:00+07'::timestamptz,
  'escalation preserves the original SLA due time'
);

select is(
  (
    select episode_no
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  1,
  'overdue stage remains in episode one'
);

create temporary table critical_return_evaluation as
select notification.evaluate_return_inspection(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'return-inspection:critical',
  '2026-07-26 11:00:00+07'::timestamptz,
  'SCHEDULED',
  '97500000-0000-4000-8000-000000000003'::uuid,
  'pgtap.return_inspection_evaluator'
) as result;

-- 63-69: the active episode escalates again after 72 hours.
select is(
  (select result ->> 'status' from critical_return_evaluation),
  'SUCCEEDED',
  'critical evaluator run succeeds'
);

select is(
  (
    select (result ->> 'updatedCount')::integer
    from critical_return_evaluation
  ),
  1,
  'critical evaluator updates the active episode'
);

select is(
  (
    select stage_code
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  'PENDING_72H',
  'seventy-three-hour-old condition uses PENDING_72H stage'
);

select is(
  (
    select severity_code
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  'CRITICAL',
  'severely overdue inspection becomes CRITICAL'
);

select is(
  (
    select occurrence_count
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  3,
  'critical observation increments occurrence'
);

select is(
  (
    select count(*)
    from notification.notification_events event_row
    where event_row.notification_id = (
      select id
      from notification.notifications notification_row
      where notification_row.rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
        and notification_row.entity_id = (
          select id
          from operations.returns
          where external_return_ref = 'NTF-RETURN-001'
        )
    )
      and event_row.event_type_code = 'STAGE_ESCALATED'
  ),
  2::bigint,
  'critical transition preserves two stage escalation events'
);

select is(
  (
    select count(*)
    from notification.notification_events event_row
    where event_row.notification_id = (
      select id
      from notification.notifications notification_row
      where notification_row.rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
        and notification_row.entity_id = (
          select id
          from operations.returns
          where external_return_ref = 'NTF-RETURN-001'
        )
    )
      and event_row.event_type_code = 'SEVERITY_CHANGED'
  ),
  2::bigint,
  'critical transition preserves two severity changes'
);

-- Inspect the first receipt completely. Pending arrival remains, but pending inspection clears.
insert into return_notification_results (kind, result)
select
  'INSPECTION_ONE',
  api.inspect_return(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-NTF-RETURN-INSPECT-001',
    'NTF-RETURN-001',
    'NTF-INSPECTION-001',
    '2026-07-26 12:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'receiptLineId',
        (
          select line.id::text
          from operations.return_receipt_lines line
          join operations.return_receipts receipt
            on receipt.id = line.receipt_id
          where receipt.receipt_ref = 'NTF-RECEIPT-001'
        ),
        'sellableQuantity',
        2,
        'damagedQuantity',
        0,
        'sourceLineRef',
        'NTF-INSPECTION-LINE-001'
      )
    ),
    'Inspect the first received quantity.',
    '{"test":true,"fixture":"return-notification"}'::jsonb
  );

select is(
  (
    select result ->> 'status'
    from return_notification_results
    where kind = 'INSPECTION_ONE'
  ),
  'PARTIALLY_INSPECTED',
  'first inspection leaves the return partially inspected'
);

select is(
  (
    select pending_inspection_qty
    from api.returns
    where external_return_ref = 'NTF-RETURN-001'
  ),
  0::numeric,
  'first inspection clears all currently received pending quantity'
);

create temporary table return_domain_before_resolution as
select
  return_header.status_code,
  item.received_qty,
  item.sellable_qty,
  item.damaged_qty,
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.organization_id =
      return_header.organization_id
  )::bigint as transaction_count,
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    where entry.organization_id =
      return_header.organization_id
  )::bigint as ledger_count
from operations.returns return_header
join operations.return_items item
  on item.organization_id = return_header.organization_id
 and item.return_id = return_header.id
where return_header.external_return_ref = 'NTF-RETURN-001';

create temporary table resolution_return_evaluation as
select notification.evaluate_return_inspection(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'return-inspection:resolved',
  '2026-07-26 13:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  '97500000-0000-4000-8000-000000000004'::uuid,
  'pgtap.return_inspection_evaluator'
) as result;

-- 72-82: source-condition clearing resolves the episode without domain mutation.
select is(
  (select result ->> 'status' from resolution_return_evaluation),
  'SUCCEEDED',
  'resolution evaluator run succeeds'
);

select is(
  (
    select (result ->> 'resolvedCount')::integer
    from resolution_return_evaluation
  ),
  1,
  'resolution evaluator resolves one episode'
);

select is(
  (
    select lifecycle_status_code
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 1
  ),
  'RESOLVED',
  'episode one becomes RESOLVED'
);

select is(
  (
    select resolution_code
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 1
  ),
  'SOURCE_CONDITION_CLEARED',
  'resolved episode stores source-condition resolution code'
);

select is(
  (
    select resolution_snapshot ->> 'resolutionReason'
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 1
  ),
  'PENDING_INSPECTION_ZERO',
  'resolution snapshot records zero pending inspection'
);

select is(
  (
    select count(*)
    from notification.notification_events event_row
    where event_row.notification_id = (
      select id
      from notification.notifications notification_row
      where notification_row.rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
        and notification_row.entity_id = (
          select id
          from operations.returns
          where external_return_ref = 'NTF-RETURN-001'
        )
        and notification_row.episode_no = 1
    )
      and event_row.event_type_code = 'RESOLVED'
  ),
  1::bigint,
  'resolution appends one RESOLVED history event'
);

select is(
  (
    select count(*)
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  0::bigint,
  'no active episode remains after inspection clears'
);

select is(
  (
    select status_code
    from operations.returns
    where external_return_ref = 'NTF-RETURN-001'
  ),
  (
    select status_code
    from return_domain_before_resolution
  ),
  'resolution evaluator does not change return status'
);

select is(
  (
    select count(*)
    from inventory.stock_transactions transaction
    where transaction.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select transaction_count
    from return_domain_before_resolution
  ),
  'resolution evaluator creates no stock transaction'
);

select is(
  (
    select count(*)
    from inventory.stock_ledger_entries entry
    where entry.organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
  ),
  (
    select ledger_count
    from return_domain_before_resolution
  ),
  'resolution evaluator creates no ledger entry'
);

select is(
  (
    select count(*)
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
  ),
  1::bigint,
  'resolved notification remains in history'
);

-- A second receipt on the same return creates a genuinely new condition episode.
insert into return_notification_results (kind, result)
select
  'RECEIPT_TWO',
  api.confirm_return_receipt(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'PGTAP-NTF-RETURN-RECEIPT-002',
    'NTF-RETURN-001',
    'NTF-RECEIPT-002',
    '2026-07-27 10:00:00+07'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'returnItemId',
        (
          select item.id::text
          from operations.return_items item
          join operations.returns return_header
            on return_header.id = item.return_id
          where return_header.external_return_ref =
            'NTF-RETURN-001'
        ),
        'marketplaceShipAllocationId',
        (
          select allocation.id::text
          from operations.marketplace_ship_allocations allocation
          join operations.marketplace_events event
            on event.id = allocation.event_id
          where event.external_event_ref =
            'NTF-RET-MKT-EVT-SHIP-001'
        ),
        'quantity',
        2,
        'sourceLineRef',
        'NTF-RECEIPT-LINE-002'
      )
    ),
    'Second physical return receipt.',
    '{"test":true,"fixture":"return-notification"}'::jsonb
  );

select is(
  (
    select pending_inspection_qty
    from api.returns
    where external_return_ref = 'NTF-RETURN-001'
  ),
  2::numeric,
  'second receipt creates two new units pending inspection'
);

select is(
  (
    select pending_arrival_qty
    from api.returns
    where external_return_ref = 'NTF-RETURN-001'
  ),
  0::numeric,
  'second receipt completes physical arrival'
);

create temporary table recurrence_return_evaluation as
select notification.evaluate_return_inspection(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'return-inspection:recurrence',
  '2026-07-27 11:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  '97500000-0000-4000-8000-000000000005'::uuid,
  'pgtap.return_inspection_evaluator'
) as result;

-- 85-96: recurrence after resolution creates episode two with predecessor linkage.
select is(
  (select result ->> 'status' from recurrence_return_evaluation),
  'SUCCEEDED',
  'recurrence evaluator run succeeds'
);

select is(
  (
    select (result ->> 'createdCount')::integer
    from recurrence_return_evaluation
  ),
  1,
  'recurrence creates one new episode'
);

select is(
  (
    select count(*)
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
  ),
  2::bigint,
  'return now has two historical notification episodes'
);

select is(
  (
    select count(*)
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  1::bigint,
  'only one episode is active after recurrence'
);

select is(
  (
    select episode_no
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  2,
  'recurrence creates episode two'
);

select is(
  (
    select previous_notification_id
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 2
  ),
  (
    select id
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 1
  ),
  'episode two links to the resolved predecessor'
);

select is(
  (
    select condition_started_at
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 2
  ),
  '2026-07-27 10:00:00+07'::timestamptz,
  'recurrence starts at the second pending receipt'
);

select is(
  (
    select stage_code
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 2
  ),
  'PENDING',
  'fresh recurrence returns to PENDING stage'
);

select is(
  (
    select severity_code
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 2
  ),
  'WARNING',
  'fresh recurrence returns to WARNING severity'
);

select is(
  (
    select source_snapshot ->> 'pendingReceiptCount'
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 2
  ),
  '1',
  'recurrence snapshot excludes the fully inspected first receipt'
);

select is(
  (
    select count(*)
    from notification.notification_events event_row
    where event_row.notification_id = (
      select id
      from notification.notifications notification_row
      where notification_row.rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
        and notification_row.entity_id = (
          select id
          from operations.returns
          where external_return_ref = 'NTF-RETURN-001'
        )
        and notification_row.episode_no = 2
    )
      and event_row.event_type_code =
        'REOPENED_AS_NEW_EPISODE'
  ),
  1::bigint,
  'recurrence appends one reopened-as-new-episode event'
);

select is(
  (
    select previous_notification_id is not null
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 2
  ),
  true,
  'recurrence preserves explicit predecessor identity'
);

create temporary table seen_again_return_evaluation as
select notification.evaluate_return_inspection(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'return-inspection:seen-again',
  '2026-07-27 11:00:00+07'::timestamptz,
  'MANUAL',
  '97500000-0000-4000-8000-000000000006'::uuid,
  'pgtap.return_inspection_evaluator'
) as result;

-- 97-100: repeated observation updates the same active recurrence episode.
select is(
  (
    select (result ->> 'updatedCount')::integer
    from seen_again_return_evaluation
  ),
  1,
  'repeated observation is counted as an update'
);

select is(
  (
    select occurrence_count
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.episode_no = 2
  ),
  2,
  'repeated observation increments occurrence on episode two'
);

select is(
  (
    select count(*)
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED'
      )
  ),
  1::bigint,
  'repeated observation preserves one active episode'
);

select is(
  (
    select episode_no
    from notification.notifications notification_row
    where notification_row.rule_code_snapshot =
      'RETURN_INSPECTION_PENDING'
      and notification_row.entity_id = (
        select id
        from operations.returns
        where external_return_ref = 'NTF-RETURN-001'
      )
      and notification_row.lifecycle_status_code = 'OPEN'
  ),
  2,
  'repeated observation remains in episode two'
);

-- Structural rule-config failure must be auditable and must not mutate the active episode.
create temporary table notification_state_before_invalid_config as
select
  notification_row.id,
  notification_row.version_no,
  notification_row.occurrence_count,
  notification_row.stage_code,
  notification_row.severity_code
from notification.notifications notification_row
where notification_row.rule_code_snapshot =
  'RETURN_INSPECTION_PENDING'
  and notification_row.entity_id = (
    select id
    from operations.returns
    where external_return_ref = 'NTF-RETURN-001'
  )
  and notification_row.lifecycle_status_code = 'OPEN';

update notification.rules
set config = jsonb_set(
  config,
  '{thresholdHours}',
  '[72,24]'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'RETURN_INSPECTION_PENDING';

create temporary table invalid_config_evaluation as
select notification.evaluate_return_inspection(
  '00000000-0000-4000-8000-000000000001'::uuid,
  'return-inspection:invalid-config',
  '2026-07-27 12:00:00+07'::timestamptz,
  'SCHEDULED',
  '97500000-0000-4000-8000-000000000007'::uuid,
  'pgtap.return_inspection_evaluator'
) as result;

-- 101-108: structural failure is visible and rolls back partial notification effects.
select is(
  (select result ->> 'status' from invalid_config_evaluation),
  'FAILED',
  'invalid rule config returns FAILED'
);

select is(
  (
    select result ->> 'errorCode'
    from invalid_config_evaluation
  ),
  'RETURN_INSPECTION_EVALUATION_FAILED',
  'invalid config exposes a stable evaluator error code'
);

select is(
  (
    select status_code
    from notification.rule_runs
    where id = (
      select (result ->> 'ruleRunId')::uuid
      from invalid_config_evaluation
    )
  ),
  'FAILED',
  'invalid config persists a failed rule run'
);

select is(
  (
    select error_code
    from notification.rule_runs
    where id = (
      select (result ->> 'ruleRunId')::uuid
      from invalid_config_evaluation
    )
  ),
  'RETURN_INSPECTION_EVALUATION_FAILED',
  'failed rule run stores the structural error code'
);

select is(
  (
    select version_no
    from notification.notifications
    where id = (
      select id
      from notification_state_before_invalid_config
    )
  ),
  (
    select version_no
    from notification_state_before_invalid_config
  ),
  'structural failure does not update notification version'
);

select is(
  (
    select occurrence_count
    from notification.notifications
    where id = (
      select id
      from notification_state_before_invalid_config
    )
  ),
  (
    select occurrence_count
    from notification_state_before_invalid_config
  ),
  'structural failure does not increment occurrence'
);

select is(
  (
    notification.evaluate_return_inspection(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'return-inspection:invalid-config',
      '2026-07-27 13:00:00+07'::timestamptz,
      'MANUAL',
      '97500000-0000-4000-8000-000000000098'::uuid,
      'pgtap.return_inspection_evaluator'
    ) ->> 'action'
  ),
  'REPLAYED',
  'failed rule run is still idempotently replayable'
);

select is(
  (
    notification.evaluate_return_inspection(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'return-inspection:invalid-config',
      '2026-07-27 13:00:00+07'::timestamptz,
      'MANUAL',
      '97500000-0000-4000-8000-000000000098'::uuid,
      'pgtap.return_inspection_evaluator'
    ) ->> 'status'
  ),
  'FAILED',
  'replay preserves the failed terminal status'
);

update notification.rules
set config = jsonb_set(
  config,
  '{thresholdHours}',
  '[24,72]'::jsonb,
  false
)
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'RETURN_INSPECTION_PENDING';

-- A second organization proves setting override and empty-source behavior.
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
  'PGTAP_RETURN_NTF_EMPTY',
  'pgTAP Empty Return Notification Organization',
  'Asia/Jakarta',
  true,
  '2026-07-16 09:00:00+07'::timestamptz
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
values (
  '61000000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000010'::uuid,
  'return.inspection_sla_hours',
  '[12,48]'::jsonb,
  1,
  '2026-07-16 00:00:00+07'::timestamptz,
  null,
  '2026-07-16 09:00:00+07'::timestamptz
);

create temporary table empty_org_evaluation as
select notification.evaluate_return_inspection(
  '00000000-0000-4000-8000-000000000010'::uuid,
  'return-inspection:empty-org',
  '2026-07-28 09:00:00+07'::timestamptz,
  'EVENT_DRIVEN',
  '97500000-0000-4000-8000-000000000008'::uuid,
  'pgtap.return_inspection_evaluator'
) as result;

-- 109-115: organization setting override and zero-source evaluation.
select is(
  (select result ->> 'status' from empty_org_evaluation),
  'SUCCEEDED',
  'empty organization evaluation succeeds'
);

select is(
  (
    select (result ->> 'evaluatedCount')::integer
    from empty_org_evaluation
  ),
  0,
  'empty organization evaluates zero returns'
);

select is(
  (
    select (result ->> 'createdCount')::integer
    from empty_org_evaluation
  ),
  0,
  'empty organization creates no notification'
);

select is(
  (
    select trigger_mode_code
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
      and code = 'RETURN_INSPECTION_PENDING'
  ),
  'HYBRID',
  'empty organization receives the same hybrid rule contract'
);

select ok(
  (
    select config -> 'thresholdHours' = '[12,48]'::jsonb
    from notification.rules
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
      and code = 'RETURN_INSPECTION_PENDING'
  ),
  'organization setting overrides default inspection thresholds'
);

select is(
  (
    select trigger_type_code
    from notification.rule_runs
    where id = (
      select (result ->> 'ruleRunId')::uuid
      from empty_org_evaluation
    )
  ),
  'EVENT_DRIVEN',
  'event-driven trigger is retained in rule-run audit'
);

select is(
  (
    select count(*)
    from notification.notifications
    where organization_id =
      '00000000-0000-4000-8000-000000000010'::uuid
  ),
  0::bigint,
  'empty organization has no fabricated notification'
);

-- Input and disabled-rule behavior.
select throws_ok(
  $sql$
    select notification.evaluate_return_inspection(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'return-inspection:invalid-trigger',
      '2026-07-28 10:00:00+07'::timestamptz,
      'OUTBOX',
      '97500000-0000-4000-8000-000000000009'::uuid,
      'pgtap.return_inspection_evaluator'
    )
  $sql$,
  'P0001',
  'RETURN_INSPECTION_TRIGGER_TYPE_INVALID',
  'evaluator rejects unsupported direct trigger type'
);

select throws_ok(
  $sql$
    select notification.evaluate_return_inspection(
      '00000000-0000-4000-8000-000000000001'::uuid,
      '   ',
      '2026-07-28 10:00:00+07'::timestamptz,
      'SCHEDULED',
      '97500000-0000-4000-8000-000000000010'::uuid,
      'pgtap.return_inspection_evaluator'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_RULE_RUN_IDEMPOTENCY_REQUIRED',
  'evaluator rejects blank idempotency key'
);

update notification.rules
set is_active = false
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'RETURN_INSPECTION_PENDING';

select throws_ok(
  $sql$
    select notification.evaluate_return_inspection(
      '00000000-0000-4000-8000-000000000001'::uuid,
      'return-inspection:disabled-rule',
      '2026-07-28 10:00:00+07'::timestamptz,
      'SCHEDULED',
      '97500000-0000-4000-8000-000000000011'::uuid,
      'pgtap.return_inspection_evaluator'
    )
  $sql$,
  'P0001',
  'RETURN_INSPECTION_RULE_NOT_ACTIVE',
  'disabled return inspection rule cannot be evaluated'
);

select is(
  (
    select count(*)
    from notification.rule_runs
    where organization_id =
      '00000000-0000-4000-8000-000000000001'::uuid
      and rule_code_snapshot =
        'RETURN_INSPECTION_PENDING'
      and idempotency_key =
        'return-inspection:disabled-rule'
  ),
  0::bigint,
  'disabled-rule rejection creates no phantom run'
);

update notification.rules
set is_active = true
where organization_id =
  '00000000-0000-4000-8000-000000000001'::uuid
  and code = 'RETURN_INSPECTION_PENDING';

select * from finish();
rollback;
