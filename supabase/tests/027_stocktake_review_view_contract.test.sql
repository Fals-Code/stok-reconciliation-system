begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

select has_view(
  'api'::name,
  'stocktake_review_lines'::name,
  'api.stocktake_review_lines exists'
);

select has_column(
  'api'::name,
  'stocktake_review_lines'::name,
  'review_decision_code'::name,
  'review view exposes the stored review decision'
);

select col_type_is(
  'api'::name,
  'stocktake_review_lines'::name,
  'review_decision_code'::name,
  'text'::name
);

select has_column(
  'api'::name,
  'stocktake_review_lines'::name,
  'review_status_code'::name,
  'review view preserves review status'
);

select has_column(
  'api'::name,
  'stocktake_review_lines'::name,
  'reason_code'::name,
  'review view preserves the variance reason'
);

select ok(
  has_table_privilege(
    'authenticated',
    'api.stocktake_review_lines',
    'SELECT'
  ),
  'authenticated users may read review lines'
);

select ok(
  not has_table_privilege(
    'anon',
    'api.stocktake_review_lines',
    'SELECT'
  ),
  'anonymous users cannot read review lines'
);

select * from finish();

rollback;