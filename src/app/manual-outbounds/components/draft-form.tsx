"use client";

import { useState, useMemo, useRef, type FormEvent } from "react";
import { useFormStatus } from "react-dom";

import {
  postManualOutboundAction,
  previewManualOutboundAction,
} from "@/app/manual-outbounds/actions";
import {
  MANUAL_OUTBOUND_REASON_CODES,
  serializeManualOutboundDraft,
  type ManualOutboundDraft,
  type ManualOutboundReasonCode,
} from "@/app/manual-outbounds/draft";
import { Button, StatusBadge } from "@/components/ui";
import { WizardProgress } from "@/components/ui/wizard-progress";
import type { ManualOutboundPreview } from "@/lib/supabase-rest";

type ProductOption = {
  productId: string;
  sku: string;
  name: string;
  availableQuantity: number;
};

type EditableLine = {
  productId: string;
  quantity: string;
  sourceLineRef: string;
};

const numberFormatter = new Intl.NumberFormat("id-ID");

function reasonLabel(reasonCode: ManualOutboundReasonCode) {
  const labels: Record<ManualOutboundReasonCode, string> = {
    OFFLINE_SALE: "Penjualan Langsung",
    BONUS: "Bonus",
    PROMO: "Promo",
    SAMPLE: "Sampel",
  };

  return labels[reasonCode];
}

function amount(value: number | null | undefined) {
  if (value === null || value === undefined) return "Belum tersedia";
  return `${numberFormatter.format(value)} unit`;
}

function nextLineRef(lines: EditableLine[]) {
  let next = lines.length + 1;

  while (lines.some((line) => line.sourceLineRef === `UI-${next}`)) {
    next += 1;
  }

  return `UI-${next}`;
}

function PreviewButton() {
  const { pending } = useFormStatus();

  return (
    <Button loading={pending} loadingLabel="Memeriksa..." type="submit">
      Lanjut: Periksa Barang Keluar
    </Button>
  );
}

function PostButton() {
  const { pending } = useFormStatus();

  return (
    <Button loading={pending} loadingLabel="Menyimpan..." type="submit">
      Catat Barang Keluar
    </Button>
  );
}

function PreviewPanel({
  draft,
  intentId,
  onEdit,
  preview,
}: {
  draft: string;
  intentId: string | null;
  onEdit: () => void;
  preview: ManualOutboundPreview;
}) {
  return (
    <section aria-live="polite" className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface shadow-[var(--ui-shadow-sm)]" id="preview">
      <div className="border-b border-ui-border px-5 py-5">
        <WizardProgress ariaLabel="Tahapan Barang Keluar" current={2} />
        <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h2 className="text-lg font-semibold text-ui-text">Periksa Barang Keluar</h2>
            <p className="mt-1 text-sm leading-6 text-ui-text-muted">
              Sistem memilih batch dengan tanggal kedaluwarsa terdekat secara otomatis. Pastikan jumlah dan dampak stok sudah benar sebelum dicatat.
            </p>
          </div>
          <StatusBadge tone={preview.eligible ? "selected" : "danger"}>
            {preview.eligible ? "Siap dicatat" : "Belum dapat dicatat"}
          </StatusBadge>
        </div>
      </div>

      <div className="grid gap-3 border-b border-ui-border px-5 py-4 sm:grid-cols-3">
        <div>
          <p className="text-xs text-ui-text-muted">Alasan</p>
          <p className="mt-1 text-sm font-semibold text-ui-text">{reasonLabel(preview.reasonCode as ManualOutboundReasonCode)}</p>
        </div>
        <div>
          <p className="text-xs text-ui-text-muted">Jumlah keluar</p>
          <p className="mt-1 text-sm font-semibold text-ui-text">{amount(preview.totalRequestedQuantity)}</p>
        </div>
        <div>
          <p className="text-xs text-ui-text-muted">Alokasi batch</p>
          <p className="mt-1 text-sm font-semibold text-ui-text">{numberFormatter.format(preview.allocationCount)} batch</p>
        </div>
      </div>

      {preview.blockers.length ? (
        <div className="space-y-3 px-5 py-4">
          {preview.blockers.map((blocker, index) => (
            <div className="rounded-[var(--ui-radius-md)] border border-ui-danger bg-ui-danger-subtle p-4 text-sm text-ui-danger" key={`${blocker.lineNo ?? "form"}-${index}`} role="alert">
              <p className="font-semibold">Perlu diperbaiki</p>
              <p className="mt-1 leading-6">{blocker.message}</p>
            </div>
          ))}
        </div>
      ) : null}

      <div className="divide-y divide-ui-border">
        {preview.products.map((product) => (
          <article className="px-5 py-4" key={product.lineNo}>
            <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p className="font-semibold text-ui-text">{product.productSku ?? "Produk tidak ditemukan"}</p>
                <p className="mt-1 text-sm text-ui-text-muted">{product.productName ?? "Periksa kembali produk yang dipilih."}</p>
              </div>
              <StatusBadge tone={product.status === "READY" ? "selected" : "danger"}>{product.status === "READY" ? "Siap" : "Terblokir"}</StatusBadge>
            </div>
            <dl className="mt-3 grid gap-2 text-sm sm:grid-cols-3">
              <div><dt className="text-ui-text-muted">Diminta</dt><dd className="mt-1 font-semibold text-ui-text">{amount(product.requestedQuantity)}</dd></div>
              <div><dt className="text-ui-text-muted">Layak Dijual</dt><dd className="mt-1 text-ui-text">{amount(product.currentSellable)} -&gt; {amount(product.resultingSellable)}</dd></div>
              <div><dt className="text-ui-text-muted">Sudah dipesan</dt><dd className="mt-1 text-ui-text">{amount(product.currentReserved)}</dd></div>
            </dl>
          </article>
        ))}
      </div>

      <div className="border-t border-ui-border px-5 py-4">
        <h3 className="text-sm font-semibold text-ui-text">Alokasi FEFO per batch</h3>
        <div className="mt-3 grid gap-3">
          {preview.allocations.length ? preview.allocations.map((allocation) => (
            <div className="grid gap-2 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 sm:grid-cols-[minmax(0,1fr)_auto]" key={`${allocation.lineNo}-${allocation.allocationNo}`}>
              <div>
                <p className="font-semibold text-ui-text">{allocation.productSku} · Kode Batch {allocation.batchCode}</p>
                <p className="mt-1 text-sm text-ui-text-muted">Kedaluwarsa {allocation.expiryDate} · Stok batch {amount(allocation.currentBatchSellable)} -&gt; {amount(allocation.resultingBatchSellable)}</p>
              </div>
              <p className="ui-number text-sm font-semibold text-ui-text sm:text-right">Keluar {amount(allocation.quantity)}</p>
            </div>
          )) : <p className="text-sm text-ui-text-muted">Belum ada batch yang dapat dialokasikan untuk data ini.</p>}
        </div>
      </div>

      {preview.eligible && intentId ? (
        <form action={postManualOutboundAction} className="border-t border-ui-border bg-ui-primary-subtle px-5 py-5">
          <input name="draft" type="hidden" value={draft} />
          <input name="previewBasisHash" type="hidden" value={preview.basisHash} />
          <input name="intentId" type="hidden" value={intentId} />
          <h3 className="text-lg font-semibold text-ui-text">Konfirmasi dan catat</h3>
          <p className="mt-1 text-sm leading-6 text-ui-text-muted">
            Menyimpan akan mengurangi stok sesuai alokasi FEFO di atas. Transaksi yang sudah tersimpan tidak dapat diedit.
          </p>
          <label className="mt-4 flex items-start gap-3 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4 text-sm text-ui-text">
            <input className="mt-0.5 size-4" name="confirmation" required type="checkbox" />
            <span><span className="font-semibold">Saya sudah memeriksa jumlah dan alokasi batch.</span><span className="mt-1 block text-ui-text-muted">Jika posisi stok berubah, sistem akan meminta pemeriksaan ulang.</span></span>
          </label>
          <div className="mt-5 flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between">
            <Button onClick={onEdit} type="button" variant="secondary">Ubah Data</Button>
            <PostButton />
          </div>
        </form>
      ) : (
        <div className="border-t border-ui-border px-5 py-4">
          <p className="text-sm leading-6 text-ui-text-muted">Perbaiki data yang terblokir sebelum melanjutkan. Stok belum berubah.</p>
          <Button className="mt-4" onClick={onEdit} type="button" variant="secondary">Ubah Data</Button>
        </div>
      )}
    </section>
  );
}

export default function ManualOutboundDraftForm({
  contextProductId,
  initialDraft,
  initialPreviewDraft,
  intentId,
  preview,
  previewError,
  products,
}: {
  contextProductId: string | null;
  initialDraft: ManualOutboundDraft;
  initialPreviewDraft: string | null;
  intentId: string | null;
  preview: ManualOutboundPreview | null;
  previewError: string | null;
  products: ProductOption[];
}) {
  const [sourceRef, setSourceRef] = useState(initialDraft.sourceRef);
  const [occurredAt, setOccurredAt] = useState(initialDraft.occurredAt);
  const [reasonCode, setReasonCode] = useState<ManualOutboundReasonCode>(initialDraft.reasonCode);
  const [reference, setReference] = useState(initialDraft.reference ?? "");
  const [note, setNote] = useState(initialDraft.note ?? "");
  const [lines, setLines] = useState<EditableLine[]>(initialDraft.lines.map((line) => ({ ...line, quantity: String(line.quantity) })));
  const [previewCurrent, setPreviewCurrent] = useState(Boolean(preview || previewError));
  const [referenceError, setReferenceError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const referenceInput = useRef<HTMLInputElement>(null);

  const draft = useMemo(() => serializeManualOutboundDraft({
    sourceRef,
    occurredAt,
    reasonCode,
    lines: lines.map((line) => ({ ...line, quantity: Number(line.quantity) })),
    note: note.trim() || null,
    reference: reference.trim() || null,
  }), [sourceRef, occurredAt, reasonCode, lines, note, reference]);
  const referenceRequired = reasonCode !== "OFFLINE_SALE";

  function changed() {
    setPreviewCurrent(false);
    setReferenceError("");
  }

  function updateLine(sourceLineRef: string, field: "productId" | "quantity", value: string) {
    changed();
    setLines((current) => current.map((line) => line.sourceLineRef === sourceLineRef ? { ...line, [field]: value } : line));
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    if (referenceRequired && !reference.trim()) {
      event.preventDefault();
      setReferenceError("Referensi kegiatan, persetujuan, penerima, atau pesanan wajib diisi.");
      referenceInput.current?.focus();
      return;
    }
    setIsSubmitting(true);
  }

  return (
    <>
      {!(previewCurrent && preview && initialPreviewDraft) ? (
      <form action={previewManualOutboundAction} className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 shadow-[var(--ui-shadow-sm)]" onSubmit={submit}>
        <input name="draft" type="hidden" value={draft} />
        <div className="border-b border-ui-border pb-5">
          <WizardProgress ariaLabel="Tahapan Barang Keluar" current={1} />
          <p className="mt-4 text-sm leading-6 text-ui-text-muted">Isi informasi barang keluar dan jumlah produk. Batch tidak dipilih di langkah ini karena sistem akan menentukan alokasi FEFO pada langkah berikutnya.</p>
        </div>
        <div className="mt-5 grid gap-4 sm:grid-cols-2">
          <label className="grid gap-2 text-sm font-semibold text-ui-text" htmlFor="outbound-reference">Referensi Barang Keluar<input className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting} id="outbound-reference" maxLength={200} onChange={(event) => { changed(); setSourceRef(event.target.value); }} required value={sourceRef} /></label>
          <label className="grid gap-2 text-sm font-semibold text-ui-text" htmlFor="outbound-occurred-at">Waktu Barang Keluar<input className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting} id="outbound-occurred-at" onChange={(event) => { changed(); setOccurredAt(event.target.value); }} required type="datetime-local" value={occurredAt} /></label>
          <label className="grid gap-2 text-sm font-semibold text-ui-text" htmlFor="outbound-reason">Alasan<select className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting} id="outbound-reason" onChange={(event) => { changed(); setReasonCode(event.target.value as ManualOutboundReasonCode); }} value={reasonCode}>{MANUAL_OUTBOUND_REASON_CODES.map((reason) => <option key={reason} value={reason}>{reasonLabel(reason)}</option>)}</select></label>
          <div className="grid gap-2">
            <label className="text-sm font-semibold text-ui-text" htmlFor="outbound-business-reference">Referensi Kegiatan {referenceRequired ? "(wajib)" : "(opsional)"}</label>
            <input aria-describedby={referenceError ? "outbound-business-reference-error" : undefined} aria-invalid={referenceError ? true : undefined} className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm text-ui-text" disabled={isSubmitting} id="outbound-business-reference" maxLength={200} onChange={(event) => { changed(); setReference(event.target.value); }} ref={referenceInput} required={referenceRequired} value={reference} />
            {referenceError ? <p className="text-xs font-medium text-ui-danger" id="outbound-business-reference-error" role="alert">{referenceError}</p> : <p className="text-xs leading-5 text-ui-text-muted">Bonus, promo, dan sampel memerlukan kegiatan, persetujuan, penerima, atau pesanan.</p>}
          </div>
          <label className="grid gap-2 text-sm font-semibold text-ui-text sm:col-span-2" htmlFor="outbound-note">Catatan (opsional)<textarea className="min-h-28 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 py-3 text-sm font-normal text-ui-text" disabled={isSubmitting} id="outbound-note" maxLength={2000} onChange={(event) => { changed(); setNote(event.target.value); }} value={note} /></label>
        </div>
        <div className="mt-6 border-t border-ui-border pt-5">
          <div className="flex items-center justify-between gap-3"><div><h3 className="text-sm font-semibold text-ui-text">Produk dan Jumlah</h3><p className="mt-1 text-sm text-ui-text-muted">Batch tidak dipilih pada alur ini.</p></div><Button disabled={isSubmitting} onClick={() => { changed(); setLines((current) => [...current, { productId: "", quantity: "1", sourceLineRef: nextLineRef(current) }]); }} type="button" variant="secondary">Tambah Produk</Button></div>
          <div className="mt-4 grid gap-3">
            {lines.map((line, index) => {
              const selected = new Set(lines.filter((item) => item.sourceLineRef !== line.sourceLineRef).map((item) => item.productId));
              const isContextProduct =
                Boolean(contextProductId) &&
                line.sourceLineRef === "UI-1" &&
                line.productId === contextProductId;

               return (
                 <div className="grid grid-cols-[minmax(0,1fr)] gap-3 rounded-[var(--ui-radius-md)] border border-ui-border p-4 sm:grid-cols-[minmax(0,1fr)_9rem_auto]" key={line.sourceLineRef}>
                   <label className="grid min-w-0 gap-2 text-sm font-semibold text-ui-text" htmlFor={`outbound-product-${index}`}>
                     Produk {index + 1}
                     <select className="min-h-[var(--ui-control-height)] min-w-0 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting || isContextProduct} id={`outbound-product-${index}`} onChange={(event) => updateLine(line.sourceLineRef, "productId", event.target.value)} required value={line.productId}>
                       <option disabled value="">Pilih produk</option>
                       {products.map((product) => <option disabled={selected.has(product.productId)} key={product.productId} value={product.productId}>{product.sku} · {product.name} · tersedia {numberFormatter.format(product.availableQuantity)} unit</option>)}
                     </select>
                   </label>
                   <label className="grid min-w-0 gap-2 text-sm font-semibold text-ui-text" htmlFor={`outbound-quantity-${index}`}>
                     Jumlah
                     <input className="min-h-[var(--ui-control-height)] min-w-0 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting} id={`outbound-quantity-${index}`} min="1" onChange={(event) => updateLine(line.sourceLineRef, "quantity", event.target.value)} required step="1" type="number" value={line.quantity} />
                   </label>
                   <div className="flex min-w-0 items-end"><Button className="w-full min-w-0" disabled={isSubmitting || lines.length === 1} onClick={() => { changed(); setLines((current) => current.filter((item) => item.sourceLineRef !== line.sourceLineRef)); }} type="button" variant="secondary">Hapus</Button></div>
                 </div>
               );
            })}
          </div>
        </div>
        {preview && !previewCurrent ? <p className="mt-4 text-sm font-medium text-ui-warning">Data berubah. Dampak sebelumnya tidak berlaku. Periksa lagi sebelum menyimpan.</p> : null}
        <div className="mt-5 flex justify-end"><PreviewButton /></div>
      </form>
      ) : null}
      {previewCurrent && previewError ? <p className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-danger bg-ui-danger-subtle p-4 text-sm text-ui-danger" role="alert">{previewError}</p> : null}
      {previewCurrent && preview && initialPreviewDraft ? <PreviewPanel draft={initialPreviewDraft} intentId={intentId} onEdit={() => { setPreviewCurrent(false); setIsSubmitting(false); }} preview={preview} /> : null}
    </>
  );
}
