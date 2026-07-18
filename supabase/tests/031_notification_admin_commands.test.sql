begin;

create extension if not exists pgtap with schema extensions;

select plan(69);

-- 1-6: internal and browser-facing command contract
select has_function(
  'notification'::name,
  'acknowledge_notification'::name,
  array[
    'uuid',
    'uuid',
    'timestamp with time zone',
    'uuid',
    'uuid',
    'text'
  ]::text[]
);

select has_function(
  'notification'::name,
  'revoke_notification_acknowledgment'::name,
  array[
    'uuid',
    'uuid',
    'timestamp with time zone',
    'uuid',
    'uuid',
    'text'
  ]::text[]
);

select has_function(
  'notification'::name,
  'set_notification_read_state'::name,
  array[
    'uuid',
    'uuid',
    'uuid',
    'text',
    'timestamp with time zone'
  ]::text[]
);

select has_function(
  'api'::name,
  'acknowledge_notification'::name,
  array['uuid', 'text', 'uuid']::text[]
);

select has_function(
  'api'::name,
  'revoke_notification_acknowledgment'::name,
  array['uuid', 'text', 'uuid']::text[]
);

select has_function(
  'api'::name,
  'set_notification_read_state'::name,
  array['uuid', 'text']::text[]
);

-- 7-12: all commands return structured JSON
select function_returns(
  'notification',
  'acknowledge_notification',
  array[
    'uuid',
    'uuid',
    'timestamptz',
    'uuid',
    'uuid',
    'text'
  ]::text[],
  'jsonb'
);

select function_returns(
  'notification',
  'revoke_notification_acknowledgment',
  array[
    'uuid',
    'uuid',
    'timestamptz',
    'uuid',
    'uuid',
    'text'
  ]::text[],
  'jsonb'
);

select function_returns(
  'notification',
  'set_notification_read_state',
  array[
    'uuid',
    'uuid',
    'uuid',
    'text',
    'timestamptz'
  ]::text[],
  'jsonb'
);

select function_returns(
  'api',
  'acknowledge_notification',
  array['uuid', 'text', 'uuid']::text[],
  'jsonb'
);

select function_returns(
  'api',
  'revoke_notification_acknowledgment',
  array['uuid', 'text', 'uuid']::text[],
  'jsonb'
);

select function_returns(
  'api',
  'set_notification_read_state',
  array['uuid', 'text']::text[],
  'jsonb'
);

-- 13-24: internal functions remain trusted while API wrappers are authenticated
select ok(
  has_function_privilege(
    'service_role',
    'notification.acknowledge_notification(uuid,uuid,timestamptz,uuid,uuid,text)',
    'EXECUTE'
  ),
  'service role may invoke trusted acknowledgment command'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.acknowledge_notification(uuid,uuid,timestamptz,uuid,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot supply trusted acknowledgment identity'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.revoke_notification_acknowledgment(uuid,uuid,timestamptz,uuid,uuid,text)',
    'EXECUTE'
  ),
  'service role may invoke trusted acknowledgment revocation'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.revoke_notification_acknowledgment(uuid,uuid,timestamptz,uuid,uuid,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot supply trusted revocation identity'
);

select ok(
  has_function_privilege(
    'service_role',
    'notification.set_notification_read_state(uuid,uuid,uuid,text,timestamptz)',
    'EXECUTE'
  ),
  'service role may invoke trusted per-user state command'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'notification.set_notification_read_state(uuid,uuid,uuid,text,timestamptz)',
    'EXECUTE'
  ),
  'authenticated clients cannot supply another user identity'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.acknowledge_notification(uuid,text,uuid)',
    'EXECUTE'
  ),
  'authenticated Admin may call the acknowledgment API'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.acknowledge_notification(uuid,text,uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot call the acknowledgment API'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.revoke_notification_acknowledgment(uuid,text,uuid)',
    'EXECUTE'
  ),
  'authenticated Admin may call the acknowledgment revocation API'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.revoke_notification_acknowledgment(uuid,text,uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot call the acknowledgment revocation API'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.set_notification_read_state(uuid,text)',
    'EXECUTE'
  ),
  'authenticated Admin may call the per-user state API'
);

select ok(
  not has_function_privilege(
    'anon',
    'api.set_notification_read_state(uuid,text)',
    'EXECUTE'
  ),
  'anonymous clients cannot call the per-user state API'
);

-- Auth and organization fixtures
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
  '94200000-0000-4000-8000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.admin.one@glowlab.invalid',
  '2026-07-16 20:55:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 20:55:00+07'::timestamptz,
  '2026-07-16 20:55:00+07'::timestamptz,
  false,
  false
),
(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94200000-0000-4000-8000-000000000002'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.admin.two@glowlab.invalid',
  '2026-07-16 20:55:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 20:55:00+07'::timestamptz,
  '2026-07-16 20:55:00+07'::timestamptz,
  false,
  false
),
(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '94200000-0000-4000-8000-000000000003'::uuid,
  'authenticated',
  'authenticated',
  'pgtap.notification.other.org@glowlab.invalid',
  '2026-07-16 20:55:00+07'::timestamptz,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-07-16 20:55:00+07'::timestamptz,
  '2026-07-16 20:55:00+07'::timestamptz,
  false,
  false
);

insert into app.organizations (
  id,
  code,
  name,
  timezone,
  is_active
)
values (
  '00000000-0000-4000-8000-000000000006'::uuid,
  'PGTAP_NOTIFICATION_ADMIN_OTHER',
  'pgTAP Notification Admin Other Organization',
  'Asia/Jakarta',
  true
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
  '94200000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Notification Admin One',
  'PGTAP-NTF-ADMIN-ONE',
  'ADMIN',
  true
),
(
  '94200000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  'pgTAP Notification Admin Two',
  'PGTAP-NTF-ADMIN-TWO',
  'ADMIN',
  true
),
(
  '94200000-0000-4000-8000-000000000003'::uuid,
  '00000000-0000-4000-8000-000000000006'::uuid,
  'pgTAP Notification Other Org Admin',
  'PGTAP-NTF-ADMIN-OTHER',
  'ADMIN',
  true
);

insert into notification.notifications (
  id,
  organization_id,
  rule_id,
  rule_code_snapshot,
  rule_version_snapshot,
  template_version_snapshot,
  notification_type_code,
  category_code,
  entity_type_code,
  entity_id,
  episode_no,
  previous_notification_id,
  deduplication_key,
  deduplication_hash,
  lifecycle_status_code,
  stage_code,
  severity_code,
  title,
  message,
  action_code,
  action_route,
  condition_started_at,
  due_at,
  first_seen_at,
  last_seen_at,
  occurrence_count,
  source_snapshot,
  config_snapshot,
  created_at,
  updated_at,
  version_no
)
values (
  '95200000-0000-4000-8000-000000000001'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '80000000-0000-4000-8000-000000000001'::uuid,
  'EXPIRY_RISK',
  '1.0.0',
  '1.0.0',
  'EXPIRY_RISK',
  'EXPIRY',
  'PRODUCT_BATCH',
  '40000000-0000-4000-8000-000000000001'::uuid,
  1,
  null,
  'expiry_risk:product_batch:40000000-0000-4000-8000-000000000001:admin-command-fixture',
  repeat('e', 64),
  'OPEN',
  'D30',
  'CRITICAL',
  'Batch mendekati kedaluwarsa',
  'Batch serum berada dalam ambang 30 hari.',
  'OPEN_BATCH_EXPIRY_DETAIL',
  '/products/30000000-0000-4000-8000-000000000001/batches/40000000-0000-4000-8000-000000000001',
  '2026-07-16 20:55:00+07'::timestamptz,
  '2026-08-01 23:59:59+07'::timestamptz,
  '2026-07-16 20:55:00+07'::timestamptz,
  '2026-07-16 20:55:00+07'::timestamptz,
  1,
  '{"riskQty":5,"daysRemaining":16}'::jsonb,
  '{"thresholdDays":[90,60,30,0]}'::jsonb,
  '2026-07-16 20:55:00+07'::timestamptz,
  '2026-07-16 20:55:00+07'::timestamptz,
  1
);

-- Admin One JWT
select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000001',
    'role',
    'authenticated',
    'email',
    'pgtap.notification.admin.one@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

-- 25-26: Critical acknowledgment requires a meaningful note
select throws_ok(
  $sql$
    select api.acknowledge_notification(
      '95200000-0000-4000-8000-000000000001'::uuid,
      null,
      '97200000-0000-4000-8000-000000000010'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_CRITICAL_ACK_NOTE_REQUIRED',
  'Critical notification rejects acknowledgment without a note'
);

select throws_ok(
  $sql$
    select api.acknowledge_notification(
      '95200000-0000-4000-8000-000000000001'::uuid,
      '   ',
      '97200000-0000-4000-8000-000000000011'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_CRITICAL_ACK_NOTE_REQUIRED',
  'Critical notification rejects a blank acknowledgment note'
);

-- 27: first organization-level acknowledgment with a valid Critical note
select is(
  (
    api.acknowledge_notification(
      '95200000-0000-4000-8000-000000000001'::uuid,
      '  Investigating the expiry risk.  ',
      '97200000-0000-4000-8000-000000000001'::uuid
    ) ->> 'action'
  ),
  'ACKNOWLEDGED',
  'first Admin acknowledgment updates organization-level triage state'
);

reset role;

-- 26-32: acknowledgment persistence and audit
select is(
  (
    select lifecycle_status_code
    from notification.notifications
    where id = '95200000-0000-4000-8000-000000000001'::uuid
  ),
  'ACKNOWLEDGED',
  'acknowledgment persists ACKNOWLEDGED lifecycle state'
);

select is(
  (
    select acknowledged_by
    from notification.notifications
    where id = '95200000-0000-4000-8000-000000000001'::uuid
  ),
  '94200000-0000-4000-8000-000000000001'::uuid,
  'acknowledgment stores the trusted session actor'
);

select is(
  (
    select acknowledgment_note
    from notification.notifications
    where id = '95200000-0000-4000-8000-000000000001'::uuid
  ),
  'Investigating the expiry risk.',
  'acknowledgment trims and stores its optional note'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and event_type_code = 'ACKNOWLEDGED'
  ),
  1::bigint,
  'acknowledgment appends one immutable history event'
);

select is(
  (
    select actor_user_id
    from notification.notification_events
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and event_type_code = 'ACKNOWLEDGED'
  ),
  '94200000-0000-4000-8000-000000000001'::uuid,
  'acknowledgment event stores the trusted session actor'
);

select is(
  (
    select source_snapshot
    from notification.notifications
    where id = '95200000-0000-4000-8000-000000000001'::uuid
  ),
  '{"riskQty":5,"daysRemaining":16}'::jsonb,
  'acknowledgment does not rewrite the source-condition snapshot'
);

select is(
  (
    select count(*)
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
  ),
  0::bigint,
  'acknowledgment does not mark any Admin account as read'
);

-- Admin Two JWT
select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000002',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000002',
    'role',
    'authenticated',
    'email',
    'pgtap.notification.admin.two@glowlab.invalid'
  )::text,
  true
);

set local role authenticated;

-- 33: second acknowledgment is idempotent
select is(
  (
    api.acknowledge_notification(
      '95200000-0000-4000-8000-000000000001'::uuid,
      'A second Admin also saw this.',
      '97200000-0000-4000-8000-000000000002'::uuid
    ) ->> 'action'
  ),
  'ALREADY_ACKNOWLEDGED',
  'second Admin acknowledgment is idempotent at organization level'
);

reset role;

-- 34-35: no duplicate event or actor rewrite
select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and event_type_code = 'ACKNOWLEDGED'
  ),
  1::bigint,
  'idempotent acknowledgment does not duplicate history'
);

select is(
  (
    select acknowledged_by
    from notification.notifications
    where id = '95200000-0000-4000-8000-000000000001'::uuid
  ),
  '94200000-0000-4000-8000-000000000001'::uuid,
  'idempotent acknowledgment preserves the first actor'
);

-- Admin One marks the notification read
select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000001',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 36: read command
select is(
  (
    api.set_notification_read_state(
      '95200000-0000-4000-8000-000000000001'::uuid,
      'READ'
    ) ->> 'action'
  ),
  'SET_READ',
  'Admin One may mark their own notification state as READ'
);

reset role;

-- 37-40: read state is per-user and lifecycle-neutral
select is(
  (
    select read_state_code
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and user_id =
        '94200000-0000-4000-8000-000000000001'::uuid
  ),
  'READ',
  'Admin One state is stored as READ'
);

select ok(
  (
    select read_at is not null
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and user_id =
        '94200000-0000-4000-8000-000000000001'::uuid
  ),
  'READ state records its server-side timestamp'
);

select is(
  (
    select lifecycle_status_code
    from notification.notifications
    where id = '95200000-0000-4000-8000-000000000001'::uuid
  ),
  'ACKNOWLEDGED',
  'marking READ does not alter organization-level lifecycle'
);

select is(
  (
    select count(*)
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and user_id =
        '94200000-0000-4000-8000-000000000002'::uuid
  ),
  0::bigint,
  'Admin One read action does not create Admin Two state'
);

-- Admin Two archives only their own presentation state
select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000002',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000002',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 41: public archive alias
select is(
  (
    api.set_notification_read_state(
      '95200000-0000-4000-8000-000000000001'::uuid,
      'ARCHIVED_FOR_USER'
    ) ->> 'action'
  ),
  'SET_ARCHIVED',
  'Admin Two may archive the notification only for their account'
);

reset role;

-- 42-44: archive persistence and independence
select is(
  (
    select read_state_code
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and user_id =
        '94200000-0000-4000-8000-000000000002'::uuid
  ),
  'ARCHIVED',
  'public ARCHIVED_FOR_USER state normalizes to stored ARCHIVED'
);

select ok(
  (
    select read_at is not null and archived_at is not null
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and user_id =
        '94200000-0000-4000-8000-000000000002'::uuid
  ),
  'archive stores read and archive timestamps'
);

select is(
  (
    select count(*)
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
  ),
  2::bigint,
  'one notification now has independent state for two Admin accounts'
);

-- Admin One RLS view
select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000001',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 45: user-state RLS for Admin One
select is(
  (
    select count(*)
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'Admin One can read only their own notification state'
);

reset role;

-- Admin Two RLS and revocation
select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000002',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000002',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 46: user-state RLS for Admin Two
select is(
  (
    select count(*)
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
  ),
  1::bigint,
  'Admin Two can read only their own notification state'
);

-- 47: authenticated cannot update organization lifecycle directly
select throws_like(
  $sql$
    update notification.notifications
    set lifecycle_status_code = 'OPEN'
    where id = '95200000-0000-4000-8000-000000000001'::uuid
  $sql$,
  '%permission denied for table notifications%',
  'authenticated clients cannot bypass the command API'
);

-- 48: organization-level acknowledgment may be revoked
select is(
  (
    api.revoke_notification_acknowledgment(
      '95200000-0000-4000-8000-000000000001'::uuid,
      'Ownership returned to the unacknowledged queue.',
      '97200000-0000-4000-8000-000000000003'::uuid
    ) ->> 'action'
  ),
  'ACKNOWLEDGMENT_REVOKED',
  'another Admin in the organization may revoke acknowledgment'
);

reset role;

-- 49-54: revocation audit and presentation-state neutrality
select is(
  (
    select lifecycle_status_code
    from notification.notifications
    where id = '95200000-0000-4000-8000-000000000001'::uuid
  ),
  'OPEN',
  'revocation returns the organization lifecycle to OPEN'
);

select ok(
  (
    select acknowledged_at is null
      and acknowledged_by is null
      and acknowledgment_note is null
    from notification.notifications
    where id = '95200000-0000-4000-8000-000000000001'::uuid
  ),
  'revocation clears the current acknowledgment payload'
);

select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and event_type_code = 'ACKNOWLEDGMENT_REVOKED'
  ),
  1::bigint,
  'revocation appends one immutable history event'
);

select is(
  (
    select actor_user_id
    from notification.notification_events
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and event_type_code = 'ACKNOWLEDGMENT_REVOKED'
  ),
  '94200000-0000-4000-8000-000000000002'::uuid,
  'revocation event stores the trusted session actor'
);

select is(
  (
    select read_state_code
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and user_id =
        '94200000-0000-4000-8000-000000000002'::uuid
  ),
  'ARCHIVED',
  'acknowledgment revocation does not unarchive Admin Two state'
);

select is(
  (
    select read_state_code
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and user_id =
        '94200000-0000-4000-8000-000000000001'::uuid
  ),
  'READ',
  'acknowledgment revocation does not change Admin One read state'
);

-- Admin Two repeated revoke
select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000002',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000002',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 55: idempotent repeated revoke
select is(
  (
    api.revoke_notification_acknowledgment(
      '95200000-0000-4000-8000-000000000001'::uuid,
      null,
      '97200000-0000-4000-8000-000000000004'::uuid
    ) ->> 'action'
  ),
  'ALREADY_OPEN',
  'repeating revocation is idempotent'
);

reset role;

-- 56: no duplicate revocation event
select is(
  (
    select count(*)
    from notification.notification_events
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and event_type_code = 'ACKNOWLEDGMENT_REVOKED'
  ),
  1::bigint,
  'idempotent revoke does not duplicate history'
);

-- Admin One returns their state to UNREAD
select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000001',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 57: set unread
select is(
  (
    api.set_notification_read_state(
      '95200000-0000-4000-8000-000000000001'::uuid,
      'UNREAD'
    ) ->> 'action'
  ),
  'SET_UNREAD',
  'Admin One may return their presentation state to UNREAD'
);

-- 58: repeated unread is idempotent
select is(
  (
    api.set_notification_read_state(
      '95200000-0000-4000-8000-000000000001'::uuid,
      'UNREAD'
    ) ->> 'action'
  ),
  'ALREADY_UNREAD',
  'repeating UNREAD is idempotent'
);

-- 59: invalid presentation state
select throws_ok(
  $sql$
    select api.set_notification_read_state(
      '95200000-0000-4000-8000-000000000001'::uuid,
      'DISMISSED'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_READ_STATE_INVALID',
  'unsupported per-user state is rejected'
);

reset role;

-- 60: UNREAD payload is internally consistent
select ok(
  (
    select read_state_code = 'UNREAD'
      and read_at is null
      and archived_at is null
      and last_seen_version_no is null
    from notification.user_states
    where notification_id =
      '95200000-0000-4000-8000-000000000001'::uuid
      and user_id =
        '94200000-0000-4000-8000-000000000001'::uuid
  ),
  'UNREAD clears read, archive, and seen-version fields'
);

-- Other-organization Admin JWT
select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000003',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000003',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 61-62: trusted organization cannot be overridden by notification id
select throws_ok(
  $sql$
    select api.acknowledge_notification(
      '95200000-0000-4000-8000-000000000001'::uuid,
      null,
      '97200000-0000-4000-8000-000000000005'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_NOT_FOUND',
  'other-organization Admin cannot acknowledge this notification'
);

select throws_ok(
  $sql$
    select api.set_notification_read_state(
      '95200000-0000-4000-8000-000000000001'::uuid,
      'READ'
    )
  $sql$,
  'P0001',
  'NOTIFICATION_NOT_FOUND',
  'other-organization Admin cannot create presentation state'
);

reset role;

-- 63: source evaluator resolution remains authoritative
select lives_ok(
  $sql$
    select notification.resolve_notification(
      p_organization_id =>
        '00000000-0000-4000-8000-000000000001'::uuid,
      p_notification_id =>
        '95200000-0000-4000-8000-000000000001'::uuid,
      p_resolution_code => 'SOURCE_CONDITION_CLEARED',
      p_resolution_snapshot => '{"riskQty":0}'::jsonb,
      p_resolved_at =>
        '2026-07-16 21:05:00+07'::timestamptz,
      p_correlation_id =>
        '97200000-0000-4000-8000-000000000006'::uuid,
      p_process_name => 'pgtap.notification_admin_commands'
    )
  $sql$,
  'source evaluator may still resolve the unacknowledged notification'
);

-- Admin One on a resolved notification
select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000001',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

-- 64: resolved lifecycle cannot be acknowledged
select throws_ok(
  $sql$
    select api.acknowledge_notification(
      '95200000-0000-4000-8000-000000000001'::uuid,
      null,
      '97200000-0000-4000-8000-000000000007'::uuid
    )
  $sql$,
  'P0001',
  'NOTIFICATION_ALREADY_RESOLVED',
  'resolved notification cannot return to ACKNOWLEDGED'
);

-- 65: presentation state remains independent after resolution
select is(
  (
    api.set_notification_read_state(
      '95200000-0000-4000-8000-000000000001'::uuid,
      'READ'
    ) ->> 'action'
  ),
  'SET_READ',
  'resolved notification may still be marked READ by its Admin'
);

reset role;

-- Regression: non-Critical acknowledgment note remains optional.
insert into notification.notifications (
  id,
  organization_id,
  rule_id,
  rule_code_snapshot,
  rule_version_snapshot,
  template_version_snapshot,
  notification_type_code,
  category_code,
  entity_type_code,
  entity_id,
  episode_no,
  previous_notification_id,
  deduplication_key,
  deduplication_hash,
  lifecycle_status_code,
  stage_code,
  severity_code,
  title,
  message,
  action_code,
  action_route,
  condition_started_at,
  due_at,
  first_seen_at,
  last_seen_at,
  occurrence_count,
  source_snapshot,
  config_snapshot,
  created_at,
  updated_at,
  version_no
)
values (
  '95200000-0000-4000-8000-000000000002'::uuid,
  '00000000-0000-4000-8000-000000000001'::uuid,
  '80000000-0000-4000-8000-000000000001'::uuid,
  'EXPIRY_RISK',
  '1.0.0',
  '1.0.0',
  'EXPIRY_RISK',
  'EXPIRY',
  'PRODUCT_BATCH',
  '40000000-0000-4000-8000-000000000002'::uuid,
  1,
  null,
  'expiry_risk:product_batch:40000000-0000-4000-8000-000000000002:high-note-optional',
  repeat('f', 64),
  'OPEN',
  'D30',
  'HIGH',
  'Batch berisiko kedaluwarsa',
  'Batch High tetap boleh di-acknowledge tanpa catatan.',
  'OPEN_BATCH_EXPIRY_DETAIL',
  '/?batchId=40000000-0000-4000-8000-000000000002#batch-40000000-0000-4000-8000-000000000002',
  '2026-07-16 21:10:00+07'::timestamptz,
  '2026-08-01 23:59:59+07'::timestamptz,
  '2026-07-16 21:10:00+07'::timestamptz,
  '2026-07-16 21:10:00+07'::timestamptz,
  1,
  '{"riskQty":3,"daysRemaining":16}'::jsonb,
  '{"thresholdDays":[90,60,30,0]}'::jsonb,
  '2026-07-16 21:10:00+07'::timestamptz,
  '2026-07-16 21:10:00+07'::timestamptz,
  1
);

select set_config(
  'request.jwt.claim.sub',
  '94200000-0000-4000-8000-000000000001',
  true
);

select set_config(
  'request.jwt.claim.role',
  'authenticated',
  true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '94200000-0000-4000-8000-000000000001',
    'role',
    'authenticated'
  )::text,
  true
);

set local role authenticated;

select is(
  (
    api.acknowledge_notification(
      '95200000-0000-4000-8000-000000000002'::uuid,
      null,
      '97200000-0000-4000-8000-000000000012'::uuid
    ) ->> 'action'
  ),
  'ACKNOWLEDGED',
  'High notification may be acknowledged without a note'
);

reset role;

select ok(
  (
    select acknowledgment_note is null
    from notification.notifications
    where id =
      '95200000-0000-4000-8000-000000000002'::uuid
  ),
  'High acknowledgment persists a null optional note'
);

select * from finish();
rollback;
