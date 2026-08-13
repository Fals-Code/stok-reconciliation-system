begin;

do $$
declare
  v_organization_id uuid;
  v_observed_at timestamptz := clock_timestamp();
begin
  for v_organization_id in
    select distinct audit.organization_id
    from catalog.master_data_audit_events audit
    join app.organizations organization
      on organization.id = audit.organization_id
     and organization.is_active
    where audit.entity_type_code = 'BATCH'
      and audit.action_code = 'BATCH_UPDATE'
      and nullif(audit.before_snapshot ->> 'expiryDate', '')
          is distinct from
          nullif(audit.after_snapshot ->> 'expiryDate', '')
      and not exists (
        select 1
        from notification.outbox_events existing_event
        where existing_event.organization_id = audit.organization_id
          and existing_event.event_type_code = 'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED'
          and existing_event.source_event_key = 'migration:20260812191758:active-expiry-reevaluation:' || audit.organization_id::text
      )
    order by audit.organization_id
  loop
    perform notification.enqueue_outbox_event(
      p_organization_id => v_organization_id,
      p_event_type_code => 'NOTIFICATION_EXPIRY_EVALUATION_REQUESTED',
      p_source_event_key => 'migration:20260812201000:expiry-reevaluation-backfill:' || v_organization_id::text,
      p_entity_type_code => 'ORGANIZATION',
      p_entity_id => v_organization_id,
      p_occurred_at => v_observed_at,
      p_payload => jsonb_build_object(
        'schemaVersion', 1,
        'requestType', 'MIGRATION_EXPIRY_REEVALUATION_BACKFILL_REPAIR',
        'migration', '20260812201000_product_batch_expiry_notification_backfill_repair'
      ),
      p_actor_user_id => null,
      p_process_name => 'migration.product_batch_expiry_notification_backfill_repair'
    );
  end loop;
end;
$$;

commit;
