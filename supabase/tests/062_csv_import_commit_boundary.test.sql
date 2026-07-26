begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('integration', 'import_commit_commands', 'import commit command ledger exists');
select has_table('integration', 'marketplace_csv_event_identities', 'stable CSV event identity table exists');
select has_table('integration', 'import_event_results', 'per-job event result audit table exists');
select has_column('integration', 'import_rows', 'commit_result_id', 'row audit result linkage exists');
select function_returns(
  'api',
  'commit_marketplace_csv_import_job',
  array['uuid', 'uuid', 'text', 'boolean'],
  'jsonb',
  'trusted CSV commit boundary exists'
);
select ok(
  has_function_privilege('service_role', 'api.commit_marketplace_csv_import_job(uuid,uuid,text,boolean)', 'EXECUTE'),
  'only service_role has direct commit boundary access'
);
select ok(
  not has_function_privilege('authenticated', 'api.commit_marketplace_csv_import_job(uuid,uuid,text,boolean)', 'EXECUTE'),
  'authenticated cannot commit CSV jobs directly'
);
select ok(
  not has_function_privilege('anon', 'api.commit_marketplace_csv_import_job(uuid,uuid,text,boolean)', 'EXECUTE'),
  'anon cannot commit CSV jobs'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, auth, app, catalog, integration, operations, api, extensions']
   from pg_proc where oid = 'api.commit_marketplace_csv_import_job(uuid,uuid,text,boolean)'::regprocedure),
  'commit boundary uses a fixed search_path'
);
select ok(
  not has_table_privilege('authenticated', 'integration.import_commit_commands', 'INSERT')
    and not has_table_privilege('authenticated', 'integration.import_event_results', 'INSERT')
    and not has_table_privilege('authenticated', 'integration.marketplace_csv_event_identities', 'INSERT'),
  'authenticated cannot write commit audit tables directly'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'integration.import_commit_commands'::regclass)
    and (select relforcerowsecurity from pg_class where oid = 'integration.import_commit_commands'::regclass),
  'commit commands keep RLS and forced RLS enabled'
);
select ok(
  (select reloptions @> array['security_invoker=true', 'security_barrier=true']
   from pg_class where oid = 'api.import_commit_read_model'::regclass),
  'commit read model is an invoker security barrier view'
);

insert into app.organizations(id, code, name, timezone, is_active, created_at)
values ('00000000-0000-4062-8000-000000000001', 'PGTAP_CSV_COMMIT_062', 'CSV Commit 062', 'Asia/Jakarta', true, '2026-07-26 08:00:00+07');

insert into catalog.channels(id, code, name, is_marketplace, is_active)
values ('00000000-0000-4062-8000-000000000011', 'CSV062', 'CSV Commit Channel 062', true, true);

insert into catalog.products(id, organization_id, sku, name, created_at)
values
  ('00000000-0000-4062-8000-000000000101', '00000000-0000-4062-8000-000000000001', 'CSV062-SINGLE', 'CSV Commit Single', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4062-8000-000000000102', '00000000-0000-4062-8000-000000000001', 'CSV062-BUNDLE-A', 'CSV Commit Bundle A', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4062-8000-000000000103', '00000000-0000-4062-8000-000000000001', 'CSV062-BUNDLE-B', 'CSV Commit Bundle B', '2026-07-26 08:00:00+07');

insert into inventory.stock_product_positions(organization_id, product_id, sellable_qty)
values
  ('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000101', 100),
  ('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000102', 100),
  ('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000103', 100);

insert into catalog.marketplace_listings(id, organization_id, channel_id, external_listing_code, display_name, listing_type_code, status_code, created_at, updated_at, row_version)
values
  ('00000000-0000-4062-8000-000000000201', '00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000011', 'SINGLE-062', 'CSV Single 062', 'SINGLE', 'ACTIVE', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', 1),
  ('00000000-0000-4062-8000-000000000202', '00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000011', 'BUNDLE-062', 'CSV Bundle 062', 'BUNDLE', 'ACTIVE', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', 1);

insert into catalog.marketplace_single_listing_versions(id, organization_id, listing_id, version, product_id, status_code, effective_from, activated_at, created_at, updated_at, row_version, schema_version)
values ('00000000-0000-4062-8000-000000000211', '00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000201', 1, '00000000-0000-4062-8000-000000000101', 'ACTIVE', '2026-07-01 00:00:00+07', '2026-07-01 00:00:00+07', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', 1, 1);

insert into catalog.bundle_recipes(id, organization_id, channel_id, external_listing_sku, external_listing_name, version, effective_from, is_active, created_at)
values ('00000000-0000-4062-8000-000000000221', '00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000011', 'BUNDLE-062', 'CSV Bundle 062', 1, '2026-07-01 00:00:00+07', true, '2026-07-26 08:00:00+07');

insert into catalog.bundle_components(bundle_recipe_id, product_id, component_qty, line_no)
values
  ('00000000-0000-4062-8000-000000000221', '00000000-0000-4062-8000-000000000102', 2, 1),
  ('00000000-0000-4062-8000-000000000221', '00000000-0000-4062-8000-000000000103', 1, 2);

insert into integration.import_jobs(id, organization_id, created_by_process, import_type_code, template_version, status_code, original_file_name, object_path, detected_mime, file_size_bytes, file_sha256, job_command_key, job_request_hash, row_count, valid_row_count, created_at)
values
  ('00000000-0000-4062-8000-000000000301', '00000000-0000-4062-8000-000000000001', 'pgtap-062', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED', 'commit.csv', '00000000-0000-4062-8000-000000000001/00000000-0000-4062-8000-000000000301/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.csv', 'text/csv', 256, repeat('a', 64), 'CSV062-JOB-301', repeat('1', 64), 2, 2, '2026-07-26 09:00:00+07'),
  ('00000000-0000-4062-8000-000000000302', '00000000-0000-4062-8000-000000000001', 'pgtap-062', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED', 'replay.csv', '00000000-0000-4062-8000-000000000001/00000000-0000-4062-8000-000000000302/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.csv', 'text/csv', 256, repeat('b', 64), 'CSV062-JOB-302', repeat('2', 64), 1, 1, '2026-07-26 09:00:01+07'),
  ('00000000-0000-4062-8000-000000000303', '00000000-0000-4062-8000-000000000001', 'pgtap-062', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED', 'conflict.csv', '00000000-0000-4062-8000-000000000001/00000000-0000-4062-8000-000000000303/cccccccccccccccccccccccccccccccc.csv', 'text/csv', 256, repeat('c', 64), 'CSV062-JOB-303', repeat('3', 64), 1, 1, '2026-07-26 09:00:02+07'),
  ('00000000-0000-4062-8000-000000000304', '00000000-0000-4062-8000-000000000001', 'pgtap-062', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED', 'rollback.csv', '00000000-0000-4062-8000-000000000001/00000000-0000-4062-8000-000000000304/dddddddddddddddddddddddddddddddd.csv', 'text/csv', 256, repeat('d', 64), 'CSV062-JOB-304', repeat('4', 64), 2, 2, '2026-07-26 09:00:03+07');

insert into integration.import_rows(organization_id, import_job_id, row_number, raw_row, normalized_row, row_fingerprint, validation_status_code, processing_status_code, external_event_ref, canonical_idempotency_key, canonical_line_count, event_group_key, expansion_preview)
values
  ('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000301', 2, '{"line":"single"}', '{"channel_code":"CSV062","external_event_ref":"EVT-062-SINGLE","external_order_ref":"ORD-062-SINGLE","source_status":"READY_TO_SHIP","occurred_at":"2026-07-26T09:00:00Z","received_at":"2026-07-26T09:01:00Z","source_line_ref":"LINE-SINGLE","external_listing_code":"SINGLE-062","listing_quantity":1}', repeat('1', 64), 'VALID', 'PENDING', 'EVT-062-SINGLE', 'csv:062:single', 1, 'CSV062|EVT-062-SINGLE', '{"listingType":"SINGLE","stockEffect":"NONE"}'),
  ('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000301', 3, '{"line":"bundle"}', '{"channel_code":"CSV062","external_event_ref":"EVT-062-BUNDLE","external_order_ref":"ORD-062-BUNDLE","source_status":"READY_TO_SHIP","occurred_at":"2026-07-26T09:00:00Z","received_at":"2026-07-26T09:01:00Z","source_line_ref":"LINE-BUNDLE","external_listing_code":"BUNDLE-062","listing_quantity":1}', repeat('2', 64), 'VALID', 'PENDING', 'EVT-062-BUNDLE', 'csv:062:bundle', 2, 'CSV062|EVT-062-BUNDLE', '{"listingType":"BUNDLE","stockEffect":"NONE"}');
insert into integration.import_rows(organization_id, import_job_id, row_number, raw_row, normalized_row, row_fingerprint, validation_status_code, processing_status_code, external_event_ref, canonical_idempotency_key, canonical_line_count, event_group_key, expansion_preview)
values
  ('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000302', 2, '{"line":"replay"}', '{"channel_code":"CSV062","external_event_ref":"EVT-062-SINGLE","external_order_ref":"ORD-062-SINGLE","source_status":"READY_TO_SHIP","occurred_at":"2026-07-26T09:00:00Z","received_at":"2026-07-26T09:01:00Z","source_line_ref":"LINE-SINGLE","external_listing_code":"SINGLE-062","listing_quantity":1}', repeat('3', 64), 'VALID', 'PENDING', 'EVT-062-SINGLE', 'csv:062:single', 1, 'CSV062|EVT-062-SINGLE', '{"listingType":"SINGLE","stockEffect":"NONE"}'),
  ('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000303', 2, '{"line":"conflict"}', '{"channel_code":"CSV062","external_event_ref":"EVT-062-SINGLE","external_order_ref":"ORD-062-SINGLE","source_status":"READY_TO_SHIP","occurred_at":"2026-07-26T09:00:00Z","received_at":"2026-07-26T09:01:00Z","source_line_ref":"LINE-SINGLE","external_listing_code":"SINGLE-062","listing_quantity":2}', repeat('4', 64), 'VALID', 'PENDING', 'EVT-062-SINGLE', 'csv:062:single-conflict', 1, 'CSV062|EVT-062-SINGLE-CONFLICT', '{"listingType":"SINGLE","stockEffect":"NONE"}');

insert into integration.import_rows(organization_id, import_job_id, row_number, raw_row, normalized_row, row_fingerprint, validation_status_code, processing_status_code, external_event_ref, canonical_idempotency_key, canonical_line_count, event_group_key, expansion_preview)
values
  ('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000304', 2, '{"line":"rollback-valid"}', '{"channel_code":"CSV062","external_event_ref":"EVT-062-ROLLBACK-VALID","external_order_ref":"ORD-062-ROLLBACK-VALID","source_status":"READY_TO_SHIP","occurred_at":"2026-07-26T09:00:00Z","received_at":"2026-07-26T09:01:00Z","source_line_ref":"LINE-ROLLBACK-VALID","external_listing_code":"SINGLE-062","listing_quantity":1}', repeat('5', 64), 'VALID', 'PENDING', 'EVT-062-ROLLBACK-VALID', 'csv:062:rollback-valid', 1, 'CSV062|EVT-062-ROLLBACK-VALID', '{"listingType":"SINGLE","stockEffect":"NONE"}'),
  ('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000304', 3, '{"line":"rollback-invalid"}', '{"channel_code":"CSV062","external_event_ref":"EVT-062-ROLLBACK-INVALID","external_order_ref":"ORD-062-ROLLBACK-INVALID","source_status":"READY_TO_SHIP","occurred_at":"2026-07-26T09:00:00Z","received_at":"2026-07-26T09:01:00Z","source_line_ref":"LINE-ROLLBACK-INVALID","external_listing_code":"UNKNOWN-062","listing_quantity":1}', repeat('6', 64), 'VALID', 'PENDING', 'EVT-062-ROLLBACK-INVALID', 'csv:062:rollback-invalid', 0, 'CSV062|EVT-062-ROLLBACK-INVALID', '{"listingType":"UNKNOWN","stockEffect":"NONE"}');

update integration.import_jobs
set status_code = 'VALIDATING'
where organization_id = '00000000-0000-4062-8000-000000000001'
  and id in ('00000000-0000-4062-8000-000000000301', '00000000-0000-4062-8000-000000000302', '00000000-0000-4062-8000-000000000303', '00000000-0000-4062-8000-000000000304');
update integration.import_jobs
set status_code = 'READY'
where organization_id = '00000000-0000-4062-8000-000000000001'
  and id in ('00000000-0000-4062-8000-000000000301', '00000000-0000-4062-8000-000000000302', '00000000-0000-4062-8000-000000000303', '00000000-0000-4062-8000-000000000304');

select is(
  api.commit_marketplace_csv_import_job('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000301', 'commit-062-301', true) ->> 'status',
  'COMPLETED', 'two grouped events commit atomically through canonical RESERVE boundary'
);
select is((select status_code from integration.import_jobs where id = '00000000-0000-4062-8000-000000000301'), 'COMPLETED', 'successful job reaches COMPLETED');
select is((select count(*) from integration.import_event_results where import_job_id = '00000000-0000-4062-8000-000000000301'), 2::bigint, 'each grouped event has an audit result');
select is((select count(*) from integration.import_rows where import_job_id = '00000000-0000-4062-8000-000000000301' and processing_status_code = 'PROCESSED'), 2::bigint, 'all rows are processed together');
select is((select count(*) from operations.marketplace_events where organization_id = '00000000-0000-4062-8000-000000000001' and external_event_ref in ('EVT-062-SINGLE', 'EVT-062-BUNDLE')), 2::bigint, 'canonical events are created without direct table writes');
select is((select count(*) from inventory.stock_reservations reservation join operations.marketplace_orders order_header on order_header.id = reservation.order_id where order_header.organization_id = '00000000-0000-4062-8000-000000000001' and order_header.external_order_ref in ('ORD-062-SINGLE', 'ORD-062-BUNDLE')), 3::bigint, 'canonical reservation creates one reservation per product component');
select is((select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4062-8000-000000000001' and source_type_code = 'MARKETPLACE'), 0::bigint, 'RESERVE commit remains physical-stock neutral');
select is((select sum(sellable_qty) from inventory.stock_product_positions where organization_id = '00000000-0000-4062-8000-000000000001' and product_id in ('00000000-0000-4062-8000-000000000101', '00000000-0000-4062-8000-000000000102', '00000000-0000-4062-8000-000000000103')), 300::numeric, 'RESERVE commit does not change physical sellable projection');

select is(
  api.commit_marketplace_csv_import_job('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000301', 'commit-062-301', true) ->> 'status',
  'EXACT_REPLAY', 'exact job commit replay returns stored response'
);
select is((select count(*) from integration.import_event_results where import_job_id = '00000000-0000-4062-8000-000000000301'), 2::bigint, 'exact job replay does not duplicate event results');

select is(
  api.commit_marketplace_csv_import_job('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000302', 'commit-062-302', true) ->> 'status',
  'COMPLETED', 'same external event in another file replays safely'
);
select is((select count(*) from operations.marketplace_events where organization_id = '00000000-0000-4062-8000-000000000001' and external_event_ref = 'EVT-062-SINGLE'), 1::bigint, 'same external event across files has one domain effect');
select is((select status_code from integration.import_event_results where import_job_id = '00000000-0000-4062-8000-000000000302'), 'REPLAYED', 'cross-file event result is marked REPLAYED');

select is(
  api.commit_marketplace_csv_import_job('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000303', 'commit-062-303', true) ->> 'status',
  'COMMIT_FAILED', 'changed external event payload is rejected without a second effect'
);
select is((select status_code from integration.import_jobs where id = '00000000-0000-4062-8000-000000000303'), 'COMMIT_FAILED', 'external identity conflict is auditable on the job');
select is((select count(*) from operations.marketplace_events where organization_id = '00000000-0000-4062-8000-000000000001' and external_event_ref = 'EVT-062-SINGLE'), 1::bigint, 'external conflict does not create another event');
update integration.import_rows
set normalized_row = normalized_row || jsonb_build_object('note', 'changed after command')
where import_job_id = '00000000-0000-4062-8000-000000000303';
select throws_ok(
  $$select api.commit_marketplace_csv_import_job('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000303', 'commit-062-303', true)$$,
  'P0001', 'CSV_IMPORT_COMMIT_KEY_REUSED', 'same commit key with changed basis is a conflict'
);

select is(
  api.commit_marketplace_csv_import_job('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000304', 'commit-062-304', true) ->> 'status',
  'COMMIT_FAILED', 'later canonical failure rolls back the whole import batch'
);
select is((select status_code from integration.import_jobs where id = '00000000-0000-4062-8000-000000000304'), 'COMMIT_FAILED', 'failed batch is marked COMMIT_FAILED');
select is((select count(*) from operations.marketplace_orders where organization_id = '00000000-0000-4062-8000-000000000001' and external_order_ref = 'ORD-062-ROLLBACK-VALID'), 0::bigint, 'failed batch leaves no partial order');
select is((select count(*) from inventory.stock_reservations reservation join operations.marketplace_orders order_header on order_header.id = reservation.order_id where order_header.organization_id = '00000000-0000-4062-8000-000000000001' and order_header.external_order_ref = 'ORD-062-ROLLBACK-VALID'), 0::bigint, 'failed batch leaves no partial reservation');
select is((select count(*) from integration.import_rows where import_job_id = '00000000-0000-4062-8000-000000000304' and processing_status_code = 'PROCESSED'), 0::bigint, 'failed batch leaves no processed rows');
select is((select count(*) from integration.import_commit_commands where import_job_id = '00000000-0000-4062-8000-000000000304' and status_code = 'FAILED'), 1::bigint, 'failed command stores safe failure evidence');

update integration.import_rows
set normalized_row = normalized_row || jsonb_build_object('external_listing_code', 'SINGLE-062'),
    canonical_line_count = 1,
    expansion_preview = '{"listingType":"SINGLE","stockEffect":"NONE"}'::jsonb
where import_job_id = '00000000-0000-4062-8000-000000000304'
  and row_number = 3;
select is(
  api.commit_marketplace_csv_import_job('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000304', 'commit-062-304-retry', true) ->> 'status',
  'COMPLETED', 'COMMIT_FAILED job can recover with a new command after the blocking mapping is fixed'
);
select is((select count(*) from integration.import_rows where import_job_id = '00000000-0000-4062-8000-000000000304' and processing_status_code = 'PROCESSED'), 2::bigint, 'recovery processes the full batch, never only the failed event');

select throws_ok(
  $$select api.commit_marketplace_csv_import_job('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000304', 'commit-062-304', true)$$,
  'P0001', 'CSV_IMPORT_COMMIT_KEY_REUSED', 'failed command key cannot be reused after recovery basis changes'
);
select throws_ok(
  $$select api.commit_marketplace_csv_import_job('00000000-0000-4062-8000-000000000002', '00000000-0000-4062-8000-000000000301', 'commit-062-cross-org', true)$$,
  'P0001', 'CSV_IMPORT_JOB_NOT_FOUND', 'cross-organization job is not found safely'
);
select throws_ok(
  $$select api.commit_marketplace_csv_import_job('00000000-0000-4062-8000-000000000001', '00000000-0000-4062-8000-000000000301', 'commit-062-no-confirm', false)$$,
  '22023', 'CSV_IMPORT_COMMIT_CONFIRMATION_REQUIRED', 'commit confirmation is mandatory'
);

select is((select count(*) from api.import_event_result_read_model where import_job_id = '00000000-0000-4062-8000-000000000301'), 2::bigint, 'event result read model exposes audit linkage');
select is((select count(*) from integration.import_event_results result join integration.import_jobs job on job.organization_id = result.organization_id and job.id = result.import_job_id where result.organization_id <> job.organization_id), 0::bigint, 'audit linkage cannot cross organization');

select * from finish();
rollback;
