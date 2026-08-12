import { randomUUID } from "node:crypto";

import Link from "next/link";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  createOpeningBalanceAction,
  postOpeningBalanceAction,
  reverseOpeningBalanceAction,
  saveOpeningBalanceDraftAction,
  submitOpeningBalanceReviewAction,
} from "@/app/opening-balances/actions";
import OpeningBalanceDraftForm from "@/app/opening-balances/components/draft-form";
import type { OpeningBalanceDraftLine } from "@/app/opening-balances/draft";
import {
  Alert,
  Button,
  EmptyState,
  StatusBadge,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  getOpeningBalanceData,
  previewOpeningBalanceCutover,
  previewOpeningBalanceReversal,
  type OpeningBalanceCutover,
  type OpeningBalancePreview,
  type OpeningBalanceReversalPreview,
  type OpeningBalanceVerificationStatus,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = Record<string, string | string[] | undefined>;

const numberFormatter = new Intl.NumberFormat("id-ID");

function first(value: SearchParams[string]) {
  return Array.isArray(value) ? value[0] : value;
}

function number(value: number | null | undefined) {
  return numberFormatter.format(Number(value ?? 0));
}

function formatDate(value: string | null | undefined) {
  if (!value) return "Belum tersedia";

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    dateStyle: "medium",
    timeStyle: "short",
    hour12: false,
  }).format(date);
}

function defaultDateTimeLocal() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date());

  const fields = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );

  return `${fields.year}-${fields.month}-${fields.day}T${fields.hour}:${fields.minute}`;
}

function verificationPresentation(status: OpeningBalanceVerificationStatus) {
  if (status === "VERIFIED") {
    return { label: "Terverifikasi", tone: "selected" as const };
  }

  if (status === "PARTIALLY_VERIFIED") {
    return { label: "Sebagian terverifikasi", tone: "warning" as const };
  }

  if (status === "UNVERIFIED") {
    return { label: "Belum terverifikasi", tone: "warning" as const };
  }

  if (status === "PENDING_POST") {
    return { label: "Belum diposting", tone: "neutral" as const };
  }

  return { label: "Tidak berlaku", tone: "neutral" as const };
}

function operationalPresentation(cutover: OpeningBalanceCutover) {
  if (cutover.operational_status_code === "ACTIVE") {
    return { label: "Aktif", tone: "selected" as const };
  }

  if (cutover.operational_status_code === "REVERSED") {
    return { label: "Sudah dikoreksi", tone: "danger" as const };
  }

  if (cutover.status_code === "REVIEW") {
    return { label: "Perlu dikonfirmasi", tone: "warning" as const };
  }

  if (cutover.status_code === "DRAFT") {
    return { label: "Draft", tone: "neutral" as const };
  }

  return { label: "Tidak aktif", tone: "neutral" as const };
}

function bucketLabel(code: string) {
  if (code === "SELLABLE") return "Barang baik";
  if (code === "QUARANTINE") return "Karantina";
  if (code === "DAMAGED") return "Rusak";
  return code;
}

function PreviewPanel({ preview }: { preview: OpeningBalancePreview }) {
  const intentId = preview.eligible ? randomUUID() : null;

  return (
    <section
      aria-labelledby="opening-preview-heading"
      className="mt-6 border-t border-ui-border pt-6"
      id="preview"
    >
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-ui-primary">
            Langkah 2 dari 3
          </p>
          <h2
            className="mt-1 text-lg font-semibold text-ui-text"
            id="opening-preview-heading"
          >
            Periksa dampak stok awal
          </h2>
          <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
            Sistem menghitung ulang posisi stok dari data yang tersimpan.
            Belum ada perubahan stok pada tahap ini.
          </p>
        </div>

        <StatusBadge tone={preview.eligible ? "selected" : "danger"}>
          {preview.eligible ? "Siap dikonfirmasi" : "Diblokir"}
        </StatusBadge>
      </div>

      <dl className="mt-5 grid gap-4 border-y border-ui-border py-4 sm:grid-cols-3">
        <div>
          <dt className="text-sm text-ui-text-muted">Baris stok</dt>
          <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
            {number(preview.positiveLineCount)}
          </dd>
        </div>
        <div>
          <dt className="text-sm text-ui-text-muted">Total unit</dt>
          <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
            {number(preview.totalQuantity)}
          </dd>
        </div>
        <div>
          <dt className="text-sm text-ui-text-muted">Status setelah disimpan</dt>
          <dd className="mt-1 text-sm font-semibold text-ui-text">
            Belum terverifikasi
          </dd>
        </div>
      </dl>

      {preview.blockers.length > 0 ? (
        <div className="mt-5 space-y-3">
          {preview.blockers.map((blocker, index) => (
            <Alert
              key={`${blocker.code}-${blocker.lineNo ?? "document"}-${index}`}
              title={
                blocker.lineNo
                  ? `Baris ${blocker.lineNo} perlu diperbaiki`
                  : "Stok awal belum dapat disimpan"
              }
              tone="danger"
            >
              {blocker.message}
            </Alert>
          ))}
        </div>
      ) : null}

      <div className="mt-5 overflow-hidden border-y border-ui-border">
        <div className="hidden grid-cols-[minmax(0,1fr)_minmax(0,1fr)_8rem_7rem_7rem] gap-4 border-b border-ui-border bg-ui-surface-subtle px-4 py-3 text-xs font-semibold uppercase tracking-wide text-ui-text-muted md:grid">
          <span>Produk</span>
          <span>Batch</span>
          <span>Kondisi</span>
          <span className="text-right">Saat ini</span>
          <span className="text-right">Setelah</span>
        </div>

        <div className="divide-y divide-ui-border">
          {preview.lines.map((line) => (
            <article
              className="grid gap-3 px-4 py-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_8rem_7rem_7rem] md:items-center md:gap-4"
              key={line.openingBalanceLineId}
            >
              <div>
                <p className="text-sm font-semibold text-ui-text">
                  {line.productSku}
                </p>
                <p className="mt-1 text-xs text-ui-text-muted">
                  {line.productName}
                </p>
              </div>

              <div>
                <p className="text-sm font-medium text-ui-text">
                  {line.batchCode}
                </p>
                <p className="mt-1 text-xs text-ui-text-muted">
                  Kedaluwarsa {line.expiryDate}
                </p>
              </div>

              <p className="text-sm text-ui-text">
                {bucketLabel(line.bucketCode)}
              </p>

              <p className="ui-number text-right text-sm text-ui-text">
                {number(line.currentBatchBucketQty)}
              </p>

              <p className="ui-number text-right text-sm font-semibold text-ui-text">
                {number(line.resultingBatchBucketQty)}
              </p>
            </article>
          ))}
        </div>
      </div>

      <details className="mt-4 border-t border-ui-border pt-4">
        <summary className="cursor-pointer text-sm font-semibold text-ui-text">
          Detail teknis
        </summary>
        <dl className="mt-3 grid gap-3 text-xs text-ui-text-muted sm:grid-cols-2">
          <div>
            <dt>Basis preview</dt>
            <dd className="ui-code mt-1 break-all text-ui-text">
              {preview.basisHash}
            </dd>
          </div>
          <div>
            <dt>Request</dt>
            <dd className="ui-code mt-1 break-all text-ui-text">
              {preview.requestHash}
            </dd>
          </div>
        </dl>
      </details>

      {preview.eligible && intentId ? (
        <form
          action={postOpeningBalanceAction}
          className="mt-6 border-t border-ui-border pt-5"
        >
          <input name="cutoverId" type="hidden" value={preview.cutoverId} />
          <input
            name="previewBasisHash"
            type="hidden"
            value={preview.basisHash}
          />
          <input name="intentId" type="hidden" value={intentId} />

          <p className="text-xs font-semibold uppercase tracking-wide text-ui-primary">
            Langkah 3 dari 3
          </p>
          <h3 className="mt-1 text-base font-semibold text-ui-text">
            Konfirmasi stok awal
          </h3>

          <label className="mt-4 flex items-start gap-3 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 text-sm leading-6 text-ui-text">
            <input
              className="mt-1 h-4 w-4"
              name="confirmation"
              required
              type="checkbox"
            />
            <span>
              Saya sudah memeriksa produk, batch, kondisi, dan jumlah.
              Setelah disimpan, stok awal tidak diedit langsung. Koreksi
              dilakukan melalui pembalikan yang tetap menyimpan jejak audit.
            </span>
          </label>

          <Button className="mt-4" type="submit">
            Simpan Stok Awal
          </Button>
        </form>
      ) : null}
    </section>
  );
}

function ReversalPanel({
  preview,
}: {
  preview: OpeningBalanceReversalPreview;
}) {
  const intentId = preview.eligible ? randomUUID() : null;

  return (
    <section
      aria-labelledby="opening-correction-heading"
      className="mt-8 border-t border-ui-border pt-7"
      id="reversal"
    >
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2
            className="text-lg font-semibold text-ui-text"
            id="opening-correction-heading"
          >
            Koreksi Stok Awal
          </h2>
          <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
            Gunakan hanya bila dokumen stok awal memang salah. Sistem akan
            membalik movement asli pada produk, batch, dan kondisi yang sama.
          </p>
        </div>
        <StatusBadge tone={preview.eligible ? "warning" : "danger"}>
          {preview.eligible ? "Koreksi tersedia" : "Diblokir"}
        </StatusBadge>
      </div>

      {preview.blockers.length > 0 ? (
        <div className="mt-5 space-y-3">
          {preview.blockers.map((blocker, index) => (
            <Alert
              key={`${blocker.code}-${index}`}
              title="Koreksi belum dapat dilakukan"
              tone="danger"
            >
              {blocker.message}
            </Alert>
          ))}
        </div>
      ) : null}

      <dl className="mt-5 grid gap-4 border-y border-ui-border py-4 sm:grid-cols-3">
        <div>
          <dt className="text-sm text-ui-text-muted">Baris yang dibalik</dt>
          <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
            {number(preview.lineCount)}
          </dd>
        </div>
        <div>
          <dt className="text-sm text-ui-text-muted">Total unit</dt>
          <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
            {number(preview.totalAbsoluteQuantity)}
          </dd>
        </div>
        <div>
          <dt className="text-sm text-ui-text-muted">Bukti opname tersimpan</dt>
          <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
            {number(preview.verificationApplicationCount)}
          </dd>
        </div>
      </dl>

      {preview.eligible && intentId ? (
        <form
          action={reverseOpeningBalanceAction}
          className="mt-5 space-y-4"
        >
          <input name="cutoverId" type="hidden" value={preview.cutoverId} />
          <input
            name="previewBasisHash"
            type="hidden"
            value={preview.basisHash}
          />
          <input name="intentId" type="hidden" value={intentId} />

          <label className="block">
            <span className="text-sm font-medium text-ui-text">
              Alasan koreksi
            </span>
            <textarea
              className="mt-2 min-h-28 w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 py-2 text-sm text-ui-text"
              maxLength={2000}
              name="note"
              placeholder="Jelaskan kesalahan pada dokumen sumber."
              required
            />
          </label>

          <label className="flex items-start gap-3 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 text-sm leading-6 text-ui-text">
            <input
              className="mt-1 h-4 w-4"
              name="confirmation"
              required
              type="checkbox"
            />
            <span>
              Saya memahami seluruh movement dari stok awal ini akan dibalik.
              Riwayat asli dan bukti opname tidak dihapus.
            </span>
          </label>

          <Button type="submit" variant="danger">
            Koreksi Stok Awal
          </Button>
        </form>
      ) : null}
    </section>
  );
}

export default async function OpeningBalancesPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [session, params] = await Promise.all([
    requireAdminSession(),
    searchParams,
  ]);

  let data: Awaited<ReturnType<typeof getOpeningBalanceData>> | null = null;
  let loadError: string | null = null;

  try {
    data = await getOpeningBalanceData(
      session.profile.organization_id,
      first(params.cutoverId),
    );
  } catch (error) {
    loadError =
      error instanceof Error
        ? error.message
        : "Setup stok awal belum dapat dimuat.";
  }

  if (!data) {
    return (
      <AppShell profile={session.profile}>
        <div className="mx-auto w-full max-w-[1120px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader
            description="Siapkan stok awal sebelum operasional berjalan."
            eyebrow="Pengaturan"
            title="Setup Stok Awal"
          />
          <Alert
            className="mt-6"
            title="Setup stok awal belum dapat dimuat"
            tone="danger"
          >
            {loadError ?? "Coba muat ulang halaman."}
          </Alert>
        </div>
      </AppShell>
    );
  }

  const selected = data.selectedCutover;
  let preview: OpeningBalancePreview | null = null;
  let previewError: string | null = null;
  let reversalPreview: OpeningBalanceReversalPreview | null = null;
  let reversalError: string | null = null;

  if (selected?.status_code === "REVIEW") {
    try {
      preview = await previewOpeningBalanceCutover(
        selected.cutover_id,
        session.profile.organization_id,
      );
    } catch (error) {
      previewError =
        error instanceof Error
          ? error.message
          : "Dampak stok awal belum dapat diperiksa.";
    }
  }

  if (selected?.operational_status_code === "ACTIVE") {
    try {
      reversalPreview = await previewOpeningBalanceReversal(
        selected.cutover_id,
        session.profile.organization_id,
      );
    } catch (error) {
      reversalError =
        error instanceof Error
          ? error.message
          : "Dampak koreksi belum dapat diperiksa.";
    }
  }

  const initialDraftLines: OpeningBalanceDraftLine[] = data.lines.map(
    (line) => ({
      productId: line.product_id,
      batchId: line.batch_id,
      bucketCode: line.bucket_code,
      quantity: line.quantity,
      batchIdentityVerified: line.batch_identity_verified,
      exceptionReference: line.exception_reference,
      sourceLineRef: line.source_line_ref,
    }),
  );

  const success = first(params.success);
  const error = first(params.error);

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1120px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          description="Masukkan perkiraan stok awal, periksa dampaknya, lalu simpan. Stok awal tetap belum terverifikasi sampai opname pertama."
          eyebrow="Pengaturan"
          title="Setup Stok Awal"
        />

        <div className="mt-4">
          <Link
            className="text-sm font-semibold text-ui-primary hover:underline"
            href="/settings"
          >
            Kembali ke Pengaturan
          </Link>
        </div>

        {success ? (
          <Alert className="mt-6" title="Berhasil" tone="success">
            {success}
          </Alert>
        ) : null}

        {error ? (
          <Alert className="mt-6" title="Belum berhasil" tone="danger">
            {error}
          </Alert>
        ) : null}

        <section
          aria-labelledby="opening-status-heading"
          className="mt-6 border-y border-ui-border py-5"
        >
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h2
                className="text-lg font-semibold text-ui-text"
                id="opening-status-heading"
              >
                Status setup
              </h2>
              <p className="mt-1 text-sm text-ui-text-muted">
                Stok awal perkiraan baru menjadi terverifikasi setelah
                opname pertama untuk produk, batch, dan kondisi yang sama.
              </p>
            </div>

            {selected ? (
              <div className="flex flex-wrap gap-2">
                <StatusBadge tone={operationalPresentation(selected).tone}>
                  {operationalPresentation(selected).label}
                </StatusBadge>
                <StatusBadge
                  tone={
                    verificationPresentation(
                      selected.verification_status_code,
                    ).tone
                  }
                >
                  {
                    verificationPresentation(
                      selected.verification_status_code,
                    ).label
                  }
                </StatusBadge>
              </div>
            ) : (
              <StatusBadge tone="neutral">Belum disiapkan</StatusBadge>
            )}
          </div>

          {selected ? (
            <dl className="mt-5 grid gap-5 sm:grid-cols-4">
              <div>
                <dt className="text-sm text-ui-text-muted">Dokumen</dt>
                <dd className="mt-1 text-sm font-semibold text-ui-text">
                  {selected.cutover_no}
                </dd>
              </div>
              <div>
                <dt className="text-sm text-ui-text-muted">Total unit</dt>
                <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                  {number(selected.total_quantity)}
                </dd>
              </div>
              <div>
                <dt className="text-sm text-ui-text-muted">Terverifikasi</dt>
                <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                  {number(selected.verified_line_count)}
                </dd>
              </div>
              <div>
                <dt className="text-sm text-ui-text-muted">Belum terverifikasi</dt>
                <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                  {number(selected.unverified_line_count)}
                </dd>
              </div>
            </dl>
          ) : null}
        </section>

        {!selected ? (
          <section
            aria-labelledby="new-opening-heading"
            className="mt-8"
            id="new"
          >
            <p className="text-xs font-semibold uppercase tracking-wide text-ui-primary">
              Langkah 1 dari 3
            </p>
            <h2
              className="mt-1 text-lg font-semibold text-ui-text"
              id="new-opening-heading"
            >
              Buat dokumen stok awal
            </h2>
            <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
              Membuat draft belum mengubah stok.
            </p>

            <form
              action={createOpeningBalanceAction}
              className="mt-5 grid gap-4 sm:grid-cols-2"
            >
              <label>
                <span className="text-sm font-medium text-ui-text">
                  Referensi dokumen sumber
                </span>
                <input
                  className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
                  maxLength={200}
                  name="sourceRef"
                  placeholder="Contoh: STOK-AWAL-2026"
                  required
                />
              </label>

              <label>
                <span className="text-sm font-medium text-ui-text">
                  Waktu mulai
                </span>
                <input
                  className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
                  defaultValue={defaultDateTimeLocal()}
                  name="cutoverAt"
                  required
                  type="datetime-local"
                />
              </label>

              <label className="sm:col-span-2">
                <span className="text-sm font-medium text-ui-text">
                  Referensi estimasi atau bukti
                </span>
                <input
                  className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
                  maxLength={200}
                  name="sourceEstimateRef"
                  placeholder="Contoh: berita acara atau spreadsheet awal"
                  required
                />
              </label>

              <label className="sm:col-span-2">
                <span className="text-sm font-medium text-ui-text">
                  Catatan
                </span>
                <textarea
                  className="mt-2 min-h-24 w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 py-2 text-sm text-ui-text"
                  maxLength={2000}
                  name="note"
                  placeholder="Jelaskan dasar angka stok awal."
                  required
                />
              </label>

              <div className="sm:col-span-2">
                <Button type="submit">Buat Draft</Button>
              </div>
            </form>
          </section>
        ) : null}

        {selected ? (
          <section className="mt-8" id="detail">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <h2 className="text-lg font-semibold text-ui-text">
                  {selected.cutover_no}
                </h2>
                <p className="mt-1 text-sm text-ui-text-muted">
                  {selected.source_ref} {"Ã‚Â·"} efektif{" "}
                  {selected.effective_local_date}
                </p>
              </div>

              <Link
                className="text-sm font-semibold text-ui-primary hover:underline"
                href="/opening-balances"
              >
                Lihat setup terbaru
              </Link>
            </div>

            <dl className="mt-5 grid gap-4 border-y border-ui-border py-4 sm:grid-cols-2">
              <div>
                <dt className="text-sm text-ui-text-muted">Referensi bukti</dt>
                <dd className="mt-1 text-sm text-ui-text">
                  {selected.source_estimate_ref}
                </dd>
              </div>
              <div>
                <dt className="text-sm text-ui-text-muted">Dibuat</dt>
                <dd className="mt-1 text-sm text-ui-text">
                  {formatDate(selected.created_at)}
                </dd>
              </div>
              <div className="sm:col-span-2">
                <dt className="text-sm text-ui-text-muted">Catatan</dt>
                <dd className="mt-1 text-sm leading-6 text-ui-text">
                  {selected.note}
                </dd>
              </div>
            </dl>

            {selected.status_code === "DRAFT" ? (
              <>
                <div className="mt-6">
                  <OpeningBalanceDraftForm
                    action={saveOpeningBalanceDraftAction}
                    batches={data.batches}
                    eligibleBatches={data.eligibleBatches}
                    cutoverAt={selected.cutover_at}
                    cutoverId={selected.cutover_id}
                    initialLines={initialDraftLines}
                    note={selected.note}
                    rowVersion={selected.row_version}
                    sourceEstimateRef={selected.source_estimate_ref}
                  />
                </div>

                <form
                  action={submitOpeningBalanceReviewAction}
                  className="mt-6 border-t border-ui-border pt-5"
                >
                  <input
                    name="cutoverId"
                    type="hidden"
                    value={selected.cutover_id}
                  />
                  <input
                    name="rowVersion"
                    type="hidden"
                    value={selected.row_version}
                  />

                  <p className="text-sm leading-6 text-ui-text-muted">
                    Setelah masuk tahap periksa, baris stok tidak dapat diedit.
                    Sistem akan menghitung ulang dampaknya terhadap stok.
                  </p>

                  <Button
                    className="mt-4"
                    disabled={selected.line_count === 0}
                    type="submit"
                  >
                    Periksa Sebelum Simpan
                  </Button>
                </form>
              </>
            ) : null}

            {previewError ? (
              <Alert
                className="mt-6"
                title="Dampak stok awal belum dapat diperiksa"
                tone="danger"
              >
                {previewError}
              </Alert>
            ) : null}

            {preview ? <PreviewPanel preview={preview} /> : null}

            {selected.status_code === "POSTED" ? (
              <section className="mt-8 border-t border-ui-border pt-7">
                <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <h2 className="text-lg font-semibold text-ui-text">
                      Verifikasi melalui opname
                    </h2>
                    <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
                      Setiap baris stok awal diverifikasi ketika opname pertama
                      untuk produk, batch, dan kondisi yang sama selesai diposting.
                    </p>
                  </div>
                  <StatusBadge
                    tone={
                      verificationPresentation(
                        selected.verification_status_code,
                      ).tone
                    }
                  >
                    {
                      verificationPresentation(
                        selected.verification_status_code,
                      ).label
                    }
                  </StatusBadge>
                </div>

                <div className="mt-5 divide-y divide-ui-border border-y border-ui-border">
                  {data.lines.map((line) => {
                    const presentation = verificationPresentation(
                      line.verification_status_code,
                    );

                    return (
                      <article
                        className="grid gap-3 py-4 sm:grid-cols-[minmax(0,1fr)_9rem_10rem] sm:items-center"
                        key={line.opening_balance_line_id}
                      >
                        <div>
                          <p className="text-sm font-semibold text-ui-text">
                            {line.product_sku_snapshot} {"Ã‚Â·"}{" "}
                            {line.batch_code_snapshot}
                          </p>
                          <p className="mt-1 text-xs text-ui-text-muted">
                            {bucketLabel(line.bucket_code)} {"Ã‚Â·"}{" "}
                            {number(line.quantity)} unit
                          </p>
                        </div>

                        <StatusBadge tone={presentation.tone}>
                          {presentation.label}
                        </StatusBadge>

                        {line.verifying_stocktake_id ? (
                          <Link
                            className="text-sm font-semibold text-ui-primary hover:underline"
                            href={`/stocktakes/${line.verifying_stocktake_id}`}
                          >
                            Buka Opname
                          </Link>
                        ) : (
                          <span className="text-sm text-ui-text-muted">
                            Belum dihitung
                          </span>
                        )}
                      </article>
                    );
                  })}
                </div>

                <details className="mt-5 border-t border-ui-border pt-4">
                  <summary className="cursor-pointer text-sm font-semibold text-ui-text">
                    Bukti audit
                  </summary>
                  <div className="mt-3 space-y-3">
                    {data.lines
                      .filter((line) => line.verification_application_id)
                      .map((line) => (
                        <div
                          className="rounded-[var(--ui-radius-md)] border border-ui-border p-4 text-xs text-ui-text-muted"
                          key={line.opening_balance_line_id}
                        >
                          <p className="font-semibold text-ui-text">
                            {line.product_sku_snapshot} {"Ã‚Â·"}{" "}
                            {line.batch_code_snapshot}
                          </p>
                          <p className="mt-2">
                            Opname: {line.verifying_stocktake_no ?? "Tidak tersedia"}
                          </p>
                          <p className="mt-1">
                            Jumlah fisik: {number(line.verifying_physical_quantity)}
                            {" Ã‚Â· "}Selisih: {number(line.verifying_variance_quantity)}
                          </p>
                          <p className="ui-code mt-2 break-all">
                            {line.verification_application_id}
                          </p>
                        </div>
                      ))}
                  </div>
                </details>
              </section>
            ) : null}

            {selected.status_code === "POSTED" && data.ledger.length > 0 ? (
              <section className="mt-8 border-t border-ui-border pt-7">
                <div>
                  <h2 className="text-lg font-semibold text-ui-text">
                    Riwayat perubahan stok awal
                  </h2>
                  <p className="mt-1 text-sm leading-6 text-ui-text-muted">
                    Movement INITIAL_BALANCE tetap tersedia sebagai bukti audit.
                  </p>
                </div>

                <div className="mt-5 divide-y divide-ui-border border-y border-ui-border">
                  {data.ledger.map((entry) => (
                    <article
                      className="grid gap-2 py-4 sm:grid-cols-[7rem_minmax(0,1fr)_minmax(0,1fr)_8rem] sm:items-center"
                      key={entry.ledger_entry_id}
                    >
                      <p className="ui-number text-sm text-ui-text-muted">
                        #{number(entry.ledger_seq)}
                      </p>
                      <div>
                        <p className="text-sm font-semibold text-ui-text">
                          {entry.product_sku_snapshot}
                        </p>
                        <p className="mt-1 text-xs text-ui-text-muted">
                          {entry.batch_code_snapshot}
                        </p>
                      </div>
                      <p className="text-sm text-ui-text">
                        {bucketLabel(entry.bucket_code)}
                      </p>
                      <p className="ui-number text-sm font-semibold text-ui-text sm:text-right">
                        {entry.quantity_delta > 0 ? "+" : ""}
                        {number(entry.quantity_delta)}
                      </p>
                    </article>
                  ))}
                </div>

                {selected.transaction_id ? (
                  <Link
                    className="mt-4 inline-flex min-h-[var(--ui-control-height)] items-center font-semibold text-ui-primary hover:underline"
                    href={`/ledger/${encodeURIComponent(selected.transaction_id)}`}
                  >
                    Buka Riwayat Stok
                  </Link>
                ) : null}
              </section>
            ) : null}

            {reversalError ? (
              <Alert
                className="mt-6"
                title="Koreksi stok awal belum dapat diperiksa"
                tone="danger"
              >
                {reversalError}
              </Alert>
            ) : null}

            {reversalPreview ? (
              <ReversalPanel preview={reversalPreview} />
            ) : null}

            {data.selectedReversal ? (
              <section className="mt-8 border-t border-ui-border pt-7" id="reversal-audit">
                <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <h2 className="text-lg font-semibold text-ui-text">
                      Koreksi stok awal selesai
                    </h2>
                    <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
                      Riwayat asli tetap tersimpan. Movement koreksi tercatat terpisah sebagai jejak audit.
                    </p>
                  </div>
                  <StatusBadge tone="danger">Sudah dikoreksi</StatusBadge>
                </div>

                <dl className="mt-5 grid gap-4 border-y border-ui-border py-4 sm:grid-cols-2 lg:grid-cols-4">
                  <div><dt className="text-sm text-ui-text-muted">Dokumen</dt><dd className="mt-1 text-sm font-semibold text-ui-text">{data.selectedReversal.cutover_no}</dd></div>
                  <div><dt className="text-sm text-ui-text-muted">Transaksi asal</dt><dd className="mt-1 text-sm text-ui-text">{data.selectedReversal.original_transaction_no}</dd></div>
                  <div><dt className="text-sm text-ui-text-muted">Transaksi koreksi</dt><dd className="mt-1 text-sm text-ui-text">{data.selectedReversal.reversal_transaction_no}</dd></div>
                  <div><dt className="text-sm text-ui-text-muted">Waktu koreksi</dt><dd className="mt-1 text-sm text-ui-text">{formatDate(data.selectedReversal.reversed_at)}</dd></div>
                </dl>

                <p className="mt-4 text-sm leading-6 text-ui-text-muted">
                  Alasan koreksi: <span className="font-medium text-ui-text">{data.selectedReversal.note}</span>
                </p>

                {data.reversalLedger.length > 0 ? (
                  <div className="mt-5 divide-y divide-ui-border border-y border-ui-border">
                    {data.reversalLedger.map((entry) => (
                      <article className="grid gap-2 py-3 sm:grid-cols-[7rem_minmax(0,1fr)_minmax(0,1fr)_8rem] sm:items-center" key={entry.ledger_entry_id}>
                        <p className="ui-number text-sm text-ui-text-muted">#{number(entry.ledger_seq)}</p>
                        <p className="text-sm font-semibold text-ui-text">{entry.product_sku_snapshot}</p>
                        <p className="text-sm text-ui-text">{entry.batch_code_snapshot}</p>
                        <p className="ui-number text-sm font-semibold text-ui-text sm:text-right">{number(entry.quantity_delta)}</p>
                      </article>
                    ))}
                  </div>
                ) : null}

                <div className="mt-5 flex flex-wrap gap-4">
                  <Link className="inline-flex min-h-[var(--ui-control-height)] items-center font-semibold text-ui-primary hover:underline" href="/opening-balances#new">
                    Buat Saldo Awal Pengganti
                  </Link>
                  <Link className="inline-flex min-h-[var(--ui-control-height)] items-center font-semibold text-ui-primary hover:underline" href={`/ledger/${encodeURIComponent(data.selectedReversal.reversal_transaction_id)}`}>
                    Buka Transaksi Koreksi
                  </Link>
                </div>
              </section>
            ) : null}
          </section>
        ) : (
          <EmptyState
            className="mt-8"
            description="Buat dokumen stok awal untuk memulai setup."
            title="Belum ada setup stok awal"
          />
        )}

        <section
          aria-labelledby="opening-history-heading"
          className="mt-10 border-t border-ui-border pt-7"
        >
          <h2
            className="text-lg font-semibold text-ui-text"
            id="opening-history-heading"
          >
            Riwayat Setup Stok Awal
          </h2>
          <p className="mt-1 text-sm text-ui-text-muted">
            Dokumen lama tetap tersedia sebagai jejak audit.
          </p>

          {data.cutovers.length === 0 ? (
            <EmptyState
              className="mt-4"
              description="Riwayat akan muncul setelah dokumen pertama dibuat."
              title="Belum ada riwayat"
            />
          ) : (
            <div className="mt-4 divide-y divide-ui-border border-y border-ui-border">
              {data.cutovers.map((cutover) => {
                const operational = operationalPresentation(cutover);
                const verification = verificationPresentation(
                  cutover.verification_status_code,
                );

                return (
                  <article
                    className="grid gap-3 py-4 sm:grid-cols-[minmax(0,1fr)_9rem_11rem_auto] sm:items-center"
                    key={cutover.cutover_id}
                  >
                    <div>
                      <p className="text-sm font-semibold text-ui-text">
                        {cutover.cutover_no}
                      </p>
                      <p className="mt-1 text-xs text-ui-text-muted">
                        {cutover.source_ref} {"Ã‚Â·"}{" "}
                        {number(cutover.total_quantity)} unit
                      </p>
                    </div>

                    <StatusBadge tone={operational.tone}>
                      {operational.label}
                    </StatusBadge>

                    <StatusBadge tone={verification.tone}>
                      {verification.label}
                    </StatusBadge>

                    <Link
                      className="text-sm font-semibold text-ui-primary hover:underline"
                      href={`/opening-balances?cutoverId=${encodeURIComponent(
                        cutover.cutover_id,
                      )}#detail`}
                    >
                      Buka
                    </Link>
                  </article>
                );
              })}
            </div>
          )}
        </section>
      </div>
    </AppShell>
  );
}
