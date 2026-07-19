"use client";

import { useMemo, useState } from "react";

import { previewManualOutboundAction } from "@/app/manual-outbounds/actions";
import {
  MANUAL_OUTBOUND_REASON_CODES,
  serializeManualOutboundDraft,
  type ManualOutboundDraft,
  type ManualOutboundReasonCode,
} from "@/app/manual-outbounds/draft";

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

function reasonLabel(reasonCode: ManualOutboundReasonCode) {
  const labels: Record<ManualOutboundReasonCode, string> = {
    OFFLINE_SALE: "Penjualan offline",
    BONUS: "Bonus",
    PROMO: "Promo",
    SAMPLE: "Sample",
  };

  return labels[reasonCode];
}

function nextSourceLineRef(lines: EditableLine[]) {
  const nextNumber =
    Math.max(
      0,
      ...lines.map((line) => {
        const match = line.sourceLineRef.match(/(\d+)$/);
        return match ? Number(match[1]) : 0;
      }),
    ) + 1;

  return `UI-${nextNumber}`;
}

export default function ManualOutboundDraftForm({
  products,
  initialDraft,
}: {
  products: ProductOption[];
  initialDraft: ManualOutboundDraft;
}) {
  const [sourceRef, setSourceRef] = useState(initialDraft.sourceRef);
  const [occurredAt, setOccurredAt] = useState(initialDraft.occurredAt);
  const [reasonCode, setReasonCode] =
    useState<ManualOutboundReasonCode>(initialDraft.reasonCode);
  const [reference, setReference] = useState(initialDraft.reference ?? "");
  const [note, setNote] = useState(initialDraft.note ?? "");
  const [lines, setLines] = useState<EditableLine[]>(
    initialDraft.lines.length
      ? initialDraft.lines.map((line) => ({
          productId: line.productId,
          quantity: String(line.quantity),
          sourceLineRef: line.sourceLineRef,
        }))
      : [{ productId: "", quantity: "1", sourceLineRef: "UI-1" }],
  );

  const reasonNeedsExplanation = reasonCode !== "OFFLINE_SALE";
  const draft = useMemo(
    () =>
      serializeManualOutboundDraft({
        sourceRef,
        occurredAt,
        reasonCode,
        lines: lines.map((line) => ({
          productId: line.productId,
          quantity: Number(line.quantity),
          sourceLineRef: line.sourceLineRef,
        })),
        note: note.trim() || null,
        reference: reference.trim() || null,
      }),
    [sourceRef, occurredAt, reasonCode, lines, note, reference],
  );

  function updateLine(
    sourceLineRef: string,
    field: "productId" | "quantity",
    value: string,
  ) {
    setLines((current) =>
      current.map((line) =>
        line.sourceLineRef === sourceLineRef
          ? { ...line, [field]: value }
          : line,
      ),
    );
  }

  function addLine() {
    setLines((current) => [
      ...current,
      {
        productId: "",
        quantity: "1",
        sourceLineRef: nextSourceLineRef(current),
      },
    ]);
  }

  function removeLine(sourceLineRef: string) {
    setLines((current) =>
      current.length === 1
        ? current
        : current.filter((line) => line.sourceLineRef !== sourceLineRef),
    );
  }

  return (
    <form action={previewManualOutboundAction} className="panel-card">
      <input name="draft" type="hidden" value={draft} />

      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="section-kicker">Draft barang keluar</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">
            Siapkan permintaan tanpa memilih batch.
          </h2>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Database menentukan batch secara FEFO setelah reserved stock dan
            batas aman kedaluwarsa diperhitungkan.
          </p>
        </div>
        <span className="inline-flex w-fit rounded-full border border-amber-400/25 bg-amber-400/10 px-3 py-1 text-xs font-medium text-amber-100">
          FEFO otomatis
        </span>
      </div>

      <div className="form-grid mt-6">
        <label className="field-label">
          Referensi barang keluar
          <input
            maxLength={200}
            onChange={(event) => setSourceRef(event.target.value)}
            placeholder="OFFLINE-2026-001"
            required
            value={sourceRef}
          />
        </label>

        <label className="field-label">
          Waktu barang keluar
          <input
            onChange={(event) => setOccurredAt(event.target.value)}
            required
            type="datetime-local"
            value={occurredAt}
          />
        </label>

        <label className="field-label">
          Alasan
          <select
            onChange={(event) =>
              setReasonCode(event.target.value as ManualOutboundReasonCode)
            }
            required
            value={reasonCode}
          >
            {MANUAL_OUTBOUND_REASON_CODES.map((reason) => (
              <option key={reason} value={reason}>
                {reasonLabel(reason)}
              </option>
            ))}
          </select>
        </label>

        <label className="field-label">
          Referensi kegiatan / penerima
          <input
            maxLength={200}
            onChange={(event) => setReference(event.target.value)}
            placeholder={
              reasonNeedsExplanation
                ? "CAMPAIGN-JUL-2026 / penerima / approval"
                : "Opsional untuk penjualan offline"
            }
            required={reasonNeedsExplanation}
            value={reference}
          />
        </label>

        <label className="field-label sm:col-span-2">
          Catatan
          <textarea
            maxLength={2000}
            onChange={(event) => setNote(event.target.value)}
            placeholder={
              reasonNeedsExplanation
                ? "Jelaskan tujuan bonus, promo, atau sample."
                : "Catatan operasional opsional."
            }
            required={reasonNeedsExplanation}
            rows={3}
            value={note}
          />
        </label>
      </div>

      <div className="mt-7 border-t border-white/10 pt-6">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p className="section-kicker">Produk</p>
            <h3 className="mt-1 text-lg font-semibold text-white">
              Quantity per produk.
            </h3>
          </div>
          <button
            className="rounded-xl border border-white/10 px-3 py-2 text-sm font-medium text-slate-200 transition hover:border-sky-400/30 hover:text-white"
            onClick={addLine}
            type="button"
          >
            Tambah produk
          </button>
        </div>

        <div className="mt-4 space-y-3">
          {lines.map((line, index) => {
            const selectedElsewhere = new Set(
              lines
                .filter(
                  (candidate) =>
                    candidate.sourceLineRef !== line.sourceLineRef,
                )
                .map((candidate) => candidate.productId)
                .filter(Boolean),
            );

            return (
              <div
                className="grid gap-3 rounded-2xl border border-white/10 bg-slate-950/35 p-4 sm:grid-cols-[minmax(0,1fr)_9rem_auto]"
                key={line.sourceLineRef}
              >
                <label className="field-label">
                  Produk {index + 1}
                  <select
                    aria-label={`Produk baris ${index + 1}`}
                    onChange={(event) =>
                      updateLine(
                        line.sourceLineRef,
                        "productId",
                        event.target.value,
                      )
                    }
                    required
                    value={line.productId}
                  >
                    <option disabled value="">
                      Pilih produk
                    </option>
                    {products.map((product) => (
                      <option
                        disabled={selectedElsewhere.has(product.productId)}
                        key={product.productId}
                        value={product.productId}
                      >
                        {product.sku} Â· {product.name} Â· tersedia{" "}
                        {product.availableQuantity}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field-label">
                  Quantity
                  <input
                    aria-label={`Quantity baris ${index + 1}`}
                    min="1"
                    onChange={(event) =>
                      updateLine(
                        line.sourceLineRef,
                        "quantity",
                        event.target.value,
                      )
                    }
                    required
                    step="1"
                    type="number"
                    value={line.quantity}
                  />
                </label>

                <div className="flex items-end">
                  <button
                    className="w-full rounded-xl border border-rose-400/20 px-3 py-2.5 text-sm font-medium text-rose-200 transition hover:border-rose-400/40 disabled:cursor-not-allowed disabled:opacity-40"
                    disabled={lines.length === 1}
                    onClick={() => removeLine(line.sourceLineRef)}
                    type="button"
                  >
                    Hapus
                  </button>
                </div>

                <p className="text-xs text-slate-600 sm:col-span-3">
                  Referensi baris: {line.sourceLineRef}
                </p>
              </div>
            );
          })}
        </div>
      </div>

      <div className="mt-6 rounded-2xl border border-sky-400/20 bg-sky-400/[0.055] p-4 text-sm leading-6 text-sky-100">
        Preview tidak mengubah stok. Setelah diposting, dokumen dan ledger tidak
        dapat diedit atau dihapus. Kesalahan diperbaiki melalui Koreksi Entri.
      </div>

      <button className="primary-button mt-6" type="submit">
        Tinjau alokasi FEFO
      </button>
    </form>
  );
}
