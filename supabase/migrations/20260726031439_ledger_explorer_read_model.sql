begin;

create index idx_stock_ledger_entries_org_seq
on inventory.stock_ledger_entries (organization_id, ledger_seq desc, id);

create index idx_stock_transactions_org_recorded
on inventory.stock_transactions (organization_id, recorded_at desc, id);

create or replace view api.ledger_explorer
with (
  security_invoker = true,
  security_barrier = true
)
as
select
  entry.ledger_seq,
  entry.id as ledger_entry_id,
  entry.organization_id,
  entry.transaction_id,
  transaction.transaction_no,
  transaction.transaction_type_code,
  transaction.reason_id,
  transaction.reason_code_snapshot,
  transaction.channel_id,
  transaction.channel_code_snapshot,
  transaction.source_type_code,
  transaction.source_id,
  transaction.source_ref_snapshot,
  entry.line_no,
  entry.product_id,
  entry.batch_id,
  entry.product_sku_snapshot,
  entry.batch_code_snapshot,
  entry.expiry_date_snapshot,
  entry.bucket_code,
  entry.quantity_delta,
  case
    when entry.quantity_delta > 0 then 'IN'
    else 'OUT'
  end as quantity_direction,
  entry.entry_role_code,
  entry.pair_no,
  entry.source_line_ref,
  entry.occurred_at,
  entry.recorded_at,
  transaction.actor_user_id,
  transaction.process_name,
  transaction.created_by_role_code,
  transaction.correlation_id,
  transaction.idempotency_command_id,
  transaction.reversal_of_transaction_id,
  transaction.note,
  transaction.metadata,
  case
    when transaction.reversal_of_transaction_id is not null then 'REVERSAL'
    when coalesce(reversal_summary.applied_quantity, 0) = 0 then 'NOT_REVERSED'
    when reversal_summary.applied_quantity >= abs(entry.quantity_delta)
      then 'FULLY_REVERSED'
    else 'PARTIALLY_REVERSED'
  end as reversal_state
from inventory.stock_ledger_entries entry
join inventory.stock_transactions transaction
  on transaction.id = entry.transaction_id
 and transaction.organization_id = entry.organization_id
left join lateral (
  select coalesce(sum(application.quantity_applied), 0)::bigint as applied_quantity
  from inventory.stock_reversal_applications application
  where application.organization_id = entry.organization_id
    and application.original_entry_id = entry.id
) reversal_summary on true;

create or replace view api.ledger_transaction_detail
with (
  security_invoker = true,
  security_barrier = true
)
as
select explorer.*
from api.ledger_explorer explorer;

create or replace view api.ledger_stock_story
with (
  security_invoker = true,
  security_barrier = true
)
as
select explorer.*
from api.ledger_explorer explorer;

create or replace view api.ledger_reversal_links
with (
  security_invoker = true,
  security_barrier = true
)
as
select
  application.id as reversal_application_id,
  application.organization_id,
  application.original_transaction_id,
  original_transaction.transaction_no as original_transaction_no,
  application.original_entry_id,
  application.reversal_transaction_id,
  reversal_transaction.transaction_no as reversal_transaction_no,
  application.reversal_entry_id,
  application.quantity_applied,
  application.created_at
from inventory.stock_reversal_applications application
join inventory.stock_transactions original_transaction
  on original_transaction.id = application.original_transaction_id
 and original_transaction.organization_id = application.organization_id
join inventory.stock_transactions reversal_transaction
  on reversal_transaction.id = application.reversal_transaction_id
 and reversal_transaction.organization_id = application.organization_id;

revoke all on api.ledger_explorer,
  api.ledger_transaction_detail,
  api.ledger_stock_story,
  api.ledger_reversal_links
from public, anon;

grant select on api.ledger_explorer,
  api.ledger_transaction_detail,
  api.ledger_stock_story,
  api.ledger_reversal_links
to authenticated, service_role;

commit;
