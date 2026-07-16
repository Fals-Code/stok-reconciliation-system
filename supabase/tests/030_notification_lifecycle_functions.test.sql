begin;

create extension if not exists pgtap with schema extensions;

select plan(64);

-- 1-8: function contract
select has_function(
  'notification'::name,
  'append_notification_event'::name,
  array[
    'uuid',
    'uuid',
    'text',
    'timestamp with time zone',
    'uuid',
    'jsonb',
    'text',
    'text',
    'text',
    'text',
    'text',
    'text',
    'text',
    'uuid',
    'text'
  ]::text[]
);

select has_function(
  'notification'::name,
  'reset_user_read_states'::name,
  array['uuid', 'uuid', 'uuid', 'text']::text[]
);

select has_function(
  'notification'::name,
  'upsert_active_notification'::name,
  array[
    'uuid',
    'uuid',
    'uuid',
    'text',
    'text',
    'text',
    'text',
    'text',
    'text',
    'timestamp with time zone',
    'timestamp with time zone',
    'timestamp with time zone',
    'jsonb',
    'text',
    'uuid',
    'uuid',
    'text'
  ]::text[]
);

select has_function(
  'notification'::name,
  'resolve_notification'::name,
  array[
    'uuid',
    'uuid',
    'text',
    'jsonb',
    'timestamp with time zone',
    'uuid',
    'text',
    'uuid',
    'text'
  ]::text[]
);

select function_returns(
  'notification',
  'append_notification_event',
  array[
    'uuid',
    'uuid',
    'text',
    'timestamptz',
    'uuid',
    'jsonb',
    'text',
    'text',
    'text',
    'text',
    'text',
    'text',
    'text',
    'uuid',
    'text'
  ]::text[],
  'uuid'
);

select function_returns(
  'notification',
  'reset_user_read_states',
  array['uuid', 'uuid', 'uuid', 'text']::text[],
  'integer'
);

select function_returns(
  'notification',
  'upsert_active_notification',
  array[
    'uuid',
    'uuid',
    'uuid',
    'text',
    'text',
    'text',
    'text',
    'text',
    'text',
    'timestamptz',
    'timestamptz',
    'timestamptz',
    'jsonb',
    'text',
    'uuid',
    'uuid',
    'text'
  ]::text[],
  'jsonb'
);

select function_returns(
  'notification',
  'resolve_notification',
  array[
    'uuid',
    'uuid',
    'text',
    'jsonb',
    'timestamptz',
    'uuid',
    'text',
    'uuid',
    'text'
  ]::text[],
  'jsonb'
);

-- 9-16: minimum execute privileges
select ok(
  has_function_privilege(
    'service_role',
    'notification.append_notification_event(uuid,uuid,text,timestamptz,uuid,jsonb,text,text,text,text,text,text,text,uuid,text)',
    'EXECUTE'
  ),
  'service role may append notification events'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.append_notification_event(uuid,uuid,text,timestamptz,uuid,jsonb,text,text,text,text,text,text,text,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot append notification events'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.reset_user_read_states(uuid,uuid,uuid,text)',
    'EXECUTE'
  ),
  'service role may reset per-user notification state'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.reset_user_read_states(uuid,uuid,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot reset per-user notification state'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.upsert_active_notification(uuid,uuid,uuid,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb,text,uuid,uuid,text)',
    'EXECUTE'
  ),
  'service role may upsert active notification episodes'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.upsert_active_notification(uuid,uuid,uuid,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb,text,uuid,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot upsert notification episodes'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.resolve_notification(uuid,uuid,text,jsonb,timestamptz,uuid,text,uuid,text)',
    'EXECUTE'
  ),
  'service role may resolve notification episodes'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.resolve_notification(uuid,uuid,text,jsonb,timestamptz,uuid,text,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot resolve notification episodes'
);

-- Test users and an isolated organization/rule
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
)
values
(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94100000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.lifecycle.one@glowlab.invalid',
  '2026-07-16 20:15:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 20:15:00+07'::timestamptz,
  '2026-07-16 20:15:00+07'::timestamptz,
  false,
  false
),
(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94100000-0000-4000-8000-000000000002'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.lifecycle.two@glowlab.invalid',
  '2026-07-16 20:15:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 20:15:00+07'::timestamptz,
  '2026-07-16 20:15:00+07'::timestamptz,
  false,
  false
);

insert into app.user_profiles (
  user_id,
  organization_id,
  display_name,
  employee_code,
  role_code,
  is_active
)
values
(
  '94100000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Notification Lifecycle Admin One',
  'PGTAP-NTF-LIFE-ONE',
  'ADMIN',
  true
),
(
  '94100000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Notification Lifecycle Admin Two',
  'PGTAP-NTF-LIFE-TWO',
  'ADMIN',
  true
);

insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active
)
values (
  '00000000-0000-4000-8000-000000000005'::uuid,
  'PGTAP_NOTIFICATION_LIFECYCLE_OTHER',
  'pgTAP Notification Lifecycle Other Organization',
  'Asia/Jakarta',
  true
);

insert into notification.rules (
  id,
  organization_id,
  code,
  version,
  category_code,
  trigger_mode_code,
  entity_type_code,
  severity_strategy_code,
  stage_strategy_code,
  condition_strategy_code,
  resolution_strategy_code,
  template_version,
  action_code,
  config,
  is_active,
  effective_from,
  effective_to,
  created_at,
  updated_at
)
values (
  '80100000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000005'::uuid,
  'OTHER_ORG_RULE',
  '1.0.0',
  'SYSTEM_JOB',
  'SCHEDULED',
  'SYSTEM_JOB',
  'STATIC',
  'JOB_STATUS',
  'JOB_FAILED',
  'JOB_RECOVERED',
  '1.0.0',
  'OPEN_JOB_DETAIL',
  '{}'::jsonb,
  true,
  '2026-07-16 00:00:00+07'::timestamptz,
  null,
  '2026-07-16 20:15:00+07'::timestamptz,
  '2026-07-16 20:15:00+07'::timestamptz
);

create temp table notification_lifecycle_results (
  result_key text primary key,
  result jsonb not null
) on commit drop;

-- 17: create the first active episode
select lives_ok(
  $sql$
    insert into notification_lifecycle_results (
      result_key,
      result
    )
    select
      'CREATE',
      notification.upsert_active_notification(
        p_organization_id =>
          '00000000-0000-4000-8000-000000000001'::uuid,
        p_rule_id =>
          '80000000-0000-4000-8000-000000000001'::uuid,
        p_entity_id =>
          '40000000-0000-4000-8000-000000000001'::uuid,
        p_deduplication_key => 'SELLABLE-EXPIRY-RISK',
        p_stage_code => 'D30',
        p_severity_code => 'HIGH',
        p_title => 'Batch mendekati kedaluwarsa',
        p_message => 'Batch serum berada dalam ambang 30 hari.',
        p_action_route =>
          '/products/30000000-0000-4000-8000-000000000001',
        p_condition_started_at =>
          '2026-07-16 20:16:00+07'::timestamptz,
        p_observed_at =>
          '2026-07-16 20:16:00+07'::timestamptz,
        p_due_at =>
          '2026-08-01 23:59:59+07'::timestamptz,
        p_source_snapshot =>
          '{"riskQty":5,"daysRemaining":16}'::jsonb,
        p_stage_direction_code => 'UNCHANGED',
        p_correlation_id =>
          '97100000-0000-4000-8000-000000000001'::uuid,
        p_process_name => 'pgtap.notification_lifecycle'
      )
  $sql$,
  'first source observation creates a notification episode'
);

-- 18-22: first-episode persistence
select is(
  (
    select result ->> 'action'
    from notification_lifecycle_results
    where result_key = 'CREATE'
  ),
  'CREATED',
  'first source observation reports CREATED'
);

select is(
  (
    select result ->> 'episodeNo'
    from notification_lifecycle_results
    where result_key = 'CREATE'
  ),
  '1',
  'first source observation creates episode one'
);

select is(
  (
    select length(result ->> 'deduplicationHash')
    from notification_lifecycle_results
    where result_key = 'CREATE'
  ),
  64,
  'server produces a SHA-256 deduplication hash'
);

select is(
  (
    select count(*)
    from notification.notifications
    where id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
  ),
  1::bigint,
  'one notification row is persisted'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and event_type_code = 'CREATED'
  ),
  1::bigint,
  'creation appends one CREATED history event'
);

-- 23: identical observation is accepted
select lives_ok(
  $sql$
    insert into notification_lifecycle_results (
      result_key,
      result
    )
    select
      'IDENTICAL',
      notification.upsert_active_notification(
        p_organization_id =>
          '00000000-0000-4000-8000-000000000001'::uuid,
        p_rule_id =>
          '80000000-0000-4000-8000-000000000001'::uuid,
        p_entity_id =>
          '40000000-0000-4000-8000-000000000001'::uuid,
        p_deduplication_key => '  SELLABLE-EXPIRY-RISK  ',
        p_stage_code => 'D30',
        p_severity_code => 'HIGH',
        p_title => 'Batch mendekati kedaluwarsa',
        p_message => 'Batch serum berada dalam ambang 30 hari.',
        p_action_route =>
          '/products/30000000-0000-4000-8000-000000000001',
        p_condition_started_at =>
          '2026-07-16 20:16:00+07'::timestamptz,
        p_observed_at =>
          '2026-07-16 20:17:00+07'::timestamptz,
        p_due_at =>
          '2026-08-01 23:59:59+07'::timestamptz,
        p_source_snapshot =>
          '{"riskQty":5,"daysRemaining":16}'::jsonb,
        p_stage_direction_code => 'UNCHANGED',
        p_correlation_id =>
          '97100000-0000-4000-8000-000000000002'::uuid,
        p_process_name => 'pgtap.notification_lifecycle'
      )
  $sql$,
  'identical source observation reuses the active episode'
);

-- 24-27: no duplicate or noisy event
select is(
  (
    select result ->> 'notificationId'
    from notification_lifecycle_results
    where result_key = 'IDENTICAL'
  ),
  (
    select result ->> 'notificationId'
    from notification_lifecycle_results
    where result_key = 'CREATE'
  ),
  'identical observation returns the same active notification'
);

select is(
  (
    select result ->> 'action'
    from notification_lifecycle_results
    where result_key = 'IDENTICAL'
  ),
  'SEEN_AGAIN',
  'identical observation reports SEEN_AGAIN'
);

select is(
  (
    select occurrence_count
    from notification.notifications
    where id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
  ),
  2,
  'identical observation increments occurrence count'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
  ),
  1::bigint,
  'identical observation does not append a noisy history event'
);

-- 28: source snapshot update
select lives_ok(
  $sql$
    insert into notification_lifecycle_results (
      result_key,
      result
    )
    select
      'SOURCE_UPDATE',
      notification.upsert_active_notification(
        p_organization_id =>
          '00000000-0000-4000-8000-000000000001'::uuid,
        p_rule_id =>
          '80000000-0000-4000-8000-000000000001'::uuid,
        p_entity_id =>
          '40000000-0000-4000-8000-000000000001'::uuid,
        p_deduplication_key => 'sellable-expiry-risk',
        p_stage_code => 'D30',
        p_severity_code => 'HIGH',
        p_title => 'Batch mendekati kedaluwarsa',
        p_message => 'Batch serum berada dalam ambang 30 hari.',
        p_action_route =>
          '/products/30000000-0000-4000-8000-000000000001',
        p_condition_started_at =>
          '2026-07-16 20:16:00+07'::timestamptz,
        p_observed_at =>
          '2026-07-16 20:18:00+07'::timestamptz,
        p_due_at =>
          '2026-08-01 23:59:59+07'::timestamptz,
        p_source_snapshot =>
          '{"riskQty":4,"daysRemaining":16}'::jsonb,
        p_stage_direction_code => 'UNCHANGED',
        p_correlation_id =>
          '97100000-0000-4000-8000-000000000003'::uuid,
        p_process_name => 'pgtap.notification_lifecycle'
      )
  $sql$,
  'changed source snapshot updates the active episode'
);

-- 29-30: meaningful source change is audited once
select is(
  (
    select result ->> 'action'
    from notification_lifecycle_results
    where result_key = 'SOURCE_UPDATE'
  ),
  'UPDATED',
  'changed source snapshot reports UPDATED'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and event_type_code = 'SOURCE_SNAPSHOT_UPDATED'
  ),
  1::bigint,
  'changed source snapshot appends one audit event'
);

-- Seed per-user state before escalation
select lives_ok(
  $sql$
    insert into notification.user_states (
      organization_id,
      notification_id,
      user_id,
      read_state_code,
      read_at,
      archived_at,
      last_seen_version_no
    )
    values
    (
      '00000000-0000-4000-8000-000000000001'::uuid,
      (
        select (result ->> 'notificationId')::uuid
        from notification_lifecycle_results
        where result_key = 'CREATE'
      ),
      '94100000-0000-4000-8000-000000000001'::uuid,
      'READ',
      '2026-07-16 20:18:30+07'::timestamptz,
      null,
      3
    ),
    (
      '00000000-0000-4000-8000-000000000001'::uuid,
      (
        select (result ->> 'notificationId')::uuid
        from notification_lifecycle_results
        where result_key = 'CREATE'
      ),
      '94100000-0000-4000-8000-000000000002'::uuid,
      'ARCHIVED',
      '2026-07-16 20:18:20+07'::timestamptz,
      '2026-07-16 20:18:40+07'::timestamptz,
      3
    )
  $sql$,
  'two Admin accounts may hold independent read and archive state'
);

-- 32: stage and severity escalation
select lives_ok(
  $sql$
    insert into notification_lifecycle_results (
      result_key,
      result
    )
    select
      'ESCALATE',
      notification.upsert_active_notification(
        p_organization_id =>
          '00000000-0000-4000-8000-000000000001'::uuid,
        p_rule_id =>
          '80000000-0000-4000-8000-000000000001'::uuid,
        p_entity_id =>
          '40000000-0000-4000-8000-000000000001'::uuid,
        p_deduplication_key => 'sellable-expiry-risk',
        p_stage_code => 'EXPIRED',
        p_severity_code => 'CRITICAL',
        p_title => 'Batch mendekati kedaluwarsa',
        p_message => 'Batch serum berada dalam ambang 30 hari.',
        p_action_route =>
          '/products/30000000-0000-4000-8000-000000000001',
        p_condition_started_at =>
          '2026-07-16 20:16:00+07'::timestamptz,
        p_observed_at =>
          '2026-07-16 20:19:00+07'::timestamptz,
        p_due_at =>
          '2026-08-01 23:59:59+07'::timestamptz,
        p_source_snapshot =>
          '{"riskQty":4,"daysRemaining":16}'::jsonb,
        p_stage_direction_code => 'ESCALATED',
        p_correlation_id =>
          '97100000-0000-4000-8000-000000000004'::uuid,
        p_process_name => 'pgtap.notification_lifecycle'
      )
  $sql$,
  'stage and severity escalation updates one active episode'
);

-- 33-40: escalation state and audit
select is(
  (
    select severity_code
    from notification.notifications
    where id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
  ),
  'CRITICAL',
  'escalation persists CRITICAL severity'
);

select is(
  (
    select stage_code
    from notification.notifications
    where id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
  ),
  'EXPIRED',
  'escalation persists the later stage'
);

select is(
  (
    select count(*)
    from notification.user_states
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and read_state_code = 'UNREAD'
  ),
  2::bigint,
  'escalation resets all active Admin states to UNREAD'
);

select is(
  (
    select count(*)
    from notification.user_states
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and read_at is null
  ),
  2::bigint,
  'escalation clears read timestamps'
);

select is(
  (
    select count(*)
    from notification.user_states
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and archived_at is null
  ),
  2::bigint,
  'escalation clears archive timestamps'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and event_type_code = 'STAGE_ESCALATED'
  ),
  1::bigint,
  'stage escalation appends one stage event'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and event_type_code = 'SEVERITY_CHANGED'
  ),
  1::bigint,
  'severity escalation appends one severity event'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and event_type_code = 'READ_STATE_RESET_BY_ESCALATION'
  ),
  1::bigint,
  'escalation appends one read-state reset event'
);

-- 41-42: stale observations and ambiguous stage changes are blocked
select throws_ok(
  $sql$
    select notification.upsert_active_notification(
      p_organization_id =>
        '00000000-0000-4000-8000-000000000001'::uuid,
      p_rule_id =>
        '80000000-0000-4000-8000-000000000001'::uuid,
      p_entity_id =>
        '40000000-0000-4000-8000-000000000001'::uuid,
      p_deduplication_key => 'sellable-expiry-risk',
      p_stage_code => 'EXPIRED',
      p_severity_code => 'CRITICAL',
      p_title => 'Batch mendekati kedaluwarsa',
      p_message => 'Stale observation.',
      p_action_route =>
        '/products/30000000-0000-4000-8000-000000000001',
      p_condition_started_at =>
        '2026-07-16 20:16:00+07'::timestamptz,
      p_observed_at =>
        '2026-07-16 20:18:30+07'::timestamptz,
      p_source_snapshot => '{}'::jsonb,
      p_stage_direction_code => 'UNCHANGED',
      p_process_name => 'pgtap.notification_lifecycle'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_OBSERVED_AT_STALE',
  'older observations cannot overwrite newer notification state'
);

select throws_ok(
  $sql$
    select notification.upsert_active_notification(
      p_organization_id =>
        '00000000-0000-4000-8000-000000000001'::uuid,
      p_rule_id =>
        '80000000-0000-4000-8000-000000000001'::uuid,
      p_entity_id =>
        '40000000-0000-4000-8000-000000000001'::uuid,
      p_deduplication_key => 'sellable-expiry-risk',
      p_stage_code => 'D7',
      p_severity_code => 'CRITICAL',
      p_title => 'Batch mendekati kedaluwarsa',
      p_message => 'Stage direction is missing.',
      p_action_route =>
        '/products/30000000-0000-4000-8000-000000000001',
      p_condition_started_at =>
        '2026-07-16 20:16:00+07'::timestamptz,
      p_observed_at =>
        '2026-07-16 20:20:00+07'::timestamptz,
      p_source_snapshot => '{}'::jsonb,
      p_stage_direction_code => 'UNCHANGED',
      p_process_name => 'pgtap.notification_lifecycle'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_STAGE_DIRECTION_REQUIRED',
  'a changed stage requires an explicit direction'
);

-- 43: resolve the active episode
select lives_ok(
  $sql$
    insert into notification_lifecycle_results (
      result_key,
      result
    )
    select
      'RESOLVE',
      notification.resolve_notification(
        p_organization_id =>
          '00000000-0000-4000-8000-000000000001'::uuid,
        p_notification_id => (
          select (result ->> 'notificationId')::uuid
          from notification_lifecycle_results
          where result_key = 'CREATE'
        ),
        p_resolution_code => 'SOURCE_CONDITION_CLEARED',
        p_resolution_snapshot => '{"riskQty":0}'::jsonb,
        p_resolved_at =>
          '2026-07-16 20:21:00+07'::timestamptz,
        p_correlation_id =>
          '97100000-0000-4000-8000-000000000005'::uuid,
        p_note => 'The source condition is no longer present.',
        p_process_name => 'pgtap.notification_lifecycle'
      )
  $sql$,
  'active notification can be resolved'
);

-- 44-46: resolution state and event
select is(
  (
    select result ->> 'action'
    from notification_lifecycle_results
    where result_key = 'RESOLVE'
  ),
  'RESOLVED',
  'first resolution reports RESOLVED'
);

select is(
  (
    select lifecycle_status_code
    from notification.notifications
    where id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
  ),
  'RESOLVED',
  'resolved episode persists RESOLVED lifecycle state'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and event_type_code = 'RESOLVED'
  ),
  1::bigint,
  'resolution appends one RESOLVED history event'
);

-- 47: identical resolution is idempotent
select is(
  (
    notification.resolve_notification(
      p_organization_id =>
        '00000000-0000-4000-8000-000000000001'::uuid,
      p_notification_id => (
        select (result ->> 'notificationId')::uuid
        from notification_lifecycle_results
        where result_key = 'CREATE'
      ),
      p_resolution_code => 'SOURCE_CONDITION_CLEARED',
      p_resolution_snapshot => '{"riskQty":0}'::jsonb,
      p_resolved_at =>
        '2026-07-16 20:22:00+07'::timestamptz,
      p_correlation_id =>
        '97100000-0000-4000-8000-000000000006'::uuid,
      p_process_name => 'pgtap.notification_lifecycle'
    ) ->> 'action'
  ),
  'ALREADY_RESOLVED',
  'identical resolution retry is idempotent'
);

-- 48: idempotent retry does not duplicate history
select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and event_type_code = 'RESOLVED'
  ),
  1::bigint,
  'idempotent resolution retry does not append another event'
);

-- 49: conflicting resolution is rejected
select throws_ok(
  $sql$
    select notification.resolve_notification(
      p_organization_id =>
        '00000000-0000-4000-8000-000000000001'::uuid,
      p_notification_id => (
        select (result ->> 'notificationId')::uuid
        from notification_lifecycle_results
        where result_key = 'CREATE'
      ),
      p_resolution_code => 'MANUALLY_DISMISSED',
      p_resolution_snapshot => '{"riskQty":0}'::jsonb,
      p_resolved_at =>
        '2026-07-16 20:22:00+07'::timestamptz,
      p_correlation_id =>
        '97100000-0000-4000-8000-000000000007'::uuid,
      p_process_name => 'pgtap.notification_lifecycle'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_ALREADY_RESOLVED',
  'resolved history cannot be rewritten with another outcome'
);

-- 50: source recurrence creates a new episode
select lives_ok(
  $sql$
    insert into notification_lifecycle_results (
      result_key,
      result
    )
    select
      'RECURRENCE',
      notification.upsert_active_notification(
        p_organization_id =>
          '00000000-0000-4000-8000-000000000001'::uuid,
        p_rule_id =>
          '80000000-0000-4000-8000-000000000001'::uuid,
        p_entity_id =>
          '40000000-0000-4000-8000-000000000001'::uuid,
        p_deduplication_key => 'sellable-expiry-risk',
        p_stage_code => 'D30',
        p_severity_code => 'HIGH',
        p_title => 'Batch kembali mendekati kedaluwarsa',
        p_message => 'Source condition returned after resolution.',
        p_action_route =>
          '/products/30000000-0000-4000-8000-000000000001',
        p_condition_started_at =>
          '2026-07-16 20:23:00+07'::timestamptz,
        p_observed_at =>
          '2026-07-16 20:23:00+07'::timestamptz,
        p_due_at =>
          '2026-08-01 23:59:59+07'::timestamptz,
        p_source_snapshot =>
          '{"riskQty":3,"daysRemaining":16}'::jsonb,
        p_stage_direction_code => 'UNCHANGED',
        p_correlation_id =>
          '97100000-0000-4000-8000-000000000008'::uuid,
        p_process_name => 'pgtap.notification_lifecycle'
      )
  $sql$,
  'resolved source condition may recur as a new episode'
);

-- 51-56: recurrence chain and uniqueness
select is(
  (
    select result ->> 'action'
    from notification_lifecycle_results
    where result_key = 'RECURRENCE'
  ),
  'REOPENED_AS_NEW_EPISODE',
  'recurrence reports a new linked episode'
);

select is(
  (
    select result ->> 'episodeNo'
    from notification_lifecycle_results
    where result_key = 'RECURRENCE'
  ),
  '2',
  'recurrence increments episode number'
);

select is(
  (
    select result ->> 'previousNotificationId'
    from notification_lifecycle_results
    where result_key = 'RECURRENCE'
  ),
  (
    select result ->> 'notificationId'
    from notification_lifecycle_results
    where result_key = 'CREATE'
  ),
  'recurrence links to the resolved previous episode'
);

select is(
  (
    select count(*)
    from notification.notifications
    where deduplication_hash = (
      select result ->> 'deduplicationHash'
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and lifecycle_status_code in ('OPEN', 'ACKNOWLEDGED')
  ),
  1::bigint,
  'deduplication hash has exactly one active episode'
);

select is(
  (
    select count(*)
    from notification.notifications
    where deduplication_hash = (
      select result ->> 'deduplicationHash'
      from notification_lifecycle_results
      where result_key = 'CREATE'
    )
      and lifecycle_status_code = 'RESOLVED'
  ),
  1::bigint,
  'resolved episode remains immutable history'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id = (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'RECURRENCE'
    )
      and event_type_code = 'REOPENED_AS_NEW_EPISODE'
  ),
  1::bigint,
  'recurrence appends one reopening history event'
);

-- 57-58: reset function is idempotent on the new episode
select is(
  notification.reset_user_read_states(
    p_organization_id =>
      '00000000-0000-4000-8000-000000000001'::uuid,
    p_notification_id => (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'RECURRENCE'
    ),
    p_process_name => 'pgtap.notification_lifecycle'
  ),
  2,
  'first reset creates UNREAD state for both active Admin accounts'
);

select is(
  notification.reset_user_read_states(
    p_organization_id =>
      '00000000-0000-4000-8000-000000000001'::uuid,
    p_notification_id => (
      select (result ->> 'notificationId')::uuid
      from notification_lifecycle_results
      where result_key = 'RECURRENCE'
    ),
    p_process_name => 'pgtap.notification_lifecycle'
  ),
  0,
  'repeating the same reset produces no second state change'
);

-- 59-60: user actor path
select lives_ok(
  $sql$
    select notification.append_notification_event(
      p_organization_id =>
        '00000000-0000-4000-8000-000000000001'::uuid,
      p_notification_id => (
        select (result ->> 'notificationId')::uuid
        from notification_lifecycle_results
        where result_key = 'RECURRENCE'
      ),
      p_event_type_code => 'SEEN_AGAIN',
      p_occurred_at =>
        '2026-07-16 20:24:00+07'::timestamptz,
      p_correlation_id =>
        '97100000-0000-4000-8000-000000000009'::uuid,
      p_source_snapshot => '{"actorFixture":true}'::jsonb,
      p_actor_user_id =>
        '94100000-0000-4000-8000-000000000001'::uuid
    )
  $sql$,
  'authorized Admin actor may append a trusted internal event'
);

select is(
  (
    select actor_type_code
    from notification.notification_events
    where correlation_id =
      '97100000-0000-4000-8000-000000000009'::uuid
  ),
  'USER',
  'user-backed event snapshots USER actor type'
);

-- 61-64: actor and organization boundaries
select throws_ok(
  $sql$
    select notification.append_notification_event(
      p_organization_id =>
        '00000000-0000-4000-8000-000000000001'::uuid,
      p_notification_id => (
        select (result ->> 'notificationId')::uuid
        from notification_lifecycle_results
        where result_key = 'RECURRENCE'
      ),
      p_event_type_code => 'SEEN_AGAIN',
      p_occurred_at =>
        '2026-07-16 20:25:00+07'::timestamptz,
      p_correlation_id => gen_random_uuid(),
      p_source_snapshot => '{}'::jsonb,
      p_actor_user_id =>
        '94100000-0000-4000-8000-000000000001'::uuid,
      p_process_name => 'invalid.double.actor'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_ACTOR_CONTEXT_INVALID',
  'one command cannot claim both a user and a process actor'
);

select throws_ok(
  $sql$
    select notification.upsert_active_notification(
      p_organization_id =>
        '00000000-0000-4000-8000-000000000005'::uuid,
      p_rule_id =>
        '80100000-0000-4000-8000-000000000001'::uuid,
      p_entity_id =>
        '95100000-0000-4000-8000-000000000001'::uuid,
      p_deduplication_key => 'other-org-job',
      p_stage_code => 'FAILED',
      p_severity_code => 'HIGH',
      p_title => 'Other organization job failed',
      p_message => 'Actor belongs to the wrong organization.',
      p_action_route => '/system/jobs/other',
      p_condition_started_at =>
        '2026-07-16 20:25:00+07'::timestamptz,
      p_observed_at =>
        '2026-07-16 20:25:00+07'::timestamptz,
      p_source_snapshot => '{}'::jsonb,
      p_actor_user_id =>
        '94100000-0000-4000-8000-000000000001'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_ACTOR_NOT_AUTHORIZED',
  'Admin actor cannot write notification state for another organization'
);

select throws_ok(
  $sql$
    select notification.upsert_active_notification(
      p_organization_id =>
        '00000000-0000-4000-8000-000000000001'::uuid,
      p_rule_id =>
        '80100000-0000-4000-8000-000000000001'::uuid,
      p_entity_id =>
        '40000000-0000-4000-8000-000000000001'::uuid,
      p_deduplication_key => 'cross-org-rule',
      p_stage_code => 'FAILED',
      p_severity_code => 'HIGH',
      p_title => 'Cross-organization rule',
      p_message => 'Rule organization must match command organization.',
      p_action_route => '/system/jobs/other',
      p_condition_started_at =>
        '2026-07-16 20:25:00+07'::timestamptz,
      p_observed_at =>
        '2026-07-16 20:25:00+07'::timestamptz,
      p_source_snapshot => '{}'::jsonb,
      p_process_name => 'pgtap.notification_lifecycle'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_RULE_NOT_FOUND',
  'rule lookup does not cross organization boundaries'
);

select throws_ok(
  $sql$
    select notification.reset_user_read_states(
      p_organization_id =>
        '00000000-0000-4000-8000-000000000001'::uuid,
      p_notification_id => (
        select (result ->> 'notificationId')::uuid
        from notification_lifecycle_results
        where result_key = 'CREATE'
      ),
      p_process_name => 'pgtap.notification_lifecycle'
    )
  $sql$,
  'P0001',
  'ACTIVE_NOTIFICATION_NOT_FOUND',
  'resolved notification state cannot be reset as active'
);

select * from finish();
rollback;
