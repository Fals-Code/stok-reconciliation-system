import { randomUUID } from "node:crypto";
import Link from "next/link";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import StockDisposalDraftForm from "@/app/stock-disposals/components/draft-form";
import {
  parseStockDisposalDraft,
  serializeStockDisposalDraft,
  stockDisposalErrorMessage,
  stockDisposalOccurredAt,
  type StockDisposalDraft,
} from "@/app/stock-disposals/draft";
import { Alert, StatusBadge } from "@/components/ui";
import { WizardProgress } from "@/components/ui/wizard-progress";
import { requireAdminSession } from "@/lib/auth";
import {
  getStockDisposalData,
  previewStockDisposal,
  type StockDisposalPreview,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = Record<string, string | string[] | undefined>;

const numberFormatter = new Intl.NumberFormat("id-ID");


function first(params: SearchParams, key: string) {
  const value = params[key];
  return (Array.isArray(value) ? value[0] : value)?.trim() ?? "";
}

function reasonLabel(code: string) {
  return code === "DAMAGED_DISPOSAL" ? "Barang Rusak" : "Barang Kedaluwarsa";
}

function conditionLabel(code: string) {
  return code === "SELLABLE" ? "Layak Dijual" : code === "QUARANTINE" ? "Ditahan" : "Rusak";
}

function jakartaDateTimeLocal() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

function emptyDraft(): StockDisposalDraft {
  return {
    sourceRef: "",
    occurredAt: jakartaDateTimeLocal(),
    reasonCode: "EXPIRED_DISPOSAL",
    lines: [{ productId: "", batchId: "", sourceBucketCode: "SELLABLE", quantity: 1, sourceLineRef: "UI-1" }],
    referenceText: "",
    note: "",
  };
}


export default async function StockDisposalsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [session, params] = await Promise.all([requireAdminSession(), searchParams]);
  const disposalId = first(params, "disposalId");
  let data;

  try {
    data = await getStockDisposalData(undefined, disposalId);
  } catch {
    return (
      <AppShell profile={session.profile}>
        <div className="mx-auto w-full max-w-[1040px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader description="Data untuk pemusnahan belum dapat dimuat. Tidak ada perubahan stok yang dilakukan." title="Barang Rusak / Kedaluwarsa" />
          <Alert className="mt-6" title="Data belum dapat dimuat" tone="warning">Muat ulang halaman. Jika masalah tetap terjadi, periksa Status Sistem.</Alert>
        </div>
      </AppShell>
    );
  }

  let draft = emptyDraft();
  let preview: StockDisposalPreview | null = null;
  let previewError: string | null = null;
  let contextBatchId: string | null = null;
  let contextMessage: string | null = null;
  let contextWarning: string | null = null;

  const draftParam = first(params, "draft");

  if (draftParam) {
    try {
      draft = parseStockDisposalDraft(draftParam);
      preview = await previewStockDisposal({
        sourceRef: draft.sourceRef,
        occurredAt: stockDisposalOccurredAt(draft),
        reasonCode: draft.reasonCode,
        lines: draft.lines,
        referenceText: draft.referenceText,
        note: draft.note,
        metadata: { source: "stock-disposal-admin-ui", version: 1 },
      });
    } catch (error) {
      previewError = stockDisposalErrorMessage(error);
    }
  } else {
    const requestedProductId =
      first(params, "productId");
    const requestedBatchId =
      first(params, "batchId");

    if (requestedProductId || requestedBatchId) {
      if (!requestedProductId || !requestedBatchId) {
        contextWarning =
          "Konteks produk dan batch belum lengkap. Pilih batch secara manual.";
      } else {
        const candidate =
          data.candidates.find(
            (item) =>
              item.product_id ===
                requestedProductId &&
              item.batch_id ===
                requestedBatchId,
          );

        if (!candidate) {
          contextWarning =
            "Produk dan batch dari halaman sebelumnya tidak cocok atau tidak tersedia. Pilih batch secara manual.";
        } else {
          const canUseExpired =
            candidate.product_is_active &&
            candidate.batch_status_code !==
              "ARCHIVED" &&
            candidate.is_expired &&
            candidate.physical_qty > 0;

          const canUseDamaged =
            candidate.product_is_active &&
            candidate.batch_status_code !==
              "ARCHIVED" &&
            candidate.damaged_qty > 0;

          if (!canUseExpired && !canUseDamaged) {
            contextWarning =
              "Batch dari halaman sebelumnya belum dapat dipakai untuk Barang Rusak atau Barang Kedaluwarsa. Pilih batch lain.";
          } else {
            const reasonCode =
              canUseExpired
                ? "EXPIRED_DISPOSAL"
                : "DAMAGED_DISPOSAL";

            const sourceBucketCode =
              reasonCode === "DAMAGED_DISPOSAL"
                ? "DAMAGED"
                : candidate.sellable_qty > 0
                  ? "SELLABLE"
                  : candidate.quarantine_qty > 0
                    ? "QUARANTINE"
                    : "DAMAGED";

            contextBatchId =
              candidate.batch_id;

            draft = {
              ...draft,
              reasonCode,
              lines: [
                {
                  ...draft.lines[0],
                  productId:
                    candidate.product_id,
                  batchId:
                    candidate.batch_id,
                  sourceBucketCode,
                },
              ],
            };

            contextMessage =
              `Batch ${candidate.batch_code} untuk ${candidate.product_sku} sudah dipilih dari halaman sebelumnya.`;
          }
        }
      }
    }
  }

  const message = first(params, "success") || first(params, "error");
  const selected = data.selectedDisposal;
  const damaged = data.candidates.filter((candidate) => candidate.damaged_qty > 0).length;
  const expired = data.candidates.filter((candidate) => candidate.is_expired && candidate.physical_qty > 0).length;

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1040px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <Link
          className="mb-4 inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
          href="/products"
        >
          &larr; Kembali ke Stok
        </Link>
        <PageHeader description="Catat pemusnahan barang fisik berdasarkan batch. Barang Rusak dan Barang Kedaluwarsa selalu diperiksa sebagai transaksi terpisah." eyebrow="Stok" title="Barang Rusak / Kedaluwarsa" />

        {contextMessage ? (
          <Alert
            className="mt-6"
            title="Batch sudah dipilih"
            tone="info"
          >
            <p>{contextMessage}</p>
            <p className="mt-1">
              Kondisi stok, jumlah, dan kelayakan
              tetap diperiksa oleh sistem sebelum
              pemusnahan dapat disimpan.
            </p>
          </Alert>
        ) : null}

        {contextWarning ? (
          <Alert
            className="mt-6"
            title="Konteks batch tidak dapat digunakan"
            tone="warning"
          >
            <p>{contextWarning}</p>
          </Alert>
        ) : null}
        {message ? <Alert className="mt-6" title={first(params, "success") ? "Pemusnahan tercatat" : "Pemusnahan belum tersimpan"} tone={first(params, "success") ? "success" : "warning"}><p>{message}</p>{first(params, "success") && first(params, "transactionId") ? <Link className="mt-3 inline-flex min-h-[var(--ui-control-height)] items-center font-semibold text-ui-primary hover:underline" href={`/entry-corrections?transactionId=${encodeURIComponent(first(params, "transactionId"))}#detail`}>Buka transaksi dan jalur Koreksi Entri</Link> : null}</Alert> : null}

        <section className="mt-6 grid gap-3 sm:grid-cols-2"><article className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4"><p className="text-sm font-semibold text-ui-text">Barang Rusak</p><p className="mt-1 text-sm leading-6 text-ui-text-muted">Hanya memakai kondisi stok Rusak pada Kode Batch yang dipilih.</p><p className="mt-3 text-sm font-semibold text-ui-text">{numberFormatter.format(damaged)} batch memiliki saldo rusak</p></article><article className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4"><p className="text-sm font-semibold text-ui-text">Barang Kedaluwarsa</p><p className="mt-1 text-sm leading-6 text-ui-text-muted">Hanya memakai batch yang server nyatakan sudah melewati tanggal kedaluwarsa.</p><p className="mt-3 text-sm font-semibold text-ui-text">{numberFormatter.format(expired)} batch sudah kedaluwarsa</p></article></section>

        {selected ? (
          <section className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 shadow-[var(--ui-shadow-sm)] sm:p-6">
            <WizardProgress ariaLabel="Tahapan Pemusnahan" current={3} />
            <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div><p className="text-sm font-semibold text-ui-primary">Pemusnahan berhasil dicatat</p><h2 className="mt-1 text-xl font-semibold text-ui-text">{selected.disposal_no}</h2><p className="mt-1 text-sm text-ui-text-muted">{reasonLabel(selected.reason_code_snapshot)} · {numberFormatter.format(selected.total_quantity)} unit</p></div>
              <StatusBadge tone="selected">Tersimpan</StatusBadge>
            </div>
            <div className="mt-5 grid gap-3 text-sm sm:grid-cols-2"><p><span className="text-ui-text-muted">Bukti / Berita Acara</span><br /><span className="font-medium text-ui-text">{selected.reference_text}</span></p><p><span className="text-ui-text-muted">Catatan</span><br /><span className="font-medium text-ui-text">{selected.note}</span></p></div>
            {data.lines.length ? <div className="mt-4 grid gap-3">{data.lines.map((line) => <div className="rounded-[var(--ui-radius-md)] border border-ui-border p-4" key={line.disposal_line_id}><p className="font-semibold text-ui-text">{line.product_sku_snapshot} · Kode Batch {line.batch_code_snapshot}</p><p className="mt-1 text-sm text-ui-text-muted">{conditionLabel(line.source_bucket_code)} · {numberFormatter.format(line.quantity_disposed)} unit dimusnahkan · saldo batch {numberFormatter.format(line.bucket_before_qty)} -&gt; {numberFormatter.format(line.bucket_after_qty)} unit</p></div>)}</div> : null}
            <div className="mt-6 flex flex-col gap-3 sm:flex-row">
              <Link className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary" href="/stock-disposals">Catat Pemusnahan Lagi</Link>
              <Link className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-text" href={`/entry-corrections?transactionId=${encodeURIComponent(selected.transaction_id)}#detail`}>Tinjau melalui Koreksi Entri</Link>
            </div>
          </section>
        ) : (
          <section className="mt-6"><StockDisposalDraftForm candidates={data.candidates} contextBatchId={contextBatchId} initialDraft={draft} initialPreviewDraft={preview ? serializeStockDisposalDraft(draft) : null} intentId={preview?.eligible ? randomUUID() : null} preview={preview} previewError={previewError} /></section>
        )}
      </div>
    </AppShell>
  );
}
