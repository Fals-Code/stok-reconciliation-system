begin;

create or replace view api.stocktake_review_lines
with (
  security_invoker = true,
  security_barrier = true
)
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
  line.version_no,
  line.review_decision_code
from operations.stocktake_lines line
join operations.stocktakes stocktake
  on stocktake.organization_id = line.organization_id
 and stocktake.id = line.stocktake_id
where stocktake.visibility_code = 'NON_BLIND'
   or stocktake.status_code <> 'COUNTING';

revoke all on api.stocktake_review_lines
from public, anon;

grant select on api.stocktake_review_lines
to authenticated, service_role;

commit;