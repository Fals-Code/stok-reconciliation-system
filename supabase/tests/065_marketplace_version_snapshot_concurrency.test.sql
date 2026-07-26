begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select ok(
  position(
    'lock_marketplace_listing_identity'
    in pg_get_functiondef(
      'operations.resolve_marketplace_listing_expansion(uuid,text,text,bigint,timestamp with time zone)'::regprocedure
    )
  ) > 0,
  'resolver serializes normalization with the shared marketplace listing identity lock'
);

select ok(
  position(
    'lock_marketplace_listing_identity'
    in pg_get_functiondef(
      'operations.resolve_marketplace_listing_expansion(uuid,text,text,bigint,timestamp with time zone)'::regprocedure
    )
  ) > 0,
  'resolver enters the shared lifecycle lock before resolving the immutable version snapshot'
);

select ok(
  position(
    'lock_marketplace_listing_identity_by_listing_id'
    in pg_get_functiondef(
      'api.activate_marketplace_listing_version(uuid,text,uuid,uuid,bigint,text,boolean)'::regprocedure
    )
  ) > 0,
  'activation uses the same listing identity lock before changing the effective version window'
);

select ok(
  position(
    'lock_marketplace_listing_identity_by_listing_id'
    in pg_get_functiondef(
      'api.retire_marketplace_listing_version(uuid,text,uuid,uuid,bigint,timestamp with time zone,boolean)'::regprocedure
    )
  ) > 0,
  'retirement uses the same listing identity lock before changing the effective version window'
);

select ok(
  position(
    'lock_marketplace_listing_identity_by_listing_id'
    in pg_get_functiondef(
      'api.archive_marketplace_listing(uuid,text,uuid,bigint,boolean)'::regprocedure
    )
  ) > 0,
  'archive uses the same listing identity lock before changing listing availability'
);
select ok(
  position('lock_marketplace_listing_identity' in pg_get_functiondef('operations.resolve_marketplace_listing_expansion(uuid,text,text,bigint,timestamp with time zone)'::regprocedure))
    < position('resolve_marketplace_listing_expansion_apply' in pg_get_functiondef('operations.resolve_marketplace_listing_expansion(uuid,text,text,bigint,timestamp with time zone)'::regprocedure)),
  'resolver takes the listing identity lock before invoking historical expansion'
);
select ok(
  position('lock_marketplace_listing_identity_by_listing_id' in pg_get_functiondef('api.activate_marketplace_listing_version(uuid,text,uuid,uuid,bigint,text,boolean)'::regprocedure))
    < position('activate_marketplace_listing_version_apply' in pg_get_functiondef('api.activate_marketplace_listing_version(uuid,text,uuid,uuid,bigint,text,boolean)'::regprocedure)),
  'activation takes the listing identity lock before lifecycle row locks'
);
select ok(
  position('lock_marketplace_listing_identity_by_listing_id' in pg_get_functiondef('api.retire_marketplace_listing_version(uuid,text,uuid,uuid,bigint,timestamp with time zone,boolean)'::regprocedure))
    < position('retire_marketplace_listing_version_apply' in pg_get_functiondef('api.retire_marketplace_listing_version(uuid,text,uuid,uuid,bigint,timestamp with time zone,boolean)'::regprocedure)),
  'retirement takes the listing identity lock before lifecycle row locks'
);
select ok(
  position('lock_marketplace_listing_identity_by_listing_id' in pg_get_functiondef('api.archive_marketplace_listing(uuid,text,uuid,bigint,boolean)'::regprocedure))
    < position('archive_marketplace_listing_apply' in pg_get_functiondef('api.archive_marketplace_listing(uuid,text,uuid,bigint,boolean)'::regprocedure)),
  'archive takes the listing identity lock before lifecycle row locks'
);

select ok(
  (select proconfig @> array['search_path=pg_catalog, operations']
   from pg_proc
   where oid = 'operations.lock_marketplace_listing_identity(uuid,uuid,text)'::regprocedure),
  'shared listing identity helper has a fixed minimal search_path'
);
select ok(
  not has_function_privilege('public', 'operations.lock_marketplace_listing_identity(uuid,uuid,text)', 'EXECUTE')
    and not has_function_privilege('anon', 'operations.lock_marketplace_listing_identity(uuid,uuid,text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'operations.lock_marketplace_listing_identity(uuid,uuid,text)', 'EXECUTE'),
  'shared listing identity helper is not directly callable outside trusted boundaries'
);
select ok(
  (select proconfig @> array['search_path=pg_catalog, catalog, operations']
   from pg_proc
   where oid = 'operations.lock_marketplace_listing_identity_by_listing_id(uuid,uuid)'::regprocedure),
  'listing-id lock lookup has a fixed search_path'
);
select ok(
  not has_function_privilege('public', 'operations.lock_marketplace_listing_identity_by_listing_id(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'operations.lock_marketplace_listing_identity_by_listing_id(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'operations.lock_marketplace_listing_identity_by_listing_id(uuid,uuid)', 'EXECUTE'),
  'listing-id lock lookup is not directly callable outside trusted boundaries'
);

insert into app.organizations(id, code, name, timezone, is_active, created_at)
values ('00000000-0000-4065-8000-000000000001', 'PGTAP_VERSION_065', 'Version Snapshot 065', 'Asia/Jakarta', true, '2026-07-26 08:00:00+07');

insert into catalog.channels(id, code, name, is_marketplace, is_active)
values ('00000000-0000-4065-8000-000000000011', 'VERSION065', 'Version Snapshot Channel 065', true, true);

insert into catalog.products(id, organization_id, sku, name, created_at)
values
  ('00000000-0000-4065-8000-000000000101', '00000000-0000-4065-8000-000000000001', 'VERSION065-OLD', 'Version Snapshot Old', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4065-8000-000000000102', '00000000-0000-4065-8000-000000000001', 'VERSION065-NEW', 'Version Snapshot New', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4065-8000-000000000103', '00000000-0000-4065-8000-000000000001', 'VERSION065-BUNDLE-A', 'Version Snapshot Bundle A', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4065-8000-000000000104', '00000000-0000-4065-8000-000000000001', 'VERSION065-BUNDLE-B', 'Version Snapshot Bundle B', '2026-07-26 08:00:00+07'),
  ('00000000-0000-4065-8000-000000000105', '00000000-0000-4065-8000-000000000001', 'VERSION065-BUNDLE-C', 'Version Snapshot Bundle C', '2026-07-26 08:00:00+07');

insert into inventory.stock_product_positions(organization_id, product_id, sellable_qty)
select '00000000-0000-4065-8000-000000000001', id, 100
from catalog.products
where organization_id = '00000000-0000-4065-8000-000000000001';

create temporary table version_results(kind text primary key, result jsonb not null) on commit drop;

insert into version_results(kind, result)
values ('SINGLE_DRAFT_V1', api.create_marketplace_listing_version_draft(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-SINGLE-DRAFT-V1', 'VERSION065', 'SINGLE-065', 'Single 065', 'SINGLE',
  '2026-07-01 00:00:00+07', '00000000-0000-4065-8000-000000000101', '[]'::jsonb, 'Single v1.', '{}'::jsonb
));
insert into version_results(kind, result)
values ('SINGLE_PREVIEW_V1', api.preview_marketplace_listing_version_activation(
  '00000000-0000-4065-8000-000000000001',
  (select (result ->> 'listingId')::uuid from version_results where kind = 'SINGLE_DRAFT_V1'),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'SINGLE_DRAFT_V1')
));
insert into version_results(kind, result)
values ('SINGLE_ACTIVE_V1', api.activate_marketplace_listing_version(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-SINGLE-ACTIVATE-V1',
  (select (result ->> 'listingId')::uuid from version_results where kind = 'SINGLE_DRAFT_V1'),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'SINGLE_DRAFT_V1'),
  (select (result ->> 'versionRowVersion')::bigint from version_results where kind = 'SINGLE_PREVIEW_V1'),
  (select result ->> 'basisHash' from version_results where kind = 'SINGLE_PREVIEW_V1'), true
));

insert into version_results(kind, result)
values ('SINGLE_EVENT_V1', api.reserve_marketplace_listing_event(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-SINGLE-EVENT-V1', 'VERSION065', 'EVT-065-SINGLE-V1', 'ORD-065-SINGLE-V1', 'READY_TO_SHIP',
  '2026-07-31 23:59:59+07', '2026-08-02 00:00:00+07',
  jsonb_build_array(jsonb_build_object('sourceLineRef','LINE-1','externalListingCode','SINGLE-065','listingQuantity',1,'sourceStatus','READY_TO_SHIP')),
  'Historical single.', '{}'::jsonb, '{}'::jsonb, 1
));

insert into version_results(kind, result)
values ('SINGLE_DRAFT_V2', api.create_marketplace_listing_version_draft(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-SINGLE-DRAFT-V2', 'VERSION065', 'SINGLE-065', 'Single 065 v2', 'SINGLE',
  '2026-08-01 00:00:00+07', '00000000-0000-4065-8000-000000000102', '[]'::jsonb, 'Single v2.', '{}'::jsonb
));
insert into version_results(kind, result)
values ('SINGLE_PREVIEW_V2', api.preview_marketplace_listing_version_activation(
  '00000000-0000-4065-8000-000000000001',
  (select (result ->> 'listingId')::uuid from version_results where kind = 'SINGLE_DRAFT_V2'),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'SINGLE_DRAFT_V2')
));
insert into version_results(kind, result)
values ('SINGLE_ACTIVE_V2', api.activate_marketplace_listing_version(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-SINGLE-ACTIVATE-V2',
  (select (result ->> 'listingId')::uuid from version_results where kind = 'SINGLE_DRAFT_V2'),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'SINGLE_DRAFT_V2'),
  (select (result ->> 'versionRowVersion')::bigint from version_results where kind = 'SINGLE_PREVIEW_V2'),
  (select result ->> 'basisHash' from version_results where kind = 'SINGLE_PREVIEW_V2'), true
));

select is(
  (select single_listing_version_id from operations.marketplace_source_lines where organization_id = '00000000-0000-4065-8000-000000000001' and source_line_ref = 'LINE-1'),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'SINGLE_ACTIVE_V1'),
  'historical single event preserves the version selected from occurred_at'
);
select is(
  (select product_id from operations.marketplace_source_line_components where organization_id = '00000000-0000-4065-8000-000000000001' and canonical_source_line_ref = 'LINE-1#C001'),
  '00000000-0000-4065-8000-000000000101'::uuid,
  'historical single component snapshot preserves the old product'
);

insert into version_results(kind, result)
values ('SINGLE_EVENT_V2', api.reserve_marketplace_listing_event(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-SINGLE-EVENT-V2', 'VERSION065', 'EVT-065-SINGLE-V2', 'ORD-065-SINGLE-V2', 'READY_TO_SHIP',
  '2026-08-01 00:00:00+07', '2026-08-02 00:00:00+07',
  jsonb_build_array(jsonb_build_object('sourceLineRef','LINE-1','externalListingCode','SINGLE-065','listingQuantity',1,'sourceStatus','READY_TO_SHIP')),
  'Boundary single.', '{}'::jsonb, '{}'::jsonb, 1
));
select is(
  (select single_listing_version_id from operations.marketplace_source_lines where organization_id = '00000000-0000-4065-8000-000000000001' and normalization_event_id = (select (result ->> 'normalizationEventId')::uuid from version_results where kind = 'SINGLE_EVENT_V2')),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'SINGLE_ACTIVE_V2'),
  'event at the half-open boundary selects the new single version'
);
insert into version_results(kind, result)
values ('SINGLE_EVENT_AFTER_V2', api.reserve_marketplace_listing_event(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-SINGLE-EVENT-AFTER-V2', 'VERSION065', 'EVT-065-SINGLE-AFTER-V2', 'ORD-065-SINGLE-AFTER-V2', 'READY_TO_SHIP',
  '2026-08-01 00:00:01+07', '2026-08-02 00:00:00+07',
  jsonb_build_array(jsonb_build_object('sourceLineRef','LINE-1','externalListingCode','SINGLE-065','listingQuantity',1,'sourceStatus','READY_TO_SHIP')),
  'After boundary single.', '{}'::jsonb, '{}'::jsonb, 1
));
select is(
  (select single_listing_version_id from operations.marketplace_source_lines where organization_id = '00000000-0000-4065-8000-000000000001' and normalization_event_id = (select (result ->> 'normalizationEventId')::uuid from version_results where kind = 'SINGLE_EVENT_AFTER_V2')),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'SINGLE_ACTIVE_V2'),
  'event after the half-open boundary keeps selecting the new single version'
);

insert into version_results(kind, result)
values ('SINGLE_REPLAY_V1', api.reserve_marketplace_listing_event(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-SINGLE-EVENT-V1-REPLAY', 'VERSION065', 'EVT-065-SINGLE-V1', 'ORD-065-SINGLE-V1', 'READY_TO_SHIP',
  '2026-07-31 23:59:59+07', '2026-08-02 00:00:00+07',
  jsonb_build_array(jsonb_build_object('sourceLineRef','LINE-1','externalListingCode','SINGLE-065','listingQuantity',1,'sourceStatus','READY_TO_SHIP')),
  'Historical single.', jsonb_build_object('adapter','CSV'), jsonb_build_object('adapter','CSV'), 1
));
select is((select result ->> 'externalEventOutcome' from version_results where kind = 'SINGLE_REPLAY_V1'), 'REPLAYED', 'replay after a mapping update returns the stored canonical result');
select is((select count(*) from operations.marketplace_normalization_events where organization_id = '00000000-0000-4065-8000-000000000001' and external_event_ref_snapshot = 'EVT-065-SINGLE-V1'), 1::bigint, 'replay does not resolve or persist another single normalization snapshot');
select throws_ok(
  $$select api.reserve_marketplace_listing_event('00000000-0000-4065-8000-000000000001','PGTAP-065-SINGLE-EVENT-V1-CONFLICT','VERSION065','EVT-065-SINGLE-V1','ORD-065-SINGLE-V1','READY_TO_SHIP','2026-07-31 23:59:59+07','2026-08-02 00:00:00+07',jsonb_build_array(jsonb_build_object('sourceLineRef','LINE-1','externalListingCode','SINGLE-065','listingQuantity',2,'sourceStatus','READY_TO_SHIP')),'Historical single.', '{}'::jsonb, '{}'::jsonb, 1)$$,
  'P0001', 'MARKETPLACE_EXTERNAL_EVENT_CONFLICT', 'changed payload cannot replace the stored single snapshot'
);

insert into integration.import_jobs(
  id, organization_id, created_by_process, import_type_code, template_version,
  status_code, original_file_name, object_path, detected_mime, file_size_bytes,
  file_sha256, job_command_key, job_request_hash, row_count, valid_row_count,
  created_at
) values (
  '00000000-0000-4065-8000-000000000301',
  '00000000-0000-4065-8000-000000000001',
  'pgtap-065', 'ORDER', 'MARKETPLACE_RESERVATION_V1', 'UPLOADED',
  'historical-single.csv',
  '00000000-0000-4065-8000-000000000001/00000000-0000-4065-8000-000000000301/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.csv',
  'text/csv', 256, repeat('a', 64), 'CSV065-JOB-301', repeat('b', 64), 1, 1,
  '2026-08-02 00:10:00+07'
);
insert into integration.import_rows(
  organization_id, import_job_id, row_number, raw_row, normalized_row,
  row_fingerprint, validation_status_code, processing_status_code,
  external_event_ref, canonical_idempotency_key, canonical_line_count,
  event_group_key, expansion_preview
) values (
  '00000000-0000-4065-8000-000000000001',
  '00000000-0000-4065-8000-000000000301', 2,
  '{"line":"historical-single"}',
  '{"channel_code":"VERSION065","external_event_ref":"EVT-065-SINGLE-V1","external_order_ref":"ORD-065-SINGLE-V1","source_status":"READY_TO_SHIP","occurred_at":"2026-07-31T16:59:59Z","received_at":"2026-08-01T17:00:00Z","source_line_ref":"LINE-1","external_listing_code":"SINGLE-065","listing_quantity":1,"note":"Historical single."}',
  repeat('c', 64), 'VALID', 'PENDING', 'EVT-065-SINGLE-V1',
  'csv:065:historical-single', 1, 'VERSION065|EVT-065-SINGLE-V1',
  '{"listingType":"SINGLE","stockEffect":"NONE"}'
);
update integration.import_jobs
set status_code = 'VALIDATING'
where id = '00000000-0000-4065-8000-000000000301';
update integration.import_jobs
set status_code = 'READY'
where id = '00000000-0000-4065-8000-000000000301';
select is(
  api.commit_marketplace_csv_import_job(
    '00000000-0000-4065-8000-000000000001',
    '00000000-0000-4065-8000-000000000301',
    'commit-065-historical-single',
    true
  ) ->> 'status',
  'COMPLETED',
  'CSV replay after a newer mapping version commits safely'
);
select is(
  (select status_code from integration.import_event_results where import_job_id = '00000000-0000-4065-8000-000000000301'),
  'REPLAYED',
  'CSV replay records the canonical historical result rather than re-resolving the mapping'
);
select is(
  (select canonical_event_id from integration.import_event_results where import_job_id = '00000000-0000-4065-8000-000000000301'),
  (select (result ->> 'eventId')::uuid from version_results where kind = 'SINGLE_EVENT_V1'),
  'CSV replay links the exact canonical event selected before the mapping update'
);
select is(
  (select count(*) from operations.marketplace_normalization_events where organization_id = '00000000-0000-4065-8000-000000000001' and external_event_ref_snapshot = 'EVT-065-SINGLE-V1'),
  1::bigint,
  'CSV replay does not re-expand the historical single listing after mapping mutation'
);

insert into version_results(kind, result)
values ('BUNDLE_DRAFT_V1', api.create_marketplace_listing_version_draft(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-BUNDLE-DRAFT-V1', 'VERSION065', 'BUNDLE-065', 'Bundle 065', 'BUNDLE',
  '2026-07-01 00:00:00+07', null,
  jsonb_build_array(jsonb_build_object('productId','00000000-0000-4065-8000-000000000103','quantity',1), jsonb_build_object('productId','00000000-0000-4065-8000-000000000104','quantity',2)),
  'Bundle v1.', '{}'::jsonb
));
insert into version_results(kind, result)
values ('BUNDLE_PREVIEW_V1', api.preview_marketplace_listing_version_activation(
  '00000000-0000-4065-8000-000000000001',
  (select (result ->> 'listingId')::uuid from version_results where kind = 'BUNDLE_DRAFT_V1'),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'BUNDLE_DRAFT_V1')
));
insert into version_results(kind, result)
values ('BUNDLE_ACTIVE_V1', api.activate_marketplace_listing_version(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-BUNDLE-ACTIVATE-V1',
  (select (result ->> 'listingId')::uuid from version_results where kind = 'BUNDLE_DRAFT_V1'),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'BUNDLE_DRAFT_V1'),
  (select (result ->> 'versionRowVersion')::bigint from version_results where kind = 'BUNDLE_PREVIEW_V1'),
  (select result ->> 'basisHash' from version_results where kind = 'BUNDLE_PREVIEW_V1'), true
));
insert into version_results(kind, result)
values ('BUNDLE_EVENT_V1', api.reserve_marketplace_listing_event(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-BUNDLE-EVENT-V1', 'VERSION065', 'EVT-065-BUNDLE-V1', 'ORD-065-BUNDLE-V1', 'READY_TO_SHIP',
  '2026-07-31 23:59:59+07', '2026-08-02 00:00:00+07',
  jsonb_build_array(jsonb_build_object('sourceLineRef','BUNDLE-LINE-1','externalListingCode','BUNDLE-065','listingQuantity',2,'sourceStatus','READY_TO_SHIP')),
  'Historical bundle.', '{}'::jsonb, '{}'::jsonb, 1
));
insert into version_results(kind, result)
values ('BUNDLE_DRAFT_V2', api.create_marketplace_listing_version_draft(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-BUNDLE-DRAFT-V2', 'VERSION065', 'BUNDLE-065', 'Bundle 065 v2', 'BUNDLE',
  '2026-08-01 00:00:00+07', null,
  jsonb_build_array(jsonb_build_object('productId','00000000-0000-4065-8000-000000000105','quantity',3)),
  'Bundle v2.', '{}'::jsonb
));
insert into version_results(kind, result)
values ('BUNDLE_PREVIEW_V2', api.preview_marketplace_listing_version_activation(
  '00000000-0000-4065-8000-000000000001',
  (select (result ->> 'listingId')::uuid from version_results where kind = 'BUNDLE_DRAFT_V2'),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'BUNDLE_DRAFT_V2')
));
insert into version_results(kind, result)
values ('BUNDLE_ACTIVE_V2', api.activate_marketplace_listing_version(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-BUNDLE-ACTIVATE-V2',
  (select (result ->> 'listingId')::uuid from version_results where kind = 'BUNDLE_DRAFT_V2'),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'BUNDLE_DRAFT_V2'),
  (select (result ->> 'versionRowVersion')::bigint from version_results where kind = 'BUNDLE_PREVIEW_V2'),
  (select result ->> 'basisHash' from version_results where kind = 'BUNDLE_PREVIEW_V2'), true
));
insert into version_results(kind, result)
values ('BUNDLE_EVENT_V2', api.reserve_marketplace_listing_event(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-BUNDLE-EVENT-V2', 'VERSION065', 'EVT-065-BUNDLE-V2', 'ORD-065-BUNDLE-V2', 'READY_TO_SHIP',
  '2026-08-01 00:00:00+07', '2026-08-02 00:00:00+07',
  jsonb_build_array(jsonb_build_object('sourceLineRef','BUNDLE-LINE-1','externalListingCode','BUNDLE-065','listingQuantity',2,'sourceStatus','READY_TO_SHIP')),
  'Boundary bundle.', '{}'::jsonb, '{}'::jsonb, 1
));
select is(
  (select bundle_recipe_id from operations.marketplace_source_lines where organization_id = '00000000-0000-4065-8000-000000000001' and normalization_event_id = (select (result ->> 'normalizationEventId')::uuid from version_results where kind = 'BUNDLE_EVENT_V2')),
  (select (result ->> 'versionId')::uuid from version_results where kind = 'BUNDLE_ACTIVE_V2'),
  'event at the boundary selects exactly the new bundle recipe version'
);
select is(
  (select string_agg(product_id::text || ':' || expanded_quantity::text, ',' order by component_no) from operations.marketplace_source_line_components where organization_id = '00000000-0000-4065-8000-000000000001' and source_line_id = (select id from operations.marketplace_source_lines where organization_id = '00000000-0000-4065-8000-000000000001' and normalization_event_id = (select (result ->> 'normalizationEventId')::uuid from version_results where kind = 'BUNDLE_EVENT_V2'))),
  '00000000-0000-4065-8000-000000000105:6',
  'bundle boundary snapshot contains one complete new-version component set without mixing recipes'
);
insert into version_results(kind, result)
values ('BUNDLE_REPLAY_V1', api.reserve_marketplace_listing_event(
  '00000000-0000-4065-8000-000000000001', 'PGTAP-065-BUNDLE-EVENT-V1-REPLAY', 'VERSION065', 'EVT-065-BUNDLE-V1', 'ORD-065-BUNDLE-V1', 'READY_TO_SHIP',
  '2026-07-31 23:59:59+07', '2026-08-02 00:00:00+07',
  jsonb_build_array(jsonb_build_object('sourceLineRef','BUNDLE-LINE-1','externalListingCode','BUNDLE-065','listingQuantity',2,'sourceStatus','READY_TO_SHIP')),
  'Historical bundle.', jsonb_build_object('adapter','CSV'), jsonb_build_object('adapter','CSV'), 1
));
select is((select result ->> 'externalEventOutcome' from version_results where kind = 'BUNDLE_REPLAY_V1'), 'REPLAYED', 'bundle replay after recipe activation returns the stored result');
select is((select count(*) from operations.marketplace_normalization_events where organization_id = '00000000-0000-4065-8000-000000000001' and external_event_ref_snapshot = 'EVT-065-BUNDLE-V1'), 1::bigint, 'bundle replay does not create a second normalization snapshot');
select is((select count(*) from inventory.stock_transactions where organization_id = '00000000-0000-4065-8000-000000000001'), 0::bigint, 'version selection and replay stay physically stock-neutral');
select is((select count(*) from inventory.stock_ledger_entries where organization_id = '00000000-0000-4065-8000-000000000001'), 0::bigint, 'version selection and replay write no ledger entries');
select is((select count(*) from operations.marketplace_events where organization_id = '00000000-0000-4065-8000-000000000001'), 5::bigint, 'each version fixture event has exactly one canonical event');

select * from finish();
rollback;
