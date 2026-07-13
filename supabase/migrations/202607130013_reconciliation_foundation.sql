begin;

create schema if not exists reconciliation;

revoke all on schema reconciliation from public;

create table reconciliation.runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references app.organizations(id) on delete restrict,
  run_no text not null,
  run_type_code text not null default 'MANUAL',
  trigger_code text not null default 'MANUAL',
  status_code text not null default 'RUNNING',
  scope jsonb not null default '{}'::jsonb,
  check_codes text[] not null,
  rule_set_version text not null,
  ledger_seq_from bigint not null default 0,
  ledger_seq_to bigint not null,
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz null,
  actor_user_id uuid null references auth.users(id) on delete set null,
  process_name text null,
  idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  summary jsonb not null default '{}'::jsonb,
  error_code text null,
  error_detail jsonb null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),

  constraint uq_reconciliation_runs_org_id
    unique (organization_id, id),

  constraint uq_reconciliation_runs_no
    unique (organization_id, run_no),

  constraint uq_reconciliation_runs_idempotency
    unique (idempotency_command_id),

  constraint ck_reconciliation_runs_no_nonblank
    check (btrim(run_no) <> ''),

  constraint ck_reconciliation_runs_type
    check (
      run_type_code in (
        'MANUAL',
        'DAILY',
        'POST_STOCKTAKE',
        'POST_REBUILD'
      )
    ),

  constraint ck_reconciliation_runs_trigger
    check (trigger_code in ('MANUAL', 'SYSTEM')),

  constraint ck_reconciliation_runs_status
    check (status_code in ('RUNNING', 'SUCCEEDED', 'FAILED')),

  constraint ck_reconciliation_runs_completion
    check (
      (status_code = 'RUNNING' and completed_at is null)
      or
      (status_code in ('SUCCEEDED', 'FAILED') and completed_at is not null)
    ),

  constraint ck_reconciliation_runs_actor_xor_process
    check ((actor_user_id is not null) <> (process_name is not null)),

  constraint ck_reconciliation_runs_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),

  constraint ck_reconciliation_runs_check_codes
    check (cardinality(check_codes) > 0),

  constraint ck_reconciliation_runs_rule_version_nonblank
    check (btrim(rule_set_version) <> ''),

  constraint ck_reconciliation_runs_ledger_from
    check (ledger_seq_from >= 0),

  constraint ck_reconciliation_runs_ledger_boundary
    check (ledger_seq_to >= ledger_seq_from),

  constraint ck_reconciliation_runs_scope_object
    check (jsonb_typeof(scope) = 'object'),

  constraint ck_reconciliation_runs_summary_object
    check (jsonb_typeof(summary) = 'object'),

  constraint ck_reconciliation_runs_error_detail_object
    check (
      error_detail is null
      or jsonb_typeof(error_detail) = 'object'
    ),

  constraint ck_reconciliation_runs_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create trigger trg_reconciliation_runs_touch_updated_at
before update on reconciliation.runs
for each row execute function app.touch_updated_at();

create table reconciliation.run_checks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  run_id uuid not null,
  check_code text not null,
  rule_version text not null,
  status_code text not null default 'PENDING',
  checked_count bigint not null default 0,
  issue_count bigint not null default 0,
  started_at timestamptz null,
  completed_at timestamptz null,
  summary jsonb not null default '{}'::jsonb,
  error_code text null,
  error_detail jsonb null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),

  constraint uq_reconciliation_run_checks_org_run_id
    unique (organization_id, run_id, id),

  constraint fk_reconciliation_run_checks_run
    foreign key (organization_id, run_id)
    references reconciliation.runs (organization_id, id)
    on delete restrict,

  constraint uq_reconciliation_run_checks_code
    unique (run_id, check_code),

  constraint ck_reconciliation_run_checks_code_nonblank
    check (btrim(check_code) <> ''),

  constraint ck_reconciliation_run_checks_rule_nonblank
    check (btrim(rule_version) <> ''),

  constraint ck_reconciliation_run_checks_status
    check (
      status_code in (
        'PENDING',
        'RUNNING',
        'PASSED',
        'FAILED',
        'ERROR'
      )
    ),

  constraint ck_reconciliation_run_checks_counts
    check (checked_count >= 0 and issue_count >= 0),

  constraint ck_reconciliation_run_checks_completion
    check (
      (
        status_code in ('PENDING', 'RUNNING')
        and completed_at is null
      )
      or
      (
        status_code in ('PASSED', 'FAILED', 'ERROR')
        and completed_at is not null
      )
    ),

  constraint ck_reconciliation_run_checks_summary_object
    check (jsonb_typeof(summary) = 'object'),

  constraint ck_reconciliation_run_checks_error_detail_object
    check (
      error_detail is null
      or jsonb_typeof(error_detail) = 'object'
    )
);

create trigger trg_reconciliation_run_checks_touch_updated_at
before update on reconciliation.run_checks
for each row execute function app.touch_updated_at();

create table reconciliation.issues (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references app.organizations(id) on delete restrict,
  fingerprint text not null,
  check_code text not null,
  rule_version text not null,
  status_code text not null default 'OPEN',
  severity_code text not null,
  entity_type_code text not null,
  entity_key jsonb not null,
  product_id uuid null,
  batch_id uuid null,
  source_type_code text null,
  source_ref text null,
  expected_value jsonb null,
  actual_value jsonb null,
  difference_value jsonb null,
  first_seen_run_id uuid not null,
  last_seen_run_id uuid not null,
  first_seen_at timestamptz not null default clock_timestamp(),
  last_seen_at timestamptz not null default clock_timestamp(),
  recurrence_count bigint not null default 1,
  resolved_at timestamptz null,
  resolution_code text null,
  resolution_note text null,
  resolved_by_user_id uuid null
    references auth.users(id) on delete set null,
  resolved_by_process_name text null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),

  constraint uq_reconciliation_issues_org_id
    unique (organization_id, id),

  constraint uq_reconciliation_issues_fingerprint
    unique (organization_id, fingerprint),

  constraint fk_reconciliation_issues_product
    foreign key (organization_id, product_id)
    references catalog.products (organization_id, id)
    on delete restrict,

  constraint fk_reconciliation_issues_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches (organization_id, product_id, id)
    on delete restrict,

  constraint fk_reconciliation_issues_first_run
    foreign key (organization_id, first_seen_run_id)
    references reconciliation.runs (organization_id, id)
    on delete restrict,

  constraint fk_reconciliation_issues_last_run
    foreign key (organization_id, last_seen_run_id)
    references reconciliation.runs (organization_id, id)
    on delete restrict,

  constraint ck_reconciliation_issues_fingerprint
    check (fingerprint ~ '^[0-9a-f]{64}$'),

  constraint ck_reconciliation_issues_check_nonblank
    check (btrim(check_code) <> ''),

  constraint ck_reconciliation_issues_rule_nonblank
    check (btrim(rule_version) <> ''),

  constraint ck_reconciliation_issues_status
    check (status_code in ('OPEN', 'RESOLVED')),

  constraint ck_reconciliation_issues_severity
    check (
      severity_code in (
        'INFO',
        'LOW',
        'MEDIUM',
        'HIGH',
        'CRITICAL'
      )
    ),

  constraint ck_reconciliation_issues_entity_nonblank
    check (btrim(entity_type_code) <> ''),

  constraint ck_reconciliation_issues_entity_key_object
    check (jsonb_typeof(entity_key) = 'object'),

  constraint ck_reconciliation_issues_batch_requires_product
    check (batch_id is null or product_id is not null),

  constraint ck_reconciliation_issues_source_pair
    check (
      (
        source_type_code is null
        and source_ref is null
      )
      or
      (
        source_type_code is not null
        and btrim(source_type_code) <> ''
        and source_ref is not null
        and btrim(source_ref) <> ''
      )
    ),

  constraint ck_reconciliation_issues_seen_order
    check (last_seen_at >= first_seen_at),

  constraint ck_reconciliation_issues_recurrence_positive
    check (recurrence_count > 0),

  constraint ck_reconciliation_issues_resolution
    check (
      (
        status_code = 'OPEN'
        and resolved_at is null
        and resolution_code is null
        and resolution_note is null
        and resolved_by_user_id is null
        and resolved_by_process_name is null
      )
      or
      (
        status_code = 'RESOLVED'
        and resolved_at is not null
        and resolution_code is not null
        and btrim(resolution_code) <> ''
        and (
          (resolved_by_user_id is not null)
          <>
          (resolved_by_process_name is not null)
        )
      )
    ),

  constraint ck_reconciliation_issues_resolution_process_nonblank
    check (
      resolved_by_process_name is null
      or btrim(resolved_by_process_name) <> ''
    )
);

create trigger trg_reconciliation_issues_touch_updated_at
before update on reconciliation.issues
for each row execute function app.touch_updated_at();

create table reconciliation.issue_evidence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  issue_id uuid not null,
  run_id uuid not null,
  run_check_id uuid not null,
  evidence_no integer not null,
  evidence_type_code text not null,
  entity_type_code text not null,
  entity_key jsonb not null,
  expected_value jsonb null,
  actual_value jsonb null,
  difference_value jsonb null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),

  constraint fk_reconciliation_issue_evidence_issue
    foreign key (organization_id, issue_id)
    references reconciliation.issues (organization_id, id)
    on delete restrict,

  constraint fk_reconciliation_issue_evidence_run
    foreign key (organization_id, run_id)
    references reconciliation.runs (organization_id, id)
    on delete restrict,

  constraint fk_reconciliation_issue_evidence_check
    foreign key (organization_id, run_id, run_check_id)
    references reconciliation.run_checks (organization_id, run_id, id)
    on delete restrict,

  constraint uq_reconciliation_issue_evidence_no
    unique (issue_id, run_id, evidence_no),

  constraint ck_reconciliation_issue_evidence_no_positive
    check (evidence_no > 0),

  constraint ck_reconciliation_issue_evidence_type_nonblank
    check (btrim(evidence_type_code) <> ''),

  constraint ck_reconciliation_issue_evidence_entity_nonblank
    check (btrim(entity_type_code) <> ''),

  constraint ck_reconciliation_issue_evidence_entity_key_object
    check (jsonb_typeof(entity_key) = 'object'),

  constraint ck_reconciliation_issue_evidence_detail_object
    check (jsonb_typeof(detail) = 'object')
);

create index idx_reconciliation_runs_status
on reconciliation.runs (
  organization_id,
  status_code,
  started_at desc,
  id
);

create index idx_reconciliation_run_checks_run_status
on reconciliation.run_checks (
  organization_id,
  run_id,
  status_code,
  check_code
);

create index idx_reconciliation_issues_open
on reconciliation.issues (
  organization_id,
  severity_code,
  last_seen_at desc,
  id
)
where status_code = 'OPEN';

create index idx_reconciliation_issue_evidence_issue
on reconciliation.issue_evidence (
  organization_id,
  issue_id,
  run_id,
  evidence_no
);

create trigger trg_reconciliation_issue_evidence_immutable
before update or delete on reconciliation.issue_evidence
for each row execute function inventory.reject_immutable_mutation();

alter table reconciliation.runs enable row level security;
alter table reconciliation.run_checks enable row level security;
alter table reconciliation.issues enable row level security;
alter table reconciliation.issue_evidence enable row level security;

create policy reconciliation_runs_read_current_org
on reconciliation.runs
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy reconciliation_run_checks_read_current_org
on reconciliation.run_checks
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy reconciliation_issues_read_current_org
on reconciliation.issues
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy reconciliation_issue_evidence_read_current_org
on reconciliation.issue_evidence
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on reconciliation.runs,
              reconciliation.run_checks,
              reconciliation.issues,
              reconciliation.issue_evidence
from anon, authenticated;

grant usage on schema reconciliation to authenticated, service_role;

grant select on reconciliation.runs,
                reconciliation.run_checks,
                reconciliation.issues,
                reconciliation.issue_evidence
to authenticated, service_role;

create or replace view api.reconciliation_runs
with (security_invoker = true)
as
select
  run.id as run_id,
  run.organization_id,
  run.run_no,
  run.run_type_code,
  run.trigger_code,
  run.status_code,
  run.scope,
  run.check_codes,
  run.rule_set_version,
  run.ledger_seq_from,
  run.ledger_seq_to,
  run.started_at,
  run.completed_at,
  run.actor_user_id,
  run.process_name,
  run.summary,
  run.error_code,
  run.metadata,
  run.created_at,
  run.updated_at
from reconciliation.runs run;

create or replace view api.reconciliation_checks
with (security_invoker = true)
as
select
  run_check.id as run_check_id,
  run_check.organization_id,
  run_check.run_id,
  run_check.check_code,
  run_check.rule_version,
  run_check.status_code,
  run_check.checked_count,
  run_check.issue_count,
  run_check.started_at,
  run_check.completed_at,
  run_check.summary,
  run_check.error_code,
  run_check.created_at,
  run_check.updated_at
from reconciliation.run_checks run_check;

create or replace view api.reconciliation_issues
with (security_invoker = true)
as
select
  issue.id as issue_id,
  issue.organization_id,
  issue.fingerprint,
  issue.check_code,
  issue.rule_version,
  issue.status_code,
  issue.severity_code,
  issue.entity_type_code,
  issue.entity_key,
  issue.product_id,
  issue.batch_id,
  issue.source_type_code,
  issue.source_ref,
  issue.expected_value,
  issue.actual_value,
  issue.difference_value,
  issue.first_seen_run_id,
  issue.last_seen_run_id,
  issue.first_seen_at,
  issue.last_seen_at,
  issue.recurrence_count,
  issue.resolved_at,
  issue.resolution_code,
  issue.resolution_note,
  issue.created_at,
  issue.updated_at
from reconciliation.issues issue;

create or replace view api.reconciliation_issue_evidence
with (security_invoker = true)
as
select
  evidence.id as evidence_id,
  evidence.organization_id,
  evidence.issue_id,
  evidence.run_id,
  evidence.run_check_id,
  evidence.evidence_no,
  evidence.evidence_type_code,
  evidence.entity_type_code,
  evidence.entity_key,
  evidence.expected_value,
  evidence.actual_value,
  evidence.difference_value,
  evidence.detail,
  evidence.created_at
from reconciliation.issue_evidence evidence;

revoke all on api.reconciliation_runs,
              api.reconciliation_checks,
              api.reconciliation_issues,
              api.reconciliation_issue_evidence
from anon;

grant select on api.reconciliation_runs,
                api.reconciliation_checks,
                api.reconciliation_issues,
                api.reconciliation_issue_evidence
to authenticated;

alter default privileges in schema reconciliation
revoke all on tables from anon, authenticated;

commit;