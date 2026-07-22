"use client";

import { useMemo, useState } from "react";

import {
  emptyOpeningBalanceLine,
  type OpeningBalanceBucketCode,
  type OpeningBalanceDraftLine,
} from "@/app/opening-balances/draft";
import type { BatchInventory } from "@/lib/supabase-rest";

type DraftFormProps = {
  action: (formData: FormData) => void | Promise<void>;
  cutoverId: string;
  rowVersion: number;
  cutoverAt: string;
  sourceEstimateRef: string;
  note: string;
  batches: BatchInventory[];
  initialLines: OpeningBalanceDraftLine[];
};

function dateTimeLocal(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) return "";

  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const fields = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );

  return `${fields.year}-${fields.month}-${fields.day}T${fields.hour}:${fields.minute}`;
}

function nextSourceRef(lines: OpeningBalanceDraftLine[]) {
  const used = new Set(lines.map((line) => line.sourceLineRef));
  let index = lines.length + 1;

  while (used.has(`UI-${index}`)) index += 1;

  return `UI-${index}`;
}

export default function OpeningBalanceDraftForm({
  action,
  cutoverId,
  rowVersion,
  cutoverAt,
  sourceEstimateRef,
  note,
  batches,
  initialLines,
}: DraftFormProps) {
  const [lines, setLines] = useState<OpeningBalanceDraftLine[]>(
    initialLines.length ? initialLines : [emptyOpeningBalanceLine()],
  );

  const batchByKey = useMemo(
    () =>
      new Map(
        batches.map((batch) => [
          `${batch.product_id}:${batch.batch_id}`,
          batch,
        ]),
      ),
    [batches],
  );

  function updateLine(
    index: number,
    patch: Partial<OpeningBalanceDraftLine>,
  ) {
    setLines((current) =>
      current.map((line, candidateIndex) =>
        candidateIndex === index ? { ...line, ...patch } : line,
      ),
    );
  }

  function selectBatch(index: number, value: string) {
    const [productId = "", batchId = ""] = value.split(":");
    const selected = batchByKey.get(value);
    const unidentified =
      selected?.batch_kind_code === "UNIDENTIFIED_RETURN";

    updateLine(index, {
      productId,
      batchId,
      batchIdentityVerified: !unidentified,
      bucketCode: unidentified ? "QUARANTINE" : lines[index].bucketCode,
      exceptionReference: unidentified
        ? lines[index].exceptionReference
        : null,
    });
  }

  function addLine() {
    setLines((current) => [
      ...current,
      {
        ...emptyOpeningBalanceLine(current.length),
        sourceLineRef: nextSourceRef(current),
      },
    ]);
  }

  function removeLine(index: number) {
    setLines((current) => {
      if (current.length === 1) return current;
      return current.filter((_, candidateIndex) => candidateIndex !== index);
    });
  }

  return (
    <form action={action} className="panel-card">
      <input name="cutoverId" type="hidden" value={cutoverId} />
      <input name="rowVersion" type="hidden" value={rowVersion} />
      <input
        name="linesJson"
        type="hidden"
        value={JSON.stringify(lines)}
      />

      <div className="grid gap-4 lg:grid-cols-3">
        <label className="space-y-2">
          <span className="text-sm font-medium text-slate-200">
            Waktu cutover
          </span>
          <input
            className="w-full rounded-xl border border-white/10 bg-slate-950/60 px-3 py-2.5 text-sm text-white"
            defaultValue={dateTimeLocal(cutoverAt)}
            name="cutoverAt"
            required
            type="datetime-local"
          />
        </label>

        <label className="space-y-2 lg:col-span-2">
          <span className="text-sm font-medium text-slate-200">
            Referensi estimasi / bukti sumber
          </span>
          <input
            className="w-full rounded-xl border border-white/10 bg-slate-950/60 px-3 py-2.5 text-sm text-white"
            defaultValue={sourceEstimateRef}
            maxLength={200}
            name="sourceEstimateRef"
            required
          />
        </label>

        <label className="space-y-2 lg:col-span-3">
          <span className="text-sm font-medium text-slate-200">
            Catatan dasar saldo awal
          </span>
          <textarea
            className="min-h-24 w-full rounded-xl border border-white/10 bg-slate-950/60 px-3 py-2.5 text-sm text-white"
            defaultValue={note}
            maxLength={2000}
            name="note"
            required
          />
        </label>
      </div>

      <div className="mt-6 flex flex-col gap-3 border-t border-white/10 pt-6 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p className="section-kicker">Baris stok fisik</p>
          <p className="mt-2 text-sm text-slate-400">
            Pilih batch yang sudah ada. Sistem tidak membuat identitas batch
            baru dari tebakan operator.
          </p>
        </div>
        <button
          className="rounded-xl border border-sky-400/20 bg-sky-400/[0.06] px-4 py-2 text-sm font-medium text-sky-100 transition hover:bg-sky-400/10"
          onClick={addLine}
          type="button"
        >
          Tambah baris
        </button>
      </div>

      <div className="mt-5 space-y-4">
        {lines.map((line, index) => {
          const selectedKey =
            line.productId && line.batchId
              ? `${line.productId}:${line.batchId}`
              : "";
          const selectedBatch = batchByKey.get(selectedKey);
          const unidentified =
            selectedBatch?.batch_kind_code === "UNIDENTIFIED_RETURN";

          return (
            <article
              className="rounded-2xl border border-white/10 bg-slate-950/35 p-4"
              key={`${line.sourceLineRef}-${index}`}
            >
              <div className="flex items-center justify-between gap-3">
                <p className="font-medium text-white">
                  Baris {index + 1}
                </p>
                <button
                  className="text-xs text-rose-300 disabled:cursor-not-allowed disabled:text-slate-700"
                  disabled={lines.length === 1}
                  onClick={() => removeLine(index)}
                  type="button"
                >
                  Hapus
                </button>
              </div>

              <div className="mt-4 grid gap-4 lg:grid-cols-12">
                <label className="space-y-2 lg:col-span-5">
                  <span className="text-xs text-slate-400">
                    Produk dan batch
                  </span>
                  <select
                    className="w-full rounded-xl border border-white/10 bg-slate-950/70 px-3 py-2.5 text-sm text-white"
                    onChange={(event) =>
                      selectBatch(index, event.target.value)
                    }
                    required
                    value={selectedKey}
                  >
                    <option value="">Pilih batch</option>
                    {batches.map((batch) => (
                      <option
                        key={batch.batch_id}
                        value={`${batch.product_id}:${batch.batch_id}`}
                      >
                        {batch.sku} · {batch.batch_code} · exp{" "}
                        {batch.expiry_date} · {batch.batch_kind_code}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="space-y-2 lg:col-span-2">
                  <span className="text-xs text-slate-400">Bucket</span>
                  <select
                    className="w-full rounded-xl border border-white/10 bg-slate-950/70 px-3 py-2.5 text-sm text-white"
                    onChange={(event) =>
                      updateLine(index, {
                        bucketCode: event.target
                          .value as OpeningBalanceBucketCode,
                      })
                    }
                    value={line.bucketCode}
                  >
                    <option value="SELLABLE">Sellable</option>
                    <option value="QUARANTINE">Quarantine</option>
                    <option value="DAMAGED">Damaged</option>
                  </select>
                </label>

                <label className="space-y-2 lg:col-span-2">
                  <span className="text-xs text-slate-400">Quantity</span>
                  <input
                    className="w-full rounded-xl border border-white/10 bg-slate-950/70 px-3 py-2.5 text-sm text-white"
                    max={999999999}
                    min={0}
                    onChange={(event) =>
                      updateLine(index, {
                        quantity: Number(event.target.value),
                      })
                    }
                    required
                    type="number"
                    value={line.quantity}
                  />
                </label>

                <label className="space-y-2 lg:col-span-3">
                  <span className="text-xs text-slate-400">
                    Referensi baris sumber
                  </span>
                  <input
                    className="w-full rounded-xl border border-white/10 bg-slate-950/70 px-3 py-2.5 text-sm text-white"
                    maxLength={100}
                    onChange={(event) =>
                      updateLine(index, {
                        sourceLineRef: event.target.value,
                      })
                    }
                    required
                    value={line.sourceLineRef}
                  />
                </label>

                <label className="flex items-start gap-3 rounded-xl border border-white/10 bg-white/[0.025] p-3 lg:col-span-4">
                  <input
                    checked={line.batchIdentityVerified}
                    className="mt-1"
                    disabled={unidentified}
                    onChange={(event) =>
                      updateLine(index, {
                        batchIdentityVerified: event.target.checked,
                        exceptionReference: event.target.checked
                          ? null
                          : line.exceptionReference,
                      })
                    }
                    type="checkbox"
                  />
                  <span>
                    <span className="block text-sm text-slate-200">
                      Identitas batch terverifikasi
                    </span>
                    <span className="mt-1 block text-xs text-slate-500">
                      Batch tak teridentifikasi wajib quarantine.
                    </span>
                  </span>
                </label>

                {!line.batchIdentityVerified ? (
                  <label className="space-y-2 lg:col-span-8">
                    <span className="text-xs text-amber-200">
                      Referensi pengecualian batch
                    </span>
                    <input
                      className="w-full rounded-xl border border-amber-400/20 bg-amber-400/[0.04] px-3 py-2.5 text-sm text-white"
                      maxLength={200}
                      onChange={(event) =>
                        updateLine(index, {
                          exceptionReference:
                            event.target.value.trim() || null,
                        })
                      }
                      required
                      value={line.exceptionReference ?? ""}
                    />
                  </label>
                ) : null}
              </div>
            </article>
          );
        })}
      </div>

      <button
        className="mt-6 rounded-xl bg-emerald-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-emerald-200"
        type="submit"
      >
        Simpan draft saldo awal
      </button>
    </form>
  );
}
