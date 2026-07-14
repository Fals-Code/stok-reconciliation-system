begin;

create or replace view api.stocktake_list
with (
  security_invoker = true,
  security_barrier = true
)
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
  coalesce(summary.line_count, 0)::bigint as line_count,
  coalesce(summary.counted_line_count, 0)::bigint as counted_line_count,
  case
    when stocktake.visibility_code = 'BLIND'
      and stocktake.status_code = 'COUNTING'
      then null::bigint
    else coalesce(summary.variance_line_count, 0)::bigint
  end as variance_line_count
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

revoke all on api.stocktake_list
from public, anon;

grant select on api.stocktake_list
to authenticated, service_role;

commit;