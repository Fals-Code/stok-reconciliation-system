import { randomUUID } from "node:crypto";

import Link from "next/link";

import PageSectionNav from "@/app/app-shell/page-section-nav";
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
  getOpeningBalanceData,
  previewOpeningBalanceCutover,
  previewOpeningBalanceReversal,
  type OpeningBalanceCutover,
  type OpeningBalancePreview,
  type OpeningBalanceReversalAudit,
  type OpeningBalanceReversalPreview,
  type OpeningBalanceVerificationStatus,
  type StockLedgerEntry,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = {
  cutoverId?: string;
  transactionId?: string;
  success?: string;
  error?: string;
};

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number | null | undefined) {
  if (value === null || value === undefined) return "-";
  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null) {
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
  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );

  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

function verificationTone(
  status: OpeningBalanceVerificationStatus,
): "success" | "warning" | "danger" | "info" | "neutral" {
  if (status === "VERIFIED") return "success";
  if (status === "PARTIALLY_VERIFIED") return "warning";
  if (status === "UNVERIFIED") return "danger";
  if (status === "NOT_APPLICABLE") return "neutral";
  return "info";
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

function operationalTone(
  cutover: OpeningBalanceCutover,
): "success" | "warning" | "danger" | "info" | "neutral" {
  if (cutover.operational_status_code === "ACTIVE") return "success";
  if (cutover.operational_status_code === "REVERSED") return "danger";
  if (cutover.status_code === "REVIEW") return "warning";
  if (cutover.status_code === "DRAFT") return "info";
  return "neutral";
}

function PreviewPanel({
  preview,
}: {
  preview: OpeningBalancePreview;
}) {
  const intentId = preview.eligible ? randomUUID() : null;

  return (
    <section className="panel-card">
      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="section-kicker">Preview authoritative</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">
            Dampak saldo awal sebelum posting.
          </h2>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Preview membaca ledger dan projection saat ini tanpa membuat
            transaksi, movement, projection update, atau idempotency effect.
          </p>
        </div>
        <Pill
          label={preview.eligible ? "Siap diposting" : "Diblokir"}
          tone={preview.eligible ? "success" : "danger"}
        />
      </div>

      <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {[
          ["Dokumen", preview.cutoverNo],
          ["Tanggal efektif", preview.effectiveLocalDate],
          ["Jumlah baris", formatNumber(preview.lineCount)],
          ["Baris movement", formatNumber(preview.positiveLineCount)],
          ["Total quantity", formatNumber(preview.totalQuantity)],
          ["Referensi sumber", preview.sourceRef],
          ["Referensi estimasi", preview.sourceEstimateRef],
          ["Status verifikasi awal", "UNVERIFIED"],
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

      {preview.blockers.length ? (
        <div className="mt-5 space-y-3">
          {preview.blockers.map((blocker, index) => (
            <article
              className="rounded-2xl border border-rose-400/20 bg-rose-400/[0.06] p-4"
              key={`${blocker.code}-${blocker.lineNo ?? "document"}-${index}`}
            >
              <p className="font-medium text-rose-100">
                {blocker.message}
              </p>
              <p className="mt-2 font-mono text-xs text-rose-300/75">
                {blocker.lineNo ? `baris ${blocker.lineNo} · ` : ""}
                {blocker.code}
              </p>
            </article>
          ))}
        </div>
      ) : null}

      <div className="mt-6 overflow-x-auto rounded-2xl border border-white/10 bg-slate-950/35">
        <table>
          <thead>
            <tr>
              <th>Baris</th>
              <th>Produk</th>
              <th>Batch</th>
              <th>Bucket</th>
              <th className="text-right">Quantity</th>
              <th className="text-right">Batch kini</th>
              <th className="text-right">Batch setelah</th>
              <th className="text-right">Produk kini</th>
              <th className="text-right">Produk setelah</th>
            </tr>
          </thead>
          <tbody>
            {preview.lines.map((line) => (
              <tr key={line.openingBalanceLineId}>
                <td>{line.lineNo}</td>
                <td>
                  <p className="font-medium text-white">
                    {line.productSku}
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    {line.productName}
                  </p>
                </td>
                <td>
                  <p className="font-medium text-white">
                    {line.batchCode}
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    exp {line.expiryDate}
                  </p>
                </td>
                <td>{line.bucketCode}</td>
                <td className="text-right font-mono font-semibold text-emerald-200">
                  +{formatNumber(line.quantity)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(line.currentBatchBucketQty)}
                </td>
                <td className="text-right font-mono font-semibold text-white">
                  {formatNumber(line.resultingBatchBucketQty)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(line.currentProductBucketQty)}
                </td>
                <td className="text-right font-mono font-semibold text-white">
                  {formatNumber(line.resultingProductBucketQty)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <details className="mt-4 rounded-2xl border border-white/10 bg-white/[0.02]">
        <summary className="cursor-pointer px-5 py-4 text-sm font-medium text-slate-300">
          Detail teknis preview
        </summary>
        <dl className="grid gap-3 border-t border-white/10 p-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs text-slate-500">Basis hash</dt>
            <dd className="mt-2 break-all font-mono text-xs text-slate-300">
              {preview.basisHash}
            </dd>
          </div>
          <div>
            <dt className="text-xs text-slate-500">Request hash</dt>
            <dd className="mt-2 break-all font-mono text-xs text-slate-300">
              {preview.requestHash}
            </dd>
          </div>
        </dl>
      </details>

      {preview.eligible && intentId ? (
        <form
          action={postOpeningBalanceAction}
          className="mt-6 rounded-3xl border border-amber-400/25 bg-amber-400/[0.055] p-5"
        >
          <input
            name="cutoverId"
            type="hidden"
            value={preview.cutoverId}
          />
          <input
            name="previewBasisHash"
            type="hidden"
            value={preview.basisHash}
          />
          <input name="intentId" type="hidden" value={intentId} />

          <p className="section-kicker text-amber-300">
            Konfirmasi final
          </p>
          <h3 className="mt-2 text-xl font-semibold text-white">
            Posting seluruh saldo awal secara atomik.
          </h3>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Database menghitung ulang basis di bawah lock. Perubahan ledger,
            master batch, atau projection membuat preview stale.
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
                Saya sudah meninjau semua batch, bucket, dan quantity.
              </span>
              <span className="mt-1 block text-xs leading-5 text-slate-500">
                Dokumen dan ledger yang diposting immutable. Kesalahan
                diperbaiki melalui exact reversal, bukan edit saldo.
              </span>
            </span>
          </label>

          <button
            className="mt-5 rounded-xl bg-amber-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-amber-200"
            type="submit"
          >
            Posting Saldo Awal
          </button>
        </form>
      ) : (
        <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/[0.055] p-5 text-sm leading-6 text-rose-100">
          Tombol posting tidak tersedia karena database menemukan blocker.
          Preview tidak mengubah stok atau ledger.
        </div>
      )}
    </section>
  );
}


function ReversalPreviewPanel({
  preview,
}: {
  preview: OpeningBalanceReversalPreview;
}) {
  const intentId = preview.eligible ? randomUUID() : null;

  return (
    <section id="reversal" className="panel-card scroll-mt-24 border-rose-400/20">
      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="section-kicker text-rose-300">
            Preview exact reversal
          </p>
          <h2 className="mt-2 text-2xl font-semibold text-white">
            Batalkan seluruh movement saldo awal tanpa mengedit histori.
          </h2>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Database memakai produk, batch, bucket, dan quantity dari
            INITIAL_BALANCE asli. Tidak ada FEFO, substitusi batch, atau
            pengurangan parsial.
          </p>
        </div>
        <Pill
          label={preview.eligible ? "Reversal tersedia" : "Diblokir"}
          tone={preview.eligible ? "warning" : "danger"}
        />
      </div>

      <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {[
          ["Dokumen", preview.cutoverNo],
          ["Transaksi asal", preview.originalTransactionNo ?? "-"],
          ["Movement dibalik", formatNumber(preview.lineCount)],
          [
            "Total quantity",
            formatNumber(preview.totalAbsoluteQuantity),
          ],
          [
            "Bukti verifikasi tersimpan",
            formatNumber(preview.verificationApplicationCount),
          ],
          ["Metode", "Exact full reversal"],
          ["Alokasi batch", "Sama dengan ledger asal"],
          ["Dampak setelah sukses", "Pointer aktif dilepas"],
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

      {preview.blockers.length ? (
        <div className="mt-5 space-y-3">
          {preview.blockers.map((blocker, index) => (
            <article
              className="rounded-2xl border border-rose-400/20 bg-rose-400/[0.06] p-4"
              key={`${blocker.code}-${index}`}
            >
              <p className="font-medium text-rose-100">
                {blocker.message}
              </p>
              <p className="mt-2 font-mono text-xs text-rose-300/75">
                {blocker.code}
              </p>
            </article>
          ))}
        </div>
      ) : null}

      <div className="mt-6 overflow-x-auto rounded-2xl border border-white/10 bg-slate-950/35">
        <table>
          <thead>
            <tr>
              <th>Baris</th>
              <th>Produk</th>
              <th>Batch</th>
              <th>Bucket</th>
              <th className="text-right">Movement asal</th>
              <th className="text-right">Reversal</th>
              <th className="text-right">Batch kini</th>
              <th className="text-right">Batch setelah</th>
              <th>Posisi produk setelah reversal</th>
            </tr>
          </thead>
          <tbody>
            {preview.lines.map((line) => (
              <tr key={line.openingBalanceLineId}>
                <td>{line.lineNo}</td>
                <td>
                  <p className="font-medium text-white">
                    {line.productSku}
                  </p>
                  <p className="mt-1 font-mono text-xs text-slate-600">
                    {line.productId}
                  </p>
                </td>
                <td>
                  <p className="font-medium text-white">
                    {line.batchCode}
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    exp {line.expiryDate}
                  </p>
                </td>
                <td>{line.bucketCode}</td>
                <td className="text-right font-mono text-emerald-200">
                  +{formatNumber(line.originalQuantity)}
                </td>
                <td className="text-right font-mono font-semibold text-rose-200">
                  {formatNumber(line.reversalDelta)}
                </td>
                <td className="text-right font-mono">
                  {formatNumber(line.currentBatchBucketQty)}
                </td>
                <td className="text-right font-mono font-semibold text-white">
                  {formatNumber(line.resultingBatchBucketQty)}
                </td>
                <td className="text-xs leading-5 text-slate-400">
                  <span className="block">
                    Sellable{" "}
                    {formatNumber(line.resultingProductSellableQty)}
                  </span>
                  <span className="block">
                    Quarantine{" "}
                    {formatNumber(line.resultingProductQuarantineQty)}
                  </span>
                  <span className="block">
                    Damaged{" "}
                    {formatNumber(line.resultingProductDamagedQty)}
                  </span>
                  <span className="block">
                    Reserved{" "}
                    {formatNumber(line.currentProductReservedQty)}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <details className="mt-4 rounded-2xl border border-white/10 bg-white/[0.02]">
        <summary className="cursor-pointer px-5 py-4 text-sm font-medium text-slate-300">
          Detail teknis preview reversal
        </summary>
        <dl className="grid gap-3 border-t border-white/10 p-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs text-slate-500">Basis hash</dt>
            <dd className="mt-2 break-all font-mono text-xs text-slate-300">
              {preview.basisHash}
            </dd>
          </div>
          <div>
            <dt className="text-xs text-slate-500">
              Transaksi asal
            </dt>
            <dd className="mt-2 break-all font-mono text-xs text-slate-300">
              {preview.originalTransactionId ?? "-"}
            </dd>
          </div>
        </dl>
      </details>

      {preview.eligible && intentId ? (
        <form
          action={reverseOpeningBalanceAction}
          className="mt-6 rounded-3xl border border-rose-400/25 bg-rose-400/[0.055] p-5"
        >
          <input
            name="cutoverId"
            type="hidden"
            value={preview.cutoverId}
          />
          <input
            name="previewBasisHash"
            type="hidden"
            value={preview.basisHash}
          />
          <input name="intentId" type="hidden" value={intentId} />

          <p className="section-kicker text-rose-300">
            Tindakan destruktif terkontrol
          </p>
          <h3 className="mt-2 text-xl font-semibold text-white">
            Balik seluruh saldo awal secara exact.
          </h3>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Ledger asal, cutover, dan bukti stok opname tidak dihapus.
            Sistem menambahkan transaksi REVERSAL dan melepas pointer cutover
            aktif agar dokumen pengganti dapat diposting.
          </p>

          <label className="mt-5 block space-y-2">
            <span className="text-sm font-medium text-slate-200">
              Alasan koreksi
            </span>
            <textarea
              className="min-h-28 w-full rounded-xl border border-rose-400/20 bg-slate-950/60 px-3 py-2.5 text-sm text-white"
              maxLength={2000}
              name="note"
              placeholder="Jelaskan kesalahan sumber dan alasan exact reversal."
              required
            />
          </label>

          <label className="mt-4 flex items-start gap-3 rounded-xl border border-white/10 bg-slate-950/45 p-4">
            <input
              className="mt-1"
              name="confirmation"
              required
              type="checkbox"
            />
            <span>
              <span className="text-sm font-semibold text-white">
                Saya memahami seluruh movement saldo awal akan dibalik.
              </span>
              <span className="mt-1 block text-xs leading-5 text-slate-500">
                Reversal hanya berhasil bila saldo bucket tetap nonnegatif,
                reserved tidak melampaui sellable, dan basis preview belum
                berubah.
              </span>
            </span>
          </label>

          <button
            className="mt-5 rounded-xl bg-rose-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-rose-200"
            type="submit"
          >
            Balik Saldo Awal
          </button>
        </form>
      ) : (
        <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/[0.055] p-5 text-sm leading-6 text-rose-100">
          Tombol exact reversal tidak tersedia karena database menemukan
          blocker. Tidak ada transaksi atau movement yang dibuat.
        </div>
      )}
    </section>
  );
}

function ReversalAuditPanel({
  reversal,
  ledger,
}: {
  reversal: OpeningBalanceReversalAudit;
  ledger: StockLedgerEntry[];
}) {
  return (
    <section id="reversal" className="panel-card scroll-mt-24 border-rose-400/20">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="section-kicker text-rose-300">
            Exact reversal selesai
          </p>
          <h2 className="mt-2 text-2xl font-semibold text-white">
            Histori asal dipertahankan, pointer aktif sudah dilepas.
          </h2>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Dokumen lama tetap POSTED sebagai bukti audit, tetapi status
            operasionalnya REVERSED. Cutover pengganti kini dapat dibuat dan
            diposting melalui workflow normal.
          </p>
        </div>
        <Pill label="REVERSED" tone="danger" />
      </div>

      <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {[
          ["Dokumen", reversal.cutover_no],
          ["Transaksi asal", reversal.original_transaction_no],
          ["Transaksi reversal", reversal.reversal_transaction_no],
          ["Waktu reversal", formatDate(reversal.reversed_at)],
          ["Movement reversal", formatNumber(reversal.line_count)],
          [
            "Total quantity",
            formatNumber(reversal.total_absolute_quantity),
          ],
          ["Ledger sebelum", formatNumber(reversal.ledger_seq_before)],
          ["Ledger setelah", formatNumber(reversal.ledger_seq_after)],
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

      <div className="mt-5 rounded-2xl border border-white/10 bg-slate-950/35 p-4">
        <p className="text-xs text-slate-500">Alasan koreksi</p>
        <p className="mt-2 text-sm leading-6 text-slate-200">
          {reversal.note}
        </p>
      </div>

      <div className="mt-6 overflow-x-auto rounded-2xl border border-white/10">
        <table>
          <thead>
            <tr>
              <th>Ledger seq</th>
              <th>Produk</th>
              <th>Batch</th>
              <th>Bucket</th>
              <th className="text-right">Delta</th>
              <th>Entry ID</th>
            </tr>
          </thead>
          <tbody>
            {ledger.map((entry) => (
              <tr key={entry.ledger_entry_id}>
                <td>{entry.ledger_seq}</td>
                <td>{entry.product_sku_snapshot}</td>
                <td>{entry.batch_code_snapshot}</td>
                <td>{entry.bucket_code}</td>
                <td className="text-right font-mono font-semibold text-rose-200">
                  {formatNumber(entry.quantity_delta)}
                </td>
                <td className="font-mono text-xs text-slate-500">
                  {entry.ledger_entry_id}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="mt-6 flex flex-wrap gap-3">
        <Link
          className="rounded-xl bg-sky-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-sky-200"
          href="#new"
        >
          Buat cutover pengganti
        </Link>
        <Link
          className="rounded-xl border border-white/10 px-4 py-2.5 text-sm font-medium text-slate-200 transition hover:bg-white/[0.05]"
          href={`/entry-corrections?transactionId=${encodeURIComponent(
            reversal.reversal_transaction_id,
          )}`}
        >
          Buka transaksi reversal
        </Link>
      </div>
    </section>
  );
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="section-kicker text-amber-300">
          Saldo Awal tidak tersedia
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

export default async function OpeningBalancesPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  let data;

  try {
    data = await getOpeningBalanceData(undefined, params.cutoverId);
  } catch (error) {
    return (
      <ConfigurationError
        message={
          error instanceof Error ? error.message : "Konfigurasi tidak valid."
        }
      />
    );
  }

  const selected = data.selectedCutover;
  let preview: OpeningBalancePreview | null = null;
  let previewError: string | null = null;
  let reversalPreview: OpeningBalanceReversalPreview | null = null;
  let reversalPreviewError: string | null = null;

  if (selected?.status_code === "REVIEW") {
    try {
      preview = await previewOpeningBalanceCutover(
        selected.cutover_id,
      );
    } catch (error) {
      previewError =
        error instanceof Error ? error.message : "Preview gagal dimuat.";
    }
  }

  if (selected?.operational_status_code === "ACTIVE") {
    try {
      reversalPreview = await previewOpeningBalanceReversal(
        selected.cutover_id,
      );
    } catch (error) {
      reversalPreviewError =
        error instanceof Error
          ? error.message
          : "Preview exact reversal gagal dimuat.";
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

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <PageSectionNav
        items={[
          { href: "#overview", label: "Ringkasan" },
          { href: "#new", label: "Buat draft" },
          { href: "#detail", label: "Detail" },
          ...(selected?.status_code === "POSTED"
            ? ([{ href: "#reversal", label: "Koreksi" }] as const)
            : []),
          { href: "#history", label: "Riwayat" },
        ] as const}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section id="overview" className="scroll-mt-24">
          <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="section-kicker">Kontrol stok</p>
              <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
                Saldo Awal produksi yang dapat diaudit.
              </h1>
              <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
                Posting saldo awal menulis INITIAL_BALANCE ke ledger.
                Estimasi tetap belum terverifikasi sampai stok opname pertama
                menghitung produk, batch, dan bucket yang sama.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Pill label="Ledger append-only" tone="info" />
              <Pill label="Preview stock-neutral" tone="warning" />
              <Pill label="Verifikasi lewat opname" tone="success" />
            </div>
          </div>

          {params.success ? (
            <div className="mt-6 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-100">
              {params.success}
            </div>
          ) : null}

          {params.error ? (
            <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-100">
              {params.error}
            </div>
          ) : null}
        </section>

        <section id="new" className="mt-10 scroll-mt-24">
          <div className="panel-card">
            <p className="section-kicker">Dokumen baru</p>
            <h2 className="mt-2 text-2xl font-semibold text-white">
              Buat header draft saldo awal.
            </h2>
            <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
              Header belum mengubah stok. Baris produk dan batch ditambahkan
              setelah draft dibuat.
            </p>

            <form
              action={createOpeningBalanceAction}
              className="mt-6 grid gap-4 lg:grid-cols-2"
            >
              <label className="space-y-2">
                <span className="text-sm text-slate-300">
                  Referensi dokumen sumber
                </span>
                <input
                  className="w-full rounded-xl border border-white/10 bg-slate-950/60 px-3 py-2.5 text-sm text-white"
                  maxLength={200}
                  name="sourceRef"
                  placeholder="OB-2026-GUDANG-UTAMA"
                  required
                />
              </label>

              <label className="space-y-2">
                <span className="text-sm text-slate-300">
                  Waktu cutover
                </span>
                <input
                  className="w-full rounded-xl border border-white/10 bg-slate-950/60 px-3 py-2.5 text-sm text-white"
                  defaultValue={defaultDateTimeLocal()}
                  name="cutoverAt"
                  required
                  type="datetime-local"
                />
              </label>

              <label className="space-y-2 lg:col-span-2">
                <span className="text-sm text-slate-300">
                  Referensi estimasi / bukti sumber
                </span>
                <input
                  className="w-full rounded-xl border border-white/10 bg-slate-950/60 px-3 py-2.5 text-sm text-white"
                  maxLength={200}
                  name="sourceEstimateRef"
                  placeholder="Berita acara, spreadsheet opname awal, atau nomor dokumen"
                  required
                />
              </label>

              <label className="space-y-2 lg:col-span-2">
                <span className="text-sm text-slate-300">
                  Catatan dasar saldo awal
                </span>
                <textarea
                  className="min-h-24 w-full rounded-xl border border-white/10 bg-slate-950/60 px-3 py-2.5 text-sm text-white"
                  maxLength={2000}
                  name="note"
                  required
                />
              </label>

              <button
                className="rounded-xl bg-sky-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-sky-200 lg:col-span-2 lg:w-fit"
                type="submit"
              >
                Buat draft saldo awal
              </button>
            </form>
          </div>
        </section>

        <section id="detail" className="mt-10 scroll-mt-24">
          {selected ? (
            <div className="space-y-6">
              <div className="panel-card">
                <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <p className="section-kicker">Detail dokumen</p>
                    <h2 className="mt-2 text-2xl font-semibold text-white">
                      {selected.cutover_no}
                    </h2>
                    <p className="mt-2 text-sm text-slate-400">
                      {selected.source_ref} · efektif{" "}
                      {selected.effective_local_date}
                    </p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Pill
                      label={selected.operational_status_code}
                      tone={operationalTone(selected)}
                    />
                    <Pill
                      label={selected.verification_status_code}
                      tone={verificationTone(
                        selected.verification_status_code,
                      )}
                    />
                  </div>
                </div>

                <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  {[
                    ["Status lifecycle", selected.status_code],
                    ["Baris", formatNumber(selected.line_count)],
                    [
                      "Baris movement",
                      formatNumber(selected.positive_line_count),
                    ],
                    ["Total quantity", formatNumber(selected.total_quantity)],
                    [
                      "Terverifikasi",
                      formatNumber(selected.verified_line_count),
                    ],
                    [
                      "Belum terverifikasi",
                      formatNumber(selected.unverified_line_count),
                    ],
                    ["Dibuat", formatDate(selected.created_at)],
                    ["Diposting", formatDate(selected.posted_at)],
                  ].map(([label, value]) => (
                    <div
                      className="rounded-2xl border border-white/10 bg-slate-950/35 p-4"
                      key={label}
                    >
                      <dt className="text-xs text-slate-500">{label}</dt>
                      <dd className="mt-2 text-sm text-slate-100">
                        {value}
                      </dd>
                    </div>
                  ))}
                </dl>

                <div className="mt-5 rounded-2xl border border-white/10 bg-slate-950/35 p-4">
                  <p className="text-xs text-slate-500">
                    Referensi estimasi
                  </p>
                  <p className="mt-2 text-sm text-white">
                    {selected.source_estimate_ref}
                  </p>
                  <p className="mt-4 text-xs text-slate-500">Catatan</p>
                  <p className="mt-2 text-sm leading-6 text-slate-300">
                    {selected.note}
                  </p>
                </div>
              </div>

              {selected.status_code === "DRAFT" ? (
                <>
                  <section id="draft" className="scroll-mt-24">
                    <OpeningBalanceDraftForm
                      action={saveOpeningBalanceDraftAction}
                      batches={data.batches}
                      cutoverAt={selected.cutover_at}
                      cutoverId={selected.cutover_id}
                      initialLines={initialDraftLines}
                      note={selected.note}
                      rowVersion={selected.row_version}
                      sourceEstimateRef={selected.source_estimate_ref}
                    />
                  </section>

                  <form
                    action={submitOpeningBalanceReviewAction}
                    className="panel-card border-amber-400/20 bg-amber-400/[0.04]"
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
                    <p className="section-kicker text-amber-300">
                      Kunci draft
                    </p>
                    <h3 className="mt-2 text-xl font-semibold text-white">
                      Kirim ke review authoritative.
                    </h3>
                    <p className="mt-3 text-sm leading-6 text-slate-400">
                      Setelah review, baris tidak lagi dapat diedit. Preview
                      membaca ulang ledger, projection, dan master batch.
                    </p>
                    <button
                      className="mt-5 rounded-xl bg-amber-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-amber-200 disabled:cursor-not-allowed disabled:opacity-40"
                      disabled={selected.line_count === 0}
                      type="submit"
                    >
                      Kirim ke review
                    </button>
                  </form>
                </>
              ) : null}

              {previewError ? (
                <div className="panel-card border-rose-400/20 bg-rose-400/[0.05] text-rose-100">
                  {previewError}
                </div>
              ) : null}

              {preview ? <PreviewPanel preview={preview} /> : null}

              {selected.status_code === "POSTED" ? (
                <>
                  <section className="panel-card">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
                      <div>
                        <p className="section-kicker">
                          Verifikasi per baris
                        </p>
                        <h3 className="mt-2 text-xl font-semibold text-white">
                          Bukti stok opname pertama.
                        </h3>
                      </div>
                      {selected.reversal_transaction_id ? (
                        <Pill label="Cutover sudah dibalik" tone="danger" />
                      ) : null}
                    </div>

                    <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10">
                      <table>
                        <thead>
                          <tr>
                            <th>Baris</th>
                            <th>Produk</th>
                            <th>Batch</th>
                            <th>Bucket</th>
                            <th className="text-right">Quantity</th>
                            <th>Status</th>
                            <th>Opname verifikator</th>
                            <th>Ledger</th>
                          </tr>
                        </thead>
                        <tbody>
                          {data.lines.map((line) => (
                            <tr key={line.opening_balance_line_id}>
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
                                <p className="font-medium text-white">
                                  {line.batch_code_snapshot}
                                </p>
                                <p className="mt-1 text-xs text-slate-500">
                                  exp {line.expiry_date_snapshot}
                                </p>
                              </td>
                              <td>{line.bucket_code}</td>
                              <td className="text-right font-mono">
                                {formatNumber(line.quantity)}
                              </td>
                              <td>
                                <Pill
                                  label={line.verification_status_code}
                                  tone={verificationTone(
                                    line.verification_status_code,
                                  )}
                                />
                              </td>
                              <td>
                                {line.verifying_stocktake_id ? (
                                  <Link
                                    className="text-sky-200 underline decoration-sky-400/30 underline-offset-4"
                                    href={`/stocktakes/${line.verifying_stocktake_id}`}
                                  >
                                    {line.verifying_stocktake_no ??
                                      line.verifying_stocktake_id}
                                  </Link>
                                ) : (
                                  <span className="text-slate-600">
                                    Belum dihitung
                                  </span>
                                )}
                              </td>
                              <td className="font-mono text-xs text-slate-500">
                                {line.ledger_entry_id ?? "zero line"}
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </section>

                  <section className="panel-card">
                    <p className="section-kicker">Ledger drill-down</p>
                    <h3 className="mt-2 text-xl font-semibold text-white">
                      Movement INITIAL_BALANCE.
                    </h3>
                    <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10">
                      <table>
                        <thead>
                          <tr>
                            <th>Ledger seq</th>
                            <th>Produk</th>
                            <th>Batch</th>
                            <th>Bucket</th>
                            <th className="text-right">Delta</th>
                            <th>Entry ID</th>
                          </tr>
                        </thead>
                        <tbody>
                          {data.ledger.length ? (
                            data.ledger.map((entry) => (
                              <tr key={entry.ledger_entry_id}>
                                <td>{entry.ledger_seq}</td>
                                <td>{entry.product_sku_snapshot}</td>
                                <td>{entry.batch_code_snapshot}</td>
                                <td>{entry.bucket_code}</td>
                                <td className="text-right font-mono font-semibold text-emerald-200">
                                  +{formatNumber(entry.quantity_delta)}
                                </td>
                                <td className="font-mono text-xs text-slate-500">
                                  {entry.ledger_entry_id}
                                </td>
                              </tr>
                            ))
                          ) : (
                            <tr>
                              <td
                                className="text-center text-slate-500"
                                colSpan={6}
                              >
                                Tidak ada movement untuk baris quantity nol.
                              </td>
                            </tr>
                          )}
                        </tbody>
                      </table>
                    </div>
                  </section>
                </>
              ) : null}

              {reversalPreviewError ? (
                <div
                  id="reversal"
                  className="panel-card scroll-mt-24 border-rose-400/20 bg-rose-400/[0.05] text-rose-100"
                >
                  {reversalPreviewError}
                </div>
              ) : null}

              {reversalPreview ? (
                <ReversalPreviewPanel preview={reversalPreview} />
              ) : null}

              {data.selectedReversal ? (
                <ReversalAuditPanel
                  ledger={data.reversalLedger}
                  reversal={data.selectedReversal}
                />
              ) : null}
            </div>
          ) : (
            <div className="panel-card text-sm leading-6 text-slate-400">
              Pilih dokumen dari riwayat atau buat draft baru. Saldo tidak
              dapat diedit langsung dari halaman ini.
            </div>
          )}
        </section>

        <section id="history" className="mt-10 scroll-mt-24">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="section-kicker">Riwayat immutable</p>
              <h2 className="section-title">
                Draft, cutover aktif, dan dokumen yang sudah dibalik.
              </h2>
            </div>
            <Pill
              label={`${formatNumber(data.cutovers.length)} dokumen`}
              tone="neutral"
            />
          </div>

          <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10 bg-slate-950/35">
            <table>
              <thead>
                <tr>
                  <th>Dokumen</th>
                  <th>Status</th>
                  <th>Verifikasi</th>
                  <th>Tanggal efektif</th>
                  <th className="text-right">Baris</th>
                  <th className="text-right">Quantity</th>
                  <th>Detail</th>
                </tr>
              </thead>
              <tbody>
                {data.cutovers.length ? (
                  data.cutovers.map((cutover) => (
                    <tr key={cutover.cutover_id}>
                      <td>
                        <p className="font-medium text-white">
                          {cutover.cutover_no}
                        </p>
                        <p className="mt-1 text-xs text-slate-500">
                          {cutover.source_ref}
                        </p>
                      </td>
                      <td>
                        <Pill
                          label={cutover.operational_status_code}
                          tone={operationalTone(cutover)}
                        />
                      </td>
                      <td>
                        <Pill
                          label={cutover.verification_status_code}
                          tone={verificationTone(
                            cutover.verification_status_code,
                          )}
                        />
                      </td>
                      <td>{cutover.effective_local_date}</td>
                      <td className="text-right font-mono">
                        {formatNumber(cutover.line_count)}
                      </td>
                      <td className="text-right font-mono">
                        {formatNumber(cutover.total_quantity)}
                      </td>
                      <td>
                        <Link
                          className="text-sky-200 underline decoration-sky-400/30 underline-offset-4"
                          href={`/opening-balances?cutoverId=${encodeURIComponent(
                            cutover.cutover_id,
                          )}#detail`}
                        >
                          Buka
                        </Link>
                      </td>
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td className="text-center text-slate-500" colSpan={7}>
                      Belum ada dokumen saldo awal produksi.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </main>
  );
}
