import Link from "next/link";
import { redirect } from "next/navigation";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  OrderWorkspaceTabs,
} from "@/app/marketplace/order-workspace-tabs";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  Alert,
  EmptyState,
  StatusBadge,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  getReturnClaimData,
  getReturnData,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = Record<
  string,
  string | string[] | undefined
>;

function first(
  value: SearchParams[string],
) {
  return Array.isArray(value)
    ? value[0]
    : value;
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value,
  );
}

function qty(value: number) {
  return new Intl.NumberFormat("id-ID").format(Number(value));
}

function channelLabel(code: string) {
  if (code === "TIKTOK_SHOP") return "TikTok Shop";
  if (code === "SHOPEE") return "Shopee";
  return code;
}

function statusLabel(status: string) {
  switch (status) {
    case "EXPECTED":
      return { label: "Menunggu datang", tone: "warning" as const };
    case "PARTIALLY_RECEIVED":
      return { label: "Datang sebagian", tone: "warning" as const };
    case "RECEIVED_PENDING_INSPECTION":
      return { label: "Menunggu diperiksa", tone: "warning" as const };
    case "PARTIALLY_INSPECTED":
      return { label: "Diperiksa sebagian", tone: "warning" as const };
    case "COMPLETED_SELLABLE":
      return { label: "Selesai - layak jual", tone: "selected" as const };
    case "COMPLETED_DAMAGED":
      return { label: "Selesai - rusak", tone: "neutral" as const };
    case "COMPLETED_MIXED":
      return { label: "Selesai - campuran", tone: "selected" as const };
    case "LOST":
      return { label: "Hilang", tone: "danger" as const };
    default:
      return { label: status, tone: "neutral" as const };
  }
}

function claimStatusLabel(status: string) {
  const labels: Record<string, string> = {
    NOT_STARTED: "Belum dikirim",
    DUE_SOON: "Segera jatuh tempo",
    SUBMITTED: "Sudah dikirim",
    RESOLVED: "Selesai",
    EXPIRED: "Lewat batas",
    EXCEPTION: "Perlu ditangani",
    CANCELLED: "Dibatalkan",
  };

  return labels[status] ?? status;
}

function claimTone(status: string) {
  if (["EXPIRED", "EXCEPTION"].includes(status)) {
    return "danger" as const;
  }

  if (status === "DUE_SOON") {
    return "warning" as const;
  }

  if (["SUBMITTED", "RESOLVED"].includes(status)) {
    return "selected" as const;
  }

  return "neutral" as const;
}

function claimTypeLabel(code: string) {
  if (code === "LOST_RETURN") return "Barang retur hilang";
  return code;
}

function nextReturnAction(status: string) {
  switch (status) {
    case "EXPECTED":
    case "PARTIALLY_RECEIVED":
      return "Tunggu kedatangan";
    case "RECEIVED_PENDING_INSPECTION":
    case "PARTIALLY_INSPECTED":
      return "Periksa barang";
    case "LOST":
      return "Tinjau kehilangan";
    case "COMPLETED_SELLABLE":
    case "COMPLETED_DAMAGED":
    case "COMPLETED_MIXED":
      return "Selesai";
    default:
      return "Buka retur";
  }
}

function returnDetailHref({
  claimId,
  returnId,
  returnTo,
}: {
  claimId?: string;
  returnId: string;
  returnTo: string;
}) {
  const params = new URLSearchParams();

  if (claimId) params.set("claimId", claimId);
  if (returnTo !== "/returns") params.set("returnTo", returnTo);

  const query = params.toString();
  return `/returns/${encodeURIComponent(returnId)}${
    query ? `?${query}` : ""
  }${claimId ? "#claim-detail" : ""}`;
}

export default async function ReturnsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [session, query] = await Promise.all([
    requireAdminSession(),
    searchParams,
  ]);

  const legacyReturnId = first(query.returnId)?.trim() ?? "";
  const legacyClaimId = first(query.claimId)?.trim() ?? "";
  let legacyClaimNotFound = false;

  if (legacyReturnId && isUuid(legacyReturnId)) {
    redirect(
      returnDetailHref({
        claimId:
          legacyClaimId && isUuid(legacyClaimId)
            ? legacyClaimId
            : undefined,
        returnId: legacyReturnId,
        returnTo: legacyClaimId ? "/returns?section=claims" : "/returns",
      }),
    );
  }

  if (legacyClaimId) {
    if (isUuid(legacyClaimId)) {
      const selectedClaim = (
        await getReturnClaimData({
          organizationId: session.profile.organization_id,
          claimId: legacyClaimId,
          pageSize: 10,
        })
      ).selectedClaim;

      if (selectedClaim) {
        redirect(
          returnDetailHref({
            claimId: selectedClaim.id,
            returnId: selectedClaim.return_id,
            returnTo: "/returns?section=claims",
          }),
        );
      }
    }

    legacyClaimNotFound = true;
  }

  let data:
    | Awaited<ReturnType<typeof getReturnData>>
    | null = null;

  let failed = false;

  let claimData:
    | Awaited<ReturnType<typeof getReturnClaimData>>
    | null = null;

  try {
    [data, claimData] = await Promise.all([
      getReturnData(session.profile.organization_id),
      getReturnClaimData({
        organizationId: session.profile.organization_id,
        pageSize: 100,
      }),
    ]);
  } catch {
    failed = true;
  }

  const returns = data?.returns ?? [];
  const claims = claimData?.claims ?? [];

  const activeSection =
    first(query.section) === "claims"
      ? "claims"
      : "returns";

  const pendingInspection = returns.filter(
    (item) => Number(item.pending_inspection_qty) > 0,
  ).length;

  const pendingArrival = returns.filter(
    (item) => Number(item.pending_arrival_qty) > 0,
  ).length;

  const lostReturns = returns.filter(
    (item) => Number(item.lost_qty) > 0,
  ).length;

  const claimsNotStarted = claims.filter(
    (claim) => claim.status_code === "NOT_STARTED",
  ).length;

  const claimsDueSoon = claims.filter(
    (claim) => claim.status_code === "DUE_SOON",
  ).length;

  const claimsNeedAction = claims.filter((claim) =>
    ["EXPIRED", "EXCEPTION"].includes(claim.status_code),
  ).length;

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          eyebrow="Pesanan"
          title="Retur & Klaim"
          description="Pantau proses retur, kondisi barang kembali, dan klaim marketplace dalam satu tempat."
        />

        <OrderWorkspaceTabs active="returns" />

        {legacyClaimNotFound ? (           <Alert             className="mt-6"             title="Klaim tidak ditemukan"             tone="danger"           >             Klaim tidak tersedia untuk organisasi ini atau tautan sudah tidak valid.           </Alert>         ) : null}

        <nav
          aria-label="Retur dan klaim"
          className="mt-4 flex gap-5 border-b border-ui-border"
        >
          <Link
            aria-current={activeSection === "returns" ? "page" : undefined}
            className={`border-b-2 px-1 py-2.5 text-sm font-semibold ${
              activeSection === "returns"
                ? "border-ui-primary text-ui-primary"
                : "border-transparent text-ui-text-muted hover:text-ui-text"
            }`}
            href="/returns"
          >
            Retur
          </Link>

          <Link
            aria-current={activeSection === "claims" ? "page" : undefined}
            className={`border-b-2 px-1 py-2.5 text-sm font-semibold ${
              activeSection === "claims"
                ? "border-ui-primary text-ui-primary"
                : "border-transparent text-ui-text-muted hover:text-ui-text"
            }`}
            href="/returns?section=claims"
          >
            Klaim
          </Link>
        </nav>

        {failed ? (
          <Alert
            className="mt-6"
            title="Retur dan klaim belum dapat dimuat"
            tone="danger"
          >
            Coba muat ulang halaman. Tidak ada perubahan stok yang dilakukan.
          </Alert>
        ) : (
          <>
            <section
              aria-label={
                activeSection === "returns"
                  ? "Ringkasan retur"
                  : "Ringkasan klaim"
              }
              className="mt-4 grid gap-3 sm:grid-cols-3"
            >
              {activeSection === "returns" ? (
                <>
                  <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border border-l-2 border-l-ui-warning bg-ui-surface px-4 py-3">
                    <p className="text-sm font-medium text-ui-text-muted">
                      Menunggu datang
                    </p>
                    <p className="ui-number text-xl font-semibold text-ui-text">
                      {qty(pendingArrival)}
                    </p>
                  </div>

                  <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border border-l-2 border-l-ui-primary bg-ui-surface px-4 py-3">
                    <p className="text-sm font-medium text-ui-text-muted">
                      Menunggu diperiksa
                    </p>
                    <p className="ui-number text-xl font-semibold text-ui-text">
                      {qty(pendingInspection)}
                    </p>
                  </div>

                  <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-3">
                    <p className="text-sm font-medium text-ui-text-muted">
                      Retur hilang
                    </p>
                    <p className="ui-number text-xl font-semibold text-ui-text">
                      {qty(lostReturns)}
                    </p>
                  </div>
                </>
              ) : (
                <>
                  <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-3">
                    <p className="text-sm font-medium text-ui-text-muted">
                      Belum dikirim
                    </p>
                    <p className="ui-number text-xl font-semibold text-ui-text">
                      {qty(claimsNotStarted)}
                    </p>
                  </div>

                  <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border border-l-2 border-l-ui-warning bg-ui-surface px-4 py-3">
                    <p className="text-sm font-medium text-ui-text-muted">
                      Segera jatuh tempo
                    </p>
                    <p className="ui-number text-xl font-semibold text-ui-text">
                      {qty(claimsDueSoon)}
                    </p>
                  </div>

                  <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border border-l-2 border-l-ui-danger bg-ui-surface px-4 py-3">
                    <p className="text-sm font-medium text-ui-text-muted">
                      Perlu ditangani
                    </p>
                    <p className="ui-number text-xl font-semibold text-ui-text">
                      {qty(claimsNeedAction)}
                    </p>
                  </div>
                </>
              )}
            </section>

            {activeSection === "returns" ? (
              <section className="mt-6">
                <div>
                  <h2 className="text-lg font-semibold text-ui-text">
                    Retur yang perlu ditangani
                  </h2>
                  <p className="mt-1 text-sm text-ui-text-muted">
                    Pilih retur yang perlu diterima, diperiksa, atau ditindaklanjuti.
                  </p>
                </div>

                {returns.length === 0 ? (
                  <EmptyState
                    className="mt-5"
                    title="Tidak ada retur yang perlu ditangani"
                    description="Retur dari marketplace akan muncul otomatis di sini."
                  />
                ) : (
                  <div className="mt-4 divide-y divide-ui-border rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface">
                    {returns.map((item) => {
                      const status = statusLabel(item.status_code);

                      return (
                        <article
                          className="grid gap-4 px-4 py-4 lg:grid-cols-[minmax(0,1.15fr)_10rem_minmax(0,1fr)_10rem_5rem] lg:items-center"
                          key={item.return_id}
                        >
                          <div>
                            <p className="ui-code text-sm font-semibold text-ui-text">
                              {item.external_return_ref}
                            </p>
                            <p className="mt-1 text-xs text-ui-text-muted">
                              {channelLabel(item.channel_code)} {"\u00B7"} {item.marketplace_order_ref}
                            </p>
                          </div>

                          <StatusBadge tone={status.tone}>
                            {status.label}
                          </StatusBadge>

                          <div className="grid grid-cols-3 gap-3 text-sm">
                            <div>
                              <p className="text-xs text-ui-text-muted">
                                Diharapkan
                              </p>
                              <p className="ui-number mt-1 font-semibold text-ui-text">
                                {qty(item.expected_qty)}
                              </p>
                            </div>
                            <div>
                              <p className="text-xs text-ui-text-muted">
                                Diterima
                              </p>
                              <p className="ui-number mt-1 font-semibold text-ui-text">
                                {qty(item.received_qty)}
                              </p>
                            </div>
                            <div>
                              <p className="text-xs text-ui-text-muted">
                                Hilang
                              </p>
                              <p className="ui-number mt-1 font-semibold text-ui-text">
                                {qty(item.lost_qty)}
                              </p>
                            </div>
                          </div>

                          <div>
                            <p className="text-xs text-ui-text-muted">
                              Berikutnya
                            </p>
                            <p className="mt-1 text-sm font-semibold text-ui-text">
                              {nextReturnAction(item.status_code)}
                            </p>
                          </div>

                          <Link
                            className="text-sm font-semibold text-ui-primary hover:underline"
                            href={returnDetailHref({
                              returnId: item.return_id,
                              returnTo: "/returns",
                            })}
                          >
                            Buka
                          </Link>
                        </article>
                      );
                    })}
                  </div>
                )}
              </section>
            ) : (
              <section className="mt-6">
                <div>
                  <h2 className="text-lg font-semibold text-ui-text">
                    Klaim marketplace
                  </h2>
                  <p className="mt-1 text-sm text-ui-text-muted">
                    Saat ini klaim tersedia untuk TikTok Shop. Pantau yang belum dikirim, mendekati batas waktu, atau perlu ditindaklanjuti. Klaim tidak mengubah stok.
                  </p>
                </div>

                {claims.length === 0 ? (
                  <EmptyState
                    className="mt-5"
                    title="Tidak ada klaim yang perlu ditangani"
                    description="Klaim marketplace akan muncul di sini saat ada kehilangan yang perlu ditindaklanjuti."
                  />
                ) : (
                  <div className="mt-4 divide-y divide-ui-border rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface">
                    {claims.map((claim) => (
                      <article
                        className="grid gap-3 px-4 py-4 md:grid-cols-[minmax(0,1fr)_11rem_11rem_8rem] md:items-center"
                        key={claim.id}
                      >
                        <div>
                          <p className="ui-code text-sm font-semibold text-ui-text">
                            {claim.external_claim_ref || "Belum dikirim"}
                          </p>
                          <p className="mt-1 text-xs text-ui-text-muted">
                            {claimTypeLabel(claim.claim_type_code)}
                          </p>
                        </div>

                        <StatusBadge tone={claimTone(claim.status_code)}>
                          {claimStatusLabel(claim.status_code)}
                        </StatusBadge>

                        <p className="text-sm text-ui-text-muted">
                          Batas:{" "}
                          {claim.deadline_at
                            ? new Intl.DateTimeFormat("id-ID", {
                                dateStyle: "medium",
                                timeZone: "Asia/Jakarta",
                              }).format(new Date(claim.deadline_at))
                            : "Belum tersedia"}
                        </p>

                        <Link
                          className="text-sm font-semibold text-ui-primary hover:underline"
                          href={returnDetailHref({
                            claimId: claim.id,
                            returnId: claim.return_id,
                            returnTo: "/returns?section=claims",
                          })}
                        >
                          Buka
                        </Link>
                      </article>
                    ))}
                  </div>
                )}
              </section>
            )}
          </>
        )}
      </div>
    </AppShell>
  );
}
