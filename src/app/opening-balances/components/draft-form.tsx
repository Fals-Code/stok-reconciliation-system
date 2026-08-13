"use client";

import { useMemo, useState } from "react";

import {
  emptyOpeningBalanceLine,
  type OpeningBalanceBucketCode,
  type OpeningBalanceDraftLine,
} from "@/app/opening-balances/draft";
import {
  Button,
} from "@/components/ui";
import type {
  BatchInventory,
  ProductBatchMasterRow,
} from "@/lib/supabase-rest";

type DraftFormProps = {
  action: (formData: FormData) => void | Promise<void>;
  cutoverId: string;
  rowVersion: number;
  cutoverAt: string;
  sourceEstimateRef: string;
  note: string;
  batches: BatchInventory[];
  eligibleBatches: ProductBatchMasterRow[];
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

function bucketLabel(code: OpeningBalanceBucketCode) {
  if (code === "SELLABLE") return "Barang baik";
  if (code === "QUARANTINE") return "Karantina";
  return "Rusak";
}

export default function OpeningBalanceDraftForm({
  action,
  cutoverId,
  rowVersion,
  cutoverAt,
  sourceEstimateRef,
  note,
  batches,
  eligibleBatches,
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

  const eligibleBatchOptions = useMemo(
    () =>
      eligibleBatches.map((batch) => ({
        ...batch,
        sku: batch.product_sku,
      })),
    [eligibleBatches],
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
    <form action={action}>
      <input name="cutoverId" type="hidden" value={cutoverId} />
      <input name="rowVersion" type="hidden" value={rowVersion} />
      <input
        name="linesJson"
        type="hidden"
        value={JSON.stringify(lines)}
      />

      <p className="text-xs font-semibold uppercase tracking-wide text-ui-primary">
        Langkah 1 dari 3
      </p>
      <h3 className="mt-1 text-base font-semibold text-ui-text">
        Isi stok awal
      </h3>
      <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
        Pilih batch yang sudah terdaftar. Sistem tidak membuat identitas batch
        baru dari tebakan operator.
      </p>

      <div className="mt-5 grid gap-4 sm:grid-cols-2">
        <label>
          <span className="text-sm font-medium text-ui-text">
            Waktu mulai
          </span>
          <input
            className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
            defaultValue={dateTimeLocal(cutoverAt)}
            name="cutoverAt"
            required
            type="datetime-local"
          />
        </label>

        <label>
          <span className="text-sm font-medium text-ui-text">
            Referensi estimasi atau bukti
          </span>
          <input
            className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
            defaultValue={sourceEstimateRef}
            maxLength={200}
            name="sourceEstimateRef"
            required
          />
        </label>

        <label className="sm:col-span-2">
          <span className="text-sm font-medium text-ui-text">
            Catatan
          </span>
          <textarea
            className="mt-2 min-h-24 w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 py-2 text-sm text-ui-text"
            defaultValue={note}
            maxLength={2000}
            name="note"
            required
          />
        </label>
      </div>

      <div className="mt-6 flex flex-col gap-3 border-t border-ui-border pt-5 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h4 className="text-sm font-semibold text-ui-text">
            Barang dan jumlah
          </h4>
          <p className="mt-1 text-sm text-ui-text-muted">
            Tambahkan satu baris untuk setiap kombinasi batch dan kondisi stok.
          </p>
        </div>

        <Button onClick={addLine} type="button" variant="secondary">
          Tambah Baris
        </Button>
      </div>

      <div className="mt-4 divide-y divide-ui-border border-y border-ui-border">
        {lines.map((line, index) => {
          const selectedKey =
            line.productId && line.batchId
              ? `${line.productId}:${line.batchId}`
              : "";

          const selectedBatch = batchByKey.get(selectedKey);
          const unidentified =
            selectedBatch?.batch_kind_code === "UNIDENTIFIED_RETURN";

          return (
            <article className="py-5" key={`${line.sourceLineRef}-${index}`}>
              <div className="flex items-center justify-between gap-3">
                <p className="text-sm font-semibold text-ui-text">
                  Baris {index + 1}
                </p>

                <button
                  className="text-sm font-semibold text-ui-danger disabled:cursor-not-allowed disabled:opacity-40"
                  disabled={lines.length === 1}
                  onClick={() => removeLine(index)}
                  type="button"
                >
                  Hapus
                </button>
              </div>

              <div className="mt-4 grid gap-4 sm:grid-cols-2">
                <label className="sm:col-span-2">
                  <span className="text-sm font-medium text-ui-text">
                    Produk dan batch
                  </span>
                  <select
                    className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
                    onChange={(event) =>
                      selectBatch(index, event.target.value)
                    }
                    required
                    value={selectedKey}
                  >
                    <option value="">Pilih batch</option>
                    {eligibleBatchOptions.map((batch) => (
                      <option
                        key={batch.batch_id}
                        value={`${batch.product_id}:${batch.batch_id}`}
                      >
                        {batch.sku} {"·"} {batch.batch_code} {"·"} kedaluwarsa{" "}
                        {batch.expiry_date}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  <span className="text-sm font-medium text-ui-text">
                    Kondisi stok
                  </span>
                  <select
                    className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
                    disabled={unidentified}
                    onChange={(event) =>
                      updateLine(index, {
                        bucketCode: event.target
                          .value as OpeningBalanceBucketCode,
                      })
                    }
                    value={line.bucketCode}
                  >
                    {(["SELLABLE", "QUARANTINE", "DAMAGED"] as const).map(
                      (code) => (
                        <option key={code} value={code}>
                          {bucketLabel(code)}
                        </option>
                      ),
                    )}
                  </select>
                </label>

                <label>
                  <span className="text-sm font-medium text-ui-text">
                    Jumlah
                  </span>
                  <input
                    className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
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

                <label className="sm:col-span-2">
                  <span className="text-sm font-medium text-ui-text">
                    Referensi baris sumber
                  </span>
                  <input
                    className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
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

                {!line.batchIdentityVerified ? (
                  <div className="sm:col-span-2">
                    <p className="text-sm font-medium text-ui-text">
                      Batch belum terverifikasi
                    </p>
                    <p className="mt-1 text-sm leading-6 text-ui-text-muted">
                      Batch ini otomatis masuk Karantina sampai identitasnya
                      dapat dibuktikan.
                    </p>

                    <label className="mt-3 block">
                      <span className="text-sm font-medium text-ui-text">
                        Referensi pengecualian
                      </span>
                      <input
                        className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
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
                  </div>
                ) : null}
              </div>
            </article>
          );
        })}
      </div>

      <Button className="mt-5" type="submit" variant="secondary">
        Simpan Draft
      </Button>
    </form>
  );
}