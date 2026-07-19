import { randomUUID } from "node:crypto";
import Link from "next/link";

import PageSectionNav from "@/app/app-shell/page-section-nav";
import { postManualOutboundAction } from "@/app/manual-outbounds/actions";
import ManualOutboundDraftForm from "@/app/manual-outbounds/components/draft-form";
import {
  manualOutboundErrorMessage,
  manualOutboundOccurredAt,
  parseManualOutboundDraft,
  serializeManualOutboundDraft,
  type ManualOutboundDraft,
} from "@/app/manual-outbounds/draft";
import {
  getManualOutboundData,
  previewManualOutbound,
  type ManualOutboundAllocation,
  type ManualOutboundLine,
  type ManualOutboundPreview,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = {
  draft?: string;
  success?: string;
  error?: string;
  outboundId?: string;
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

function emptyDraft(): ManualOutboundDraft {
  return {
    sourceRef: "",
    occurredAt: defaultDateTimeLocal(),
    reasonCode: "OFFLINE_SALE",
    lines: [
      {
        productId: "",
        quantity: 1,
        sourceLineRef: "UI-1",
      },
    ],
    note: null,
    reference: null,
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

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="section-kicker text-amber-300">
          Barang Keluar tidak tersedia
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
  draft: ManualOutboundDraft;
  preview: ManualOutboundPreview;
}) {
  const intentId = preview.eligible ? randomUUID() : null;

  return (
    <section className="panel-card mt-6">
      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="section-kicker">Preview authoritative</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">
            Alokasi FEFO dan dampak stok.
          </h2>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Preview dihitung database dan tidak menulis dokumen, alokasi,
            ledger, projection, maupun idempotency command.
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
          ["Channel", preview.channelCode],
          ["Tanggal efektif", preview.effectiveLocalDate],
          ["Jumlah produk", formatNumber(preview.lineCount)],
          ["Total quantity", formatNumber(preview.totalRequestedQuantity)],
          ["Jumlah alokasi", formatNumber(preview.allocationCount)],
          [
            "Safety buffer",
            `${formatNumber(preview.expirySafetyBufferDays)} hari`,
          ],
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
                {blocker.productSku ? `${blocker.productSku} Â· ` : ""}
                {blocker.requestedQuantity !== undefined
                  ? `diminta ${formatNumber(blocker.requestedQuantity)} Â· `
                  : ""}
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
              <th>Produk</th>
              <th className="text-right">Diminta</th>
              <th className="text-right">Sellable kini</th>
              <th className="text-right">Reserved</th>
              <th className="text-right">Available kini</th>
              <th className="text-right">Sellable setelah</th>
              <th className="text-right">Available setelah</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {preview.products.map((product) => (
              <tr key={product.sourceLineRef}>
                <td>
                  <p className="font-medium text-white">
                    {product.productSku ?? "Produk tidak ditemukan"}
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    {product.productName ?? product.productId}
                  </p>
                </td>
                <td className="text-right font-mono">
                  {formatNumber(product.requestedQuantity)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(product.currentSellable)}
                </td>
                <td className="text-right font-mono text-amber-200">
                  {formatNumber(product.currentReserved)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(product.currentAvailable)}
                </td>
                <td className="text-right font-mono font-semibold text-white">
                  {formatNumber(product.resultingSellable)}
                </td>
                <td className="text-right font-mono font-semibold text-white">
                  {formatNumber(product.resultingAvailable)}
                </td>
                <td>
                  <Pill
                    label={product.status === "READY" ? "Siap" : "Diblokir"}
                    tone={
                      product.status === "READY" ? "success" : "danger"
                    }
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="mt-6 overflow-x-auto rounded-2xl border border-white/10 bg-slate-950/35">
        <table>
          <thead>
            <tr>
              <th>Urutan FEFO</th>
              <th>Produk</th>
              <th>Batch</th>
              <th>Kedaluwarsa</th>
              <th>Diterima pertama</th>
              <th className="text-right">Batch kini</th>
              <th className="text-right">Dialokasikan</th>
              <th className="text-right">Batch setelah</th>
            </tr>
          </thead>
          <tbody>
            {preview.allocations.length ? (
              preview.allocations.map((allocation) => (
                <tr
                  key={`${allocation.sourceLineRef}-${allocation.allocationNo}`}
                >
                  <td className="font-mono text-xs text-slate-500">
                    {allocation.lineNo}.{allocation.allocationNo}
                  </td>
                  <td>{allocation.productSku}</td>
                  <td className="font-medium text-white">
                    {allocation.batchCode}
                  </td>
                  <td>{allocation.expiryDate}</td>
                  <td>{formatDate(allocation.receivedFirstAt)}</td>
                  <td className="text-right font-mono">
                    {formatNumber(allocation.currentBatchSellable)}
                  </td>
                  <td className="text-right font-mono font-semibold text-rose-200">
                    -{formatNumber(allocation.quantity)}
                  </td>
                  <td className="text-right font-mono font-semibold text-white">
                    {formatNumber(allocation.resultingBatchSellable)}
                  </td>
                </tr>
              ))
            ) : (
              <tr>
                <td className="text-center text-slate-500" colSpan={8}>
                  Belum ada batch yang dapat dialokasikan.
                </td>
              </tr>
            )}
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
          action={postManualOutboundAction}
          className="mt-6 rounded-3xl border border-amber-400/25 bg-amber-400/[0.055] p-5 lg:p-6"
        >
          <input
            name="draft"
            type="hidden"
            value={serializeManualOutboundDraft(draft)}
          />
          <input
            name="previewBasisHash"
            type="hidden"
            value={preview.basisHash}
          />
          <input name="intentId" type="hidden" value={intentId} />

          <p className="section-kicker text-amber-300">Konfirmasi final</p>
          <h3 className="mt-2 text-xl font-semibold text-white">
            Posting seluruh produk secara atomik.
          </h3>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Commit menghitung ulang basis di bawah lock. Perubahan stok,
            eligibility batch, atau safety buffer membuat preview ini stale dan
            wajib ditinjau ulang.
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
                Saya sudah meninjau batch FEFO dan dampak stok.
              </span>
              <span className="mt-1 block text-xs leading-5 text-slate-500">
                Dokumen, alokasi, dan ledger yang berhasil diposting bersifat
                immutable. Kesalahan diperbaiki melalui Koreksi Entri.
              </span>
            </span>
          </label>

          <button
            className="mt-5 rounded-xl bg-amber-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-amber-200"
            type="submit"
          >
            Posting Barang Keluar
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

function OutboundLines({
  lines,
  allocations,
}: {
  lines: ManualOutboundLine[];
  allocations: ManualOutboundAllocation[];
}) {
  return (
    <div className="mt-5 space-y-4">
      {lines.map((line) => {
        const lineAllocations = allocations.filter(
          (allocation) => allocation.outbound_line_id === line.outbound_line_id,
        );

        return (
          <article
            className="rounded-2xl border border-white/10 bg-slate-950/35 p-5"
            key={line.outbound_line_id}
          >
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="font-semibold text-white">
                  {line.product_sku_snapshot}
                </p>
                <p className="mt-1 text-xs text-slate-500">
                  Baris {line.line_no} Â· {line.source_line_ref}
                </p>
              </div>
              <Pill
                label={`${formatNumber(line.quantity_requested)} unit`}
                tone="info"
              />
            </div>

            <div className="mt-4 overflow-x-auto">
              <table>
                <thead>
                  <tr>
                    <th>Urutan</th>
                    <th>Batch</th>
                    <th>Kedaluwarsa</th>
                    <th className="text-right">Quantity</th>
                    <th>Ledger entry</th>
                  </tr>
                </thead>
                <tbody>
                  {lineAllocations.map((allocation) => (
                    <tr key={allocation.allocation_id}>
                      <td>{allocation.allocation_no}</td>
                      <td className="font-medium text-white">
                        {allocation.batch_code_snapshot}
                      </td>
                      <td>{allocation.expiry_date_snapshot}</td>
                      <td className="text-right font-mono">
                        {formatNumber(allocation.quantity_allocated)}
                      </td>
                      <td className="font-mono text-xs text-slate-500">
                        {allocation.ledger_entry_id}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </article>
        );
      })}
    </div>
  );
}

export default async function ManualOutboundsPage({
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
      draft = parseManualOutboundDraft(params.draft);
      shouldPreview = true;
    } catch (error) {
      draftError = manualOutboundErrorMessage(error);
    }
  }

  let data;

  try {
    data = await getManualOutboundData(undefined, params.outboundId);
  } catch (error) {
    return (
      <ConfigurationError
        message={
          error instanceof Error ? error.message : "Konfigurasi tidak valid."
        }
      />
    );
  }

  let preview: ManualOutboundPreview | null = null;
  let previewError: string | null = null;

  if (shouldPreview) {
    try {
      preview = await previewManualOutbound({
        sourceRef: draft.sourceRef,
        occurredAt: manualOutboundOccurredAt(draft),
        reasonCode: draft.reasonCode,
        lines: draft.lines,
        note: draft.note,
        reference: draft.reference,
        metadata: {
          source: "manual-outbound-admin-ui",
          version: 1,
        },
      });
    } catch (error) {
      previewError = manualOutboundErrorMessage(error);
    }
  }

  const selectedOutbound = data.selectedOutbound;

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <PageSectionNav
        items={[
          { href: "#overview", label: "Ringkasan" },
          { href: "#draft", label: "Draft" },
          { href: "#preview", label: "Preview FEFO" },
          { href: "#history", label: "Riwayat" },
        ]}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section id="overview" className="scroll-mt-24">
          <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="section-kicker">Operasional gudang</p>
              <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
                Barang Keluar dengan preview FEFO.
              </h1>
              <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
                Penjualan offline, bonus, promo, dan sample memakai channel
                MANUAL. Operator menentukan produk dan quantity, sedangkan
                database menentukan batch.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Pill label="Ledger append-only" tone="info" />
              <Pill label="Reserved dilindungi" tone="warning" />
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
                  )}#detail`}
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
        </section>

        <section id="draft" className="mt-10 scroll-mt-24">
          <ManualOutboundDraftForm
            initialDraft={draft}
            products={data.products.map((product) => ({
              productId: product.product_id,
              sku: product.sku,
              name: product.name,
              availableQuantity: product.available_qty,
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
              <strong className="text-white">Tinjau alokasi FEFO</strong>.
              Sistem tidak menyediakan tombol posting sebelum preview
              authoritative tersedia.
            </div>
          ) : null}
        </section>

        <section id="history" className="mt-10 scroll-mt-24">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="section-kicker">Riwayat immutable</p>
              <h2 className="section-title">
                Barang keluar yang sudah diposting.
              </h2>
            </div>
            <Pill
              label={`${formatNumber(data.outbounds.length)} dokumen terbaru`}
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
                {data.outbounds.length ? (
                  data.outbounds.map((outbound) => (
                    <tr key={outbound.outbound_id}>
                      <td className="font-semibold text-white">
                        {outbound.outbound_no}
                      </td>
                      <td>{outbound.source_ref}</td>
                      <td>{outbound.reason_code_snapshot}</td>
                      <td>{formatDate(outbound.occurred_at)}</td>
                      <td className="text-right font-mono">
                        {formatNumber(outbound.total_quantity)}
                      </td>
                      <td>
                        <Link
                          className="text-sky-300 underline decoration-sky-400/30 underline-offset-4"
                          href={`/manual-outbounds?outboundId=${encodeURIComponent(
                            outbound.outbound_id,
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
                      Belum ada barang keluar manual.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {selectedOutbound ? (
            <article className="panel-card mt-6">
              <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <p className="section-kicker">Detail dokumen</p>
                  <h3 className="mt-2 text-2xl font-semibold text-white">
                    {selectedOutbound.outbound_no}
                  </h3>
                  <p className="mt-2 text-sm text-slate-400">
                    {selectedOutbound.source_ref} Â·{" "}
                    {formatDate(selectedOutbound.occurred_at)}
                  </p>
                </div>
                <Pill label={selectedOutbound.status_code} tone="success" />
              </div>

              <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                {[
                  ["Alasan", selectedOutbound.reason_code_snapshot],
                  ["Quantity", formatNumber(selectedOutbound.total_quantity)],
                  ["Transaction ID", selectedOutbound.transaction_id],
                  ["Dicatat", formatDate(selectedOutbound.recorded_at)],
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

              <OutboundLines
                allocations={data.allocations}
                lines={data.lines}
              />

              <div className="mt-5 flex flex-wrap gap-3">
                <Link
                  className="primary-button inline-flex"
                  href={`/entry-corrections?transactionId=${encodeURIComponent(
                    selectedOutbound.transaction_id,
                  )}#detail`}
                >
                  Buka Ledger dan Koreksi Entri
                </Link>
                <Link
                  className="rounded-xl border border-white/10 px-4 py-2.5 text-sm font-medium text-slate-200 transition hover:border-sky-400/30 hover:text-white"
                  href="/manual-outbounds#draft"
                >
                  Buat draft baru
                </Link>
              </div>
            </article>
          ) : null}
        </section>
      </div>
    </main>
  );
}
