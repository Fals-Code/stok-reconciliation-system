-- Close the internal state-transition helper to every external role.
revoke execute on function catalog.change_promo_reference_active_state(
  uuid, text, uuid, bigint, boolean, text, text
) from public, anon, authenticated, service_role;

-- api.archive_promo_reference and api.reactivate_promo_reference retain
-- their explicit grants from the original migration and call this helper internally.
