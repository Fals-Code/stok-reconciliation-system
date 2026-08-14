begin;

-- Supabase Cron is pg_cron. Jobs execute SQL in this database; no HTTP
-- scheduler boundary or application secret is required.
create extension if not exists pg_cron;

create schema if not exists scheduler;
revoke all on schema scheduler from public, anon, authenticated, service_role;

create table scheduler.job_runs (
  id uuid primary key default gen_random_uuid(),
  job_code text not null,
  scope_code text not null,
  scope_key text not null,
  organization_id uuid null references app.organizations(id) on delete restrict,
  scheduled_slot timestamptz not null,
  status_code text not null default 'STARTED',
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz null,
  summary jsonb not null default '{}'::jsonb,
  error_code text null,
  error_summary text null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint ck_scheduler_job_runs_code check (job_code in ('NOTIFICATION_OUTBOX','CLAIM_DEADLINE','EXPIRY_DAILY','RECONCILIATION_DAILY')),
  constraint ck_scheduler_job_runs_scope check (scope_code in ('GLOBAL','ORGANIZATION')),
  constraint ck_scheduler_job_runs_scope_shape check ((scope_code = 'GLOBAL' and scope_key = 'GLOBAL' and organization_id is null) or (scope_code = 'ORGANIZATION' and scope_key = organization_id::text and organization_id is not null)),
  constraint ck_scheduler_job_runs_job_scope check ((job_code = 'NOTIFICATION_OUTBOX' and scope_code = 'GLOBAL') or (job_code in ('CLAIM_DEADLINE','EXPIRY_DAILY','RECONCILIATION_DAILY') and scope_code = 'ORGANIZATION')),
  constraint ck_scheduler_job_runs_status check (status_code in ('STARTED','SUCCEEDED','FAILED')),
  constraint ck_scheduler_job_runs_completion check ((status_code = 'STARTED' and completed_at is null and error_code is null and error_summary is null) or (status_code = 'SUCCEEDED' and completed_at is not null and error_code is null and error_summary is null) or (status_code = 'FAILED' and completed_at is not null and error_code is not null and error_summary is not null)),
  constraint ck_scheduler_job_runs_summary_object check (jsonb_typeof(summary) = 'object'),
  constraint ck_scheduler_job_runs_error_code_nonblank check (error_code is null or btrim(error_code) <> ''),
  constraint ck_scheduler_job_runs_error_summary_nonblank check (error_summary is null or btrim(error_summary) <> ''),
  constraint uq_scheduler_job_runs_slot unique (job_code, scope_key, scheduled_slot)
);
create index idx_scheduler_job_runs_scope_recent on scheduler.job_runs (scope_key, job_code, scheduled_slot desc);
alter table scheduler.job_runs enable row level security;
revoke all on scheduler.job_runs from public, anon, authenticated, service_role;

create or replace function scheduler.slot_for(p_job_code text, p_now timestamptz)
returns timestamptz language plpgsql immutable set search_path = pg_catalog as $$
begin
  if p_now is null then raise exception using errcode = 'P0001', message = 'SCHEDULER_TIME_REQUIRED'; end if;
  case p_job_code
    when 'NOTIFICATION_OUTBOX' then return date_trunc('minute', p_now);
    when 'CLAIM_DEADLINE' then return date_trunc('hour', p_now);
    when 'EXPIRY_DAILY', 'RECONCILIATION_DAILY' then return date_trunc('day', p_now at time zone 'Asia/Jakarta') at time zone 'Asia/Jakarta';
    else raise exception using errcode = 'P0001', message = 'SCHEDULER_JOB_CODE_INVALID';
  end case;
end;
$$;

create or replace function scheduler.run_daily_reconciliation(p_organization_id uuid, p_scheduled_slot timestamptz)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, scheduler, app, inventory, reconciliation, notification, api as $$
declare v_result jsonb; v_run_id uuid; v_outbox_result jsonb;
begin
  v_result := api.run_reconciliation(
    p_organization_id,
    'scheduler:reconciliation-daily:' || p_organization_id::text || ':' || to_char(p_scheduled_slot, 'YYYYMMDD'),
    array['LEDGER_BATCH_PROJECTION','BATCH_PRODUCT_PROJECTION','RESERVATION_CONSISTENCY','MARKETPLACE_ALLOCATION_CONSISTENCY','RETURN_RECEIPT_CONSISTENCY','RETURN_INSPECTION_CONSISTENCY','DUPLICATE_SOURCE_EFFECT','IMPOSSIBLE_PROJECTION_STATE']::text[],
    '{}'::jsonb,
    jsonb_build_object('source','scheduler','jobCode','RECONCILIATION_DAILY','scheduledSlot',p_scheduled_slot)
  );
  v_run_id := nullif(v_result ->> 'runId', '')::uuid;
  if v_run_id is null then raise exception using errcode = 'P0001', message = 'SCHEDULER_RECONCILIATION_RUN_ID_MISSING'; end if;
  update reconciliation.runs run_row set run_type_code = 'DAILY', trigger_code = 'SYSTEM', actor_user_id = null, process_name = 'scheduler.run_daily_reconciliation', metadata = run_row.metadata || jsonb_build_object('schedulerJobCode','RECONCILIATION_DAILY','scheduledSlot',p_scheduled_slot), updated_at = clock_timestamp()
  where run_row.id = v_run_id and run_row.organization_id = p_organization_id;
  if not found then raise exception using errcode = 'P0001', message = 'SCHEDULER_RECONCILIATION_PROVENANCE_UPDATE_FAILED'; end if;
  v_outbox_result := notification.enqueue_outbox_event(
    p_organization_id,
    'NOTIFICATION_RECONCILIATION_EVALUATION_REQUESTED',
    'scheduler:reconciliation-daily:' || p_organization_id::text || ':' || to_char(p_scheduled_slot, 'YYYYMMDD'),
    'RECONCILIATION_RUN', v_run_id, p_scheduled_slot,
    jsonb_build_object('reconciliationRunId',v_run_id,'scheduledSlot',p_scheduled_slot,'source','scheduler'),
    gen_random_uuid(), null, 'scheduler.run_daily_reconciliation'
  );
  return jsonb_build_object('reconciliation',v_result,'notificationOutbox',v_outbox_result);
end;
$$;

create or replace function scheduler.execute_scope(p_job_code text, p_scope_code text, p_scope_key text, p_organization_id uuid, p_scheduled_slot timestamptz, p_now timestamptz)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, scheduler, app, notification, reconciliation, inventory as $$
declare v_run scheduler.job_runs%rowtype; v_delegate_result jsonb; v_error_state text;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_job_code || ':' || p_scope_key || ':' || p_scheduled_slot::text, 0::bigint));
  insert into scheduler.job_runs (job_code,scope_code,scope_key,organization_id,scheduled_slot,status_code,started_at,summary)
  values (p_job_code,p_scope_code,p_scope_key,p_organization_id,p_scheduled_slot,'STARTED',p_now,'{}'::jsonb)
  on conflict (job_code,scope_key,scheduled_slot) do nothing returning * into v_run;
  if v_run.id is null then
    select * into v_run from scheduler.job_runs where job_code = p_job_code and scope_key = p_scope_key and scheduled_slot = p_scheduled_slot;
    return jsonb_build_object('action','REPLAYED','jobRunId',v_run.id,'status',v_run.status_code,'scheduledSlot',v_run.scheduled_slot,'summary',v_run.summary);
  end if;
  begin
    case p_job_code
      when 'NOTIFICATION_OUTBOX' then v_delegate_result := notification.process_outbox('scheduler:notification-outbox:' || extract(epoch from p_scheduled_slot)::bigint::text,100,p_now,interval '5 minutes',5,60,3600,'scheduler.notification_outbox');
      when 'CLAIM_DEADLINE' then v_delegate_result := notification.evaluate_tiktok_claim_deadlines(p_organization_id,'scheduler:claim-deadline:' || p_organization_id::text || ':' || to_char(p_scheduled_slot,'YYYYMMDDHH24'),p_now,'scheduler.claim_deadline');
      when 'EXPIRY_DAILY' then v_delegate_result := notification.evaluate_expiry(p_organization_id,'scheduler:expiry-daily:' || p_organization_id::text || ':' || to_char(p_scheduled_slot,'YYYYMMDD'),p_now,'SCHEDULED',gen_random_uuid(),'scheduler.expiry_daily');
      when 'RECONCILIATION_DAILY' then v_delegate_result := scheduler.run_daily_reconciliation(p_organization_id,p_scheduled_slot);
      else raise exception using errcode = 'P0001', message = 'SCHEDULER_JOB_CODE_INVALID';
    end case;
    update scheduler.job_runs set status_code='SUCCEEDED',completed_at=clock_timestamp(),summary=coalesce(v_delegate_result,'{}'::jsonb),updated_at=clock_timestamp() where id=v_run.id;
  exception when others then
    get stacked diagnostics v_error_state = returned_sqlstate;
    update scheduler.job_runs set status_code='FAILED',completed_at=clock_timestamp(),error_code='SCHEDULER_DELEGATE_FAILED',error_summary='Operasi terjadwal gagal dan perlu diperiksa.',summary=jsonb_build_object('sqlstate',v_error_state),updated_at=clock_timestamp() where id=v_run.id;
  end;
  select * into v_run from scheduler.job_runs where id=v_run.id;
  return jsonb_build_object('action','EXECUTED','jobRunId',v_run.id,'status',v_run.status_code,'scheduledSlot',v_run.scheduled_slot,'summary',v_run.summary,'errorCode',v_run.error_code);
end;
$$;

create or replace function scheduler.run_job_at(p_job_code text, p_now timestamptz)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, scheduler, app as $$
declare v_job_code text := upper(btrim(coalesce(p_job_code,''))); v_slot timestamptz; v_organization record; v_results jsonb := '[]'::jsonb;
begin
  if v_job_code not in ('NOTIFICATION_OUTBOX','CLAIM_DEADLINE','EXPIRY_DAILY','RECONCILIATION_DAILY') then raise exception using errcode='P0001', message='SCHEDULER_JOB_CODE_INVALID'; end if;
  v_slot := scheduler.slot_for(v_job_code,p_now);
  if v_job_code='NOTIFICATION_OUTBOX' then return scheduler.execute_scope(v_job_code,'GLOBAL','GLOBAL',null,v_slot,p_now); end if;
  for v_organization in select organization.id from app.organizations organization where organization.is_active order by organization.id loop
    v_results := v_results || jsonb_build_array(scheduler.execute_scope(v_job_code,'ORGANIZATION',v_organization.id::text,v_organization.id,v_slot,p_now));
  end loop;
  return jsonb_build_object('jobCode',v_job_code,'scheduledSlot',v_slot,'results',v_results);
end;
$$;

create or replace function scheduler.run_production_job(p_job_code text)
returns jsonb language sql security definer set search_path = pg_catalog, scheduler as $$
  select scheduler.run_job_at(p_job_code, clock_timestamp());
$$;

create or replace function scheduler.operations_summary(p_organization_id uuid, p_now timestamptz)
returns jsonb language sql security definer stable set search_path = pg_catalog, scheduler as $$
  with catalog(job_code,scope_key,stale_after) as (
    values ('NOTIFICATION_OUTBOX'::text,'GLOBAL'::text,interval '5 minutes'),('CLAIM_DEADLINE'::text,p_organization_id::text,interval '2 hours'),('EXPIRY_DAILY'::text,p_organization_id::text,interval '30 hours'),('RECONCILIATION_DAILY'::text,p_organization_id::text,interval '30 hours')
  ), latest as (
    select distinct on (run_row.job_code,run_row.scope_key) run_row.job_code,run_row.scope_key,run_row.status_code,run_row.scheduled_slot,run_row.completed_at,run_row.error_summary
    from scheduler.job_runs run_row where run_row.scope_key='GLOBAL' or run_row.organization_id=p_organization_id order by run_row.job_code,run_row.scope_key,run_row.scheduled_slot desc,run_row.created_at desc
  )
  select jsonb_build_object('generatedAt',p_now,'jobs',coalesce(jsonb_agg(jsonb_build_object('jobCode',catalog.job_code,'healthCode',case when latest.status_code='FAILED' then 'FAILED' when latest.status_code='SUCCEEDED' and latest.completed_at >= p_now-catalog.stale_after then 'HEALTHY' when latest.status_code is null then 'NEVER_RUN' else 'STALE' end,'lastScheduledSlot',latest.scheduled_slot,'lastCompletedAt',latest.completed_at,'lastFailureSummary',case when latest.status_code='FAILED' then latest.error_summary else null end) order by catalog.job_code),'[]'::jsonb)) from catalog left join latest on latest.job_code=catalog.job_code and latest.scope_key=catalog.scope_key;
$$;

create or replace function api.scheduler_operations_summary()
returns jsonb language plpgsql security definer stable set search_path = pg_catalog, auth, app, scheduler as $$
declare v_actor_user_id uuid := auth.uid(); v_organization_id uuid;
begin
  if v_actor_user_id is null then raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED'; end if;
  v_organization_id := app.current_organization_id();
  if v_organization_id is null or not app.is_admin() then raise exception using errcode='42501',message='ADMIN_ACCESS_REQUIRED'; end if;
  return scheduler.operations_summary(v_organization_id,clock_timestamp());
end;
$$;

revoke all on function scheduler.slot_for(text,timestamptz) from public, anon, authenticated, service_role;
revoke all on function scheduler.run_daily_reconciliation(uuid,timestamptz) from public, anon, authenticated, service_role;
revoke all on function scheduler.execute_scope(text,text,text,uuid,timestamptz,timestamptz) from public, anon, authenticated, service_role;
revoke all on function scheduler.run_job_at(text,timestamptz) from public, anon, authenticated, service_role;
revoke all on function scheduler.run_production_job(text) from public, anon, authenticated, service_role;
revoke all on function scheduler.operations_summary(uuid,timestamptz) from public, anon, authenticated, service_role;
revoke all on function api.scheduler_operations_summary() from public, anon;
grant execute on function api.scheduler_operations_summary() to authenticated;

revoke all on schema cron from public, anon, authenticated;
revoke all on function cron.schedule(text,text,text) from public, anon, authenticated;
revoke all on function cron.unschedule(bigint) from public, anon, authenticated;
select cron.unschedule(jobid) from cron.job where jobname in ('phase2-notification-outbox','phase2-claim-deadline','phase2-expiry-daily','phase2-reconciliation-daily');
select cron.schedule('phase2-notification-outbox','* * * * *',$$select scheduler.run_production_job('NOTIFICATION_OUTBOX');$$);
select cron.schedule('phase2-claim-deadline','7 * * * *',$$select scheduler.run_production_job('CLAIM_DEADLINE');$$);
-- pg_cron uses UTC locally; 17:10 UTC is 00:10 Asia/Jakarta the next day.
select cron.schedule('phase2-expiry-daily','10 17 * * *',$$select scheduler.run_production_job('EXPIRY_DAILY');$$);
-- Run after expiry and the minute worker has had time to dispatch prior work.
select cron.schedule('phase2-reconciliation-daily','25 17 * * *',$$select scheduler.run_production_job('RECONCILIATION_DAILY');$$);

commit;