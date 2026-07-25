begin;

create or replace function notification.ensure_tiktok_claim_rule(p_organization_id uuid,p_code text,p_effective_at timestamptz) returns uuid language plpgsql security definer set search_path = pg_catalog, notification, app as $$
declare v_id uuid; v_config jsonb; v_next_effective_from timestamptz; v_version text;
begin
  if p_organization_id is null or p_effective_at is null or p_code not in ('CLAIM_DEADLINE','CLAIM_BASIS_MISSING') then raise exception using errcode='P0001',message='CLAIM_NOTIFICATION_RULE_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':TIKTOK_CLAIM_RULE:'||p_code,0));
  select id into v_id from notification.rules where organization_id=p_organization_id and code=p_code and is_active and effective_from<=p_effective_at and (effective_to is null or effective_to>p_effective_at) order by effective_from desc limit 1;
  if v_id is not null then return v_id; end if;
  select min(effective_from) into v_next_effective_from from notification.rules where organization_id=p_organization_id and code=p_code and is_active and effective_from>p_effective_at;
  v_version:=case when exists(select 1 from notification.rules where organization_id=p_organization_id and code=p_code) then '1.0.0-effective-'||replace(gen_random_uuid()::text,'-','') else '1.0.0' end;
  v_config := case when p_code='CLAIM_DEADLINE' then jsonb_build_object('schemaVersion',1,'stages',jsonb_build_array('D14','D7','D3','D1','DUE_TODAY','OVERDUE'),'deadlineField','deadline_at') else jsonb_build_object('schemaVersion',1,'stage','BASIS_MISSING') end;
  insert into notification.rules(organization_id,code,version,category_code,trigger_mode_code,entity_type_code,severity_strategy_code,stage_strategy_code,condition_strategy_code,resolution_strategy_code,template_version,action_code,config,is_active,effective_from,effective_to,created_at,updated_at)
  values(p_organization_id,p_code,v_version,'RETURN','HYBRID','RETURN_CLAIM','TIKTOK_CLAIM_V1','TIKTOK_CLAIM_V1','TIKTOK_CLAIM_V1','TIKTOK_CLAIM_V1','1.0.0','OPEN_RETURN_CLAIM_DETAIL',v_config,true,p_effective_at,v_next_effective_from,clock_timestamp(),clock_timestamp()) returning id into v_id;
  return v_id;
end $$;

revoke all on function notification.ensure_tiktok_claim_rule(uuid,text,timestamptz) from public, anon, authenticated;

commit;
