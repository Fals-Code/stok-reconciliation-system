begin;

-- 019 creates the claim and 020 provides the existing outbox primitive, but
-- neither migration connected the successful claim-create write to that
-- primitive.  Keep the command RPC immutable and attach the durable request
-- to the authoritative insert instead.  The outbox unique source key makes a
-- replay impossible to duplicate, while a failed enqueue rolls back the claim
-- command atomically.
create or replace function operations.enqueue_tiktok_claim_deadline_evaluation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, notification
as $$
begin
  perform notification.enqueue_outbox_event(
    p_organization_id => new.organization_id,
    p_event_type_code => 'TIKTOK_CLAIM_DEADLINE_EVALUATION_REQUEST',
    p_source_event_key => 'tiktok-claim-evaluation:claim:' || new.id::text,
    p_entity_type_code => 'RETURN_CLAIM',
    p_entity_id => new.id,
    p_occurred_at => new.created_at,
    p_payload => jsonb_build_object(
      'schemaVersion', 1,
      'claimId', new.id,
      'returnId', new.return_id,
      'deadlineAt', new.deadline_at,
      'stockEffectCode', 'NONE'
    ),
    p_correlation_id => gen_random_uuid(),
    p_actor_user_id => new.actor_user_id,
    p_process_name => new.process_name
  );

  return new;
end;
$$;

drop trigger if exists trg_return_claim_enqueue_deadline_evaluation on operations.return_claims;
create trigger trg_return_claim_enqueue_deadline_evaluation
after insert on operations.return_claims
for each row execute function operations.enqueue_tiktok_claim_deadline_evaluation();

revoke all on function operations.enqueue_tiktok_claim_deadline_evaluation() from public, anon, authenticated;

commit;
