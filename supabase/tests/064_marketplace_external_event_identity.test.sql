begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function('operations', 'marketplace_reservation_external_event_hash', array['uuid', 'text', 'text', 'text', 'text', 'timestamp with time zone', 'timestamp with time zone', 'jsonb', 'text', 'integer']::text[], 'shared canonical marketplace external-event hash boundary exists');
select function_returns('api', 'reserve_marketplace_listing_event', array['uuid', 'text', 'text', 'text', 'text', 'text', 'timestamp with time zone', 'timestamp with time zone', 'jsonb', 'text', 'jsonb', 'jsonb', 'integer']::text[], 'jsonb', 'canonical reservation wrapper preserves its public contract');
select ok((select proconfig @> array['search_path=pg_catalog, auth, app, catalog, inventory, operations, api, extensions'] from pg_proc where oid = 'api.reserve_marketplace_listing_event(uuid,text,text,text,text,text,timestamp with time zone,timestamp with time zone,jsonb,text,jsonb,jsonb,integer)'::regprocedure), 'shared canonical reservation boundary has a fixed search_path');
select ok(not has_function_privilege('anon', 'api.reserve_marketplace_listing_event(uuid,text,text,text,text,text,timestamp with time zone,timestamp with time zone,jsonb,text,jsonb,jsonb,integer)', 'EXECUTE'), 'anon cannot call canonical reservation boundary');
select ok(not has_function_privilege('authenticated', 'api.reserve_marketplace_listing_event_apply(uuid,text,text,text,text,text,timestamp with time zone,timestamp with time zone,jsonb,text,jsonb,jsonb,integer)', 'EXECUTE'), 'legacy apply implementation cannot bypass shared canonical claim');
select ok(not has_function_privilege('authenticated', 'operations.marketplace_reservation_external_event_hash(uuid,text,text,text,text,timestamp with time zone,timestamp with time zone,jsonb,text,integer)', 'EXECUTE'), 'hash helper is internal only');

insert into app.organizations(id, code, name, timezone, is_active, created_at)
values ('00000000-0000-4064-8000-000000000001', 'PGTAP_EXTERNAL_064', 'External Event 064', 'Asia/Jakarta', true, '2026-07-26 08:00:00+07');
insert into catalog.channels(id, code, name, is_marketplace, is_active)
values ('00000000-0000-4064-8000-000000000011', 'CSV064', 'External Identity Channel 064', true, true);
insert into catalog.products(id, organization_id, sku, name, created_at)
values ('00000000-0000-4064-8000-000000000101', '00000000-0000-4064-8000-000000000001', 'CSV064-SINGLE', 'External Identity Single', '2026-07-26 08:00:00+07');
insert into inventory.stock_product_positions(organization_id, product_id, sellable_qty)
values ('00000000-0000-4064-8000-000000000001', '00000000-0000-4064-8000-000000000101', 100);
insert into catalog.marketplace_listings(id, organization_id, channel_id, external_listing_code, display_name, listing_type_code, status_code, created_at, updated_at, row_version)
values ('00000000-0000-4064-8000-000000000201', '00000000-0000-4064-8000-000000000001', '00000000-0000-4064-8000-000000000011', 'SINGLE-064', 'External Identity Listing', 'SINGLE', 'ACTIVE', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', 1);
insert into catalog.marketplace_single_listing_versions(id, organization_id, listing_id, version, product_id, status_code, effective_from, activated_at, created_at, updated_at, row_version, schema_version)
values ('00000000-0000-4064-8000-000000000211', '00000000-0000-4064-8000-000000000001', '00000000-0000-4064-8000-000000000201', 1, '00000000-0000-4064-8000-000000000101', 'ACTIVE', '2026-07-01 00:00:00+07', '2026-07-01 00:00:00+07', '2026-07-26 08:00:00+07', '2026-07-26 08:00:00+07', 1, 1);

create temporary table external_results(kind text primary key, result jsonb not null) on commit drop;
insert into external_results(kind, result)
values ('DIRECT_CREATED', api.reserve_marketplace_listing_event(
  '00000000-0000-4064-8000-000000000001', 'DIRECT-064-ONE', 'CSV064', 'EVT-064-DIRECT', 'ORD-064-DIRECT', 'READY_TO_SHIP',
  '2026-07-26 09:00:00+07', '2026-07-26 09:01:00+07',
  jsonb_build_array(jsonb_build_object('sourceLineRef', 'LINE-1', 'externalListingCode', 'SINGLE-064', 'listingQuantity', 1, 'sourceStatus', 'READY_TO_SHIP')),
  'Semantik sama.', jsonb_build_object('adapter', 'SIMULATOR', 'volatile', 'not-hashed'), jsonb_build_object('adapter', 'SIMULATOR'), 1
));
select is((select result ->> 'externalEventOutcome' from external_results where kind = 'DIRECT_CREATED'), 'CREATED', 'direct canonical reservation claims a new external event');

create temporary table identity_jobs(id uuid primary key, event_ref text not null, order_ref text not null, qty integer not null) on commit drop;
insert into identity_jobs values
  ('00000000-0000-4064-8000-000000000301', 'EVT-064-DIRECT', 'ORD-064-DIRECT', 1),
  ('00000000-0000-4064-8000-000000000302', 'EVT-064-CSV', 'ORD-064-CSV', 1),
  ('00000000-0000-4064-8000-000000000303', 'EVT-064-DIRECT', 'ORD-064-DIRECT', 2),
  ('00000000-0000-4064-8000-000000000304', 'EVT-064-GROUP-NEW', 'ORD-064-GROUP-NEW', 1),
  ('00000000-0000-4064-8000-000000000305', 'EVT-064-GROUP-CONFLICT', 'ORD-064-DIRECT', 2);
insert into integration.import_jobs(id, organization_id, created_by_process, import_type_code, template_version, status_code, original_file_name, object_path, detected_mime, file_size_bytes, file_sha256, job_command_key, job_request_hash, row_count, valid_row_count, created_at)
select id, '00000000-0000-4064-8000-000000000001', 'pgtap-064', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED',
  'commit.csv', '00000000-0000-4064-8000-000000000001/' || id::text || '/' || repeat('a', 32) || '.csv', 'text/csv', 256,
  lpad(to_hex(row_number() over (order by id)), 64, 'a'), 'CSV064-JOB-' || right(id::text, 3), lpad(to_hex(row_number() over (order by id) + 32), 64, 'b'), 1, 1, '2026-07-26 09:10:00+07'
from identity_jobs;
insert into integration.import_rows(organization_id, import_job_id, row_number, raw_row, normalized_row, row_fingerprint, validation_status_code, processing_status_code, external_event_ref, canonical_idempotency_key, canonical_line_count, event_group_key, expansion_preview)
select '00000000-0000-4064-8000-000000000001', id, 2, jsonb_build_object('line', event_ref),
  jsonb_build_object('channel_code','CSV064','external_event_ref',event_ref,'external_order_ref',order_ref,'source_status','READY_TO_SHIP','occurred_at','2026-07-26T02:00:00Z','received_at','2026-07-26T02:01:00Z','source_line_ref','LINE-1','external_listing_code','SINGLE-064','listing_quantity',qty,'note','Semantik sama.'),
  lpad(to_hex(row_number() over (order by id) + 64), 64, 'c'), 'VALID', 'PENDING', event_ref, 'csv:064:' || event_ref, 1, 'CSV064|' || event_ref, '{"listingType":"SINGLE","stockEffect":"NONE"}'::jsonb
from identity_jobs;
update integration.import_jobs set status_code = 'VALIDATING' where organization_id = '00000000-0000-4064-8000-000000000001';
update integration.import_jobs set status_code = 'READY' where organization_id = '00000000-0000-4064-8000-000000000001';

select is(api.commit_marketplace_csv_import_job('00000000-0000-4064-8000-000000000001', '00000000-0000-4064-8000-000000000301', 'commit-064-direct-replay', true) ->> 'status', 'COMPLETED', 'CSV can commit after a direct canonical event');
select is((select status_code from integration.import_event_results where import_job_id = '00000000-0000-4064-8000-000000000301'), 'REPLAYED', 'CSV direct-event linkage is explicitly replayed');
select is((select count(*) from integration.import_event_results where import_job_id = '00000000-0000-4064-8000-000000000301' and canonical_event_id = (select (result ->> 'eventId')::uuid from external_results where kind = 'DIRECT_CREATED')), 1::bigint, 'CSV replay links the exact canonical event');
select is((select count(*) from operations.marketplace_events where organization_id = '00000000-0000-4064-8000-000000000001' and external_event_ref = 'EVT-064-DIRECT'), 1::bigint, 'direct then CSV creates one canonical event');

select is(api.commit_marketplace_csv_import_job('00000000-0000-4064-8000-000000000001', '00000000-0000-4064-8000-000000000302', 'commit-064-csv-created', true) ->> 'status', 'COMPLETED', 'CSV creates a canonical event through the shared boundary');
insert into external_results(kind, result) values ('DIRECT_REPLAY', api.reserve_marketplace_listing_event(
  '00000000-0000-4064-8000-000000000001', 'DIRECT-064-TWO', 'CSV064', 'EVT-064-CSV', 'ORD-064-CSV', 'READY_TO_SHIP',
  '2026-07-26 09:00:00+07', '2026-07-26 09:01:00+07', jsonb_build_array(jsonb_build_object('sourceLineRef','LINE-1','externalListingCode','SINGLE-064','listingQuantity',1,'sourceStatus','READY_TO_SHIP')),
  'Semantik sama.', jsonb_build_object('adapter','SIMULATOR'), jsonb_build_object('adapter','SIMULATOR'), 1
));
select is((select result ->> 'externalEventOutcome' from external_results where kind = 'DIRECT_REPLAY'), 'REPLAYED', 'direct canonical caller replays a CSV-created event');
select is((select count(*) from operations.marketplace_events where organization_id = '00000000-0000-4064-8000-000000000001' and external_event_ref = 'EVT-064-CSV'), 1::bigint, 'CSV then direct creates one canonical event');

select is(api.commit_marketplace_csv_import_job('00000000-0000-4064-8000-000000000001', '00000000-0000-4064-8000-000000000303', 'commit-064-conflict', true) ->> 'status', 'COMMIT_FAILED', 'CSV changed payload is a terminal grouped conflict');
select is((select failure_code from integration.import_jobs where id = '00000000-0000-4064-8000-000000000303'), 'MARKETPLACE_EXTERNAL_EVENT_CONFLICT', 'CSV reports canonical changed-payload conflict');
select is((select count(*) from operations.marketplace_events where organization_id = '00000000-0000-4064-8000-000000000001' and external_event_ref = 'EVT-064-DIRECT'), 1::bigint, 'conflict cannot add another canonical event');

-- Add a replayed group and a later changed-payload group to prove savepoint rollback.
insert into integration.import_rows(organization_id, import_job_id, row_number, raw_row, normalized_row, row_fingerprint, validation_status_code, processing_status_code, external_event_ref, canonical_idempotency_key, canonical_line_count, event_group_key, expansion_preview)
values
  ('00000000-0000-4064-8000-000000000001','00000000-0000-4064-8000-000000000304',3,'{"line":"conflict"}','{"channel_code":"CSV064","external_event_ref":"EVT-064-DIRECT","external_order_ref":"ORD-064-DIRECT","source_status":"READY_TO_SHIP","occurred_at":"2026-07-26T02:00:00Z","received_at":"2026-07-26T02:01:00Z","source_line_ref":"LINE-2","external_listing_code":"SINGLE-064","listing_quantity":2,"note":"Semantik sama."}',repeat('d',64),'VALID','PENDING','EVT-064-DIRECT','csv:064:conflict',1,'ZZZ-CONFLICT','{}');
update integration.import_jobs set row_count = 2, valid_row_count = 2 where id = '00000000-0000-4064-8000-000000000304';
select is(api.commit_marketplace_csv_import_job('00000000-0000-4064-8000-000000000001', '00000000-0000-4064-8000-000000000304', 'commit-064-grouped-rollback', true) ->> 'status', 'COMMIT_FAILED', 'later grouped conflict rolls back an earlier created group');
select is((select count(*) from operations.marketplace_events where organization_id = '00000000-0000-4064-8000-000000000001' and external_event_ref = 'EVT-064-GROUP-NEW'), 0::bigint, 'grouped conflict leaves no earlier canonical event');
select is((select count(*) from integration.import_event_results where import_job_id = '00000000-0000-4064-8000-000000000304'), 0::bigint, 'grouped conflict leaves no partial CSV audit result');
select is((select count(*) from integration.import_rows where import_job_id = '00000000-0000-4064-8000-000000000304' and processing_status_code = 'PROCESSED'), 0::bigint, 'grouped conflict leaves no processed CSV row');

select throws_ok($$select api.commit_marketplace_csv_import_job('00000000-0000-4064-8000-000000000002', '00000000-0000-4064-8000-000000000301', 'commit-064-cross-org', true)$$, 'P0001', 'CSV_IMPORT_JOB_NOT_FOUND', 'cross-organization CSV job is not found');
select is((select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4064-8000-000000000001'), 0::bigint, 'canonical reservation and CSV replay remain physically stock-neutral');
select is((select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4064-8000-000000000001'), 0::bigint, 'canonical reservation and CSV replay write no ledger entries');
select is((select sellable_qty from inventory.stock_product_positions where organization_id = '00000000-0000-4064-8000-000000000001' and product_id = '00000000-0000-4064-8000-000000000101'), 100::bigint, 'physical projection remains unchanged');
select is((select count(*) from inventory.idempotency_commands where organization_id = '00000000-0000-4064-8000-000000000001' and scope = 'MARKETPLACE_RESERVATION_EXTERNAL_EVENT'), 2::bigint, 'one shared canonical command exists for each committed external event');

select * from finish();
rollback;
