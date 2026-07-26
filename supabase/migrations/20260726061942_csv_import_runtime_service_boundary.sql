begin;

create or replace function api.validate_marketplace_csv_import_job_trusted(
  p_organization_id uuid,
  p_job_id uuid,
  p_file_sha256 text,
  p_rows jsonb,
  p_parse_errors jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, integration, operations, api, extensions
as $$
begin
  if coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'CSV_IMPORT_VALIDATION_SERVICE_REQUIRED';
  end if;
  perform pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
  return api.validate_marketplace_csv_import_job(
    p_organization_id,
    p_job_id,
    p_file_sha256,
    p_rows,
    p_parse_errors
  );
end;
$$;

comment on function api.validate_marketplace_csv_import_job_trusted(uuid, uuid, text, jsonb, jsonb) is
  'Service-role compatibility boundary for the existing canonical CSV validation function. It does not post domain events.';

revoke all on function api.validate_marketplace_csv_import_job_trusted(uuid, uuid, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function api.validate_marketplace_csv_import_job_trusted(uuid, uuid, text, jsonb, jsonb) to service_role;

create or replace function api.commit_marketplace_csv_import_job_trusted(
  p_organization_id uuid,
  p_import_job_id uuid,
  p_commit_idempotency_key text,
  p_confirmation boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, integration, operations, api, extensions
as $$
begin
  if coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'CSV_IMPORT_COMMIT_SERVICE_REQUIRED';
  end if;
  perform pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
  return api.commit_marketplace_csv_import_job(
    p_organization_id,
    p_import_job_id,
    p_commit_idempotency_key,
    p_confirmation
  );
end;
$$;

comment on function api.commit_marketplace_csv_import_job_trusted(uuid, uuid, text, boolean) is
  'Service-role compatibility boundary for the atomic canonical CSV commit. Shipment, cancellation, return, and direct stock writes remain unsupported.';

revoke all on function api.commit_marketplace_csv_import_job_trusted(uuid, uuid, text, boolean) from public, anon, authenticated;
grant execute on function api.commit_marketplace_csv_import_job_trusted(uuid, uuid, text, boolean) to service_role;

commit;
