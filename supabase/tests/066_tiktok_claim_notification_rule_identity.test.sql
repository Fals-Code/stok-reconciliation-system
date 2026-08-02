begin;
create extension if not exists pgtap;
select plan(22);

-- This fixture deliberately recreates the retired seed identity.  It is
-- isolated, rolls back, and never touches Golden Demo evidence.
insert into app.organizations (id, code, name, timezone, is_active, created_at)
values (
  '00000000-0000-4000-8000-000000000066',
  'PGTAP_RULE_IDENTITY_066',
  'pgTAP TikTok rule identity fixture',
  'Asia/Jakarta', true, '2026-08-01 00:00:00+00'
);

insert into notification.rules(
  id, organization_id, code, version, category_code, trigger_mode_code,
  entity_type_code, severity_strategy_code, stage_strategy_code,
  condition_strategy_code, resolution_strategy_code, template_version,
  action_code, config, is_active, effective_from, effective_to, created_at, updated_at
) values (
  '80000000-0000-4000-8000-000000000066',
  '00000000-0000-4000-8000-000000000066',
  'CLAIM_DEADLINE', '1.0.0', 'CLAIM', 'HYBRID', 'CLAIM',
  'DYNAMIC', 'CLAIM_DEADLINE_STAGE', 'CLAIM_ELIGIBLE_AND_OPEN',
  'CLAIM_SUBMITTED_OR_RESOLVED', '1.0.0', 'OPEN_CLAIM_DETAIL',
  jsonb_build_object('thresholdDays', jsonb_build_array(14,7,3,1,0)),
  true, '2026-08-01 00:00:00+00', null,
  '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00'
);

select is(
  notification.ensure_tiktok_claim_rule(
    '00000000-0000-4000-8000-000000000066', 'CLAIM_DEADLINE', '2026-08-02 00:00:00+00'
  ) is distinct from '80000000-0000-4000-8000-000000000066'::uuid,
  true,
  'ensure never adopts a legacy CLAIM rule'
);
select is(
  (select count(*) from notification.rules where organization_id='00000000-0000-4000-8000-000000000066'::uuid and code='CLAIM_DEADLINE' and entity_type_code='RETURN_CLAIM' and is_active),
  1::bigint,
  'ensure provisions exactly one active RETURN_CLAIM deadline rule'
);
select is(
  (select category_code from notification.rules where organization_id='00000000-0000-4000-8000-000000000066'::uuid and code='CLAIM_DEADLINE' and entity_type_code='RETURN_CLAIM'),
  'RETURN',
  'canonical rule category is RETURN'
);
select is(
  (select action_code from notification.rules where organization_id='00000000-0000-4000-8000-000000000066'::uuid and code='CLAIM_DEADLINE' and entity_type_code='RETURN_CLAIM'),
  'OPEN_RETURN_CLAIM_DETAIL',
  'canonical rule action is the return-claim deep-link action'
);
select is(
  (select config->>'deadlineField' from notification.rules where organization_id='00000000-0000-4000-8000-000000000066'::uuid and code='CLAIM_DEADLINE' and entity_type_code='RETURN_CLAIM'),
  'deadline_at',
  'canonical rule uses the immutable claim deadline field'
);
select is(
  (notification.require_tiktok_claim_deadline_rule(
    '00000000-0000-4000-8000-000000000066', '2026-08-02 00:00:00+00'
  )).entity_type_code,
  'RETURN_CLAIM',
  'evaluator selection accepts only RETURN_CLAIM identity'
);
select throws_ok(
  $$select notification.require_tiktok_claim_deadline_rule('00000000-0000-4000-8000-000000000066','2026-07-31 23:59:59+00')$$,
  'P0001', 'CLAIM_NOTIFICATION_CANONICAL_RULE_NOT_EXACT',
  'non-effective canonical rule fails before a rule run can be created'
);
select ok(
  position('require_tiktok_claim_deadline_rule' in pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure)) > 0,
  'evaluator performs canonical identity selection before rule-run insertion'
);
select ok(
  position('entity_type_code = ''RETURN_CLAIM''' in pg_get_functiondef('notification.require_tiktok_claim_deadline_rule(uuid,timestamp with time zone)'::regprocedure)) > 0,
  'canonical evaluator selector pins RETURN_CLAIM'
);
select ok(
  not has_function_privilege('public','notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)','EXECUTE')
  and not has_function_privilege('anon','notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)','EXECUTE')
  and not has_function_privilege('authenticated','notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)','EXECUTE'),
  'rule provisioner remains internal only'
);
select ok(
  has_function_privilege('service_role','notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)','EXECUTE')
  and not has_function_privilege('public','notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)','EXECUTE')
  and not has_function_privilege('anon','notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)','EXECUTE')
  and not has_function_privilege('authenticated','notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)','EXECUTE'),
  'evaluator remains service-role-only'
);
select is(
  (select array_to_string(proconfig, ',') from pg_proc where oid='notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),
  'search_path=pg_catalog, notification, operations, app, extensions',
  'evaluator retains fixed search_path'
);
select is(
  (select count(*) from notification.notifications where organization_id='00000000-0000-4000-8000-000000000066'::uuid),
  0::bigint,
  'identity selection itself has no notification side effect'
);
select is(
  (select count(*) from notification.rule_runs where organization_id='00000000-0000-4000-8000-000000000066'::uuid),
  0::bigint,
  'identity selection itself has no rule-run side effect'
);
select is(
  (select count(*) from inventory.stock_ledger_entries where organization_id='00000000-0000-4000-8000-000000000066'::uuid),
  0::bigint,
  'rule identity handling is stock-neutral'
);
select is(
  (select count(*) from notification.rules where organization_id='00000000-0000-4000-8000-000000000066'::uuid and code='CLAIM_DEADLINE' and entity_type_code='CLAIM'),
  1::bigint,
  'legacy fixture is retained for audit rather than deleted'
);
select ok(
  (select prosecdef from pg_proc where oid='notification.require_tiktok_claim_deadline_rule(uuid,timestamp with time zone)'::regprocedure),
  'canonical selector is SECURITY DEFINER'
);
select is(
  (select array_to_string(proconfig, ',') from pg_proc where oid='notification.require_tiktok_claim_deadline_rule(uuid,timestamp with time zone)'::regprocedure),
  'search_path=pg_catalog, notification',
  'canonical selector has fixed search_path'
);
select is(
  (select count(*) from notification.rules where organization_id='00000000-0000-4000-8000-000000000066'::uuid and code='CLAIM_DEADLINE' and entity_type_code='RETURN_CLAIM' and config->'stages' = jsonb_build_array('D14','D7','D3','D1','DUE_TODAY','OVERDUE')),
  1::bigint,
  'canonical stage contract is complete'
);
select is(
  notification.ensure_tiktok_claim_rule('00000000-0000-4000-8000-000000000066','CLAIM_DEADLINE','2026-08-02 00:00:00+00'),
  (notification.require_tiktok_claim_deadline_rule('00000000-0000-4000-8000-000000000066','2026-08-02 00:00:00+00')).id,
  'ensure and evaluator resolve the same canonical rule'
);
select is(
  (select count(*) from notification.rules where organization_id='00000000-0000-4000-8000-000000000066'::uuid and code='CLAIM_DEADLINE' and entity_type_code='RETURN_CLAIM'),
  1::bigint,
  'repeated exact provisioning does not create a second canonical rule'
);
select is(
  (select count(*) from notification.notification_events where organization_id='00000000-0000-4000-8000-000000000066'::uuid),
  0::bigint,
  'identity replay does not create notification history'
);

select * from finish();
rollback;
