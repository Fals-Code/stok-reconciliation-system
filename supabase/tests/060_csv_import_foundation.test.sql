begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_table('integration', 'import_jobs', 'CSV import job staging table exists');
select has_table('integration', 'import_rows', 'CSV import row staging table exists');
select has_view('api', 'import_job_read_model', 'CSV import job read model exists');
select has_view('api', 'import_row_read_model', 'CSV import row read model exists');
select has_column('integration', 'import_jobs', 'organization_id', 'jobs are organization-scoped');
select has_column('integration', 'import_jobs', 'file_sha256', 'file checksum is distinct identity');
select has_column('integration', 'import_jobs', 'job_command_key', 'job command key is distinct identity');
select has_column('integration', 'import_jobs', 'job_request_hash', 'request hash supports changed-payload conflict');
select has_column('integration', 'import_rows', 'row_fingerprint', 'row fingerprint is distinct identity');
select has_column('integration', 'import_rows', 'canonical_idempotency_key', 'canonical event key is staged separately');

select ok(
  (select reloptions @> array['security_invoker=true', 'security_barrier=true']
   from pg_class where oid = 'api.import_job_read_model'::regclass),
  'job read model is an invoker security-barrier view'
);
select ok(
  (select reloptions @> array['security_invoker=true', 'security_barrier=true']
   from pg_class where oid = 'api.import_row_read_model'::regclass),
  'row read model is an invoker security-barrier view'
);
select ok((select relrowsecurity from pg_class where oid = 'integration.import_jobs'::regclass), 'jobs retain RLS');
select ok((select relforcerowsecurity from pg_class where oid = 'integration.import_jobs'::regclass), 'jobs force RLS');
select ok((select relrowsecurity from pg_class where oid = 'integration.import_rows'::regclass), 'rows retain RLS');
select ok((select relforcerowsecurity from pg_class where oid = 'integration.import_rows'::regclass), 'rows force RLS');

select has_index('integration', 'import_jobs', 'import_jobs_org_command_key', 'job command identity is organization-scoped and unique');
select has_index('integration', 'import_jobs', 'import_jobs_org_file_hash_key', 'file checksum duplicate detection is organization-scoped');
select has_index('integration', 'import_rows', 'import_rows_job_row_number_key', 'row number is unique within a job');
select has_index('integration', 'import_rows', 'import_rows_job_fingerprint_key', 'row fingerprint is unique within a job');

select function_returns(
  'api',
  'create_marketplace_csv_import_job',
  array['text', 'text', 'text', 'text', 'bigint', 'text'],
  'jsonb',
  'staging job creation is an API contract'
);
select function_returns(
  'api',
  'classify_marketplace_csv_import_request',
  array['text', 'text', 'text'],
  'text',
  'replay classification is a read-only API contract'
);
select ok(
  has_function_privilege('authenticated', 'api.create_marketplace_csv_import_job(text,text,text,text,bigint,text)', 'EXECUTE'),
  'authenticated Admin may create a staging job'
);
select ok(
  not has_function_privilege('anon', 'api.create_marketplace_csv_import_job(text,text,text,text,bigint,text)', 'EXECUTE'),
  'anon cannot create a staging job'
);
select ok(
  has_function_privilege('service_role', 'api.create_marketplace_csv_import_job(text,text,text,text,bigint,text)', 'EXECUTE'),
  'service role retains staging boundary access'
);
select ok(
  not has_table_privilege('authenticated', 'integration.import_jobs', 'INSERT'),
  'authenticated cannot directly insert import jobs'
);
select ok(
  not has_table_privilege('authenticated', 'integration.import_rows', 'INSERT'),
  'authenticated cannot directly insert import rows'
);
select ok(
  not has_table_privilege('anon', 'api.import_job_read_model', 'SELECT'),
  'anon cannot read import jobs'
);
select ok(
  not has_table_privilege('anon', 'api.import_row_read_model', 'SELECT'),
  'anon cannot read import rows'
);

select ok(
  (select proconfig @> array['search_path=pg_catalog, auth, app, integration, api, extensions']
   from pg_proc
   where oid = 'api.create_marketplace_csv_import_job(text,text,text,text,bigint,text)'::regprocedure),
  'job creation SECURITY DEFINER uses a fixed search_path'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, auth, app, integration, api, extensions']
   from pg_proc
   where oid = 'api.classify_marketplace_csv_import_request(text,text,text)'::regprocedure),
  'classification SECURITY DEFINER uses a fixed search_path'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, integration']
   from pg_proc
   where oid = 'integration.enforce_import_job_transition()'::regprocedure),
  'lifecycle trigger uses a fixed search_path'
);

select ok(
  exists (
    select 1
    from pg_description d
    join pg_class c on c.oid = d.objoid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'integration'
      and c.relname = 'import_jobs'
      and d.description like '%RESERVE%'
  ),
  'migration documents v1 as the existing RESERVE boundary'
);

select is((select public from storage.buckets where id = 'imports'), false, 'imports bucket is private');
select is((select file_size_limit from storage.buckets where id = 'imports'), 10485760::bigint, 'imports bucket has the 10 MB limit');
select ok(
  (select allowed_mime_types @> array['text/csv', 'application/csv', 'text/plain']::text[] from storage.buckets where id = 'imports'),
  'imports bucket restricts accepted MIME declarations'
);
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and (policyname like 'csv_imports_%')
      and (roles @> array['public']::name[] or roles @> array['anon']::name[] or roles @> array['authenticated']::name[])
  ),
  'this migration does not add browser or public storage access'
);

insert into app.organizations(id, code, name, timezone, is_active, created_at)
values
  ('00000000-0000-4060-8000-000000000001', 'PGTAP_CSV_060_A', 'CSV Foundation 060 A', 'Asia/Jakarta', true, '2026-07-26 08:00:00+07'),
  ('00000000-0000-4060-8000-000000000002', 'PGTAP_CSV_060_B', 'CSV Foundation 060 B', 'Asia/Jakarta', true, '2026-07-26 08:00:00+07');

insert into auth.users(instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4060-8000-000000000001', 'authenticated', 'authenticated', 'pgtap.csv.060@glowlab.invalid', '2026-07-26 08:00:00+07', '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', false, false);

insert into app.user_profiles(user_id, organization_id, display_name, employee_code, role_code, is_active)
values ('00000000-0000-4060-8000-000000000001', '00000000-0000-4060-8000-000000000001', 'CSV Foundation Admin', 'PGTAP-CSV-060', 'ADMIN', true);

insert into integration.import_jobs (
  id, organization_id, created_by_process, import_type_code, template_version, status_code,
  original_file_name, object_path, detected_mime, file_size_bytes, file_sha256,
  job_command_key, job_request_hash, row_count, valid_row_count, invalid_row_count,
  duplicate_row_count, conflict_row_count, processed_row_count, created_at
) values
  ('00000000-0000-4060-8000-000000000101', '00000000-0000-4060-8000-000000000001', 'pgtap-060', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED', 'orders.csv', '00000000-0000-4060-8000-000000000001/00000000-0000-4060-8000-000000000101/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.csv', 'text/csv', 128, repeat('a', 64), 'CSV060-CMD-A', repeat('1', 64), 2, 1, 1, 0, 0, 0, '2026-07-26 09:00:01+07'),
  ('00000000-0000-4060-8000-000000000102', '00000000-0000-4060-8000-000000000002', 'pgtap-060', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED', 'other.csv', '00000000-0000-4060-8000-000000000002/00000000-0000-4060-8000-000000000102/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.csv', 'text/csv', 128, repeat('b', 64), 'CSV060-CMD-B', repeat('2', 64), 1, 1, 0, 0, 0, 0, '2026-07-26 09:00:02+07');

insert into integration.import_rows (
  id, organization_id, import_job_id, row_number, raw_row, normalized_row,
  row_fingerprint, validation_status_code, validation_errors, processing_status_code,
  external_event_ref, canonical_idempotency_key, canonical_line_count
) values
  ('00000000-0000-4060-8000-000000000201', '00000000-0000-4060-8000-000000000001', '00000000-0000-4060-8000-000000000101', 1, '{"order_ref":"ORD-060-A"}', '{"sourceLineRef":"LINE-060-A"}', repeat('c', 64), 'VALID', '[]'::jsonb, 'PENDING', 'CSV060-EVENT-A', 'CSV060-CANONICAL-A', 2),
  ('00000000-0000-4060-8000-000000000202', '00000000-0000-4060-8000-000000000001', '00000000-0000-4060-8000-000000000101', 2, '{"order_ref":"ORD-060-B"}', '{}'::jsonb, repeat('d', 64), 'INVALID', '[{"field":"externalListingCode","code":"MAPPING_NOT_FOUND","message":"Listing mapping was not found","fix":"Check the listing code"}]'::jsonb, 'SKIPPED', 'CSV060-EVENT-B', 'CSV060-CANONICAL-B', 0),
  ('00000000-0000-4060-8000-000000000203', '00000000-0000-4060-8000-000000000002', '00000000-0000-4060-8000-000000000102', 1, '{"order_ref":"ORD-060-OTHER"}', '{"sourceLineRef":"LINE-060-OTHER"}', repeat('e', 64), 'VALID', '[]'::jsonb, 'PENDING', 'CSV060-EVENT-OTHER', 'CSV060-CANONICAL-OTHER', 1);

create temp table csv_domain_baseline as
select
  (select count(*) from inventory.stock_reservations where organization_id = '00000000-0000-4060-8000-000000000001') as reservation_count,
  (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4060-8000-000000000001') as ledger_count,
  (select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4060-8000-000000000001') as product_position_count,
  (select count(*) from operations.marketplace_orders where organization_id = '00000000-0000-4060-8000-000000000001') as order_count;
grant select on csv_domain_baseline to authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-4060-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4060-8000-000000000001', 'role', 'authenticated')::text, true);
set local role authenticated;

select is((select count(*) from api.import_job_read_model), 1::bigint, 'job read model is organization-scoped');
select is((select count(*) from api.import_row_read_model), 2::bigint, 'row read model is organization-scoped');
select is((select count(*) from api.import_job_read_model where id = '00000000-0000-4060-8000-000000000102'), 0::bigint, 'cross-organization job is safe not-found');
select is((select count(*) from api.import_row_read_model where id = '00000000-0000-4060-8000-000000000203'), 0::bigint, 'cross-organization row is safe not-found');
select is((select count(*) from (select 1 from api.import_row_read_model where import_job_id = '00000000-0000-4060-8000-000000000101' order by row_number, id limit 1) page), 1::bigint, 'row read model supports deterministic page limit');
select is((select row_number from api.import_row_read_model where import_job_id = '00000000-0000-4060-8000-000000000101' order by row_number, id limit 1), 1, 'row pagination has stable row-number ordering');
select is((select validation_errors->0->>'code' from api.import_row_read_model where id = '00000000-0000-4060-8000-000000000202'), 'MAPPING_NOT_FOUND', 'structured row errors are readable');
select is((select count(*) from information_schema.columns where table_schema = 'api' and table_name = 'import_row_read_model' and column_name = 'raw_row'), 0::bigint, 'raw file evidence is not exposed by the read model');

select ok(
  ((api.create_marketplace_csv_import_job('CSV060-CREATE', repeat('6', 64), 'new-orders.csv', 'text/csv', 256, repeat('6', 64))->>'objectPath') ~ '^00000000-0000-4060-8000-000000000001/[0-9a-f-]{36}/[0-9a-f]{32}[.]csv$'),
  'job creation generates an organization-scoped opaque object path'
);
select is((api.create_marketplace_csv_import_job('CSV060-REPLAY', repeat('7', 64), 'replay.csv', 'text/csv', 256, repeat('7', 64))->>'status'), 'CREATED', 'new command creates an UPLOADED staging job');
select is((api.create_marketplace_csv_import_job('CSV060-REPLAY', repeat('7', 64), 'replay.csv', 'text/csv', 256, repeat('7', 64))->>'status'), 'EXACT_REPLAY', 'same command and metadata replays the existing staging job');
select throws_ok(
  $$select api.create_marketplace_csv_import_job('CSV060-REPLAY', repeat('8', 64), 'replay.csv', 'text/csv', 256, repeat('7', 64))$$,
  'P0001',
  'IDEMPOTENCY_KEY_REUSED',
  'same command with changed metadata is rejected'
);
select is((api.create_marketplace_csv_import_job('CSV060-DUPLICATE-FILE', repeat('8', 64), 'duplicate.csv', 'text/csv', 256, repeat('a', 64))->>'status'), 'DUPLICATE_FILE', 'same file checksum does not create another job');
select is(api.classify_marketplace_csv_import_request('CSV060-CMD-A', repeat('1', 64), repeat('a', 64)), 'EXACT_REPLAY', 'same command and payload is an exact replay');
select is(api.classify_marketplace_csv_import_request('CSV060-CMD-A', repeat('9', 64), repeat('a', 64)), 'CONFLICT', 'same command with changed payload is a conflict');
select is(api.classify_marketplace_csv_import_request('CSV060-CMD-NEW', repeat('9', 64), repeat('a', 64)), 'DUPLICATE_FILE', 'same file checksum is classified as duplicate');
select is(api.classify_marketplace_csv_import_request('CSV060-CMD-NEW', repeat('9', 64), repeat('f', 64)), 'NEW', 'new command and file are classified as new');

select throws_ok(
  $$insert into integration.import_jobs (organization_id, created_by_process, original_file_name, object_path, detected_mime, file_size_bytes, file_sha256, job_command_key, job_request_hash) values ('00000000-0000-4060-8000-000000000001', 'authenticated', 'blocked.csv', '00000000-0000-4060-8000-000000000001/00000000-0000-4060-8000-000000000999/ffffffffffffffffffffffffffffffff.csv', 'text/csv', 128, repeat('f', 64), 'CSV060-DIRECT', repeat('f', 64))$$,
  '42501',
  'permission denied for table import_jobs',
  'authenticated cannot directly write staging tables'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'integration' and tablename in ('import_jobs', 'import_rows')
      and (roles @> array['anon']::name[] or roles @> array['public']::name[])
  ),
  'import staging has no public or anonymous policy'
);

select is((select count(*) from integration.import_jobs where organization_id = '00000000-0000-4060-8000-000000000001'), 3::bigint, 'staging contains fixture and two newly created jobs');
select is((select count(*) from integration.import_rows where organization_id = '00000000-0000-4060-8000-000000000001'), 2::bigint, 'fixture contains two organization rows');
select is((select count(*) from inventory.stock_reservations where organization_id = '00000000-0000-4060-8000-000000000001'), (select reservation_count from csv_domain_baseline), 'staging reads do not create reservations');
select is((select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4060-8000-000000000001'), (select ledger_count from csv_domain_baseline), 'staging reads do not write ledger entries');
select is((select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4060-8000-000000000001'), (select product_position_count from csv_domain_baseline), 'staging reads do not change projection');
select is((select count(*) from operations.marketplace_orders where organization_id = '00000000-0000-4060-8000-000000000001'), (select order_count from csv_domain_baseline), 'staging reads do not create marketplace orders');

reset role;
select throws_ok(
  $$update integration.import_jobs set status_code = 'COMPLETED' where id = '00000000-0000-4060-8000-000000000101'$$,
  'P0001',
  'IMPORT_INVALID_STATE_TRANSITION',
  'illegal lifecycle transition is rejected'
);
select lives_ok(
  $$update integration.import_jobs set status_code = 'VALIDATING' where id = '00000000-0000-4060-8000-000000000101'$$,
  'legal lifecycle transition is accepted'
);
select lives_ok(
  $$update integration.import_jobs set status_code = 'READY' where id = '00000000-0000-4060-8000-000000000101'$$,
  'validation completion transition is accepted'
);

select is((select position('RESERVE' in obj_description('integration.import_jobs'::regclass)) > 0), true, 'job contract records canonical reservation event boundary');

select * from finish();
rollback;
