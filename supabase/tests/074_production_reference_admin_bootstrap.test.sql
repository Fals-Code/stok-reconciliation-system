begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

select has_function('api'::name, 'bootstrap_admin'::name, array['uuid', 'text', 'text']::text[]);
select ok(coalesce((select coalesce(array_to_string(proconfig, ','), '') like '%search_path=pg_catalog, app, auth%' from pg_proc where oid = to_regprocedure('api.bootstrap_admin(uuid,text,text)')), false), 'bootstrap has a fixed search path');
select ok(not has_function_privilege('anon', 'api.bootstrap_admin(uuid,text,text)', 'EXECUTE'), 'anon cannot bootstrap a production Admin');
select ok(not has_function_privilege('authenticated', 'api.bootstrap_admin(uuid,text,text)', 'EXECUTE'), 'authenticated cannot bootstrap a production Admin');
select ok(has_function_privilege('service_role', 'api.bootstrap_admin(uuid,text,text)', 'EXECUTE'), 'service role can bootstrap a production Admin');

select is(
  (select count(*) from app.organizations where code = 'STOK_RECONCILIATION_PRODUCTION' and name = 'Sistem Rekonsiliasi Stok' and timezone = 'Asia/Jakarta' and is_active),
  1::bigint,
  'one active non-demo production organization exists'
);
select ok(not exists (select 1 from app.organizations where code = 'STOK_RECONCILIATION_PRODUCTION' and (code ilike '%DEMO%' or name ilike '%DEMO%')), 'production organization is not demo-named');

select is((select count(*) from catalog.channels where code in ('MANUAL','SHOPEE','TIKTOK_SHOP','IMPORT','SIMULATOR','SYSTEM') and is_active), 6::bigint, 'required channels are active');
select is(coalesce((select count(*) from catalog.channels where code in ('MANUAL','SHOPEE','TIKTOK_SHOP','IMPORT','SIMULATOR','SYSTEM') group by code having count(*) <> 1), 0), 0::bigint, 'required channel codes are unique');
select is((select count(*) from catalog.movement_reasons where code in ('INITIAL_BALANCE','MAKLON_RECEIPT','MARKETPLACE_SALE','OFFLINE_SALE','BONUS','PROMO','SAMPLE','RETURN_RECEIVED','RETURN_SELLABLE','RETURN_DAMAGED','DAMAGED_FOUND','EXPIRED_DISPOSAL','DAMAGED_DISPOSAL','STOCKTAKE_GAIN','STOCKTAKE_LOSS','STOCKTAKE_ADJUSTMENT','REVERSAL','RETURN_INSPECTION') and is_active), 18::bigint, 'required movement reasons are active');
select is(coalesce((select count(*) from catalog.movement_reasons where code in ('INITIAL_BALANCE','MAKLON_RECEIPT','MARKETPLACE_SALE','OFFLINE_SALE','BONUS','PROMO','SAMPLE','RETURN_RECEIVED','RETURN_SELLABLE','RETURN_DAMAGED','DAMAGED_FOUND','EXPIRED_DISPOSAL','DAMAGED_DISPOSAL','STOCKTAKE_GAIN','STOCKTAKE_LOSS','STOCKTAKE_ADJUSTMENT','REVERSAL','RETURN_INSPECTION') group by code having count(*) <> 1), 0), 0::bigint, 'required movement reason codes are unique');

select is((select value from app.settings where organization_id = (select id from app.organizations where code = 'STOK_RECONCILIATION_PRODUCTION') and key = 'expiry.warning_days' and effective_to is null), '[90,60,30,0]'::jsonb, 'expiry warning settings are canonical');
select is((select value from app.settings where organization_id = (select id from app.organizations where code = 'STOK_RECONCILIATION_PRODUCTION') and key = 'expiry.safety_buffer_days' and effective_to is null), '0'::jsonb, 'expiry safety buffer settings are canonical');
select is((select value from app.settings where organization_id = (select id from app.organizations where code = 'STOK_RECONCILIATION_PRODUCTION') and key = 'return.inspection_sla_hours' and effective_to is null), '[24,72]'::jsonb, 'return inspection settings use the runtime key');
select is((select count(*) from app.settings where organization_id = (select id from app.organizations where code = 'STOK_RECONCILIATION_PRODUCTION') and key in ('demo.clock.fixed_at','simulator.demo','marketplace.listing_mappings.demo','reconciliation.daily_hour') and effective_to is null), 0::bigint, 'demo and stale scheduler settings are absent');

select throws_ok($$select api.bootstrap_admin(null, 'production.admin@invalid.test', 'Production Admin')$$, 'P0001', 'ADMIN_USER_ID_REQUIRED', 'bootstrap requires an Auth user id');
select throws_ok($$select api.bootstrap_admin('97400000-0000-4000-8000-000000000001'::uuid, 'missing.production.admin@invalid.test', 'Production Admin')$$, 'P0001', 'AUTH_USER_NOT_FOUND', 'bootstrap rejects unknown Auth users');

create temp table bootstrap_fixture(user_id uuid primary key, email text not null) on commit drop;
insert into auth.users (instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
values ('00000000-0000-0000-0000-000000000000','97400000-0000-4000-8000-000000000001','authenticated','authenticated','production.admin@invalid.test',clock_timestamp(),'{}'::jsonb,'{}'::jsonb,clock_timestamp(),clock_timestamp(),false,false);
insert into bootstrap_fixture values ('97400000-0000-4000-8000-000000000001','production.admin@invalid.test');

create temp table stock_before as
select (select count(*) from inventory.stock_transactions) as transactions,
       (select count(*) from inventory.stock_ledger_entries) as ledger_entries,
       (select count(*) from inventory.stock_product_positions) as positions,
       (select count(*) from inventory.stock_reservations) as reservations;

select is((api.bootstrap_admin((select user_id from bootstrap_fixture), (select email from bootstrap_fixture), 'Production Admin')->>'roleCode'), 'ADMIN', 'bootstrap returns the only application role');
select is((select organization_id from app.user_profiles where user_id = (select user_id from bootstrap_fixture)), (select id from app.organizations where code = 'STOK_RECONCILIATION_PRODUCTION'), 'bootstrap binds the canonical production organization internally');
select is((select role_code from app.user_profiles where user_id = (select user_id from bootstrap_fixture)), 'ADMIN', 'bootstrap cannot assign another role');
select lives_ok($$select api.bootstrap_admin('97400000-0000-4000-8000-000000000001'::uuid, 'production.admin@invalid.test', 'Production Admin')$$, 'same production Admin bootstrap is idempotent');
select is((select count(*) from app.user_profiles where user_id = (select user_id from bootstrap_fixture)), 1::bigint, 'idempotent bootstrap leaves one profile');
select is((select row_to_json(stock_before)::jsonb = jsonb_build_object('transactions',(select count(*) from inventory.stock_transactions),'ledger_entries',(select count(*) from inventory.stock_ledger_entries),'positions',(select count(*) from inventory.stock_product_positions),'reservations',(select count(*) from inventory.stock_reservations)) from stock_before), true, 'bootstrap has no stock-domain side effect');
select has_function('api'::name, 'bootstrap_demo_admin'::name, array['uuid','text','text']::text[], 'existing demo bootstrap remains available');

select * from finish();
rollback;
