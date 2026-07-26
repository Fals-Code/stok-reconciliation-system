begin;

create extension if not exists pgtap;

select plan(49);

select has_function('api', 'submit_tiktok_return_claim', array['uuid', 'text', 'uuid', 'text', 'timestamp with time zone'], 'submit wrapper has the stable identity');
select has_function('api', 'resolve_tiktok_return_claim', array['uuid', 'text', 'uuid', 'text', 'timestamp with time zone'], 'resolve wrapper has the stable identity');
select has_function('api', 'cancel_tiktok_return_claim', array['uuid', 'text', 'uuid', 'text', 'timestamp with time zone'], 'cancel wrapper has the stable identity');
select has_function('api', 'evaluate_tiktok_return_claim_deadline', array['uuid', 'text', 'uuid', 'timestamp with time zone'], 'evaluate wrapper has the stable identity');

select is((select p.prorettype::regtype::text from pg_proc p where p.oid = 'api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 'jsonb', 'submit wrapper returns jsonb');
select is((select p.prorettype::regtype::text from pg_proc p where p.oid = 'api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 'jsonb', 'resolve wrapper returns jsonb');
select is((select p.prorettype::regtype::text from pg_proc p where p.oid = 'api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 'jsonb', 'cancel wrapper returns jsonb');
select is((select p.prorettype::regtype::text from pg_proc p where p.oid = 'api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamp with time zone)'::regprocedure), 'jsonb', 'evaluate wrapper returns jsonb');

select ok((select p.prosecdef from pg_proc p where p.oid = 'api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 'submit wrapper is security definer');
select ok((select p.prosecdef from pg_proc p where p.oid = 'api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 'resolve wrapper is security definer');
select ok((select p.prosecdef from pg_proc p where p.oid = 'api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 'cancel wrapper is security definer');
select ok((select p.prosecdef from pg_proc p where p.oid = 'api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamp with time zone)'::regprocedure), 'evaluate wrapper is security definer');

select is((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = 'api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 'search_path=pg_catalog, api', 'submit wrapper has fixed search_path');
select is((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = 'api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 'search_path=pg_catalog, api', 'resolve wrapper has fixed search_path');
select is((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = 'api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 'search_path=pg_catalog, api', 'cancel wrapper has fixed search_path');
select is((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = 'api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamp with time zone)'::regprocedure), 'search_path=pg_catalog, api', 'evaluate wrapper has fixed search_path');

select is((select p.proargnames from pg_proc p where p.oid = 'api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), array['p_organization_id', 'p_idempotency_key', 'p_claim_id', 'p_external_claim_ref', 'p_occurred_at']::text[], 'submit wrapper exposes ordered PostgREST argument names');
select is((select p.proargnames from pg_proc p where p.oid = 'api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), array['p_organization_id', 'p_idempotency_key', 'p_claim_id', 'p_resolution_code', 'p_occurred_at']::text[], 'resolve wrapper exposes ordered PostgREST argument names');
select is((select p.proargnames from pg_proc p where p.oid = 'api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), array['p_organization_id', 'p_idempotency_key', 'p_claim_id', 'p_reason', 'p_occurred_at']::text[], 'cancel wrapper exposes ordered PostgREST argument names');
select is((select p.proargnames from pg_proc p where p.oid = 'api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamp with time zone)'::regprocedure), array['p_organization_id', 'p_idempotency_key', 'p_claim_id', 'p_observed_at']::text[], 'evaluate wrapper exposes ordered PostgREST argument names');

select is((select p.pronargdefaults::integer from pg_proc p where p.oid = 'api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 1, 'submit occurred_at has a default');
select is((select p.pronargdefaults::integer from pg_proc p where p.oid = 'api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 1, 'resolve occurred_at has a default');
select is((select p.pronargdefaults::integer from pg_proc p where p.oid = 'api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)'::regprocedure), 1, 'cancel occurred_at has a default');
select is((select p.pronargdefaults::integer from pg_proc p where p.oid = 'api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamp with time zone)'::regprocedure), 1, 'evaluate observed_at has a default');

select ok(has_function_privilege('authenticated', 'api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'authenticated can execute submit wrapper');
select ok(has_function_privilege('authenticated', 'api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'authenticated can execute resolve wrapper');
select ok(has_function_privilege('authenticated', 'api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'authenticated can execute cancel wrapper');
select ok(not has_function_privilege('authenticated', 'api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamp with time zone)', 'EXECUTE'), 'authenticated cannot execute trusted-worker expiry wrapper');
select ok(has_function_privilege('service_role', 'api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'service role can execute submit wrapper');
select ok(has_function_privilege('service_role', 'api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'service role can execute resolve wrapper');
select ok(has_function_privilege('service_role', 'api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'service role can execute cancel wrapper');
select ok(has_function_privilege('service_role', 'api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamp with time zone)', 'EXECUTE'), 'service role can execute evaluate wrapper');
select ok(not has_function_privilege('public', 'api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'public cannot execute submit wrapper');
select ok(not has_function_privilege('public', 'api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'public cannot execute resolve wrapper');
select ok(not has_function_privilege('public', 'api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'public cannot execute cancel wrapper');
select ok(not has_function_privilege('public', 'api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamp with time zone)', 'EXECUTE'), 'public cannot execute evaluate wrapper');
select ok(not has_function_privilege('anon', 'api.submit_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'anon cannot execute submit wrapper');
select ok(not has_function_privilege('anon', 'api.resolve_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'anon cannot execute resolve wrapper');
select ok(not has_function_privilege('anon', 'api.cancel_tiktok_return_claim(uuid,text,uuid,text,timestamp with time zone)', 'EXECUTE'), 'anon cannot execute cancel wrapper');
select ok(not has_function_privilege('anon', 'api.evaluate_tiktok_return_claim_deadline(uuid,text,uuid,timestamp with time zone)', 'EXECUTE'), 'anon cannot execute evaluate wrapper');
select ok(not has_function_privilege('authenticated', 'api.transition_tiktok_return_claim(uuid,text,uuid,text,text,text,text,timestamp with time zone)', 'EXECUTE'), 'authenticated cannot execute internal transition helper');

select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'api' and p.proname = 'submit_tiktok_return_claim'), 1, 'submit has no ambiguous overload');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'api' and p.proname = 'resolve_tiktok_return_claim'), 1, 'resolve has no ambiguous overload');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'api' and p.proname = 'cancel_tiktok_return_claim'), 1, 'cancel has no ambiguous overload');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'api' and p.proname = 'evaluate_tiktok_return_claim_deadline'), 1, 'evaluate has no ambiguous overload');

select throws_ok($$select api.submit_tiktok_return_claim(p_organization_id := '00000000-0000-4000-8000-000000000001', p_idempotency_key := '058-NAMED-SUBMIT', p_claim_id := gen_random_uuid(), p_external_claim_ref := '058-NAMED-SUBMIT')$$, '42501', 'ORGANIZATION_ACCESS_DENIED', 'submit named notation resolves before controlled authorization rejection');
select throws_ok($$select api.resolve_tiktok_return_claim(p_organization_id := '00000000-0000-4000-8000-000000000001', p_idempotency_key := '058-NAMED-RESOLVE', p_claim_id := gen_random_uuid(), p_resolution_code := 'APPROVED')$$, '42501', 'ORGANIZATION_ACCESS_DENIED', 'resolve named notation resolves before controlled authorization rejection');
select throws_ok($$select api.cancel_tiktok_return_claim(p_organization_id := '00000000-0000-4000-8000-000000000001', p_idempotency_key := '058-NAMED-CANCEL', p_claim_id := gen_random_uuid(), p_reason := 'contract parser probe')$$, '42501', 'ORGANIZATION_ACCESS_DENIED', 'cancel named notation resolves before controlled authorization rejection');
select throws_ok($$select api.evaluate_tiktok_return_claim_deadline(p_organization_id := '00000000-0000-4000-8000-000000000001', p_idempotency_key := '058-NAMED-EVALUATE', p_claim_id := gen_random_uuid())$$, '42501', 'ORGANIZATION_ACCESS_DENIED', 'evaluate named notation resolves before controlled authorization rejection');

select * from finish();

rollback;
