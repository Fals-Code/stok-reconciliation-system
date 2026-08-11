"use client";

import { useMemo, useRef, useState, type FormEvent } from "react";
import { useFormStatus } from "react-dom";

import {
  postStockDisposalAction,
  previewStockDisposalAction,
} from "@/app/stock-disposals/actions";
import {
  STOCK_DISPOSAL_REASON_CODES,
  serializeStockDisposalDraft,
  type StockDisposalBucketCode,
  type StockDisposalDraft,
  type StockDisposalReasonCode,
} from "@/app/stock-disposals/draft";
import { Button, StatusBadge } from "@/components/ui";
import { WizardProgress } from "@/components/ui/wizard-progress";
import type {
  StockDisposalCandidate,
  StockDisposalPreview,
} from "@/lib/supabase-rest";

type EditableLine = {
  productId: string;
  batchId: string;
  sourceBucketCode: StockDisposalBucketCode;
  quantity: string;
  sourceLineRef: string;
};

const numberFormatter = new Intl.NumberFormat("id-ID");

function reasonLabel(reason: StockDisposalReasonCode) {
  return reason === "DAMAGED_DISPOSAL" ? "Barang Rusak" : "Barang Kedaluwarsa";
}

function conditionLabel(bucket: StockDisposalBucketCode) {
  return bucket === "SELLABLE" ? "Layak Dijual" : bucket === "QUARANTINE" ? "Ditahan" : "Rusak";
}

function amount(value: number | null | undefined) {
  return value === null || value === undefined ? "Belum tersedia" : `${numberFormatter.format(value)} unit`;
}

function bucketAmount(candidate: StockDisposalCandidate | undefined, bucket: StockDisposalBucketCode) {
  if (!candidate) return 0;
  return bucket === "SELLABLE" ? candidate.sellable_qty : bucket === "QUARANTINE" ? candidate.quarantine_qty : candidate.damaged_qty;
}

function availableBuckets(candidate: StockDisposalCandidate | undefined, reason: StockDisposalReasonCode): StockDisposalBucketCode[] {
  if (!candidate) return [] as StockDisposalBucketCode[];
  if (reason === "DAMAGED_DISPOSAL") return candidate.damaged_qty > 0 ? ["DAMAGED"] : [];
  return (["SELLABLE", "QUARANTINE", "DAMAGED"] as StockDisposalBucketCode[]).filter((bucket) => bucketAmount(candidate, bucket) > 0);
}

function candidateEligible(candidate: StockDisposalCandidate, reason: StockDisposalReasonCode) {
  if (!candidate.product_is_active || candidate.batch_status_code === "ARCHIVED") return false;
  return reason === "DAMAGED_DISPOSAL" ? candidate.damaged_qty > 0 : candidate.is_expired && candidate.physical_qty > 0;
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
  return <Button loading={pending} loadingLabel="Memeriksa..." type="submit">Lanjut: Periksa Pemusnahan</Button>;
}

function PostButton() {
  const { pending } = useFormStatus();
  return <Button loading={pending} loadingLabel="Menyimpan..." type="submit" variant="danger">Catat Pemusnahan</Button>;
}

function PreviewPanel({ draft, intentId, onEdit, preview }: { draft: string; intentId: string | null; onEdit: () => void; preview: StockDisposalPreview }) {
  return <section aria-live="polite" className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface shadow-[var(--ui-shadow-sm)]" id="preview">
    <div className="border-b border-ui-border px-5 py-5">
      <WizardProgress ariaLabel="Tahapan Pemusnahan" current={2} />
      <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div><h2 className="text-lg font-semibold text-ui-text">Periksa Pemusnahan</h2><p className="mt-1 text-sm leading-6 text-ui-text-muted">Dampak stok per batch dihitung dari saldo saat ini. Pastikan batch, kondisi, jumlah, bukti, dan catatan sudah benar sebelum dicatat.</p></div>
        <StatusBadge tone={preview.eligible ? "selected" : "danger"}>{preview.eligible ? "Siap dicatat" : "Belum dapat dicatat"}</StatusBadge>
      </div>
    </div>
    <div className="grid gap-3 border-b border-ui-border px-5 py-4 sm:grid-cols-3"><div><p className="text-xs text-ui-text-muted">Jenis pemusnahan</p><p className="mt-1 text-sm font-semibold text-ui-text">{reasonLabel(preview.reasonCode)}</p></div><div><p className="text-xs text-ui-text-muted">Jumlah dimusnahkan</p><p className="mt-1 text-sm font-semibold text-ui-text">{amount(preview.totalRequestedQuantity)}</p></div><div><p className="text-xs text-ui-text-muted">Bukti</p><p className="mt-1 text-sm font-semibold text-ui-text">{preview.referenceText}</p></div></div>
    {preview.blockers.length ? <div className="space-y-3 px-5 py-4">{preview.blockers.map((blocker, index) => <div className="rounded-[var(--ui-radius-md)] border border-ui-danger bg-ui-danger-subtle p-4 text-sm text-ui-danger" key={`${blocker.lineNo ?? "form"}-${index}`} role="alert"><p className="font-semibold">Perlu diperbaiki</p><p className="mt-1 leading-6">{blocker.message}</p></div>)}</div> : null}
    <div className="divide-y divide-ui-border">{preview.lines.map((line) => <article className="px-5 py-4" key={line.lineNo}><div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-semibold text-ui-text">{line.productSku ?? "Produk tidak ditemukan"} · Kode Batch {line.batchCode ?? "belum tersedia"}</p><p className="mt-1 text-sm text-ui-text-muted">Kondisi stok: {conditionLabel(line.sourceBucketCode)} · Kedaluwarsa {line.expiryDate ?? "belum tersedia"}</p></div><StatusBadge tone={line.lineEligible ? "selected" : "danger"}>{line.lineEligible ? "Siap" : "Terblokir"}</StatusBadge></div><dl className="mt-3 grid gap-2 text-sm sm:grid-cols-3"><div><dt className="text-ui-text-muted">Dimusnahkan</dt><dd className="mt-1 font-semibold text-ui-text">{amount(line.quantityRequested)}</dd></div><div><dt className="text-ui-text-muted">Saldo batch</dt><dd className="mt-1 text-ui-text">{amount(line.currentBatchBucketQty)} -&gt; {amount(line.resultingBatchBucketQty)}</dd></div><div><dt className="text-ui-text-muted">Stok fisik produk</dt><dd className="mt-1 text-ui-text">{amount(line.currentProductOnHandQty)} -&gt; {amount(line.resultingProductOnHandQty)}</dd></div></dl></article>)}</div>
    {preview.eligible && intentId ? <form action={postStockDisposalAction} className="border-t border-ui-border bg-ui-danger-subtle px-5 py-5"><input name="draft" type="hidden" value={draft} /><input name="previewBasisHash" type="hidden" value={preview.basisHash} /><input name="intentId" type="hidden" value={intentId} /><h3 className="text-lg font-semibold text-ui-text">Konfirmasi dan catat</h3><p className="mt-1 text-sm leading-6 text-ui-text-muted">Menyimpan akan mengurangi barang fisik dari batch dan kondisi stok yang diperiksa di atas.</p><label className="mt-4 flex items-start gap-3 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4 text-sm text-ui-text"><input className="mt-0.5 size-4" name="confirmation" required type="checkbox" /><span><span className="font-semibold">Saya sudah memeriksa batch, jumlah, bukti, dan catatan.</span><span className="mt-1 block text-ui-text-muted">Pemusnahan yang tersimpan tidak dapat diedit.</span></span></label><div className="mt-5 flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between"><Button onClick={onEdit} type="button" variant="secondary">Ubah Data</Button><PostButton /></div></form> : <div className="border-t border-ui-border px-5 py-4"><p className="text-sm leading-6 text-ui-text-muted">Perbaiki data yang terblokir sebelum melanjutkan. Stok belum berubah.</p><Button className="mt-4" onClick={onEdit} type="button" variant="secondary">Ubah Data</Button></div>}
  </section>;
}

export default function StockDisposalDraftForm({ candidates, contextBatchId, initialDraft, initialPreviewDraft, intentId, preview, previewError }: { candidates: StockDisposalCandidate[]; contextBatchId: string | null; initialDraft: StockDisposalDraft; initialPreviewDraft: string | null; intentId: string | null; preview: StockDisposalPreview | null; previewError: string | null }) {
  const [sourceRef, setSourceRef] = useState(initialDraft.sourceRef);
  const [occurredAt, setOccurredAt] = useState(initialDraft.occurredAt);
  const [reasonCode, setReasonCode] = useState<StockDisposalReasonCode>(initialDraft.reasonCode);
  const [referenceText, setReferenceText] = useState(initialDraft.referenceText);
  const [note, setNote] = useState(initialDraft.note);
  const [lines, setLines] = useState<EditableLine[]>(initialDraft.lines.map((line) => ({ ...line, quantity: String(line.quantity) })));
  const [previewCurrent, setPreviewCurrent] = useState(Boolean(preview || previewError));
  const [formError, setFormError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const evidenceInput = useRef<HTMLInputElement>(null);
  const noteInput = useRef<HTMLTextAreaElement>(null);
  const eligibleCandidates = useMemo(() => candidates.filter((candidate) => candidateEligible(candidate, reasonCode)), [candidates, reasonCode]);
  const draft = useMemo(() => serializeStockDisposalDraft({ sourceRef, occurredAt, reasonCode, lines: lines.map((line) => ({ ...line, quantity: Number(line.quantity) })), referenceText, note }), [sourceRef, occurredAt, reasonCode, lines, referenceText, note]);

  function changed() { setPreviewCurrent(false); setFormError(""); }
  function selectReason(
    value: StockDisposalReasonCode,
  ) {
    changed();
    setReasonCode(value);

    setLines((current) =>
      current.map((line) => {
        if (
          contextBatchId &&
          line.batchId === contextBatchId
        ) {
          const candidate =
            candidates.find(
              (item) =>
                item.batch_id ===
                contextBatchId,
            );

          if (
            candidate &&
            candidateEligible(
              candidate,
              value,
            )
          ) {
            const buckets =
              availableBuckets(
                candidate,
                value,
              );

            return {
              ...line,
              productId:
                candidate.product_id,
              batchId:
                candidate.batch_id,
              sourceBucketCode:
                value === "DAMAGED_DISPOSAL"
                  ? "DAMAGED"
                  : buckets[0] ??
                    "SELLABLE",
            };
          }
        }

        return {
          ...line,
          productId: "",
          batchId: "",
          sourceBucketCode:
            value === "DAMAGED_DISPOSAL"
              ? "DAMAGED"
              : "SELLABLE",
        };
      }),
    );
  }
  function selectBatch(sourceLineRef: string, batchId: string) { changed(); const candidate = candidates.find((item) => item.batch_id === batchId); const buckets = availableBuckets(candidate, reasonCode); setLines((current) => current.map((line) => line.sourceLineRef === sourceLineRef ? { ...line, productId: candidate?.product_id ?? "", batchId, sourceBucketCode: (reasonCode === "DAMAGED_DISPOSAL" ? "DAMAGED" : (buckets[0] ?? "SELLABLE")) as StockDisposalBucketCode } : line)); }
  function submit(event: FormEvent<HTMLFormElement>) { if (!referenceText.trim() || !note.trim()) { event.preventDefault(); setFormError("Bukti / Berita Acara dan Catatan wajib diisi sebelum pemusnahan diperiksa."); (!referenceText.trim() ? evidenceInput : noteInput).current?.focus(); return; } setIsSubmitting(true); }

  return <>
    <style>{`
      #stock-disposal-draft :has(> label[for^="disposal-batch-"]) {
        grid-template-columns: minmax(0, 1fr);
      }

      #stock-disposal-draft :has(> label[for^="disposal-batch-"]) > *,
      #stock-disposal-draft :has(> label[for^="disposal-batch-"]) :is(select, input, button) {
        min-width: 0;
      }

      @media (min-width: 640px) {
        #stock-disposal-draft :has(> label[for^="disposal-batch-"]) {
          grid-template-columns: minmax(0, 1fr) minmax(0, 0.8fr) 8rem auto;
        }
      }
    `}</style>
    <div id="stock-disposal-draft">
    {!(previewCurrent && preview && initialPreviewDraft) ? (
    <form action={previewStockDisposalAction} className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 shadow-[var(--ui-shadow-sm)]" onInvalidCapture={(event) => { if ((event.target as HTMLTextAreaElement).id === "disposal-note") setFormError("Catatan wajib diisi sebelum pemusnahan diperiksa."); }} onSubmit={submit}><input name="draft" type="hidden" value={draft} />
      <div className="border-b border-ui-border pb-5"><WizardProgress ariaLabel="Tahapan Pemusnahan" current={1} /><p className="mt-4 text-sm leading-6 text-ui-text-muted">Isi bukti pemusnahan, lalu pilih batch, kondisi stok, dan jumlah yang benar. Dampak stok baru diperiksa pada langkah berikutnya.</p></div>
      <div className="mt-5 grid gap-4 sm:grid-cols-2"><label className="grid gap-2 text-sm font-semibold text-ui-text" htmlFor="disposal-reference">Referensi Pemusnahan<input className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting} id="disposal-reference" maxLength={200} onChange={(event) => { changed(); setSourceRef(event.target.value); }} required value={sourceRef} /></label><label className="grid gap-2 text-sm font-semibold text-ui-text" htmlFor="disposal-occurred-at">Waktu Pemusnahan<input className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting} id="disposal-occurred-at" onChange={(event) => { changed(); setOccurredAt(event.target.value); }} required type="datetime-local" value={occurredAt} /></label><label className="grid gap-2 text-sm font-semibold text-ui-text" htmlFor="disposal-reason">Jenis Pemusnahan<select className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting} id="disposal-reason" onChange={(event) => selectReason(event.target.value as StockDisposalReasonCode)} value={reasonCode}>{STOCK_DISPOSAL_REASON_CODES.map((reason) => <option key={reason} value={reason}>{reasonLabel(reason)}</option>)}</select></label><label className="grid gap-2 text-sm font-semibold text-ui-text" htmlFor="disposal-evidence">Bukti / Berita Acara<input aria-describedby={formError ? "disposal-form-error" : undefined} aria-invalid={formError ? true : undefined} className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting} id="disposal-evidence" maxLength={200} onChange={(event) => { changed(); setReferenceText(event.target.value); }} ref={evidenceInput} required value={referenceText} /></label><label className="grid gap-2 text-sm font-semibold text-ui-text sm:col-span-2" htmlFor="disposal-note">Catatan<textarea aria-describedby={formError ? "disposal-form-error" : undefined} aria-invalid={formError ? true : undefined} className="min-h-28 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 py-3 text-sm font-normal text-ui-text" disabled={isSubmitting} id="disposal-note" maxLength={2000} onChange={(event) => { changed(); setNote(event.target.value); }} ref={noteInput} required value={note} /></label></div>
      {formError ? <p className="mt-3 text-sm font-medium text-ui-danger" id="disposal-form-error" role="alert">{formError}</p> : null}
      <div className="mt-6 border-t border-ui-border pt-5"><div className="flex items-center justify-between gap-3"><div><h3 className="text-sm font-semibold text-ui-text">Batch dan Jumlah</h3><p className="mt-1 text-sm text-ui-text-muted">Pilih Kode Batch dan kondisi stok yang benar.</p></div><Button disabled={isSubmitting} onClick={() => { changed(); setLines((current) => [...current, { productId: "", batchId: "", sourceBucketCode: (reasonCode === "DAMAGED_DISPOSAL" ? "DAMAGED" : "SELLABLE") as StockDisposalBucketCode, quantity: "1", sourceLineRef: nextLineRef(current) }]); }} type="button" variant="secondary">Tambah Batch</Button></div><div className="mt-4 grid gap-3">{lines.map((line, index) => { const selected = candidates.find((candidate) => candidate.batch_id === line.batchId); const buckets = availableBuckets(selected, reasonCode); return <div className="grid grid-cols-[minmax(0,1fr)] gap-3 rounded-[var(--ui-radius-md)] border border-ui-border p-4 sm:grid-cols-[minmax(0,1fr)_minmax(0,0.8fr)_8rem_auto]" key={line.sourceLineRef}><label className="grid gap-2 text-sm font-semibold text-ui-text" htmlFor={`disposal-batch-${index}`}>Kode Batch<select className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting || line.batchId === contextBatchId} id={`disposal-batch-${index}`} onChange={(event) => selectBatch(line.sourceLineRef, event.target.value)} required value={line.batchId}><option disabled value="">Pilih batch</option>{eligibleCandidates.map((candidate) => <option key={candidate.batch_id} value={candidate.batch_id}>{candidate.product_sku} · {candidate.batch_code} · kedaluwarsa {candidate.expiry_date}</option>)}</select></label><label className="grid gap-2 text-sm font-semibold text-ui-text" htmlFor={`disposal-condition-${index}`}>Kondisi Stok<select className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting || reasonCode === "DAMAGED_DISPOSAL" || !selected} id={`disposal-condition-${index}`} onChange={(event) => { changed(); setLines((current) => current.map((item) => item.sourceLineRef === line.sourceLineRef ? { ...item, sourceBucketCode: event.target.value as StockDisposalBucketCode } : item)); }} value={line.sourceBucketCode}>{buckets.map((bucket) => <option key={bucket} value={bucket}>{conditionLabel(bucket)} · {numberFormatter.format(bucketAmount(selected, bucket))} unit</option>)}</select></label><label className="grid gap-2 text-sm font-semibold text-ui-text" htmlFor={`disposal-quantity-${index}`}>Jumlah<input className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3.5 text-sm font-normal text-ui-text" disabled={isSubmitting} id={`disposal-quantity-${index}`} max={bucketAmount(selected, line.sourceBucketCode) || undefined} min="1" onChange={(event) => { changed(); setLines((current) => current.map((item) => item.sourceLineRef === line.sourceLineRef ? { ...item, quantity: event.target.value } : item)); }} required type="number" value={line.quantity} /></label><div className="flex items-end"><Button className="w-full" disabled={isSubmitting || lines.length === 1} onClick={() => { changed(); setLines((current) => current.filter((item) => item.sourceLineRef !== line.sourceLineRef)); }} type="button" variant="secondary">Hapus</Button></div></div>; })}</div>{!eligibleCandidates.length ? <p className="mt-4 text-sm leading-6 text-ui-warning">Tidak ada batch yang dapat dipilih untuk jenis pemusnahan ini. Barang Rusak hanya memakai saldo Rusak; Barang Kedaluwarsa hanya memakai batch yang sudah kedaluwarsa.</p> : null}</div>
      {preview && !previewCurrent ? <p className="mt-4 text-sm font-medium text-ui-warning">Data berubah. Dampak sebelumnya tidak berlaku. Periksa lagi sebelum menyimpan.</p> : null}<div className="mt-5 flex justify-end"><PreviewButton /></div>
    </form>
    ) : null}
    {previewCurrent && previewError ? <p className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-danger bg-ui-danger-subtle p-4 text-sm text-ui-danger" role="alert">{previewError}</p> : null}
    {previewCurrent && preview && initialPreviewDraft ? <PreviewPanel draft={initialPreviewDraft} intentId={intentId} onEdit={() => { setPreviewCurrent(false); setIsSubmitting(false); }} preview={preview} /> : null}
    </div>
  </>;
}
