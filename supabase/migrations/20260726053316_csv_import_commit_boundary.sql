begin;

create table integration.import_commit_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  import_job_id uuid not null,
  commit_idempotency_key text not null,
  request_hash text not null,
  status_code text not null default 'STARTED',
  actor_user_id uuid references auth.users(id) on delete set null,
  process_name text,
  response_snapshot jsonb not null default '{}'::jsonb,
  error_code text,
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  constraint import_commit_commands_job_fk foreign key (organization_id, import_job_id)
    references integration.import_jobs (organization_id, id) on delete restrict,
  constraint import_commit_commands_key_check check (length(btrim(commit_idempotency_key)) between 1 and 200),
  constraint import_commit_commands_hash_check check (request_hash ~ '^[0-9a-f]{64}$'),
  constraint import_commit_commands_status_check check (status_code in ('STARTED', 'SUCCEEDED', 'FAILED')),
  constraint import_commit_commands_actor_check check ((actor_user_id is not null) <> (process_name is not null)),
  constraint import_commit_commands_completion_check check (
    (status_code = 'STARTED' and completed_at is null)
    or (status_code in ('SUCCEEDED', 'FAILED') and completed_at is not null)
  )
);

create unique index import_commit_commands_job_key
  on integration.import_commit_commands (organization_id, import_job_id, commit_idempotency_key);
create index import_commit_commands_job_status
  on integration.import_commit_commands (organization_id, import_job_id, status_code, started_at desc);

create table integration.marketplace_csv_event_identities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  channel_code text not null,
  external_event_ref text not null,
  event_request_hash text not null,
  canonical_idempotency_key text not null,
  canonical_event_id uuid not null,
  marketplace_order_id uuid not null,
  normalization_event_id uuid not null,
  first_import_job_id uuid not null,
  response_snapshot jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint csv_event_identity_job_fk foreign key (organization_id, first_import_job_id)
    references integration.import_jobs (organization_id, id) on delete restrict,
  constraint csv_event_identity_hash_check check (event_request_hash ~ '^[0-9a-f]{64}$'),
  constraint csv_event_identity_key_check check (length(btrim(canonical_idempotency_key)) between 1 and 200),
  constraint csv_event_identity_ref_check check (length(btrim(external_event_ref)) between 1 and 200),
  constraint csv_event_identity_channel_check check (length(btrim(channel_code)) between 1 and 100),
  constraint csv_event_identity_response_check check (jsonb_typeof(response_snapshot) = 'object')
);

comment on table integration.marketplace_csv_event_identities is
  'Stable organization/channel/external-event identity for CSV RESERVE events. It excludes job and raw-file identity so replay across files has one domain effect.';
comment on column integration.marketplace_csv_event_identities.event_request_hash is
  'Semantic normalized event payload hash; raw row evidence and import job identity are intentionally excluded.';

create unique index marketplace_csv_event_identity_key
  on integration.marketplace_csv_event_identities (organization_id, channel_code, external_event_ref);
create index marketplace_csv_event_identity_job
  on integration.marketplace_csv_event_identities (organization_id, first_import_job_id, created_at, id);

create table integration.import_event_results (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete restrict,
  import_job_id uuid not null,
  import_commit_command_id uuid not null,
  event_identity_id uuid not null,
  event_group_key text not null,
  status_code text not null,
  external_event_ref text not null,
  canonical_idempotency_key text not null,
  canonical_event_id uuid not null,
  marketplace_order_id uuid not null,
  normalization_event_id uuid not null,
  response_snapshot jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint import_event_results_job_fk foreign key (organization_id, import_job_id)
    references integration.import_jobs (organization_id, id) on delete restrict,
  constraint import_event_results_command_fk foreign key (import_commit_command_id)
    references integration.import_commit_commands(id) on delete restrict,
  constraint import_event_results_identity_fk foreign key (event_identity_id)
    references integration.marketplace_csv_event_identities(id) on delete restrict,
  constraint import_event_results_status_check check (status_code in ('COMPLETED', 'REPLAYED')),
  constraint import_event_results_response_check check (jsonb_typeof(response_snapshot) = 'object')
);

comment on table integration.import_event_results is
  'Audit linkage from one import job group to the canonical normalized event, order, and reservation result.';

create unique index import_event_results_job_group_key
  on integration.import_event_results (organization_id, import_job_id, event_group_key);
create index import_event_results_job_order_key
  on integration.import_event_results (organization_id, import_job_id, created_at, id);

alter table integration.import_rows
  add column if not exists commit_result_id uuid,
  add column if not exists canonical_event_id uuid,
  add column if not exists marketplace_order_id uuid,
  add column if not exists normalization_event_id uuid;

alter table integration.import_rows
  add constraint import_rows_commit_result_fk
    foreign key (commit_result_id) references integration.import_event_results(id) on delete restrict;

create index import_rows_job_processing_order_key
  on integration.import_rows (organization_id, import_job_id, processing_status_code, row_number, id);

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
  commit_result_id,
  canonical_event_id,
  marketplace_order_id,
  normalization_event_id,
  processed_at,
  created_at,
  updated_at
from integration.import_rows;

grant select on api.import_row_preview_read_model to authenticated, service_role;
revoke all on api.import_row_preview_read_model from public, anon;

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
    or (old.status_code = 'COMMIT_FAILED' and new.status_code = 'COMMITTING')
  ) then
    raise exception using errcode = 'P0001', message = 'IMPORT_INVALID_STATE_TRANSITION';
  end if;

  return new;
end;
$$;

alter table integration.import_commit_commands enable row level security;
alter table integration.import_commit_commands force row level security;
alter table integration.marketplace_csv_event_identities enable row level security;
alter table integration.marketplace_csv_event_identities force row level security;
alter table integration.import_event_results enable row level security;
alter table integration.import_event_results force row level security;

create policy import_commit_commands_read_current_organization
on integration.import_commit_commands for select to authenticated
using (organization_id = app.current_organization_id());

create policy marketplace_csv_event_identities_read_current_organization
on integration.marketplace_csv_event_identities for select to authenticated
using (organization_id = app.current_organization_id());

create policy import_event_results_read_current_organization
on integration.import_event_results for select to authenticated
using (organization_id = app.current_organization_id());

revoke all on integration.import_commit_commands,
  integration.marketplace_csv_event_identities,
  integration.import_event_results
from public, anon;
revoke insert, update, delete, truncate, references, trigger
on integration.import_commit_commands,
   integration.marketplace_csv_event_identities,
   integration.import_event_results
from authenticated;
grant select on integration.import_commit_commands,
  integration.marketplace_csv_event_identities,
  integration.import_event_results
to authenticated;
grant all on integration.import_commit_commands,
  integration.marketplace_csv_event_identities,
  integration.import_event_results
to service_role;

create view api.import_commit_read_model
with (security_invoker = true, security_barrier = true)
as
select id, organization_id, import_job_id, commit_idempotency_key,
  request_hash, status_code, response_snapshot, error_code,
  started_at, completed_at
from integration.import_commit_commands;

create view api.import_event_result_read_model
with (security_invoker = true, security_barrier = true)
as
select id, organization_id, import_job_id, import_commit_command_id,
  event_identity_id, event_group_key, status_code, external_event_ref,
  canonical_idempotency_key, canonical_event_id, marketplace_order_id,
  normalization_event_id, response_snapshot, created_at
from integration.import_event_results;

grant select on api.import_commit_read_model, api.import_event_result_read_model
to authenticated, service_role;
revoke all on api.import_commit_read_model, api.import_event_result_read_model
from public, anon;

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
  v_identity_lines jsonb;
  v_raw_rows jsonb;
  v_event_request_hash text;
  v_canonical_key text;
  v_effective_canonical_key text;
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

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':CSV_IMPORT_JOB:' || p_import_job_id::text, 0::bigint));

  select * into v_job
  from integration.import_jobs
  where organization_id = p_organization_id and id = p_import_job_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'CSV_IMPORT_JOB_NOT_FOUND';
  end if;

  select encode(extensions.digest(convert_to(
    jsonb_build_object(
      'jobId', v_job.id,
      'organizationId', v_job.organization_id,
      'templateVersion', v_job.template_version,
      'fileSha256', v_job.file_sha256,
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'rowNumber', row.row_number,
        'rawRow', row.raw_row,
        'rowFingerprint', row.row_fingerprint,
        'normalizedRow', row.normalized_row,
        'validationStatus', row.validation_status_code,
        'eventGroupKey', row.event_group_key,
        'expansionPreview', row.expansion_preview
      ) order by row.row_number, row.id) from integration.import_rows row where row.organization_id = v_job.organization_id and row.import_job_id = v_job.id), '[]'::jsonb)
    )::text, 'UTF8'), 'sha256'), 'hex') into v_basis_hash;

  select * into v_command
  from integration.import_commit_commands
  where organization_id = v_job.organization_id
    and import_job_id = v_job.id
    and commit_idempotency_key = btrim(p_commit_idempotency_key)
  for update;
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

  update integration.import_jobs
  set status_code = 'COMMITTING', failure_code = null, failure_detail = null
  where id = v_job.id;

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
      group by row.event_group_key
      order by row.event_group_key
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
      )) order by row.row_number, row.id),
      jsonb_agg(row.raw_row order by row.row_number, row.id)
      into v_lines, v_raw_rows
      from integration.import_rows row
      where row.organization_id = v_job.organization_id and row.import_job_id = v_job.id and row.event_group_key = v_group.event_group_key;

      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'sourceLineRef', row.normalized_row ->> 'source_line_ref',
        'externalListingCode', row.normalized_row ->> 'external_listing_code',
        'listingQuantity', (row.normalized_row ->> 'listing_quantity')::bigint,
        'sourceTitle', nullif(row.normalized_row ->> 'source_title', ''),
        'sourceSku', nullif(row.normalized_row ->> 'source_sku', ''),
        'sourceStatus', row.normalized_row ->> 'source_status'
      )) order by row.row_number, row.id)
      into v_identity_lines
      from integration.import_rows row
      where row.organization_id = v_job.organization_id and row.import_job_id = v_job.id and row.event_group_key = v_group.event_group_key;

      v_event_request_hash := encode(extensions.digest(convert_to(jsonb_build_object(
        'organizationId', v_job.organization_id,
        'channelCode', upper(btrim(v_group.channel_code)),
        'eventRef', btrim(v_group.external_event_ref),
        'orderRef', btrim(v_group.external_order_ref),
        'sourceStatus', upper(btrim(v_group.source_status)),
        'occurredAt', v_group.occurred_at,
        'receivedAt', v_group.received_at,
        'lines', v_identity_lines,
        'note', v_group.note,
        'schemaVersion', 1
      )::text, 'UTF8'), 'sha256'), 'hex');
      v_canonical_key := 'csv-reserve-v1:' || encode(extensions.digest(convert_to(v_job.organization_id::text || ':' || upper(btrim(v_group.channel_code)) || ':' || btrim(v_group.external_event_ref), 'UTF8'), 'sha256'), 'hex');

      perform pg_advisory_xact_lock(hashtextextended(v_job.organization_id::text || ':CSV_IMPORT_EVENT:' || upper(btrim(v_group.channel_code)) || ':' || btrim(v_group.external_event_ref), 0::bigint));
      v_existing_identity := null;
      select * into v_existing_identity
      from integration.marketplace_csv_event_identities identity
      where identity.organization_id = v_job.organization_id
        and identity.channel_code = upper(btrim(v_group.channel_code))
        and identity.external_event_ref = btrim(v_group.external_event_ref)
      for update;

      if found then
        if v_existing_identity.event_request_hash <> v_event_request_hash then
          raise exception using errcode = 'P0001', message = 'CSV_EXTERNAL_EVENT_CONFLICT';
        end if;
        v_identity_id := v_existing_identity.id;
        v_result := v_existing_identity.response_snapshot;
        v_effective_canonical_key := v_existing_identity.canonical_idempotency_key;
        v_status := 'REPLAYED';
      else
        if exists (select 1 from operations.marketplace_events event where event.organization_id = v_job.organization_id and event.external_event_ref = btrim(v_group.external_event_ref) and event.channel_id = (select channel.id from catalog.channels channel where channel.code = upper(btrim(v_group.channel_code)))) then
          raise exception using errcode = 'P0001', message = 'CSV_EXTERNAL_EVENT_ALREADY_EXISTS';
        end if;
        v_result := api.reserve_marketplace_listing_event(
          v_job.organization_id,
          v_canonical_key,
          upper(btrim(v_group.channel_code)),
          btrim(v_group.external_event_ref),
          btrim(v_group.external_order_ref),
          upper(btrim(v_group.source_status)),
          v_group.occurred_at,
          v_group.received_at,
          v_lines,
          v_group.note,
          jsonb_build_object('adapter', 'CSV', 'templateVersion', v_job.template_version, 'eventGroupKey', v_group.event_group_key, 'rows', v_raw_rows),
          jsonb_build_object('adapterContract', 'MARKETPLACE_LISTING_EVENT_V1', 'csvTemplateVersion', v_job.template_version, 'externalEventIdentity', upper(btrim(v_group.channel_code)) || ':' || btrim(v_group.external_event_ref), 'eventRequestHash', v_event_request_hash),
          1
        );
        insert into integration.marketplace_csv_event_identities (
          organization_id, channel_code, external_event_ref, event_request_hash,
          canonical_idempotency_key, canonical_event_id, marketplace_order_id,
          normalization_event_id, first_import_job_id, response_snapshot
        ) values (
          v_job.organization_id, upper(btrim(v_group.channel_code)), btrim(v_group.external_event_ref), v_event_request_hash,
          v_canonical_key, (v_result ->> 'eventId')::uuid, (v_result ->> 'orderId')::uuid,
          (v_result ->> 'normalizationEventId')::uuid, v_job.id, v_result
        ) returning id into v_identity_id;
        v_effective_canonical_key := v_canonical_key;
        v_status := 'COMPLETED';
      end if;

      insert into integration.import_event_results (
        organization_id, import_job_id, import_commit_command_id, event_identity_id,
        event_group_key, status_code, external_event_ref, canonical_idempotency_key,
        canonical_event_id, marketplace_order_id, normalization_event_id, response_snapshot
      ) values (
        v_job.organization_id, v_job.id, v_commit_id, v_identity_id, v_group.event_group_key,
        v_status, btrim(v_group.external_event_ref), v_effective_canonical_key,
        (v_result ->> 'eventId')::uuid, (v_result ->> 'orderId')::uuid,
        (v_result ->> 'normalizationEventId')::uuid, v_result
      ) returning id into v_group_result_id;

      update integration.import_rows row
      set processing_status_code = 'PROCESSED',
          canonical_idempotency_key = v_effective_canonical_key,
          result_entity_type = 'MARKETPLACE_EVENT',
          result_entity_id = (v_result ->> 'eventId')::uuid,
          canonical_event_id = (v_result ->> 'eventId')::uuid,
          marketplace_order_id = (v_result ->> 'orderId')::uuid,
          normalization_event_id = (v_result ->> 'normalizationEventId')::uuid,
          commit_result_id = v_group_result_id,
          processed_at = clock_timestamp()
      where row.organization_id = v_job.organization_id and row.import_job_id = v_job.id and row.event_group_key = v_group.event_group_key;

      v_processed_rows := v_processed_rows + v_group.row_count;
      v_event_count := v_event_count + 1;
      v_event_results := v_event_results || jsonb_build_array(jsonb_build_object('eventGroupKey', v_group.event_group_key, 'status', v_status, 'eventId', v_result ->> 'eventId', 'orderId', v_result ->> 'orderId', 'normalizationEventId', v_result ->> 'normalizationEventId'));
    end loop;
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_failed_detail = message_text;
    v_failed_code := case when coalesce(v_failed_detail, '') ~ '^(CSV_|MARKETPLACE_|IDEMPOTENCY_)' then v_failed_detail else 'CSV_IMPORT_COMMIT_FAILED' end;
    v_failed_detail := case when v_failed_code = v_failed_detail then left(v_failed_detail, 200) else 'Canonical reservation batch gagal; seluruh domain effect dibatalkan.' end;
  end;

  if v_failed_code is not null then
    update integration.import_commit_commands
    set status_code = 'FAILED', completed_at = clock_timestamp(), error_code = v_failed_code,
        response_snapshot = jsonb_build_object('status', 'COMMIT_FAILED', 'jobId', v_job.id, 'errorCode', v_failed_code, 'detail', v_failed_detail)
    where id = v_commit_id;
    update integration.import_jobs
    set status_code = 'COMMIT_FAILED', failure_code = v_failed_code, failure_detail = v_failed_detail,
        processed_row_count = 0
    where id = v_job.id;
    return jsonb_build_object('status', 'COMMIT_FAILED', 'jobId', v_job.id, 'errorCode', v_failed_code, 'detail', v_failed_detail);
  end if;

  v_response := jsonb_build_object('status', 'COMPLETED', 'jobId', v_job.id, 'commitCommandId', v_commit_id, 'requestHash', v_basis_hash, 'processedRowCount', v_processed_rows, 'eventCount', v_event_count, 'events', v_event_results);
  update integration.import_commit_commands
  set status_code = 'SUCCEEDED', completed_at = clock_timestamp(), response_snapshot = v_response
  where id = v_commit_id;
  update integration.import_jobs
  set status_code = 'COMPLETED', committed_at = clock_timestamp(), processed_row_count = v_processed_rows,
      failure_code = null, failure_detail = null
  where id = v_job.id;
  return v_response;
end;
$$;

comment on function api.commit_marketplace_csv_import_job(uuid, uuid, text, boolean) is
  'Trusted atomic CSV v1 ORDER/RESERVE commit. It reuses api.reserve_marketplace_listing_event; shipment, cancellation, return, direct ledger, and direct projection writes are not supported.';

revoke all on function api.commit_marketplace_csv_import_job(uuid, uuid, text, boolean)
from public, anon, authenticated;
grant execute on function api.commit_marketplace_csv_import_job(uuid, uuid, text, boolean)
to service_role;

commit;
