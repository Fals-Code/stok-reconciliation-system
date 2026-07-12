begin;

create table notification.rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete cascade,
  code text not null,
  version text not null,
  category_code text not null,
  trigger_mode_code text not null,
  entity_type_code text not null,
  severity_strategy_code text not null,
  stage_strategy_code text not null,
  condition_strategy_code text not null,
  resolution_strategy_code text not null,
  template_version text not null,
  action_code text not null,
  config jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_to timestamptz null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid null references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint uq_notification_rules_version unique (organization_id, code, version),
  constraint ck_notification_rules_code_nonblank check (btrim(code) <> ''),
  constraint ck_notification_rules_version_nonblank check (btrim(version) <> ''),
  constraint ck_notification_rules_effective_range check (
    effective_to is null or effective_to > effective_from
  )
);

create unique index uidx_notification_rules_active
on notification.rules (organization_id, code)
where effective_to is null and is_active;

create trigger trg_notification_rules_touch_updated_at
before update on notification.rules
for each row execute function app.touch_updated_at();

create or replace function app.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, app
as $$
  select profile.organization_id
  from app.user_profiles profile
  where profile.user_id = (select auth.uid())
    and profile.is_active
    and profile.role_code = 'ADMIN'
$$;

create or replace function app.is_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, app
as $$
  select exists (
    select 1
    from app.user_profiles profile
    where profile.user_id = (select auth.uid())
      and profile.is_active
      and profile.role_code = 'ADMIN'
  )
$$;

revoke all on function app.current_organization_id() from public;
revoke all on function app.is_admin() from public;
grant execute on function app.current_organization_id() to authenticated;
grant execute on function app.is_admin() to authenticated;

alter table app.organizations enable row level security;
alter table app.user_profiles enable row level security;
alter table app.settings enable row level security;
alter table catalog.channels enable row level security;
alter table catalog.movement_reasons enable row level security;
alter table catalog.products enable row level security;
alter table catalog.product_batches enable row level security;
alter table catalog.bundle_recipes enable row level security;
alter table catalog.bundle_components enable row level security;
alter table inventory.idempotency_commands enable row level security;
alter table inventory.stock_transactions enable row level security;
alter table inventory.stock_ledger_entries enable row level security;
alter table inventory.stock_batch_balances enable row level security;
alter table inventory.stock_product_positions enable row level security;
alter table inventory.stock_reservations enable row level security;
alter table notification.rules enable row level security;

create policy organizations_read_current
on app.organizations
for select
to authenticated
using (id = (select app.current_organization_id()));

create policy user_profiles_read_self
on app.user_profiles
for select
to authenticated
using (user_id = (select auth.uid()));

create policy settings_read_current_org
on app.settings
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy channels_read_authenticated
on catalog.channels
for select
to authenticated
using ((select auth.uid()) is not null and is_active);

create policy movement_reasons_read_authenticated
on catalog.movement_reasons
for select
to authenticated
using ((select auth.uid()) is not null and is_active);

create policy products_read_current_org
on catalog.products
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy product_batches_read_current_org
on catalog.product_batches
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy bundle_recipes_read_current_org
on catalog.bundle_recipes
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy bundle_components_read_current_org
on catalog.bundle_components
for select
to authenticated
using (
  exists (
    select 1
    from catalog.bundle_recipes recipe
    where recipe.id = bundle_components.bundle_recipe_id
      and recipe.organization_id = (select app.current_organization_id())
  )
);

create policy idempotency_commands_read_current_org
on inventory.idempotency_commands
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stock_transactions_read_current_org
on inventory.stock_transactions
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stock_ledger_entries_read_current_org
on inventory.stock_ledger_entries
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stock_batch_balances_read_current_org
on inventory.stock_batch_balances
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stock_product_positions_read_current_org
on inventory.stock_product_positions
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy stock_reservations_read_current_org
on inventory.stock_reservations
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

create policy notification_rules_read_current_org
on notification.rules
for select
to authenticated
using (organization_id = (select app.current_organization_id()));

revoke all on all tables in schema app, catalog, inventory, notification from anon;
revoke all on all tables in schema app, catalog, inventory, notification from authenticated;

revoke insert, update, delete, truncate
on inventory.stock_transactions,
   inventory.stock_ledger_entries,
   inventory.stock_batch_balances,
   inventory.stock_product_positions
from anon, authenticated;

grant usage on schema app, catalog, inventory, notification to authenticated;

grant select on app.organizations, app.user_profiles, app.settings to authenticated;
grant select on catalog.channels,
                catalog.movement_reasons,
                catalog.products,
                catalog.product_batches,
                catalog.bundle_recipes,
                catalog.bundle_components
to authenticated;
grant select on inventory.idempotency_commands,
                inventory.stock_transactions,
                inventory.stock_ledger_entries,
                inventory.stock_batch_balances,
                inventory.stock_product_positions,
                inventory.stock_reservations
to authenticated;
grant select on notification.rules to authenticated;

create or replace view api.product_inventory
with (security_invoker = true)
as
select
  product.id as product_id,
  product.organization_id,
  product.sku,
  product.name,
  product.unit_code,
  product.is_active,
  coalesce(position.sellable_qty, 0) as sellable_qty,
  coalesce(position.quarantine_qty, 0) as quarantine_qty,
  coalesce(position.damaged_qty, 0) as damaged_qty,
  coalesce(position.reserved_qty, 0) as reserved_qty,
  coalesce(position.sellable_qty, 0) - coalesce(position.reserved_qty, 0) as available_qty,
  coalesce(position.last_ledger_seq, 0) as last_ledger_seq,
  position.updated_at as stock_updated_at
from catalog.products product
left join inventory.stock_product_positions position
  on position.organization_id = product.organization_id
 and position.product_id = product.id;

create or replace view api.batch_inventory
with (security_invoker = true)
as
select
  batch.id as batch_id,
  batch.organization_id,
  batch.product_id,
  product.sku,
  product.name as product_name,
  batch.batch_code,
  batch.expiry_date,
  batch.received_first_at,
  batch.status_code,
  coalesce(balance.sellable_qty, 0) as sellable_qty,
  coalesce(balance.quarantine_qty, 0) as quarantine_qty,
  coalesce(balance.damaged_qty, 0) as damaged_qty,
  coalesce(balance.last_ledger_seq, 0) as last_ledger_seq,
  balance.updated_at as stock_updated_at
from catalog.product_batches batch
join catalog.products product
  on product.organization_id = batch.organization_id
 and product.id = batch.product_id
left join inventory.stock_batch_balances balance
  on balance.organization_id = batch.organization_id
 and balance.batch_id = batch.id;

create or replace view api.stock_ledger
with (security_invoker = true)
as
select
  entry.ledger_seq,
  entry.id as ledger_entry_id,
  entry.organization_id,
  entry.transaction_id,
  transaction.transaction_no,
  transaction.transaction_type_code,
  transaction.reason_code_snapshot,
  transaction.channel_code_snapshot,
  transaction.source_type_code,
  transaction.source_ref_snapshot,
  entry.line_no,
  entry.product_id,
  entry.batch_id,
  entry.product_sku_snapshot,
  entry.batch_code_snapshot,
  entry.expiry_date_snapshot,
  entry.bucket_code,
  entry.quantity_delta,
  entry.entry_role_code,
  entry.source_line_ref,
  entry.occurred_at,
  entry.recorded_at,
  transaction.note,
  transaction.correlation_id
from inventory.stock_ledger_entries entry
join inventory.stock_transactions transaction
  on transaction.id = entry.transaction_id
 and transaction.organization_id = entry.organization_id;

revoke all on schema api from public;
grant usage on schema api to authenticated;
revoke all on api.product_inventory, api.batch_inventory, api.stock_ledger from anon;
grant select on api.product_inventory, api.batch_inventory, api.stock_ledger to authenticated;

alter default privileges in schema app revoke all on tables from anon, authenticated;
alter default privileges in schema catalog revoke all on tables from anon, authenticated;
alter default privileges in schema inventory revoke all on tables from anon, authenticated;
alter default privileges in schema notification revoke all on tables from anon, authenticated;
alter default privileges in schema api revoke all on tables from anon, authenticated;

commit;
