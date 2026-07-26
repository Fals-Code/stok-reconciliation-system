begin;

revoke all on function api.submit_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  from public, anon, authenticated;
drop function api.submit_tiktok_return_claim(uuid, text, uuid, text, timestamptz);

create function api.submit_tiktok_return_claim(
  p_organization_id uuid,
  p_idempotency_key text,
  p_claim_id uuid,
  p_external_claim_ref text,
  p_occurred_at timestamptz default clock_timestamp()
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, api
as $$
  select api.transition_tiktok_return_claim(
    p_organization_id,
    p_idempotency_key,
    p_claim_id,
    'SUBMIT',
    p_external_claim_ref,
    null,
    null,
    p_occurred_at
  )
$$;

revoke all on function api.submit_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function api.submit_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  to authenticated, service_role;
comment on function api.submit_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  is 'Named PostgREST boundary for TikTok return-claim submission lifecycle.';

revoke all on function api.resolve_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  from public, anon, authenticated;
drop function api.resolve_tiktok_return_claim(uuid, text, uuid, text, timestamptz);

create function api.resolve_tiktok_return_claim(
  p_organization_id uuid,
  p_idempotency_key text,
  p_claim_id uuid,
  p_resolution_code text,
  p_occurred_at timestamptz default clock_timestamp()
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, api
as $$
  select api.transition_tiktok_return_claim(
    p_organization_id,
    p_idempotency_key,
    p_claim_id,
    'RESOLVE',
    null,
    p_resolution_code,
    null,
    p_occurred_at
  )
$$;

revoke all on function api.resolve_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function api.resolve_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  to authenticated, service_role;
comment on function api.resolve_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  is 'Named PostgREST boundary for TikTok return-claim resolution lifecycle.';

revoke all on function api.cancel_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  from public, anon, authenticated;
drop function api.cancel_tiktok_return_claim(uuid, text, uuid, text, timestamptz);

create function api.cancel_tiktok_return_claim(
  p_organization_id uuid,
  p_idempotency_key text,
  p_claim_id uuid,
  p_reason text,
  p_occurred_at timestamptz default clock_timestamp()
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, api
as $$
  select api.transition_tiktok_return_claim(
    p_organization_id,
    p_idempotency_key,
    p_claim_id,
    'CANCEL',
    null,
    null,
    p_reason,
    p_occurred_at
  )
$$;

revoke all on function api.cancel_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function api.cancel_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  to authenticated, service_role;
comment on function api.cancel_tiktok_return_claim(uuid, text, uuid, text, timestamptz)
  is 'Named PostgREST boundary for TikTok return-claim cancellation lifecycle.';

revoke all on function api.evaluate_tiktok_return_claim_deadline(uuid, text, uuid, timestamptz)
  from public, anon, authenticated;
drop function api.evaluate_tiktok_return_claim_deadline(uuid, text, uuid, timestamptz);

create function api.evaluate_tiktok_return_claim_deadline(
  p_organization_id uuid,
  p_idempotency_key text,
  p_claim_id uuid,
  p_observed_at timestamptz default clock_timestamp()
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, api
as $$
  select api.transition_tiktok_return_claim(
    p_organization_id,
    p_idempotency_key,
    p_claim_id,
    'EVALUATE',
    null,
    null,
    null,
    p_observed_at
  )
$$;

revoke all on function api.evaluate_tiktok_return_claim_deadline(uuid, text, uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function api.evaluate_tiktok_return_claim_deadline(uuid, text, uuid, timestamptz)
  to authenticated, service_role;
comment on function api.evaluate_tiktok_return_claim_deadline(uuid, text, uuid, timestamptz)
  is 'Named PostgREST boundary for TikTok return-claim deadline evaluation lifecycle.';

commit;
