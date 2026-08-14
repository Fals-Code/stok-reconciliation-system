begin;

-- A Jakarta daily slot is stored as its UTC instant (17:00 on the prior
-- calendar day). Derive external idempotency keys in Jakarta, never from the
-- database session timezone used by pg_cron.
create or replace function scheduler.run_daily_reconciliation(p_organization_id uuid, p_scheduled_slot timestamptz)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, scheduler, app, inventory, reconciliation, notification, api as $$
declare v_result jsonb; v_run_id uuid; v_outbox_result jsonb; v_slot_date text;
begin
  v_slot_date := to_char(p_scheduled_slot at time zone 'Asia/Jakarta', 'YYYYMMDD');
  v_result := api.run_reconciliation(
    p_organization_id,
    'scheduler:reconciliation-daily:' || p_organization_id::text || ':' || v_slot_date,
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
    'scheduler:reconciliation-daily:' || p_organization_id::text || ':' || v_slot_date,
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
declare v_run scheduler.job_runs%rowtype; v_delegate_result jsonb; v_error_state text; v_slot_date text;
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
      when 'EXPIRY_DAILY' then
        v_slot_date := to_char(p_scheduled_slot at time zone 'Asia/Jakarta','YYYYMMDD');
        v_delegate_result := notification.evaluate_expiry(p_organization_id,'scheduler:expiry-daily:' || p_organization_id::text || ':' || v_slot_date,p_now,'SCHEDULED',gen_random_uuid(),'scheduler.expiry_daily');
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

revoke all on function scheduler.run_daily_reconciliation(uuid,timestamptz) from public, anon, authenticated, service_role;
revoke all on function scheduler.execute_scope(text,text,text,uuid,timestamptz,timestamptz) from public, anon, authenticated, service_role;

commit;
