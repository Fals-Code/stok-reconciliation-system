begin;
create extension if not exists pgtap;
select plan(169);
select has_function('notification','ensure_tiktok_claim_rule',array['uuid','text','timestamp with time zone'],'claim rule provisioner exists');
select has_function('notification','request_tiktok_claim_deadline_evaluation',array['uuid','text','timestamp with time zone','text'],'outbox evaluation request exists');
select has_function('notification','evaluate_tiktok_claim_deadlines',array['uuid','text','timestamp with time zone','text'],'claim evaluator exists');
select ok(not has_function_privilege('anon','notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)','EXECUTE'),'anonymous users cannot invoke evaluator');
select ok(not has_function_privilege('authenticated','notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)','EXECUTE'),'authenticated cannot invoke internal evaluator');
select ok(has_function_privilege('service_role','notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)','EXECUTE'),'service role follows notification evaluator pattern');
select ok(not has_function_privilege('authenticated','notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)','EXECUTE'),'authenticated cannot provision internal rules');
select ok((select procedure.prosecdef from pg_proc procedure where procedure.oid='notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'evaluator is SECURITY DEFINER');
select ok((select procedure.prosecdef from pg_proc procedure where procedure.oid='notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'rule provisioner is SECURITY DEFINER');
select matches(coalesce((select array_to_string(procedure.proconfig,',') from pg_proc procedure where procedure.oid='notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),''),'^search_path=pg_catalog, notification, app$','rule provisioner has fixed search_path');
select matches(coalesce((select array_to_string(procedure.proconfig,',') from pg_proc procedure where procedure.oid='notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),''),'^search_path=pg_catalog, notification, operations, app, extensions$','evaluator has fixed search_path');
select matches(coalesce((select array_to_string(procedure.proconfig,',') from pg_proc procedure where procedure.oid='notification.request_tiktok_claim_deadline_evaluation(uuid,text,timestamp with time zone,text)'::regprocedure),''),'^search_path=pg_catalog, notification, app$','request RPC has fixed search_path');
select ok(exists(select 1 from pg_proc where oid='notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'evaluator signature is stable');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'CLAIM_DEADLINE','deadline rule is provisioned');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'CLAIM_BASIS_MISSING','basis-missing rule is provisioned');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'D14','D14 stage configured');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'D7','D7 stage configured');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'D3','D3 stage configured');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'D1','D1 stage configured');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'DUE_TODAY','due-today stage configured');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'OVERDUE','overdue stage configured');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'effective_from<=p_effective_at and \(effective_to is null or effective_to>p_effective_at\)','rule lookup uses the observed effective window');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'notification.rule_runs','evaluator links evaluation to existing rule runs');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'pg_advisory_xact_lock','evaluator serializes active episode updates');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'idempotency_key','duplicate evaluation is deduplicated');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'upsert_active_notification','one active episode is updated on escalation');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'resolve_notification','claim lifecycle resolves reminder episodes');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'SUBMITTED','submitted resolves deadline reminder');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'''RESOLVED''','resolved resolves deadline reminder');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'''CANCELLED''','cancelled resolves deadline and basis-missing reminders');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'''EXPIRED''','expired retains overdue policy');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'claim_basis_at is null','missing basis starts separate episode');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'CLAIM_BASIS_VALID','valid basis resolves basis-missing episode');
select matches(pg_get_functiondef('notification.request_tiktok_claim_deadline_evaluation(uuid,text,timestamp with time zone,text)'::regprocedure),'enqueue_outbox_event','existing outbox is used for evaluation requests');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'claimId=','safe claim deep-link contract is stored');
select matches(pg_get_functiondef('notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamp with time zone,text)'::regprocedure),'stockEffectCode','evaluator is explicitly stock-neutral');
select throws_ok($$select notification.ensure_tiktok_claim_rule(gen_random_uuid(),'OTHER',clock_timestamp())$$,'P0001','CLAIM_NOTIFICATION_RULE_INVALID','invalid rule family is rejected through trusted validation');

-- The evaluator chain must be isolated from durable UI-smoke data.  Keep its
-- identities deterministic, but create the complete operational prerequisite
-- through the same trusted APIs used by the lifecycle fixture below.
create temp table claim_notification_results(kind text primary key,result jsonb not null) on commit drop;
grant select,insert,update on claim_notification_results to authenticated;
create temp table evaluator_fixture(organization_id uuid primary key,admin_user_id uuid not null,second_admin_user_id uuid not null,product_id uuid,batch_id uuid) on commit drop;
grant select,update on evaluator_fixture to authenticated;
insert into app.organizations (id,code,name,timezone,is_active,created_at) values ('00000000-0000-4000-8000-000000000156','PGTAP_EVALUATOR_056','pgTAP Evaluator Fixture 056','Asia/Jakarta',true,'2026-06-01 00:00:00+07');
insert into auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous) values
  ('00000000-0000-0000-0000-000000000000','720d8ca5-3f95-4a20-8063-d24981ad5156','authenticated','authenticated','pgtap.evaluator.056.admin@glowlab.invalid','2026-06-01 00:00:00+07','{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,'2026-06-01 00:00:00+07','2026-06-01 00:00:00+07',false,false),
  ('00000000-0000-0000-0000-000000000000','95600000-0000-4000-8000-000000000156','authenticated','authenticated','pgtap.evaluator.056.second-admin@glowlab.invalid','2026-06-01 00:00:00+07','{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,'2026-06-01 00:00:00+07','2026-06-01 00:00:00+07',false,false);
insert into app.user_profiles(user_id,organization_id,display_name,employee_code,role_code,is_active) values
  ('720d8ca5-3f95-4a20-8063-d24981ad5156','00000000-0000-4000-8000-000000000156','pgTAP Evaluator Admin','PGTAP-EVAL-056-1','ADMIN',true),
  ('95600000-0000-4000-8000-000000000156','00000000-0000-4000-8000-000000000156','pgTAP Evaluator Second Admin','PGTAP-EVAL-056-2','ADMIN',true);
insert into evaluator_fixture(organization_id,admin_user_id,second_admin_user_id) values ('00000000-0000-4000-8000-000000000156','720d8ca5-3f95-4a20-8063-d24981ad5156','95600000-0000-4000-8000-000000000156');
select set_config('request.jwt.claim.sub',(select admin_user_id::text from evaluator_fixture),true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',(select admin_user_id::text from evaluator_fixture),'role','authenticated')::text,true);
set local role authenticated;
insert into claim_notification_results select 'FIXTURE_PRODUCT',api.create_product((select organization_id from evaluator_fixture),'056-EVALUATOR-PRODUCT','EVALUATOR 056','Evaluator fixture product','UNIT',null,'Evaluator fixture');
update evaluator_fixture set product_id=(select (result->>'productId')::uuid from claim_notification_results where kind='FIXTURE_PRODUCT');
insert into claim_notification_results select 'FIXTURE_BATCH',api.create_product_batch((select organization_id from evaluator_fixture),'056-EVALUATOR-BATCH',(select product_id from evaluator_fixture),'EVALUATOR LOT 056','2027-12-31','2026-06-01',null,'STANDARD','Evaluator fixture');
update evaluator_fixture set batch_id=(select (result->>'batchId')::uuid from claim_notification_results where kind='FIXTURE_BATCH');
insert into claim_notification_results select 'FIXTURE_RECEIPT',api.post_receipt((select organization_id from evaluator_fixture),'056-EVALUATOR-RECEIPT','RCV-EVALUATOR-056','2026-06-01 08:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select product_id from evaluator_fixture),'batchId',(select batch_id from evaluator_fixture),'quantity',10,'sourceLineRef','EVALUATOR-LINE-1')),'Evaluator fixture receipt.','{"fixture":"evaluator-056"}'::jsonb);
reset role;
select set_config('request.jwt.claim.sub',(select admin_user_id::text from evaluator_fixture),true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"720d8ca5-3f95-4a20-8063-d24981ad551d","role":"authenticated"}',true);
set local role authenticated;
insert into claim_notification_results select 'RESERVE',api.apply_marketplace_event((select organization_id from evaluator_fixture),'056-TT-RESERVE','TIKTOK_SHOP','RESERVE','056-TT-RESERVE-EVENT','056-TT-ORDER','2026-06-01 09:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select product_id from evaluator_fixture),'quantity',1,'sourceLineRef','056-TT-LINE')),'fixture','{}');
insert into claim_notification_results select 'SHIP',api.apply_marketplace_event((select organization_id from evaluator_fixture),'056-TT-SHIP','TIKTOK_SHOP','SHIP','056-TT-SHIP-EVENT','056-TT-ORDER','2026-06-02 09:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select product_id from evaluator_fixture),'quantity',1,'sourceLineRef','056-TT-LINE')),'fixture','{}');
insert into claim_notification_results select 'EXPECTED',api.create_expected_return((select organization_id from evaluator_fixture),'056-TT-EXPECTED','TIKTOK_SHOP','056-TT-RETURN','056-TT-ORDER','2026-06-03 10:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select product_id from evaluator_fixture),'quantity',1,'sourceLineRef','056-TT-LINE')),'RETURN_REQUESTED','fixture','{}');
insert into claim_notification_results select 'RETURN',jsonb_build_object('returnId',(select id from operations.returns where external_return_ref='056-TT-RETURN'));
insert into claim_notification_results select 'RETURN_ITEM',jsonb_build_object('returnItemId',(select item.id from operations.return_items item join operations.returns header on header.id=item.return_id where header.external_return_ref='056-TT-RETURN'));
insert into claim_notification_results select 'LOST',api.mark_return_lost((select organization_id from evaluator_fixture),'056-TT-LOST','056-TT-RETURN','056-TT-LOST-EVENT','2026-06-04 11:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select item.id::text from operations.return_items item join operations.returns header on header.id=item.return_id where header.external_return_ref='056-TT-RETURN'),'quantity',1,'sourceLineRef','056-TT-LOST-LINE')),'fixture','{}');
insert into claim_notification_results select 'CLAIM',api.create_tiktok_return_claim((select organization_id from evaluator_fixture),'056-TT-CLAIM',(select id from operations.returns where external_return_ref='056-TT-RETURN'),'LOST_RETURN',jsonb_build_array(jsonb_build_object('returnItemId',(select item.id::text from operations.return_items item join operations.returns header on header.id=item.return_id where header.external_return_ref='056-TT-RETURN'),'quantity',1)),'2026-06-20 10:00:00+07');
reset role;
select is((select count(*) from notification.outbox_events where organization_id=(select organization_id from evaluator_fixture)::uuid and entity_type_code='RETURN_CLAIM' and entity_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') and event_type_code='TIKTOK_CLAIM_DEADLINE_EVALUATION_REQUEST'),1::bigint,'trusted claim creation writes one claim-linked deadline-evaluation outbox request');
select ok(exists(select 1 from notification.outbox_events where organization_id=(select organization_id from evaluator_fixture)::uuid and entity_type_code='RETURN_CLAIM' and entity_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') and payload->>'claimId'=(select result->>'claimId' from claim_notification_results where kind='CLAIM')),'claim outbox payload remains traceable to the claim');
select is((select count(*) from notification.outbox_events where organization_id=(select organization_id from evaluator_fixture)::uuid and entity_type_code='RETURN_CLAIM' and entity_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') and event_type_code='TIKTOK_CLAIM_DEADLINE_EVALUATION_REQUEST'),1::bigint,'claim creation effect has one durable outbox record before evaluator execution');
select set_config('request.jwt.claim.sub',(select admin_user_id::text from evaluator_fixture),true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"720d8ca5-3f95-4a20-8063-d24981ad551d","role":"authenticated"}',true);
set local role authenticated;
insert into claim_notification_results select 'CLAIM_REPLAY',api.create_tiktok_return_claim((select organization_id from evaluator_fixture),'056-TT-CLAIM',(select (result->>'returnId')::uuid from claim_notification_results where kind='RETURN'),'LOST_RETURN',jsonb_build_array(jsonb_build_object('returnItemId',(select result->>'returnItemId' from claim_notification_results where kind='RETURN_ITEM'),'quantity',1)),'2026-06-20 10:00:00+07');
reset role;
select is((select result->>'claimId' from claim_notification_results where kind='CLAIM_REPLAY'),(select result->>'claimId' from claim_notification_results where kind='CLAIM'),'identical create replay returns the original claim');
select is((select count(*) from notification.outbox_events where organization_id=(select organization_id from evaluator_fixture)::uuid and entity_type_code='RETURN_CLAIM' and entity_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') and event_type_code='TIKTOK_CLAIM_DEADLINE_EVALUATION_REQUEST'),1::bigint,'identical create replay does not duplicate the claim outbox request');
create temp table evaluator_stock_before as select (select count(*) from inventory.stock_transactions)::bigint transaction_count,(select count(*) from inventory.stock_ledger_entries)::bigint ledger_count;
insert into claim_notification_results select 'BEFORE_D14',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-before',(select deadline_at-interval '14 days 1 microsecond' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'pgtap.056');
select is((select count(*) from notification.notifications where entity_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') and rule_code_snapshot='CLAIM_DEADLINE' and lifecycle_status_code in ('OPEN','ACKNOWLEDGED')),0::bigint,'before D14 no active deadline episode exists');
insert into claim_notification_results select 'D14',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-d14',(select deadline_at-interval '14 days' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'pgtap.056');
create temp table evaluator_episode as select id from notification.notifications where entity_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') and rule_code_snapshot='CLAIM_DEADLINE';
insert into claim_notification_results values ('EPISODE',jsonb_build_object('notificationId',(select id from evaluator_episode)));
select is((select stage_code from notification.notifications where id=(select id from evaluator_episode)),'D14','exact D14 creates D14 stage');
select is((select action_route from notification.notifications where id=(select id from evaluator_episode)),'/returns?returnId='||(select return_id from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM'))||'&claimId='||(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')||'#claim-detail','deadline notification route carries exact return and claim context');

-- A second real Admin exercises the public per-user notification API.  This is
-- fixture identity data only; notification and claim state are still changed
-- exclusively through trusted commands.
-- The public wrapper intentionally uses clock_timestamp().  The deterministic
-- evaluator has created a historical D14 episode, so call the same trusted
-- internal command with a deterministic changed-at timestamp.
select lives_ok($$select notification.set_notification_read_state((select organization_id from evaluator_fixture),(select (result->>'notificationId')::uuid from claim_notification_results where kind='EPISODE'),(select admin_user_id from evaluator_fixture),'READ',(select deadline_at-interval '14 days'+interval '1 microsecond' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')))$$,'Admin A marks the deterministic D14 notification read through the trusted state command');
select lives_ok($$select notification.set_notification_read_state((select organization_id from evaluator_fixture),(select (result->>'notificationId')::uuid from claim_notification_results where kind='EPISODE'),(select second_admin_user_id from evaluator_fixture),'READ',(select deadline_at-interval '14 days'+interval '1 microsecond' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')))$$,'Admin B marks the same deterministic D14 notification read through the trusted state command');
select is((select count(*) from notification.user_states where notification_id=(select id from evaluator_episode)),2::bigint,'read state is stored once per active Admin');
select is((select count(*) from notification.user_states where notification_id=(select id from evaluator_episode) and read_state_code='READ'),2::bigint,'both Admin read states are READ before escalation');
select is((select lifecycle_status_code from notification.notifications where id=(select id from evaluator_episode)),'OPEN','marking read does not resolve the notification');
select is((select status_code from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'NOT_STARTED','marking read does not mutate claim lifecycle');
insert into claim_notification_results select 'D7',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-d7',(select deadline_at-interval '7 days' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'pgtap.056');
select is((select stage_code from notification.notifications where id=(select id from evaluator_episode)),'D7','D7 updates same active episode');
select is((select count(*) from notification.notifications where entity_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') and rule_code_snapshot='CLAIM_DEADLINE'),1::bigint,'escalation does not create a second episode');
select ok((select count(*) from notification.notification_events where notification_id=(select id from evaluator_episode) and event_type_code='STAGE_ESCALATED')>=1,'stage escalation appends notification history');
select is((select count(*) from notification.user_states where notification_id=(select id from evaluator_episode) and read_state_code='UNREAD'),2::bigint,'D7 escalation resets both Admin states to UNREAD on the same episode');
select is((select count(*) from notification.user_states where notification_id=(select id from evaluator_episode)),2::bigint,'D7 escalation does not duplicate user-state rows');
select ok(exists(select 1 from notification.notification_events where notification_id=(select id from evaluator_episode) and event_type_code='READ_STATE_RESET_BY_ESCALATION'),'read-state reset is recorded append-only');
select is((select status_code from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'NOT_STARTED','escalation does not mutate claim lifecycle');
insert into claim_notification_results select 'D3',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-d3',(select deadline_at-interval '3 days' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'pgtap.056');
select is((select stage_code from notification.notifications where id=(select id from evaluator_episode)),'D3','D3 preserves active episode identity');
insert into claim_notification_results select 'D1',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-d1',(select deadline_at-interval '1 day' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'pgtap.056');
select is((select stage_code from notification.notifications where id=(select id from evaluator_episode)),'D1','D1 preserves active episode identity');
insert into claim_notification_results select 'DUE',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-due',(select deadline_at from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'pgtap.056');
select is((select stage_code from notification.notifications where id=(select id from evaluator_episode)),'DUE_TODAY','exact deadline follows DUE_TODAY boundary');
insert into claim_notification_results select 'OVERDUE',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-overdue',(select deadline_at+interval '1 microsecond' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'pgtap.056');
select is((select stage_code from notification.notifications where id=(select id from evaluator_episode)),'OVERDUE','after exact deadline updates same episode to overdue');
select is((select count(*) from inventory.stock_transactions),(select transaction_count from evaluator_stock_before),'threshold evaluator is stock-transaction neutral');
select is((select count(*) from inventory.stock_ledger_entries),(select ledger_count from evaluator_stock_before),'threshold evaluator is ledger neutral');
select ok(exists(select 1 from notification.rule_runs where organization_id=(select organization_id from evaluator_fixture)::uuid and rule_code_snapshot='CLAIM_DEADLINE' and idempotency_key='056-overdue' and status_code='SUCCEEDED'),'evaluator records successful rule run');
select is((select count(*) from notification.rule_runs where organization_id=(select organization_id from evaluator_fixture)::uuid and rule_code_snapshot='CLAIM_DEADLINE' and idempotency_key='056-overdue'),1::bigint,'one durable rule run is stored for an evaluator run key');
create temp table overdue_replay_before as select count(*)::bigint event_count from notification.notification_events where notification_id=(select id from evaluator_episode);
insert into claim_notification_results select 'OVERDUE_REPLAY',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-overdue',(select deadline_at+interval '1 microsecond' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'pgtap.056');
select is((select result->>'action' from claim_notification_results where kind='OVERDUE_REPLAY'),'REPLAYED','repeating an evaluator run key is idempotently replayed');
select is((select count(*) from notification.rule_runs where organization_id=(select organization_id from evaluator_fixture)::uuid and rule_code_snapshot='CLAIM_DEADLINE' and idempotency_key='056-overdue'),1::bigint,'rule-run replay does not create a second run');
select is((select count(*) from notification.notification_events where notification_id=(select id from evaluator_episode)),(select event_count from overdue_replay_before),'replay leaves notification event history stable');

select ok(not has_function_privilege('public','notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)','EXECUTE'),'PUBLIC cannot provision internal rules');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'organization_id=p_organization_id','rule lookup remains organization-scoped');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'code=p_code','rule lookup remains rule-family-scoped');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'is_active','rule lookup excludes inactive versions');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'effective_from<=p_effective_at','future-dated rules are excluded and the effective-from boundary is inclusive');
select matches(pg_get_functiondef('notification.ensure_tiktok_claim_rule(uuid,text,timestamp with time zone)'::regprocedure),'effective_to>p_effective_at','expired rules are excluded and the effective-to boundary is exclusive');

-- This schema-owner fixture represents a historical/imported corrupt claim:
-- it keeps the real return and product-linked claim item, but has only the
-- legacy missing basis/deadline fields.  RLS remains enabled and no grant or
-- production helper is introduced.
create temp table basis_missing_fixture(id uuid primary key,product_id uuid not null) on commit drop;
insert into inventory.idempotency_commands(id,organization_id,scope,key,request_hash,status_code,completed_at,response_snapshot)
values (gen_random_uuid(),(select organization_id from evaluator_fixture),'LEGACY_IMPORTED_TIKTOK_RETURN_CLAIM','056-basis-missing-fixture',repeat('0',64),'SUCCEEDED',clock_timestamp(),'{}');
with claim as (
  insert into operations.return_claims(id,organization_id,return_id,claim_type_code,claim_basis_code,claim_basis_at,window_days_snapshot,timezone_snapshot,deadline_source_code,deadline_at,policy_version_snapshot,created_at,process_name,idempotency_command_id,request_hash)
  select gen_random_uuid(),existing.organization_id,existing.return_id,'LOST_RETURN','RETURN_CREATED_AT',null,40,'Asia/Jakarta','INTERNAL_RETURN_CREATED_AT',null,'TIKTOK_RETURN_CREATED_AT_V1','2026-06-04 11:00:00+07','pgtap.056.legacy_fixture',command.id,repeat('0',64)
  from operations.return_claims existing
  cross join lateral (select id from inventory.idempotency_commands where organization_id=existing.organization_id and scope='LEGACY_IMPORTED_TIKTOK_RETURN_CLAIM' and key='056-basis-missing-fixture') command
  where existing.id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')
  returning id
)
insert into basis_missing_fixture(id,product_id)
select claim.id,item.product_id
from claim
cross join lateral (
  select product_id from operations.return_claim_items where claim_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') order by id limit 1
) item;
insert into operations.return_claim_items(organization_id,claim_id,return_item_id,quantity,eligible_lost_qty_snapshot,product_id,product_sku_snapshot,source_line_ref_snapshot,canonical_components_snapshot)
select item.organization_id,fixture.id,item.return_item_id,item.quantity,item.eligible_lost_qty_snapshot,item.product_id,item.product_sku_snapshot,item.source_line_ref_snapshot,item.canonical_components_snapshot
from operations.return_claim_items item cross join basis_missing_fixture fixture
where item.claim_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM');
insert into claim_notification_results values ('BASIS_FIXTURE',jsonb_build_object('claimId',(select id from basis_missing_fixture)));
select ok(exists(select 1 from operations.return_claims claim join basis_missing_fixture fixture on fixture.id=claim.id join operations.returns returned on returned.id=claim.return_id and returned.organization_id=claim.organization_id where claim.claim_basis_at is null and claim.deadline_at is null),'legacy fixture remains related to a real return');
select ok(exists(select 1 from operations.return_claim_items item join basis_missing_fixture fixture on fixture.id=item.claim_id),'legacy fixture remains related to a real product item');
create temp table basis_missing_stock_before as
select jsonb_build_object(
  'transactions',(select count(*) from inventory.stock_transactions),
  'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),
  'productLedgerQuantity',(select coalesce(sum(quantity_delta),0) from inventory.stock_ledger_entries where product_id=(select product_id from basis_missing_fixture)),
  'batchLedgerQuantity',(select coalesce(sum(quantity_delta),0) from inventory.stock_ledger_entries where batch_id=(select batch_id from inventory.stock_ledger_entries where product_id=(select product_id from basis_missing_fixture) order by ledger_seq limit 1)),
  'reservationQuantity',(select coalesce(sum(reserved_qty),0) from inventory.stock_reservations where product_id=(select product_id from basis_missing_fixture)),
  'productProjection',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position where position.product_id=(select product_id from basis_missing_fixture)),
  'batchProjection',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance where balance.product_id=(select product_id from basis_missing_fixture))
) snapshot;
insert into claim_notification_results select 'BASIS_MISSING_INITIAL',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-basis-missing-initial','2026-07-01 10:00:00+07','pgtap.056');
create temp table basis_missing_episode as select id from notification.notifications where entity_id=(select id from basis_missing_fixture) and rule_code_snapshot='CLAIM_BASIS_MISSING';
create temp table basis_missing_events_before_replay as select count(*)::bigint event_count from notification.notification_events where notification_id=(select id from basis_missing_episode);
select is((select result->>'action' from claim_notification_results where kind='BASIS_MISSING_INITIAL'),'COMPLETED','basis-missing evaluator run completes without NOTIFICATION_RULE_NOT_FOUND');
select is((select count(*) from basis_missing_episode),1::bigint,'exactly one CLAIM_BASIS_MISSING episode is created');
select is((select severity_code from notification.notifications where id=(select id from basis_missing_episode)),'HIGH','basis-missing episode is HIGH severity');
select is((select entity_type_code from notification.notifications where id=(select id from basis_missing_episode)),'RETURN_CLAIM','basis-missing episode identifies a return claim');
select is((select entity_id from notification.notifications where id=(select id from basis_missing_episode)),(select id from basis_missing_fixture),'basis-missing episode identifies the fixture claim');
select is((select action_code from notification.notifications where id=(select id from basis_missing_episode)),'OPEN_RETURN_CLAIM_DETAIL','basis-missing action code follows the rule contract');
select is((select action_route from notification.notifications where id=(select id from basis_missing_episode)),'/returns?returnId='||(select return_id from operations.return_claims where id=(select id from basis_missing_fixture))||'&claimId='||(select id from basis_missing_fixture)||'#claim-detail','basis-missing deep link follows the exact claim contract');
select isnt((select deduplication_key from notification.notifications where id=(select id from basis_missing_episode)),(select deduplication_key from notification.notifications where id=(select id from evaluator_episode)),'basis-missing and deadline deduplication keys are separate');
select is((select count(*) from notification.notifications where entity_id=(select id from basis_missing_fixture) and rule_code_snapshot='CLAIM_DEADLINE' and lifecycle_status_code in ('OPEN','ACKNOWLEDGED')),0::bigint,'deadline rule is inactive for a claim without a basis');
select is((select jsonb_build_object(
  'transactions',(select count(*) from inventory.stock_transactions),'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),
  'productLedgerQuantity',(select coalesce(sum(quantity_delta),0) from inventory.stock_ledger_entries where product_id=(select product_id from basis_missing_fixture)),
  'batchLedgerQuantity',(select coalesce(sum(quantity_delta),0) from inventory.stock_ledger_entries where batch_id=(select batch_id from inventory.stock_ledger_entries where product_id=(select product_id from basis_missing_fixture) order by ledger_seq limit 1)),
  'reservationQuantity',(select coalesce(sum(reserved_qty),0) from inventory.stock_reservations where product_id=(select product_id from basis_missing_fixture)),
  'productProjection',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position where position.product_id=(select product_id from basis_missing_fixture)),
  'batchProjection',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance where balance.product_id=(select product_id from basis_missing_fixture))
)),(select snapshot from basis_missing_stock_before),'initial basis-missing evaluation is stock-neutral');
insert into claim_notification_results select 'BASIS_MISSING_REPLAY',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-basis-missing-initial','2026-07-01 10:00:00+07','pgtap.056');
select is((select result->>'action' from claim_notification_results where kind='BASIS_MISSING_REPLAY'),'REPLAYED','basis-missing replay is REPLAYED');
select is((select count(*) from notification.notifications where entity_id=(select id from basis_missing_fixture) and rule_code_snapshot='CLAIM_BASIS_MISSING'),1::bigint,'basis-missing replay does not duplicate the notification');
select is((select count(*) from notification.notification_events where notification_id=(select id from basis_missing_episode)),(select event_count from basis_missing_events_before_replay),'basis-missing replay does not duplicate events');
select is((select jsonb_build_object('transactions',(select count(*) from inventory.stock_transactions),'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),'productLedgerQuantity',(select coalesce(sum(quantity_delta),0) from inventory.stock_ledger_entries where product_id=(select product_id from basis_missing_fixture)),'batchLedgerQuantity',(select coalesce(sum(quantity_delta),0) from inventory.stock_ledger_entries where batch_id=(select batch_id from inventory.stock_ledger_entries where product_id=(select product_id from basis_missing_fixture) order by ledger_seq limit 1)),'reservationQuantity',(select coalesce(sum(reserved_qty),0) from inventory.stock_reservations where product_id=(select product_id from basis_missing_fixture)),'productProjection',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position where position.product_id=(select product_id from basis_missing_fixture)),'batchProjection',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance where balance.product_id=(select product_id from basis_missing_fixture)))),(select snapshot from basis_missing_stock_before),'basis-missing replay is stock-neutral');
select set_config('request.jwt.claim.sub',(select admin_user_id::text from evaluator_fixture),true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"720d8ca5-3f95-4a20-8063-d24981ad551d","role":"authenticated"}',true);
set local role authenticated;
insert into claim_notification_results select 'BASIS_MISSING_CANCEL',api.cancel_tiktok_return_claim((select organization_id from evaluator_fixture),'056-basis-missing-cancel',(select (result->>'claimId')::uuid from claim_notification_results where kind='BASIS_FIXTURE'),'legacy fixture terminal resolution','2026-07-02 10:00:00+07');
reset role;
insert into claim_notification_results select 'BASIS_MISSING_RESOLUTION',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-basis-missing-resolution','2026-07-02 10:00:00+07','pgtap.056');
select is((select result->>'status' from claim_notification_results where kind='BASIS_MISSING_CANCEL'),'CANCELLED','fixture is cancelled through the existing trusted transition');
select is((select lifecycle_status_code from notification.notifications where id=(select id from basis_missing_episode)),'RESOLVED','CANCELLED resolves the basis-missing episode');
select is((select count(*) from notification.notifications where entity_id=(select id from basis_missing_fixture) and rule_code_snapshot='CLAIM_BASIS_MISSING' and lifecycle_status_code in ('OPEN','ACKNOWLEDGED')),0::bigint,'resolution creates no active basis-missing duplicate');
select ok((select count(*) from notification.notification_events where notification_id=(select id from basis_missing_episode))>(select event_count from basis_missing_events_before_replay),'resolution appends history without deleting it');
select is((select jsonb_build_object('transactions',(select count(*) from inventory.stock_transactions),'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),'productLedgerQuantity',(select coalesce(sum(quantity_delta),0) from inventory.stock_ledger_entries where product_id=(select product_id from basis_missing_fixture)),'batchLedgerQuantity',(select coalesce(sum(quantity_delta),0) from inventory.stock_ledger_entries where batch_id=(select batch_id from inventory.stock_ledger_entries where product_id=(select product_id from basis_missing_fixture) order by ledger_seq limit 1)),'reservationQuantity',(select coalesce(sum(reserved_qty),0) from inventory.stock_reservations where product_id=(select product_id from basis_missing_fixture)),'productProjection',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position where position.product_id=(select product_id from basis_missing_fixture)),'batchProjection',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance where balance.product_id=(select product_id from basis_missing_fixture)))),(select snapshot from basis_missing_stock_before),'basis-missing resolution is stock-neutral');
select isnt((select rule_id from notification.notifications where id=(select id from basis_missing_episode)),(select rule_id from notification.notifications where id=(select id from evaluator_episode)),'CLAIM_BASIS_MISSING and CLAIM_DEADLINE use separate rule families');
select is((select count(*) from notification.notifications where id=(select id from basis_missing_episode) and organization_id<>(select organization_id from evaluator_fixture)::uuid),0::bigint,'no foreign organization owns the basis-missing episode');

create temp table lifecycle_stock_before as select jsonb_build_object(
  'transactions',(select count(*) from inventory.stock_transactions),
  'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),
  'ledgerByProduct',(select coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'quantity',quantity) order by product_id),'[]'::jsonb) from (select product_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by product_id) product_ledger),
  'ledgerByBatch',(select coalesce(jsonb_agg(jsonb_build_object('batchId',batch_id,'quantity',quantity) order by batch_id),'[]'::jsonb) from (select batch_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by batch_id) batch_ledger),
  'reservations',(select coalesce(jsonb_agg(to_jsonb(reservation) order by reservation.id),'[]'::jsonb) from inventory.stock_reservations reservation),
  'productPositions',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position),
  'batchPositions',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance)
) snapshot;
insert into claim_notification_results values ('CLAIM_CONTEXT',jsonb_build_object('claimId',(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM'),'deadlineAt',(select deadline_at from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM'))));
select set_config('request.jwt.claim.sub',(select admin_user_id::text from evaluator_fixture),true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"720d8ca5-3f95-4a20-8063-d24981ad551d","role":"authenticated"}',true);
set local role authenticated;
insert into claim_notification_results select 'EXPIRE',api.evaluate_tiktok_return_claim_deadline((select organization_id from evaluator_fixture),'056-expire',(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM_CONTEXT'),(select (result->>'deadlineAt')::timestamptz+interval '1 microsecond' from claim_notification_results where kind='CLAIM_CONTEXT'));
reset role;
insert into claim_notification_results select 'EXPIRE_EVALUATION',notification.evaluate_tiktok_claim_deadlines((select organization_id from evaluator_fixture),'056-expire-evaluation',(select deadline_at+interval '2 microseconds' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'pgtap.056');
select is((select result->>'status' from claim_notification_results where kind='EXPIRE'),'EXPIRED','trusted deadline transition marks the claim EXPIRED');
select is((select lifecycle_status_code from notification.notifications where id=(select id from evaluator_episode)),'OPEN','EXPIRED claim keeps its deadline notification active');
select is((select stage_code from notification.notifications where id=(select id from evaluator_episode)),'OVERDUE','EXPIRED claim keeps the overdue stage');
select is((select count(*) from notification.notifications where entity_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') and rule_code_snapshot='CLAIM_DEADLINE'),1::bigint,'EXPIRED evaluation preserves notification identity');
select is((select count(*) from operations.return_claim_events where claim_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') and event_type_code='EXPIRED'),1::bigint,'EXPIRED transition appends one claim event');
select lives_ok($$select notification.set_notification_read_state((select organization_id from evaluator_fixture),(select id from evaluator_episode),(select admin_user_id from evaluator_fixture),'READ',(select deadline_at+interval '3 microseconds' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')))$$,'Admin A can read an overdue notification');
select lives_ok($$select notification.set_notification_read_state((select organization_id from evaluator_fixture),(select id from evaluator_episode),(select second_admin_user_id from evaluator_fixture),'READ',(select deadline_at+interval '3 microseconds' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')))$$,'Admin B can independently read an overdue notification');
select lives_ok($$select notification.set_notification_read_state((select organization_id from evaluator_fixture),(select id from evaluator_episode),(select admin_user_id from evaluator_fixture),'ARCHIVED_FOR_USER',(select deadline_at+interval '4 microseconds' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')))$$,'Admin A can archive only their presentation state');
select is((select read_state_code from notification.user_states where notification_id=(select id from evaluator_episode) and user_id=(select admin_user_id from evaluator_fixture)),'ARCHIVED','Admin A archive is stored per user');
select is((select read_state_code from notification.user_states where notification_id=(select id from evaluator_episode) and user_id=(select second_admin_user_id from evaluator_fixture)),'READ','Admin B state is unaffected by Admin A archive');
select is((select count(*) from notification.user_states where notification_id=(select id from evaluator_episode) and user_id in ((select admin_user_id from evaluator_fixture),(select second_admin_user_id from evaluator_fixture))),2::bigint,'two Admin actions do not duplicate user-state rows');
select lives_ok($$select notification.acknowledge_notification((select organization_id from evaluator_fixture),(select id from evaluator_episode),(select deadline_at+interval '5 microseconds' from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),gen_random_uuid(),(select admin_user_id from evaluator_fixture),'critical overdue acknowledged')$$,'ACKNOWLEDGE follows the existing critical-note contract');
select is((select lifecycle_status_code from notification.notifications where id=(select id from evaluator_episode)),'ACKNOWLEDGED','ACKNOWLEDGE changes notification lifecycle only');
select is((select status_code from operations.return_claims where id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM')),'EXPIRED','READ ARCHIVE and ACKNOWLEDGE do not mutate EXPIRED claim');
select is((select count(*) from operations.return_claim_events where claim_id=(select (result->>'claimId')::uuid from claim_notification_results where kind='CLAIM') and event_type_code='EXPIRED'),1::bigint,'notification actions do not append claim events');
-- The original claim/episode is intentionally retained only for EXPIRED and
-- user-action coverage.  Lifecycle-resolution fixtures must use fresh claims.

-- Fresh OPEN lifecycle fixture: all marketplace and claim commands use a
-- separate order/return/claim and never reuse evaluator_episode.
select set_config('request.jwt.claim.sub',(select admin_user_id::text from evaluator_fixture),true); select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claims','{"sub":"720d8ca5-3f95-4a20-8063-d24981ad551d","role":"authenticated"}',true); set local role authenticated;
create temp table fresh_timeline as select coalesce(max(last_seen_at),'2026-07-01 00:00:00+07'::timestamptz) max_last_seen_at from notification.notifications where organization_id=(select organization_id from evaluator_fixture)::uuid;
insert into claim_notification_results select 'FRESH_RESERVE',api.apply_marketplace_event((select organization_id from evaluator_fixture),'056-FRESH-RESERVE','TIKTOK_SHOP','RESERVE','056-FRESH-RESERVE-EVENT','056-FRESH-ORDER',(select max_last_seen_at-interval '27 days' from fresh_timeline),jsonb_build_array(jsonb_build_object('productId',(select product_id from evaluator_fixture),'quantity',1,'sourceLineRef','056-FRESH-LINE')),'fixture','{}');
insert into claim_notification_results select 'FRESH_SHIP',api.apply_marketplace_event((select organization_id from evaluator_fixture),'056-FRESH-SHIP','TIKTOK_SHOP','SHIP','056-FRESH-SHIP-EVENT','056-FRESH-ORDER',(select max_last_seen_at-interval '26 days' from fresh_timeline),jsonb_build_array(jsonb_build_object('productId',(select product_id from evaluator_fixture),'quantity',1,'sourceLineRef','056-FRESH-LINE')),'fixture','{}');
insert into claim_notification_results select 'FRESH_EXPECTED',api.create_expected_return((select organization_id from evaluator_fixture),'056-FRESH-EXPECTED','TIKTOK_SHOP','056-FRESH-RETURN','056-FRESH-ORDER',(select max_last_seen_at-interval '25 days' from fresh_timeline),jsonb_build_array(jsonb_build_object('productId',(select product_id from evaluator_fixture),'quantity',1,'sourceLineRef','056-FRESH-LINE')),'RETURN_REQUESTED','fixture','{}');
insert into claim_notification_results select 'FRESH_LOST',api.mark_return_lost((select organization_id from evaluator_fixture),'056-FRESH-LOST','056-FRESH-RETURN','056-FRESH-LOST-EVENT',(select max_last_seen_at-interval '24 days' from fresh_timeline),jsonb_build_array(jsonb_build_object('returnItemId',(select id::text from operations.return_items where return_id=(select id from operations.returns where external_return_ref='056-FRESH-RETURN')),'quantity',1,'sourceLineRef','056-FRESH-LINE')),'fixture','{}');
insert into claim_notification_results select 'FRESH_CLAIM',api.create_tiktok_return_claim((select organization_id from evaluator_fixture),'056-FRESH-CLAIM',(select id from operations.returns where external_return_ref='056-FRESH-RETURN'),'LOST_RETURN',jsonb_build_array(jsonb_build_object('returnItemId',(select id::text from operations.return_items where return_id=(select id from operations.returns where external_return_ref='056-FRESH-RETURN')),'quantity',1)),'2026-06-20 10:00:00+07'); reset role;

insert into app.organizations (id,code,name,timezone,is_active,created_at) values ('00000000-0000-4000-8000-000000000056','PGTAP_LIFECYCLE_056','pgTAP Lifecycle Bootstrap 056','Asia/Jakarta',true,'2026-07-23 08:00:00+07');
insert into auth.users (instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous) values ('00000000-0000-0000-0000-000000000000','95600000-0000-4000-8000-000000000056','authenticated','authenticated','pgtap.lifecycle.056@glowlab.invalid','2026-07-23 08:00:00+07','{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,'2026-07-23 08:00:00+07','2026-07-23 08:00:00+07',false,false);
insert into app.user_profiles (user_id,organization_id,display_name,employee_code,role_code,is_active) values ('95600000-0000-4000-8000-000000000056','00000000-0000-4000-8000-000000000056','pgTAP Lifecycle Admin','PGTAP-LIFECYCLE-056','ADMIN',true);
select set_config('request.jwt.claim.sub','95600000-0000-4000-8000-000000000056',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims',jsonb_build_object('sub','95600000-0000-4000-8000-000000000056','role','authenticated','email','pgtap.lifecycle.056@glowlab.invalid')::text,true);
create temp table lifecycle_fixture_results (kind text primary key,result jsonb not null) on commit drop;
grant select, insert, update on lifecycle_fixture_results to authenticated;
set local role authenticated;
insert into lifecycle_fixture_results select 'PRODUCT',api.create_product('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-PRODUCT','LIFECYCLE 056','Lifecycle Bootstrap Product','UNIT',null,'Lifecycle bootstrap fixture');
insert into lifecycle_fixture_results select 'BATCH',api.create_product_batch('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-BATCH',(select (result->>'productId')::uuid from lifecycle_fixture_results where kind='PRODUCT'),'LIFECYCLE LOT 056','2027-12-31','2026-07-23',null,'STANDARD','Lifecycle bootstrap fixture');
insert into lifecycle_fixture_results select 'RECEIPT',api.post_receipt('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-RECEIPT','RCV-LIFECYCLE-056','2026-07-23 09:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select result->>'productId' from lifecycle_fixture_results where kind='PRODUCT'),'batchId',(select result->>'batchId' from lifecycle_fixture_results where kind='BATCH'),'quantity',10,'sourceLineRef','LIFECYCLE-LINE-1')),'Lifecycle bootstrap receipt.','{"fixture":"lifecycle-056"}'::jsonb);
select is(app.current_organization_id(),'00000000-0000-4000-8000-000000000056'::uuid,'lifecycle bootstrap JWT resolves the fixture organization');
select is((select organization_id from catalog.products where id=(select (result->>'productId')::uuid from lifecycle_fixture_results where kind='PRODUCT')),'00000000-0000-4000-8000-000000000056'::uuid,'lifecycle bootstrap product belongs to the fixture organization');
select ok((select organization_id='00000000-0000-4000-8000-000000000056'::uuid and product_id=(select (result->>'productId')::uuid from lifecycle_fixture_results where kind='PRODUCT') from catalog.product_batches where id=(select (result->>'batchId')::uuid from lifecycle_fixture_results where kind='BATCH')),'lifecycle bootstrap batch belongs to the fixture product and organization');
select ok((select nullif(result->>'transactionId','') is not null from lifecycle_fixture_results where kind='RECEIPT'),'lifecycle bootstrap receipt returns a transactionId');
select is((select count(*) from inventory.stock_transactions where id=(select (result->>'transactionId')::uuid from lifecycle_fixture_results where kind='RECEIPT')),1::bigint,'lifecycle bootstrap receipt creates one stock transaction');
select is((select count(*) from inventory.stock_ledger_entries where transaction_id=(select (result->>'transactionId')::uuid from lifecycle_fixture_results where kind='RECEIPT')),1::bigint,'lifecycle bootstrap receipt creates one ledger entry');
select is((select coalesce(sum(quantity_delta),0)::bigint from inventory.stock_ledger_entries where transaction_id=(select (result->>'transactionId')::uuid from lifecycle_fixture_results where kind='RECEIPT') and product_id=(select (result->>'productId')::uuid from lifecycle_fixture_results where kind='PRODUCT')),10::bigint,'lifecycle bootstrap ledger product quantity is 10');
select is((select coalesce(sum(quantity_delta),0)::bigint from inventory.stock_ledger_entries where transaction_id=(select (result->>'transactionId')::uuid from lifecycle_fixture_results where kind='RECEIPT') and batch_id=(select (result->>'batchId')::uuid from lifecycle_fixture_results where kind='BATCH')),10::bigint,'lifecycle bootstrap ledger batch quantity is 10');
reset role;

set local role authenticated;
insert into lifecycle_fixture_results select 'LIFECYCLE_A_RESERVE',api.apply_marketplace_event('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-A-RESERVE','TIKTOK_SHOP','RESERVE','056-LIFECYCLE-A-RESERVE-EVENT','056-LIFECYCLE-A-ORDER','2026-06-01 09:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select result->>'productId' from lifecycle_fixture_results where kind='PRODUCT'),'quantity',1,'sourceLineRef','056-LIFECYCLE-A-LINE')),'fixture','{}');
insert into lifecycle_fixture_results select 'LIFECYCLE_A_SHIP',api.apply_marketplace_event('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-A-SHIP','TIKTOK_SHOP','SHIP','056-LIFECYCLE-A-SHIP-EVENT','056-LIFECYCLE-A-ORDER','2026-06-02 09:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select result->>'productId' from lifecycle_fixture_results where kind='PRODUCT'),'quantity',1,'sourceLineRef','056-LIFECYCLE-A-LINE')),'fixture','{}');
insert into lifecycle_fixture_results select 'LIFECYCLE_A_EXPECTED',api.create_expected_return('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-A-EXPECTED','TIKTOK_SHOP','056-LIFECYCLE-A-RETURN','056-LIFECYCLE-A-ORDER','2026-06-03 10:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select result->>'productId' from lifecycle_fixture_results where kind='PRODUCT'),'quantity',1,'sourceLineRef','056-LIFECYCLE-A-LINE')),'RETURN_REQUESTED','fixture','{}');
insert into lifecycle_fixture_results select 'LIFECYCLE_A_LOST',api.mark_return_lost('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-A-LOST','056-LIFECYCLE-A-RETURN','056-LIFECYCLE-A-LOST-EVENT','2026-06-04 11:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select id::text from operations.return_items where return_id=(select id from operations.returns where external_return_ref='056-LIFECYCLE-A-RETURN')),'quantity',1,'sourceLineRef','056-LIFECYCLE-A-LOST-LINE')),'fixture','{}');
insert into lifecycle_fixture_results select 'LIFECYCLE_A_CLAIM',api.create_tiktok_return_claim('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-A-CLAIM',(select id from operations.returns where external_return_ref='056-LIFECYCLE-A-RETURN'),'LOST_RETURN',jsonb_build_array(jsonb_build_object('returnItemId',(select id::text from operations.return_items where return_id=(select id from operations.returns where external_return_ref='056-LIFECYCLE-A-RETURN')),'quantity',1)),'2026-06-20 10:00:00+07');
reset role;
create temp table lifecycle_a_timeline as select id claim_id,deadline_at-interval '14 days' a_d14,deadline_at-interval '14 days'+interval '1 hour' a_resolution_at from operations.return_claims where id=(select (result->>'claimId')::uuid from lifecycle_fixture_results where kind='LIFECYCLE_A_CLAIM');
grant select on lifecycle_a_timeline to authenticated;
select is((select count(*) from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid),0::bigint,'lifecycle tenant has no notification before Claim A evaluation');
select is((select status_code from operations.return_claims where id=(select claim_id from lifecycle_a_timeline)),'NOT_STARTED','Claim A remains NOT_STARTED before evaluator');
select is((select deadline_at from operations.return_claims where id=(select claim_id from lifecycle_a_timeline)),(select created_at+interval '40 days' from operations.returns where external_return_ref='056-LIFECYCLE-A-RETURN'),'Claim A deadline is forty days after the return was created');
insert into lifecycle_fixture_results select 'LIFECYCLE_A_D14',notification.evaluate_tiktok_claim_deadlines('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-A-D14',(select a_d14 from lifecycle_a_timeline),'pgtap.056');
create temp table lifecycle_a_episode as select id from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_a_timeline) and rule_code_snapshot='CLAIM_DEADLINE';
insert into lifecycle_fixture_results values ('LIFECYCLE_A_EPISODE',jsonb_build_object('notificationId',(select id from lifecycle_a_episode)));
select is((select count(*) from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_a_timeline) and rule_code_snapshot='CLAIM_DEADLINE'),1::bigint,'Claim A creates one CLAIM_DEADLINE notification');
select is((select lifecycle_status_code from notification.notifications where id=(select id from lifecycle_a_episode)),'OPEN','Claim A deadline notification opens at D14');
select is((select stage_code from notification.notifications where id=(select id from lifecycle_a_episode)),'D14','Claim A deadline notification has D14 stage');
select is((select entity_id from notification.notifications where id=(select id from lifecycle_a_episode)),(select claim_id from lifecycle_a_timeline),'Claim A deadline notification is linked to Claim A');
select ok((select nullif(result->>'notificationId','') is not null from lifecycle_fixture_results where kind='LIFECYCLE_A_EPISODE'),'Claim A notification ID is stored in lifecycle fixture results');
select is((select count(*) from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_a_timeline) and rule_code_snapshot='CLAIM_DEADLINE' and lifecycle_status_code in ('OPEN','ACKNOWLEDGED')),1::bigint,'Claim A has no active deadline duplicate');
create temp table lifecycle_a_stock_open as select jsonb_build_object('transactions',(select count(*) from inventory.stock_transactions),'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),'ledgerByProduct',(select coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'quantity',quantity) order by product_id),'[]'::jsonb) from (select product_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by product_id) product_ledger),'ledgerByBatch',(select coalesce(jsonb_agg(jsonb_build_object('batchId',batch_id,'quantity',quantity) order by batch_id),'[]'::jsonb) from (select batch_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by batch_id) batch_ledger),'reservations',(select coalesce(jsonb_agg(to_jsonb(reservation) order by reservation.id),'[]'::jsonb) from inventory.stock_reservations reservation),'productPositions',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position),'batchPositions',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance)) snapshot;
create temp table lifecycle_a_events_open as select count(*)::bigint event_count from notification.notification_events where notification_id=(select id from lifecycle_a_episode);
set local role authenticated;
insert into lifecycle_fixture_results select 'LIFECYCLE_A_SUBMIT',api.submit_tiktok_return_claim('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-A-SUBMIT',(select claim_id from lifecycle_a_timeline),'056-LIFECYCLE-A-EXTERNAL-CLAIM',(select a_resolution_at from lifecycle_a_timeline));
reset role;
insert into lifecycle_fixture_results select 'LIFECYCLE_A_RESOLUTION',notification.evaluate_tiktok_claim_deadlines('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-A-RESOLUTION',(select a_resolution_at from lifecycle_a_timeline),'pgtap.056');
select is((select status_code from operations.return_claims where id=(select claim_id from lifecycle_a_timeline)),'SUBMITTED','Claim A is SUBMITTED before deadline episode resolution');
select is((select lifecycle_status_code from notification.notifications where id=(select id from lifecycle_a_episode)),'RESOLVED','submitted Claim A resolves the deadline notification');
select is((select resolution_code from notification.notifications where id=(select id from lifecycle_a_episode)),'CLAIM_LIFECYCLE_COMPLETED','Claim A resolution has the lifecycle-completed reason');
select is((select id from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_a_timeline) and rule_code_snapshot='CLAIM_DEADLINE'),(select (result->>'notificationId')::uuid from lifecycle_fixture_results where kind='LIFECYCLE_A_EPISODE'),'Claim A resolution retains the original notification ID');
select is((select count(*) from notification.notification_events where notification_id=(select id from lifecycle_a_episode) and event_type_code='RESOLVED'),1::bigint,'Claim A resolution appends one RESOLVED event');
select is((select count(*) from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_a_timeline) and rule_code_snapshot='CLAIM_DEADLINE' and lifecycle_status_code in ('OPEN','ACKNOWLEDGED')),0::bigint,'Claim A has no active CLAIM_DEADLINE episode after submission');
select ok(exists(select 1 from notification.notification_events where notification_id=(select id from lifecycle_a_episode) and event_type_code='CREATED' and to_stage_code='D14'),'Claim A retains its D14 notification history after resolution');
select is(
  (
    select jsonb_build_object(
      'transactions',(select count(*) from inventory.stock_transactions),
      'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),
      'ledgerByProduct',(select coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'quantity',quantity) order by product_id),'[]'::jsonb) from (select product_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by product_id) product_ledger),
      'ledgerByBatch',(select coalesce(jsonb_agg(jsonb_build_object('batchId',batch_id,'quantity',quantity) order by batch_id),'[]'::jsonb) from (select batch_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by batch_id) batch_ledger),
      'reservations',(select coalesce(jsonb_agg(to_jsonb(reservation) order by reservation.id),'[]'::jsonb) from inventory.stock_reservations reservation),
      'productPositions',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position),
      'batchPositions',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance)
    )
  ),
  (
    select snapshot
    from lifecycle_a_stock_open
  ),
  'Claim A submission and resolution are stock-neutral'
);
create temp table lifecycle_a_events_resolved as select count(*)::bigint event_count from notification.notification_events where notification_id=(select id from lifecycle_a_episode);
insert into lifecycle_fixture_results select 'LIFECYCLE_A_RESOLUTION_REPLAY',notification.evaluate_tiktok_claim_deadlines('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-A-RESOLUTION',(select a_resolution_at from lifecycle_a_timeline),'pgtap.056');
select is((select result->>'action' from lifecycle_fixture_results where kind='LIFECYCLE_A_RESOLUTION_REPLAY'),'REPLAYED','Claim A resolution evaluator replay is REPLAYED');
select is((select count(*) from notification.rule_runs where organization_id='00000000-0000-4000-8000-000000000056'::uuid and rule_code_snapshot='CLAIM_DEADLINE' and idempotency_key='056-LIFECYCLE-A-RESOLUTION'),1::bigint,'Claim A replay does not create a second rule run');
select is((select count(*) from notification.notification_events where notification_id=(select id from lifecycle_a_episode)),(select event_count from lifecycle_a_events_resolved),'Claim A replay adds no notification event');
select is((select lifecycle_status_code from notification.notifications where id=(select id from lifecycle_a_episode)),'RESOLVED','Claim A notification remains RESOLVED after replay');
select is(
  (
    select jsonb_build_object(
      'transactions',(select count(*) from inventory.stock_transactions),
      'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),
      'ledgerByProduct',(select coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'quantity',quantity) order by product_id),'[]'::jsonb) from (select product_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by product_id) product_ledger),
      'ledgerByBatch',(select coalesce(jsonb_agg(jsonb_build_object('batchId',batch_id,'quantity',quantity) order by batch_id),'[]'::jsonb) from (select batch_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by batch_id) batch_ledger),
      'reservations',(select coalesce(jsonb_agg(to_jsonb(reservation) order by reservation.id),'[]'::jsonb) from inventory.stock_reservations reservation),
      'productPositions',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position),
      'batchPositions',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance)
    )
  ),
  (
    select snapshot
    from lifecycle_a_stock_open
  ),
  'Claim A replay remains stock-neutral'
);

set local role authenticated;
insert into lifecycle_fixture_results select 'LIFECYCLE_B_RESERVE',api.apply_marketplace_event('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-B-RESERVE','TIKTOK_SHOP','RESERVE','056-LIFECYCLE-B-RESERVE-EVENT','056-LIFECYCLE-B-ORDER','2026-06-01 10:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select result->>'productId' from lifecycle_fixture_results where kind='PRODUCT'),'quantity',1,'sourceLineRef','056-LIFECYCLE-B-LINE')),'fixture','{}');
insert into lifecycle_fixture_results select 'LIFECYCLE_B_SHIP',api.apply_marketplace_event('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-B-SHIP','TIKTOK_SHOP','SHIP','056-LIFECYCLE-B-SHIP-EVENT','056-LIFECYCLE-B-ORDER','2026-06-02 10:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select result->>'productId' from lifecycle_fixture_results where kind='PRODUCT'),'quantity',1,'sourceLineRef','056-LIFECYCLE-B-LINE')),'fixture','{}');
insert into lifecycle_fixture_results select 'LIFECYCLE_B_EXPECTED',api.create_expected_return('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-B-EXPECTED','TIKTOK_SHOP','056-LIFECYCLE-B-RETURN','056-LIFECYCLE-B-ORDER','2026-06-03 12:00:00+07',jsonb_build_array(jsonb_build_object('productId',(select result->>'productId' from lifecycle_fixture_results where kind='PRODUCT'),'quantity',1,'sourceLineRef','056-LIFECYCLE-B-LINE')),'RETURN_REQUESTED','fixture','{}');
insert into lifecycle_fixture_results select 'LIFECYCLE_B_LOST',api.mark_return_lost('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-B-LOST','056-LIFECYCLE-B-RETURN','056-LIFECYCLE-B-LOST-EVENT','2026-06-04 12:00:00+07',jsonb_build_array(jsonb_build_object('returnItemId',(select id::text from operations.return_items where return_id=(select id from operations.returns where external_return_ref='056-LIFECYCLE-B-RETURN')),'quantity',1,'sourceLineRef','056-LIFECYCLE-B-LOST-LINE')),'fixture','{}');
insert into lifecycle_fixture_results select 'LIFECYCLE_B_CLAIM',api.create_tiktok_return_claim('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-B-CLAIM',(select id from operations.returns where external_return_ref='056-LIFECYCLE-B-RETURN'),'LOST_RETURN',jsonb_build_array(jsonb_build_object('returnItemId',(select id::text from operations.return_items where return_id=(select id from operations.returns where external_return_ref='056-LIFECYCLE-B-RETURN')),'quantity',1)),'2026-06-20 12:00:00+07');
reset role;
create temp table lifecycle_b_timeline as select id claim_id,deadline_at-interval '14 days' b_d14,deadline_at-interval '14 days'+interval '1 minute' b_acknowledged_at,deadline_at-interval '14 days'+interval '1 hour' b_resolution_at from operations.return_claims where id=(select (result->>'claimId')::uuid from lifecycle_fixture_results where kind='LIFECYCLE_B_CLAIM');
grant select on lifecycle_b_timeline to authenticated;
select ok((select b_d14>(select max(last_seen_at) from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid) from lifecycle_b_timeline),'Claim B D14 is later than every lifecycle notification last_seen_at');
select is((select status_code from operations.return_claims where id=(select claim_id from lifecycle_b_timeline)),'NOT_STARTED','Claim B remains NOT_STARTED before evaluator');
insert into lifecycle_fixture_results select 'LIFECYCLE_B_D14',notification.evaluate_tiktok_claim_deadlines('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-B-D14',(select b_d14 from lifecycle_b_timeline),'pgtap.056');
create temp table lifecycle_b_episode as select id from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_b_timeline) and rule_code_snapshot='CLAIM_DEADLINE';
insert into lifecycle_fixture_results values ('LIFECYCLE_B_EPISODE',jsonb_build_object('notificationId',(select id from lifecycle_b_episode)));
select is((select count(*) from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_b_timeline) and rule_code_snapshot='CLAIM_DEADLINE'),1::bigint,'Claim B creates one CLAIM_DEADLINE notification');
select is((select lifecycle_status_code from notification.notifications where id=(select id from lifecycle_b_episode)),'OPEN','Claim B deadline notification opens at D14');
select is((select stage_code from notification.notifications where id=(select id from lifecycle_b_episode)),'D14','Claim B deadline notification has D14 stage');
select is((select entity_id from notification.notifications where id=(select id from lifecycle_b_episode)),(select claim_id from lifecycle_b_timeline),'Claim B deadline notification is linked to Claim B');
select isnt((select id from lifecycle_b_episode),(select (result->>'notificationId')::uuid from lifecycle_fixture_results where kind='LIFECYCLE_A_EPISODE'),'Claim B notification ID differs from Claim A');
select is((select count(*) from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_b_timeline) and rule_code_snapshot='CLAIM_DEADLINE' and lifecycle_status_code in ('OPEN','ACKNOWLEDGED')),1::bigint,'Claim B has no active deadline duplicate');
insert into lifecycle_fixture_results select 'LIFECYCLE_B_ACKNOWLEDGE',notification.acknowledge_notification('00000000-0000-4000-8000-000000000056',(select id from lifecycle_b_episode),(select b_acknowledged_at from lifecycle_b_timeline),gen_random_uuid(),'95600000-0000-4000-8000-000000000056','056-LIFECYCLE-B acknowledged');
select is((select lifecycle_status_code from notification.notifications where id=(select id from lifecycle_b_episode)),'ACKNOWLEDGED','Claim B notification is ACKNOWLEDGED');
select is((select count(*) from notification.notification_events where notification_id=(select id from lifecycle_b_episode) and event_type_code='ACKNOWLEDGED'),1::bigint,'Claim B acknowledgement appends one ACKNOWLEDGED event');
select is((select status_code from operations.return_claims where id=(select claim_id from lifecycle_b_timeline)),'NOT_STARTED','Claim B acknowledgement does not mutate claim lifecycle');
select is((select id from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_b_timeline) and rule_code_snapshot='CLAIM_DEADLINE'),(select (result->>'notificationId')::uuid from lifecycle_fixture_results where kind='LIFECYCLE_B_EPISODE'),'Claim B acknowledgement retains the original notification ID');
create temp table lifecycle_b_stock_acknowledged as select jsonb_build_object('transactions',(select count(*) from inventory.stock_transactions),'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),'ledgerByProduct',(select coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'quantity',quantity) order by product_id),'[]'::jsonb) from (select product_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by product_id) product_ledger),'ledgerByBatch',(select coalesce(jsonb_agg(jsonb_build_object('batchId',batch_id,'quantity',quantity) order by batch_id),'[]'::jsonb) from (select batch_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by batch_id) batch_ledger),'reservations',(select coalesce(jsonb_agg(to_jsonb(reservation) order by reservation.id),'[]'::jsonb) from inventory.stock_reservations reservation),'productPositions',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position),'batchPositions',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance)) snapshot;
set local role authenticated;
insert into lifecycle_fixture_results select 'LIFECYCLE_B_SUBMIT',api.submit_tiktok_return_claim('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-B-SUBMIT',(select claim_id from lifecycle_b_timeline),'056-LIFECYCLE-B-EXTERNAL-CLAIM',(select b_resolution_at from lifecycle_b_timeline));
reset role;
insert into lifecycle_fixture_results select 'LIFECYCLE_B_RESOLUTION',notification.evaluate_tiktok_claim_deadlines('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-B-RESOLUTION',(select b_resolution_at from lifecycle_b_timeline),'pgtap.056');
select is((select status_code from operations.return_claims where id=(select claim_id from lifecycle_b_timeline)),'SUBMITTED','Claim B is SUBMITTED before deadline episode resolution');
select is((select lifecycle_status_code from notification.notifications where id=(select id from lifecycle_b_episode)),'RESOLVED','submitted Claim B resolves the deadline notification');
select is((select resolution_code from notification.notifications where id=(select id from lifecycle_b_episode)),'CLAIM_LIFECYCLE_COMPLETED','Claim B resolution has the lifecycle-completed reason');
select is((select count(*) from notification.notification_events where notification_id=(select id from lifecycle_b_episode) and event_type_code='ACKNOWLEDGED'),1::bigint,'Claim B resolution retains the ACKNOWLEDGED event');
select is((select count(*) from notification.notification_events where notification_id=(select id from lifecycle_b_episode) and event_type_code='RESOLVED'),1::bigint,'Claim B resolution appends one RESOLVED event');
select is((select id from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_b_timeline) and rule_code_snapshot='CLAIM_DEADLINE'),(select (result->>'notificationId')::uuid from lifecycle_fixture_results where kind='LIFECYCLE_B_EPISODE'),'Claim B resolution retains the original notification ID');
select is((select count(*) from notification.notifications where organization_id='00000000-0000-4000-8000-000000000056'::uuid and entity_id=(select claim_id from lifecycle_b_timeline) and rule_code_snapshot='CLAIM_DEADLINE' and lifecycle_status_code in ('OPEN','ACKNOWLEDGED')),0::bigint,'Claim B has no active CLAIM_DEADLINE episode after submission');
select ok(exists(select 1 from notification.notification_events where notification_id=(select id from lifecycle_b_episode) and event_type_code='CREATED' and to_stage_code='D14'),'Claim B retains its D14 notification history after resolution');
select is(
  (
    select jsonb_build_object(
      'transactions',(select count(*) from inventory.stock_transactions),
      'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),
      'ledgerByProduct',(select coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'quantity',quantity) order by product_id),'[]'::jsonb) from (select product_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by product_id) product_ledger),
      'ledgerByBatch',(select coalesce(jsonb_agg(jsonb_build_object('batchId',batch_id,'quantity',quantity) order by batch_id),'[]'::jsonb) from (select batch_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by batch_id) batch_ledger),
      'reservations',(select coalesce(jsonb_agg(to_jsonb(reservation) order by reservation.id),'[]'::jsonb) from inventory.stock_reservations reservation),
      'productPositions',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position),
      'batchPositions',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance)
    )
  ),
  (
    select snapshot
    from lifecycle_b_stock_acknowledged
  ),
  'Claim B submission and resolution are stock-neutral'
);
create temp table lifecycle_b_events_resolved as select count(*)::bigint event_count from notification.notification_events where notification_id=(select id from lifecycle_b_episode);
insert into lifecycle_fixture_results select 'LIFECYCLE_B_RESOLUTION_REPLAY',notification.evaluate_tiktok_claim_deadlines('00000000-0000-4000-8000-000000000056','056-LIFECYCLE-B-RESOLUTION',(select b_resolution_at from lifecycle_b_timeline),'pgtap.056');
select is((select result->>'action' from lifecycle_fixture_results where kind='LIFECYCLE_B_RESOLUTION_REPLAY'),'REPLAYED','Claim B resolution evaluator replay is REPLAYED');
select is((select count(*) from notification.rule_runs where organization_id='00000000-0000-4000-8000-000000000056'::uuid and rule_code_snapshot='CLAIM_DEADLINE' and idempotency_key='056-LIFECYCLE-B-RESOLUTION'),1::bigint,'Claim B replay does not create a second rule run');
select is((select count(*) from notification.notification_events where notification_id=(select id from lifecycle_b_episode)),(select event_count from lifecycle_b_events_resolved),'Claim B replay adds no notification event');
select is((select lifecycle_status_code from notification.notifications where id=(select id from lifecycle_b_episode)),'RESOLVED','Claim B notification remains RESOLVED after replay');
select is(
  (
    select jsonb_build_object(
      'transactions',(select count(*) from inventory.stock_transactions),
      'ledgerEntries',(select count(*) from inventory.stock_ledger_entries),
      'ledgerByProduct',(select coalesce(jsonb_agg(jsonb_build_object('productId',product_id,'quantity',quantity) order by product_id),'[]'::jsonb) from (select product_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by product_id) product_ledger),
      'ledgerByBatch',(select coalesce(jsonb_agg(jsonb_build_object('batchId',batch_id,'quantity',quantity) order by batch_id),'[]'::jsonb) from (select batch_id,sum(quantity_delta) quantity from inventory.stock_ledger_entries group by batch_id) batch_ledger),
      'reservations',(select coalesce(jsonb_agg(to_jsonb(reservation) order by reservation.id),'[]'::jsonb) from inventory.stock_reservations reservation),
      'productPositions',(select coalesce(jsonb_agg(to_jsonb(position) order by position.product_id),'[]'::jsonb) from inventory.stock_product_positions position),
      'batchPositions',(select coalesce(jsonb_agg(to_jsonb(balance) order by balance.batch_id),'[]'::jsonb) from inventory.stock_batch_balances balance)
    )
  ),
  (
    select snapshot
    from lifecycle_b_stock_acknowledged
  ),
  'Claim B replay remains stock-neutral'
);

select * from finish();
rollback;
