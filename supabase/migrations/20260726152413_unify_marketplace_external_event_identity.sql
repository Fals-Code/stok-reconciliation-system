begin;

-- One marketplace external event is a domain identity, not an adapter identity.
-- The semantic hash intentionally excludes CSV job/file/row and raw adapter payload.
create or replace function operations.marketplace_reservation_external_event_hash(
  p_organization_id uuid,
  p_channel_code text,
  p_event_ref text,
  p_order_ref text,
  p_source_status text,
  p_occurred_at timestamptz,
  p_received_at timestamptz,
  p_lines jsonb,
  p_note text,
  p_schema_version integer
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, operations, extensions
as $$
declare
  v_lines jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;
  if btrim(coalesce(p_channel_code, '')) = '' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_CHANNEL_REQUIRED';
  end if;
  if btrim(coalesce(p_event_ref, '')) = '' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_EVENT_REF_REQUIRED';
  end if;
  if btrim(coalesce(p_order_ref, '')) = '' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_ORDER_REF_REQUIRED';
  end if;
  if btrim(coalesce(p_source_status, '')) = '' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_SOURCE_STATUS_REQUIRED';
  end if;
  if p_occurred_at is null then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_OCCURRED_AT_REQUIRED';
  end if;
  if p_received_at is null then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_RECEIVED_AT_REQUIRED';
  end if;
  if p_received_at < p_occurred_at then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_RECEIVED_BEFORE_OCCURRED';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) = 0
     or jsonb_array_length(p_lines) > 100 then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_SOURCE_LINES_REQUIRED';
  end if;
  if p_schema_version is null or p_schema_version <= 0 then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_SCHEMA_VERSION_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_lines) item(value)
    where jsonb_typeof(item.value) is distinct from 'object'
       or jsonb_typeof(item.value -> 'sourceLineRef') is distinct from 'string'
       or btrim(item.value ->> 'sourceLineRef') = ''
       or length(btrim(item.value ->> 'sourceLineRef')) > 90
       or jsonb_typeof(item.value -> 'externalListingCode') is distinct from 'string'
       or btrim(item.value ->> 'externalListingCode') = ''
       or length(btrim(item.value ->> 'externalListingCode')) > 200
       or jsonb_typeof(item.value -> 'listingQuantity') is distinct from 'number'
       or (item.value ->> 'listingQuantity') !~ '^[1-9][0-9]{0,8}$'
       or (item.value ? 'sourceTitle' and (jsonb_typeof(item.value -> 'sourceTitle') is distinct from 'string' or btrim(item.value ->> 'sourceTitle') = '' or length(btrim(item.value ->> 'sourceTitle')) > 300))
       or (item.value ? 'sourceSku' and (jsonb_typeof(item.value -> 'sourceSku') is distinct from 'string' or btrim(item.value ->> 'sourceSku') = '' or length(btrim(item.value ->> 'sourceSku')) > 200))
       or (item.value ? 'sourceStatus' and (jsonb_typeof(item.value -> 'sourceStatus') is distinct from 'string' or btrim(item.value ->> 'sourceStatus') = '' or length(btrim(item.value ->> 'sourceStatus')) > 100))
  ) then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_SOURCE_LINE_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_lines) item(value)
    group by btrim(item.value ->> 'sourceLineRef') having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_DUPLICATE_SOURCE_LINE';
  end if;

  select jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'sourceLineRef', btrim(item.value ->> 'sourceLineRef'),
      'externalListingCode', btrim(item.value ->> 'externalListingCode'),
      'listingQuantity', (item.value ->> 'listingQuantity')::bigint,
      'sourceTitle', nullif(btrim(coalesce(item.value ->> 'sourceTitle', '')), ''),
      'sourceSku', nullif(btrim(coalesce(item.value ->> 'sourceSku', '')), ''),
      'sourceStatus', upper(btrim(coalesce(item.value ->> 'sourceStatus', p_source_status)))
    )) order by btrim(item.value ->> 'sourceLineRef')
  ) into v_lines
  from jsonb_array_elements(p_lines) item(value);

  return encode(extensions.digest(convert_to(jsonb_build_object(
    'organizationId', p_organization_id,
    'channelCode', upper(btrim(p_channel_code)),
    'eventRef', btrim(p_event_ref),
    'orderRef', btrim(p_order_ref),
    'sourceStatus', upper(btrim(p_source_status)),
    'occurredAt', p_occurred_at,
    'receivedAt', p_received_at,
    'lines', v_lines,
    'note', nullif(btrim(coalesce(p_note, '')), ''),
    'schemaVersion', p_schema_version
  )::text, 'UTF8'), 'sha256'), 'hex');
end;
$$;

comment on function operations.marketplace_reservation_external_event_hash(uuid, text, text, text, text, timestamptz, timestamptz, jsonb, text, integer) is
  'Canonical RESERVE external-event request hash. It includes normalized domain fields only; adapter job, file, row, raw payload, and adapter metadata are excluded.';

revoke all on function operations.marketplace_reservation_external_event_hash(uuid, text, text, text, text, timestamptz, timestamptz, jsonb, text, integer) from public, anon, authenticated;

alter function api.reserve_marketplace_listing_event(
  uuid, text, text, text, text, text, timestamptz, timestamptz, jsonb, text, jsonb, jsonb, integer
) rename to reserve_marketplace_listing_event_apply;

revoke all on function api.reserve_marketplace_listing_event_apply(
  uuid, text, text, text, text, text, timestamptz, timestamptz, jsonb, text, jsonb, jsonb, integer
) from public, anon, authenticated, service_role;

create or replace function api.reserve_marketplace_listing_event(
  p_organization_id uuid,
  p_idempotency_key text,
  p_channel_code text,
  p_event_ref text,
  p_order_ref text,
  p_source_status text,
  p_occurred_at timestamptz,
  p_received_at timestamptz,
  p_lines jsonb,
  p_note text default null,
  p_raw_payload jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb,
  p_schema_version integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, api, extensions
as $$
declare
  v_scope constant text := 'MARKETPLACE_RESERVATION_EXTERNAL_EVENT';
  v_idempotency_key text := btrim(coalesce(p_idempotency_key, ''));
  v_channel_code text := upper(btrim(coalesce(p_channel_code, '')));
  v_event_ref text := btrim(coalesce(p_event_ref, ''));
  v_hash text;
  v_legacy_request_hash text;
  v_key text;
  v_existing inventory.idempotency_commands%rowtype;
  v_legacy_existing inventory.idempotency_commands%rowtype;
  v_command_id uuid := gen_random_uuid();
  v_actor_user_id uuid := auth.uid();
  v_jwt_role text := coalesce(auth.jwt() ->> 'role', current_setting('request.jwt.claim.role', true));
  v_result jsonb;
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;
  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if length(v_idempotency_key) > 200 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_TOO_LONG';
  end if;
  if jsonb_typeof(coalesce(p_raw_payload, '{}'::jsonb)) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_RAW_PAYLOAD_MUST_BE_OBJECT';
  end if;
  if jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_METADATA_MUST_BE_OBJECT';
  end if;
  if p_note is not null and length(btrim(p_note)) > 2000 then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_NOTE_TOO_LONG';
  end if;
  if v_jwt_role = 'anon' or (v_jwt_role = 'authenticated' and v_actor_user_id is null) then
    raise exception using errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  end if;
  if v_actor_user_id is null and coalesce(v_jwt_role, '') <> 'service_role' and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'TRUSTED_CALLER_REQUIRED';
  end if;
  if v_actor_user_id is not null and (not app.is_admin() or app.current_organization_id() is distinct from p_organization_id) then
    raise exception using errcode = '42501', message = 'ORGANIZATION_ACCESS_DENIED';
  end if;
  if not exists (select 1 from app.organizations organization where organization.id = p_organization_id and organization.is_active) then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_NOT_FOUND';
  end if;
  if not exists (select 1 from catalog.channels channel where channel.code = v_channel_code and channel.is_marketplace and channel.is_active) then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_CHANNEL_NOT_ALLOWED';
  end if;

  v_hash := operations.marketplace_reservation_external_event_hash(
    p_organization_id, v_channel_code, v_event_ref, p_order_ref, p_source_status,
    p_occurred_at, p_received_at, p_lines, p_note, p_schema_version
  );
  v_legacy_request_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'organizationId', p_organization_id,
    'channelCode', v_channel_code,
    'eventRef', v_event_ref,
    'orderRef', btrim(coalesce(p_order_ref, '')),
    'sourceStatus', upper(btrim(coalesce(p_source_status, ''))),
    'occurredAt', p_occurred_at,
    'receivedAt', p_received_at,
    'lines', p_lines,
    'note', nullif(btrim(coalesce(p_note, '')), ''),
    'rawPayload', coalesce(p_raw_payload, '{}'::jsonb),
    'metadata', coalesce(p_metadata, '{}'::jsonb),
    'schemaVersion', p_schema_version
  )::text, 'UTF8'), 'sha256'), 'hex');
  v_key := v_channel_code || ':' || v_event_ref;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':MARKETPLACE_EVENT:' || v_key,
    0::bigint
  ));
  select command.* into v_legacy_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id
    and command.scope = 'RESERVE_MARKETPLACE_LISTING_EVENT'
    and command.key = v_idempotency_key
  for update;
  -- CSV uses a deterministic internal bridge key. Its adapter raw payload is
  -- intentionally excluded from the shared identity, so only the external
  -- canonical hash may decide replay/conflict for that bridge invocation.
  if found
     and v_idempotency_key not like 'marketplace-reserve-v1:%'
     and v_legacy_existing.request_hash <> v_legacy_request_hash then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_KEY_REUSED';
  end if;
  select command.* into v_existing
  from inventory.idempotency_commands command
  where command.organization_id = p_organization_id and command.scope = v_scope and command.key = v_key
  for update;

  if found then
    if v_existing.request_hash <> v_hash then
      raise exception using errcode = 'P0001', message = 'MARKETPLACE_EXTERNAL_EVENT_CONFLICT';
    end if;
    if v_existing.status_code = 'SUCCEEDED' then
      return v_existing.response_snapshot || jsonb_build_object('externalEventOutcome', 'REPLAYED');
    end if;
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_EXTERNAL_EVENT_IN_PROGRESS';
  end if;

  insert into inventory.idempotency_commands (
    id, organization_id, scope, key, request_hash, status_code, started_at, response_snapshot
  ) values (
    v_command_id, p_organization_id, v_scope, v_key, v_hash, 'STARTED', clock_timestamp(), '{}'::jsonb
  );

  v_result := api.reserve_marketplace_listing_event_apply(
    p_organization_id, v_idempotency_key, v_channel_code, v_event_ref, p_order_ref,
    p_source_status, p_occurred_at, p_received_at, p_lines, p_note, p_raw_payload,
    p_metadata, p_schema_version
  );

  update inventory.idempotency_commands command
  set status_code = 'SUCCEEDED', completed_at = clock_timestamp(), response_snapshot = v_result,
      error_code = null, result_transaction_id = null
  where command.id = v_command_id;

  return v_result || jsonb_build_object('externalEventOutcome', 'CREATED');
end;
$$;

comment on function api.reserve_marketplace_listing_event(uuid, text, text, text, text, text, timestamptz, timestamptz, jsonb, text, jsonb, jsonb, integer) is
  'Canonical RESERVE boundary. A shared organization/channel/external-event identity returns CREATED, REPLAYED, or deterministic conflict across every adapter.';

revoke all on function api.reserve_marketplace_listing_event(
  uuid, text, text, text, text, text, timestamptz, timestamptz, jsonb, text, jsonb, jsonb, integer
) from public, anon;
grant execute on function api.reserve_marketplace_listing_event(
  uuid, text, text, text, text, text, timestamptz, timestamptz, jsonb, text, jsonb, jsonb, integer
) to authenticated, service_role;

-- CSV owns only job lifecycle and audit linkage. The domain event is always
-- claimed by api.reserve_marketplace_listing_event under the shared event lock.
create or replace function api.commit_marketplace_csv_import_job(
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
declare
  v_job integration.import_jobs%rowtype;
  v_command integration.import_commit_commands%rowtype;
  v_basis_hash text;
  v_commit_id uuid := gen_random_uuid();
  v_actor uuid := auth.uid();
  v_process text;
  v_group record;
  v_existing_identity integration.marketplace_csv_event_identities%rowtype;
  v_identity_id uuid;
  v_result jsonb;
  v_lines jsonb;
  v_raw_rows jsonb;
  v_event_request_hash text;
  v_canonical_key text;
  v_status text;
  v_group_result_id uuid;
  v_failed_code text;
  v_failed_detail text;
  v_sqlstate text;
  v_response jsonb;
  v_event_results jsonb := '[]'::jsonb;
  v_processed_rows integer := 0;
  v_event_count integer := 0;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception using errcode = '42501', message = 'CSV_IMPORT_COMMIT_SERVICE_REQUIRED';
  end if;
  if p_organization_id is null or p_import_job_id is null then
    raise exception using errcode = '22023', message = 'CSV_IMPORT_COMMIT_JOB_REQUIRED';
  end if;
  if p_commit_idempotency_key is null or length(btrim(p_commit_idempotency_key)) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'CSV_IMPORT_COMMIT_KEY_INVALID';
  end if;
  if p_confirmation is distinct from true then
    raise exception using errcode = '22023', message = 'CSV_IMPORT_COMMIT_CONFIRMATION_REQUIRED';
  end if;

  -- Lock order is job -> shared canonical external event -> existing domain locks -> CSV audit rows.
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':CSV_IMPORT_JOB:' || p_import_job_id::text, 0::bigint));
  select * into v_job from integration.import_jobs
  where organization_id = p_organization_id and id = p_import_job_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'CSV_IMPORT_JOB_NOT_FOUND';
  end if;

  select encode(extensions.digest(convert_to(jsonb_build_object(
    'jobId', v_job.id,
    'organizationId', v_job.organization_id,
    'templateVersion', v_job.template_version,
    'fileSha256', v_job.file_sha256,
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'rowNumber', row.row_number, 'rawRow', row.raw_row, 'rowFingerprint', row.row_fingerprint,
      'normalizedRow', row.normalized_row, 'validationStatus', row.validation_status_code,
      'eventGroupKey', row.event_group_key, 'expansionPreview', row.expansion_preview
    ) order by row.row_number, row.id) from integration.import_rows row
      where row.organization_id = v_job.organization_id and row.import_job_id = v_job.id), '[]'::jsonb)
  )::text, 'UTF8'), 'sha256'), 'hex') into v_basis_hash;

  select * into v_command from integration.import_commit_commands
  where organization_id = v_job.organization_id and import_job_id = v_job.id
    and commit_idempotency_key = btrim(p_commit_idempotency_key) for update;
  if found then
    if v_command.request_hash <> v_basis_hash then
      raise exception using errcode = 'P0001', message = 'CSV_IMPORT_COMMIT_KEY_REUSED';
    end if;
    if v_command.status_code = 'SUCCEEDED' then
      return v_command.response_snapshot || jsonb_build_object('status', 'EXACT_REPLAY');
    end if;
    if v_command.status_code = 'STARTED' then
      raise exception using errcode = 'P0001', message = 'CSV_IMPORT_COMMIT_IN_PROGRESS';
    end if;
    raise exception using errcode = 'P0001', message = 'CSV_IMPORT_COMMIT_FAILED_REPLAY';
  end if;

  if v_job.status_code = 'COMPLETED' then
    raise exception using errcode = 'P0001', message = 'CSV_IMPORT_ALREADY_COMPLETED';
  end if;
  if v_job.status_code = 'COMMITTING' then
    raise exception using errcode = 'P0001', message = 'CSV_IMPORT_COMMIT_IN_PROGRESS';
  end if;
  if v_job.status_code not in ('READY', 'COMMIT_FAILED') then
    raise exception using errcode = 'P0001', message = 'CSV_IMPORT_COMMIT_STATE_INVALID';
  end if;
  if exists (select 1 from integration.import_rows row where row.organization_id = v_job.organization_id and row.import_job_id = v_job.id and (row.validation_status_code <> 'VALID' or row.processing_status_code <> 'PENDING')) then
    raise exception using errcode = 'P0001', message = 'CSV_IMPORT_BLOCKING_ROWS';
  end if;
  if not exists (select 1 from integration.import_rows row where row.organization_id = v_job.organization_id and row.import_job_id = v_job.id) then
    raise exception using errcode = 'P0001', message = 'CSV_IMPORT_NO_ROWS';
  end if;

  if v_actor is null then v_process := 'api.commit_marketplace_csv_import_job'; end if;
  insert into integration.import_commit_commands (
    id, organization_id, import_job_id, commit_idempotency_key, request_hash,
    status_code, actor_user_id, process_name, response_snapshot
  ) values (
    v_commit_id, v_job.organization_id, v_job.id, btrim(p_commit_idempotency_key),
    v_basis_hash, 'STARTED', v_actor, v_process, '{}'::jsonb
  );
  update integration.import_jobs set status_code = 'COMMITTING', failure_code = null, failure_detail = null where id = v_job.id;

  begin
    for v_group in
      select row.event_group_key,
        min(row.normalized_row ->> 'channel_code') as channel_code,
        min(row.normalized_row ->> 'external_event_ref') as external_event_ref,
        min(row.normalized_row ->> 'external_order_ref') as external_order_ref,
        min(row.normalized_row ->> 'source_status') as source_status,
        min((row.normalized_row ->> 'occurred_at')::timestamptz) as occurred_at,
        min((row.normalized_row ->> 'received_at')::timestamptz) as received_at,
        min(nullif(btrim(row.normalized_row ->> 'note'), '')) as note,
        count(*)::integer as row_count
      from integration.import_rows row
      where row.organization_id = v_job.organization_id and row.import_job_id = v_job.id
      group by row.event_group_key order by row.event_group_key
    loop
      if v_group.event_group_key is null or v_group.row_count <= 0 then
        raise exception using errcode = 'P0001', message = 'CSV_IMPORT_EVENT_GROUP_INVALID';
      end if;
      if (select count(distinct row.normalized_row ->> 'channel_code') from integration.import_rows row where row.import_job_id = v_job.id and row.event_group_key = v_group.event_group_key) <> 1
         or (select count(distinct row.normalized_row ->> 'external_order_ref') from integration.import_rows row where row.import_job_id = v_job.id and row.event_group_key = v_group.event_group_key) <> 1
         or (select count(distinct row.normalized_row ->> 'source_status') from integration.import_rows row where row.import_job_id = v_job.id and row.event_group_key = v_group.event_group_key) <> 1
         or (select count(distinct row.normalized_row ->> 'occurred_at') from integration.import_rows row where row.import_job_id = v_job.id and row.event_group_key = v_group.event_group_key) <> 1
         or (select count(distinct row.normalized_row ->> 'received_at') from integration.import_rows row where row.import_job_id = v_job.id and row.event_group_key = v_group.event_group_key) <> 1 then
        raise exception using errcode = 'P0001', message = 'CSV_IMPORT_EVENT_GROUP_CONFLICT';
      end if;

      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'sourceLineRef', row.normalized_row ->> 'source_line_ref',
        'externalListingCode', row.normalized_row ->> 'external_listing_code',
        'listingQuantity', (row.normalized_row ->> 'listing_quantity')::bigint,
        'sourceTitle', nullif(row.normalized_row ->> 'source_title', ''),
        'sourceSku', nullif(row.normalized_row ->> 'source_sku', ''),
        'sourceStatus', row.normalized_row ->> 'source_status',
        'rawLinePayload', row.raw_row
      )) order by row.row_number, row.id), jsonb_agg(row.raw_row order by row.row_number, row.id)
      into v_lines, v_raw_rows
      from integration.import_rows row
      where row.organization_id = v_job.organization_id and row.import_job_id = v_job.id and row.event_group_key = v_group.event_group_key;

      v_event_request_hash := operations.marketplace_reservation_external_event_hash(
        v_job.organization_id, upper(btrim(v_group.channel_code)), btrim(v_group.external_event_ref),
        btrim(v_group.external_order_ref), upper(btrim(v_group.source_status)), v_group.occurred_at,
        v_group.received_at, v_lines, v_group.note, 1
      );
      v_canonical_key := 'marketplace-reserve-v1:' || encode(extensions.digest(convert_to(
        v_job.organization_id::text || ':' || upper(btrim(v_group.channel_code)) || ':' || btrim(v_group.external_event_ref), 'UTF8'
      ), 'sha256'), 'hex');

      v_result := api.reserve_marketplace_listing_event(
        v_job.organization_id, v_canonical_key, upper(btrim(v_group.channel_code)), btrim(v_group.external_event_ref),
        btrim(v_group.external_order_ref), upper(btrim(v_group.source_status)), v_group.occurred_at, v_group.received_at,
        v_lines, v_group.note,
        jsonb_build_object('adapter', 'CSV', 'templateVersion', v_job.template_version, 'eventGroupKey', v_group.event_group_key, 'rows', v_raw_rows),
        jsonb_build_object('adapterContract', 'MARKETPLACE_LISTING_EVENT_V1', 'csvTemplateVersion', v_job.template_version,
          'externalEventIdentity', upper(btrim(v_group.channel_code)) || ':' || btrim(v_group.external_event_ref), 'eventRequestHash', v_event_request_hash),
        1
      );

      -- This is adapter audit linkage only. It is reached after the canonical event lock.
      v_existing_identity := null;
      select * into v_existing_identity from integration.marketplace_csv_event_identities identity
      where identity.organization_id = v_job.organization_id
        and identity.channel_code = upper(btrim(v_group.channel_code))
        and identity.external_event_ref = btrim(v_group.external_event_ref)
      for update;
      if found then
        if v_existing_identity.event_request_hash <> v_event_request_hash then
          raise exception using errcode = 'P0001', message = 'MARKETPLACE_EXTERNAL_EVENT_CONFLICT';
        end if;
        v_identity_id := v_existing_identity.id;
      else
        insert into integration.marketplace_csv_event_identities (
          organization_id, channel_code, external_event_ref, event_request_hash,
          canonical_idempotency_key, canonical_event_id, marketplace_order_id,
          normalization_event_id, first_import_job_id, response_snapshot
        ) values (
          v_job.organization_id, upper(btrim(v_group.channel_code)), btrim(v_group.external_event_ref), v_event_request_hash,
          v_canonical_key, (v_result ->> 'eventId')::uuid, (v_result ->> 'orderId')::uuid,
          (v_result ->> 'normalizationEventId')::uuid, v_job.id, v_result
        ) returning id into v_identity_id;
      end if;
      v_status := case when v_result ->> 'externalEventOutcome' = 'REPLAYED' then 'REPLAYED' else 'COMPLETED' end;

      insert into integration.import_event_results (
        organization_id, import_job_id, import_commit_command_id, event_identity_id,
        event_group_key, status_code, external_event_ref, canonical_idempotency_key,
        canonical_event_id, marketplace_order_id, normalization_event_id, response_snapshot
      ) values (
        v_job.organization_id, v_job.id, v_commit_id, v_identity_id, v_group.event_group_key,
        v_status, btrim(v_group.external_event_ref), v_canonical_key,
        (v_result ->> 'eventId')::uuid, (v_result ->> 'orderId')::uuid,
        (v_result ->> 'normalizationEventId')::uuid, v_result
      ) returning id into v_group_result_id;

      update integration.import_rows row set processing_status_code = 'PROCESSED', canonical_idempotency_key = v_canonical_key,
        result_entity_type = 'MARKETPLACE_EVENT', result_entity_id = (v_result ->> 'eventId')::uuid,
        canonical_event_id = (v_result ->> 'eventId')::uuid, marketplace_order_id = (v_result ->> 'orderId')::uuid,
        normalization_event_id = (v_result ->> 'normalizationEventId')::uuid, commit_result_id = v_group_result_id,
        processed_at = clock_timestamp()
      where row.organization_id = v_job.organization_id and row.import_job_id = v_job.id and row.event_group_key = v_group.event_group_key;

      v_processed_rows := v_processed_rows + v_group.row_count;
      v_event_count := v_event_count + 1;
      v_event_results := v_event_results || jsonb_build_array(jsonb_build_object(
        'eventGroupKey', v_group.event_group_key, 'status', v_status, 'eventId', v_result ->> 'eventId',
        'orderId', v_result ->> 'orderId', 'normalizationEventId', v_result ->> 'normalizationEventId'
      ));
    end loop;
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_failed_detail = message_text;
    v_failed_code := case when coalesce(v_failed_detail, '') ~ '^(CSV_|MARKETPLACE_|IDEMPOTENCY_)' then v_failed_detail else 'CSV_IMPORT_COMMIT_FAILED' end;
    v_failed_detail := case when v_failed_code = v_failed_detail then left(v_failed_detail, 200) else 'Canonical reservation batch gagal; seluruh domain effect dibatalkan.' end;
  end;

  if v_failed_code is not null then
    update integration.import_commit_commands set status_code = 'FAILED', completed_at = clock_timestamp(), error_code = v_failed_code,
      response_snapshot = jsonb_build_object('status', 'COMMIT_FAILED', 'jobId', v_job.id, 'errorCode', v_failed_code, 'detail', v_failed_detail)
    where id = v_commit_id;
    update integration.import_jobs set status_code = 'COMMIT_FAILED', failure_code = v_failed_code, failure_detail = v_failed_detail,
      processed_row_count = 0 where id = v_job.id;
    return jsonb_build_object('status', 'COMMIT_FAILED', 'jobId', v_job.id, 'errorCode', v_failed_code, 'detail', v_failed_detail);
  end if;

  v_response := jsonb_build_object('status', 'COMPLETED', 'jobId', v_job.id, 'commitCommandId', v_commit_id,
    'requestHash', v_basis_hash, 'processedRowCount', v_processed_rows, 'eventCount', v_event_count, 'events', v_event_results);
  update integration.import_commit_commands set status_code = 'SUCCEEDED', completed_at = clock_timestamp(), response_snapshot = v_response where id = v_commit_id;
  update integration.import_jobs set status_code = 'COMPLETED', committed_at = clock_timestamp(), processed_row_count = v_processed_rows,
    failure_code = null, failure_detail = null where id = v_job.id;
  return v_response;
end;
$$;

comment on function api.commit_marketplace_csv_import_job(uuid, uuid, text, boolean) is
  'Trusted atomic CSV v1 ORDER/RESERVE commit. CSV job audit is linked only after api.reserve_marketplace_listing_event has claimed the shared canonical external-event identity.';

revoke all on function api.commit_marketplace_csv_import_job(uuid, uuid, text, boolean) from public, anon, authenticated;
grant execute on function api.commit_marketplace_csv_import_job(uuid, uuid, text, boolean) to service_role;

commit;
