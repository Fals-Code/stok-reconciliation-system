"use client";

import {
  useMemo,
  useState,
} from "react";

import {
  postMultiLineReceiptAction,
} from "@/app/receipts/actions";
import {
  Alert,
  Input,
  Select,
  StatusBadge,
  Textarea,
} from "@/components/ui";
import type {
  ProductBatchMasterRow,
  ProductMasterRow,
} from "@/lib/supabase-rest";

type ReceiptLineState = {
  id: number;
  productId: string;
  batchMode: "existing" | "new";
  batchId: string;
  batchCode: string;
  expiryDate: string;
  manufacturedDate: string;
  quantity: string;
};

const numberFormatter =
  new Intl.NumberFormat("id-ID");

function nextLine(id: number, defaultProductId = ""): ReceiptLineState {
  return {
    id,
    productId: defaultProductId,
    batchMode: "new",
    batchId: "",
    batchCode: "",
    expiryDate: "",
    manufacturedDate: "",
    quantity: "1",
  };
}

function totalQuantity(
  lines: ReceiptLineState[],
) {
  return lines.reduce(
    (sum, line) => {
      const value =
        Number(line.quantity);

      return Number.isSafeInteger(value) &&
        value > 0
        ? sum + value
        : sum;
    },
    0,
  );
}

function localDateTimeValue() {
  const now = new Date();
  const jakarta = new Date(
    now.toLocaleString(
      "en-US",
      {
        timeZone:
          "Asia/Jakarta",
      },
    ),
  );

  const offset =
    jakarta.getTimezoneOffset();
  const local = new Date(
    jakarta.getTime() -
      offset * 60_000,
  );

  return local
    .toISOString()
    .slice(0, 16);
}

function formatExpiry(
  value: string,
) {
  if (!value) return "-";
  const date = new Date(
    `${value}T00:00:00`,
  );

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat(
    "id-ID",
    {
      day: "2-digit",
      month: "short",
      year: "numeric",
      timeZone: "Asia/Jakarta",
    },
  ).format(date);
}

export function ReceiptForm({
  products,
  batches,
}: {
  products: ProductMasterRow[];
  batches: ProductBatchMasterRow[];
}) {
  const [sourceRef, setSourceRef] = useState("");
  const [occurredAt, setOccurredAt] = useState(localDateTimeValue);
  const [note, setNote] = useState("");
  const [step, setStep] = useState<"edit" | "review">("edit");

  const [lines, setLines] = useState<ReceiptLineState[]>(() => [
    nextLine(1, products[0]?.product_id ?? ""),
  ]);

  const productMap = useMemo(
    () => new Map(products.map((p) => [p.product_id, p])),
    [products],
  );

  const batchMap = useMemo(
    () => new Map(batches.map((b) => [b.batch_id, b])),
    [batches],
  );

  // Group existing batches by product_id
  const batchesByProduct = useMemo(() => {
    const map = new Map<string, ProductBatchMasterRow[]>();
    for (const batch of batches) {
      const list = map.get(batch.product_id) ?? [];
      list.push(batch);
      map.set(batch.product_id, list);
    }
    return map;
  }, [batches]);

  const total = totalQuantity(lines);

  // Line validation
  const validatedLines = useMemo(() => {
    const seenIdentities = new Set<string>();

    return lines.map((line) => {
      const product = productMap.get(line.productId);
      const qty = Number(line.quantity);
      const isValidQty = Number.isSafeInteger(qty) && qty > 0;

      let isValidBatch = false;
      let batchDisplayCode = "";
      let batchDisplayExpiry = "";
      let identityKey = "";
      let dateRangeError = false;

      if (line.batchMode === "existing") {
        const existingBatch = batchMap.get(line.batchId);
        if (existingBatch && existingBatch.product_id === line.productId) {
          isValidBatch = true;
          batchDisplayCode = existingBatch.batch_code;
          batchDisplayExpiry = existingBatch.expiry_date;
          identityKey = `${line.productId}:id:${line.batchId}`;
        }
      } else {
        const code = line.batchCode.trim();
        const exp = line.expiryDate.trim();
        const mfg = line.manufacturedDate.trim();

        if (code && exp) {
          if (mfg && mfg > exp) {
            dateRangeError = true;
          } else {
            isValidBatch = true;
            batchDisplayCode = code;
            batchDisplayExpiry = exp;
            identityKey = `${line.productId}:code:${code.toUpperCase()}`;
          }
        }
      }

      const isDuplicate = Boolean(identityKey && seenIdentities.has(identityKey));
      if (identityKey) {
        seenIdentities.add(identityKey);
      }

      const isValid = Boolean(product) && isValidQty && isValidBatch && !isDuplicate && !dateRangeError;

      return {
        line,
        product,
        qty,
        isValid,
        isDuplicate,
        dateRangeError,
        batchDisplayCode,
        batchDisplayExpiry,
      };
    });
  }, [lines, productMap, batchMap]);

  const hasIncompleteLine = validatedLines.some((v) => !v.isValid);
  const isHeaderValid = sourceRef.trim().length > 0 && occurredAt.length > 0;
  const canSubmit = isHeaderValid && lines.length > 0 && !hasIncompleteLine && total > 0;

  const serializedLines = JSON.stringify(
    validatedLines
      .filter((v) => v.isValid)
      .map(({ line, qty }) => ({
        productId: line.productId,
        ...(line.batchMode === "existing"
          ? { batchId: line.batchId }
          : {
              batchCode: line.batchCode.trim(),
              expiryDate: line.expiryDate.trim(),
              manufacturedDate: line.manufacturedDate.trim() || null,
            }),
        quantity: qty,
      })),
  );

  function updateLine(id: number, patch: Partial<ReceiptLineState>) {
    setLines((current) =>
      current.map((line) => {
        if (line.id !== id) return line;

        const updated = { ...line, ...patch };

        // If product changed, update default batch mode and selection
        if (patch.productId && patch.productId !== line.productId) {
          const availBatches = batchesByProduct.get(patch.productId) ?? [];
          if (availBatches.length > 0) {
            updated.batchMode = "existing";
            updated.batchId = availBatches[0].batch_id;
          } else {
            updated.batchMode = "new";
            updated.batchId = "";
          }
        }

        return updated;
      }),
    );
  }

  function addLine() {
    setLines((current) => [
      ...current,
      nextLine(
        Math.max(0, ...current.map((l) => l.id)) + 1,
        products[0]?.product_id ?? "",
      ),
    ]);
  }

  function removeLine(id: number) {
    setLines((current) =>
      current.length === 1
        ? current
        : current.filter((l) => l.id !== id),
    );
  }

  return (
    <form action={postMultiLineReceiptAction} className="mt-7">
      <input name="receiptLines" type="hidden" value={serializedLines} />
      <input name="sourceRef" type="hidden" value={sourceRef} />
      <input name="occurredAt" type="hidden" value={occurredAt} />
      <input name="note" type="hidden" value={note} />

      <section
        aria-labelledby="receipt-data-heading"
        className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 shadow-[var(--ui-shadow-sm)] sm:p-6"
      >
        <div className="border-b border-ui-border pb-5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h2
                className="text-lg font-semibold text-ui-text"
                id="receipt-data-heading"
              >
                {step === "edit" ? "Isi data penerimaan" : "Periksa sebelum simpan"}
              </h2>
              <p className="mt-1 text-sm leading-6 text-ui-text-muted">
                {step === "edit"
                  ? "Catat referensi penerimaan dan barang yang benar-benar sudah diterima gudang."
                  : "Periksa kembali ringkasan penerimaan sebelum menyimpan ke stok."}
              </p>
            </div>
            {step === "review" ? (
              <StatusBadge tone="warning">Status: Menunggu Konfirmasi</StatusBadge>
            ) : null}
          </div>
        </div>

        {step === "edit" ? (
          /* STEP 1: FORM INPUT */
          <div>
            <div className="mt-5 grid gap-5 sm:grid-cols-2">
              <label className="grid gap-2 text-sm font-semibold text-ui-text">
                Referensi penerimaan *
                <Input
                  autoComplete="off"
                  name="sourceRefInput"
                  onChange={(e) => setSourceRef(e.target.value)}
                  placeholder="Contoh: DO-MAKLON-090826"
                  required
                  value={sourceRef}
                />
                <span className="text-xs font-normal leading-5 text-ui-text-muted">
                  Gunakan nomor yang dapat dicocokkan kembali dengan dokumen penerimaan.
                </span>
              </label>

              <label className="grid gap-2 text-sm font-semibold text-ui-text">
                Waktu diterima *
                <Input
                  name="occurredAtInput"
                  onChange={(e) => setOccurredAt(e.target.value)}
                  required
                  type="datetime-local"
                  value={occurredAt}
                />
              </label>

              <label className="grid gap-2 text-sm font-semibold text-ui-text sm:col-span-2">
                Catatan
                <Textarea
                  name="noteInput"
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="Opsional. Contoh: diterima dari maklon sesuai surat jalan."
                  rows={2}
                  value={note}
                />
              </label>
            </div>

            <div className="mt-7 border-t border-ui-border pt-6">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
                <div>
                  <h3 className="text-base font-semibold text-ui-text">
                    Barang diterima
                  </h3>
                  <p className="mt-1 text-sm leading-6 text-ui-text-muted">
                    Pilih produk lalu pilih batch existing atau buat batch baru untuk setiap barang.
                  </p>
                </div>

                <button
                  className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text hover:bg-ui-surface-subtle"
                  onClick={addLine}
                  type="button"
                >
                  + Tambah barang
                </button>
              </div>

              <div className="mt-4 grid gap-4">
                {lines.map((line, index) => {
                  const val = validatedLines[index];
                  const availBatches = batchesByProduct.get(line.productId) ?? [];

                  return (
                    <div
                      className="grid gap-4 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 sm:p-5"
                      key={line.id}
                    >
                      <div className="flex items-center justify-between border-b border-ui-border pb-3">
                        <span className="text-xs font-semibold uppercase tracking-wider text-ui-text-muted">
                          Barang #{index + 1}
                        </span>

                        <button
                          aria-label={`Hapus barang ${index + 1}`}
                          className="rounded-[var(--ui-radius-md)] px-2.5 py-1 text-xs font-semibold text-ui-danger hover:bg-ui-danger-subtle disabled:cursor-not-allowed disabled:opacity-50"
                          disabled={lines.length === 1}
                          onClick={() => removeLine(line.id)}
                          type="button"
                        >
                          Hapus
                        </button>
                      </div>

                      {/* Select Product */}
                      <label className="grid gap-2 text-sm font-semibold text-ui-text">
                        Produk *
                        <Select
                          onChange={(e) =>
                            updateLine(line.id, {
                              productId: e.target.value,
                            })
                          }
                          value={line.productId}
                        >
                          <option value="">-- Pilih Produk Aktif --</option>
                          {products.map((p) => (
                            <option key={p.product_id} value={p.product_id}>
                              {p.sku} &mdash; {p.name}
                            </option>
                          ))}
                        </Select>
                      </label>

                      {/* Select Batch Mode */}
                      {line.productId ? (
                        <div className="grid gap-3 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-3 sm:p-4">
                          <span className="text-xs font-semibold text-ui-text">
                            Batch
                          </span>
                          <div className="flex flex-wrap gap-4 text-sm">
                            <label className="inline-flex items-center gap-2 font-medium text-ui-text cursor-pointer">
                              <input
                                checked={line.batchMode === "existing"}
                                disabled={availBatches.length === 0}
                                name={`batchMode_${line.id}`}
                                onChange={() =>
                                  updateLine(line.id, {
                                    batchMode: "existing",
                                    batchId: availBatches[0]?.batch_id ?? "",
                                  })
                                }
                                type="radio"
                              />
                              Batch yang sudah ada
                              {availBatches.length === 0 ? (
                                <span className="text-xs text-ui-text-muted font-normal">(Tidak ada)</span>
                              ) : null}
                            </label>

                            <label className="inline-flex items-center gap-2 font-medium text-ui-text cursor-pointer">
                              <input
                                checked={line.batchMode === "new"}
                                name={`batchMode_${line.id}`}
                                onChange={() =>
                                  updateLine(line.id, {
                                    batchMode: "new",
                                  })
                                }
                                type="radio"
                              />
                              Buat batch baru
                            </label>
                          </div>

                          {/* Mode Existing */}
                          {line.batchMode === "existing" ? (
                            <div className="mt-2">
                              <label className="grid gap-1.5 text-xs font-semibold text-ui-text">
                                Pilih batch existing *
                                <Select
                                  onChange={(e) =>
                                    updateLine(line.id, {
                                      batchId: e.target.value,
                                    })
                                  }
                                  value={line.batchId}
                                >
                                  <option value="">-- Pilih Batch --</option>
                                  {availBatches.map((b) => (
                                    <option key={b.batch_id} value={b.batch_id}>
                                      {b.batch_code} · Exp {formatExpiry(b.expiry_date)}
                                    </option>
                                  ))}
                                </Select>
                              </label>
                            </div>
                          ) : (
                            /* Mode New Batch */
                            <div className="mt-2 grid gap-3 sm:grid-cols-3">
                              <label className="grid gap-1.5 text-xs font-semibold text-ui-text">
                                Kode Batch *
                                <Input
                                  autoComplete="off"
                                  onChange={(e) =>
                                    updateLine(line.id, {
                                      batchCode: e.target.value,
                                    })
                                  }
                                  placeholder="Contoh: BATCH-001"
                                  value={line.batchCode}
                                />
                              </label>

                              <label className="grid gap-1.5 text-xs font-semibold text-ui-text">
                                Tanggal Kedaluwarsa *
                                <Input
                                  onChange={(e) =>
                                    updateLine(line.id, {
                                      expiryDate: e.target.value,
                                    })
                                  }
                                  type="date"
                                  value={line.expiryDate}
                                />
                              </label>

                              <label className="grid gap-1.5 text-xs font-semibold text-ui-text">
                                Tanggal Produksi
                                <Input
                                  onChange={(e) =>
                                    updateLine(line.id, {
                                      manufacturedDate: e.target.value,
                                    })
                                  }
                                  type="date"
                                  value={line.manufacturedDate}
                                />
                              </label>
                            </div>
                          )}
                        </div>
                      ) : null}

                      {/* Quantity */}
                      <label className="grid gap-2 text-sm font-semibold text-ui-text">
                        Jumlah *
                        <Input
                          inputMode="numeric"
                          min={1}
                          onChange={(e) =>
                            updateLine(line.id, {
                              quantity: e.target.value,
                            })
                          }
                          step={1}
                          type="number"
                          value={line.quantity}
                        />
                      </label>

                      {/* Inline Validation Warnings */}
                      {val?.isDuplicate ? (
                        <p className="text-xs font-semibold text-ui-danger">
                          ⚠ Batch yang sama tidak boleh ditambahkan dua kali dalam satu penerimaan.
                        </p>
                      ) : null}
                      {val?.dateRangeError ? (
                        <p className="text-xs font-semibold text-ui-danger">
                          ⚠ Tanggal produksi tidak boleh setelah tanggal kedaluwarsa.
                        </p>
                      ) : null}
                    </div>
                  );
                })}
              </div>
            </div>

            <div className="mt-6 border-t border-ui-border pt-5 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <p className="text-sm text-ui-text-muted">
                {canSubmit
                  ? `${numberFormatter.format(lines.length)} barang · ${numberFormatter.format(total)} unit siap diperiksa.`
                  : "Lengkapi seluruh field wajib untuk memeriksa ringkasan penerimaan."}
              </p>

              <button
                className="inline-flex min-h-[var(--ui-control-height)] shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] bg-ui-primary px-5 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
                disabled={!canSubmit}
                onClick={() => setStep("review")}
                type="button"
              >
                Periksa Sebelum Simpan &rarr;
              </button>
            </div>
          </div>
        ) : (
          /* STEP 2: REVIEW / PREVIEW SUMMARY */
          <div>
            <div className="mt-5 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 grid gap-3 sm:grid-cols-3">
              <div>
                <span className="text-xs font-semibold text-ui-text-muted">Referensi Penerimaan</span>
                <p className="text-sm font-semibold text-ui-text">{sourceRef}</p>
              </div>
              <div>
                <span className="text-xs font-semibold text-ui-text-muted">Waktu Diterima</span>
                <p className="text-sm font-semibold text-ui-text">{occurredAt.replace("T", " ")}</p>
              </div>
              <div>
                <span className="text-xs font-semibold text-ui-text-muted">Catatan</span>
                <p className="text-sm text-ui-text">{note || "-"}</p>
              </div>
            </div>

            <div className="mt-6">
              <h3 className="text-base font-semibold text-ui-text">
                Ringkasan barang ({numberFormatter.format(validatedLines.length)} baris · {numberFormatter.format(total)} unit)
              </h3>

              <div className="mt-4 divide-y divide-ui-border border-t border-b border-ui-border">
                {validatedLines.map(({ line, product, batchDisplayCode, batchDisplayExpiry, qty }, idx) => (
                  <div
                    className="flex flex-col gap-2 py-4 sm:flex-row sm:items-center sm:justify-between"
                    key={line.id}
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-semibold text-ui-text-muted">#{idx + 1}</span>
                        <p className="text-sm font-semibold text-ui-text">
                          {product?.sku} &mdash; {product?.name}
                        </p>
                        {line.batchMode === "new" ? (
                          <StatusBadge tone="selected">Batch Baru</StatusBadge>
                        ) : (
                          <StatusBadge tone="neutral">Batch Existing</StatusBadge>
                        )}
                      </div>
                      <p className="mt-1 text-xs text-ui-text-muted">
                        Batch: <span className="font-semibold text-ui-text">{batchDisplayCode}</span> · EXP:{" "}
                        <span className="font-semibold text-ui-text">{formatExpiry(batchDisplayExpiry)}</span>
                      </p>
                    </div>

                    <p className="ui-number text-sm font-semibold text-ui-text">
                      {numberFormatter.format(qty)} unit
                    </p>
                  </div>
                ))}
              </div>
            </div>

            <Alert className="mt-6" tone="info">
              <p className="font-semibold">Dampak terhadap stok:</p>
              <p className="mt-1">
                Stok fisik akan bertambah <span className="font-semibold">{numberFormatter.format(total)} unit</span> di gudang setelah Anda menekan &quot;Simpan Barang Masuk&quot;. Reservasi produk tidak berubah.
              </p>
            </Alert>

            <div className="mt-6 flex flex-col sm:flex-row items-center justify-between gap-4 border-t border-ui-border pt-5">
              <button
                className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text hover:bg-ui-surface-subtle"
                onClick={() => setStep("edit")}
                type="button"
              >
                &larr; Kembali Edit
              </button>

              <button
                className="inline-flex min-h-[var(--ui-control-height)] shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] bg-ui-primary px-6 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
                type="submit"
              >
                Simpan Barang Masuk ({numberFormatter.format(total)} Unit)
              </button>
            </div>
          </div>
        )}
      </section>
    </form>
  );
}