"use client";

import { useMemo, useState } from "react";

import { previewMarketplaceCancellationAction } from "@/app/marketplace/cancellations/actions";
import {
  serializeMarketplaceCancellationDraft,
  type MarketplaceCancellationDraft,
  type MarketplaceCancellationPhaseCode,
} from "@/app/marketplace/cancellations/draft";
import type { MarketplaceCancellationCandidate } from "@/lib/supabase-rest";

type CancellationOption = {
  key: string;
  candidate: MarketplaceCancellationCandidate;
  phaseCode: MarketplaceCancellationPhaseCode;
  maximumQuantity: number;
};

function phaseLabel(phaseCode: MarketplaceCancellationPhaseCode) {
  return phaseCode === "PRE_SHIPMENT"
    ? "Sebelum shipment · lepas reservasi"
    : "Sesudah shipment · reversal stok";
}

function buildOptions(
  candidates: MarketplaceCancellationCandidate[],
): CancellationOption[] {
  return candidates.flatMap((candidate) => {
    const options: CancellationOption[] = [];
    const preQuantity = Number(candidate.open_reserved_qty);
    const postQuantity = Number(candidate.remaining_post_cancellable_qty);

    if (preQuantity > 0) {
      options.push({
        key: `${candidate.order_item_id}:PRE_SHIPMENT`,
        candidate,
        phaseCode: "PRE_SHIPMENT",
        maximumQuantity: preQuantity,
      });
    }

    if (postQuantity > 0) {
      options.push({
        key: `${candidate.order_item_id}:POST_SHIPMENT`,
        candidate,
        phaseCode: "POST_SHIPMENT",
        maximumQuantity: postQuantity,
      });
    }

    return options;
  });
}

function initialOptionKey(
  options: CancellationOption[],
  initialDraft: MarketplaceCancellationDraft,
) {
  const initialLine = initialDraft.lines[0];

  if (initialLine) {
    const matching = options.find(
      (option) =>
        option.candidate.external_order_ref === initialDraft.orderRef &&
        option.candidate.external_item_ref === initialLine.orderItemRef &&
        option.candidate.product_id === initialLine.productId &&
        option.phaseCode === initialLine.phaseCode,
    );

    if (matching) {
      return matching.key;
    }
  }

  return options[0]?.key ?? "";
}

export default function MarketplaceCancellationDraftForm({
  candidates,
  initialDraft,
}: {
  candidates: MarketplaceCancellationCandidate[];
  initialDraft: MarketplaceCancellationDraft;
}) {
  const options = useMemo(() => buildOptions(candidates), [candidates]);
  const [selectedKey, setSelectedKey] = useState(() =>
    initialOptionKey(options, initialDraft),
  );
  const [eventRef, setEventRef] = useState(initialDraft.eventRef);
  const [occurredAt, setOccurredAt] = useState(initialDraft.occurredAt);
  const [sourceStatus, setSourceStatus] = useState(
    initialDraft.sourceStatus || "CANCELLED",
  );
  const [quantity, setQuantity] = useState(() =>
    String(initialDraft.lines[0]?.quantity ?? 1),
  );
  const [note, setNote] = useState(initialDraft.note ?? "");

  const selectedOption =
    options.find((option) => option.key === selectedKey) ?? options[0] ?? null;
  const selectedCandidate = selectedOption?.candidate ?? null;
  const requiresAuditNote =
    selectedOption?.phaseCode === "POST_SHIPMENT";

  const draft = useMemo(
    () =>
      serializeMarketplaceCancellationDraft({
        channelCode: selectedCandidate?.channel_code ?? "SHOPEE",
        eventRef,
        orderRef: selectedCandidate?.external_order_ref ?? "",
        occurredAt,
        sourceStatus,
        lines: selectedCandidate && selectedOption
          ? [
              {
                productId: selectedCandidate.product_id,
                orderItemRef: selectedCandidate.external_item_ref,
                phaseCode: selectedOption.phaseCode,
                quantity: Number(quantity),
                sourceLineRef: "UI-1",
              },
            ]
          : [],
        note: note.trim() || null,
      }),
    [
      eventRef,
      note,
      occurredAt,
      quantity,
      selectedCandidate,
      selectedOption,
      sourceStatus,
    ],
  );

  return (
    <form
      action={previewMarketplaceCancellationAction}
      className="panel-card"
      id="cancellation-draft"
    >
      <input name="draft" type="hidden" value={draft} />

      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="section-kicker">Draft pembatalan</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">
            Pilih item dan fase fisiknya.
          </h2>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Fase harus dinyatakan secara eksplisit. Sistem tidak menebak apakah
            quantity masih berupa reservasi atau sudah keluar melalui shipment.
          </p>
        </div>
        <span className="inline-flex w-fit rounded-full border border-sky-400/25 bg-sky-400/10 px-3 py-1 text-xs font-medium text-sky-100">
          Tanpa pemilihan batch manual
        </span>
      </div>

      {options.length === 0 ? (
        <div className="mt-6 rounded-2xl border border-amber-400/20 bg-amber-400/[0.055] p-5 text-sm leading-6 text-amber-100">
          Tidak ada item marketplace yang masih dapat dibatalkan. Buat reservasi
          atau shipment yang valid terlebih dahulu, lalu muat ulang halaman.
        </div>
      ) : (
        <>
          <div className="form-grid mt-6">
            <label className="field-label sm:col-span-2">
              Item dan fase pembatalan
              <select
                aria-label="Item dan fase pembatalan"
                onChange={(event) => {
                  setSelectedKey(event.target.value);
                  setQuantity("1");
                }}
                required
                value={selectedOption?.key ?? ""}
              >
                {options.map((option) => (
                  <option key={option.key} value={option.key}>
                    {option.candidate.channel_code} ·{" "}
                    {option.candidate.external_order_ref} ·{" "}
                    {option.candidate.external_item_ref} ·{" "}
                    {option.candidate.product_sku_snapshot} ·{" "}
                    {phaseLabel(option.phaseCode)} · maks{" "}
                    {option.maximumQuantity}
                  </option>
                ))}
              </select>
            </label>

            <label className="field-label">
              Referensi event pembatalan
              <input
                maxLength={200}
                onChange={(event) => setEventRef(event.target.value)}
                placeholder="SHP-EVT-CANCEL-1001"
                required
                value={eventRef}
              />
            </label>

            <label className="field-label">
              Waktu pembatalan
              <input
                onChange={(event) => setOccurredAt(event.target.value)}
                required
                type="datetime-local"
                value={occurredAt}
              />
            </label>

            <label className="field-label">
              Status sumber marketplace
              <input
                maxLength={100}
                onChange={(event) => setSourceStatus(event.target.value)}
                placeholder="CANCELLED"
                required
                value={sourceStatus}
              />
            </label>

            <label className="field-label">
              Quantity dibatalkan
              <input
                aria-label="Quantity dibatalkan"
                max={selectedOption?.maximumQuantity}
                min="1"
                onChange={(event) => setQuantity(event.target.value)}
                required
                step="1"
                type="number"
                value={quantity}
              />
            </label>

            <label className="field-label sm:col-span-2">
              Alasan audit
              <textarea
                maxLength={2000}
                onChange={(event) => setNote(event.target.value)}
                placeholder={
                  requiresAuditNote
                    ? "Wajib untuk pembatalan setelah shipment."
                    : "Opsional untuk pelepasan reservasi sebelum shipment."
                }
                required={requiresAuditNote}
                rows={3}
                value={note}
              />
            </label>
          </div>

          {selectedCandidate && selectedOption ? (
            <dl className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {[
                ["Order", selectedCandidate.external_order_ref],
                ["Item", selectedCandidate.external_item_ref],
                ["SKU", selectedCandidate.product_sku_snapshot],
                ["Fase", phaseLabel(selectedOption.phaseCode)],
                [
                  "Reservasi terbuka",
                  String(selectedCandidate.open_reserved_qty),
                ],
                [
                  "Shipped",
                  String(selectedCandidate.shipped_qty),
                ],
                [
                  "Sudah dibatalkan pre",
                  String(selectedCandidate.pre_shipment_cancelled_qty),
                ],
                [
                  "Sudah dibalik post",
                  String(selectedCandidate.post_shipment_cancelled_qty),
                ],
                [
                  "Expected return",
                  String(selectedCandidate.return_expected_qty),
                ],
                [
                  "Sisa post cancellable",
                  String(selectedCandidate.remaining_post_cancellable_qty),
                ],
                [
                  "Maksimum fase terpilih",
                  String(selectedOption.maximumQuantity),
                ],
                [
                  "Status cancellation",
                  selectedCandidate.cancellation_status_code,
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
          ) : null}

          <div className="mt-6 rounded-2xl border border-sky-400/20 bg-sky-400/[0.055] p-4 text-sm leading-6 text-sky-100">
            Preview dihitung database dan tidak menulis event, reservation,
            stock transaction, ledger, projection, atau idempotency command.
          </div>

          <button className="primary-button mt-6" type="submit">
            Tinjau dampak pembatalan
          </button>
        </>
      )}
    </form>
  );
}
