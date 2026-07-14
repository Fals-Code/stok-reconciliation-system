begin;

create schema if not exists operations;
revoke all on schema operations from public;

create table operations.stocktakes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references app.organizations(id) on delete restrict,
  stocktake_no text not null,
  title text not null,
  stocktake_type_code text not null,
  mode_code text not null,
  visibility_code text not null,
  status_code text not null default 'DRAFT',
  scope_definition jsonb not null,
  tolerance_policy_snapshot jsonb not null default
    '{"units": 0, "percent": 0}'::jsonb,
  rule_version text not null default 'stocktake-continuous-v1',
  timezone_snapshot text not null,
  planned_at timestamptz null,
  snapshot_ledger_seq bigint null,
  started_at timestamptz null,
  counting_completed_at timestamptz null,
  approved_at timestamptz null,
  posted_at timestamptz null,
  stock_transaction_id uuid null
    references inventory.stock_transactions(id) on delete restrict,
  reconciliation_run_id uuid null
    references reconciliation.runs(id) on delete restrict,
  created_by uuid null references auth.users(id) on delete set null,
  process_name text null,
  create_idempotency_command_id uuid not null
    references inventory.idempotency_commands(id) on delete restrict,
  note text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  version_no bigint not null default 1,

  constraint uq_stocktakes_org_id
    unique (organization_id, id),

  constraint uq_stocktakes_org_no
    unique (organization_id, stocktake_no),

  constraint uq_stocktakes_create_idempotency
    unique (create_idempotency_command_id),

  constraint ck_stocktakes_no_nonblank
    check (btrim(stocktake_no) <> ''),

  constraint ck_stocktakes_title_nonblank
    check (btrim(title) <> ''),

  constraint ck_stocktakes_type
    check (stocktake_type_code in ('FULL', 'CYCLE', 'AD_HOC')),

  constraint ck_stocktakes_mode
    check (mode_code = 'CONTINUOUS'),

  constraint ck_stocktakes_visibility
    check (visibility_code in ('BLIND', 'NON_BLIND')),

  constraint ck_stocktakes_status
    check (
      status_code in (
        'DRAFT',
        'READY',
        'COUNTING',
        'REVIEW',
        'APPROVED',
        'POSTING',
        'POSTED',
        'CANCELLED',
        'EXCEPTION'
      )
    ),

  constraint ck_stocktakes_scope_object
    check (jsonb_typeof(scope_definition) = 'object'),

  constraint ck_stocktakes_tolerance_object
    check (jsonb_typeof(tolerance_policy_snapshot) = 'object'),

  constraint ck_stocktakes_rule_nonblank
    check (btrim(rule_version) <> ''),

  constraint ck_stocktakes_timezone_nonblank
    check (btrim(timezone_snapshot) <> ''),

  constraint ck_stocktakes_snapshot_boundary
    check (snapshot_ledger_seq is null or snapshot_ledger_seq >= 0),

  constraint ck_stocktakes_actor_xor_process
    check ((created_by is not null) <> (process_name is not null)),

  constraint ck_stocktakes_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),

  constraint ck_stocktakes_note_length
    check (note is null or length(note) <= 2000),

  constraint ck_stocktakes_metadata_object
    check (jsonb_typeof(metadata) = 'object'),

  constraint ck_stocktakes_version_positive
    check (version_no > 0)
);

create table operations.stocktake_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  stocktake_id uuid not null,
  line_no integer not null,
  product_id uuid not null,
  batch_id uuid not null,
  bucket_code text not null,
  product_sku_snapshot text not null,
  product_name_snapshot text not null,
  batch_code_snapshot text not null,
  expiry_date_snapshot date not null,
  system_qty_at_snapshot bigint not null,
  final_attempt_id uuid null,
  final_physical_qty bigint null,
  expected_qty_at_count bigint null,
  variance_qty bigint null,
  count_cutoff_ledger_seq bigint null,
  expected_formula_version text null,
  count_attempt_no integer not null default 0,
  count_status_code text not null default 'PENDING',
  review_status_code text not null default 'PENDING',
  reason_code text null,
  review_note text null,
  exception_code text null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  version_no bigint not null default 1,

  constraint uq_stocktake_lines_org_stocktake_id
    unique (organization_id, stocktake_id, id),

  constraint fk_stocktake_lines_stocktake
    foreign key (organization_id, stocktake_id)
    references operations.stocktakes(organization_id, id)
    on delete restrict,

  constraint fk_stocktake_lines_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches(organization_id, product_id, id)
    on delete restrict,

  constraint uq_stocktake_lines_number
    unique (stocktake_id, line_no),

  constraint uq_stocktake_lines_entity
    unique (stocktake_id, product_id, batch_id, bucket_code),

  constraint ck_stocktake_lines_number_positive
    check (line_no > 0),

  constraint ck_stocktake_lines_bucket
    check (bucket_code in ('SELLABLE', 'QUARANTINE', 'DAMAGED')),

  constraint ck_stocktake_lines_sku_nonblank
    check (btrim(product_sku_snapshot) <> ''),

  constraint ck_stocktake_lines_product_name_nonblank
    check (btrim(product_name_snapshot) <> ''),

  constraint ck_stocktake_lines_batch_nonblank
    check (btrim(batch_code_snapshot) <> ''),

  constraint ck_stocktake_lines_final_physical_nonnegative
    check (final_physical_qty is null or final_physical_qty >= 0),

  constraint ck_stocktake_lines_cutoff_nonnegative
    check (
      count_cutoff_ledger_seq is null
      or count_cutoff_ledger_seq >= 0
    ),

  constraint ck_stocktake_lines_attempt_nonnegative
    check (count_attempt_no >= 0),

  constraint ck_stocktake_lines_count_status
    check (
      count_status_code in (
        'PENDING',
        'COUNTED',
        'RECOUNT_REQUESTED'
      )
    ),

  constraint ck_stocktake_lines_review_status
    check (
      review_status_code in (
        'PENDING',
        'READY',
        'REVIEWED'
      )
    ),

  constraint ck_stocktake_lines_expected_formula
    check (
      expected_formula_version is null
      or btrim(expected_formula_version) <> ''
    ),

  constraint ck_stocktake_lines_variance
    check (
      final_physical_qty is null
      or expected_qty_at_count is null
      or variance_qty = final_physical_qty - expected_qty_at_count
    ),

  constraint ck_stocktake_lines_final_attempt_payload
    check (
      final_attempt_id is null
      or (
        final_physical_qty is not null
        and expected_qty_at_count is not null
        and variance_qty is not null
        and count_cutoff_ledger_seq is not null
        and expected_formula_version is not null
        and count_attempt_no > 0
      )
    ),

  constraint ck_stocktake_lines_review_note_length
    check (review_note is null or length(review_note) <= 2000),

  constraint ck_stocktake_lines_version_positive
    check (version_no > 0)
);

create table operations.stocktake_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  stocktake_id uuid not null,
  stocktake_line_id uuid not null,
  product_id uuid not null,
  batch_id uuid not null,
  bucket_code text not null,
  snapshot_ledger_seq bigint not null,
  system_qty_at_snapshot bigint not null,
  product_sku_snapshot text not null,
  product_name_snapshot text not null,
  batch_code_snapshot text not null,
  expiry_date_snapshot date not null,
  created_at timestamptz not null default clock_timestamp(),

  constraint fk_stocktake_snapshots_stocktake
    foreign key (organization_id, stocktake_id)
    references operations.stocktakes(organization_id, id)
    on delete restrict,

  constraint fk_stocktake_snapshots_line
    foreign key (organization_id, stocktake_id, stocktake_line_id)
    references operations.stocktake_lines(
      organization_id,
      stocktake_id,
      id
    )
    on delete restrict,

  constraint fk_stocktake_snapshots_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches(organization_id, product_id, id)
    on delete restrict,

  constraint uq_stocktake_snapshots_line
    unique (stocktake_id, stocktake_line_id),

  constraint ck_stocktake_snapshots_bucket
    check (bucket_code in ('SELLABLE', 'QUARANTINE', 'DAMAGED')),

  constraint ck_stocktake_snapshots_boundary
    check (snapshot_ledger_seq >= 0),

  constraint ck_stocktake_snapshots_sku_nonblank
    check (btrim(product_sku_snapshot) <> ''),

  constraint ck_stocktake_snapshots_product_name_nonblank
    check (btrim(product_name_snapshot) <> ''),

  constraint ck_stocktake_snapshots_batch_nonblank
    check (btrim(batch_code_snapshot) <> '')
);

create table operations.stocktake_count_attempts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  stocktake_id uuid not null,
  stocktake_line_id uuid not null,
  attempt_no integer not null,
  physical_qty bigint not null,
  counted_at timestamptz not null,
  count_cutoff_ledger_seq bigint not null,
  expected_qty_at_count bigint not null,
  variance_qty bigint not null,
  expected_formula_version text not null,
  counted_by uuid null references auth.users(id) on delete set null,
  process_name text null,
  count_method_code text not null,
  zero_confirmed boolean not null default false,
  note text null,
  idempotency_key text not null,
  request_hash text not null,
  status_code text not null default 'VALID',
  created_at timestamptz not null default clock_timestamp(),

  constraint uq_stocktake_attempts_org_line_id
    unique (organization_id, stocktake_line_id, id),

  constraint fk_stocktake_attempts_stocktake
    foreign key (organization_id, stocktake_id)
    references operations.stocktakes(organization_id, id)
    on delete restrict,

  constraint fk_stocktake_attempts_line
    foreign key (organization_id, stocktake_id, stocktake_line_id)
    references operations.stocktake_lines(
      organization_id,
      stocktake_id,
      id
    )
    on delete restrict,

  constraint uq_stocktake_attempts_number
    unique (stocktake_line_id, attempt_no),

  constraint uq_stocktake_attempts_idempotency
    unique (organization_id, idempotency_key),

  constraint ck_stocktake_attempts_number_positive
    check (attempt_no > 0),

  constraint ck_stocktake_attempts_physical_nonnegative
    check (physical_qty >= 0),

  constraint ck_stocktake_attempts_zero_confirmation
    check (physical_qty <> 0 or zero_confirmed),

  constraint ck_stocktake_attempts_cutoff_nonnegative
    check (count_cutoff_ledger_seq >= 0),

  constraint ck_stocktake_attempts_variance
    check (variance_qty = physical_qty - expected_qty_at_count),

  constraint ck_stocktake_attempts_formula_nonblank
    check (btrim(expected_formula_version) <> ''),

  constraint ck_stocktake_attempts_actor_xor_process
    check ((counted_by is not null) <> (process_name is not null)),

  constraint ck_stocktake_attempts_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),

  constraint ck_stocktake_attempts_method
    check (
      count_method_code in (
        'MANUAL_ENTRY',
        'SCANNER',
        'IMPORT'
      )
    ),

  constraint ck_stocktake_attempts_note_length
    check (note is null or length(note) <= 2000),

  constraint ck_stocktake_attempts_idempotency_nonblank
    check (btrim(idempotency_key) <> ''),

  constraint ck_stocktake_attempts_hash
    check (request_hash ~ '^[0-9a-f]{64}$'),

  constraint ck_stocktake_attempts_status
    check (status_code = 'VALID')
);

alter table operations.stocktake_lines
add constraint fk_stocktake_lines_final_attempt
foreign key (organization_id, id, final_attempt_id)
references operations.stocktake_count_attempts(
  organization_id,
  stocktake_line_id,
  id
)
on delete restrict;

create index idx_stocktakes_org_status
on operations.stocktakes (
  organization_id,
  status_code,
  created_at desc,
  id
);

create index idx_stocktake_lines_session_status
on operations.stocktake_lines (
  stocktake_id,
  count_status_code,
  review_status_code,
  line_no
);

create index idx_stocktake_lines_entity
on operations.stocktake_lines (
  organization_id,
  product_id,
  batch_id,
  bucket_code
);

create index idx_stocktake_attempts_line
on operations.stocktake_count_attempts (
  stocktake_line_id,
  attempt_no desc,
  id
);

create trigger trg_stocktakes_touch_updated_at
before update on operations.stocktakes
for each row execute function app.touch_updated_at();

create trigger trg_stocktake_lines_touch_updated_at
before update on operations.stocktake_lines
for each row execute function app.touch_updated_at();

create trigger trg_stocktake_snapshots_immutable
before update or delete on operations.stocktake_snapshots
for each row execute function inventory.reject_immutable_mutation();

create trigger trg_stocktake_count_attempts_immutable
before update or delete on operations.stocktake_count_attempts
for each row execute function inventory.reject_immutable_mutation();

alter table operations.stocktakes enable row level security;
alter table operations.stocktake_lines enable row level security;
alter table operations.stocktake_snapshots enable row level security;
alter table operations.stocktake_count_attempts enable row level security;

create policy stocktakes_read_current_org
on operations.stocktakes
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stocktake_lines_read_current_org
on operations.stocktake_lines
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stocktake_snapshots_read_current_org
on operations.stocktake_snapshots
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stocktake_attempts_read_current_org
on operations.stocktake_count_attempts
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all
on operations.stocktakes,
   operations.stocktake_lines,
   operations.stocktake_snapshots,
   operations.stocktake_count_attempts
from public, anon, authenticated;

grant usage on schema operations to authenticated, service_role;

grant select
on operations.stocktakes,
   operations.stocktake_lines,
   operations.stocktake_snapshots,
   operations.stocktake_count_attempts
to authenticated, service_role;

create or replace view api.stocktake_list
with (security_invoker = true)
as
select
  stocktake.id as stocktake_id,
  stocktake.organization_id,
  stocktake.stocktake_no,
  stocktake.title,
  stocktake.stocktake_type_code,
  stocktake.mode_code,
  stocktake.visibility_code,
  stocktake.status_code,
  stocktake.planned_at,
  stocktake.snapshot_ledger_seq,
  stocktake.started_at,
  stocktake.counting_completed_at,
  stocktake.created_at,
  stocktake.updated_at,
  stocktake.version_no,
  coalesce(summary.line_count, 0) as line_count,
  coalesce(summary.counted_line_count, 0) as counted_line_count,
  coalesce(summary.variance_line_count, 0) as variance_line_count
from operations.stocktakes stocktake
left join lateral (
  select
    count(*) as line_count,
    count(*) filter (
      where line.count_status_code = 'COUNTED'
    ) as counted_line_count,
    count(*) filter (
      where line.variance_qty is not null
        and line.variance_qty <> 0
    ) as variance_line_count
  from operations.stocktake_lines line
  where line.organization_id = stocktake.organization_id
    and line.stocktake_id = stocktake.id
) summary on true;

create or replace view api.stocktake_details
with (security_invoker = true)
as
select
  stocktake.id as stocktake_id,
  stocktake.organization_id,
  stocktake.stocktake_no,
  stocktake.title,
  stocktake.stocktake_type_code,
  stocktake.mode_code,
  stocktake.visibility_code,
  stocktake.status_code,
  stocktake.scope_definition,
  stocktake.tolerance_policy_snapshot,
  stocktake.rule_version,
  stocktake.timezone_snapshot,
  stocktake.planned_at,
  stocktake.snapshot_ledger_seq,
  stocktake.started_at,
  stocktake.counting_completed_at,
  stocktake.approved_at,
  stocktake.posted_at,
  stocktake.stock_transaction_id,
  stocktake.reconciliation_run_id,
  stocktake.created_by,
  stocktake.process_name,
  stocktake.note,
  stocktake.metadata,
  stocktake.created_at,
  stocktake.updated_at,
  stocktake.version_no
from operations.stocktakes stocktake;

create or replace view api.stocktake_review_lines
with (security_invoker = true)
as
select
  line.id as stocktake_line_id,
  line.organization_id,
  line.stocktake_id,
  line.line_no,
  line.product_id,
  line.batch_id,
  line.bucket_code,
  line.product_sku_snapshot,
  line.product_name_snapshot,
  line.batch_code_snapshot,
  line.expiry_date_snapshot,
  line.system_qty_at_snapshot,
  line.final_attempt_id,
  line.final_physical_qty,
  line.expected_qty_at_count,
  line.variance_qty,
  line.count_cutoff_ledger_seq,
  line.expected_formula_version,
  line.count_attempt_no,
  line.count_status_code,
  line.review_status_code,
  line.reason_code,
  line.review_note,
  line.exception_code,
  line.created_at,
  line.updated_at,
  line.version_no
from operations.stocktake_lines line;

create or replace view api.stocktake_count_attempts
with (security_invoker = true)
as
select
  attempt.id as count_attempt_id,
  attempt.organization_id,
  attempt.stocktake_id,
  attempt.stocktake_line_id,
  attempt.attempt_no,
  attempt.physical_qty,
  attempt.counted_at,
  attempt.count_cutoff_ledger_seq,
  attempt.expected_qty_at_count,
  attempt.variance_qty,
  attempt.expected_formula_version,
  attempt.counted_by,
  attempt.process_name,
  attempt.count_method_code,
  attempt.zero_confirmed,
  attempt.note,
  attempt.idempotency_key,
  attempt.request_hash,
  attempt.status_code,
  attempt.created_at
from operations.stocktake_count_attempts attempt;

create or replace view api.stocktake_blind_lines
with (security_invoker = true)
as
select
  line.id as stocktake_line_id,
  line.organization_id,
  line.stocktake_id,
  line.line_no,
  line.product_id,
  line.batch_id,
  line.bucket_code,
  line.product_sku_snapshot,
  line.product_name_snapshot,
  line.batch_code_snapshot,
  line.expiry_date_snapshot,
  line.final_physical_qty,
  line.count_attempt_no,
  line.count_status_code,
  line.review_status_code,
  line.exception_code,
  line.created_at,
  line.updated_at,
  line.version_no
from operations.stocktake_lines line
join operations.stocktakes stocktake
  on stocktake.organization_id = line.organization_id
 and stocktake.id = line.stocktake_id
where stocktake.visibility_code = 'BLIND';

create or replace view api.stocktake_non_blind_lines
with (security_invoker = true)
as
select
  line.id as stocktake_line_id,
  line.organization_id,
  line.stocktake_id,
  line.line_no,
  line.product_id,
  line.batch_id,
  line.bucket_code,
  line.product_sku_snapshot,
  line.product_name_snapshot,
  line.batch_code_snapshot,
  line.expiry_date_snapshot,
  line.system_qty_at_snapshot,
  line.final_attempt_id,
  line.final_physical_qty,
  line.expected_qty_at_count,
  line.variance_qty,
  line.count_cutoff_ledger_seq,
  line.expected_formula_version,
  line.count_attempt_no,
  line.count_status_code,
  line.review_status_code,
  line.exception_code,
  line.created_at,
  line.updated_at,
  line.version_no
from operations.stocktake_lines line
join operations.stocktakes stocktake
  on stocktake.organization_id = line.organization_id
 and stocktake.id = line.stocktake_id
where stocktake.visibility_code = 'NON_BLIND';

grant usage on schema api to authenticated, service_role;

grant select
on api.stocktake_list,
   api.stocktake_details,
   api.stocktake_review_lines,
   api.stocktake_count_attempts,
   api.stocktake_blind_lines,
   api.stocktake_non_blind_lines
to authenticated, service_role;

commit;
