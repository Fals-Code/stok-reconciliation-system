begin;

-- notification.rules already exists from the database foundation.
-- This migration hardens its organization key and adds the runtime persistence
-- required by the Phase 1 Notification Center.

alter table notification.rules
add constraint uq_notification_rules_org_id
unique (organization_id, id);

alter table notification.rules
add constraint ck_notification_rules_category_nonblank
check (btrim(category_code) <> '');

alter table notification.rules
add constraint ck_notification_rules_trigger_mode
check (trigger_mode_code in ('EVENT_DRIVEN', 'SCHEDULED', 'HYBRID'));

alter table notification.rules
add constraint ck_notification_rules_entity_type_nonblank
check (btrim(entity_type_code) <> '');

alter table notification.rules
add constraint ck_notification_rules_strategy_nonblank
check (
  btrim(severity_strategy_code) <> ''
  and btrim(stage_strategy_code) <> ''
  and btrim(condition_strategy_code) <> ''
  and btrim(resolution_strategy_code) <> ''
);

alter table notification.rules
add constraint ck_notification_rules_template_action_nonblank
check (
  btrim(template_version) <> ''
  and btrim(action_code) <> ''
);

alter table notification.rules
add constraint ck_notification_rules_config_object
check (jsonb_typeof(config) = 'object');

create table notification.outbox_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references app.organizations(id) on delete restrict,
  event_type_code text not null,
  source_event_key text not null,
  entity_type_code text not null,
  entity_id uuid not null,
  occurred_at timestamptz not null,
  payload jsonb not null default '{}'::jsonb,
  payload_hash text not null,
  correlation_id uuid not null default gen_random_uuid(),
  status_code text not null default 'PENDING',
  attempt_count integer not null default 0,
  available_at timestamptz not null default clock_timestamp(),
  locked_at timestamptz null,
  locked_by text null,
  completed_at timestamptz null,
  last_error_code text null,
  last_error_detail jsonb not null default '{}'::jsonb,
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  created_at timestamptz not null default clock_timestamp(),

  constraint uq_notification_outbox_org_id
    unique (organization_id, id),

  constraint uq_notification_outbox_source_event
    unique (organization_id, event_type_code, source_event_key),

  constraint ck_notification_outbox_event_type_nonblank
    check (btrim(event_type_code) <> ''),

  constraint ck_notification_outbox_source_key_nonblank
    check (btrim(source_event_key) <> ''),

  constraint ck_notification_outbox_entity_type_nonblank
    check (btrim(entity_type_code) <> ''),

  constraint ck_notification_outbox_payload_object
    check (jsonb_typeof(payload) = 'object'),

  constraint ck_notification_outbox_payload_hash
    check (payload_hash ~ '^[0-9a-f]{64}$'),

  constraint ck_notification_outbox_status
    check (
      status_code in (
        'PENDING',
        'PROCESSING',
        'COMPLETED',
        'FAILED_RETRYABLE',
        'FAILED_FINAL'
      )
    ),

  constraint ck_notification_outbox_attempt_count
    check (attempt_count >= 0),

  constraint ck_notification_outbox_available_time
    check (available_at >= occurred_at),

  constraint ck_notification_outbox_lock_pair
    check (
      (locked_at is null and locked_by is null)
      or (
        locked_at is not null
        and locked_by is not null
        and btrim(locked_by) <> ''
      )
    ),

  constraint ck_notification_outbox_status_payload
    check (
      (
        status_code = 'PENDING'
        and locked_at is null
        and locked_by is null
        and completed_at is null
      )
      or (
        status_code = 'PROCESSING'
        and locked_at is not null
        and locked_by is not null
        and completed_at is null
      )
      or (
        status_code = 'COMPLETED'
        and locked_at is null
        and locked_by is null
        and completed_at is not null
      )
      or (
        status_code = 'FAILED_RETRYABLE'
        and locked_at is null
        and locked_by is null
        and completed_at is null
        and last_error_code is not null
        and btrim(last_error_code) <> ''
      )
      or (
        status_code = 'FAILED_FINAL'
        and locked_at is null
        and locked_by is null
        and completed_at is not null
        and last_error_code is not null
        and btrim(last_error_code) <> ''
      )
    ),

  constraint ck_notification_outbox_error_detail_object
    check (jsonb_typeof(last_error_detail) = 'object'),

  constraint ck_notification_outbox_actor_xor_process
    check ((actor_user_id is not null) <> (process_name is not null)),

  constraint ck_notification_outbox_process_nonblank
    check (process_name is null or btrim(process_name) <> '')
);

create table notification.rule_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  rule_id uuid null,
  rule_code_snapshot text not null,
  rule_version_snapshot text not null,
  trigger_type_code text not null,
  triggered_by_outbox_event_id uuid null,
  idempotency_key text not null,
  status_code text not null default 'STARTED',
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz null,
  evaluated_count integer not null default 0,
  created_count integer not null default 0,
  updated_count integer not null default 0,
  resolved_count integer not null default 0,
  skipped_count integer not null default 0,
  error_count integer not null default 0,
  summary jsonb not null default '{}'::jsonb,
  error_code text null,
  error_detail jsonb not null default '{}'::jsonb,
  correlation_id uuid not null default gen_random_uuid(),
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  created_at timestamptz not null default clock_timestamp(),

  constraint uq_notification_rule_runs_org_id
    unique (organization_id, id),

  constraint fk_notification_rule_runs_organization
    foreign key (organization_id)
    references app.organizations(id)
    on delete restrict,

  constraint fk_notification_rule_runs_rule
    foreign key (organization_id, rule_id)
    references notification.rules(organization_id, id)
    on delete restrict,

  constraint fk_notification_rule_runs_outbox
    foreign key (organization_id, triggered_by_outbox_event_id)
    references notification.outbox_events(organization_id, id)
    on delete restrict,

  constraint uq_notification_rule_runs_idempotency
    unique (organization_id, rule_code_snapshot, idempotency_key),

  constraint ck_notification_rule_runs_rule_code_nonblank
    check (btrim(rule_code_snapshot) <> ''),

  constraint ck_notification_rule_runs_rule_version_nonblank
    check (btrim(rule_version_snapshot) <> ''),

  constraint ck_notification_rule_runs_trigger_type
    check (
      trigger_type_code in (
        'EVENT_DRIVEN',
        'SCHEDULED',
        'MANUAL',
        'OUTBOX'
      )
    ),

  constraint ck_notification_rule_runs_idempotency_nonblank
    check (btrim(idempotency_key) <> ''),

  constraint ck_notification_rule_runs_status
    check (
      status_code in (
        'STARTED',
        'SUCCEEDED',
        'PARTIALLY_FAILED',
        'FAILED'
      )
    ),

  constraint ck_notification_rule_runs_completion
    check (
      (status_code = 'STARTED' and completed_at is null)
      or (
        status_code in ('SUCCEEDED', 'PARTIALLY_FAILED', 'FAILED')
        and completed_at is not null
      )
    ),

  constraint ck_notification_rule_runs_counts
    check (
      evaluated_count >= 0
      and created_count >= 0
      and updated_count >= 0
      and resolved_count >= 0
      and skipped_count >= 0
      and error_count >= 0
      and created_count + updated_count + resolved_count + skipped_count
        <= evaluated_count
    ),

  constraint ck_notification_rule_runs_error_state
    check (
      (
        status_code in ('STARTED', 'SUCCEEDED')
        and error_count = 0
        and error_code is null
      )
      or (
        status_code = 'PARTIALLY_FAILED'
        and error_count > 0
      )
      or (
        status_code = 'FAILED'
        and error_count > 0
        and error_code is not null
        and btrim(error_code) <> ''
      )
    ),

  constraint ck_notification_rule_runs_summary_object
    check (jsonb_typeof(summary) = 'object'),

  constraint ck_notification_rule_runs_error_detail_object
    check (jsonb_typeof(error_detail) = 'object'),

  constraint ck_notification_rule_runs_actor_xor_process
    check ((actor_user_id is not null) <> (process_name is not null)),

  constraint ck_notification_rule_runs_process_nonblank
    check (process_name is null or btrim(process_name) <> '')
);

create table notification.notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  rule_id uuid not null,
  rule_code_snapshot text not null,
  rule_version_snapshot text not null,
  template_version_snapshot text not null,
  notification_type_code text not null,
  category_code text not null,
  entity_type_code text not null,
  entity_id uuid not null,
  episode_no integer not null default 1,
  previous_notification_id uuid null,
  deduplication_key text not null,
  deduplication_hash text not null,
  lifecycle_status_code text not null default 'OPEN',
  stage_code text not null,
  severity_code text not null,
  title text not null,
  message text not null,
  action_code text not null,
  action_route text not null,
  condition_started_at timestamptz not null,
  due_at timestamptz null,
  first_seen_at timestamptz not null,
  last_seen_at timestamptz not null,
  last_reminded_at timestamptz null,
  occurrence_count integer not null default 1,
  acknowledged_at timestamptz null,
  acknowledged_by uuid null references auth.users(id) on delete set null,
  acknowledgment_note text null,
  resolved_at timestamptz null,
  resolution_code text null,
  resolution_snapshot jsonb null,
  source_snapshot jsonb not null default '{}'::jsonb,
  config_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  version_no bigint not null default 1,

  constraint uq_notifications_org_id
    unique (organization_id, id),

  constraint fk_notifications_organization
    foreign key (organization_id)
    references app.organizations(id)
    on delete restrict,

  constraint fk_notifications_rule
    foreign key (organization_id, rule_id)
    references notification.rules(organization_id, id)
    on delete restrict,

  constraint fk_notifications_previous_episode
    foreign key (organization_id, previous_notification_id)
    references notification.notifications(organization_id, id)
    on delete restrict,

  constraint uq_notifications_episode
    unique (organization_id, deduplication_hash, episode_no),

  constraint ck_notifications_rule_snapshot_nonblank
    check (
      btrim(rule_code_snapshot) <> ''
      and btrim(rule_version_snapshot) <> ''
      and btrim(template_version_snapshot) <> ''
    ),

  constraint ck_notifications_type_category_nonblank
    check (
      btrim(notification_type_code) <> ''
      and btrim(category_code) <> ''
      and btrim(entity_type_code) <> ''
    ),

  constraint ck_notifications_episode_positive
    check (episode_no > 0),

  constraint ck_notifications_previous_not_self
    check (previous_notification_id is null or previous_notification_id <> id),

  constraint ck_notifications_dedup_key_nonblank
    check (btrim(deduplication_key) <> ''),

  constraint ck_notifications_dedup_hash
    check (deduplication_hash ~ '^[0-9a-f]{64}$'),

  constraint ck_notifications_lifecycle
    check (
      lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED',
        'RESOLVED'
      )
    ),

  constraint ck_notifications_stage_nonblank
    check (btrim(stage_code) <> ''),

  constraint ck_notifications_severity
    check (severity_code in ('INFO', 'WARNING', 'HIGH', 'CRITICAL')),

  constraint ck_notifications_title
    check (btrim(title) <> '' and length(title) <= 300),

  constraint ck_notifications_message
    check (btrim(message) <> '' and length(message) <= 4000),

  constraint ck_notifications_action
    check (
      btrim(action_code) <> ''
      and btrim(action_route) <> ''
      and left(action_route, 1) = '/'
      and length(action_route) <= 2000
    ),

  constraint ck_notifications_seen_times
    check (
      condition_started_at <= first_seen_at
      and first_seen_at <= last_seen_at
      and (
        last_reminded_at is null
        or last_reminded_at >= first_seen_at
      )
    ),

  constraint ck_notifications_occurrence_positive
    check (occurrence_count > 0),

  constraint ck_notifications_acknowledgment_note
    check (
      acknowledgment_note is null
      or (
        btrim(acknowledgment_note) <> ''
        and length(acknowledgment_note) <= 2000
      )
    ),

  constraint ck_notifications_resolution_code
    check (
      resolution_code is null
      or btrim(resolution_code) <> ''
    ),

  constraint ck_notifications_lifecycle_payload
    check (
      (
        lifecycle_status_code = 'OPEN'
        and acknowledged_at is null
        and acknowledged_by is null
        and resolved_at is null
        and resolution_code is null
        and resolution_snapshot is null
      )
      or (
        lifecycle_status_code = 'ACKNOWLEDGED'
        and acknowledged_at is not null
        and acknowledged_by is not null
        and resolved_at is null
        and resolution_code is null
        and resolution_snapshot is null
      )
      or (
        lifecycle_status_code = 'RESOLVED'
        and resolved_at is not null
        and resolution_code is not null
        and btrim(resolution_code) <> ''
        and resolution_snapshot is not null
        and jsonb_typeof(resolution_snapshot) = 'object'
      )
    ),

  constraint ck_notifications_source_snapshot_object
    check (jsonb_typeof(source_snapshot) = 'object'),

  constraint ck_notifications_config_snapshot_object
    check (jsonb_typeof(config_snapshot) = 'object'),

  constraint ck_notifications_version_positive
    check (version_no > 0)
);

create table notification.notification_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  notification_id uuid not null,
  event_type_code text not null,
  from_lifecycle_status_code text null,
  to_lifecycle_status_code text null,
  from_stage_code text null,
  to_stage_code text null,
  from_severity_code text null,
  to_severity_code text null,
  source_snapshot jsonb not null default '{}'::jsonb,
  note text null,
  actor_type_code text not null,
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  occurred_at timestamptz not null,
  correlation_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default clock_timestamp(),

  constraint fk_notification_events_notification
    foreign key (organization_id, notification_id)
    references notification.notifications(organization_id, id)
    on delete restrict,

  constraint ck_notification_events_type
    check (
      event_type_code in (
        'CREATED',
        'SEEN_AGAIN',
        'STAGE_ESCALATED',
        'STAGE_DEESCALATED',
        'SEVERITY_CHANGED',
        'REMINDER_EMITTED',
        'ACKNOWLEDGED',
        'ACKNOWLEDGMENT_REVOKED',
        'RESOLVED',
        'REOPENED_AS_NEW_EPISODE',
        'SOURCE_SNAPSHOT_UPDATED',
        'READ_STATE_RESET_BY_ESCALATION'
      )
    ),

  constraint ck_notification_events_lifecycle_from
    check (
      from_lifecycle_status_code is null
      or from_lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED',
        'RESOLVED'
      )
    ),

  constraint ck_notification_events_lifecycle_to
    check (
      to_lifecycle_status_code is null
      or to_lifecycle_status_code in (
        'OPEN',
        'ACKNOWLEDGED',
        'RESOLVED'
      )
    ),

  constraint ck_notification_events_stage_nonblank
    check (
      (from_stage_code is null or btrim(from_stage_code) <> '')
      and (to_stage_code is null or btrim(to_stage_code) <> '')
    ),

  constraint ck_notification_events_severity_from
    check (
      from_severity_code is null
      or from_severity_code in ('INFO', 'WARNING', 'HIGH', 'CRITICAL')
    ),

  constraint ck_notification_events_severity_to
    check (
      to_severity_code is null
      or to_severity_code in ('INFO', 'WARNING', 'HIGH', 'CRITICAL')
    ),

  constraint ck_notification_events_snapshot_object
    check (jsonb_typeof(source_snapshot) = 'object'),

  constraint ck_notification_events_note
    check (
      note is null
      or (
        btrim(note) <> ''
        and length(note) <= 2000
      )
    ),

  constraint ck_notification_events_actor
    check (
      (
        actor_type_code = 'USER'
        and actor_user_id is not null
        and process_name is null
      )
      or (
        actor_type_code = 'SYSTEM_PROCESS'
        and actor_user_id is null
        and process_name is not null
        and btrim(process_name) <> ''
      )
    )
);

create table notification.user_states (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  notification_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_state_code text not null default 'UNREAD',
  read_at timestamptz null,
  archived_at timestamptz null,
  last_seen_version_no bigint null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),

  constraint fk_notification_user_states_notification
    foreign key (organization_id, notification_id)
    references notification.notifications(organization_id, id)
    on delete cascade,

  constraint uq_notification_user_states_notification_user
    unique (notification_id, user_id),

  constraint ck_notification_user_states_read_state
    check (read_state_code in ('UNREAD', 'READ', 'ARCHIVED')),

  constraint ck_notification_user_states_state_payload
    check (
      (
        read_state_code = 'UNREAD'
        and read_at is null
        and archived_at is null
      )
      or (
        read_state_code = 'READ'
        and read_at is not null
        and archived_at is null
      )
      or (
        read_state_code = 'ARCHIVED'
        and archived_at is not null
      )
    ),

  constraint ck_notification_user_states_version
    check (
      last_seen_version_no is null
      or last_seen_version_no > 0
    )
);

create unique index uidx_notifications_active_dedup
on notification.notifications (
  organization_id,
  deduplication_hash
)
where lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED');

create index idx_notifications_org_active
on notification.notifications (
  organization_id,
  lifecycle_status_code,
  severity_code,
  last_seen_at desc,
  id
);

create index idx_notifications_entity
on notification.notifications (
  organization_id,
  entity_type_code,
  entity_id,
  created_at desc,
  id
);

create index idx_notification_events_history
on notification.notification_events (
  organization_id,
  notification_id,
  occurred_at,
  id
);

create index idx_notification_user_states_user
on notification.user_states (
  organization_id,
  user_id,
  read_state_code,
  updated_at desc,
  notification_id
);

create index idx_notification_outbox_pending
on notification.outbox_events (
  available_at,
  created_at,
  id
)
where status_code in ('PENDING', 'FAILED_RETRYABLE');

create index idx_notification_rule_runs_status
on notification.rule_runs (
  organization_id,
  rule_code_snapshot,
  status_code,
  started_at desc,
  id
);

create or replace function notification.touch_notification_row()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  new.version_no := old.version_no + 1;
  return new;
end;
$$;

create or replace function notification.reject_immutable_event_mutation()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = 'IMMUTABLE_NOTIFICATION_EVENT';
end;
$$;

revoke all
on function notification.touch_notification_row()
from public, anon, authenticated;

revoke all
on function notification.reject_immutable_event_mutation()
from public, anon, authenticated;

create trigger trg_notifications_touch_version
before update on notification.notifications
for each row execute function notification.touch_notification_row();

create trigger trg_notification_events_immutable
before update or delete on notification.notification_events
for each row execute function notification.reject_immutable_event_mutation();

create trigger trg_notification_user_states_touch_updated_at
before update on notification.user_states
for each row execute function app.touch_updated_at();

alter table notification.outbox_events enable row level security;
alter table notification.rule_runs enable row level security;
alter table notification.notifications enable row level security;
alter table notification.notification_events enable row level security;
alter table notification.user_states enable row level security;

create policy notification_rule_runs_read_current_org
on notification.rule_runs
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy notifications_read_current_org
on notification.notifications
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy notification_events_read_current_org
on notification.notification_events
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy notification_user_states_read_self
on notification.user_states
for select
to authenticated
using (
  organization_id = (select app.current_organization_id())
  and user_id = (select auth.uid())
);

revoke all
on notification.outbox_events,
   notification.rule_runs,
   notification.notifications,
   notification.notification_events,
   notification.user_states
from public, anon, authenticated;

grant select
on notification.rule_runs,
   notification.notifications,
   notification.notification_events,
   notification.user_states
to authenticated;

grant usage on schema notification to service_role;

grant select, insert, update, delete
on notification.outbox_events,
   notification.rule_runs,
   notification.notifications,
   notification.notification_events,
   notification.user_states
to service_role;

commit;
