begin;

-- A function returning notification.rules is a composite row, not a scalar
-- UUID.  Keep the evaluator's row variable intact while retaining canonical
-- identity enforcement.
do $$
declare
  v_definition text;
  v_incorrect constant text := 'select notification.require_tiktok_claim_deadline_rule(p_organization_id,p_observed_at) into v_rule;';
  v_correct constant text := 'select * into strict v_rule from notification.require_tiktok_claim_deadline_rule(p_organization_id,p_observed_at);';
begin
  select pg_get_functiondef(
    'notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamptz,text)'::regprocedure
  ) into v_definition;
  if position(v_incorrect in v_definition) = 0 then
    raise exception using errcode = 'P0001', message = 'CLAIM_NOTIFICATION_EVALUATOR_SELECTOR_SOURCE_UNEXPECTED';
  end if;
  v_definition := replace(v_definition, v_incorrect, v_correct);
  execute v_definition;
end;
$$;

revoke all on function notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamptz,text) from public, anon, authenticated;
grant execute on function notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamptz,text) to service_role;

commit;
