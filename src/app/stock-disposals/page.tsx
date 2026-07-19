import { randomUUID } from "node:crypto";
import Link from "next/link";

import PageSectionNav from "@/app/app-shell/page-section-nav";
import { postStockDisposalAction } from "@/app/stock-disposals/actions";
import StockDisposalDraftForm from "@/app/stock-disposals/components/draft-form";
import {
  parseStockDisposalDraft,
  serializeStockDisposalDraft,
  stockDisposalErrorMessage,
  stockDisposalOccurredAt,
  type StockDisposalDraft,
} from "@/app/stock-disposals/draft";
import {
  getStockDisposalData,
  previewStockDisposal,
  type StockDisposalLine,
  type StockDisposalPreview,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = {
  draft?: string;
  success?: string;
  error?: string;
  disposalId?: string;
  transactionId?: string;
};

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number | null | undefined) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return "-";
  }

  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null) {
  if (!value) return "Belum tersedia";

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;

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

function emptyDraft(): StockDisposalDraft {
  return {
    sourceRef: "",
    occurredAt: defaultDateTimeLocal(),
    reasonCode: "EXPIRED_DISPOSAL",
    lines: [
      {
        productId: "",
        batchId: "",
        sourceBucketCode: "SELLABLE",
        quantity: 1,
        sourceLineRef: "UI-1",
      },
    ],
    referenceText: "",
    note: "",
  };
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

function reasonLabel(code: string) {
  return code === "DAMAGED_DISPOSAL"
    ? "Barang rusak"
    : "Barang kedaluwarsa";
}

function bucketLabel(code: string) {
  const labels: Record<string, string> = {
    SELLABLE: "Layak jual",
    QUARANTINE: "Karantina",
    DAMAGED: "Rusak",
  };

  return labels[code] ?? code;
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="section-kicker text-amber-300">
          Rusak & Kedaluwarsa tidak tersedia
        </p>
        <h1 className="mt-3 text-3xl font-semibold">
          Data operasional gagal dimuat.
        </h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <Link className="nav-link mt-6 inline-flex" href="/">
          Kembali ke dashboard
        </Link>
      </section>
    </main>
  );
}

function PreviewPanel({
  draft,
  preview,
}: {
  draft: StockDisposalDraft;
  preview: StockDisposalPreview;
}) {
  const intentId = preview.eligible ? randomUUID() : null;

  return (
    <section className="panel-card mt-6">
      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="section-kicker">Preview authoritative</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">
            Dampak stok exact batch dan bucket.
          </h2>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Database menghitung saldo sebelum dan sesudah tanpa menulis dokumen,
            ledger, projection, atau idempotency command.
          </p>
        </div>
        <Pill
          label={preview.eligible ? "Siap diposting" : "Diblokir"}
          tone={preview.eligible ? "success" : "danger"}
        />
      </div>

      <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {[
          ["Referensi", preview.sourceRef],
          ["Alasan", preview.reasonName],
          ["Bukti", preview.referenceText],
          ["Tanggal efektif", preview.effectiveLocalDate],
          ["Jumlah baris", formatNumber(preview.lineCount)],
          ["Total quantity", formatNumber(preview.totalRequestedQuantity)],
          ["Channel", preview.channelCode],
          ["Zona waktu", preview.organizationTimezone],
        ].map(([label, value]) => (
          <div
            className="rounded-2xl border border-white/10 bg-slate-950/35 p-4"
            key={label}
          >
            <dt className="text-xs text-slate-500">{label}</dt>
            <dd className="mt-2 text-sm font-medium text-slate-100">{value}</dd>
          </div>
        ))}
      </dl>

      {preview.blockers.length ? (
        <div className="mt-5 space-y-3">
          {preview.blockers.map((blocker, index) => (
            <article
              className="rounded-2xl border border-rose-400/20 bg-rose-400/[0.06] p-4"
              key={`${blocker.code}-${blocker.lineNo ?? "request"}-${index}`}
            >
              <p className="font-medium text-rose-100">{blocker.message}</p>
              <p className="mt-2 text-xs text-rose-300/75">
                {blocker.lineNo ? `Baris ${blocker.lineNo} â€¢ ` : ""}
                kode {blocker.code}
              </p>
            </article>
          ))}
        </div>
      ) : null}

      <div className="mt-6 overflow-x-auto rounded-2xl border border-white/10 bg-slate-950/35">
        <table>
          <thead>
            <tr>
              <th>Produk / batch</th>
              <th>Bucket</th>
              <th className="text-right">Dimusnahkan</th>
              <th className="text-right">Bucket kini</th>
              <th className="text-right">Bucket setelah</th>
              <th className="text-right">On-hand kini</th>
              <th className="text-right">On-hand setelah</th>
              <th className="text-right">Reserved</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {preview.lines.map((line) => (
              <tr key={line.sourceLineRef}>
                <td>
                  <p className="font-medium text-white">
                    {line.productSku ?? "Produk tidak ditemukan"}
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    {line.batchCode ?? line.batchId} â€¢ exp{" "}
                    {line.expiryDate ?? "-"} â€¢ {line.batchStatusCode ?? "-"}
                  </p>
                </td>
                <td>{bucketLabel(line.sourceBucketCode)}</td>
                <td className="text-right font-mono font-semibold text-rose-200">
                  -{formatNumber(line.quantityRequested)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(line.currentBatchBucketQty)}
                </td>
                <td className="text-right font-mono font-semibold text-white">
                  {formatNumber(line.resultingBatchBucketQty)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(line.currentProductOnHandQty)}
                </td>
                <td className="text-right font-mono font-semibold text-white">
                  {formatNumber(line.resultingProductOnHandQty)}
                </td>
                <td className="text-right font-mono text-amber-200">
                  {formatNumber(line.currentProductReservedQty)}
                </td>
                <td>
                  <Pill
                    label={line.lineEligible ? "Siap" : "Diblokir"}
                    tone={line.lineEligible ? "success" : "danger"}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

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
          action={postStockDisposalAction}
          className="mt-6 rounded-3xl border border-amber-400/25 bg-amber-400/[0.055] p-5 lg:p-6"
        >
          <input
            name="draft"
            type="hidden"
            value={serializeStockDisposalDraft(draft)}
          />
          <input
            name="previewBasisHash"
            type="hidden"
            value={preview.basisHash}
          />
          <input name="intentId" type="hidden" value={intentId} />

          <p className="section-kicker text-amber-300">Konfirmasi final</p>
          <h3 className="mt-2 text-xl font-semibold text-white">
            Posting pemusnahan stok secara atomik.
          </h3>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Commit menghitung ulang basis di bawah lock. Perubahan saldo, status
            batch, tanggal kedaluwarsa, atau reserved stock membuat preview stale
            dan wajib ditinjau ulang.
          </p>

          <label className="mt-4 flex items-start gap-3 rounded-xl border border-white/10 bg-slate-950/45 p-4">
            <input
              className="mt-1"
              name="confirmation"
              required
              type="checkbox"
            />
            <span>
              <span className="text-sm font-semibold text-white">
                Saya sudah memeriksa batch, bucket, quantity, dan bukti.
              </span>
              <span className="mt-1 block text-xs leading-5 text-slate-500">
                Dokumen dan ledger bersifat immutable. Koreksi dilakukan melalui
                transaksi REVERSAL, bukan edit saldo.
              </span>
            </span>
          </label>

          <button
            className="mt-5 rounded-xl bg-amber-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-amber-200"
            type="submit"
          >
            Posting Pemusnahan Stok
          </button>
        </form>
      ) : (
        <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/[0.055] p-5 text-sm leading-6 text-rose-100">
          Tombol posting tidak tersedia karena database menemukan blocker.
          Preview ini tidak mengubah stok atau ledger.
        </div>
      )}
    </section>
  );
}

function DisposalLines({ lines }: { lines: StockDisposalLine[] }) {
  return (
    <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10 bg-slate-950/35">
      <table>
        <thead>
          <tr>
            <th>Baris</th>
            <th>Produk</th>
            <th>Batch</th>
            <th>Bucket</th>
            <th className="text-right">Quantity</th>
            <th className="text-right">Sebelum</th>
            <th className="text-right">Sesudah</th>
            <th>Ledger entry</th>
          </tr>
        </thead>
        <tbody>
          {lines.map((line) => (
            <tr key={line.disposal_line_id}>
              <td>{line.line_no}</td>
              <td>
                <p className="font-medium text-white">
                  {line.product_sku_snapshot}
                </p>
                <p className="mt-1 text-xs text-slate-500">
                  {line.product_name_snapshot}
                </p>
              </td>
              <td>
                <p>{line.batch_code_snapshot}</p>
                <p className="mt-1 text-xs text-slate-500">
                  exp {line.expiry_date_snapshot}
                </p>
              </td>
              <td>{bucketLabel(line.source_bucket_code)}</td>
              <td className="text-right font-mono text-rose-200">
                -{formatNumber(line.quantity_disposed)}
              </td>
              <td className="text-right font-mono">
                {formatNumber(line.bucket_before_qty)}
              </td>
              <td className="text-right font-mono font-semibold text-white">
                {formatNumber(line.bucket_after_qty)}
              </td>
              <td className="font-mono text-xs text-slate-500">
                {line.ledger_entry_id}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default async function StockDisposalsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  let draft = emptyDraft();
  let shouldPreview = false;
  let draftError: string | null = null;

  if (params.draft) {
    try {
      draft = parseStockDisposalDraft(params.draft);
      shouldPreview = true;
    } catch (error) {
      draftError = stockDisposalErrorMessage(error);
    }
  }

  let data;

  try {
    data = await getStockDisposalData(undefined, params.disposalId);
  } catch (error) {
    return (
      <ConfigurationError
        message={
          error instanceof Error ? error.message : "Konfigurasi tidak valid."
        }
      />
    );
  }

  let preview: StockDisposalPreview | null = null;
  let previewError: string | null = null;

  if (shouldPreview) {
    try {
      preview = await previewStockDisposal({
        sourceRef: draft.sourceRef,
        occurredAt: stockDisposalOccurredAt(draft),
        reasonCode: draft.reasonCode,
        lines: draft.lines,
        referenceText: draft.referenceText,
        note: draft.note,
        metadata: {
          source: "stock-disposal-admin-ui",
          version: 1,
        },
      });
    } catch (error) {
      previewError = stockDisposalErrorMessage(error);
    }
  }

  const selectedDisposal = data.selectedDisposal;
  const expiredCount = data.candidates.filter(
    (candidate) => candidate.is_expired,
  ).length;
  const nearExpiryCount = data.candidates.filter(
    (candidate) =>
      !candidate.is_expired &&
      candidate.days_to_expiry >= 0 &&
      candidate.days_to_expiry <= 30,
  ).length;
  const damagedCount = data.candidates.filter(
    (candidate) => candidate.damaged_qty > 0,
  ).length;

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <PageSectionNav
        items={[
          { href: "#overview", label: "Ringkasan" },
          { href: "#queue", label: "Antrean batch" },
          { href: "#draft", label: "Draft" },
          { href: "#preview", label: "Preview" },
          { href: "#history", label: "Riwayat" },
        ]}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section id="overview" className="scroll-mt-24">
          <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="section-kicker">Kontrol stok fisik</p>
              <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
                Rusak & Kedaluwarsa.
              </h1>
              <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
                Tinjau antrean batch, pilih bucket fisik yang benar, lihat dampak
                stok sebelum commit, lalu simpan pemusnahan sebagai outbound
                eksternal yang immutable.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Pill label="Bukan FEFO" tone="warning" />
              <Pill label="Ledger append-only" tone="info" />
              <Pill label="Commit atomik" tone="success" />
            </div>
          </div>

          {params.success ? (
            <div className="mt-6 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-100">
              <p>{params.success}</p>
              {params.transactionId ? (
                <Link
                  className="mt-3 inline-flex font-medium text-emerald-200 underline decoration-emerald-400/40 underline-offset-4"
                  href={`/entry-corrections?transactionId=${encodeURIComponent(
                    params.transactionId,
                  )}&type=DISPOSAL#detail`}
                >
                  Buka transaksi dan jalur Koreksi Entri
                </Link>
              ) : null}
            </div>
          ) : null}

          {params.error || draftError ? (
            <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-100">
              {params.error ?? draftError}
            </div>
          ) : null}

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              {
                label: "Batch kedaluwarsa",
                value: expiredCount,
                tone: "danger" as const,
              },
              {
                label: "Mendekati kedaluwarsa",
                value: nearExpiryCount,
                tone: "warning" as const,
              },
              {
                label: "Batch dengan saldo rusak",
                value: damagedCount,
                tone: "danger" as const,
              },
              {
                label: "Riwayat pemusnahan",
                value: data.disposals.length,
                tone: "info" as const,
              },
            ].map((card) => (
              <article
                className="rounded-2xl border border-white/10 bg-white/[0.025] p-5"
                key={card.label}
              >
                <p className="text-xs text-slate-500">{card.label}</p>
                <p className="mt-2 text-3xl font-semibold text-white">
                  {formatNumber(card.value)}
                </p>
                <div className="mt-3">
                  <Pill
                    label={
                      card.tone === "danger"
                        ? "Perlu tindakan"
                        : card.tone === "warning"
                          ? "Pantau"
                          : "Audit tersedia"
                    }
                    tone={card.tone}
                  />
                </div>
              </article>
            ))}
          </div>
        </section>

        <section id="queue" className="mt-10 scroll-mt-24">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="section-kicker">Antrean batch</p>
              <h2 className="section-title">
                Kedaluwarsa, mendekati kedaluwarsa, dan saldo rusak.
              </h2>
            </div>
            <Pill
              label={`${formatNumber(data.candidates.length)} batch bersaldo`}
              tone="neutral"
            />
          </div>

          <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10 bg-white/[0.02]">
            <table>
              <thead>
                <tr>
                  <th>Produk / batch</th>
                  <th>Kedaluwarsa</th>
                  <th>Status batch</th>
                  <th className="text-right">Sellable</th>
                  <th className="text-right">Karantina</th>
                  <th className="text-right">Rusak</th>
                  <th className="text-right">Reserved</th>
                  <th>Tindak lanjut</th>
                </tr>
              </thead>
              <tbody>
                {data.candidates.length ? (
                  data.candidates.map((candidate) => {
                    const needsExpiredDisposal =
                      candidate.is_expired &&
                      candidate.batch_status_code !== "ARCHIVED";
                    const needsDamagedDisposal =
                      candidate.damaged_qty > 0 &&
                      candidate.batch_status_code !== "ARCHIVED";
                    const nearExpiry =
                      !candidate.is_expired &&
                      candidate.days_to_expiry >= 0 &&
                      candidate.days_to_expiry <= 30;

                    return (
                      <tr key={candidate.batch_id}>
                        <td>
                          <p className="font-medium text-white">
                            {candidate.product_sku} â€¢ {candidate.batch_code}
                          </p>
                          <p className="mt-1 text-xs text-slate-500">
                            {candidate.product_name}
                          </p>
                        </td>
                        <td>
                          <p>{candidate.expiry_date}</p>
                          <p className="mt-1 text-xs text-slate-500">
                            {candidate.is_expired
                              ? `${Math.abs(candidate.days_to_expiry)} hari lewat`
                              : `${candidate.days_to_expiry} hari lagi`}
                          </p>
                        </td>
                        <td>
                          <Pill
                            label={candidate.batch_status_code}
                            tone={
                              candidate.batch_status_code === "ARCHIVED"
                                ? "neutral"
                                : candidate.batch_status_code === "BLOCKED"
                                  ? "warning"
                                  : "info"
                            }
                          />
                        </td>
                        <td className="text-right font-mono">
                          {formatNumber(candidate.sellable_qty)}
                        </td>
                        <td className="text-right font-mono">
                          {formatNumber(candidate.quarantine_qty)}
                        </td>
                        <td className="text-right font-mono text-rose-200">
                          {formatNumber(candidate.damaged_qty)}
                        </td>
                        <td className="text-right font-mono text-amber-200">
                          {formatNumber(candidate.reserved_qty)}
                        </td>
                        <td>
                          <div className="flex flex-wrap gap-2">
                            {needsExpiredDisposal ? (
                              <Pill label="Kedaluwarsa" tone="danger" />
                            ) : null}
                            {needsDamagedDisposal ? (
                              <Pill label="Rusak" tone="danger" />
                            ) : null}
                            {nearExpiry ? (
                              <Pill label="Pantau" tone="warning" />
                            ) : null}
                            {!needsExpiredDisposal &&
                            !needsDamagedDisposal &&
                            !nearExpiry ? (
                              <Pill label="Tidak mendesak" tone="neutral" />
                            ) : null}
                          </div>
                        </td>
                      </tr>
                    );
                  })
                ) : (
                  <tr>
                    <td className="text-center text-slate-500" colSpan={8}>
                      Belum ada batch bersaldo pada antrean.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </section>

        <section id="draft" className="mt-10 scroll-mt-24">
          <StockDisposalDraftForm
            initialDraft={draft}
            candidates={data.candidates.map((candidate) => ({
              organizationId: candidate.organization_id,
              productId: candidate.product_id,
              productSku: candidate.product_sku,
              productName: candidate.product_name,
              productIsActive: candidate.product_is_active,
              batchId: candidate.batch_id,
              batchCode: candidate.batch_code,
              expiryDate: candidate.expiry_date,
              batchStatusCode: candidate.batch_status_code,
              blockReason: candidate.block_reason,
              sellableQty: candidate.sellable_qty,
              quarantineQty: candidate.quarantine_qty,
              damagedQty: candidate.damaged_qty,
              physicalQty: candidate.physical_qty,
              reservedQty: candidate.reserved_qty,
              localDate: candidate.local_date,
              isExpired: candidate.is_expired,
              daysToExpiry: candidate.days_to_expiry,
            }))}
          />
        </section>

        <section id="preview" className="scroll-mt-24">
          {previewError ? (
            <div className="panel-card mt-6 border-rose-400/20 bg-rose-400/[0.055] text-rose-100">
              {previewError}
            </div>
          ) : null}

          {preview ? <PreviewPanel draft={draft} preview={preview} /> : null}

          {!preview && !previewError ? (
            <div className="panel-card mt-6 text-sm leading-6 text-slate-400">
              Isi draft lalu pilih{" "}
              <strong className="text-white">
                Tinjau dampak pemusnahan
              </strong>
              . Sistem tidak menyediakan tombol posting sebelum preview
              authoritative tersedia.
            </div>
          ) : null}
        </section>

        <section id="history" className="mt-10 scroll-mt-24">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="section-kicker">Riwayat immutable</p>
              <h2 className="section-title">
                Pemusnahan yang sudah diposting.
              </h2>
            </div>
            <Pill
              label={`${formatNumber(data.disposals.length)} dokumen terbaru`}
              tone="neutral"
            />
          </div>

          <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10 bg-white/[0.02]">
            <table>
              <thead>
                <tr>
                  <th>Dokumen</th>
                  <th>Referensi</th>
                  <th>Alasan</th>
                  <th>Waktu</th>
                  <th className="text-right">Quantity</th>
                  <th>Detail</th>
                </tr>
              </thead>
              <tbody>
                {data.disposals.length ? (
                  data.disposals.map((disposal) => (
                    <tr key={disposal.disposal_id}>
                      <td className="font-semibold text-white">
                        {disposal.disposal_no}
                      </td>
                      <td>{disposal.source_ref}</td>
                      <td>{reasonLabel(disposal.reason_code_snapshot)}</td>
                      <td>{formatDate(disposal.occurred_at)}</td>
                      <td className="text-right font-mono">
                        {formatNumber(disposal.total_quantity)}
                      </td>
                      <td>
                        <Link
                          className="text-sky-300 underline decoration-sky-400/30 underline-offset-4"
                          href={`/stock-disposals?disposalId=${encodeURIComponent(
                            disposal.disposal_id,
                          )}#history`}
                        >
                          Buka
                        </Link>
                      </td>
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td className="text-center text-slate-500" colSpan={6}>
                      Belum ada pemusnahan stok.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {selectedDisposal ? (
            <article className="panel-card mt-6">
              <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <p className="section-kicker">Detail dokumen</p>
                  <h3 className="mt-2 text-2xl font-semibold text-white">
                    {selectedDisposal.disposal_no}
                  </h3>
                  <p className="mt-2 text-sm text-slate-400">
                    {selectedDisposal.source_ref} â€¢{" "}
                    {formatDate(selectedDisposal.occurred_at)}
                  </p>
                </div>
                <Pill label={selectedDisposal.status_code} tone="success" />
              </div>

              <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                {[
                  [
                    "Alasan",
                    reasonLabel(selectedDisposal.reason_code_snapshot),
                  ],
                  [
                    "Quantity",
                    formatNumber(selectedDisposal.total_quantity),
                  ],
                  ["Bukti", selectedDisposal.reference_text],
                  ["Transaction ID", selectedDisposal.transaction_id],
                ].map(([label, value]) => (
                  <div
                    className="rounded-2xl border border-white/10 bg-slate-950/35 p-4"
                    key={label}
                  >
                    <dt className="text-xs text-slate-500">{label}</dt>
                    <dd className="mt-2 break-all text-sm text-slate-100">
                      {value}
                    </dd>
                  </div>
                ))}
              </dl>

              <div className="mt-5 rounded-2xl border border-white/10 bg-white/[0.02] p-4 text-sm leading-6 text-slate-300">
                {selectedDisposal.note}
              </div>

              <DisposalLines lines={data.lines} />

              <Link
                className="mt-5 inline-flex rounded-xl border border-sky-400/25 px-4 py-2.5 text-sm font-medium text-sky-200 transition hover:bg-sky-400/10"
                href={`/entry-corrections?transactionId=${encodeURIComponent(
                  selectedDisposal.transaction_id,
                )}&type=DISPOSAL#detail`}
              >
                Tinjau melalui Koreksi Entri
              </Link>
            </article>
          ) : null}
        </section>
      </div>
    </main>
  );
}