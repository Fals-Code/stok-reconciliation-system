begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

select has_schema('reconciliation');

select has_table('reconciliation'::name, 'runs'::name);
select has_table('reconciliation'::name, 'run_checks'::name);
select has_table('reconciliation'::name, 'issues'::name);
select has_table('reconciliation'::name, 'issue_evidence'::name);

select has_view('api'::name, 'reconciliation_runs'::name);
select has_view('api'::name, 'reconciliation_checks'::name);
select has_view('api'::name, 'reconciliation_issues'::name);
select has_view('api'::name, 'reconciliation_issue_evidence'::name);

select col_is_pk('reconciliation'::name, 'runs'::name, 'id'::name);
select col_is_pk('reconciliation'::name, 'run_checks'::name, 'id'::name);
select col_is_pk('reconciliation'::name, 'issues'::name, 'id'::name);
select col_is_pk('reconciliation'::name, 'issue_evidence'::name, 'id'::name);

select has_index(
  'reconciliation'::name,
  'runs'::name,
  'idx_reconciliation_runs_status'::name
);

select has_index(
  'reconciliation'::name,
  'run_checks'::name,
  'idx_reconciliation_run_checks_run_status'::name
);

select has_index(
  'reconciliation'::name,
  'issues'::name,
  'idx_reconciliation_issues_open'::name
);

select has_index(
  'reconciliation'::name,
  'issue_evidence'::name,
  'idx_reconciliation_issue_evidence_issue'::name
);

select policies_are(
  'reconciliation',
  'runs',
  array['reconciliation_runs_read_current_org']
);

select policies_are(
  'reconciliation',
  'run_checks',
  array['reconciliation_run_checks_read_current_org']
);

select policies_are(
  'reconciliation',
  'issues',
  array['reconciliation_issues_read_current_org']
);

select policies_are(
  'reconciliation',
  'issue_evidence',
  array['reconciliation_issue_evidence_read_current_org']
);

select ok(
  not has_table_privilege(
    'authenticated',
    'reconciliation.runs',
    'INSERT'
  ),
  'authenticated users cannot insert reconciliation runs directly'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'reconciliation.issues',
    'UPDATE'
  ),
  'authenticated users cannot update reconciliation issues directly'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'reconciliation.issue_evidence',
    'DELETE'
  ),
  'authenticated users cannot delete reconciliation evidence directly'
);

select has_trigger(
  'reconciliation'::name,
  'runs'::name,
  'trg_reconciliation_runs_touch_updated_at'::name
);

select has_trigger(
  'reconciliation'::name,
  'run_checks'::name,
  'trg_reconciliation_run_checks_touch_updated_at'::name
);

select has_trigger(
  'reconciliation'::name,
  'issues'::name,
  'trg_reconciliation_issues_touch_updated_at'::name
);

select has_trigger(
  'reconciliation'::name,
  'issue_evidence'::name,
  'trg_reconciliation_issue_evidence_immutable'::name
);

select ok(
  exists (
    select 1
    from pg_constraint constraint_record
    join pg_class relation
      on relation.oid = constraint_record.conrelid
    join pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'reconciliation'
      and relation.relname = 'issue_evidence'
      and constraint_record.conname =
        'fk_reconciliation_issue_evidence_check'
      and position(
        'FOREIGN KEY (organization_id, run_id, run_check_id)'
        in pg_get_constraintdef(constraint_record.oid)
      ) > 0
      and position(
        'REFERENCES reconciliation.run_checks(organization_id, run_id, id)'
        in pg_get_constraintdef(constraint_record.oid)
      ) > 0
  ),
  'issue evidence must reference a check from the same run'
);

select * from finish();

rollback;