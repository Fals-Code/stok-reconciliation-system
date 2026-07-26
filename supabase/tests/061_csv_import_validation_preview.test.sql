begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_column('integration', 'import_rows', 'event_group_key', 'event grouping identity is staged');
select has_column('integration', 'import_rows', 'expansion_preview', 'canonical expansion preview is staged');
select has_view('api', 'import_row_preview_read_model', 'row preview read model exists');
select function_returns(
  'api',
  'validate_marketplace_csv_import_job',
  array['uuid', 'uuid', 'text', 'jsonb', 'jsonb'],
  'jsonb',
  'validation and preview RPC exists'
);
select ok(
  has_function_privilege('service_role', 'api.validate_marketplace_csv_import_job(uuid,uuid,text,jsonb,jsonb)', 'EXECUTE'),
  'validation RPC is available only to the server boundary'
);
select ok(
  not has_function_privilege('authenticated', 'api.validate_marketplace_csv_import_job(uuid,uuid,text,jsonb,jsonb)', 'EXECUTE'),
  'authenticated cannot submit arbitrary staging rows directly'
);
select ok(
  not has_function_privilege('anon', 'api.validate_marketplace_csv_import_job(uuid,uuid,text,jsonb,jsonb)', 'EXECUTE'),
  'anon cannot validate staging rows'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, auth, app, catalog, integration, operations, api, extensions']
   from pg_proc
   where oid = 'api.validate_marketplace_csv_import_job(uuid,uuid,text,jsonb,jsonb)'::regprocedure),
  'validation SECURITY DEFINER uses a fixed search_path'
);
select ok(
  (select reloptions @> array['security_invoker=true', 'security_barrier=true']
   from pg_class where oid = 'api.import_row_preview_read_model'::regclass),
  'preview read model is an invoker security-barrier view'
);

insert into app.organizations(id, code, name, timezone, is_active, created_at)
values ('00000000-0000-4061-8000-000000000001', 'PGTAP_CSV_061', 'CSV Preview 061', 'Asia/Jakarta', true, '2026-07-26 08:00:00+07');

insert into catalog.channels(id, code, name, is_marketplace, is_active)
values ('00000000-0000-4061-8000-000000000011', 'CSV061', 'CSV Preview Channel 061', true, true);

insert into catalog.products(id, organization_id, sku, name, created_at)
values
  ('00000000-0000-4061-8000-000000000101', '00000000-0000-4061-8000-000000000001', 'CSV061-SINGLE', 'CSV Preview Single', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4061-8000-000000000102', '00000000-0000-4061-8000-000000000001', 'CSV061-BUNDLE-A', 'CSV Preview Bundle A', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4061-8000-000000000103', '00000000-0000-4061-8000-000000000001', 'CSV061-BUNDLE-B', 'CSV Preview Bundle B', '2026-07-26 08:00:00+07');

insert into catalog.marketplace_listings(id, organization_id, channel_id, external_listing_code, display_name, listing_type_code, status_code, created_at, updated_at, row_version)
values
  ('00000000-0000-4061-8000-000000000201', '00000000-0000-4061-8000-000000000001', '00000000-0000-4061-8000-000000000011', 'SINGLE-061', 'CSV Single', 'SINGLE', 'ACTIVE', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', 1),
  ('00000000-0000-4061-8000-000000000202', '00000000-0000-4061-8000-000000000001', '00000000-0000-4061-8000-000000000011', 'BUNDLE-061', 'CSV Bundle', 'BUNDLE', 'ACTIVE', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', 1);

insert into catalog.marketplace_single_listing_versions(id, organization_id, listing_id, version, product_id, status_code, effective_from, activated_at, created_at, updated_at, row_version, schema_version)
values ('00000000-0000-4061-8000-000000000211', '00000000-0000-4061-8000-000000000001', '00000000-0000-4061-8000-000000000201', 1, '00000000-0000-4061-8000-000000000101', 'ACTIVE', '2026-07-01 00:00:00+07', '2026-07-01 00:00:00+07', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', 1, 1);

insert into catalog.bundle_recipes(id, organization_id, channel_id, external_listing_sku, external_listing_name, version, effective_from, is_active, created_at)
values ('00000000-0000-4061-8000-000000000221', '00000000-0000-4061-8000-000000000001', '00000000-0000-4061-8000-000000000011', 'BUNDLE-061', 'CSV Bundle', 1, '2026-07-01 00:00:00+07', true, '2026-07-26 08:00:00+07');

insert into catalog.bundle_components(bundle_recipe_id, product_id, component_qty, line_no)
values
  ('00000000-0000-4061-8000-000000000221', '00000000-0000-4061-8000-000000000102', 2, 1),
  ('00000000-0000-4061-8000-000000000221', '00000000-0000-4061-8000-000000000103', 1, 2);

insert into integration.import_jobs(
  id, organization_id, created_by_process, import_type_code, template_version, status_code,
  original_file_name, object_path, detected_mime, file_size_bytes, file_sha256,
  job_command_key, job_request_hash, created_at
)
values
  ('00000000-0000-4061-8000-000000000301', '00000000-0000-4061-8000-000000000001', 'pgtap-061', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED', 'valid.csv', '00000000-0000-4061-8000-000000000001/00000000-0000-4061-8000-000000000301/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.csv', 'text/csv', 256, repeat('a', 64), 'CSV061-VALID', repeat('1', 64), '2026-07-26 09:00:00+07'),
  ('00000000-0000-4061-8000-000000000302', '00000000-0000-4061-8000-000000000001', 'pgtap-061', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED', 'invalid.csv', '00000000-0000-4061-8000-000000000001/00000000-0000-4061-8000-000000000302/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.csv', 'text/csv', 256, repeat('b', 64), 'CSV061-INVALID', repeat('2', 64), '2026-07-26 09:00:01+07'),
  ('00000000-0000-4061-8000-000000000303', '00000000-0000-4061-8000-000000000001', 'pgtap-061', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED', 'duplicate.csv', '00000000-0000-4061-8000-000000000001/00000000-0000-4061-8000-000000000303/cccccccccccccccccccccccccccccccc.csv', 'text/csv', 256, repeat('c', 64), 'CSV061-DUPLICATE', repeat('3', 64), '2026-07-26 09:00:02+07');

create temporary table csv_061_before as
select
  (select count(*) from inventory.stock_reservations where organization_id = '00000000-0000-4061-8000-000000000001') as reservations,
  (select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4061-8000-000000000001') as transactions,
  (select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4061-8000-000000000001') as ledger_entries,
  (select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4061-8000-000000000001') as positions,
  (select count(*) from operations.marketplace_orders where organization_id = '00000000-0000-4061-8000-000000000001') as orders;

select is(
  api.validate_marketplace_csv_import_job(
    '00000000-0000-4061-8000-000000000001',
    '00000000-0000-4061-8000-000000000301',
    repeat('a', 64),
    jsonb_build_array(
      jsonb_build_object(
        'rowNumber', 2,
        'rawRow', jsonb_build_object('external_listing_code', 'SINGLE-061'),
        'normalizedRow', jsonb_build_object('channel_code', 'CSV061', 'external_event_ref', 'EVT-061', 'external_order_ref', 'ORD-061', 'source_status', 'READY_TO_SHIP', 'occurred_at', '2026-07-26T09:00:00Z', 'received_at', '2026-07-26T09:01:00Z', 'external_listing_code', 'SINGLE-061', 'listing_quantity', 3),
        'rowFingerprint', repeat('d', 64), 'eventGroupKey', 'CSV061|EVT-061', 'externalEventRef', 'EVT-061', 'canonicalIdempotencyKey', 'csv:061:EVT-061', 'errors', '[]'::jsonb
      ),
      jsonb_build_object(
        'rowNumber', 3,
        'rawRow', jsonb_build_object('external_listing_code', 'BUNDLE-061'),
        'normalizedRow', jsonb_build_object('channel_code', 'CSV061', 'external_event_ref', 'EVT-062', 'external_order_ref', 'ORD-062', 'source_status', 'READY_TO_SHIP', 'occurred_at', '2026-07-26T09:00:00Z', 'received_at', '2026-07-26T09:01:00Z', 'external_listing_code', 'BUNDLE-061', 'listing_quantity', 2),
        'rowFingerprint', repeat('e', 64), 'eventGroupKey', 'CSV061|EVT-062', 'externalEventRef', 'EVT-062', 'canonicalIdempotencyKey', 'csv:061:EVT-062', 'errors', '[]'::jsonb
      )
    ),
    '[]'::jsonb
  ) ->> 'status',
  'READY',
  'valid SINGLE and versioned BUNDLE rows reach READY without posting'
);
select is((select status_code from integration.import_jobs where id = '00000000-0000-4061-8000-000000000301'), 'READY', 'valid job reaches READY');
select is((select count(*) from api.import_row_preview_read_model where import_job_id = '00000000-0000-4061-8000-000000000301'), 2::bigint, 'preview rows are readable');
select is((select expansion_preview->>'listingType' from api.import_row_preview_read_model where row_number = 2), 'SINGLE', 'SINGLE preview is canonical');
select is((select expansion_preview->>'listingType' from api.import_row_preview_read_model where row_number = 3), 'BUNDLE', 'BUNDLE preview is canonical');
select is((select expansion_preview->>'stockEffect' from api.import_row_preview_read_model where row_number = 3), 'NONE', 'preview has no stock effect');
select is((select canonical_line_count from api.import_row_preview_read_model where row_number = 3), 2, 'bundle preview exposes expanded component count');

select is(
  api.validate_marketplace_csv_import_job(
    '00000000-0000-4061-8000-000000000001',
    '00000000-0000-4061-8000-000000000301',
    repeat('a', 64),
    '[]'::jsonb,
    '[]'::jsonb
  ) ->> 'status',
  'READY',
  'repeated validation replays existing READY result'
);
select is((select count(*) from integration.import_rows where import_job_id = '00000000-0000-4061-8000-000000000301'), 2::bigint, 'repeated validation does not duplicate rows');

select is(
  api.validate_marketplace_csv_import_job(
    '00000000-0000-4061-8000-000000000001',
    '00000000-0000-4061-8000-000000000302',
    repeat('b', 64),
    jsonb_build_array(jsonb_build_object(
      'rowNumber', 2,
      'rawRow', jsonb_build_object('external_listing_code', 'UNKNOWN-061'),
      'normalizedRow', jsonb_build_object('channel_code', 'CSV061', 'external_event_ref', 'EVT-INVALID', 'external_order_ref', 'ORD-INVALID', 'source_status', 'READY_TO_SHIP', 'occurred_at', '2026-07-26T09:00:00Z', 'received_at', '2026-07-26T09:01:00Z', 'external_listing_code', 'UNKNOWN-061', 'listing_quantity', 1),
      'rowFingerprint', repeat('f', 64), 'eventGroupKey', 'CSV061|EVT-INVALID', 'externalEventRef', 'EVT-INVALID', 'canonicalIdempotencyKey', 'csv:061:INVALID', 'errors', '[]'::jsonb
    )),
    '[]'::jsonb
  ) ->> 'status',
  'VALIDATION_FAILED',
  'unknown listing creates a structured validation failure'
);
select ok((select validation_status_code = 'INVALID' and validation_errors->0->>'code' = 'MARKETPLACE_LISTING_NOT_FOUND' from integration.import_rows where import_job_id = '00000000-0000-4061-8000-000000000302'), 'canonical mapping failure is retained as safe structured error');

select is(
  api.validate_marketplace_csv_import_job(
    '00000000-0000-4061-8000-000000000001',
    '00000000-0000-4061-8000-000000000303',
    repeat('c', 64),
    jsonb_build_array(
      jsonb_build_object('rowNumber', 2, 'rawRow', '{}'::jsonb, 'normalizedRow', '{}'::jsonb, 'rowFingerprint', repeat('9', 64), 'errors', '[]'::jsonb),
      jsonb_build_object('rowNumber', 3, 'rawRow', '{}'::jsonb, 'normalizedRow', '{}'::jsonb, 'rowFingerprint', repeat('9', 64), 'errors', '[]'::jsonb)
    ),
    '[]'::jsonb
  ) ->> 'status',
  'VALIDATION_FAILED',
  'duplicate row fingerprint fails validation without domain effect'
);
select is((select count(*) from integration.import_rows where import_job_id = '00000000-0000-4061-8000-000000000303'), 2::bigint, 'duplicate rows remain auditable');

select is((select count(*) from inventory.stock_reservations where organization_id = '00000000-0000-4061-8000-000000000001'), (select reservations from csv_061_before), 'preview does not create reservations');
select is((select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4061-8000-000000000001'), (select transactions from csv_061_before), 'preview does not create transactions');
select is((select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4061-8000-000000000001'), (select ledger_entries from csv_061_before), 'preview does not write ledger');
select is((select count(*) from inventory.stock_product_positions where organization_id = '00000000-0000-4061-8000-000000000001'), (select positions from csv_061_before), 'preview does not change projection');
select is((select count(*) from operations.marketplace_orders where organization_id = '00000000-0000-4061-8000-000000000001'), (select orders from csv_061_before), 'preview does not create marketplace orders');

select throws_ok(
  $$select api.validate_marketplace_csv_import_job('00000000-0000-4061-8000-000000000002', '00000000-0000-4061-8000-000000000301', repeat('a', 64), '[]'::jsonb, '[]'::jsonb)$$,
  'P0001',
  'CSV_IMPORT_JOB_NOT_FOUND',
  'cross-organization job is not found safely'
);

select * from finish();
rollback;
