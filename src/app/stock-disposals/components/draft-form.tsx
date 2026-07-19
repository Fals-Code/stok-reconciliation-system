"use client";

import { useMemo, useState } from "react";

import { previewStockDisposalAction } from "@/app/stock-disposals/actions";
import {
  STOCK_DISPOSAL_REASON_CODES,
  serializeStockDisposalDraft,
  type StockDisposalBucketCode,
  type StockDisposalDraft,
  type StockDisposalReasonCode,
} from "@/app/stock-disposals/draft";

type CandidateOption = {
  organizationId: string;
  productId: string;
  productSku: string;
  productName: string;
  productIsActive: boolean;
  batchId: string;
  batchCode: string;
  expiryDate: string;
  batchStatusCode: "ACTIVE" | "BLOCKED" | "EXPIRED" | "ARCHIVED";
  blockReason: string | null;
  sellableQty: number;
  quarantineQty: number;
  damagedQty: number;
  physicalQty: number;
  reservedQty: number;
  localDate: string;
  isExpired: boolean;
  daysToExpiry: number;
};

type EditableLine = {
  productId: string;
  batchId: string;
  sourceBucketCode: StockDisposalBucketCode;
  quantity: string;
  sourceLineRef: string;
};

function reasonLabel(reasonCode: StockDisposalReasonCode) {
  return reasonCode === "DAMAGED_DISPOSAL"
    ? "Pemusnahan barang rusak"
    : "Pemusnahan barang kedaluwarsa";
}

function bucketLabel(bucketCode: StockDisposalBucketCode) {
  const labels: Record<StockDisposalBucketCode, string> = {
    SELLABLE: "Layak jual",
    QUARANTINE: "Karantina",
    DAMAGED: "Rusak",
  };

  return labels[bucketCode];
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

function candidateEligible(
  candidate: CandidateOption,
  reasonCode: StockDisposalReasonCode,
) {
  if (!candidate.productIsActive || candidate.batchStatusCode === "ARCHIVED") {
    return false;
  }

  if (reasonCode === "DAMAGED_DISPOSAL") {
    return candidate.damagedQty > 0;
  }

  return candidate.isExpired && candidate.physicalQty > 0;
}

function availableBuckets(
  candidate: CandidateOption | undefined,
  reasonCode: StockDisposalReasonCode,
): StockDisposalBucketCode[] {
  if (!candidate) return [];

  if (reasonCode === "DAMAGED_DISPOSAL") {
    return candidate.damagedQty > 0 ? ["DAMAGED"] : [];
  }

  const buckets: StockDisposalBucketCode[] = [];

  if (candidate.sellableQty > 0) buckets.push("SELLABLE");
  if (candidate.quarantineQty > 0) buckets.push("QUARANTINE");
  if (candidate.damagedQty > 0) buckets.push("DAMAGED");

  return buckets;
}

function bucketQuantity(
  candidate: CandidateOption | undefined,
  bucketCode: StockDisposalBucketCode,
) {
  if (!candidate) return 0;
  if (bucketCode === "SELLABLE") return candidate.sellableQty;
  if (bucketCode === "QUARANTINE") return candidate.quarantineQty;
  return candidate.damagedQty;
}

export default function StockDisposalDraftForm({
  candidates,
  initialDraft,
}: {
  candidates: CandidateOption[];
  initialDraft: StockDisposalDraft;
}) {
  const [sourceRef, setSourceRef] = useState(initialDraft.sourceRef);
  const [occurredAt, setOccurredAt] = useState(initialDraft.occurredAt);
  const [reasonCode, setReasonCode] =
    useState<StockDisposalReasonCode>(initialDraft.reasonCode);
  const [referenceText, setReferenceText] = useState(
    initialDraft.referenceText,
  );
  const [note, setNote] = useState(initialDraft.note);
  const [lines, setLines] = useState<EditableLine[]>(
    initialDraft.lines.length
      ? initialDraft.lines.map((line) => ({
          productId: line.productId,
          batchId: line.batchId,
          sourceBucketCode: line.sourceBucketCode,
          quantity: String(line.quantity),
          sourceLineRef: line.sourceLineRef,
        }))
      : [
          {
            productId: "",
            batchId: "",
            sourceBucketCode:
              initialDraft.reasonCode === "DAMAGED_DISPOSAL"
                ? "DAMAGED"
                : "SELLABLE",
            quantity: "1",
            sourceLineRef: "UI-1",
          },
        ],
  );

  const eligibleCandidates = useMemo(
    () =>
      candidates.filter((candidate) =>
        candidateEligible(candidate, reasonCode),
      ),
    [candidates, reasonCode],
  );

  const draft = useMemo(
    () =>
      serializeStockDisposalDraft({
        sourceRef,
        occurredAt,
        reasonCode,
        lines: lines.map((line) => ({
          productId: line.productId,
          batchId: line.batchId,
          sourceBucketCode: line.sourceBucketCode,
          quantity: Number(line.quantity),
          sourceLineRef: line.sourceLineRef,
        })),
        referenceText,
        note,
      }),
    [
      sourceRef,
      occurredAt,
      reasonCode,
      lines,
      referenceText,
      note,
    ],
  );

  function selectReason(nextReason: StockDisposalReasonCode) {
    setReasonCode(nextReason);
    setLines((current) =>
      current.map((line) => {
        const candidate = candidates.find(
          (item) => item.batchId === line.batchId,
        );

        if (!candidate || !candidateEligible(candidate, nextReason)) {
          return {
            ...line,
            productId: "",
            batchId: "",
            sourceBucketCode:
              nextReason === "DAMAGED_DISPOSAL" ? "DAMAGED" : "SELLABLE",
          };
        }

        const buckets = availableBuckets(candidate, nextReason);

        return {
          ...line,
          sourceBucketCode:
            nextReason === "DAMAGED_DISPOSAL"
              ? "DAMAGED"
              : buckets.includes(line.sourceBucketCode)
                ? line.sourceBucketCode
                : (buckets[0] ?? "SELLABLE"),
        };
      }),
    );
  }

  function selectBatch(sourceLineRef: string, batchId: string) {
    const candidate = candidates.find((item) => item.batchId === batchId);
    const buckets = availableBuckets(candidate, reasonCode);

    setLines((current) =>
      current.map((line) =>
        line.sourceLineRef === sourceLineRef
          ? {
              ...line,
              productId: candidate?.productId ?? "",
              batchId,
              sourceBucketCode:
                reasonCode === "DAMAGED_DISPOSAL"
                  ? "DAMAGED"
                  : (buckets[0] ?? "SELLABLE"),
            }
          : line,
      ),
    );
  }

  function updateLine(
    sourceLineRef: string,
    field: "sourceBucketCode" | "quantity",
    value: string,
  ) {
    setLines((current) =>
      current.map((line) =>
        line.sourceLineRef === sourceLineRef
          ? {
              ...line,
              [field]:
                field === "sourceBucketCode"
                  ? (value as StockDisposalBucketCode)
                  : value,
            }
          : line,
      ),
    );
  }

  function addLine() {
    setLines((current) => [
      ...current,
      {
        productId: "",
        batchId: "",
        sourceBucketCode:
          reasonCode === "DAMAGED_DISPOSAL" ? "DAMAGED" : "SELLABLE",
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
    <form action={previewStockDisposalAction} className="panel-card">
      <input name="draft" type="hidden" value={draft} />

      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="section-kicker">Draft pemusnahan stok</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">
            Pilih batch dan bucket fisik yang benar-benar dimusnahkan.
          </h2>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Pemusnahan bukan outbound FEFO. Operator wajib memilih batch dan
            bucket sumber secara eksplisit, kemudian database memvalidasi saldo,
            reserved stock, status batch, dan tanggal kedaluwarsa.
          </p>
        </div>
        <span className="inline-flex w-fit rounded-full border border-rose-400/25 bg-rose-400/10 px-3 py-1 text-xs font-medium text-rose-100">
          Exact batch & bucket
        </span>
      </div>

      <div className="form-grid mt-6">
        <label className="field-label">
          Referensi pemusnahan
          <input
            maxLength={200}
            onChange={(event) => setSourceRef(event.target.value)}
            placeholder="DSP-2026-001"
            required
            value={sourceRef}
          />
        </label>

        <label className="field-label">
          Waktu pemusnahan
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
              selectReason(
                event.target.value as StockDisposalReasonCode,
              )
            }
            required
            value={reasonCode}
          >
            {STOCK_DISPOSAL_REASON_CODES.map((reason) => (
              <option key={reason} value={reason}>
                {reasonLabel(reason)}
              </option>
            ))}
          </select>
        </label>

        <label className="field-label">
          Referensi bukti / berita acara
          <input
            maxLength={200}
            onChange={(event) => setReferenceText(event.target.value)}
            placeholder="BA-Pemusnahan-2026-001 / foto / persetujuan"
            required
            value={referenceText}
          />
        </label>

        <label className="field-label sm:col-span-2">
          Catatan pemusnahan
          <textarea
            maxLength={2000}
            onChange={(event) => setNote(event.target.value)}
            placeholder="Jelaskan kondisi fisik, alasan pemusnahan, dan bukti yang tersedia."
            required
            rows={4}
            value={note}
          />
        </label>
      </div>

      <div className="mt-7 border-t border-white/10 pt-6">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p className="section-kicker">Batch fisik</p>
            <h3 className="mt-1 text-lg font-semibold text-white">
              Quantity per batch dan bucket.
            </h3>
          </div>
          <button
            className="rounded-xl border border-white/10 px-3 py-2 text-sm font-medium text-slate-200 transition hover:border-sky-400/30 hover:text-white"
            onClick={addLine}
            type="button"
          >
            Tambah batch
          </button>
        </div>

        <div className="mt-4 space-y-3">
          {lines.map((line, index) => {
            const candidate = candidates.find(
              (item) => item.batchId === line.batchId,
            );
            const buckets = availableBuckets(candidate, reasonCode);
            const selectedQuantity = bucketQuantity(
              candidate,
              line.sourceBucketCode,
            );

            return (
              <div
                className="grid gap-3 rounded-2xl border border-white/10 bg-slate-950/35 p-4 lg:grid-cols-[minmax(0,1.7fr)_minmax(10rem,0.7fr)_9rem_auto]"
                key={line.sourceLineRef}
              >
                <label className="field-label">
                  Batch {index + 1}
                  <select
                    aria-label={`Batch baris ${index + 1}`}
                    onChange={(event) =>
                      selectBatch(line.sourceLineRef, event.target.value)
                    }
                    required
                    value={line.batchId}
                  >
                    <option disabled value="">
                      Pilih batch
                    </option>
                    {eligibleCandidates.map((item) => (
                      <option key={item.batchId} value={item.batchId}>
                        {item.productSku} â€¢ {item.batchCode} â€¢ exp{" "}
                        {item.expiryDate} â€¢ S {item.sellableQty} / Q{" "}
                        {item.quarantineQty} / D {item.damagedQty}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field-label">
                  Bucket sumber
                  <select
                    aria-label={`Bucket baris ${index + 1}`}
                    disabled={!candidate || reasonCode === "DAMAGED_DISPOSAL"}
                    onChange={(event) =>
                      updateLine(
                        line.sourceLineRef,
                        "sourceBucketCode",
                        event.target.value,
                      )
                    }
                    required
                    value={line.sourceBucketCode}
                  >
                    {buckets.length ? (
                      buckets.map((bucket) => (
                        <option key={bucket} value={bucket}>
                          {bucketLabel(bucket)} â€¢{" "}
                          {bucketQuantity(candidate, bucket)} unit
                        </option>
                      ))
                    ) : (
                      <option value={line.sourceBucketCode}>
                        {bucketLabel(line.sourceBucketCode)}
                      </option>
                    )}
                  </select>
                </label>

                <label className="field-label">
                  Quantity
                  <input
                    aria-label={`Quantity baris ${index + 1}`}
                    max={selectedQuantity || undefined}
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

                <p className="text-xs leading-5 text-slate-600 lg:col-span-4">
                  Referensi baris: {line.sourceLineRef}
                  {candidate
                    ? ` â€¢ ${candidate.productName} â€¢ status ${candidate.batchStatusCode}` +
                      `${candidate.blockReason ? ` â€¢ ${candidate.blockReason}` : ""}`
                    : ""}
                </p>
              </div>
            );
          })}
        </div>

        {!eligibleCandidates.length ? (
          <div className="mt-4 rounded-2xl border border-amber-400/20 bg-amber-400/[0.055] p-4 text-sm leading-6 text-amber-100">
            Tidak ada batch yang memenuhi alasan ini. Barang rusak hanya membaca
            saldo ledger-backed DAMAGED. Barang kedaluwarsa hanya menerima batch
            yang tanggal kedaluwarsanya sudah lewat.
          </div>
        ) : null}
      </div>

      <div className="mt-6 rounded-2xl border border-sky-400/20 bg-sky-400/[0.055] p-4 text-sm leading-6 text-sky-100">
        Preview tidak menulis dokumen, ledger, atau projection. Setelah diposting,
        dokumen pemusnahan tidak dapat diedit atau dihapus. Kesalahan diperbaiki
        melalui Koreksi Entri.
      </div>

      <button className="primary-button mt-6" type="submit">
        Tinjau dampak pemusnahan
      </button>
    </form>
  );
}