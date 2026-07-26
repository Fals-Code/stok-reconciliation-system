begin;

alter table integration.import_rows
  add column if not exists event_group_key text,
  add column if not exists expansion_preview jsonb;

create index if not exists import_rows_org_job_event_key
  on integration.import_rows (organization_id, import_job_id, event_group_key, row_number, id);

drop index if exists integration.import_rows_job_fingerprint_key;
create unique index import_rows_job_fingerprint_key
  on integration.import_rows (import_job_id, row_fingerprint)
  where validation_status_code <> 'DUPLICATE';

comment on column integration.import_rows.event_group_key is
  'Deterministic CSV grouping identity: channel_code plus external_event_ref. It is not a domain event idempotency key.';
comment on column integration.import_rows.expansion_preview is
  'Read-only canonical listing/bundle expansion snapshot. It has stockEffect NONE and is never a posting result.';

drop view if exists api.import_row_preview_read_model;
create view api.import_row_preview_read_model
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
  event_group_key,
  expansion_preview,
  processed_at,
  created_at,
  updated_at
from integration.import_rows;

grant select on api.import_row_preview_read_model to authenticated, service_role;
revoke all on api.import_row_preview_read_model from public, anon;

create or replace function api.validate_marketplace_csv_import_job(
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
declare
  v_job integration.import_jobs%rowtype;
  v_row jsonb;
  v_raw_row jsonb;
  v_normalized_row jsonb;
  v_row_number integer;
  v_row_fingerprint text;
  v_event_group_key text;
  v_external_event_ref text;
  v_canonical_idempotency_key text;
  v_errors jsonb;
  v_preview jsonb;
  v_canonical_line_count integer;
  v_valid_count integer := 0;
  v_invalid_count integer := 0;
  v_expanded_count integer := 0;
  v_seen_fingerprints text[] := array[]::text[];
  v_message text;
  v_sqlstate text;
  v_has_blocking boolean := false;
  v_is_duplicate boolean;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'CSV_IMPORT_VALIDATION_SERVICE_REQUIRED';
  end if;
  if p_organization_id is null or p_job_id is null then
    raise exception using errcode = '22023', message = 'CSV_IMPORT_JOB_REQUIRED';
  end if;
  if p_file_sha256 is null or p_file_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'CSV_IMPORT_FILE_HASH_INVALID';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'CSV_IMPORT_ROWS_INVALID';
  end if;
  if jsonb_typeof(coalesce(p_parse_errors, '[]'::jsonb)) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'CSV_IMPORT_PARSE_ERRORS_INVALID';
  end if;

  select * into v_job
  from integration.import_jobs
  where id = p_job_id
    and organization_id = p_organization_id
    and file_sha256 = p_file_sha256
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'CSV_IMPORT_JOB_NOT_FOUND';
  end if;

  if v_job.status_code in ('READY', 'VALIDATION_FAILED') then
    return jsonb_build_object(
      'status', v_job.status_code,
      'jobId', v_job.id,
      'rowCount', v_job.row_count,
      'validRowCount', v_job.valid_row_count,
      'invalidRowCount', v_job.invalid_row_count,
      'expandedLineCount', v_job.expanded_line_count
    );
  end if;

  if v_job.status_code <> 'UPLOADED' then
    raise exception using errcode = 'P0001', message = 'CSV_IMPORT_VALIDATION_STATE_INVALID';
  end if;

  update integration.import_jobs
  set status_code = 'VALIDATING',
      failure_code = null,
      failure_detail = null,
      row_count = jsonb_array_length(p_rows),
      valid_row_count = 0,
      invalid_row_count = 0,
      duplicate_row_count = 0,
      conflict_row_count = 0,
      processed_row_count = 0,
      expanded_line_count = 0,
      validated_at = null
  where id = v_job.id;

  delete from integration.import_rows where import_job_id = v_job.id;

  if jsonb_array_length(p_parse_errors) > 0 then
    update integration.import_jobs
    set status_code = 'VALIDATION_FAILED',
        invalid_row_count = jsonb_array_length(p_rows),
        failure_code = 'CSV_PARSE_FAILED',
        failure_detail = left(coalesce(p_parse_errors -> 0 ->> 'message', 'CSV parsing failed'), 500),
        validated_at = clock_timestamp()
    where id = v_job.id;
    return jsonb_build_object(
      'status', 'VALIDATION_FAILED',
      'jobId', v_job.id,
      'rowCount', jsonb_array_length(p_rows),
      'validRowCount', 0,
      'invalidRowCount', jsonb_array_length(p_rows),
      'expandedLineCount', 0
    );
  end if;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_raw_row := v_row -> 'rawRow';
    v_normalized_row := v_row -> 'normalizedRow';
    v_row_number := (v_row ->> 'rowNumber')::integer;
    v_row_fingerprint := v_row ->> 'rowFingerprint';
    v_event_group_key := nullif(v_row ->> 'eventGroupKey', '');
    v_external_event_ref := nullif(v_row ->> 'externalEventRef', '');
    v_canonical_idempotency_key := nullif(v_row ->> 'canonicalIdempotencyKey', '');
    v_errors := coalesce(v_row -> 'errors', '[]'::jsonb);
    v_preview := null;
    v_canonical_line_count := 0;
    v_is_duplicate := false;

    if jsonb_typeof(v_errors) is distinct from 'array' then
      v_errors := '[]'::jsonb;
    end if;

    if jsonb_typeof(v_raw_row) is distinct from 'object'
       or jsonb_typeof(v_normalized_row) is distinct from 'object'
       or v_row_number is null
       or v_row_number < 2
       or v_row_number > 100001
       or v_row_fingerprint is null
       or v_row_fingerprint !~ '^[0-9a-f]{64}$'
       or jsonb_typeof(v_errors) is distinct from 'array' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', null,
        'code', 'STAGING_ROW_SHAPE_INVALID',
        'message', 'Bentuk row hasil parser tidak valid.',
        'remediation', 'Gunakan parser CSV resmi.',
        'severity', 'BLOCKING'
      ));
      if jsonb_typeof(v_raw_row) is distinct from 'object' then
        v_raw_row := '{}'::jsonb;
      end if;
      if jsonb_typeof(v_normalized_row) is distinct from 'object' then
        v_normalized_row := '{}'::jsonb;
      end if;
    end if;

    if v_row_fingerprint = any(v_seen_fingerprints) then
      v_is_duplicate := true;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', null,
        'code', 'DUPLICATE_ROW',
        'message', 'Row fingerprint duplikat dalam import.',
        'remediation', 'Hapus row duplikat atau gunakan import baru yang benar.',
        'severity', 'BLOCKING'
      ));
    else
      v_seen_fingerprints := array_append(v_seen_fingerprints, v_row_fingerprint);
    end if;

    if jsonb_array_length(v_errors) = 0 then
      begin
        v_preview := operations.resolve_marketplace_listing_expansion(
          p_organization_id,
          upper(btrim(v_normalized_row ->> 'channel_code')),
          btrim(v_normalized_row ->> 'external_listing_code'),
          (v_normalized_row ->> 'listing_quantity')::bigint,
          (v_normalized_row ->> 'occurred_at')::timestamptz
        );
        v_canonical_line_count := jsonb_array_length(coalesce(v_preview -> 'components', '[]'::jsonb));
        if v_canonical_line_count > 200 then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'external_listing_code',
            'code', 'EXPANDED_LINE_LIMIT_EXCEEDED',
            'message', 'Canonical expansion melebihi batas.',
            'remediation', 'Gunakan listing dengan expansion lebih kecil.',
            'severity', 'BLOCKING'
          ));
          v_preview := null;
          v_canonical_line_count := 0;
        end if;
      exception when others then
        get stacked diagnostics v_sqlstate = returned_sqlstate, v_message = message_text;
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'external_listing_code',
          'code', case when coalesce(v_message, '') like 'MARKETPLACE_%' then v_message else 'CANONICAL_MAPPING_ERROR' end,
          'message', case when coalesce(v_message, '') like 'MARKETPLACE_%' then v_message else 'Canonical mapping tidak dapat di-resolve.' end,
          'remediation', 'Periksa listing, channel, dan versi mapping pada occurred_at.',
          'severity', 'BLOCKING'
        ));
        v_preview := null;
        v_canonical_line_count := 0;
      end;
    end if;

    if jsonb_array_length(v_errors) = 0 then
      v_valid_count := v_valid_count + 1;
      v_expanded_count := v_expanded_count + v_canonical_line_count;
    else
      v_invalid_count := v_invalid_count + 1;
      v_has_blocking := true;
    end if;

    insert into integration.import_rows (
      organization_id, import_job_id, row_number, raw_row, normalized_row,
      row_fingerprint, validation_status_code, validation_errors,
      processing_status_code, external_event_ref, canonical_idempotency_key,
      canonical_line_count, event_group_key, expansion_preview
    ) values (
      p_organization_id, v_job.id, v_row_number, v_raw_row, v_normalized_row,
      v_row_fingerprint,
      case when v_is_duplicate then 'DUPLICATE' when jsonb_array_length(v_errors) = 0 then 'VALID' else 'INVALID' end,
      v_errors,
      case when jsonb_array_length(v_errors) = 0 then 'PENDING' else 'SKIPPED' end,
      v_external_event_ref, v_canonical_idempotency_key,
      v_canonical_line_count, v_event_group_key, v_preview
    );
  end loop;

  update integration.import_jobs
  set status_code = case when v_has_blocking then 'VALIDATION_FAILED' else 'READY' end,
      row_count = jsonb_array_length(p_rows),
      valid_row_count = v_valid_count,
      invalid_row_count = v_invalid_count,
      expanded_line_count = v_expanded_count,
      failure_code = case when v_has_blocking then 'CSV_ROW_VALIDATION_FAILED' else null end,
      failure_detail = case when v_has_blocking then 'Satu atau beberapa row membutuhkan perbaikan.' else null end,
      validated_at = clock_timestamp()
  where id = v_job.id;

  return jsonb_build_object(
    'status', case when v_has_blocking then 'VALIDATION_FAILED' else 'READY' end,
    'jobId', v_job.id,
    'rowCount', jsonb_array_length(p_rows),
    'validRowCount', v_valid_count,
    'invalidRowCount', v_invalid_count,
    'expandedLineCount', v_expanded_count
  );
end;
$$;

revoke all on function api.validate_marketplace_csv_import_job(uuid, uuid, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function api.validate_marketplace_csv_import_job(uuid, uuid, text, jsonb, jsonb) to service_role;

commit;
