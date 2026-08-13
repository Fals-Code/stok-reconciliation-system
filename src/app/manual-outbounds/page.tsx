import { randomUUID } from "node:crypto";
import Link from "next/link";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import ManualOutboundDraftForm from "@/app/manual-outbounds/components/draft-form";
import {
  manualOutboundErrorMessage,
  manualOutboundOccurredAt,
  parseManualOutboundDraft,
  serializeManualOutboundDraft,
  type ManualOutboundDraft,
} from "@/app/manual-outbounds/draft";
import { Alert, StatusBadge } from "@/components/ui";
import { WizardProgress } from "@/components/ui/wizard-progress";
import { requireAdminSession } from "@/lib/auth";
import {
  getManualOutboundData,
  previewManualOutbound,
  type ManualOutboundPreview,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = Record<string, string | string[] | undefined>;

const numberFormatter = new Intl.NumberFormat("id-ID");
const UUID_PATTERN = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i;

function safeReference(value: string) {
  return UUID_PATTERN.test(value) ? "Referensi internal" : value;
}

function first(params: SearchParams, key: string) {
  const value = params[key];
  return (Array.isArray(value) ? value[0] : value)?.trim() ?? "";
}

function reasonLabel(code: string) {
  const labels: Record<string, string> = {
    OFFLINE_SALE: "Penjualan Langsung",
    BONUS: "Bonus",
    PROMO: "Promo",
    SAMPLE: "Sampel",
  };
  return labels[code] ?? "Barang keluar";
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

function emptyDraft(): ManualOutboundDraft {
  return {
    sourceRef: "",
    occurredAt: jakartaDateTimeLocal(),
    reasonCode: "OFFLINE_SALE",
    lines: [{ productId: "", quantity: 1, sourceLineRef: "UI-1" }],
    note: null,
    reference: null,
  };
}

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Waktu tidak tersedia";
  return `${new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date)} WIB`;
}

export default async function ManualOutboundsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [session, params] = await Promise.all([requireAdminSession(), searchParams]);
  const outboundId = first(params, "outboundId");
  let data;

  try {
    data = await getManualOutboundData(undefined, outboundId);
  } catch {
    return (
      <AppShell profile={session.profile}>
        <div className="mx-auto w-full max-w-[1040px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader description="Data untuk barang keluar belum dapat dimuat. Tidak ada perubahan stok yang dilakukan." title="Barang Keluar" />
          <Alert className="mt-6" title="Data belum dapat dimuat" tone="warning">Muat ulang halaman. Jika masalah tetap terjadi, periksa Status Sistem.</Alert>
        </div>
      </AppShell>
    );
  }

  let draft = emptyDraft();
  let preview: ManualOutboundPreview | null = null;
  let previewError: string | null = null;
  let contextProductId: string | null = null;
  let contextMessage: string | null = null;
  let contextWarning: string | null = null;

  const draftParam = first(params, "draft");

  if (draftParam) {
    try {
      draft = parseManualOutboundDraft(draftParam);
      preview = await previewManualOutbound({
        sourceRef: draft.sourceRef,
        occurredAt: manualOutboundOccurredAt(draft),
        reasonCode: draft.reasonCode,
        lines: draft.lines,
        note: draft.note,
        reference: draft.reference,
        metadata: { source: "manual-outbound-admin-ui", version: 1 },
      });
    } catch (error) {
      previewError = manualOutboundErrorMessage(error);
    }
  } else {
    const requestedProductId =
      first(params, "productId");

    if (requestedProductId) {
      const contextualProduct =
        data.products.find(
          (product) =>
            product.product_id ===
            requestedProductId,
        );

      if (contextualProduct) {
        contextProductId =
          contextualProduct.product_id;

        draft = {
          ...draft,
          lines: [
            {
              ...draft.lines[0],
              productId:
                contextualProduct.product_id,
            },
          ],
        };

        contextMessage =
          `Produk ${contextualProduct.sku} - ${contextualProduct.name} sudah dipilih dari halaman sebelumnya.`;
      } else {
        contextWarning =
          "Produk dari halaman sebelumnya tidak tersedia. Pilih produk yang akan dikeluarkan secara manual.";
      }
    }
  }

  const message = first(params, "success") || first(params, "error");
  const selected = data.selectedOutbound;

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1040px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <Link
          className="mb-4 inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
          href="/products"
        >
          &larr; Kembali ke Stok
        </Link>
        <PageHeader
          description="Catat barang keluar manual. Pilih produk dan jumlah, lalu sistem menentukan batch yang dipakai sesuai FEFO."
          eyebrow="Stok"
          title="Barang Keluar"
        />

        {contextMessage ? (
          <Alert
            className="mt-6"
            title="Produk sudah dipilih"
            tone="info"
          >
            <p>{contextMessage}</p>
            <p className="mt-1">
              Sistem tetap menentukan batch melalui
              pemeriksaan FEFO sebelum stok disimpan.
            </p>
          </Alert>
        ) : null}

        {contextWarning ? (
          <Alert
            className="mt-6"
            title="Konteks produk tidak dapat digunakan"
            tone="warning"
          >
            <p>{contextWarning}</p>
          </Alert>
        ) : null}

        {message ? (
          <Alert className="mt-6" title={first(params, "success") ? "Barang keluar tercatat" : "Barang keluar belum tersimpan"} tone={first(params, "success") ? "success" : "warning"}>
            <p>{message}</p>
            {first(params, "success") && first(params, "transactionId") ? <Link className="mt-3 inline-flex min-h-[var(--ui-control-height)] items-center font-semibold text-ui-primary hover:underline" href={`/entry-corrections?transactionId=${encodeURIComponent(first(params, "transactionId"))}#detail`}>Buka transaksi dan jalur Koreksi Entri</Link> : null}
          </Alert>
        ) : null}

        {selected ? (
          <section className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 shadow-[var(--ui-shadow-sm)] sm:p-6">
            <WizardProgress ariaLabel="Tahapan Barang Keluar" current={3} />
            <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div><p className="text-sm font-semibold text-ui-primary">Barang keluar berhasil dicatat</p><h2 className="mt-1 text-xl font-semibold text-ui-text">{selected.outbound_no}</h2><p className="mt-1 text-sm text-ui-text-muted">{reasonLabel(selected.reason_code_snapshot)} · {numberFormatter.format(selected.total_quantity)} unit</p></div>
              <StatusBadge tone="selected">Tersimpan</StatusBadge>
            </div>
            <div className="mt-5 grid gap-3 text-sm sm:grid-cols-2"><p><span className="text-ui-text-muted">Referensi</span><br /><span className="font-medium text-ui-text">{safeReference(selected.source_ref)}</span></p><p><span className="text-ui-text-muted">Waktu</span><br /><span className="font-medium text-ui-text">{formatDate(selected.occurred_at)}</span></p></div>
            {data.allocations.length ? <div className="mt-5"><h3 className="text-sm font-semibold text-ui-text">Alokasi FEFO tersimpan</h3><div className="mt-3 grid gap-3">{data.allocations.map((allocation) => <div className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4" key={allocation.allocation_id}><p className="font-semibold text-ui-text">{allocation.product_sku_snapshot} · Kode Batch {allocation.batch_code_snapshot}</p><p className="mt-1 text-sm text-ui-text-muted">Kedaluwarsa {allocation.expiry_date_snapshot} · {numberFormatter.format(allocation.quantity_allocated)} unit keluar</p></div>)}</div></div> : null}
            <div className="mt-6 flex flex-col gap-3 sm:flex-row">
              <Link className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary" href="/manual-outbounds">Catat Barang Keluar Lagi</Link>
              <Link className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-text" href={`/entry-corrections?transactionId=${encodeURIComponent(selected.transaction_id)}#detail`}>Buka Ledger dan Koreksi Entri</Link>
            </div>
          </section>
        ) : (
          <section className="mt-6">
            <ManualOutboundDraftForm contextProductId={contextProductId} initialDraft={draft} initialPreviewDraft={preview ? serializeManualOutboundDraft(draft) : null} intentId={preview?.eligible ? randomUUID() : null} preview={preview} previewError={previewError} products={data.products.map((product) => ({ productId: product.product_id, sku: product.sku, name: product.name, availableQuantity: product.available_qty }))} />
          </section>
        )}
      </div>
    </AppShell>
  );
}
