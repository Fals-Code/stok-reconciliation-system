import { randomUUID } from "node:crypto";
import Link from "next/link";

import PageSectionNav from "@/app/app-shell/page-section-nav";
import {
  postMarketplaceCancellationAction,
} from "@/app/marketplace/cancellations/actions";
import MarketplaceCancellationDraftForm from "@/app/marketplace/cancellations/components/draft-form";
import {
  marketplaceCancellationErrorMessage,
  marketplaceCancellationOccurredAt,
  parseMarketplaceCancellationDraft,
  serializeMarketplaceCancellationDraft,
  type MarketplaceCancellationDraft,
  type MarketplaceCancellationPhaseCode,
} from "@/app/marketplace/cancellations/draft";
import {
  getMarketplaceData,
  previewMarketplaceCancellation,
  type MarketplaceCancellationApplication,
  type MarketplaceCancellationCandidate,
  type MarketplaceCancellationPreview,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = {
  cancellationDraft?: string;
  success?: string;
  error?: string;
  cancellationId?: string;
  cancellationEventId?: string;
  transactionId?: string;
};

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number | null | undefined) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return "—";
  }

  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null | undefined) {
  if (!value) return "—";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
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

  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );

  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

function defaultDraft(
  candidates: MarketplaceCancellationCandidate[],
): MarketplaceCancellationDraft {
  const candidate = candidates.find(
    (row) => Number(row.open_reserved_qty) > 0,
  ) ?? candidates.find(
    (row) => Number(row.remaining_post_cancellable_qty) > 0,
  ) ?? null;

  const phaseCode: MarketplaceCancellationPhaseCode =
    candidate && Number(candidate.open_reserved_qty) > 0
      ? "PRE_SHIPMENT"
      : "POST_SHIPMENT";

  return {
    channelCode: candidate?.channel_code ?? "SHOPEE",
    eventRef: "",
    orderRef: candidate?.external_order_ref ?? "",
    occurredAt: defaultDateTimeLocal(),
    sourceStatus: "CANCELLED",
    lines: candidate
      ? [
          {
            productId: candidate.product_id,
            orderItemRef: candidate.external_item_ref,
            phaseCode,
            quantity: 1,
            sourceLineRef: "UI-1",
          },
        ]
      : [],
    note: null,
  };
}

function phaseLabel(phaseCode: MarketplaceCancellationPhaseCode) {
  return phaseCode === "PRE_SHIPMENT"
    ? "Sebelum shipment"
    : "Sesudah shipment";
}

function Pill({
  label,
  tone = "neutral",
}: {
  label: string;
  tone?: "success" | "warning" | "danger" | "info" | "neutral";
}) {
  const tones = {
    success: "border-emerald-400/25 bg-emerald-400/10 text-emerald-200",
    warning: "border-amber-400/25 bg-amber-400/10 text-amber-100",
    danger: "border-rose-400/25 bg-rose-400/10 text-rose-100",
    info: "border-sky-400/25 bg-sky-400/10 text-sky-100",
    neutral: "border-white/10 bg-white/[0.04] text-slate-300",
  };

  return (
    <span
      className={`inline-flex rounded-full border px-2.5 py-1 text-xs font-medium ${tones[tone]}`}
    >
      {label}
    </span>
  );
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="section-kicker text-amber-300">
          Pembatalan marketplace tidak tersedia
        </p>
        <h1 className="mt-3 text-3xl font-semibold">
          Data operasional gagal dimuat.
        </h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <Link className="nav-link mt-6 inline-flex" href="/marketplace">
          Kembali ke Marketplace
        </Link>
      </section>
    </main>
  );
}

function PreviewPanel({
  draft,
  preview,
}: {
  draft: MarketplaceCancellationDraft;
  preview: MarketplaceCancellationPreview;
}) {
  const intentId = preview.eligible ? randomUUID() : null;
  const applications = preview.lines.flatMap((line) =>
    line.applications.map((application) => ({
      line,
      application,
    })),
  );
  const requiresConfirmation = preview.postShipmentQuantity > 0;

  return (
    <section className="panel-card mt-6" id="cancellation-preview">
      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="section-kicker">Preview authoritative</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">
            Dampak reservasi dan ledger sebelum commit.
          </h2>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Pembatalan sebelum shipment hanya melepaskan reservasi. Pembatalan
            sesudah shipment memulihkan batch persis dari alokasi shipment asal,
            tanpa menjalankan FEFO ulang.
          </p>
        </div>
        <Pill
          label={preview.eligible ? "Siap diposting" : "Diblokir"}
          tone={preview.eligible ? "success" : "danger"}
        />
      </div>

      <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {[
          ["Event", preview.eventRef],
          ["Order", preview.orderRef],
          ["Channel", preview.channelCode],
          ["Status sumber", preview.sourceStatus],
          ["Total quantity", formatNumber(preview.totalRequestedQuantity)],
          ["Pre-shipment", formatNumber(preview.preShipmentQuantity)],
          ["Post-shipment", formatNumber(preview.postShipmentQuantity)],
          ["Tanggal efektif", preview.effectiveLocalDate],
        ].map(([label, value]) => (
          <div
            className="rounded-2xl border border-white/10 bg-slate-950/35 p-4"
            key={label}
          >
            <dt className="text-xs text-slate-500">{label}</dt>
            <dd className="mt-2 text-sm font-medium text-slate-100">
              {value}
            </dd>
          </div>
        ))}
      </dl>

      {preview.blockers.length > 0 ? (
        <div className="mt-5 space-y-3">
          {preview.blockers.map((blocker, index) => (
            <article
              className="rounded-2xl border border-rose-400/20 bg-rose-400/[0.06] p-4"
              key={`${blocker.code}-${blocker.lineNo ?? "request"}-${index}`}
            >
              <p className="font-medium text-rose-100">{blocker.message}</p>
              <p className="mt-2 text-xs text-rose-300/75">
                Kode {blocker.code}
                {blocker.lineNo ? ` · baris ${blocker.lineNo}` : ""}
              </p>
            </article>
          ))}
        </div>
      ) : null}

      <div className="mt-6 overflow-x-auto rounded-2xl border border-white/10 bg-slate-950/35">
        <table>
          <thead>
            <tr>
              <th>Item</th>
              <th>SKU</th>
              <th>Fase</th>
              <th className="text-right">Quantity</th>
              <th className="text-right">Open reserved</th>
              <th className="text-right">Open setelah</th>
              <th className="text-right">Post cancellable</th>
              <th className="text-right">Post setelah</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {preview.lines.map((line) => (
              <tr key={`${line.sourceLineRef}-${line.phaseCode}`}>
                <td className="font-mono text-xs text-white">
                  {line.orderItemRef}
                </td>
                <td>{line.productSku ?? line.productId}</td>
                <td>
                  <Pill
                    label={phaseLabel(line.phaseCode)}
                    tone={
                      line.phaseCode === "POST_SHIPMENT"
                        ? "warning"
                        : "info"
                    }
                  />
                </td>
                <td className="text-right font-mono font-semibold text-white">
                  {formatNumber(line.quantity)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(line.openReservedBefore)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(line.openReservedAfter)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(line.remainingPostCancellableBefore)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(line.remainingPostCancellableAfter)}
                </td>
                <td>
                  <Pill
                    label={line.eligible ? "Siap" : "Diblokir"}
                    tone={line.eligible ? "success" : "danger"}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {applications.length > 0 ? (
        <div className="mt-6">
          <div className="mb-3">
            <p className="section-kicker">Exact restoration</p>
            <h3 className="mt-1 text-lg font-semibold text-white">
              Batch dan ledger shipment yang akan dibalik.
            </h3>
          </div>
          <div className="overflow-x-auto rounded-2xl border border-white/10 bg-slate-950/35">
            <table>
              <thead>
                <tr>
                  <th>Item</th>
                  <th>Effect</th>
                  <th>Shipment</th>
                  <th>Ledger asal</th>
                  <th>Batch</th>
                  <th>Expiry</th>
                  <th className="text-right">Quantity</th>
                  <th className="text-right">Batch kini</th>
                  <th className="text-right">Batch setelah</th>
                </tr>
              </thead>
              <tbody>
                {applications.map(({ line, application }) => (
                  <tr
                    key={`${line.sourceLineRef}-${application.applicationNo}`}
                  >
                    <td>{line.orderItemRef}</td>
                    <td>
                      <Pill
                        label={
                          application.effectCode ===
                          "POST_SHIPMENT_REVERSAL"
                            ? "Ledger reversal"
                            : "Release reservation"
                        }
                        tone={
                          application.effectCode ===
                          "POST_SHIPMENT_REVERSAL"
                            ? "warning"
                            : "info"
                        }
                      />
                    </td>
                    <td className="font-mono text-xs">
                      {application.originalTransactionNo ??
                        application.shipEventRef ??
                        "non-physical"}
                    </td>
                    <td className="font-mono text-xs text-slate-400">
                      {application.originalLedgerEntryId ?? "—"}
                    </td>
                    <td className="font-mono text-xs">
                      {application.batchCode ?? "—"}
                    </td>
                    <td>{application.expiryDate ?? "—"}</td>
                    <td className="text-right font-mono font-semibold text-white">
                      +{formatNumber(application.quantity)}
                    </td>
                    <td className="text-right font-mono">
                      {formatNumber(application.batchSellableBefore)}
                    </td>
                    <td className="text-right font-mono font-semibold text-emerald-200">
                      {formatNumber(application.batchSellableAfter)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}

      <details className="mt-4 rounded-2xl border border-white/10 bg-white/[0.02]">
        <summary className="cursor-pointer px-5 py-4 text-sm font-medium text-slate-300 transition hover:text-white">
          Detail teknis preview
        </summary>
        <dl className="grid gap-3 border-t border-white/10 p-5 sm:grid-cols-2">
          <div className="rounded-xl border border-white/10 bg-slate-950/35 p-4">
            <dt className="text-xs text-slate-500">Basis hash</dt>
            <dd className="mt-2 break-all font-mono text-xs text-slate-300">
              {preview.basisHash}
            </dd>
          </div>
          <div className="rounded-xl border border-white/10 bg-slate-950/35 p-4">
            <dt className="text-xs text-slate-500">Request hash</dt>
            <dd className="mt-2 break-all font-mono text-xs text-slate-300">
              {preview.requestHash}
            </dd>
          </div>
        </dl>
      </details>

      {preview.eligible && intentId ? (
        <form
          action={postMarketplaceCancellationAction}
          className="mt-6 rounded-3xl border border-amber-400/25 bg-amber-400/[0.055] p-5 lg:p-6"
        >
          <input
            name="draft"
            type="hidden"
            value={serializeMarketplaceCancellationDraft(draft)}
          />
          <input
            name="previewBasisHash"
            type="hidden"
            value={preview.basisHash}
          />
          <input name="intentId" type="hidden" value={intentId} />

          <h3 className="text-lg font-semibold text-amber-50">
            Konfirmasi final pembatalan
          </h3>
          <p className="mt-2 text-sm leading-6 text-amber-100/80">
            {requiresConfirmation
              ? "Quantity sesudah shipment akan membuat REVERSAL append-only ke batch dan ledger asal. Shipment asli tidak diedit."
              : "Quantity sebelum shipment hanya akan dilepas dari reservasi. Tidak ada pergerakan stok fisik."}
          </p>

          {requiresConfirmation ? (
            <label className="mt-4 flex items-start gap-3 rounded-2xl border border-amber-300/20 bg-slate-950/25 p-4 text-sm leading-6 text-amber-50">
              <input
                className="mt-1 h-4 w-4"
                name="confirmation"
                required
                type="checkbox"
              />
              Saya sudah memeriksa batch, ledger shipment asal, dan quantity
              reversal yang ditampilkan di preview.
            </label>
          ) : null}

          <button className="primary-button mt-5" type="submit">
            {requiresConfirmation
              ? "Posting reversal pembatalan"
              : "Lepaskan reservasi"}
          </button>
        </form>
      ) : null}
    </section>
  );
}

function applicationTone(
  application: MarketplaceCancellationApplication,
) {
  return application.effect_code === "POST_SHIPMENT_REVERSAL"
    ? "warning"
    : "info";
}

export default async function MarketplaceCancellationPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const feedback = await searchParams;
  let marketplace;

  try {
    marketplace = await getMarketplaceData();
  } catch (error) {
    return (
      <ConfigurationError
        message={
          error instanceof Error ? error.message : "Konfigurasi tidak valid."
        }
      />
    );
  }

  const candidates = marketplace.candidates.filter(
    (candidate) => Number(candidate.total_remaining_cancellable_qty) > 0,
  );
  let draft = defaultDraft(candidates);
  let preview: MarketplaceCancellationPreview | null = null;
  let draftError: string | null = null;

  if (feedback.cancellationDraft) {
    try {
      draft = parseMarketplaceCancellationDraft(
        feedback.cancellationDraft,
      );
      preview = await previewMarketplaceCancellation({
        ...draft,
        occurredAt: marketplaceCancellationOccurredAt(draft),
        metadata: {
          source: "marketplace-cancellation-admin-ui",
          version: 1,
        },
      });
    } catch (error) {
      draftError = marketplaceCancellationErrorMessage(error);
    }
  }

  const selectedCancellation =
    marketplace.cancellations.find(
      (row) => row.cancellation_id === feedback.cancellationId,
    ) ??
    marketplace.cancellations[0] ??
    null;
  const selectedLines = selectedCancellation
    ? marketplace.cancellationLines.filter(
        (line) =>
          line.cancellation_id === selectedCancellation.cancellation_id,
      )
    : [];
  const selectedApplications = selectedCancellation
    ? marketplace.cancellationApplications.filter(
        (application) =>
          application.cancellation_id ===
          selectedCancellation.cancellation_id,
      )
    : [];

  const totalPre = marketplace.cancellations.reduce(
    (sum, row) => sum + Number(row.pre_shipment_quantity),
    0,
  );
  const totalPost = marketplace.cancellations.reduce(
    (sum, row) => sum + Number(row.post_shipment_quantity),
    0,
  );

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <PageSectionNav
        items={[
          { href: "#cancellation-draft", label: "Draft" },
          { href: "#cancellation-preview", label: "Preview" },
          { href: "#cancellation-history", label: "Riwayat" },
          { href: "#cancellation-detail", label: "Drill-down" },
        ]}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section>
          <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="section-kicker">Marketplace cancellation</p>
              <h1 className="mt-3 max-w-4xl text-3xl font-semibold tracking-tight sm:text-4xl">
                Batalkan quantity per item dengan dampak stok yang dapat
                diverifikasi.
              </h1>
              <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
                Sebelum shipment, sistem hanya melepas reservasi. Sesudah
                shipment, sistem membalik batch dan ledger persis dari alokasi
                asal. Admin tidak memilih batch dan shipment asli tetap
                immutable.
              </p>
            </div>
            <Link
              className="nav-link inline-flex w-fit"
              href="/marketplace"
            >
              Kembali ke lifecycle marketplace
            </Link>
          </div>

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              [
                "Item cancellable",
                candidates.length,
                "Masih memiliki quantity yang sah",
              ],
              [
                "Event cancellation",
                marketplace.cancellations.length,
                "Riwayat append-only",
              ],
              [
                "Pre-shipment released",
                totalPre,
                "Tanpa movement stok",
              ],
              [
                "Post-shipment reversed",
                totalPost,
                "Exact original batch",
              ],
            ].map(([label, value, description]) => (
              <article className="metric-card" key={label}>
                <p className="text-sm text-slate-400">{label}</p>
                <p className="mt-3 text-3xl font-semibold text-white">
                  {formatNumber(Number(value))}
                </p>
                <p className="mt-2 text-xs text-slate-500">
                  {description}
                </p>
              </article>
            ))}
          </div>
        </section>

        {feedback.success ? (
          <div className="mt-8 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-200">
            {feedback.success}
          </div>
        ) : null}

        {feedback.error ? (
          <div className="mt-8 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-200">
            {feedback.error}
          </div>
        ) : null}

        {draftError ? (
          <div className="mt-8 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-200">
            {draftError}
          </div>
        ) : null}

        <section className="mt-10">
          <MarketplaceCancellationDraftForm
            candidates={candidates}
            initialDraft={draft}
          />
        </section>

        {preview ? <PreviewPanel draft={draft} preview={preview} /> : null}

        <section
          className="mt-10 scroll-mt-24"
          id="cancellation-history"
        >
          <div>
            <p className="section-kicker">Immutable history</p>
            <h2 className="section-title">
              Event pembatalan yang sudah diposting.
            </h2>
          </div>

          <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10 bg-white/[0.025]">
            <table>
              <thead>
                <tr>
                  <th>Cancellation</th>
                  <th>Event</th>
                  <th>Order</th>
                  <th>Channel</th>
                  <th className="text-right">Pre</th>
                  <th className="text-right">Post</th>
                  <th className="text-right">Total</th>
                  <th>Occurred</th>
                  <th>Detail</th>
                </tr>
              </thead>
              <tbody>
                {marketplace.cancellations.length === 0 ? (
                  <tr>
                    <td className="text-center text-slate-500" colSpan={9}>
                      Belum ada pembatalan marketplace.
                    </td>
                  </tr>
                ) : (
                  marketplace.cancellations.map((cancellation) => (
                    <tr key={cancellation.cancellation_id}>
                      <td className="font-mono text-xs text-white">
                        {cancellation.cancellation_no}
                      </td>
                      <td className="font-mono text-xs">
                        {cancellation.external_event_ref}
                      </td>
                      <td>{cancellation.external_order_ref}</td>
                      <td>{cancellation.channel_code}</td>
                      <td className="text-right font-mono">
                        {formatNumber(
                          cancellation.pre_shipment_quantity,
                        )}
                      </td>
                      <td className="text-right font-mono">
                        {formatNumber(
                          cancellation.post_shipment_quantity,
                        )}
                      </td>
                      <td className="text-right font-mono font-semibold text-white">
                        {formatNumber(cancellation.total_quantity)}
                      </td>
                      <td className="whitespace-nowrap">
                        {formatDate(cancellation.occurred_at)}
                      </td>
                      <td>
                        <Link
                          className="nav-link"
                          href={`/marketplace/cancellations?cancellationId=${encodeURIComponent(
                            cancellation.cancellation_id,
                          )}#cancellation-detail`}
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
        </section>

        <section
          className="mt-10 scroll-mt-24 pb-12"
          id="cancellation-detail"
        >
          <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="section-kicker">Audit drill-down</p>
              <h2 className="section-title">
                Cancellation → shipment → ledger reversal.
              </h2>
            </div>
            <div className="flex flex-wrap gap-2">
              <Link className="nav-link" href="/marketplace#events">
                Event timeline
              </Link>
              <Link className="nav-link" href="/marketplace#allocations">
                Shipment FEFO
              </Link>
            </div>
          </div>

          {!selectedCancellation ? (
            <div className="mt-5 rounded-2xl border border-white/10 bg-white/[0.025] p-6 text-sm text-slate-400">
              Belum ada cancellation yang dapat ditelusuri.
            </div>
          ) : (
            <>
              <article className="panel-card mt-5">
                <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <p className="font-mono text-xs text-sky-200">
                      {selectedCancellation.cancellation_no}
                    </p>
                    <h3 className="mt-2 text-xl font-semibold text-white">
                      {selectedCancellation.external_order_ref}
                    </h3>
                    <p className="mt-2 text-sm text-slate-400">
                      Event {selectedCancellation.external_event_ref} ·{" "}
                      {selectedCancellation.source_status_code}
                    </p>
                  </div>
                  <Pill label="POSTED" tone="success" />
                </div>

                <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  {[
                    ["Channel", selectedCancellation.channel_code],
                    [
                      "Pre-shipment",
                      formatNumber(
                        selectedCancellation.pre_shipment_quantity,
                      ),
                    ],
                    [
                      "Post-shipment",
                      formatNumber(
                        selectedCancellation.post_shipment_quantity,
                      ),
                    ],
                    [
                      "Recorded",
                      formatDate(selectedCancellation.recorded_at),
                    ],
                  ].map(([label, value]) => (
                    <div
                      className="rounded-2xl border border-white/10 bg-slate-950/35 p-4"
                      key={label}
                    >
                      <dt className="text-xs text-slate-500">{label}</dt>
                      <dd className="mt-2 text-sm font-medium text-slate-100">
                        {value}
                      </dd>
                    </div>
                  ))}
                </dl>
              </article>

              <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10 bg-white/[0.025]">
                <table>
                  <thead>
                    <tr>
                      <th>Line</th>
                      <th>Item</th>
                      <th>SKU</th>
                      <th>Fase</th>
                      <th className="text-right">Quantity</th>
                      <th className="text-right">Open sebelum</th>
                      <th className="text-right">Open setelah</th>
                    </tr>
                  </thead>
                  <tbody>
                    {selectedLines.map((line) => (
                      <tr key={line.cancellation_line_id}>
                        <td>#{line.line_no}</td>
                        <td className="font-mono text-xs text-white">
                          {line.order_item_ref_snapshot}
                        </td>
                        <td>{line.product_sku_snapshot}</td>
                        <td>
                          <Pill
                            label={phaseLabel(line.phase_code)}
                            tone={
                              line.phase_code === "POST_SHIPMENT"
                                ? "warning"
                                : "info"
                            }
                          />
                        </td>
                        <td className="text-right font-mono font-semibold text-white">
                          {formatNumber(line.quantity_cancelled)}
                        </td>
                        <td className="text-right font-mono">
                          {formatNumber(line.open_reserved_before)}
                        </td>
                        <td className="text-right font-mono">
                          {formatNumber(line.open_reserved_after)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10 bg-white/[0.025]">
                <table>
                  <thead>
                    <tr>
                      <th>Application</th>
                      <th>Effect</th>
                      <th className="text-right">Quantity</th>
                      <th>Shipment event</th>
                      <th>Original transaction</th>
                      <th>Reversal transaction</th>
                      <th>Batch</th>
                      <th>Ledger link</th>
                    </tr>
                  </thead>
                  <tbody>
                    {selectedApplications.length === 0 ? (
                      <tr>
                        <td className="text-center text-slate-500" colSpan={8}>
                          Belum ada application untuk cancellation ini.
                        </td>
                      </tr>
                    ) : (
                      selectedApplications.map((application) => (
                        <tr
                          key={application.cancellation_application_id}
                        >
                          <td>#{application.application_no}</td>
                          <td>
                            <Pill
                              label={application.effect_code}
                              tone={applicationTone(application)}
                            />
                          </td>
                          <td className="text-right font-mono font-semibold text-white">
                            {formatNumber(application.quantity_applied)}
                          </td>
                          <td className="font-mono text-xs">
                            {application.original_ship_event_ref ?? "—"}
                          </td>
                          <td className="font-mono text-xs">
                            {application.original_transaction_no ?? "—"}
                          </td>
                          <td>
                            {application.reversal_transaction_id ? (
                              <Link
                                className="nav-link font-mono text-xs"
                                href={`/entry-corrections?transactionId=${encodeURIComponent(
                                  application.reversal_transaction_id,
                                )}`}
                              >
                                {application.reversal_transaction_no ??
                                  application.reversal_transaction_id}
                              </Link>
                            ) : (
                              "non-physical"
                            )}
                          </td>
                          <td className="font-mono text-xs">
                            {application.batch_code_snapshot ?? "—"}
                          </td>
                          <td className="font-mono text-xs text-slate-500">
                            {application.original_ledger_entry_id
                              ? `${application.original_ledger_entry_id.slice(
                                  0,
                                  8,
                                )}… → ${
                                  application.reversal_entry_id?.slice(
                                    0,
                                    8,
                                  ) ?? "—"
                                }…`
                              : "—"}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </section>
      </div>
    </main>
  );
}
