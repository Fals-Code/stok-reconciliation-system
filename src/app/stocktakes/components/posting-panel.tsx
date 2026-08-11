import Link from "next/link";

import { postStocktakeAdjustmentAction } from "@/app/stocktakes/actions";
import { Textarea } from "@/components/ui";
import {
  buildStocktakeAdjustmentPreview,
  evaluateStocktakeApprovalSnapshot,
  evaluateStocktakePostingSnapshot,
} from "@/lib/stocktakes/posting";
import type {
  StocktakeApproval,
  StocktakeApprovalLine,
  StocktakePosting,
  StocktakePostingLine,
  StocktakeReviewLine,
  StocktakeStatus,
  StocktakeVarianceReason,
} from "@/lib/stocktakes/types";

const numberFormatter = new Intl.NumberFormat("id-ID");

const reasonLabels: Record<
  StocktakeVarianceReason,
  string
> = {
  UNRECORDED_MANUAL_OUTBOUND:
    "Barang keluar manual belum tercatat",
  UNRECORDED_INBOUND:
    "Barang masuk belum tercatat",
  RETURN_MISMATCH:
    "Ketidaksesuaian retur",
  WRONG_BATCH_COUNT:
    "Salah hitung Kode Batch",
  WRONG_BUCKET_COUNT:
    "Salah hitung kondisi stok",
  DAMAGE_NOT_RECORDED:
    "Kerusakan belum tercatat",
  EXPIRY_NOT_RECORDED:
    "Kedaluwarsa belum tercatat",
  INITIAL_BALANCE_UNCERTAIN:
    "Saldo awal belum pasti",
  COUNT_TIMING_DIFFERENCE:
    "Perbedaan waktu penghitungan",
  DUPLICATE_MOVEMENT:
    "Perubahan stok tercatat dua kali",
  SOURCE_EVENT_FAILURE:
    "Peristiwa sumber gagal tercatat",
  PROJECTION_DRIFT:
    "Catatan stok tidak selaras",
  PHYSICAL_LOSS:
    "Kehilangan fisik",
  PHYSICAL_SURPLUS:
    "Kelebihan fisik",
  MASTER_DATA_ERROR:
    "Data produk atau batch keliru",
  UNKNOWN:
    "Belum diketahui",
  OTHER:
    "Lainnya",
};

function bucketLabel(bucket: string) {
  return bucket === "SELLABLE"
    ? "Layak Dijual"
    : bucket === "QUARANTINE"
      ? "Ditahan"
      : "Rusak";
}

function formatDate(value: string) {
  const date = new Date(value);

  return Number.isNaN(date.getTime())
    ? "Waktu tidak tersedia"
    : new Intl.DateTimeFormat(
        "id-ID",
        {
          timeZone: "Asia/Jakarta",
          day: "2-digit",
          month: "short",
          year: "numeric",
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        },
      ).format(date);
}

function signedAmount(value: number) {
  const amount = Number(value);

  return `${
    amount > 0 ? "+" : ""
  }${numberFormatter.format(amount)} unit`;
}

export function PostingPanel({
  approval,
  approvalLines,
  posting,
  postingLines,
  reviewLines,
  status,
  stocktakeId,
}: {
  approval: StocktakeApproval | null;
  approvalLines: StocktakeApprovalLine[];
  posting: StocktakePosting | null;
  postingLines: StocktakePostingLine[];
  reviewLines: StocktakeReviewLine[];
  status: StocktakeStatus;
  stocktakeId: string;
}) {
  const reviewByLine = new Map(
    reviewLines.map((line) => [
      line.stocktake_line_id,
      line,
    ]),
  );

  if (status === "POSTING") {
    return (
      <section className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-warning bg-ui-warning-subtle p-4 text-sm text-ui-warning">
        <h2 className="font-semibold">
          Perubahan stok sedang disimpan
        </h2>
        <p className="mt-1 leading-6">
          Jangan ulangi perintah. Muat ulang
          halaman untuk melihat hasil yang
          tersimpan.
        </p>
      </section>
    );
  }

  if (status === "POSTED" && !posting) {
    return (
      <section className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-warning bg-ui-warning-subtle p-4 text-sm text-ui-warning">
        <h2 className="font-semibold">
          Bukti penyimpanan belum dapat dimuat
        </h2>
        <p className="mt-1 leading-6">
          Status Hitung Stok sudah selesai.
          Jangan menyimpan ulang. Muat ulang
          halaman untuk mengambil bukti transaksi
          yang sudah tercatat.
        </p>
      </section>
    );
  }

  if (status === "POSTED" && posting) {
    const integrity =
      evaluateStocktakePostingSnapshot(
        posting,
        postingLines,
      );

    const identityComplete =
      postingLines.every((line) =>
        reviewByLine.has(
          line.stocktake_line_id,
        ),
      );

    return (
      <section className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4">
        <h2 className="text-lg font-semibold text-ui-text">
          Perubahan Sudah Disimpan
        </h2>

        <p className="mt-1 text-sm text-ui-text-muted">
          Perubahan disimpan pada{" "}
          {formatDate(posting.posted_at)}.
          Bukti hasil tetap tersedia pada sesi
          ini.
        </p>

        <div className="mt-4 grid gap-3 text-sm sm:grid-cols-3">
          <p>
            <span className="text-ui-text-muted">
              Baris berubah
            </span>
            <br />
            <span className="ui-number font-semibold text-ui-text">
              {numberFormatter.format(
                posting.nonzero_line_count,
              )}
            </span>
          </p>

          <p>
            <span className="text-ui-text-muted">
              Perubahan bersih
            </span>
            <br />
            <span className="ui-number font-semibold text-ui-text">
              {signedAmount(
                posting.net_adjustment_qty,
              )}
            </span>
          </p>

          <p>
            <span className="text-ui-text-muted">
              Jumlah seluruh perubahan
            </span>
            <br />
            <span className="ui-number font-semibold text-ui-text">
              {numberFormatter.format(
                posting.total_absolute_adjustment_qty,
              )}{" "}
              unit
            </span>
          </p>
        </div>

        {postingLines.length ? (
          <div className="mt-5 border-t border-ui-border pt-4">
            <h3 className="text-sm font-semibold text-ui-text">
              Bukti perubahan per lokasi
            </h3>

            <div className="mt-3 grid gap-3">
              {postingLines.map((line) => {
                const review =
                  reviewByLine.get(
                    line.stocktake_line_id,
                  );

                return (
                  <article
                    className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-3 text-sm"
                    key={line.posting_line_id}
                  >
                    <p className="font-semibold text-ui-text">
                      {review
                        ? `${review.product_name_snapshot} · Kode Batch ${review.batch_code_snapshot}`
                        : "Identitas lokasi belum lengkap"}
                    </p>

                    <p className="mt-1 text-ui-text-muted">
                      {bucketLabel(
                        line.bucket_code,
                      )}{" "}
                      · saldo{" "}
                      {numberFormatter.format(
                        line.current_ledger_qty_before,
                      )}{" "}
                      →{" "}
                      {numberFormatter.format(
                        line.current_ledger_qty_after,
                      )}{" "}
                      unit
                    </p>

                    <p className="mt-1 text-ui-text-muted">
                      Dampak{" "}
                      {signedAmount(
                        line.adjustment_qty,
                      )}
                      {" · "}
                      {line.reason_code
                        ? reasonLabels[
                            line.reason_code
                          ]
                        : "Sesuai catatan"}
                    </p>
                  </article>
                );
              })}
            </div>
          </div>
        ) : null}

        {!integrity.isValid ||
        !identityComplete ? (
          <p className="mt-4 text-sm text-ui-danger">
            Bukti perubahan belum lengkap untuk
            ditampilkan dengan aman. Muat ulang
            dan periksa kembali transaksi yang
            sudah tersimpan.
          </p>
        ) : null}

        {posting.note ? (
          <p className="mt-4 border-t border-ui-border pt-4 text-sm text-ui-text-muted">
            Catatan penyimpanan:{" "}
            {posting.note}
          </p>
        ) : null}

        <Link
          className="mt-4 inline-flex min-h-[var(--ui-control-height)] items-center font-semibold text-ui-primary hover:underline"
          href={`/ledger/${encodeURIComponent(
            posting.transaction_id,
          )}`}
        >
          Buka transaksi di Riwayat Stok
        </Link>
      </section>
    );
  }

  if (!approval) {
    return (
      <section className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-warning bg-ui-warning-subtle p-4 text-sm text-ui-warning">
        Hasil yang disetujui belum dapat dimuat.
        Muat ulang halaman sebelum menyimpan
        perubahan.
      </section>
    );
  }

  const integrity =
    evaluateStocktakeApprovalSnapshot(
      approval,
      approvalLines,
    );

  const preview =
    buildStocktakeAdjustmentPreview(
      approvalLines,
    );

  const identityComplete =
    approvalLines.every((line) =>
      reviewByLine.has(
        line.stocktake_line_id,
      ),
    );

  return (
    <section className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4">
      <h2 className="text-lg font-semibold text-ui-text">
        Simpan Perubahan Stok
      </h2>

      <p className="mt-1 text-sm leading-6 text-ui-text-muted">
        Hasil yang sudah disetujui akan disimpan
        tepat seperti pemeriksaan berikut.
      </p>

      <div className="mt-4 grid gap-3">
        {approvalLines.map((line) => {
          const review =
            reviewByLine.get(
              line.stocktake_line_id,
            );

          if (!review) {
            return null;
          }

          return (
            <article
              className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-3 text-sm"
              key={line.approval_line_id}
            >
              <p className="font-semibold text-ui-text">
                {review.product_name_snapshot}
                {" · "}Kode Batch{" "}
                {review.batch_code_snapshot}
              </p>

              <p className="mt-1 text-ui-text-muted">
                {bucketLabel(
                  review.bucket_code,
                )}
                {" · "}Catatan{" "}
                {numberFormatter.format(
                  line.expected_qty_at_count,
                )}
                {" · "}Fisik{" "}
                {numberFormatter.format(
                  line.final_physical_qty,
                )}
                {" · "}Selisih{" "}
                {numberFormatter.format(
                  line.variance_qty,
                )}{" "}
                unit
              </p>

              <p className="mt-1 text-ui-text-muted">
                Dampak:{" "}
                {signedAmount(
                  line.variance_qty,
                )}
                {" · "}
                {line.reason_code
                  ? reasonLabels[
                      line.reason_code
                    ]
                  : "Sesuai catatan"}
              </p>
            </article>
          );
        })}
      </div>

      <p className="mt-4 text-sm text-ui-text-muted">
        Ringkasan:{" "}
        {numberFormatter.format(
          preview.positiveLineCount,
        )}{" "}
        bertambah,{" "}
        {numberFormatter.format(
          preview.negativeLineCount,
        )}{" "}
        berkurang, total perubahan{" "}
        {numberFormatter.format(
          preview.totalAbsoluteAdjustmentQty,
        )}{" "}
        unit.
      </p>

      {!integrity.isValid ||
      !identityComplete ? (
        <p className="mt-3 text-sm text-ui-danger">
          Hasil yang disetujui belum lengkap untuk
          ditampilkan dengan aman. Muat ulang dan
          periksa kembali sebelum menyimpan.
        </p>
      ) : null}

      {status === "APPROVED" &&
      integrity.isValid &&
      identityComplete ? (
        <form
          action={postStocktakeAdjustmentAction}
          className="mt-4 grid gap-3"
        >
          <input
            name="stocktakeId"
            type="hidden"
            value={stocktakeId}
          />

          <input
            name="approvalVersion"
            type="hidden"
            value={
              approval.approval_version_no
            }
          />

          <label className="grid gap-2 text-sm font-semibold text-ui-text">
            Catatan penyimpanan
            <Textarea name="note" />
          </label>

          <label className="flex items-start gap-2 text-sm text-ui-text">
            <input
              className="mt-1"
              name="confirmation"
              required
              type="checkbox"
            />
            Saya memahami hasil ini akan
            menyimpan perubahan stok permanen.
          </label>

          <button
            className="min-h-[var(--ui-control-height)] justify-self-start rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary"
            type="submit"
          >
            Simpan Perubahan Stok
          </button>
        </form>
      ) : null}
    </section>
  );
}
