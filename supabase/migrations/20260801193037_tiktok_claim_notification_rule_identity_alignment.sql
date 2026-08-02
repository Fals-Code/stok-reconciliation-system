begin;

-- A CLAIM_DEADLINE rule is a return-claim notification contract.  Older seed
-- data used the generic CLAIM entity, which made a successfully-created
-- notification invisible to the RETURN_CLAIM read model.
create or replace function notification.ensure_tiktok_claim_rule(
  p_organization_id uuid,
  p_code text,
  p_effective_at timestamptz
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, notification, app
as $$
declare
  v_id uuid;
  v_count integer;
  v_config jsonb;
  v_next_effective_from timestamptz;
  v_version text;
begin
  if p_organization_id is null
     or p_effective_at is null
     or p_code not in ('CLAIM_DEADLINE', 'CLAIM_BASIS_MISSING') then
    raise exception using errcode = 'P0001', message = 'CLAIM_NOTIFICATION_RULE_INVALID';
  end if;

  v_config := case p_code
    when 'CLAIM_DEADLINE' then jsonb_build_object(
      'schemaVersion', 1,
      'stages', jsonb_build_array('D14','D7','D3','D1','DUE_TODAY','OVERDUE'),
      'deadlineField', 'deadline_at'
    )
    else jsonb_build_object('schemaVersion', 1, 'stage', 'BASIS_MISSING')
  end;

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':TIKTOK_CLAIM_RULE:' || p_code, 0)
  );

  select count(*) into v_count
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = p_code
    and rule.category_code = 'RETURN'
    and rule.trigger_mode_code = 'HYBRID'
    and rule.entity_type_code = 'RETURN_CLAIM'
    and rule.severity_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.stage_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.condition_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.resolution_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.template_version = '1.0.0'
    and rule.action_code = 'OPEN_RETURN_CLAIM_DETAIL'
    and rule.config = v_config
    and rule.is_active
    and rule.effective_from <= p_effective_at
    and (rule.effective_to is null or rule.effective_to > p_effective_at);

  if v_count > 1 then
    raise exception using errcode = 'P0001', message = 'CLAIM_NOTIFICATION_CANONICAL_RULE_AMBIGUOUS';
  end if;
  if v_count = 1 then
    select rule.id into v_id
    from notification.rules rule
    where rule.organization_id = p_organization_id
      and rule.code = p_code
      and rule.category_code = 'RETURN'
      and rule.trigger_mode_code = 'HYBRID'
      and rule.entity_type_code = 'RETURN_CLAIM'
      and rule.severity_strategy_code = 'TIKTOK_CLAIM_V1'
      and rule.stage_strategy_code = 'TIKTOK_CLAIM_V1'
      and rule.condition_strategy_code = 'TIKTOK_CLAIM_V1'
      and rule.resolution_strategy_code = 'TIKTOK_CLAIM_V1'
      and rule.template_version = '1.0.0'
      and rule.action_code = 'OPEN_RETURN_CLAIM_DETAIL'
      and rule.config = v_config
      and rule.is_active
      and rule.effective_from <= p_effective_at
      and (rule.effective_to is null or rule.effective_to > p_effective_at);
    return v_id;
  end if;

  select min(rule.effective_from) into v_next_effective_from
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = p_code
    and rule.category_code = 'RETURN'
    and rule.trigger_mode_code = 'HYBRID'
    and rule.entity_type_code = 'RETURN_CLAIM'
    and rule.is_active
    and rule.effective_from > p_effective_at;

  v_version := case
    when exists (
      select 1 from notification.rules rule
      where rule.organization_id = p_organization_id and rule.code = p_code
    ) then '1.0.0-return-claim-' || replace(gen_random_uuid()::text, '-', '')
    else '1.0.0'
  end;

  insert into notification.rules(
    organization_id, code, version, category_code, trigger_mode_code,
    entity_type_code, severity_strategy_code, stage_strategy_code,
    condition_strategy_code, resolution_strategy_code, template_version,
    action_code, config, is_active, effective_from, effective_to, created_at, updated_at
  ) values (
    p_organization_id, p_code, v_version, 'RETURN', 'HYBRID',
    'RETURN_CLAIM', 'TIKTOK_CLAIM_V1', 'TIKTOK_CLAIM_V1',
    'TIKTOK_CLAIM_V1', 'TIKTOK_CLAIM_V1', '1.0.0',
    'OPEN_RETURN_CLAIM_DETAIL', v_config, true, p_effective_at,
    v_next_effective_from, clock_timestamp(), clock_timestamp()
  ) returning id into v_id;
  return v_id;
end;
$$;

-- One cutover instant closes every currently-effective legacy CLAIM_DEADLINE
-- rule and provisions exactly one canonical successor for its organization.
do $$
declare
  v_cutover timestamptz := clock_timestamp();
  v_organization_id uuid;
  v_canonical_count integer;
begin
  for v_organization_id in
    select distinct rule.organization_id
    from notification.rules rule
    where rule.code = 'CLAIM_DEADLINE'
      and rule.entity_type_code <> 'RETURN_CLAIM'
      and rule.is_active
      and rule.effective_from <= v_cutover
      and (rule.effective_to is null or rule.effective_to > v_cutover)
    order by rule.organization_id
  loop
    perform pg_advisory_xact_lock(
      hashtextextended(v_organization_id::text || ':TIKTOK_CLAIM_RULE:CLAIM_DEADLINE', 0)
    );
    select count(*) into v_canonical_count
    from notification.rules rule
    where rule.organization_id = v_organization_id
      and rule.code = 'CLAIM_DEADLINE'
      and rule.entity_type_code = 'RETURN_CLAIM'
      and rule.is_active
      and rule.effective_from <= v_cutover
      and (rule.effective_to is null or rule.effective_to > v_cutover);
    if v_canonical_count > 1 then
      raise exception using errcode = 'P0001', message = 'CLAIM_NOTIFICATION_CANONICAL_RULE_AMBIGUOUS';
    end if;

    update notification.rules rule
    set is_active = false,
        effective_to = v_cutover,
        updated_at = v_cutover
    where rule.organization_id = v_organization_id
      and rule.code = 'CLAIM_DEADLINE'
      and rule.entity_type_code <> 'RETURN_CLAIM'
      and rule.is_active
      and rule.effective_from <= v_cutover
      and (rule.effective_to is null or rule.effective_to > v_cutover);

    if v_canonical_count = 0 then
      perform notification.ensure_tiktok_claim_rule(
        v_organization_id, 'CLAIM_DEADLINE', v_cutover
      );
    end if;
  end loop;
end;
$$;

-- Evaluator selection is asserted separately from provisioning so a legacy
-- row can never be used if a future caller bypasses ensure.
create or replace function notification.require_tiktok_claim_deadline_rule(
  p_organization_id uuid,
  p_observed_at timestamptz
) returns notification.rules
language plpgsql
security definer
set search_path = pg_catalog, notification
as $$
declare
  v_rule notification.rules%rowtype;
  v_count integer;
  v_config jsonb := jsonb_build_object(
    'schemaVersion', 1,
    'stages', jsonb_build_array('D14','D7','D3','D1','DUE_TODAY','OVERDUE'),
    'deadlineField', 'deadline_at'
  );
begin
  select count(*) into v_count
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'CLAIM_DEADLINE'
    and rule.category_code = 'RETURN'
    and rule.trigger_mode_code = 'HYBRID'
    and rule.entity_type_code = 'RETURN_CLAIM'
    and rule.severity_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.stage_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.condition_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.resolution_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.template_version = '1.0.0'
    and rule.action_code = 'OPEN_RETURN_CLAIM_DETAIL'
    and rule.config = v_config
    and rule.is_active
    and rule.effective_from <= p_observed_at
    and (rule.effective_to is null or rule.effective_to > p_observed_at);
  if v_count <> 1 then
    raise exception using errcode = 'P0001', message = 'CLAIM_NOTIFICATION_CANONICAL_RULE_NOT_EXACT';
  end if;
  select rule.* into v_rule
  from notification.rules rule
  where rule.organization_id = p_organization_id
    and rule.code = 'CLAIM_DEADLINE'
    and rule.category_code = 'RETURN'
    and rule.trigger_mode_code = 'HYBRID'
    and rule.entity_type_code = 'RETURN_CLAIM'
    and rule.severity_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.stage_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.condition_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.resolution_strategy_code = 'TIKTOK_CLAIM_V1'
    and rule.template_version = '1.0.0'
    and rule.action_code = 'OPEN_RETURN_CLAIM_DETAIL'
    and rule.config = v_config
    and rule.is_active
    and rule.effective_from <= p_observed_at
    and (rule.effective_to is null or rule.effective_to > p_observed_at);
  return v_rule;
end;
$$;

-- Preserve the final evaluator body installed by migration 034 and replace
-- only its previously broad effective-rule lookup.  The substitution is
-- asserted once, so an unexpected historical function definition fails the
-- forward migration rather than silently installing a partial evaluator.
do $$
declare
  v_definition text;
  v_legacy_lookup constant text := 'select * into strict v_rule from notification.rules where organization_id=p_organization_id and code=''CLAIM_DEADLINE'' and is_active and effective_from<=p_observed_at and (effective_to is null or effective_to>p_observed_at) order by effective_from desc,created_at desc limit 1;';
  v_canonical_lookup constant text := 'select notification.require_tiktok_claim_deadline_rule(p_organization_id,p_observed_at) into v_rule;';
begin
  select pg_get_functiondef(
    'notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamptz,text)'::regprocedure
  ) into v_definition;
  if position(v_legacy_lookup in v_definition) <> 1
     and position(v_legacy_lookup in v_definition) = 0 then
    raise exception using errcode = 'P0001', message = 'CLAIM_NOTIFICATION_EVALUATOR_SOURCE_UNEXPECTED';
  end if;
  v_definition := replace(v_definition, v_legacy_lookup, v_canonical_lookup);
  if position(v_canonical_lookup in v_definition) = 0 then
    raise exception using errcode = 'P0001', message = 'CLAIM_NOTIFICATION_EVALUATOR_INSTALL_INCOMPLETE';
  end if;
  execute v_definition;
end;
$$;

revoke all on function notification.ensure_tiktok_claim_rule(uuid,text,timestamptz) from public, anon, authenticated;
revoke all on function notification.require_tiktok_claim_deadline_rule(uuid,timestamptz) from public, anon, authenticated;
revoke all on function notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamptz,text) from public, anon, authenticated;
grant execute on function notification.evaluate_tiktok_claim_deadlines(uuid,text,timestamptz,text) to service_role;

commit;
