begin;

create or replace function reconciliation.find_duplicate_source_effects(
  p_organization_id uuid
)
returns table (
  organization_id uuid,
  violation_key text,
  detection_scope text,
  transaction_type_code text,
  source_type_code text,
  source_ref text,
  idempotency_command_id uuid,
  transaction_count bigint,
  command_count bigint,
  domain_effect_count bigint,
  ledger_entry_count bigint,
  absolute_quantity bigint,
  transaction_ids jsonb,
  command_ids jsonb,
  domain_effects jsonb,
  issue_code text
)
language sql
stable
security definer
set search_path = pg_catalog, inventory, operations
as $$
  with source_transactions as (
    select
      stock_transaction.organization_id,
      stock_transaction.id,
      stock_transaction.transaction_type_code,
      stock_transaction.source_type_code,
      stock_transaction.source_ref_snapshot,
      stock_transaction.idempotency_command_id
    from inventory.stock_transactions stock_transaction
    where stock_transaction.organization_id =
      p_organization_id
  ),
  duplicate_transaction_groups as (
    select
      source_transaction.organization_id,
      source_transaction.transaction_type_code,
      source_transaction.source_type_code,
      source_transaction.source_ref_snapshot,
      count(*)::bigint as transaction_count,
      count(
        distinct source_transaction.idempotency_command_id
      )::bigint as command_count,
      jsonb_agg(
        to_jsonb(source_transaction.id::text)
        order by source_transaction.id::text
      ) as transaction_ids,
      jsonb_agg(
        to_jsonb(
          source_transaction.idempotency_command_id::text
        )
        order by
          source_transaction.idempotency_command_id::text
      ) as command_ids
    from source_transactions source_transaction
    group by
      source_transaction.organization_id,
      source_transaction.transaction_type_code,
      source_transaction.source_type_code,
      source_transaction.source_ref_snapshot
    having count(*) > 1
  ),
  duplicate_transaction_ledger as (
    select
      duplicate_group.organization_id,
      duplicate_group.transaction_type_code,
      duplicate_group.source_type_code,
      duplicate_group.source_ref_snapshot,
      count(ledger_entry.id)::bigint
        as ledger_entry_count,
      coalesce(
        sum(abs(ledger_entry.quantity_delta)),
        0
      )::bigint as absolute_quantity
    from duplicate_transaction_groups duplicate_group
    join source_transactions source_transaction
      on source_transaction.organization_id =
          duplicate_group.organization_id
     and source_transaction.transaction_type_code =
          duplicate_group.transaction_type_code
     and source_transaction.source_type_code =
          duplicate_group.source_type_code
     and source_transaction.source_ref_snapshot =
          duplicate_group.source_ref_snapshot
    left join inventory.stock_ledger_entries ledger_entry
      on ledger_entry.organization_id =
          source_transaction.organization_id
     and ledger_entry.transaction_id =
          source_transaction.id
    group by
      duplicate_group.organization_id,
      duplicate_group.transaction_type_code,
      duplicate_group.source_type_code,
      duplicate_group.source_ref_snapshot
  ),
  domain_effects as (
    select
      receipt.organization_id,
      'RECEIPT'::text as domain_type_code,
      receipt.id as domain_effect_id,
      receipt.source_ref,
      receipt.transaction_id,
      receipt.idempotency_command_id
    from operations.receipts receipt
    where receipt.organization_id = p_organization_id

    union all

    select
      outbound.organization_id,
      'MANUAL_OUTBOUND'::text,
      outbound.id,
      outbound.source_ref,
      outbound.transaction_id,
      outbound.idempotency_command_id
    from operations.manual_outbounds outbound
    where outbound.organization_id = p_organization_id

    union all

    select
      marketplace_event.organization_id,
      'MARKETPLACE_EVENT'::text,
      marketplace_event.id,
      marketplace_event.external_event_ref,
      marketplace_event.transaction_id,
      marketplace_event.idempotency_command_id
    from operations.marketplace_events marketplace_event
    where marketplace_event.organization_id =
      p_organization_id

    union all

    select
      return_event.organization_id,
      'RETURN_EVENT'::text,
      return_event.id,
      return_event.external_event_ref,
      return_event.transaction_id,
      return_event.idempotency_command_id
    from operations.return_events return_event
    where return_event.organization_id = p_organization_id
  ),
  duplicate_command_groups as (
    select
      domain_effect.organization_id,
      domain_effect.idempotency_command_id,
      count(*)::bigint as domain_effect_count,
      count(
        distinct domain_effect.transaction_id
      ) filter (
        where domain_effect.transaction_id is not null
      )::bigint as transaction_count,
      jsonb_agg(
        jsonb_build_object(
          'domainType',
          domain_effect.domain_type_code,
          'domainEffectId',
          domain_effect.domain_effect_id,
          'sourceRef',
          domain_effect.source_ref,
          'transactionId',
          domain_effect.transaction_id
        )
        order by
          domain_effect.domain_type_code,
          domain_effect.source_ref,
          domain_effect.domain_effect_id
      ) as domain_effects
    from domain_effects domain_effect
    group by
      domain_effect.organization_id,
      domain_effect.idempotency_command_id
    having count(*) > 1
  ),
  duplicate_command_transactions as (
    select distinct
      duplicate_group.organization_id,
      duplicate_group.idempotency_command_id,
      domain_effect.transaction_id
    from duplicate_command_groups duplicate_group
    join domain_effects domain_effect
      on domain_effect.organization_id =
          duplicate_group.organization_id
     and domain_effect.idempotency_command_id =
          duplicate_group.idempotency_command_id
    where domain_effect.transaction_id is not null
  ),
  duplicate_command_ledger as (
    select
      duplicate_group.organization_id,
      duplicate_group.idempotency_command_id,
      count(ledger_entry.id)::bigint
        as ledger_entry_count,
      coalesce(
        sum(abs(ledger_entry.quantity_delta)),
        0
      )::bigint as absolute_quantity,
      coalesce(
        jsonb_agg(
          to_jsonb(command_transaction.transaction_id::text)
          order by command_transaction.transaction_id::text
        ) filter (
          where command_transaction.transaction_id is not null
        ),
        '[]'::jsonb
      ) as transaction_ids
    from duplicate_command_groups duplicate_group
    left join duplicate_command_transactions
      command_transaction
      on command_transaction.organization_id =
          duplicate_group.organization_id
     and command_transaction.idempotency_command_id =
          duplicate_group.idempotency_command_id
    left join inventory.stock_ledger_entries ledger_entry
      on ledger_entry.organization_id =
          command_transaction.organization_id
     and ledger_entry.transaction_id =
          command_transaction.transaction_id
    group by
      duplicate_group.organization_id,
      duplicate_group.idempotency_command_id
  )
  select
    duplicate_group.organization_id,
    duplicate_group.transaction_type_code
      || '|'
      || duplicate_group.source_type_code
      || '|'
      || duplicate_group.source_ref_snapshot
      as violation_key,
    'SOURCE_TRANSACTION'::text as detection_scope,
    duplicate_group.transaction_type_code,
    duplicate_group.source_type_code,
    duplicate_group.source_ref_snapshot as source_ref,
    null::uuid as idempotency_command_id,
    duplicate_group.transaction_count,
    duplicate_group.command_count,
    0::bigint as domain_effect_count,
    ledger_stats.ledger_entry_count,
    ledger_stats.absolute_quantity,
    duplicate_group.transaction_ids,
    duplicate_group.command_ids,
    '[]'::jsonb as domain_effects,
    'DUPLICATE_SOURCE_TRANSACTION'::text as issue_code
  from duplicate_transaction_groups duplicate_group
  join duplicate_transaction_ledger ledger_stats
    on ledger_stats.organization_id =
        duplicate_group.organization_id
   and ledger_stats.transaction_type_code =
        duplicate_group.transaction_type_code
   and ledger_stats.source_type_code =
        duplicate_group.source_type_code
   and ledger_stats.source_ref_snapshot =
        duplicate_group.source_ref_snapshot

  union all

  select
    duplicate_group.organization_id,
    duplicate_group.idempotency_command_id::text
      as violation_key,
    'COMMAND_DOMAIN'::text as detection_scope,
    null::text as transaction_type_code,
    null::text as source_type_code,
    null::text as source_ref,
    duplicate_group.idempotency_command_id,
    duplicate_group.transaction_count,
    1::bigint as command_count,
    duplicate_group.domain_effect_count,
    ledger_stats.ledger_entry_count,
    ledger_stats.absolute_quantity,
    ledger_stats.transaction_ids,
    jsonb_build_array(
      duplicate_group.idempotency_command_id::text
    ) as command_ids,
    duplicate_group.domain_effects,
    'DUPLICATE_COMMAND_DOMAIN_EFFECT'::text as issue_code
  from duplicate_command_groups duplicate_group
  join duplicate_command_ledger ledger_stats
    on ledger_stats.organization_id =
        duplicate_group.organization_id
   and ledger_stats.idempotency_command_id =
        duplicate_group.idempotency_command_id;
$$;

revoke all on function
  reconciliation.find_duplicate_source_effects(uuid)
from public, anon, authenticated, service_role;

commit;