import ApprovalPanel from "@/app/stocktakes/components/approval-panel";
import {
  requestStocktakeReviewRecountAction,
  reviewStocktakeLineAction,
} from "@/app/stocktakes/actions";
import {
  STOCKTAKE_BUCKET_LABELS,
  STOCKTAKE_REVIEW_DECISION_META,
  STOCKTAKE_VARIANCE_REASON_LABELS,
  STOCKTAKE_VARIANCE_REASON_OPTIONS,
  type StocktakePillTone,
} from "@/lib/stocktakes/constants";
import type {
  StocktakeCountAttempt,
  StocktakeDetails,
  StocktakeReviewLine,
} from "@/lib/stocktakes/types";

const numberFormatter = new Intl.NumberFormat("id-ID");

type ReviewFilters = {
  query: string;
  bucket: string;
  variance: string;
  review: string;
  reason: string;
};

function formatNumber(value: number | null) {
  return value === null ? "Belum ada" : numberFormatter.format(Number(value));
}

function formatDateTime(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function StatusPill({
  label,
  tone,
}: {
  label: string;
  tone: StocktakePillTone;
}) {
  const tones: Record<StocktakePillTone, string> = {
    success: "border-emerald-400/25 bg-emerald-400/10 text-emerald-200",
    warning: "border-amber-400/25 bg-amber-400/10 text-amber-100",
    danger: "border-rose-400/25 bg-rose-400/10 text-rose-100",
    neutral: "border-white/10 bg-white/[0.04] text-slate-300",
  };

  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-medium ${tones[tone]}`}
    >
      {label}
    </span>
  );
}

function lineMatchesFilters(
  line: StocktakeReviewLine,
  filters: ReviewFilters,
) {
  const normalizedQuery = filters.query.trim().toLowerCase();

  if (
    normalizedQuery &&
    ![
      line.product_sku_snapshot,
      line.product_name_snapshot,
      line.batch_code_snapshot,
    ].some((value) => value.toLowerCase().includes(normalizedQuery))
  ) {
    return false;
  }

  if (filters.bucket && line.bucket_code !== filters.bucket) {
    return false;
  }

  if (filters.variance === "MATCHED" && line.variance_qty !== 0) {
    return false;
  }

  if (
    filters.variance === "NONZERO" &&
    (line.variance_qty === null || line.variance_qty === 0)
  ) {
    return false;
  }

  if (
    filters.review === "PENDING" &&
    line.review_status_code === "REVIEWED"
  ) {
    return false;
  }

  if (
    filters.review === "REVIEWED" &&
    line.review_status_code !== "REVIEWED"
  ) {
    return false;
  }

  if (
    filters.review === "EXCEPTION" &&
    line.review_decision_code !== "EXCEPTION"
  ) {
    return false;
  }

  if (filters.reason && line.reason_code !== filters.reason) {
    return false;
  }

  return true;
}

function ReviewForm({
  stocktakeId,
  line,
}: {
  stocktakeId: string;
  line: StocktakeReviewLine;
}) {
  const isMatched = line.variance_qty === 0;
  const defaultDecision =
    line.review_decision_code &&
    line.review_decision_code !== "RECOUNT_REQUIRED"
      ? line.review_decision_code
      : isMatched
        ? "MATCHED"
        : "VARIANCE_ACCEPTED";

  return (
    <form
      action={reviewStocktakeLineAction}
      className="mt-5 rounded-2xl border border-white/10 bg-slate-950/45 p-4"
    >
      <input type="hidden" name="stocktakeId" value={stocktakeId} />
      <input
        type="hidden"
        name="stocktakeLineId"
        value={line.stocktake_line_id}
      />
      <input type="hidden" name="lineVersion" value={line.version_no} />

      <div className="grid gap-4 lg:grid-cols-2">
        <label>
          <span className="field-label">Keputusan review</span>
          <select
            className="mt-2 w-full rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-emerald-400/50"
            name="decisionCode"
            defaultValue={defaultDecision}
            required
          >
            {isMatched ? (
              <option value="MATCHED">Matched</option>
            ) : (
              <option value="VARIANCE_ACCEPTED">
                Terima variance
              </option>
            )}
            <option value="EXCEPTION">Tandai exception</option>
          </select>
        </label>

        <label>
          <span className="field-label">
            Reason variance
          </span>
          <select
            className="mt-2 w-full rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-emerald-400/50"
            name="reasonCode"
            defaultValue={line.reason_code ?? ""}
            disabled={isMatched}
          >
            <option value="">
              {isMatched
                ? "Tidak berlaku untuk matched line"
                : "Pilih reason"}
            </option>
            {STOCKTAKE_VARIANCE_REASON_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>

        <label>
          <span className="field-label">Kode exception</span>
          <input
            className="mt-2 w-full rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-rose-400/50"
            type="text"
            name="exceptionCode"
            maxLength={100}
            defaultValue={line.exception_code ?? ""}
            placeholder="Wajib ketika keputusan EXCEPTION."
          />
        </label>

        <label>
          <span className="field-label">Catatan review</span>
          <textarea
            className="mt-2 min-h-24 w-full rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-emerald-400/50"
            name="reviewNote"
            maxLength={2000}
            defaultValue={line.review_note ?? ""}
            placeholder="Wajib untuk UNKNOWN atau OTHER."
          />
        </label>
      </div>

      <button className="primary-button mt-4" type="submit">
        {line.review_status_code === "REVIEWED"
          ? "Perbarui keputusan review"
          : "Simpan keputusan review"}
      </button>
    </form>
  );
}

function ReviewRecountForm({
  stocktakeId,
  line,
}: {
  stocktakeId: string;
  line: StocktakeReviewLine;
}) {
  return (
    <details className="mt-4 rounded-xl border border-amber-400/20 bg-amber-400/[0.045] p-4">
      <summary className="cursor-pointer text-sm font-semibold text-amber-100">
        Kembalikan line ke counting
      </summary>

      <form action={requestStocktakeReviewRecountAction} className="mt-4">
        <input type="hidden" name="stocktakeId" value={stocktakeId} />
        <input
          type="hidden"
          name="stocktakeLineId"
          value={line.stocktake_line_id}
        />
        <input type="hidden" name="lineVersion" value={line.version_no} />

        <label>
          <span className="field-label">Alasan review recount</span>
          <textarea
            className="mt-2 min-h-24 w-full rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-amber-400/50"
            name="reason"
            maxLength={2000}
            required
            placeholder="Jelaskan mengapa physical quantity perlu dihitung ulang."
          />
        </label>

        <button
          className="mt-4 rounded-xl border border-amber-400/30 bg-amber-400/10 px-4 py-2.5 text-sm font-semibold text-amber-100 transition hover:bg-amber-400/15"
          type="submit"
        >
          Minta recount dari review
        </button>
      </form>
    </details>
  );
}

export default function ReviewPanel({
  details,
  lines,
  attempts,
  filters,
}: {
  details: StocktakeDetails;
  lines: StocktakeReviewLine[];
  attempts: StocktakeCountAttempt[];
  filters: ReviewFilters;
}) {
  const attemptsByLine = new Map<string, StocktakeCountAttempt[]>();

  for (const attempt of attempts) {
    const current = attemptsByLine.get(attempt.stocktake_line_id) ?? [];
    current.push(attempt);
    attemptsByLine.set(attempt.stocktake_line_id, current);
  }

  const filteredLines = lines.filter((line) =>
    lineMatchesFilters(line, filters),
  );
  const reviewedLines = lines.filter(
    (line) => line.review_status_code === "REVIEWED",
  ).length;
  const exceptionLines = lines.filter(
    (line) => line.review_decision_code === "EXCEPTION",
  ).length;
  const approvalReadyLines = lines.filter(
    (line) =>
      line.review_status_code === "REVIEWED" &&
      (line.review_decision_code === "MATCHED" ||
        line.review_decision_code === "VARIANCE_ACCEPTED") &&
      !line.exception_code,
  ).length;
  return (
    <section className="mt-8">
      <div className="panel-card">
        <p className="section-kicker">Variance review</p>
        <h2 className="section-title">
          Tinjau expected, physical, dan variance per line.
        </h2>
        <p className="mt-3 max-w-4xl text-sm leading-6 text-slate-400">
          Review tidak mengubah stok. Setiap keputusan memakai line version
          saat ini. Konflik versi harus dimuat ulang, bukan dilewati dengan
          tebakan versi baru.
        </p>

        <div className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <div className="metric-card">
            <p className="metric-label">Line</p>
            <p className="metric-value">{formatNumber(lines.length)}</p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Reviewed</p>
            <p className="metric-value">
              {formatNumber(reviewedLines)} / {formatNumber(lines.length)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Exception</p>
            <p className="metric-value">{formatNumber(exceptionLines)}</p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Approval ready</p>
            <p className="metric-value">
              {formatNumber(approvalReadyLines)} / {formatNumber(lines.length)}
            </p>
          </div>
        </div>

        <form className="mt-6 grid gap-3 lg:grid-cols-7" method="get">
          <input
            className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none lg:col-span-2"
            type="search"
            name="q"
            defaultValue={filters.query}
            placeholder="Cari SKU, produk, atau batch"
          />

          <select
            className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white"
            name="bucket"
            defaultValue={filters.bucket}
          >
            <option value="">Semua bucket</option>
            {Object.entries(STOCKTAKE_BUCKET_LABELS).map(
              ([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ),
            )}
          </select>

          <select
            className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white"
            name="variance"
            defaultValue={filters.variance}
          >
            <option value="">Semua variance</option>
            <option value="MATCHED">Variance nol</option>
            <option value="NONZERO">Variance nonzero</option>
          </select>

          <select
            className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white"
            name="review"
            defaultValue={filters.review}
          >
            <option value="">Semua status review</option>
            <option value="PENDING">Belum direview</option>
            <option value="REVIEWED">Sudah direview</option>
            <option value="EXCEPTION">Exception</option>
          </select>

          <select
            className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white"
            name="reason"
            defaultValue={filters.reason}
          >
            <option value="">Semua reason</option>
            {STOCKTAKE_VARIANCE_REASON_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>

          <button className="primary-button" type="submit">
            Terapkan filter
          </button>
        </form>
      </div>

      <div className="mt-5 space-y-5">
        {filteredLines.map((line) => {
          const lineAttempts =
            attemptsByLine.get(line.stocktake_line_id) ?? [];
          const decision = line.review_decision_code
            ? STOCKTAKE_REVIEW_DECISION_META[line.review_decision_code]
            : null;

          return (
            <article key={line.stocktake_line_id} className="panel-card">
              <div className="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-mono text-xs text-slate-500">
                      Line {formatNumber(line.line_no)} Â· Version{" "}
                      {formatNumber(line.version_no)}
                    </span>
                    <StatusPill
                      label={STOCKTAKE_BUCKET_LABELS[line.bucket_code]}
                      tone="neutral"
                    />
                    {decision ? (
                      <StatusPill
                        label={decision.label}
                        tone={decision.tone}
                      />
                    ) : (
                      <StatusPill
                        label="Belum direview"
                        tone="neutral"
                      />
                    )}
                  </div>

                  <h3 className="mt-3 text-lg font-semibold text-white">
                    {line.product_sku_snapshot} Â· {line.product_name_snapshot}
                  </h3>
                  <p className="mt-2 text-sm text-slate-400">
                    Batch {line.batch_code_snapshot} Â· Expiry{" "}
                    {line.expiry_date_snapshot}
                  </p>
                </div>

                <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                  <div className="rounded-xl border border-white/10 bg-slate-950/40 p-3">
                    <p className="text-xs text-slate-500">Expected</p>
                    <p className="mt-1 font-semibold text-white">
                      {formatNumber(line.expected_qty_at_count)}
                    </p>
                  </div>
                  <div className="rounded-xl border border-white/10 bg-slate-950/40 p-3">
                    <p className="text-xs text-slate-500">Physical</p>
                    <p className="mt-1 font-semibold text-white">
                      {formatNumber(line.final_physical_qty)}
                    </p>
                  </div>
                  <div className="rounded-xl border border-white/10 bg-slate-950/40 p-3">
                    <p className="text-xs text-slate-500">Variance</p>
                    <p
                      className={`mt-1 font-semibold ${
                        (line.variance_qty ?? 0) === 0
                          ? "text-emerald-200"
                          : "text-amber-100"
                      }`}
                    >
                      {formatNumber(line.variance_qty)}
                    </p>
                  </div>
                  <div className="rounded-xl border border-white/10 bg-slate-950/40 p-3">
                    <p className="text-xs text-slate-500">Attempt</p>
                    <p className="mt-1 font-semibold text-white">
                      {formatNumber(line.count_attempt_no)}
                    </p>
                  </div>
                </div>
              </div>

              <div className="mt-4 grid gap-3 text-sm lg:grid-cols-3">
                <div className="rounded-xl border border-white/10 p-3">
                  <p className="text-xs text-slate-500">Snapshot awal</p>
                  <p className="mt-1 text-slate-200">
                    {formatNumber(line.system_qty_at_snapshot)}
                  </p>
                </div>
                <div className="rounded-xl border border-white/10 p-3">
                  <p className="text-xs text-slate-500">Count cutoff</p>
                  <p className="mt-1 text-slate-200">
                    {formatNumber(line.count_cutoff_ledger_seq)}
                  </p>
                </div>
                <div className="rounded-xl border border-white/10 p-3">
                  <p className="text-xs text-slate-500">Formula</p>
                  <p className="mt-1 break-all text-slate-200">
                    {line.expected_formula_version ?? "Belum ada"}
                  </p>
                </div>
              </div>

              {line.review_status_code === "REVIEWED" ? (
                <>
                  <div className="mt-4 rounded-xl border border-white/10 bg-white/[0.025] p-4 text-sm">
                    <p className="font-semibold text-slate-200">
                      Keputusan tersimpan
                    </p>
                    <p className="mt-2 text-slate-400">
                      Reason:{" "}
                      {line.reason_code
                        ? STOCKTAKE_VARIANCE_REASON_LABELS[line.reason_code]
                        : "Tidak ada"}
                    </p>
                    <p className="mt-1 text-slate-400">
                      Exception: {line.exception_code ?? "Tidak ada"}
                    </p>
                    <p className="mt-1 text-slate-400">
                      Catatan: {line.review_note ?? "Tidak ada"}
                    </p>
                  </div>

                  <details className="mt-4 rounded-xl border border-white/10 p-4">
                    <summary className="cursor-pointer text-sm font-semibold text-slate-200">
                      Ubah keputusan review
                    </summary>
                    <ReviewForm
                      stocktakeId={details.stocktake_id}
                      line={line}
                    />
                  </details>
                </>
              ) : (
                <ReviewForm
                  stocktakeId={details.stocktake_id}
                  line={line}
                />
              )}

              <ReviewRecountForm
                stocktakeId={details.stocktake_id}
                line={line}
              />

              <details className="mt-4 rounded-xl border border-white/10 p-4">
                <summary className="cursor-pointer text-sm font-semibold text-slate-200">
                  Riwayat count attempt ({lineAttempts.length})
                </summary>

                <div className="mt-4 overflow-x-auto">
                  <table className="min-w-[880px]">
                    <thead>
                      <tr>
                        <th>Attempt</th>
                        <th>Physical</th>
                        <th>Expected</th>
                        <th>Variance</th>
                        <th>Cutoff</th>
                        <th>Method</th>
                        <th>Counted at</th>
                        <th>Catatan</th>
                      </tr>
                    </thead>
                    <tbody>
                      {lineAttempts.map((attempt) => (
                        <tr key={attempt.count_attempt_id}>
                          <td>{formatNumber(attempt.attempt_no)}</td>
                          <td>{formatNumber(attempt.physical_qty)}</td>
                          <td>
                            {formatNumber(attempt.expected_qty_at_count)}
                          </td>
                          <td>{formatNumber(attempt.variance_qty)}</td>
                          <td>
                            {formatNumber(
                              attempt.count_cutoff_ledger_seq,
                            )}
                          </td>
                          <td>{attempt.count_method_code}</td>
                          <td>{formatDateTime(attempt.counted_at)}</td>
                          <td>{attempt.note ?? "-"}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </details>
            </article>
          );
        })}

        {filteredLines.length === 0 ? (
          <div className="panel-card text-sm text-slate-400">
            Tidak ada review line yang cocok dengan filter.
          </div>
        ) : null}
      </div>

      <ApprovalPanel details={details} reviewLines={lines} />
    </section>
  );
}
