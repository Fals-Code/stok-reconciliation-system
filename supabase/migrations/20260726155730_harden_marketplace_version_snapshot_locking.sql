begin;

-- A version lifecycle and a canonical reservation share this lock.  The key is
-- deliberately the marketplace listing identity, not an adapter event key.
create or replace function operations.lock_marketplace_listing_identity(
  p_organization_id uuid,
  p_channel_id uuid,
  p_external_listing_code text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, operations
as $$
declare
  v_external_listing_code text := btrim(coalesce(p_external_listing_code, ''));
begin
  if p_organization_id is null or p_channel_id is null then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_LISTING_IDENTITY_REQUIRED';
  end if;

  if v_external_listing_code = '' or length(v_external_listing_code) > 200 then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_LISTING_CODE_INVALID';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_organization_id::text
        || ':MARKETPLACE_LISTING_IDENTITY:'
        || p_channel_id::text
        || ':'
        || v_external_listing_code,
      0::bigint
    )
  );
end;
$$;

create or replace function operations.lock_marketplace_listing_identity_by_listing_id(
  p_organization_id uuid,
  p_listing_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, catalog, operations
as $$
declare
  v_channel_id uuid;
  v_external_listing_code text;
begin
  if p_organization_id is null or p_listing_id is null then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_LISTING_IDENTITY_REQUIRED';
  end if;

  select listing.channel_id, listing.external_listing_code
  into v_channel_id, v_external_listing_code
  from catalog.marketplace_listings listing
  where listing.organization_id = p_organization_id
    and listing.id = p_listing_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_LISTING_NOT_FOUND';
  end if;

  perform operations.lock_marketplace_listing_identity(
    p_organization_id,
    v_channel_id,
    v_external_listing_code
  );
end;
$$;

revoke all on function operations.lock_marketplace_listing_identity(uuid, uuid, text)
from public, anon, authenticated, service_role;

revoke all on function operations.lock_marketplace_listing_identity_by_listing_id(uuid, uuid)
from public, anon, authenticated, service_role;

alter function operations.resolve_marketplace_listing_expansion(
  uuid,
  text,
  text,
  bigint,
  timestamptz
) rename to resolve_marketplace_listing_expansion_apply;

revoke all on function operations.resolve_marketplace_listing_expansion_apply(
  uuid,
  text,
  text,
  bigint,
  timestamptz
) from public, anon, authenticated, service_role;

create or replace function operations.resolve_marketplace_listing_expansion(
  p_organization_id uuid,
  p_channel_code text,
  p_external_listing_code text,
  p_listing_quantity bigint,
  p_occurred_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, catalog, operations, extensions
as $$
declare
  v_channel_id uuid;
  v_channel_code text := upper(btrim(coalesce(p_channel_code, '')));
  v_external_listing_code text := btrim(coalesce(p_external_listing_code, ''));
begin
  if p_organization_id is null then
    raise exception using errcode = 'P0001', message = 'ORGANIZATION_REQUIRED';
  end if;

  if v_channel_code = '' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_CHANNEL_REQUIRED';
  end if;

  if v_external_listing_code = '' then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_LISTING_CODE_REQUIRED';
  end if;

  if length(v_external_listing_code) > 200 then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_LISTING_CODE_TOO_LONG';
  end if;

  select channel.id
  into v_channel_id
  from catalog.channels channel
  where channel.code = v_channel_code
    and channel.is_marketplace
    and channel.is_active;

  if not found then
    raise exception using errcode = 'P0001', message = 'MARKETPLACE_LISTING_CHANNEL_NOT_ALLOWED';
  end if;

  -- Canonical reserve already holds the external-event lock.  This second,
  -- listing-identity lock serializes any effective-window transition before
  -- the immutable expansion is selected by p_occurred_at.
  perform operations.lock_marketplace_listing_identity(
    p_organization_id,
    v_channel_id,
    v_external_listing_code
  );

  return operations.resolve_marketplace_listing_expansion_apply(
    p_organization_id,
    v_channel_code,
    v_external_listing_code,
    p_listing_quantity,
    p_occurred_at
  );
end;
$$;

revoke all on function operations.resolve_marketplace_listing_expansion(
  uuid,
  text,
  text,
  bigint,
  timestamptz
) from public, anon, authenticated, service_role;

alter function api.activate_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  text,
  boolean
) rename to activate_marketplace_listing_version_apply;

revoke all on function api.activate_marketplace_listing_version_apply(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  text,
  boolean
) from public, anon, authenticated, service_role;

create or replace function api.activate_marketplace_listing_version(
  p_organization_id uuid,
  p_idempotency_key text,
  p_listing_id uuid,
  p_version_id uuid,
  p_expected_row_version bigint,
  p_preview_basis_hash text,
  p_confirmation boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, api, extensions
as $$
begin
  perform operations.assert_marketplace_adapter_access(p_organization_id);
  perform operations.lock_marketplace_listing_identity_by_listing_id(
    p_organization_id,
    p_listing_id
  );

  return api.activate_marketplace_listing_version_apply(
    p_organization_id,
    p_idempotency_key,
    p_listing_id,
    p_version_id,
    p_expected_row_version,
    p_preview_basis_hash,
    p_confirmation
  );
end;
$$;

revoke all on function api.activate_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  text,
  boolean
) from public, anon;

grant execute on function api.activate_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  text,
  boolean
) to authenticated, service_role;

alter function api.retire_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz,
  boolean
) rename to retire_marketplace_listing_version_apply;

revoke all on function api.retire_marketplace_listing_version_apply(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz,
  boolean
) from public, anon, authenticated, service_role;

create or replace function api.retire_marketplace_listing_version(
  p_organization_id uuid,
  p_idempotency_key text,
  p_listing_id uuid,
  p_version_id uuid,
  p_expected_row_version bigint,
  p_effective_to timestamptz,
  p_confirmation boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, api, extensions
as $$
begin
  perform operations.assert_marketplace_adapter_access(p_organization_id);
  perform operations.lock_marketplace_listing_identity_by_listing_id(
    p_organization_id,
    p_listing_id
  );

  return api.retire_marketplace_listing_version_apply(
    p_organization_id,
    p_idempotency_key,
    p_listing_id,
    p_version_id,
    p_expected_row_version,
    p_effective_to,
    p_confirmation
  );
end;
$$;

revoke all on function api.retire_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz,
  boolean
) from public, anon;

grant execute on function api.retire_marketplace_listing_version(
  uuid,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz,
  boolean
) to authenticated, service_role;

alter function api.archive_marketplace_listing(
  uuid,
  text,
  uuid,
  bigint,
  boolean
) rename to archive_marketplace_listing_apply;

revoke all on function api.archive_marketplace_listing_apply(
  uuid,
  text,
  uuid,
  bigint,
  boolean
) from public, anon, authenticated, service_role;

create or replace function api.archive_marketplace_listing(
  p_organization_id uuid,
  p_idempotency_key text,
  p_listing_id uuid,
  p_expected_row_version bigint,
  p_confirmation boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, app, catalog, inventory, operations, api, extensions
as $$
begin
  perform operations.assert_marketplace_adapter_access(p_organization_id);
  perform operations.lock_marketplace_listing_identity_by_listing_id(
    p_organization_id,
    p_listing_id
  );

  return api.archive_marketplace_listing_apply(
    p_organization_id,
    p_idempotency_key,
    p_listing_id,
    p_expected_row_version,
    p_confirmation
  );
end;
$$;

revoke all on function api.archive_marketplace_listing(
  uuid,
  text,
  uuid,
  bigint,
  boolean
) from public, anon;

grant execute on function api.archive_marketplace_listing(
  uuid,
  text,
  uuid,
  bigint,
  boolean
) to authenticated, service_role;

comment on function operations.lock_marketplace_listing_identity(uuid, uuid, text) is
  'Internal transaction lock for a marketplace listing identity. Canonical reservation and listing lifecycle mutations must hold it before resolving or changing an effective version window.';

comment on function operations.resolve_marketplace_listing_expansion(uuid, text, text, bigint, timestamptz) is
  'Resolves exactly one historical listing or recipe version by occurred_at after taking the shared listing identity lock. The returned expansion is persisted as an immutable canonical snapshot.';

commit;
