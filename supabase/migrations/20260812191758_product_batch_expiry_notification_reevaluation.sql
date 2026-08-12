begin;

create or replace function catalog.enqueue_product_batch_expiry_reevaluation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, catalog, notification
as $$
declare
  v_before_expiry text := nullif(new.before_snapshot ->> 'expiryDate', '');
  v_after_expiry text := nullif(new.after_snapshot ->> 'expiryDate', '');
begin
  if new.entity_type_code <> 'BATCH'
     or new.action_code <> 'BATCH_UPDATE'
     or v_before_expiry is not distinct from v_after_expiry then
    return new;
  end if;

  perform notification.enqueue_outbox_event(
    p_organization_id => new.organization_id,
    p_event_type_code => 'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
    p_source_event_key => 'product-batch-expiry-reevaluation:' || new.id::text,
    p_entity_type_code => 'ORGANIZATION',
    p_entity_id => new.organization_id,
    p_occurred_at => new.occurred_at,
    p_payload => jsonb_build_object(
      'auditId', new.id,
      'batchId', new.entity_id,
      'beforeExpiryDate', v_before_expiry,
      'afterExpiryDate', v_after_expiry,
      'reason', new.reason
    ),
    p_actor_user_id => new.actor_user_id,
    p_process_name => new.process_name
  );

  return new;
end;
$$;

revoke all on function catalog.enqueue_product_batch_expiry_reevaluation()
from public, anon, authenticated, service_role;

create trigger trg_master_data_audit_batch_expiry_reevaluation
after insert on catalog.master_data_audit_events
for each row
when (
  new.entity_type_code = 'BATCH'
  and new.action_code = 'BATCH_UPDATE'
)
execute function catalog.enqueue_product_batch_expiry_reevaluation();


do $$
declare
  v_organization_id uuid;
  v_observed_at timestamptz := clock_timestamp();
begin
  for v_organization_id in
    select distinct notification_row.organization_id
    from notification.notifications notification_row
    join app.organizations organization
      on organization.id = notification_row.organization_id
     and organization.is_active
    where notification_row.rule_code_snapshot = 'EXPIRY_RISK'
      and notification_row.entity_type_code = 'PRODUCT_BATCH'
      and notification_row.lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  loop
    perform notification.enqueue_outbox_event(
      p_organization_id => v_organization_id,
      p_event_type_code => 'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
      p_source_event_key => 'migration:20260812191758:active-expiry-reevaluation:' || v_organization_id::text,
      p_entity_type_code => 'ORGANIZATION',
      p_entity_id => v_organization_id,
      p_occurred_at => v_observed_at,
      p_payload => jsonb_build_object(
        'schemaVersion', 1,
        'requestType', 'MIGRATION_ACTIVE_EXPIRY_REEVALUATION',
        'migration', '20260812191758_product_batch_expiry_notification_reevaluation'
      ),
      p_actor_user_id => null,
      p_process_name => 'migration.product_batch_expiry_notification_reevaluation'
    );
  end loop;
end;
$$;

commit;
