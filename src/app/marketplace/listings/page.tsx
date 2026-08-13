import { randomUUID } from "node:crypto";
import Link from "next/link";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import MarketplaceListingDraftForm from "@/app/marketplace/listings/components/listing-draft-form";
import {
  Alert,
  Input,
  Select,
  StatusBadge,
  type StatusBadgeTone,
} from "@/components/ui";
import {
  activateMarketplaceListingVersionAction,
  archiveMarketplaceListingAction,
  retireMarketplaceListingVersionAction,
} from "@/app/marketplace/listings/actions";
import {
  getMarketplaceListingAdminData,
  previewMarketplaceListingVersionActivation,
  type MarketplaceListingActivationPreview,
  type MarketplaceListingCatalogRow,
  type MarketplaceListingVersionRow,
} from "@/lib/supabase-rest";
import { requireAdminSession } from "@/lib/auth";

export const dynamic = "force-dynamic";

type SearchParams = {
  success?: string;
  error?: string;
  q?: string;
  channel?: string;
  type?: string;
  status?: string;
  selectedListingId?: string;
  selectedVersionId?: string;
  previewListingId?: string;
  previewVersionId?: string;
  cloneListingId?: string;
  sampleQuantity?: string;
};

type PillTone = StatusBadgeTone;

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number) {
  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null, includeTime = false) {
  if (!value) return "—";

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
    ...(includeTime
      ? { hour: "2-digit", minute: "2-digit", hour12: false }
      : {}),
  }).format(new Date(value));
}

function toDateTimeLocal(value: string | Date) {
  const resolved = value instanceof Date ? value : new Date(value);
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(resolved);
  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );

  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

function Pill({
  label,
  tone = "neutral",
}: {
  label: string;
  tone?: PillTone;
}) {
  return (
    <StatusBadge tone={tone}>
      {label}
    </StatusBadge>
  );
}

function listingReadinessLabel(value: string) {
  if (value === "PUBLISHED") return "Siap dipakai";
  if (value === "DRAFT_ONLY") return "Draft";
  if (value === "MISSING") return "Belum dipetakan";
  return value;
}

function versionStatusLabel(value: string) {
  if (value === "ACTIVE") return "Aktif";
  if (value === "DRAFT") return "Draft";
  if (value === "RETIRED") return "Dihentikan";
  return value;
}

function listingTone(listing: MarketplaceListingCatalogRow): PillTone {
  if (listing.status_code === "ARCHIVED") return "danger";
  if (listing.mapping_readiness_code === "PUBLISHED") return "selected";
  if (listing.mapping_readiness_code === "DRAFT_ONLY") return "warning";
  return "neutral";
}

function versionTone(version: MarketplaceListingVersionRow): PillTone {
  if (version.status_code === "ACTIVE") return "selected";
  if (version.status_code === "DRAFT") return "warning";
  if (version.status_code === "RETIRED") return "neutral";
  return "danger";
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <div className="mx-auto w-full max-w-[1000px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <PageHeader
        description="Mapping produk marketplace tidak dapat dimuat saat ini."
        eyebrow="Pengaturan"
        title="Mapping Produk Marketplace"
      />

      <Alert
        className="mt-6"
        title="Data mapping belum dapat dimuat"
        tone="danger"
      >
        {message}
      </Alert>

      <Link
        className="mt-5 inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
        href="/settings"
      >
        ← Kembali ke Pengaturan
      </Link>
    </div>
  );
}

function listingMatchesStatus(
  listing: MarketplaceListingCatalogRow,
  status: string,
) {
  if (status === "ALL") return true;
  if (status === "ACTIVE" || status === "ARCHIVED") {
    return listing.status_code === status;
  }

  return listing.mapping_readiness_code === status;
}

export default async function MarketplaceListingsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [params, session] = await Promise.all([
    searchParams,
    requireAdminSession(),
  ]);
  let data;

  try {
    data = await getMarketplaceListingAdminData();
  } catch (error) {
    return (
      <AppShell profile={session.profile}>
        <ConfigurationError
          message={
            error instanceof Error ? error.message : "Konfigurasi tidak valid."
          }
        />
      </AppShell>
    );
  }

  const {
    listings,
    versions,
    bundleComponents,
    products,
    normalizations,
  } = data;

  const query = params.q?.trim().toLowerCase() ?? "";
  const channel = params.channel?.trim().toUpperCase() || "ALL";
  const listingType = params.type?.trim().toUpperCase() || "ALL";
  const status = params.status?.trim().toUpperCase() || "ALL";

  const filteredListings = listings.filter((listing) => {
    const searchValue =
      `${listing.channel_code} ${listing.external_listing_code} ${listing.display_name}`.toLowerCase();

    return (
      (!query || searchValue.includes(query)) &&
      (channel === "ALL" || listing.channel_code === channel) &&
      (listingType === "ALL" ||
        listing.listing_type_code === listingType) &&
      listingMatchesStatus(listing, status)
    );
  });

  const selectedListing =
    listings.find(
      (listing) => listing.listing_id === params.selectedListingId,
    ) ??
    listings.find(
      (listing) => listing.listing_id === params.previewListingId,
    ) ??
    null;

  const listingVersions = selectedListing
    ? versions
        .filter(
          (version) => version.listing_id === selectedListing.listing_id,
        )
        .sort((left, right) => right.version - left.version)
    : [];

  const selectedVersion =
    listingVersions.find(
      (version) => version.version_id === params.selectedVersionId,
    ) ??
    listingVersions.find(
      (version) => version.version_id === params.previewVersionId,
    ) ??
    listingVersions[0] ??
    null;

  const selectedComponents =
    selectedVersion?.listing_type_code === "BUNDLE"
      ? bundleComponents.filter(
          (component) =>
            component.version_id === selectedVersion.version_id,
        )
      : [];

  const usageByVersion = new Map<string, Set<string>>();
  for (const row of normalizations) {
    const key = `${row.listing_id}:${row.mapping_version}`;
    const orderIds = usageByVersion.get(key) ?? new Set<string>();
    orderIds.add(row.order_id);
    usageByVersion.set(key, orderIds);
  }

  const cloneListing =
    listings.find(
      (listing) => listing.listing_id === params.cloneListingId,
    ) ?? null;
  const cloneVersions = cloneListing
    ? versions
        .filter(
          (version) => version.listing_id === cloneListing.listing_id,
        )
        .sort((left, right) => right.version - left.version)
    : [];
  const cloneVersion =
    cloneVersions.find((version) => version.status_code === "ACTIVE") ??
    cloneVersions[0] ??
    null;
  const cloneComponents =
    cloneVersion?.listing_type_code === "BUNDLE"
      ? bundleComponents
          .filter(
            (component) =>
              component.version_id === cloneVersion.version_id,
          )
          .map((component) => ({
            productId: component.product_id,
            quantity: Number(component.component_qty),
          }))
      : [];

  const createInitial = cloneListing
    ? {
        channelCode: cloneListing.channel_code,
        externalListingCode: cloneListing.external_listing_code,
        displayName: `${cloneListing.display_name} V${
          (cloneVersions[0]?.version ?? 0) + 1
        }`,
        listingTypeCode: cloneListing.listing_type_code,
        effectiveFrom: "",
        productId: cloneVersion?.product_id ?? "",
        components: cloneComponents,
        note: "Versi mapping baru.",
      }
    : {
        channelCode: "SHOPEE" as const,
        externalListingCode: "",
        displayName: "",
        listingTypeCode: "SINGLE" as const,
        effectiveFrom: "",
        productId: "",
        components: [],
        note: "",
      };

  let activationPreview: MarketplaceListingActivationPreview | null = null;
  let previewError: string | null = null;

  if (params.previewListingId && params.previewVersionId) {
    try {
      activationPreview =
        await previewMarketplaceListingVersionActivation({
          listingId: params.previewListingId,
          versionId: params.previewVersionId,
        });
    } catch (error) {
      previewError =
        error instanceof Error ? error.message : "Preview gagal dimuat.";
    }
  }

  const sampleQuantityRaw = Number(params.sampleQuantity ?? 1);
  const sampleQuantity =
    Number.isSafeInteger(sampleQuantityRaw) &&
    sampleQuantityRaw > 0 &&
    sampleQuantityRaw <= 999_999
      ? sampleQuantityRaw
      : 1;

  const activeCount = listings.filter(
    (listing) => listing.status_code === "ACTIVE",
  ).length;
  const publishedCount = listings.filter(
    (listing) => listing.mapping_readiness_code === "PUBLISHED",
  ).length;
  const draftCount = versions.filter(
    (version) => version.status_code === "DRAFT",
  ).length;
  const archivedCount = listings.filter(
    (listing) => listing.status_code === "ARCHIVED",
  ).length;

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1300px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <section>
          <PageHeader
            action={
              <div className="flex flex-wrap justify-end gap-2">
                <Link
                  className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text hover:border-ui-border-strong hover:bg-ui-surface-subtle"
                  href="/marketplace"
                >
                  Kembali ke Pesanan
                </Link>
                <Link
                  className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
                  href="#listing-draft"
                >
                  Buat mapping
                </Link>
              </div>
            }
            description="Hubungkan listing marketplace ke produk stok. Setiap perubahan disimpan sebagai versi sehingga pesanan lama tetap memakai mapping yang berlaku saat diproses."
            eyebrow="Pengaturan"
            title="Mapping Produk Marketplace"
          />

          <div className="mt-4">
            <Link
              className="inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
              href="/settings"
            >
              ← Kembali ke Pengaturan
            </Link>
          </div>

          <dl className="mt-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            {[
              ["Listing aktif", activeCount, "Masih dapat digunakan"],
              ["Siap dipakai", publishedCount, "Mapping aktif tersedia"],
              ["Draft", draftCount, "Belum dipakai pesanan baru"],
              ["Diarsipkan", archivedCount, "Histori tetap tersimpan"],
            ].map(([label, value, detail]) => (
              <div
                className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4"
                key={String(label)}
              >
                <dt className="text-xs font-medium text-ui-text-muted">
                  {label}
                </dt>
                <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                  {formatNumber(Number(value))}
                </dd>
                <p className="mt-1 text-xs leading-5 text-ui-text-muted">
                  {detail}
                </p>
              </div>
            ))}
          </dl>
        </section>

        {params.success ? (
          <Alert
            className="mt-8"
            title="Perubahan tersimpan"
            tone="success"
          >
            {params.success}
          </Alert>
        ) : null}

        {params.error ? (
          <Alert
            className="mt-8"
            title="Perubahan belum tersimpan"
            tone="danger"
          >
            {params.error}
          </Alert>
        ) : null}

        <section className="mt-10" id="listing-draft">
          <MarketplaceListingDraftForm
            initial={createInitial}
            intentId={randomUUID()}
            lockedIdentity={Boolean(cloneListing)}
            mode="create"
            products={products}
          />
        </section>

        <section className="mt-10" id="listing-catalog">
          <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 sm:p-6">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">Daftar listing</p>
                <h2 className="mt-1 text-lg font-semibold text-ui-text">Cari dan periksa listing</h2>
              </div>

              <form className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
                <Input
                  aria-label="Cari listing"
                  defaultValue={params.q}
                  name="q"
                  placeholder="Cari kode atau nama listing"
                />
                <Select
                  aria-label="Filter marketplace"
                  defaultValue={channel}
                  name="channel"
                >
                  <option value="ALL">Semua marketplace</option>
                  <option value="SHOPEE">Shopee</option>
                  <option value="TIKTOK_SHOP">TikTok Shop</option>
                </Select>
                <Select
                  aria-label="Filter jenis listing"
                  defaultValue={listingType}
                  name="type"
                >
                  <option value="ALL">Semua jenis</option>
                  <option value="SINGLE">Produk tunggal</option>
                  <option value="BUNDLE">Bundle</option>
                </Select>
                <Select
                  aria-label="Filter status mapping"
                  defaultValue={status}
                  name="status"
                >
                  <option value="ALL">Semua status</option>
                  <option value="PUBLISHED">Siap dipakai</option>
                  <option value="DRAFT_ONLY">Draft</option>
                  <option value="MISSING">Belum dipetakan</option>
                  <option value="ARCHIVED">Diarsipkan</option>
                </Select>
                <button
                  className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
                  type="submit"
                >
                  Terapkan filter
                </button>
              </form>
            </div>

            <div className="mt-6 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border">
              <div className="overflow-x-auto [&_table]:w-full [&_table]:min-w-[760px] [&_table]:text-left [&_table]:text-sm [&_thead]:border-b [&_thead]:border-ui-border [&_thead]:bg-ui-surface-subtle [&_th]:px-4 [&_th]:py-3 [&_th]:text-xs [&_th]:font-semibold [&_th]:uppercase [&_th]:tracking-wide [&_th]:text-ui-text-muted [&_td]:px-4 [&_td]:py-4 [&_tbody]:divide-y [&_tbody]:divide-ui-border">
                <table>
                  <thead>
                    <tr>
                      <th>Listing</th>
                      <th>Jenis</th>
                      <th>Status</th>
                      <th>Versi saat ini</th>
                      <th>Draft</th>
                      <th>Diperbarui</th>
                      <th>Tindakan</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredListings.length === 0 ? (
                      <tr>
                        <td className="text-center text-ui-text-muted" colSpan={7}>
                          Tidak ada listing yang cocok dengan filter.
                        </td>
                      </tr>
                    ) : (
                      filteredListings.map((listing) => (
                        <tr key={listing.listing_id}>
                          <td>
                            <p className="font-medium text-ui-text">
                              {listing.display_name}
                            </p>
                            <p className="mt-1 font-mono text-xs text-ui-text-muted">
                              {listing.channel_code} /{" "}
                              {listing.external_listing_code}
                            </p>
                          </td>
                          <td>{listing.listing_type_code}</td>
                          <td>
                            <Pill
                              label={listingReadinessLabel(listing.mapping_readiness_code)}
                              tone={listingTone(listing)}
                            />
                          </td>
                          <td>
                            {listing.current_version
                              ? `v${listing.current_version}`
                              : "—"}
                          </td>
                          <td>{formatNumber(listing.draft_version_count)}</td>
                          <td>{formatDate(listing.updated_at, true)}</td>
                          <td>
                            <Link
                              className="inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
                              href={`/marketplace/listings?selectedListingId=${encodeURIComponent(
                                listing.listing_id,
                              )}#version-detail`}
                            >
                              Buka
                            </Link>
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </section>

        {selectedListing ? (
          <section className="mt-10" id="version-detail">
            <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 sm:p-6">
              <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">Detail listing</p>
                  <h2 className="mt-1 text-lg font-semibold text-ui-text">
                    {selectedListing.display_name}
                  </h2>
                  <p className="mt-2 text-xs text-ui-text-muted">
                    {selectedListing.channel_code} /{" "}
                    {selectedListing.external_listing_code} /{" "}
                    {selectedListing.listing_type_code}
                  </p>
                  {selectedListing.status_code === "ARCHIVED" ? (
                    <p className="mt-2 text-xs font-semibold text-ui-danger">
                      Diarsipkan · kode audit ARCHIVED
                    </p>
                  ) : null}
                </div>
                <div className="flex flex-wrap gap-2">
                  <Pill
                    label={listingReadinessLabel(selectedListing.mapping_readiness_code)}
                    tone={listingTone(selectedListing)}
                  />
                  {selectedListing.status_code !== "ARCHIVED" ? (
                    <Link
                      className="inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
                      href={`/marketplace/listings?cloneListingId=${encodeURIComponent(
                        selectedListing.listing_id,
                      )}#listing-draft`}
                    >
                      Buat versi baru
                    </Link>
                  ) : null}
                </div>
              </div>

              <div className="mt-6 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border">
                <div className="overflow-x-auto [&_table]:w-full [&_table]:min-w-[760px] [&_table]:text-left [&_table]:text-sm [&_thead]:border-b [&_thead]:border-ui-border [&_thead]:bg-ui-surface-subtle [&_th]:px-4 [&_th]:py-3 [&_th]:text-xs [&_th]:font-semibold [&_th]:uppercase [&_th]:tracking-wide [&_th]:text-ui-text-muted [&_td]:px-4 [&_td]:py-4 [&_tbody]:divide-y [&_tbody]:divide-ui-border">
                  <table>
                    <thead>
                      <tr>
                        <th>Versi</th>
                        <th>Status</th>
                        <th>Efektif</th>
                        <th>Komponen</th>
                        <th>Pesanan memakai versi</th>
                        <th>Versi data</th>
                        <th>Tindakan</th>
                      </tr>
                    </thead>
                    <tbody>
                      {listingVersions.length === 0 ? (
                        <tr>
                          <td colSpan={7}>Belum ada versi mapping.</td>
                        </tr>
                      ) : (
                        listingVersions.map((version) => {
                          const usageCount =
                            usageByVersion.get(
                              `${version.listing_id}:${version.version}`,
                            )?.size ?? 0;

                          return (
                            <tr key={version.version_id}>
                              <td className="font-mono text-ui-text">
                                v{version.version}
                              </td>
                              <td>
                                <Pill
                                  label={versionStatusLabel(version.status_code)}
                                  tone={versionTone(version)}
                                />
                              </td>
                              <td>
                                {formatDate(version.effective_from, true)}
                                <span className="block text-xs text-ui-text-muted">
                                  sampai{" "}
                                  {formatDate(version.effective_to, true)}
                                </span>
                              </td>
                              <td>{formatNumber(version.component_count)}</td>
                              <td>{formatNumber(usageCount)}</td>
                              <td>{formatNumber(version.row_version)}</td>
                              <td>
                                <div className="flex flex-wrap gap-2">
                                  <Link
                                    className="inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
                                    href={`/marketplace/listings?selectedListingId=${encodeURIComponent(
                                      version.listing_id,
                                    )}&selectedVersionId=${encodeURIComponent(
                                      version.version_id,
                                    )}#version-detail`}
                                  >
                                    Detail
                                  </Link>
                                  {version.status_code === "DRAFT" ? (
                                    <Link
                                      className="inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
                                      href={`/marketplace/listings?selectedListingId=${encodeURIComponent(
                                        version.listing_id,
                                      )}&selectedVersionId=${encodeURIComponent(
                                        version.version_id,
                                      )}&previewListingId=${encodeURIComponent(
                                        version.listing_id,
                                      )}&previewVersionId=${encodeURIComponent(
                                        version.version_id,
                                      )}#activation-preview`}
                                    >
                                      Preview aktivasi
                                    </Link>
                                  ) : null}
                                </div>
                              </td>
                            </tr>
                          );
                        })
                      )}
                    </tbody>
                  </table>
                </div>
              </div>

              {selectedListing.status_code !== "ARCHIVED" ? (
                <form
                  action={archiveMarketplaceListingAction}
                  className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-danger bg-ui-danger-subtle p-5"
                >
                  <input
                    name="intentId"
                    type="hidden"
                    value={randomUUID()}
                  />
                  <input
                    name="listingId"
                    type="hidden"
                    value={selectedListing.listing_id}
                  />
                  <input
                    name="expectedRowVersion"
                    type="hidden"
                    value={selectedListing.row_version}
                  />
                  <p className="font-medium text-ui-text">Arsipkan listing</p>
                  <p className="mt-2 text-sm leading-6 text-ui-text-muted">
                    Listing yang diarsipkan tidak dipakai untuk pesanan baru. Order lama,
                    versi, komponen, dan audit trail tidak dihapus.
                  </p>
                  <label className="mt-4 flex items-start gap-3 text-sm text-ui-text">
                    <input name="confirmation" type="checkbox" />
                    Saya memahami listing ini tidak dapat dipakai untuk event
                    baru.
                  </label>
                  <button className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-danger bg-ui-danger px-4 text-sm font-semibold text-ui-text-on-primary hover:opacity-90 mt-4" type="submit">
                    Arsipkan listing
                  </button>
                </form>
              ) : null}
            </div>

            {selectedVersion?.status_code === "DRAFT" ? (
              <div className="mt-6">
                <MarketplaceListingDraftForm
                  expectedRowVersion={selectedVersion.row_version}
                  initial={{
                    channelCode: selectedVersion.channel_code,
                    externalListingCode:
                      selectedVersion.external_listing_code,
                    displayName: selectedVersion.display_name,
                    listingTypeCode:
                      selectedVersion.listing_type_code,
                    effectiveFrom: toDateTimeLocal(
                      selectedVersion.effective_from,
                    ),
                    productId: selectedVersion.product_id ?? "",
                    components: selectedComponents.map((component) => ({
                      productId: component.product_id,
                      quantity: Number(component.component_qty),
                    })),
                    note: selectedVersion.note ?? "",
                  }}
                  intentId={randomUUID()}
                  listingId={selectedVersion.listing_id}
                  lockedIdentity
                  mode="save"
                  products={products}
                  versionId={selectedVersion.version_id}
                />
              </div>
            ) : null}

            {selectedVersion ? (
              <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 sm:p-6 mt-6">
                <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">Riwayat versi</p>
                    <h3 className="mt-2 text-xl font-semibold">
                      Versi {selectedVersion.version} /{" "}
                      {selectedVersion.status_code}
                    </h3>
                    <p className="mt-2 text-sm leading-6 text-ui-text-muted">
                      Fingerprint{" "}
                      <span className="font-mono text-xs text-ui-text">
                        {selectedVersion.mapping_fingerprint ?? "belum aktif"}
                      </span>
                    </p>
                  </div>
                  <Pill
                    label={versionStatusLabel(selectedVersion.status_code)}
                    tone={versionTone(selectedVersion)}
                  />
                </div>

                <div className="mt-5 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border">
                  <div className="overflow-x-auto [&_table]:w-full [&_table]:min-w-[760px] [&_table]:text-left [&_table]:text-sm [&_thead]:border-b [&_thead]:border-ui-border [&_thead]:bg-ui-surface-subtle [&_th]:px-4 [&_th]:py-3 [&_th]:text-xs [&_th]:font-semibold [&_th]:uppercase [&_th]:tracking-wide [&_th]:text-ui-text-muted [&_td]:px-4 [&_td]:py-4 [&_tbody]:divide-y [&_tbody]:divide-ui-border">
                    <table>
                      <thead>
                        <tr>
                          <th>Urutan</th>
                          <th>Produk</th>
                          <th>Jumlah per listing</th>
                          <th>Status produk</th>
                        </tr>
                      </thead>
                      <tbody>
                        {selectedVersion.listing_type_code === "SINGLE" ? (
                          <tr>
                            <td>1</td>
                            <td>
                              {products.find(
                                (product) =>
                                  product.product_id ===
                                  selectedVersion.product_id,
                              )?.sku ?? selectedVersion.product_id}
                            </td>
                            <td>1</td>
                            <td>
                              <Pill label="Aktif" tone="selected" />
                            </td>
                          </tr>
                        ) : selectedComponents.length === 0 ? (
                          <tr>
                            <td colSpan={4}>
                              Draft bundle belum memiliki komponen.
                            </td>
                          </tr>
                        ) : (
                          selectedComponents.map((component) => (
                            <tr key={component.component_id}>
                              <td>{component.line_no}</td>
                              <td>
                                <p className="font-medium text-ui-text">
                                  {component.product_sku}
                                </p>
                                <p className="mt-1 text-xs text-ui-text-muted">
                                  {component.product_name}
                                </p>
                              </td>
                              <td>{formatNumber(component.component_qty)}</td>
                              <td>
                                <Pill
                                  label={
                                    component.product_is_active
                                      ? "Aktif"
                                      : "Nonaktif"
                                  }
                                  tone={
                                    component.product_is_active
                                      ? "selected"
                                      : "danger"
                                  }
                                />
                              </td>
                            </tr>
                          ))
                        )}
                      </tbody>
                    </table>
                  </div>
                </div>

                {selectedVersion.status_code === "ACTIVE" ? (
                  <form
                    action={retireMarketplaceListingVersionAction}
                    className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-warning bg-ui-warning-subtle p-5"
                  >
                    <input
                      name="intentId"
                      type="hidden"
                      value={randomUUID()}
                    />
                    <input
                      name="listingId"
                      type="hidden"
                      value={selectedVersion.listing_id}
                    />
                    <input
                      name="versionId"
                      type="hidden"
                      value={selectedVersion.version_id}
                    />
                    <input
                      name="expectedRowVersion"
                      type="hidden"
                      value={selectedVersion.row_version}
                    />
                    <p className="font-medium text-ui-text">
                      Hentikan versi aktif
                    </p>
                    <p className="mt-2 text-sm leading-6 text-ui-text-muted">
                      Event sebelum batas waktu tetap memakai versi ini.
                      Event sesudah batas membutuhkan versi lain yang efektif.
                    </p>
                    <label className="grid gap-2 text-sm font-semibold text-ui-text mt-4 max-w-sm">
                      Berhenti berlaku
                      <Input
                        min={toDateTimeLocal(
                          new Date(
                            new Date(
                              selectedVersion.effective_from,
                            ).getTime() + 60_000,
                          ),
                        )}
                        name="effectiveTo"
                        required
                        type="datetime-local"
                      />
                    </label>
                    <label className="mt-4 flex items-start gap-3 text-sm text-ui-text">
                      <input name="confirmation" type="checkbox" />
                      Saya memahami histori order tidak berubah.
                    </label>
                    <button className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover mt-4" type="submit">
                      Hentikan versi
                    </button>
                  </form>
                ) : null}
              </div>
            ) : null}
          </section>
        ) : null}

        {(activationPreview || previewError) && selectedVersion ? (
          <section className="mt-10" id="activation-preview">
            <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 sm:p-6">
              <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">Preview aktivasi</p>
              <h2 className="mt-1 text-lg font-semibold text-ui-text">
                Tinjau dampak aktivasi versi {selectedVersion.version}.
              </h2>

              {previewError ? (
                <div className="mt-5 rounded-[var(--ui-radius-lg)] border border-ui-danger bg-ui-danger-subtle p-5 text-sm text-ui-danger">
                  {previewError}
                </div>
              ) : null}

              {activationPreview ? (
                <>
                  <div className="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
                    {[
                      [
                        "Status preview",
                        activationPreview.status,
                        activationPreview.eligible
                          ? "Dapat diaktifkan"
                          : "Masih diblokir",
                      ],
                      [
                        "Versi",
                        `v${activationPreview.version}`,
                        `row ${activationPreview.versionRowVersion}`,
                      ],
                      [
                        "Komponen",
                        activationPreview.componentCount,
                        activationPreview.listingType,
                      ],
                      [
                        "Versi aktif saat ini",
                        activationPreview.currentOpenVersion ?? "—",
                        "Ditutup tepat pada boundary baru",
                      ],
                    ].map(([label, value, detail]) => (
                      <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4" key={String(label)}>
                        <p className="text-xs font-medium text-ui-text-muted">{label}</p>
                        <p className="ui-number mt-1 text-xl font-semibold text-ui-text">{String(value)}</p>
                        <p className="mt-1 text-xs leading-5 text-ui-text-muted">{detail}</p>
                      </article>
                    ))}
                  </div>

                  <form className="mt-6 flex flex-wrap items-end gap-3">
                    <input
                      name="selectedListingId"
                      type="hidden"
                      value={selectedVersion.listing_id}
                    />
                    <input
                      name="selectedVersionId"
                      type="hidden"
                      value={selectedVersion.version_id}
                    />
                    <input
                      name="previewListingId"
                      type="hidden"
                      value={selectedVersion.listing_id}
                    />
                    <input
                      name="previewVersionId"
                      type="hidden"
                      value={selectedVersion.version_id}
                    />
                    <label className="grid gap-2 text-sm font-semibold text-ui-text">
                      Contoh jumlah listing
                      <Input
                        defaultValue={sampleQuantity}
                        min={1}
                        name="sampleQuantity"
                        step={1}
                        type="number"
                      />
                    </label>
                    <button className="inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline" type="submit">
                      Hitung ekspansi
                    </button>
                  </form>

                  <div className="mt-5 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border">
                    <div className="overflow-x-auto [&_table]:w-full [&_table]:min-w-[760px] [&_table]:text-left [&_table]:text-sm [&_thead]:border-b [&_thead]:border-ui-border [&_thead]:bg-ui-surface-subtle [&_th]:px-4 [&_th]:py-3 [&_th]:text-xs [&_th]:font-semibold [&_th]:uppercase [&_th]:tracking-wide [&_th]:text-ui-text-muted [&_td]:px-4 [&_td]:py-4 [&_tbody]:divide-y [&_tbody]:divide-ui-border">
                      <table>
                        <thead>
                          <tr>
                            <th>Produk</th>
                            <th>Per listing</th>
                            <th>Contoh listing</th>
                            <th>Total unit</th>
                            <th>Status</th>
                          </tr>
                        </thead>
                        <tbody>
                          {activationPreview.components.map((component) => (
                            <tr key={component.productId}>
                              <td>
                                <p className="font-medium text-ui-text">
                                  {component.productSku}
                                </p>
                                <p className="mt-1 text-xs text-ui-text-muted">
                                  {component.productName}
                                </p>
                              </td>
                              <td>{formatNumber(component.quantity)}</td>
                              <td>{formatNumber(sampleQuantity)}</td>
                              <td>
                                {formatNumber(
                                  component.quantity * sampleQuantity,
                                )}
                              </td>
                              <td>
                                <Pill
                                  label={
                                    component.active ? "Aktif" : "Nonaktif"
                                  }
                                  tone={
                                    component.active ? "selected" : "danger"
                                  }
                                />
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>

                  {activationPreview.blockers.length > 0 ? (
                    <div className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-warning bg-ui-warning-subtle p-5">
                      <p className="font-medium text-ui-warning">
                        Aktivasi diblokir
                      </p>
                      <ul className="mt-3 space-y-2 text-sm leading-6 text-ui-warning">
                        {activationPreview.blockers.map((blocker) => (
                          <li key={`${blocker.code}:${blocker.scope}`}>
                            <span className="font-mono text-xs">
                              {blocker.code}
                            </span>{" "}
                            / {blocker.message}
                          </li>
                        ))}
                      </ul>
                    </div>
                  ) : null}

                  {activationPreview.eligible ? (
                    <form
                      action={activateMarketplaceListingVersionAction}
                      className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border-strong bg-ui-primary-subtle p-5"
                    >
                      <input
                        name="intentId"
                        type="hidden"
                        value={randomUUID()}
                      />
                      <input
                        name="listingId"
                        type="hidden"
                        value={activationPreview.listingId}
                      />
                      <input
                        name="versionId"
                        type="hidden"
                        value={activationPreview.versionId}
                      />
                      <input
                        name="expectedRowVersion"
                        type="hidden"
                        value={activationPreview.versionRowVersion}
                      />
                      <input
                        name="previewBasisHash"
                        type="hidden"
                        value={activationPreview.basisHash}
                      />
                      <p className="font-medium text-ui-text">
                        Konfirmasi aktivasi final
                      </p>
                      <p className="mt-2 text-sm leading-6 text-ui-text-muted">
                        Aktivasi membuat mapping tersedia untuk event pada
                        periode efektif. Aktivasi tidak langsung mengubah stok.
                      </p>
                      <label className="mt-4 flex items-start gap-3 text-sm text-ui-text">
                        <input name="confirmation" type="checkbox" />
                        Saya sudah memeriksa produk, quantity, waktu efektif,
                        dan boundary versi sebelumnya.
                      </label>
                      <button className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover mt-4" type="submit">
                        Aktifkan versi mapping
                      </button>
                    </form>
                  ) : (
                    <p className="mt-6 text-sm text-ui-text-muted">
                      Tombol aktivasi tidak ditampilkan selama preview masih
                      memiliki blocker.
                    </p>
                  )}
                </>
              ) : null}
            </div>
          </section>
        ) : null}
      </div>
    </AppShell>
  );
}
