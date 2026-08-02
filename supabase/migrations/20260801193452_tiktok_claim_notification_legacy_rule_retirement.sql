begin;

-- The active-rule uniqueness invariant is organization/code scoped.  Close a
-- generic legacy row in the same transaction before the canonical successor
-- is inserted; retain the row and its foreign-key history.
do $$
declare
  v_definition text;
  v_marker constant text := '  v_version := case';
  v_retirement constant text := $replacement$
  update notification.rules rule
  set is_active = false,
      effective_to = p_effective_at,
      updated_at = clock_timestamp()
  where rule.organization_id = p_organization_id
    and rule.code = p_code
    and rule.entity_type_code <> 'RETURN_CLAIM'
    and rule.is_active
    and rule.effective_from <= p_effective_at
    and (rule.effective_to is null or rule.effective_to > p_effective_at);

  v_version := case$replacement$;
begin
  select pg_get_functiondef(
    'notification.ensure_tiktok_claim_rule(uuid,text,timestamptz)'::regprocedure
  ) into v_definition;
  if position(v_marker in v_definition) = 0 then
    raise exception using errcode = 'P0001', message = 'CLAIM_NOTIFICATION_RULE_PROVISIONER_SOURCE_UNEXPECTED';
  end if;
  v_definition := replace(v_definition, v_marker, v_retirement);
  if position('entity_type_code <> ''RETURN_CLAIM''' in v_definition) = 0 then
    raise exception using errcode = 'P0001', message = 'CLAIM_NOTIFICATION_RULE_PROVISIONER_INSTALL_INCOMPLETE';
  end if;
  execute v_definition;
end;
$$;

revoke all on function notification.ensure_tiktok_claim_rule(uuid,text,timestamptz) from public, anon, authenticated;

commit;
