begin;

create schema if not exists integration;
revoke all on schema integration from public;
grant usage on schema integration to authenticated, service_role;

create table if not exists integration.import_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id),
  uploaded_by uuid,
  created_by_process text,
  import_type_code text not null default 'ORDER',
  template_version text not null default 'MARKETPLACE_RESERVATION_V1',
  status_code text not null default 'UPLOADED',
  original_file_name text not null,
  object_path text not null,
  detected_mime text not null,
  file_size_bytes bigint not null,
  file_sha256 text not null,
  job_command_key text not null,
  job_request_hash text not null,
  row_count integer not null default 0,
  valid_row_count integer not null default 0,
  invalid_row_count integer not null default 0,
  duplicate_row_count integer not null default 0,
  conflict_row_count integer not null default 0,
  processed_row_count integer not null default 0,
  expanded_line_count integer not null default 0,
  failure_code text,
  failure_detail text,
  uploaded_at timestamptz not null default now(),
  validated_at timestamptz,
  committed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint import_jobs_actor_check check (uploaded_by is not null or created_by_process is not null),
  constraint import_jobs_type_check check (import_type_code = 'ORDER'),
  constraint import_jobs_template_check check (template_version = 'MARKETPLACE_RESERVATION_V1'),
  constraint import_jobs_status_check check (status_code in ('UPLOADED', 'VALIDATING', 'READY', 'VALIDATION_FAILED', 'COMMITTING', 'COMPLETED', 'COMMIT_FAILED', 'CANCELLED')),
  constraint import_jobs_filename_check check (length(btrim(original_file_name)) between 1 and 255 and original_file_name !~ '[\\/\\x00]'),
  constraint import_jobs_object_path_check check (object_path ~ ('^' || organization_id::text || '/[0-9a-f-]{36}/[0-9a-f]{32}[.]csv$')),
  constraint import_jobs_mime_check check (detected_mime in ('text/csv', 'application/csv', 'text/plain')),
  constraint import_jobs_size_check check (file_size_bytes > 0 and file_size_bytes <= 10485760),
  constraint import_jobs_file_hash_check check (file_sha256 ~ '^[0-9a-f]{64}$'),
  constraint import_jobs_command_key_check check (length(btrim(job_command_key)) between 1 and 200),
  constraint import_jobs_request_hash_check check (job_request_hash ~ '^[0-9a-f]{64}$'),
  constraint import_jobs_counts_check check (
    row_count between 0 and 100000
    and valid_row_count >= 0
    and invalid_row_count >= 0
    and duplicate_row_count >= 0
    and conflict_row_count >= 0
    and processed_row_count between 0 and valid_row_count
    and expanded_line_count between 0 and 20000000
    and valid_row_count + invalid_row_count + duplicate_row_count + conflict_row_count <= row_count
  )
);

create unique index if not exists import_jobs_org_id_key
  on integration.import_jobs (organization_id, id);
create unique index if not exists import_jobs_org_command_key
  on integration.import_jobs (organization_id, job_command_key);
create unique index if not exists import_jobs_org_file_hash_key
  on integration.import_jobs (organization_id, import_type_code, template_version, file_sha256);
create index if not exists import_jobs_org_created_key
  on integration.import_jobs (organization_id, created_at desc, id desc);
create index if not exists import_jobs_org_status_created_key
  on integration.import_jobs (organization_id, status_code, created_at desc, id desc);

create table if not exists integration.import_rows (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  import_job_id uuid not null,
  row_number integer not null,
  raw_row jsonb not null,
  normalized_row jsonb not null default '{}'::jsonb,
  row_fingerprint text not null,
  validation_status_code text not null default 'PENDING',
  validation_errors jsonb not null default '[]'::jsonb,
  processing_status_code text not null default 'PENDING',
  external_event_ref text,
  canonical_idempotency_key text,
  result_entity_type text,
  result_entity_id uuid,
  canonical_line_count integer not null default 0,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint import_rows_job_fk foreign key (organization_id, import_job_id)
    references integration.import_jobs (organization_id, id) on delete restrict,
  constraint import_rows_row_number_check check (row_number between 1 and 100000),
  constraint import_rows_raw_object_check check (jsonb_typeof(raw_row) = 'object'),
  constraint import_rows_normalized_object_check check (jsonb_typeof(normalized_row) = 'object'),
  constraint import_rows_fingerprint_check check (row_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint import_rows_validation_check check (validation_status_code in ('PENDING', 'VALID', 'INVALID', 'DUPLICATE', 'CONFLICT')),
  constraint import_rows_errors_check check (jsonb_typeof(validation_errors) = 'array'),
  constraint import_rows_processing_check check (processing_status_code in ('PENDING', 'PROCESSED', 'SKIPPED', 'FAILED')),
  constraint import_rows_line_count_check check (canonical_line_count between 0 and 200)
);

create unique index if not exists import_rows_job_row_number_key
  on integration.import_rows (import_job_id, row_number);
create unique index if not exists import_rows_job_fingerprint_key
  on integration.import_rows (import_job_id, row_fingerprint);
create index if not exists import_rows_org_job_order_key
  on integration.import_rows (organization_id, import_job_id, row_number, id);
create index if not exists import_rows_org_job_validation_key
  on integration.import_rows (organization_id, import_job_id, validation_status_code, row_number, id);

comment on table integration.import_jobs is
  'Private staging jobs for CSV adapter v1. ORDER rows normalize through the existing reservation boundary and produce domain event type RESERVE; shipment, cancellation, and return are not supported here.';
comment on column integration.import_jobs.file_sha256 is
  'File identity only; distinct from the job command key, row fingerprint, external event reference, and canonical domain idempotency key.';
comment on column integration.import_jobs.job_command_key is
  'Import command identity. Same key with a different request hash is a conflict; it is not a file checksum.';
comment on column integration.import_jobs.object_path is
  'Server-generated opaque path: organization UUID/job UUID/random token.csv. Raw filenames are metadata only.';
comment on table integration.import_rows is
  'Read-only validation staging. Raw and normalized evidence are retained for audit; domain result fields remain null until a future explicit commit through the canonical event pipeline.';
comment on column integration.import_rows.canonical_idempotency_key is
  'Future canonical event identity, distinct from the row fingerprint and external event reference.';

create or replace function integration.enforce_import_job_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, integration
as $$
begin
  if tg_op = 'INSERT' then
    if new.status_code <> 'UPLOADED' then
      raise exception using errcode = 'P0001', message = 'IMPORT_INVALID_INITIAL_STATUS';
    end if;
    return new;
  end if;

  if new.status_code = old.status_code then
    return new;
  end if;

  if not (
    (old.status_code = 'UPLOADED' and new.status_code in ('VALIDATING', 'CANCELLED'))
    or (old.status_code = 'VALIDATING' and new.status_code in ('READY', 'VALIDATION_FAILED', 'CANCELLED'))
    or (old.status_code = 'READY' and new.status_code in ('COMMITTING', 'CANCELLED'))
    or (old.status_code = 'COMMITTING' and new.status_code in ('COMPLETED', 'COMMIT_FAILED'))
  ) then
    raise exception using errcode = 'P0001', message = 'IMPORT_INVALID_STATE_TRANSITION';
  end if;

  return new;
end;
$$;

drop trigger if exists import_jobs_state_transition on integration.import_jobs;
create trigger import_jobs_state_transition
before insert or update of status_code on integration.import_jobs
for each row execute function integration.enforce_import_job_transition();

drop trigger if exists import_jobs_touch_updated_at on integration.import_jobs;
create trigger import_jobs_touch_updated_at
before update on integration.import_jobs
for each row execute function app.touch_updated_at();

drop trigger if exists import_rows_touch_updated_at on integration.import_rows;
create trigger import_rows_touch_updated_at
before update on integration.import_rows
for each row execute function app.touch_updated_at();

alter table integration.import_jobs enable row level security;
alter table integration.import_jobs force row level security;
alter table integration.import_rows enable row level security;
alter table integration.import_rows force row level security;

drop policy if exists import_jobs_read_current_organization on integration.import_jobs;
create policy import_jobs_read_current_organization
on integration.import_jobs for select to authenticated
using (organization_id = app.current_organization_id());

drop policy if exists import_rows_read_current_organization on integration.import_rows;
create policy import_rows_read_current_organization
on integration.import_rows for select to authenticated
using (organization_id = app.current_organization_id());

revoke all on integration.import_jobs, integration.import_rows from public, anon;
revoke insert, update, delete, truncate, references, trigger on integration.import_jobs, integration.import_rows from authenticated;
grant select on integration.import_jobs, integration.import_rows to authenticated;
grant all on integration.import_jobs, integration.import_rows to service_role;

create or replace view api.import_job_read_model
with (security_invoker = true, security_barrier = true)
as
select
  id,
  organization_id,
  import_type_code,
  template_version,
  status_code,
  original_file_name,
  detected_mime,
  file_size_bytes,
  row_count,
  valid_row_count,
  invalid_row_count,
  duplicate_row_count,
  conflict_row_count,
  processed_row_count,
  expanded_line_count,
  failure_code,
  failure_detail,
  uploaded_at,
  validated_at,
  committed_at,
  created_at,
  updated_at
from integration.import_jobs;

create or replace view api.import_row_read_model
with (security_invoker = true, security_barrier = true)
as
select
  id,
  organization_id,
  import_job_id,
  row_number,
  normalized_row,
  row_fingerprint,
  validation_status_code,
  validation_errors,
  processing_status_code,
  external_event_ref,
  canonical_idempotency_key,
  result_entity_type,
  result_entity_id,
  canonical_line_count,
  processed_at,
  created_at,
  updated_at
from integration.import_rows;

grant select on api.import_job_read_model, api.import_row_read_model to authenticated, service_role;
revoke all on api.import_job_read_model, api.import_row_read_model from public, anon;

create or replace function api.create_marketplace_csv_import_job(
  p_job_command_key text,
  p_request_hash text,
  p_original_file_name text,
  p_detected_mime text,
  p_file_size_bytes bigint,
  p_file_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, integration, api, extensions
as $$
declare
  v_organization_id uuid := app.current_organization_id();
  v_actor uuid := auth.uid();
  v_existing integration.import_jobs%rowtype;
  v_job_id uuid := gen_random_uuid();
  v_object_path text;
begin
  if v_organization_id is null or v_actor is null or not app.is_admin() then
    raise exception using errcode = '42501', message = 'IMPORT_ADMIN_REQUIRED';
  end if;
  if p_job_command_key is null or length(btrim(p_job_command_key)) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'IMPORT_INVALID_COMMAND_KEY';
  end if;
  if p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'IMPORT_INVALID_REQUEST_HASH';
  end if;
  if p_original_file_name is null or length(btrim(p_original_file_name)) not between 1 and 255 or p_original_file_name ~ '[\\/\\x00]' then
    raise exception using errcode = '22023', message = 'IMPORT_INVALID_FILE_NAME';
  end if;
  if p_detected_mime not in ('text/csv', 'application/csv', 'text/plain') then
    raise exception using errcode = '22023', message = 'IMPORT_INVALID_MIME';
  end if;
  if p_file_size_bytes is null or p_file_size_bytes <= 0 or p_file_size_bytes > 10485760 then
    raise exception using errcode = '22023', message = 'IMPORT_FILE_TOO_LARGE';
  end if;
  if p_file_sha256 is null or p_file_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'IMPORT_INVALID_FILE_HASH';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_organization_id::text || ':CSV_IMPORT_JOB:' || p_job_command_key, 0));

  select * into v_existing
  from integration.import_jobs
  where organization_id = v_organization_id
    and job_command_key = p_job_command_key
  for update;

  if found then
    if v_existing.job_request_hash = p_request_hash then
      return jsonb_build_object('status', 'EXACT_REPLAY', 'jobId', v_existing.id, 'objectPath', v_existing.object_path);
    end if;
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REUSED';
  end if;

  if exists (
    select 1 from integration.import_jobs
    where organization_id = v_organization_id
      and import_type_code = 'ORDER'
      and template_version = 'MARKETPLACE_RESERVATION_V1'
      and file_sha256 = p_file_sha256
  ) then
    return jsonb_build_object('status', 'DUPLICATE_FILE', 'fileSha256', p_file_sha256);
  end if;

  v_object_path := v_organization_id::text || '/' || v_job_id::text || '/' || replace(gen_random_uuid()::text, '-', '') || '.csv';
  insert into integration.import_jobs (
    id, organization_id, uploaded_by, import_type_code, template_version,
    original_file_name, object_path, detected_mime, file_size_bytes,
    file_sha256, job_command_key, job_request_hash
  ) values (
    v_job_id, v_organization_id, v_actor, 'ORDER', 'MARKETPLACE_RESERVATION_V1',
    p_original_file_name, v_object_path, p_detected_mime, p_file_size_bytes,
    p_file_sha256, p_job_command_key, p_request_hash
  );

  return jsonb_build_object('status', 'CREATED', 'jobId', v_job_id, 'objectPath', v_object_path);
end;
$$;

revoke all on function api.create_marketplace_csv_import_job(text, text, text, text, bigint, text) from public, anon;
grant execute on function api.create_marketplace_csv_import_job(text, text, text, text, bigint, text) to authenticated, service_role;

create or replace function api.classify_marketplace_csv_import_request(
  p_job_command_key text,
  p_request_hash text,
  p_file_sha256 text
)
returns text
language plpgsql
security definer
stable
set search_path = pg_catalog, auth, app, integration, api, extensions
as $$
declare
  v_organization_id uuid := app.current_organization_id();
  v_existing integration.import_jobs%rowtype;
begin
  if v_organization_id is null or auth.uid() is null or not app.is_admin() then
    raise exception using errcode = '42501', message = 'IMPORT_ADMIN_REQUIRED';
  end if;

  select * into v_existing
  from integration.import_jobs
  where organization_id = v_organization_id
    and job_command_key = p_job_command_key;

  if found then
    if v_existing.job_request_hash = p_request_hash then
      return 'EXACT_REPLAY';
    end if;
    return 'CONFLICT';
  end if;

  if exists (
    select 1 from integration.import_jobs
    where organization_id = v_organization_id
      and file_sha256 = p_file_sha256
  ) then
    return 'DUPLICATE_FILE';
  end if;
  return 'NEW';
end;
$$;

revoke all on function api.classify_marketplace_csv_import_request(text, text, text) from public, anon;
grant execute on function api.classify_marketplace_csv_import_request(text, text, text) to authenticated, service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('imports', 'imports', false, 10485760, array['text/csv', 'application/csv', 'text/plain']::text[])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- storage.objects is owned by the Supabase Storage service and its RLS is
-- managed by that service. This migration only creates the private bucket;
-- future upload/download APIs must use the server-authorized Storage boundary.

commit;
