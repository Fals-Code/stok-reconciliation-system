begin;

-- The claim API views are the authenticated read boundary.  Migration 019
-- revoked direct table access, so SECURITY INVOKER made those views unusable.
-- Their predicates remain organization-scoped through app.current_organization_id().
alter view api.return_claim_master set (security_invoker = false);
alter view api.return_claim_items set (security_invoker = false);
alter view api.return_claim_events set (security_invoker = false);

commit;
