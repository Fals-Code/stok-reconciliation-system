begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

select has_view('api'::name, 'current_admin_profile'::name);
select has_function(
  'api'::name,
  'bootstrap_demo_admin'::name,
  array['uuid', 'text', 'text']::text[]
);
select ok(
  has_table_privilege('authenticated', 'api.current_admin_profile', 'SELECT'),
  'authenticated users can read their current admin profile'
);
select ok(
  not has_table_privilege('anon', 'api.current_admin_profile', 'SELECT'),
  'anonymous users cannot read admin profiles'
);
select ok(
  has_function_privilege(
    'service_role',
    'api.bootstrap_demo_admin(uuid,text,text)',
    'EXECUTE'
  ),
  'service role can bootstrap the local demo admin'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'api.bootstrap_demo_admin(uuid,text,text)',
    'EXECUTE'
  ),
  'authenticated users cannot bootstrap admin profiles'
);
select ok(
  not has_function_privilege(
    'anon',
    'api.bootstrap_demo_admin(uuid,text,text)',
    'EXECUTE'
  ),
  'anonymous users cannot bootstrap admin profiles'
);
select ok(
  not has_table_privilege('authenticated', 'app.user_profiles', 'INSERT'),
  'authenticated users cannot insert their own admin profile'
);
select is(
  (select count(*) from api.current_admin_profile),
  0::bigint,
  'profile view returns no row without an authenticated JWT'
);
select throws_ok(
  $$select api.bootstrap_demo_admin(null, 'demo.admin@glowlab.invalid', 'Demo Admin')$$,
  'P0001',
  'ADMIN_USER_ID_REQUIRED',
  'bootstrap requires a user id'
);
select throws_ok(
  $$select api.bootstrap_demo_admin(
    '99999999-9999-4999-8999-999999999999'::uuid,
    '',
    'Demo Admin'
  )$$,
  'P0001',
  'ADMIN_EMAIL_REQUIRED',
  'bootstrap requires an email address'
);
select throws_ok(
  $$select api.bootstrap_demo_admin(
    '99999999-9999-4999-8999-999999999999'::uuid,
    'missing.user@glowlab.invalid',
    'Demo Admin'
  )$$,
  'P0001',
  'AUTH_USER_NOT_FOUND',
  'bootstrap rejects unknown auth users'
);

select * from finish();
rollback;
