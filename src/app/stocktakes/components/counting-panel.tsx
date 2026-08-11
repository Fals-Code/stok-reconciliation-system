"use client";

import { useState } from "react";
import { useFormStatus } from "react-dom";

import {
  completeStocktakeCountingAction,
  requestStocktakeRecountAction,
  submitStocktakeCountAction,
} from "@/app/stocktakes/actions";
import { Input, StatusBadge, Textarea } from "@/components/ui";
import type {
  StocktakeCountingLine,
  StocktakeNonBlindLine,
  StocktakeVisibility,
} from "@/lib/stocktakes/types";

const numberFormatter = new Intl.NumberFormat("id-ID");

function bucketLabel(bucket: string) {
  return bucket === "SELLABLE"
    ? "Layak Dijual"
    : bucket === "QUARANTINE"
      ? "Ditahan"
      : "Rusak";
}

function isNonBlindLine(
  line: StocktakeCountingLine,
): line is StocktakeNonBlindLine {
  return "expected_qty_at_count" in line;
}

function CountSubmitButton() {
  const { pending } = useFormStatus();

  return (
    <button
      className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary disabled:cursor-not-allowed disabled:opacity-60"
      disabled={pending}
      type="submit"
    >
      {pending ? "Menyimpan..." : "Simpan Hitungan"}
    </button>
  );
}

function RecountSubmitButton() {
  const { pending } = useFormStatus();

  return (
    <button
      className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text disabled:cursor-not-allowed disabled:opacity-60"
      disabled={pending}
      type="submit"
    >
      {pending ? "Meminta..." : "Minta Hitung Ulang"}
    </button>
  );
}

function CompleteSubmitButton({
  disabled,
}: {
  disabled: boolean;
}) {
  const { pending } = useFormStatus();

  return (
    <button
      className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary disabled:cursor-not-allowed disabled:border-ui-border disabled:bg-ui-surface-subtle disabled:text-ui-text-muted"
      disabled={disabled || pending}
      type="submit"
    >
      {pending ? "Menyelesaikan..." : "Selesaikan Penghitungan"}
    </button>
  );
}

export function CountingPanel({
  lines,
  stocktakeId,
  stocktakeVersion,
  visibility,
}: {
  lines: StocktakeCountingLine[];
  stocktakeId: string;
  stocktakeVersion: number;
  visibility: StocktakeVisibility;
}) {
  const [quantities, setQuantities] = useState<Record<string, string>>({});
  const [recountOpenByLine, setRecountOpenByLine] = useState<
    Record<string, boolean>
  >({});

  const countedCount = lines.filter(
    (line) => line.count_status_code === "COUNTED",
  ).length;
  const remainingCount = lines.length - countedCount;
  const allCounted = lines.length > 0 && remainingCount === 0;

  return (
    <section className="mt-6">
      <div className="flex flex-col gap-1 border-b border-ui-border pb-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-lg font-semibold text-ui-text">
            Hitung barang fisik
          </h2>
          <p className="mt-1 text-sm text-ui-text-muted">
            {visibility === "BLIND"
              ? "Jumlah sistem dan selisih disembunyikan selama menghitung."
              : "Catatan sistem tersedia sebagai informasi pendamping."}
          </p>
        </div>
        <p className="text-sm font-medium text-ui-text-muted">
          {countedCount} dari {lines.length} selesai
        </p>
      </div>

      <div className="mt-4 grid gap-3">
        {lines.map((line) => {
          const physicalQty = quantities[line.stocktake_line_id] ?? "";
          const isZero = physicalQty === "0";
          const nonBlind =
            visibility === "NON_BLIND" && isNonBlindLine(line);
          const isCounted = line.count_status_code === "COUNTED";
          const needsRecount =
            line.count_status_code === "RECOUNT_REQUESTED";
          const canCount = line.count_status_code !== "COUNTED";
          const recountOpen =
            recountOpenByLine[line.stocktake_line_id] ?? false;

          const expectedQty = nonBlind
            ? line.expected_qty_at_count ?? line.system_qty_at_snapshot
            : null;

          return (
            <article
              className={`rounded-[var(--ui-radius-md)] border p-4 ${
                isCounted
                  ? "border-ui-border bg-ui-surface"
                  : "border-ui-border bg-ui-surface-subtle"
              }`}
              key={line.stocktake_line_id}
            >
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div className="min-w-0">
                  <h3 className="font-semibold text-ui-text">
                    {line.product_name_snapshot}
                  </h3>
                  <p className="mt-1 text-sm text-ui-text-muted">
                    {line.product_sku_snapshot}
                    {" · "}Kode Batch {line.batch_code_snapshot}
                    {" · "}
                    {bucketLabel(line.bucket_code)}
                  </p>
                </div>

                <StatusBadge
                  tone={
                    isCounted
                      ? "selected"
                      : needsRecount
                        ? "warning"
                        : "neutral"
                  }
                >
                  {isCounted
                    ? "Sudah dihitung"
                    : needsRecount
                      ? "Perlu hitung ulang"
                      : "Belum dihitung"}
                </StatusBadge>
              </div>

              {isCounted ? (
                <div
                  className={`mt-4 grid gap-3 text-sm ${
                    nonBlind ? "sm:grid-cols-3" : "sm:grid-cols-1"
                  }`}
                >
                  {nonBlind ? (
                    <p>
                      <span className="text-ui-text-muted">
                        Catatan sistem
                      </span>
                      <br />
                      <span className="ui-number font-semibold text-ui-text">
                        {numberFormatter.format(expectedQty ?? 0)} unit
                      </span>
                    </p>
                  ) : null}

                  <p>
                    <span className="text-ui-text-muted">Fisik terakhir</span>
                    <br />
                    <span className="ui-number font-semibold text-ui-text">
                      {line.final_physical_qty === null
                        ? "Belum tersedia"
                        : `${numberFormatter.format(line.final_physical_qty)} unit`}
                    </span>
                  </p>

                  {nonBlind ? (
                    <p>
                      <span className="text-ui-text-muted">
                        Selisih terakhir
                      </span>
                      <br />
                      <span className="ui-number font-semibold text-ui-text">
                        {line.variance_qty === null
                          ? "Belum tersedia"
                          : `${line.variance_qty > 0 ? "+" : ""}${numberFormatter.format(line.variance_qty)} unit`}
                      </span>
                    </p>
                  ) : null}
                </div>
              ) : nonBlind ? (
                <div className="mt-4 text-sm">
                  <p>
                    <span className="text-ui-text-muted">Catatan sistem</span>
                    <br />
                    <span className="ui-number font-semibold text-ui-text">
                      {numberFormatter.format(expectedQty ?? 0)} unit
                    </span>
                  </p>
                </div>
              ) : null}

              {canCount ? (
                <form
                  action={submitStocktakeCountAction}
                  className="mt-4 grid gap-3 border-t border-ui-border pt-4 sm:grid-cols-[minmax(0,200px)_1fr_auto]"
                >
                  <input
                    name="stocktakeId"
                    type="hidden"
                    value={stocktakeId}
                  />
                  <input
                    name="stocktakeLineId"
                    type="hidden"
                    value={line.stocktake_line_id}
                  />
                  <input
                    name="attemptNo"
                    type="hidden"
                    value={line.count_attempt_no}
                  />

                  <label className="grid gap-2 text-sm font-semibold text-ui-text">
                    Jumlah fisik
                    <Input
                      inputMode="numeric"
                      min="0"
                      name="physicalQty"
                      onChange={(event) =>
                        setQuantities((current) => ({
                          ...current,
                          [line.stocktake_line_id]: event.target.value,
                        }))
                      }
                      required
                      step="1"
                      type="number"
                      value={physicalQty}
                    />
                  </label>

                  <label className="grid gap-2 text-sm font-semibold text-ui-text">
                    Catatan (opsional)
                    <Textarea
                      className="min-h-[var(--ui-control-height)]"
                      name="note"
                      placeholder="Contoh: rak belakang"
                      rows={1}
                    />
                  </label>

                  <div className="flex flex-col justify-end gap-2">
                    {isZero ? (
                      <label className="flex max-w-52 items-start gap-2 text-xs leading-5 text-ui-text-muted">
                        <input
                          className="mt-1"
                          name="zeroConfirmed"
                          required
                          type="checkbox"
                        />
                        Saya memastikan jumlah fisiknya nol
                      </label>
                    ) : null}

                    <CountSubmitButton />
                  </div>
                </form>
              ) : null}

              {isCounted ? (
                <div className="mt-4 border-t border-ui-border pt-3">
                  {!recountOpen ? (
                    <button
                      className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
                      onClick={() =>
                        setRecountOpenByLine((current) => ({
                          ...current,
                          [line.stocktake_line_id]: true,
                        }))
                      }
                      type="button"
                    >
                      Hitung ulang
                    </button>
                  ) : (
                    <form
                      action={requestStocktakeRecountAction}
                      className="grid gap-3 sm:grid-cols-[1fr_auto] sm:items-end"
                    >
                      <input
                        name="stocktakeId"
                        type="hidden"
                        value={stocktakeId}
                      />
                      <input
                        name="stocktakeLineId"
                        type="hidden"
                        value={line.stocktake_line_id}
                      />
                      <input
                        name="attemptNo"
                        type="hidden"
                        value={line.count_attempt_no}
                      />

                      <label className="grid gap-2 text-sm font-semibold text-ui-text">
                        Alasan hitung ulang
                        <Input
                          name="reason"
                          placeholder="Contoh: jumlah perlu dicek kembali"
                          required
                        />
                      </label>

                      <div className="flex flex-wrap gap-2">
                        <button
                          className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] px-3 text-sm font-semibold text-ui-text-muted hover:text-ui-text"
                          onClick={() =>
                            setRecountOpenByLine((current) => ({
                              ...current,
                              [line.stocktake_line_id]: false,
                            }))
                          }
                          type="button"
                        >
                          Batal
                        </button>
                        <RecountSubmitButton />
                      </div>
                    </form>
                  )}
                </div>
              ) : null}

              {needsRecount ? (
                <p className="mt-3 text-xs font-medium text-ui-warning">
                  Lakukan hitung ulang lalu simpan hasil baru.
                </p>
              ) : null}
            </article>
          );
        })}
      </div>

      <form
        action={completeStocktakeCountingAction}
        className="mt-6 flex flex-col gap-3 border-t border-ui-border pt-5 sm:flex-row sm:items-center sm:justify-between"
      >
        <input name="stocktakeId" type="hidden" value={stocktakeId} />
        <input
          name="stocktakeVersion"
          type="hidden"
          value={stocktakeVersion}
        />

        <div>
          <p className="text-sm font-semibold text-ui-text">
            {allCounted
              ? "Semua lokasi sudah dihitung."
              : `${remainingCount} lokasi masih perlu dihitung.`}
          </p>
          <p className="mt-1 text-sm text-ui-text-muted">
            Setelah selesai, hasil masuk ke pemeriksaan dan stok belum berubah.
          </p>
        </div>

        <CompleteSubmitButton disabled={!allCounted} />
      </form>
    </section>
  );
}