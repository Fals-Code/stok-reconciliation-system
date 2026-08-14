begin;

create extension if not exists pgtap with schema extensions;

select plan(52);

select has_schema('scheduler', 'Scheduler memakai namespace privat tersendiri.');
select has_table('scheduler', 'job_runs', 'Scheduler memiliki run ledger authoritative.');
select has_column('scheduler', 'job_runs', 'scheduled_slot', 'Run ledger menyimpan slot deterministik.');
select has_column('scheduler', 'job_runs', 'status_code', 'Run ledger menyimpan hasil domain job.');
select has_column('scheduler', 'job_runs', 'error_summary', 'Run ledger menyimpan ringkasan kegagalan tersanitasi.');
select has_function('scheduler', 'run_production_job', array['text'], 'Orkestrator produksi hanya menerima katalog job tetap.');
select has_function('scheduler', 'run_job_at', array['text', 'timestamp with time zone'], 'Clock test hanya ada pada boundary privat.');
select has_function('api', 'scheduler_operations_summary', array[]::text[], 'Admin memiliki read contract untuk status scheduler.');
select function_returns('scheduler', 'run_production_job', array['text'], 'jsonb');
select function_returns('api', 'scheduler_operations_summary', array[]::text[], 'jsonb');
select ok(has_function_privilege('authenticated', 'api.scheduler_operations_summary()', 'EXECUTE'), 'Authenticated Admin dapat membaca ringkasan scheduler.');
select ok(not has_function_privilege('anon', 'api.scheduler_operations_summary()', 'EXECUTE'), 'Anon tidak dapat membaca ringkasan scheduler.');
select ok(not has_function_privilege('authenticated', 'scheduler.run_production_job(text)', 'EXECUTE'), 'Authenticated tidak dapat memicu scheduler privat.');
select ok(not has_function_privilege('service_role', 'scheduler.run_production_job(text)', 'EXECUTE'), 'Service role tidak diberi hak scheduler tanpa kebutuhan.');
select ok(not exists (select 1 from pg_namespace namespace_row where namespace_row.nspname = 'scheduler' and has_schema_privilege('anon', namespace_row.oid, 'USAGE')), 'Anon tidak dapat memakai namespace scheduler privat.');
select ok((select relrowsecurity from pg_class where oid = 'scheduler.job_runs'::regclass), 'Run ledger scheduler memakai RLS defensif.');

select is((select count(*) from cron.job where jobname like 'phase2-%'), 4::bigint, 'Tepat empat job Phase 2 terdaftar.');
select is((select schedule from cron.job where jobname = 'phase2-notification-outbox'), '* * * * *', 'Outbox berjalan setiap menit.');
select is((select schedule from cron.job where jobname = 'phase2-claim-deadline'), '7 * * * *', 'Pengingat klaim berjalan tiap jam.');
select is((select schedule from cron.job where jobname = 'phase2-expiry-daily'), '10 17 * * *', 'Kedaluwarsa dijadwalkan 00:10 WIB dalam UTC.');
select is((select schedule from cron.job where jobname = 'phase2-reconciliation-daily'), '25 17 * * *', 'Rekonsiliasi dijadwalkan setelah kedaluwarsa dalam UTC.');
select is((select count(*) from cron.job where jobname in ('phase2-stocktake','phase2-return-inspection','phase2-marketplace')), 0::bigint, 'Tidak ada cron mutasi stok yang terlarang.');
select is(scheduler.slot_for('RECONCILIATION_DAILY', '2026-08-14 17:30:00+00'::timestamptz), '2026-08-14 17:00:00+00'::timestamptz, 'Slot harian diturunkan dari tanggal operasional Asia/Jakarta.');
select is(to_char(scheduler.slot_for('RECONCILIATION_DAILY', '2026-08-14 17:30:00+00'::timestamptz) at time zone 'Asia/Jakarta', 'YYYYMMDD'), '20260815', 'Kunci daily memakai tanggal operasional Asia/Jakarta, bukan tanggal UTC slot.');

create temp table scheduler_test_results (kind text primary key, result jsonb not null) on commit drop;
create temp table scheduler_stock_snapshot (stage text primary key, transaction_count bigint not null, ledger_count bigint not null, position_count bigint not null, reservation_count bigint not null) on commit drop;

insert into scheduler_stock_snapshot
select 'BEFORE',
  (select count(*) from inventory.stock_transactions),
  (select count(*) from inventory.stock_ledger_entries),
  (select count(*) from inventory.stock_product_positions),
  (select count(*) from inventory.stock_reservations);

insert into scheduler_test_results values
  ('OUTBOX_FIRST', scheduler.run_job_at('NOTIFICATION_OUTBOX', '2026-08-14 01:23:45+00'::timestamptz)),
  ('OUTBOX_REPLAY', scheduler.run_job_at('NOTIFICATION_OUTBOX', '2026-08-14 01:23:59+00'::timestamptz)),
  ('CLAIM_FIRST', scheduler.run_job_at('CLAIM_DEADLINE', '2026-08-14 01:30:00+00'::timestamptz)),
  ('CLAIM_REPLAY', scheduler.run_job_at('CLAIM_DEADLINE', '2026-08-14 01:59:00+00'::timestamptz)),
  ('EXPIRY_FIRST', scheduler.run_job_at('EXPIRY_DAILY', '2026-08-14 17:15:00+00'::timestamptz)),
  ('EXPIRY_REPLAY', scheduler.run_job_at('EXPIRY_DAILY', '2026-08-14 17:55:00+00'::timestamptz));

select is((select result ->> 'action' from scheduler_test_results where kind='OUTBOX_FIRST'), 'EXECUTED', 'Outbox slot pertama dieksekusi.');
select is((select result ->> 'action' from scheduler_test_results where kind='OUTBOX_REPLAY'), 'REPLAYED', 'Outbox slot identik diputar ulang tanpa delegasi kedua.');
select is((select count(*) from scheduler.job_runs where job_code='NOTIFICATION_OUTBOX' and scheduled_slot='2026-08-14 01:23:00+00'::timestamptz), 1::bigint, 'Outbox memiliki satu authoritative run per minute slot.');
select is((select count(*) from scheduler.job_runs where job_code='CLAIM_DEADLINE' and organization_id='00000000-0000-4000-8000-000000000001'::uuid and scheduled_slot='2026-08-14 01:00:00+00'::timestamptz), 1::bigint, 'Claim deadline memiliki satu run per organisasi dan hour slot.');
select is((select count(*) from scheduler.job_runs where job_code='EXPIRY_DAILY' and organization_id='00000000-0000-4000-8000-000000000001'::uuid and scheduled_slot='2026-08-14 17:00:00+00'::timestamptz), 1::bigint, 'Expiry memiliki satu run per organisasi dan Jakarta date slot.');
select is((select count(*) = count(distinct organization_id) from scheduler.job_runs where job_code='CLAIM_DEADLINE' and scheduled_slot='2026-08-14 01:00:00+00'::timestamptz), true, 'Replay hourly claim tidak menggandakan run ledger per organisasi.');
select is((select count(*) = count(distinct organization_id) from scheduler.job_runs where job_code='EXPIRY_DAILY' and scheduled_slot='2026-08-14 17:00:00+00'::timestamptz), true, 'Replay daily expiry tidak menggandakan run ledger per organisasi.');

insert into app.organizations (id, code, name, timezone, is_active)
values (gen_random_uuid(), 'PGTAP_SCHEDULER_INVALID_TZ', 'Fixture scheduler invalid timezone', 'Invalid/Timezone', true);

insert into scheduler_test_results values
  ('RECON_DAILY', scheduler.run_job_at('RECONCILIATION_DAILY', '2026-08-14 17:30:00+00'::timestamptz)),
  ('RECON_REPLAY', scheduler.run_job_at('RECONCILIATION_DAILY', '2026-08-14 17:59:00+00'::timestamptz));

select is((select status_code from scheduler.job_runs where job_code='RECONCILIATION_DAILY' and organization_id='00000000-0000-4000-8000-000000000001'::uuid and scheduled_slot='2026-08-14 17:00:00+00'::timestamptz), 'SUCCEEDED', 'Rekonsiliasi daily organisasi valid sukses.');
select is((select run_type_code from reconciliation.runs where organization_id='00000000-0000-4000-8000-000000000001'::uuid and metadata ->> 'schedulerJobCode'='RECONCILIATION_DAILY' order by created_at desc limit 1), 'DAILY', 'Rekonsiliasi scheduler memakai provenance DAILY.');
select is((select trigger_code from reconciliation.runs where organization_id='00000000-0000-4000-8000-000000000001'::uuid and metadata ->> 'schedulerJobCode'='RECONCILIATION_DAILY' order by created_at desc limit 1), 'SYSTEM', 'Rekonsiliasi scheduler memakai trigger SYSTEM.');
select is((select process_name from reconciliation.runs where organization_id='00000000-0000-4000-8000-000000000001'::uuid and metadata ->> 'schedulerJobCode'='RECONCILIATION_DAILY' order by created_at desc limit 1), 'scheduler.run_daily_reconciliation', 'Rekonsiliasi scheduler mencatat process provenance.');
select is((select count(*) from reconciliation.runs where organization_id='00000000-0000-4000-8000-000000000001'::uuid and metadata ->> 'schedulerJobCode'='RECONCILIATION_DAILY'), 1::bigint, 'Replay daily reconciliation tidak membuat run kedua.');
select is((select count(*) from notification.outbox_events where organization_id='00000000-0000-4000-8000-000000000001'::uuid and event_type_code='NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED' and source_event_key='scheduler:reconciliation-daily:00000000-0000-4000-8000-000000000001:20260815'), 1::bigint, 'Rekonsiliasi daily mengantrekan satu evaluasi notifikasi deterministik.');
select is((select status_code from scheduler.job_runs where job_code='RECONCILIATION_DAILY' and organization_id=(select id from app.organizations where code='PGTAP_SCHEDULER_INVALID_TZ') and scheduled_slot='2026-08-14 17:00:00+00'::timestamptz), 'FAILED', 'Kegagalan organisasi tercatat tanpa menggagalkan evidence organisasi lain.');
select is((select error_code from scheduler.job_runs where job_code='RECONCILIATION_DAILY' and organization_id=(select id from app.organizations where code='PGTAP_SCHEDULER_INVALID_TZ')), 'SCHEDULER_DELEGATE_FAILED', 'Kegagalan scheduler memakai kode tersanitasi.');
select is((select error_summary from scheduler.job_runs where job_code='RECONCILIATION_DAILY' and organization_id=(select id from app.organizations where code='PGTAP_SCHEDULER_INVALID_TZ')), 'Operasi terjadwal gagal dan perlu diperiksa.', 'Kegagalan scheduler tidak memaparkan error internal.');
select ok((select error_summary not like '%Invalid/Timezone%' from scheduler.job_runs where job_code='RECONCILIATION_DAILY' and organization_id=(select id from app.organizations where code='PGTAP_SCHEDULER_INVALID_TZ')), 'Ringkasan failure tidak membocorkan detail fixture/internal.');

select is(api.run_reconciliation('00000000-0000-4000-8000-000000000001'::uuid, 'PGTAP-SCHEDULER-MANUAL-PROVENANCE', array['LEDGER_BATCH_PROJECTION']::text[], '{}'::jsonb, '{"test":true}'::jsonb) ->> 'status', 'SUCCEEDED', 'Manual reconciliation existing tetap dapat dijalankan.');
select is((select run_type_code from reconciliation.runs where idempotency_command_id=(select id from inventory.idempotency_commands where organization_id='00000000-0000-4000-8000-000000000001'::uuid and scope='RUN_RECONCILIATION' and key='PGTAP-SCHEDULER-MANUAL-PROVENANCE')), 'MANUAL', 'Manual reconciliation tetap memakai provenance MANUAL.');
select is((select trigger_code from reconciliation.runs where idempotency_command_id=(select id from inventory.idempotency_commands where organization_id='00000000-0000-4000-8000-000000000001'::uuid and scope='RUN_RECONCILIATION' and key='PGTAP-SCHEDULER-MANUAL-PROVENANCE')), 'MANUAL', 'Manual reconciliation tetap memakai trigger MANUAL.');

select is((select count(*) from inventory.stock_transactions), (select transaction_count from scheduler_stock_snapshot where stage='BEFORE'), 'Scheduler tidak membuat stock transaction.');
select is((select count(*) from inventory.stock_ledger_entries), (select ledger_count from scheduler_stock_snapshot where stage='BEFORE'), 'Scheduler tidak menulis ledger fisik.');
select is((select count(*) from inventory.stock_product_positions), (select position_count from scheduler_stock_snapshot where stage='BEFORE'), 'Scheduler tidak mengubah projection produk.');
select is((select count(*) from inventory.stock_reservations), (select reservation_count from scheduler_stock_snapshot where stage='BEFORE'), 'Scheduler tidak mengubah reservasi.');

create temp table scheduler_auth_fixture (
  fixture_key text primary key,
  organization_id uuid not null,
  user_id uuid not null
) on commit drop;
insert into scheduler_auth_fixture values
  ('CURRENT_ADMIN', gen_random_uuid(), gen_random_uuid()),
  ('OTHER_ADMIN', gen_random_uuid(), gen_random_uuid());
insert into app.organizations (id, code, name, timezone, is_active)
select organization_id, 'PGTAP_SCHEDULER_' || fixture_key, 'Fixture isolasi scheduler ' || fixture_key, 'Asia/Jakarta', true
from scheduler_auth_fixture;
insert into auth.users (instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
select '00000000-0000-0000-0000-000000000000'::uuid, user_id, 'authenticated', 'authenticated', lower(fixture_key) || '.scheduler@glowlab.invalid', clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, clock_timestamp(), clock_timestamp(), false, false
from scheduler_auth_fixture;
insert into app.user_profiles (user_id,organization_id,display_name,employee_code,role_code,is_active,created_at,updated_at)
select user_id, organization_id, 'Admin ' || fixture_key, 'PGTAP-SCHED-' || fixture_key, 'ADMIN', true, clock_timestamp(), clock_timestamp()
from scheduler_auth_fixture;
insert into scheduler.job_runs (job_code,scope_code,scope_key,organization_id,scheduled_slot,status_code,started_at,completed_at,summary,error_code,error_summary)
select 'CLAIM_DEADLINE', 'ORGANIZATION', organization_id::text, organization_id, '2026-08-14 01:00:00+00'::timestamptz, 'FAILED', clock_timestamp(), clock_timestamp(), '{"fixture":"other-org"}'::jsonb, 'SCHEDULER_DELEGATE_FAILED', 'Kegagalan organisasi lain tidak boleh bocor.'
from scheduler_auth_fixture where fixture_key = 'OTHER_ADMIN';
select set_config('request.jwt.claim.sub', (select user_id::text from scheduler_auth_fixture where fixture_key='CURRENT_ADMIN'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub',(select user_id::text from scheduler_auth_fixture where fixture_key='CURRENT_ADMIN'),'role','authenticated')::text, true);
set local role authenticated;
select is((select job ->> 'healthCode' from jsonb_array_elements(api.scheduler_operations_summary() -> 'jobs') job where job ->> 'jobCode' = 'CLAIM_DEADLINE'), 'NEVER_RUN', 'Admin organisasi saat ini tidak melihat kegagalan scheduler organisasi lain.');
select ok(api.scheduler_operations_summary()::text not like '%organisasi lain%', 'Read contract scheduler tidak membocorkan ringkasan kegagalan organisasi lain.');
reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claims', '{}', true);
select throws_ok($$select api.scheduler_operations_summary()$$, '42501', 'AUTHENTICATION_REQUIRED', 'Read contract scheduler menolak caller tanpa Admin session.');
select throws_ok($$insert into scheduler.job_runs (job_code,scope_code,scope_key,organization_id,scheduled_slot,status_code,summary) values ('NOTIFICATION_OUTBOX','GLOBAL','GLOBAL',null,'2026-08-14 01:23:00+00','STARTED','{}'::jsonb)$$, '23505', 'duplicate key value violates unique constraint "uq_scheduler_job_runs_slot"', 'Unique slot invariant ditahan database.');

select * from finish();
rollback;