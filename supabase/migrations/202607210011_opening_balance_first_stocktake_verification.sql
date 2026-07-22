begin;

alter table operations.opening_balance_cutover_lines
add constraint uq_opening_balance_cutover_lines_org_cutover_id
unique (organization_id, cutover_id, id);

alter table operations.stocktake_posting_lines
add constraint uq_stocktake_posting_lines_org_stocktake_posting_id
unique (organization_id, stocktake_id, posting_id, id);

create table operations.opening_balance_verification_applications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  opening_balance_cutover_id uuid not null,
  opening_balance_line_id uuid not null,
  stocktake_id uuid not null,
  stocktake_approval_id uuid not null,
  approval_version_no bigint not null,
  stocktake_posting_id uuid not null,
  stocktake_posting_line_id uuid not null,
  stocktake_line_id uuid not null,
  count_attempt_id uuid not null,
  product_id uuid not null,
  batch_id uuid not null,
  bucket_code text not null,
  opening_balance_quantity bigint not null,
  physical_quantity bigint not null,
  stocktake_variance_quantity bigint not null,
  count_cutoff_ledger_seq bigint not null,
  opening_balance_ledger_seq_after bigint not null,
  verified_at timestamptz not null,
  verified_by uuid null references auth.users(id) on delete set null,
  process_name text null,
  verification_rule_version text not null default
    'opening-balance-first-stocktake-v1',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),

  constraint uq_opening_balance_verification_org_id
    unique (organization_id, id),

  constraint fk_opening_balance_verification_cutover
    foreign key (organization_id, opening_balance_cutover_id)
    references operations.opening_balance_cutovers(organization_id, id)
    on delete restrict,

  constraint fk_opening_balance_verification_line
    foreign key (
      organization_id,
      opening_balance_cutover_id,
      opening_balance_line_id
    )
    references operations.opening_balance_cutover_lines(
      organization_id,
      cutover_id,
      id
    )
    on delete restrict,

  constraint fk_opening_balance_verification_stocktake
    foreign key (organization_id, stocktake_id)
    references operations.stocktakes(organization_id, id)
    on delete restrict,

  constraint fk_opening_balance_verification_approval
    foreign key (
      organization_id,
      stocktake_id,
      stocktake_approval_id
    )
    references operations.stocktake_approvals(
      organization_id,
      stocktake_id,
      id
    )
    on delete restrict,

  constraint fk_opening_balance_verification_posting
    foreign key (
      organization_id,
      stocktake_id,
      stocktake_posting_id
    )
    references operations.stocktake_postings(
      organization_id,
      stocktake_id,
      id
    )
    on delete restrict,

  constraint fk_opening_balance_verification_posting_line
    foreign key (
      organization_id,
      stocktake_id,
      stocktake_posting_id,
      stocktake_posting_line_id
    )
    references operations.stocktake_posting_lines(
      organization_id,
      stocktake_id,
      posting_id,
      id
    )
    on delete restrict,

  constraint fk_opening_balance_verification_stocktake_line
    foreign key (organization_id, stocktake_id, stocktake_line_id)
    references operations.stocktake_lines(
      organization_id,
      stocktake_id,
      id
    )
    on delete restrict,

  constraint fk_opening_balance_verification_count_attempt
    foreign key (organization_id, stocktake_line_id, count_attempt_id)
    references operations.stocktake_count_attempts(
      organization_id,
      stocktake_line_id,
      id
    )
    on delete restrict,

  constraint fk_opening_balance_verification_batch
    foreign key (organization_id, product_id, batch_id)
    references catalog.product_batches(organization_id, product_id, id)
    on delete restrict,

  constraint uq_opening_balance_verification_first_line
    unique (opening_balance_line_id),

  constraint uq_opening_balance_verification_posting_line
    unique (stocktake_posting_line_id),

  constraint ck_opening_balance_verification_approval_version
    check (approval_version_no > 0),

  constraint ck_opening_balance_verification_bucket
    check (bucket_code in ('SELLABLE', 'QUARANTINE', 'DAMAGED')),

  constraint ck_opening_balance_verification_opening_quantity
    check (opening_balance_quantity > 0),

  constraint ck_opening_balance_verification_physical_quantity
    check (physical_quantity >= 0),

  constraint ck_opening_balance_verification_ledger_boundary
    check (
      opening_balance_ledger_seq_after >= 0
      and count_cutoff_ledger_seq >= opening_balance_ledger_seq_after
    ),

  constraint ck_opening_balance_verification_actor
    check ((verified_by is not null) <> (process_name is not null)),

  constraint ck_opening_balance_verification_process_nonblank
    check (process_name is null or btrim(process_name) <> ''),

  constraint ck_opening_balance_verification_rule_nonblank
    check (btrim(verification_rule_version) <> ''),

  constraint ck_opening_balance_verification_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create index idx_opening_balance_verification_cutover
on operations.opening_balance_verification_applications (
  organization_id,
  opening_balance_cutover_id,
  verified_at,
  opening_balance_line_id
);

create index idx_opening_balance_verification_stocktake
on operations.opening_balance_verification_applications (
  organization_id,
  stocktake_id,
  stocktake_posting_id,
  stocktake_posting_line_id
);

create index idx_opening_balance_verification_scope
on operations.opening_balance_verification_applications (
  organization_id,
  product_id,
  batch_id,
  bucket_code,
  verified_at
);

create trigger trg_opening_balance_verification_immutable
before update or delete
on operations.opening_balance_verification_applications
for each row execute function inventory.reject_immutable_mutation();

alter table operations.opening_balance_verification_applications
  enable row level security;

create policy opening_balance_verification_read_current_org
on operations.opening_balance_verification_applications
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all
on operations.opening_balance_verification_applications
from public, anon, authenticated;

grant select
on operations.opening_balance_verification_applications
to authenticated, service_role;

create or replace function inventory.apply_opening_balance_first_verification()
returns trigger
language plpgsql
security definer
set search_path =
  pg_catalog,
  auth,
  app,
  catalog,
  inventory,
  operations
as $$
declare
  v_posting operations.stocktake_postings%rowtype;
  v_approval operations.stocktake_approvals%rowtype;
  v_approval_line operations.stocktake_approval_lines%rowtype;
  v_stocktake_line operations.stocktake_lines%rowtype;
  v_count_attempt operations.stocktake_count_attempts%rowtype;
  v_cutover_id uuid;
  v_opening_balance_line_id uuid;
  v_opening_balance_quantity bigint;
  v_opening_balance_ledger_seq_after bigint;
  v_cutover_posted_at timestamptz;
begin
  select
    cutover.id,
    line.id,
    line.quantity,
    cutover.ledger_seq_after,
    cutover.posted_at
  into
    v_cutover_id,
    v_opening_balance_line_id,
    v_opening_balance_quantity,
    v_opening_balance_ledger_seq_after,
    v_cutover_posted_at
  from operations.opening_balance_cutover_lines line
  join operations.opening_balance_cutovers cutover
    on cutover.organization_id = line.organization_id
   and cutover.id = line.cutover_id
  where line.organization_id = new.organization_id
    and line.product_id = new.product_id
    and line.batch_id = new.batch_id
    and line.bucket_code = new.bucket_code
    and line.quantity > 0
    and line.ledger_entry_id is not null
    and cutover.status_code = 'POSTED'
    and cutover.posted_at is not null
    and cutover.ledger_seq_after is not null
    and not exists (
      select 1
      from operations.opening_balance_verification_applications application
      where application.opening_balance_line_id = line.id
    )
  order by cutover.posted_at, line.line_no
  limit 1;

  if not found then
    return new;
  end if;

  select posting.*
  into v_posting
  from operations.stocktake_postings posting
  where posting.organization_id = new.organization_id
    and posting.stocktake_id = new.stocktake_id
    and posting.id = new.posting_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_POSTING_NOT_FOUND';
  end if;

  select approval.*
  into v_approval
  from operations.stocktake_approvals approval
  where approval.organization_id = new.organization_id
    and approval.stocktake_id = new.stocktake_id
    and approval.id = v_posting.approval_id
    and approval.approval_version_no = v_posting.approval_version_no;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_APPROVAL_INVALID';
  end if;

  select approval_line.*
  into v_approval_line
  from operations.stocktake_approval_lines approval_line
  where approval_line.organization_id = new.organization_id
    and approval_line.stocktake_id = new.stocktake_id
    and approval_line.approval_id = v_posting.approval_id
    and approval_line.id = new.approval_line_id
    and approval_line.stocktake_line_id = new.stocktake_line_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_APPROVAL_LINE_INVALID';
  end if;

  select line.*
  into v_stocktake_line
  from operations.stocktake_lines line
  where line.organization_id = new.organization_id
    and line.stocktake_id = new.stocktake_id
    and line.id = new.stocktake_line_id
    and line.product_id = new.product_id
    and line.batch_id = new.batch_id
    and line.bucket_code = new.bucket_code;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_STOCKTAKE_LINE_INVALID';
  end if;

  if new.line_no <> v_approval_line.line_no
     or new.adjustment_qty <> v_approval_line.variance_qty
     or v_stocktake_line.final_attempt_id is distinct from
        v_approval_line.final_attempt_id
     or v_stocktake_line.final_physical_qty is distinct from
        v_approval_line.final_physical_qty
     or v_stocktake_line.expected_qty_at_count is distinct from
        v_approval_line.expected_qty_at_count
     or v_stocktake_line.count_cutoff_ledger_seq is distinct from
        v_approval_line.count_cutoff_ledger_seq then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_POSTING_LINE_INVALID';
  end if;

  select attempt.*
  into v_count_attempt
  from operations.stocktake_count_attempts attempt
  where attempt.organization_id = new.organization_id
    and attempt.stocktake_id = new.stocktake_id
    and attempt.stocktake_line_id = new.stocktake_line_id
    and attempt.id = v_approval_line.final_attempt_id
    and attempt.status_code = 'VALID';

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_COUNT_EVIDENCE_INVALID';
  end if;

  if v_count_attempt.physical_qty <> v_approval_line.final_physical_qty
     or v_count_attempt.expected_qty_at_count <>
        v_approval_line.expected_qty_at_count
     or v_count_attempt.variance_qty <> v_approval_line.variance_qty
     or v_count_attempt.count_cutoff_ledger_seq <>
        v_approval_line.count_cutoff_ledger_seq then
    raise exception using
      errcode = 'P0001',
      message = 'OPENING_BALANCE_VERIFICATION_COUNT_EVIDENCE_INVALID';
  end if;

  if v_count_attempt.counted_at < v_cutover_posted_at
     or v_count_attempt.count_cutoff_ledger_seq <
        v_opening_balance_ledger_seq_after
     or v_posting.posting_ledger_seq_before <
        v_opening_balance_ledger_seq_after then
    return new;
  end if;

  perform line.id
  from operations.opening_balance_cutover_lines line
  where line.organization_id = new.organization_id
    and line.id = v_opening_balance_line_id
    and not exists (
      select 1
      from operations.opening_balance_verification_applications application
      where application.opening_balance_line_id = line.id
    )
  for update of line;

  if not found then
    return new;
  end if;

  insert into operations.opening_balance_verification_applications (
    organization_id,
    opening_balance_cutover_id,
    opening_balance_line_id,
    stocktake_id,
    stocktake_approval_id,
    approval_version_no,
    stocktake_posting_id,
    stocktake_posting_line_id,
    stocktake_line_id,
    count_attempt_id,
    product_id,
    batch_id,
    bucket_code,
    opening_balance_quantity,
    physical_quantity,
    stocktake_variance_quantity,
    count_cutoff_ledger_seq,
    opening_balance_ledger_seq_after,
    verified_at,
    verified_by,
    process_name,
    verification_rule_version,
    metadata,
    created_at
  ) values (
    new.organization_id,
    v_cutover_id,
    v_opening_balance_line_id,
    new.stocktake_id,
    v_posting.approval_id,
    v_posting.approval_version_no,
    new.posting_id,
    new.id,
    new.stocktake_line_id,
    v_count_attempt.id,
    new.product_id,
    new.batch_id,
    new.bucket_code,
    v_opening_balance_quantity,
    v_count_attempt.physical_qty,
    v_approval_line.variance_qty,
    v_count_attempt.count_cutoff_ledger_seq,
    v_opening_balance_ledger_seq_after,
    v_posting.posted_at,
    v_posting.posted_by,
    v_posting.process_name,
    'opening-balance-first-stocktake-v1',
    jsonb_build_object(
      'source', 'STOCKTAKE_POSTING',
      'stocktakePostingLineId', new.id,
      'countedAt', v_count_attempt.counted_at,
      'cutoverPostedAt', v_cutover_posted_at
    ),
    clock_timestamp()
  )
  on conflict (opening_balance_line_id) do nothing;

  return new;
end;
$$;

revoke all
on function inventory.apply_opening_balance_first_verification()
from public, anon, authenticated, service_role;

create trigger trg_stocktake_posting_lines_opening_balance_verification
after insert
on operations.stocktake_posting_lines
for each row execute function inventory.apply_opening_balance_first_verification();

create or replace view api.opening_balance_cutovers
with (security_invoker = true, security_barrier = true)
as
select
  cutover.id as cutover_id,
  cutover.organization_id,
  cutover.cutover_no,
  cutover.source_ref,
  cutover.source_estimate_ref,
  cutover.status_code,
  cutover.cutover_at,
  cutover.effective_local_date,
  cutover.created_at,
  cutover.updated_at,
  cutover.created_by,
  cutover.create_process_name,
  cutover.reviewed_at,
  cutover.reviewed_by,
  cutover.review_process_name,
  cutover.posted_at,
  cutover.posted_by,
  cutover.post_process_name,
  cutover.transaction_id,
  cutover.request_hash,
  cutover.posted_basis_hash,
  cutover.ledger_seq_before,
  cutover.ledger_seq_after,
  cutover.line_count,
  cutover.positive_line_count,
  cutover.total_quantity,
  cutover.note,
  cutover.metadata,
  cutover.row_version,
  case
    when cutover.status_code <> 'POSTED' then 'PENDING_POST'
    when cutover.positive_line_count = 0 then 'NOT_APPLICABLE'
    when verification.verified_line_count = 0 then 'UNVERIFIED'
    when verification.verified_line_count < cutover.positive_line_count
      then 'PARTIALLY_VERIFIED'
    else 'VERIFIED'
  end as verification_status_code,
  verification.verified_line_count,
  case
    when cutover.status_code = 'POSTED' then
      greatest(
        cutover.positive_line_count - verification.verified_line_count,
        0
      )
    else 0
  end as unverified_line_count
from operations.opening_balance_cutovers cutover
cross join lateral (
  select count(*)::bigint as verified_line_count
  from operations.opening_balance_verification_applications application
  where application.organization_id = cutover.organization_id
    and application.opening_balance_cutover_id = cutover.id
) verification;

create or replace view api.opening_balance_cutover_lines
with (security_invoker = true, security_barrier = true)
as
select
  line.id as opening_balance_line_id,
  line.organization_id,
  line.cutover_id,
  line.line_no,
  line.product_id,
  line.batch_id,
  line.bucket_code,
  line.quantity,
  line.batch_identity_verified,
  line.exception_reference,
  line.product_sku_snapshot,
  line.product_name_snapshot,
  line.batch_code_snapshot,
  line.expiry_date_snapshot,
  line.batch_status_code_snapshot,
  line.product_row_version_snapshot,
  line.batch_row_version_snapshot,
  line.source_line_ref,
  line.ledger_entry_id,
  line.batch_bucket_qty_before,
  line.batch_bucket_qty_after,
  line.product_bucket_qty_before,
  line.product_bucket_qty_after,
  line.created_at,
  line.updated_at,
  case
    when cutover.status_code <> 'POSTED' then 'PENDING_POST'
    when line.quantity = 0 then 'NOT_APPLICABLE'
    when application.id is not null then 'VERIFIED'
    else 'UNVERIFIED'
  end as verification_status_code,
  application.id as verification_application_id,
  application.stocktake_id as verifying_stocktake_id,
  application.stocktake_approval_id as verifying_stocktake_approval_id,
  application.approval_version_no as verifying_approval_version_no,
  application.stocktake_posting_id as verifying_stocktake_posting_id,
  application.stocktake_posting_line_id as verifying_stocktake_posting_line_id,
  application.stocktake_line_id as verifying_stocktake_line_id,
  application.count_attempt_id as verifying_count_attempt_id,
  application.physical_quantity as verifying_physical_quantity,
  application.stocktake_variance_quantity as verifying_variance_quantity,
  application.verified_at,
  count_attempt.counted_at as verifying_counted_at,
  posting_line.ledger_entry_id as verifying_adjustment_ledger_entry_id,
  stocktake.stocktake_no as verifying_stocktake_no
from operations.opening_balance_cutover_lines line
join operations.opening_balance_cutovers cutover
  on cutover.organization_id = line.organization_id
 and cutover.id = line.cutover_id
left join operations.opening_balance_verification_applications application
  on application.organization_id = line.organization_id
 and application.opening_balance_line_id = line.id
left join operations.stocktake_count_attempts count_attempt
  on count_attempt.organization_id = application.organization_id
 and count_attempt.stocktake_line_id = application.stocktake_line_id
 and count_attempt.id = application.count_attempt_id
left join operations.stocktake_posting_lines posting_line
  on posting_line.id = application.stocktake_posting_line_id
left join operations.stocktakes stocktake
  on stocktake.organization_id = application.organization_id
 and stocktake.id = application.stocktake_id;

create or replace view api.opening_balance_verification_applications
with (security_invoker = true, security_barrier = true)
as
select
  application.id as verification_application_id,
  application.organization_id,
  application.opening_balance_cutover_id,
  application.opening_balance_line_id,
  application.stocktake_id,
  stocktake.stocktake_no,
  application.stocktake_approval_id,
  application.approval_version_no,
  application.stocktake_posting_id,
  application.stocktake_posting_line_id,
  application.stocktake_line_id,
  application.count_attempt_id,
  application.product_id,
  application.batch_id,
  application.bucket_code,
  application.opening_balance_quantity,
  application.physical_quantity,
  application.stocktake_variance_quantity,
  application.count_cutoff_ledger_seq,
  application.opening_balance_ledger_seq_after,
  application.verified_at,
  application.verified_by,
  application.process_name,
  application.verification_rule_version,
  application.metadata,
  application.created_at,
  approval.approved_at,
  posting.posted_at as stocktake_posted_at,
  posting_line.ledger_entry_id as stocktake_adjustment_ledger_entry_id,
  count_attempt.counted_at,
  count_attempt.counted_by,
  count_attempt.process_name as count_process_name,
  count_attempt.count_method_code,
  count_attempt.zero_confirmed
from operations.opening_balance_verification_applications application
join operations.stocktakes stocktake
  on stocktake.organization_id = application.organization_id
 and stocktake.id = application.stocktake_id
join operations.stocktake_approvals approval
  on approval.organization_id = application.organization_id
 and approval.stocktake_id = application.stocktake_id
 and approval.id = application.stocktake_approval_id
join operations.stocktake_postings posting
  on posting.organization_id = application.organization_id
 and posting.stocktake_id = application.stocktake_id
 and posting.id = application.stocktake_posting_id
join operations.stocktake_posting_lines posting_line
  on posting_line.id = application.stocktake_posting_line_id
join operations.stocktake_count_attempts count_attempt
  on count_attempt.organization_id = application.organization_id
 and count_attempt.stocktake_line_id = application.stocktake_line_id
 and count_attempt.id = application.count_attempt_id;

revoke all
on api.opening_balance_cutovers,
   api.opening_balance_cutover_lines,
   api.opening_balance_verification_applications
from public, anon;

grant select
on api.opening_balance_cutovers,
   api.opening_balance_cutover_lines,
   api.opening_balance_verification_applications
to authenticated, service_role;

comment on table operations.opening_balance_verification_applications
is 'Immutable first-stocktake evidence linking one positive opening-balance line to the first qualifying posted physical count for the exact organization, product, batch, and bucket.';

comment on function inventory.apply_opening_balance_first_verification()
is 'Internal AFTER INSERT stocktake-posting hook. It creates no stock movement and records one immutable first-verification application when count evidence is after the posted opening-balance basis.';

comment on view api.opening_balance_verification_applications
is 'Organization-scoped drill-down for the first stocktake evidence that verified each positive opening-balance line.';

commit;
