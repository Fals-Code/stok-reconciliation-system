import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import { ApprovalPanel } from "@/app/stocktakes/components/approval-panel";
import { CancelStocktakePanel } from "@/app/stocktakes/components/cancel-stocktake-panel";
import { CountingPanel } from "@/app/stocktakes/components/counting-panel";
import { PostingPanel } from "@/app/stocktakes/components/posting-panel";
import { ReviewPanel } from "@/app/stocktakes/components/review-panel";
import { StocktakePresentationFeedback } from "@/app/stocktakes/presentation-feedback";
import {
  prepareStocktakeAction,
  startStocktakeAction,
} from "@/app/stocktakes/actions";
import { Alert, StatusBadge } from "@/components/ui";
import { requireAdminSession } from "@/lib/auth";
import { safeInternalRoute } from "@/lib/safe-internal-route";
import {
  getLatestStocktakeApproval,
  getLatestStocktakePosting,
  getStocktakeCancellation,
  getStocktakeApprovalLines,
  getStocktakeCountAttempts,
  getStocktakeCountingLines,
  getStocktakeDetails,
  getStocktakePostingLines,
  getStocktakeReviewLines,
} from "@/lib/stocktakes/queries";
import type {
  StocktakeApproval,
  StocktakeApprovalLine,
  StocktakeCancellation,
  StocktakeCountAttempt,
  StocktakeCountingLine,
  StocktakePosting,
  StocktakePostingLine,
  StocktakeReviewLine,
  StocktakeStatus,
} from "@/lib/stocktakes/types";

export const dynamic = "force-dynamic";

const statusLabels: Record<StocktakeStatus, string> = {
  DRAFT: "Belum Dimulai",
  READY: "Siap Dihitung",
  COUNTING: "Sedang Dihitung",
  REVIEW: "Perlu Diperiksa",
  APPROVED: "Siap Disimpan",
  POSTING: "Menyimpan Perubahan",
  POSTED: "Selesai",
  CANCELLED: "Dibatalkan",
  EXCEPTION: "Bermasalah",
};

function statusTone(status: StocktakeStatus) {
  return status === "POSTED"
    ? ("selected" as const)
    : status === "EXCEPTION" || status === "CANCELLED"
      ? ("danger" as const)
      : status === "COUNTING" ||
          status === "REVIEW" ||
          status === "APPROVED" ||
          status === "POSTING"
        ? ("warning" as const)
        : ("neutral" as const);
}

function scopeLabel(mode: string) {
  return mode === "ALL_ACTIVE_INVENTORY"
    ? "Semua produk aktif"
    : mode === "PRODUCTS"
      ? "Produk tertentu"
      : "Kode Batch tertentu";
}

function bucketLabel(bucket: string) {
  return bucket === "SELLABLE"
    ? "Layak Dijual"
    : bucket === "QUARANTINE"
      ? "Ditahan"
      : "Rusak";
}

function first(
  params: Record<string, string | string[] | undefined>,
  key: string,
) {
  const value = params[key];
  return (Array.isArray(value) ? value[0] : value)?.trim() ?? "";
}

export default async function StocktakeDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ stocktakeId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ stocktakeId }, session, query] = await Promise.all([
    params,
    requireAdminSession(),
    searchParams,
  ]);

  const rawSuccess = Boolean(first(query, "success"));
  const rawError = Boolean(first(query, "error"));
  const rawIdempotencyKey = Boolean(first(query, "idempotencyKey"));
  const returnTo = safeInternalRoute(
    first(query, "returnTo"),
    "/stocktakes",
    { allowedPathnames: ["/stocktakes"] },
  );

  if (rawSuccess || rawError || rawIdempotencyKey) {
    const notice =
      rawSuccess && !rawError && !rawIdempotencyKey ? "updated" : "retry";
    const params = new URLSearchParams({ notice });
    if (returnTo !== "/stocktakes") params.set("returnTo", returnTo);
    redirect(`/stocktakes/${encodeURIComponent(stocktakeId)}?${params}`);
  }

  let data;

  try {
    data = await getStocktakeDetails(stocktakeId);
  } catch {
    return (
      <AppShell profile={session.profile}>
        <div className="mx-auto w-full max-w-[1120px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader
            description="Data Hitung Stok belum dapat dimuat. Kondisi gagal tidak mengubah stok."
            title="Hitung Stok"
          />
          <Alert
            className="mt-6"
            title="Data belum dapat dimuat"
            tone="warning"
          >
            Muat ulang halaman sebelum melakukan perubahan.
          </Alert>
        </div>
      </AppShell>
    );
  }

  if (!data) notFound();

  const { details, summary } = data;
  let countingLines: StocktakeCountingLine[] | null = null;
  let reviewLines: StocktakeReviewLine[] = [];
  let countAttempts: StocktakeCountAttempt[] = [];
  let approval: StocktakeApproval | null = null;
  let approvalLines: StocktakeApprovalLine[] = [];
  let posting: StocktakePosting | null = null;
  let postingLines: StocktakePostingLine[] = [];
  let cancellation: StocktakeCancellation | null = null;
  let downstreamError = false;

  try {
    if (details.status_code === "COUNTING") {
      countingLines = await getStocktakeCountingLines(
        stocktakeId,
        details.visibility_code,
      );
    } else if (details.status_code === "REVIEW") {
      [reviewLines, countAttempts] = await Promise.all([
        getStocktakeReviewLines(stocktakeId),
        getStocktakeCountAttempts(stocktakeId),
      ]);
    } else if (details.status_code === "CANCELLED") {
      cancellation = await getStocktakeCancellation(stocktakeId);
    } else if (
      details.status_code === "APPROVED" ||
      details.status_code === "POSTING" ||
      details.status_code === "POSTED"
    ) {
      const [loadedApproval, loadedReview, loadedPosting] = await Promise.all([
        getLatestStocktakeApproval(stocktakeId),
        getStocktakeReviewLines(stocktakeId),
        details.status_code === "POSTING" || details.status_code === "POSTED"
          ? getLatestStocktakePosting(stocktakeId)
          : Promise.resolve(null),
      ]);

      approval = loadedApproval;
      reviewLines = loadedReview;
      posting = loadedPosting;

      const reads: Promise<void>[] = [];

      if (approval) {
        reads.push(
          getStocktakeApprovalLines(stocktakeId, approval.approval_id).then(
            (rows) => {
              approvalLines = rows;
            },
          ),
        );
      }

      if (posting) {
        reads.push(
          getStocktakePostingLines(stocktakeId, posting.posting_id).then(
            (rows) => {
              postingLines = rows;
            },
          ),
        );
      }

      await Promise.all(reads);
    }
  } catch {
    downstreamError = true;
  }

  const notice = first(query, "notice");
  const hasError = notice === "retry";
  const success = notice === "updated";
  const progress =
    summary && summary.line_count > 0
      ? Math.round((summary.counted_line_count / summary.line_count) * 100)
      : 0;
  const remaining =
    summary && summary.line_count > 0
      ? Math.max(summary.line_count - summary.counted_line_count, 0)
      : 0;

  return (
    <AppShell profile={session.profile}>
      <StocktakePresentationFeedback
        shouldSanitize={notice === "updated" || notice === "retry"}
      />

      <div className="mx-auto w-full max-w-[1120px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <Link
          className="mb-4 inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
          href={returnTo}
        >
          &larr; Kembali ke Hitung Stok
        </Link>

        <PageHeader
          description="Hitung stok fisik per produk, Kode Batch, dan kondisi. Stok baru berubah setelah hasil diperiksa, disetujui, dan disimpan."
          eyebrow="Hitung Stok"
          title={details.title}
        />

        {success ? (
          <Alert
            className="mt-6"
            title="Hitung Stok diperbarui"
            tone="success"
          >
            Status sekarang {statusLabels[details.status_code].toLowerCase()}.
          </Alert>
        ) : null}

        {hasError ? (
          <Alert
            className="mt-6"
            title="Perubahan belum disimpan"
            tone="warning"
          >
            Perubahan belum dapat disimpan. Muat ulang halaman lalu coba lagi.
          </Alert>
        ) : null}

        <section className="mt-6 border-y border-ui-border py-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="min-w-0">
              <p className="text-sm font-medium text-ui-text">
                {scopeLabel(details.scope_definition.mode)}
                {" · "}
                {details.visibility_code === "BLIND"
                  ? "Tanpa melihat catatan"
                  : "Dengan melihat catatan"}
              </p>
              <p className="mt-1 text-sm text-ui-text-muted">
                {details.scope_definition.bucketCodes
                  .map(bucketLabel)
                  .join(" · ")}
              </p>
            </div>

            <StatusBadge tone={statusTone(details.status_code)}>
              {statusLabels[details.status_code]}
            </StatusBadge>
          </div>

          {summary && summary.line_count > 0 ? (
            <div className="mt-4">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <p className="text-sm font-semibold text-ui-text">
                  {summary.counted_line_count} dari {summary.line_count} lokasi
                  selesai
                </p>
                <p className="ui-number text-sm text-ui-text-muted">
                  {progress}%
                </p>
              </div>

              <div
                aria-label={`${progress}% penghitungan selesai`}
                aria-valuemax={100}
                aria-valuemin={0}
                aria-valuenow={progress}
                className="mt-2 h-2 overflow-hidden rounded-full bg-ui-surface-subtle"
                role="progressbar"
              >
                <div
                  className="h-full rounded-full bg-ui-primary"
                  style={{ width: `${progress}%` }}
                />
              </div>

              <p className="mt-2 text-xs text-ui-text-muted">
                {remaining === 0
                  ? "Semua lokasi sudah dihitung."
                  : `${remaining} lokasi masih perlu dihitung.`}
              </p>
            </div>
          ) : null}

          {details.note ? (
            <p className="mt-4 text-sm text-ui-text-muted">
              Catatan: {details.note}
            </p>
          ) : null}
        </section>

        {downstreamError ? (
          <Alert
            className="mt-6"
            title="Rincian belum dapat dimuat"
            tone="warning"
          >
            Muat ulang halaman. Tidak ada perubahan stok yang dilakukan.
          </Alert>
        ) : (
          <>
            {details.status_code === "DRAFT" ? (
              <section className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4">
                <h2 className="text-lg font-semibold text-ui-text">
                  Siapkan Hitung Stok
                </h2>
                <p className="mt-1 text-sm leading-6 text-ui-text-muted">
                  Periksa cakupan yang dipilih sebelum daftar hitung dibuat.
                  Tahap ini belum mengubah stok.
                </p>
                <form action={prepareStocktakeAction} className="mt-4">
                  <input name="returnTo" type="hidden" value={returnTo} />
                  <input
                    name="stocktakeId"
                    type="hidden"
                    value={stocktakeId}
                  />
                  <button
                    className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary"
                    type="submit"
                  >
                    Siapkan Hitung Stok
                  </button>
                </form>
              </section>
            ) : null}

            {details.status_code === "READY" ? (
              <section className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4">
                <h2 className="text-lg font-semibold text-ui-text">
                  Mulai Menghitung
                </h2>
                <p className="mt-1 text-sm leading-6 text-ui-text-muted">
                  Mulai saat barang siap diperiksa secara fisik. Daftar lokasi
                  akan dibuat dari cakupan sesi ini.
                </p>
                <form action={startStocktakeAction} className="mt-4">
                  <input name="returnTo" type="hidden" value={returnTo} />
                  <input
                    name="stocktakeId"
                    type="hidden"
                    value={stocktakeId}
                  />
                  <input name="confirmStart" type="hidden" value="on" />
                  <button
                    className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary"
                    type="submit"
                  >
                    Mulai Menghitung
                  </button>
                </form>
              </section>
            ) : null}

            {details.status_code === "COUNTING" && countingLines ? (
              <CountingPanel
                lines={countingLines}
                returnTo={returnTo}
                stocktakeId={stocktakeId}
                stocktakeVersion={details.version_no}
                visibility={details.visibility_code}
              />
            ) : null}

            {details.status_code === "REVIEW" ? (
              <>
                <ReviewPanel
                  attempts={countAttempts}
                  lines={reviewLines}
                  returnTo={returnTo}
                  stocktakeId={stocktakeId}
                />
                <ApprovalPanel
                  lines={reviewLines}
                  returnTo={returnTo}
                  stocktakeId={stocktakeId}
                  stocktakeVersion={details.version_no}
                />
              </>
            ) : null}

            {details.status_code === "APPROVED" ||
            details.status_code === "POSTING" ||
            details.status_code === "POSTED" ? (
              <PostingPanel
                approval={approval}
                approvalLines={approvalLines}
                posting={posting}
                postingLines={postingLines}
                reviewLines={reviewLines}
                returnTo={returnTo}
                status={details.status_code}
                stocktakeId={stocktakeId}
              />
            ) : null}

            {["DRAFT", "READY", "COUNTING", "REVIEW"].includes(
              details.status_code,
            ) ? (
              <CancelStocktakePanel
                returnTo={returnTo}
                stocktakeId={stocktakeId}
              />
            ) : null}

            {details.status_code === "EXCEPTION" ? (
              <Alert
                className="mt-6"
                title="Hitung Stok perlu diperiksa"
                tone="danger"
              >
                Ada hasil yang ditandai bermasalah. Periksa bukti dan tindak
                lanjuti sesuai prosedur gudang.
              </Alert>
            ) : null}

            {details.status_code === "CANCELLED" ? (
              <Alert
                className="mt-6"
                title="Hitung Stok dibatalkan"
                tone="warning"
              >
                Sesi ini hanya dapat dibaca dan tidak memiliki tindakan
                lanjutan. Hasil hitung sebelumnya tetap tersimpan dan stok
                tidak berubah.
                {cancellation ? (
                  <span className="mt-2 block">
                    Alasan: {cancellation.reason}
                  </span>
                ) : null}
              </Alert>
            ) : null}
          </>
        )}
      </div>
    </AppShell>
  );
}
