import { approveStocktakeAction } from "@/app/stocktakes/actions";
import {
  STOCKTAKE_BUCKET_LABELS,
  STOCKTAKE_VARIANCE_REASON_LABELS,
} from "@/lib/stocktakes/constants";
import type {
  StocktakeApproval,
  StocktakeApprovalLine,
  StocktakeDetails,
  StocktakeReviewLine,
} from "@/lib/stocktakes/types";

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number) {
  return numberFormatter.format(Number(value));
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

function reviewReady(line: StocktakeReviewLine) {
  return (
    line.review_status_code === "REVIEWED" &&
    (line.review_decision_code === "MATCHED" ||
      line.review_decision_code === "VARIANCE_ACCEPTED") &&
    !line.exception_code
  );
}

function ReviewApprovalForm({
  details,
  reviewLines,
}: {
  details: StocktakeDetails;
  reviewLines: StocktakeReviewLine[];
}) {
  const lineCount = reviewLines.length;
  const readyLineCount = reviewLines.filter(reviewReady).length;
  const varianceLineCount = reviewLines.filter(
    (line) => line.variance_qty !== null && line.variance_qty !== 0,
  ).length;
  const exceptionLineCount = reviewLines.filter(
    (line) => line.review_decision_code === "EXCEPTION",
  ).length;
  const totalVarianceQty = reviewLines.reduce(
    (total, line) => total + (line.variance_qty ?? 0),
    0,
  );
  const approvalReady =
    lineCount > 0 && readyLineCount === lineCount;

  return (
    <section
      className={`mt-6 rounded-2xl border p-5 ${
        approvalReady
          ? "border-emerald-400/20 bg-emerald-400/[0.055]"
          : "border-white/10 bg-white/[0.025]"
      }`}
    >
      <p className="section-kicker">Immutable approval</p>
      <h2 className="section-title">
        Bekukan hasil review sebagai approval versioned.
      </h2>
      <p className="mt-3 max-w-4xl text-sm leading-6 text-slate-400">
        Approval tidak mengubah stok. Server membuat header dan snapshot line
        immutable menggunakan stocktake version saat ini. Konflik versi harus
        dimuat ulang, bukan ditimpa dengan versi hasil tebakan.
      </p>

      <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        <div className="metric-card">
          <p className="metric-label">Line</p>
          <p className="metric-value">{formatNumber(lineCount)}</p>
        </div>
        <div className="metric-card">
          <p className="metric-label">Approval ready</p>
          <p className="metric-value">
            {formatNumber(readyLineCount)} / {formatNumber(lineCount)}
          </p>
        </div>
        <div className="metric-card">
          <p className="metric-label">Variance line</p>
          <p className="metric-value">
            {formatNumber(varianceLineCount)}
          </p>
        </div>
        <div className="metric-card">
          <p className="metric-label">Total variance</p>
          <p className="metric-value">
            {formatNumber(totalVarianceQty)}
          </p>
        </div>
        <div className="metric-card">
          <p className="metric-label">Stocktake version</p>
          <p className="metric-value">
            {formatNumber(details.version_no)}
          </p>
        </div>
      </div>

      {!approvalReady ? (
        <div className="mt-5 rounded-xl border border-amber-400/20 bg-amber-400/[0.05] p-4 text-sm text-amber-100">
          Approval diblokir. Selesaikan seluruh review sebagai MATCHED atau
          VARIANCE_ACCEPTED dan hilangkan {formatNumber(exceptionLineCount)}{" "}
          exception line.
        </div>
      ) : (
        <form action={approveStocktakeAction} className="mt-5">
          <input
            type="hidden"
            name="stocktakeId"
            value={details.stocktake_id}
          />
          <input
            type="hidden"
            name="stocktakeVersion"
            value={details.version_no}
          />

          <label>
            <span className="field-label">Catatan approval</span>
            <textarea
              className="mt-2 min-h-24 w-full rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-emerald-400/50"
              name="note"
              maxLength={2000}
              placeholder="Opsional. Catatan ini ikut disimpan pada approval immutable."
            />
          </label>

          <label className="mt-4 flex items-start gap-3 rounded-xl border border-emerald-400/20 bg-emerald-400/[0.045] p-4">
            <input
              className="mt-1"
              type="checkbox"
              name="confirmation"
            />
            <span className="text-sm leading-6 text-slate-300">
              Saya mengonfirmasi seluruh line sudah direview. Approval ini
              membuat snapshot immutable, tetapi belum memposting adjustment
              ke ledger.
            </span>
          </label>

          <button
            className="mt-4 rounded-xl border border-emerald-400/35 bg-emerald-400/15 px-4 py-2.5 text-sm font-semibold text-emerald-100 transition hover:bg-emerald-400/20"
            type="submit"
          >
            Setujui stocktake
          </button>
        </form>
      )}
    </section>
  );
}

function ApprovalAudit({
  details,
  reviewLines,
  approval,
  approvalLines,
}: {
  details: StocktakeDetails;
  reviewLines: StocktakeReviewLine[];
  approval: StocktakeApproval | null;
  approvalLines: StocktakeApprovalLine[];
}) {
  if (!approval) {
    return (
      <section className="panel-card mt-8 border-rose-400/20">
        <p className="section-kicker text-rose-300">Approval contract error</p>
        <h2 className="section-title">Approval aktif tidak ditemukan.</h2>
        <p className="mt-3 text-sm leading-6 text-slate-400">
          Status sesi sudah {details.status_code}, tetapi view approval tidak
          mengembalikan snapshot. Jangan lanjut ke posting sebelum kontrak ini
          diperiksa.
        </p>
      </section>
    );
  }

  const identityByLine = new Map(
    reviewLines.map((line) => [line.stocktake_line_id, line]),
  );

  return (
    <section className="mt-8">
      <div className="panel-card">
        <p className="section-kicker">Immutable approval audit</p>
        <h2 className="section-title">
          Approval version {formatNumber(approval.approval_version_no)}
        </h2>
        <p className="mt-3 text-sm leading-6 text-slate-400">
          Snapshot ini read-only. Preview dan posting adjustment harus
          memakai approval version ini, bukan data form review yang dapat
          berubah.
        </p>

        <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <div className="metric-card">
            <p className="metric-label">Line</p>
            <p className="metric-value">
              {formatNumber(approval.line_count)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Variance line</p>
            <p className="metric-value">
              {formatNumber(approval.variance_line_count)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Total variance</p>
            <p className="metric-value">
              {formatNumber(approval.total_variance_qty)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Stocktake version snapshot</p>
            <p className="metric-value">
              {formatNumber(approval.stocktake_version_no)}
            </p>
          </div>
        </div>

        <dl className="mt-5 grid gap-3 text-sm lg:grid-cols-2">
          <div className="rounded-xl border border-white/10 p-4">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Approval ID
            </dt>
            <dd className="mt-2 break-all font-mono text-slate-200">
              {approval.approval_id}
            </dd>
          </div>
          <div className="rounded-xl border border-white/10 p-4">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Approved at
            </dt>
            <dd className="mt-2 text-slate-200">
              {formatDateTime(approval.approved_at)}
            </dd>
          </div>
          <div className="rounded-xl border border-white/10 p-4">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Actor
            </dt>
            <dd className="mt-2 break-all font-mono text-slate-200">
              {approval.approved_by ??
                approval.process_name ??
                "Tidak diketahui"}
            </dd>
          </div>
          <div className="rounded-xl border border-white/10 p-4">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Snapshot ledger seq
            </dt>
            <dd className="mt-2 text-slate-200">
              {formatNumber(approval.snapshot_ledger_seq)}
            </dd>
          </div>
          <div className="rounded-xl border border-white/10 p-4 lg:col-span-2">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Approval hash
            </dt>
            <dd className="mt-2 break-all font-mono text-xs text-emerald-200">
              {approval.approval_hash}
            </dd>
          </div>
        </dl>

        {approval.note ? (
          <div className="mt-5 rounded-xl border border-white/10 p-4">
            <p className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Catatan approval
            </p>
            <p className="mt-2 text-sm leading-6 text-slate-300">
              {approval.note}
            </p>
          </div>
        ) : null}
      </div>

      <div className="panel-card mt-5 overflow-x-auto">
        <table className="min-w-[1180px]">
          <thead>
            <tr>
              <th>Line</th>
              <th>Identity</th>
              <th>Bucket</th>
              <th>Decision</th>
              <th>Physical</th>
              <th>Expected</th>
              <th>Variance</th>
              <th>Reason</th>
              <th>Line version</th>
              <th>Cutoff</th>
              <th>Catatan</th>
            </tr>
          </thead>
          <tbody>
            {approvalLines.map((line) => {
              const identity = identityByLine.get(
                line.stocktake_line_id,
              );

              return (
                <tr key={line.approval_line_id}>
                  <td>{formatNumber(line.line_no)}</td>
                  <td>
                    <p className="font-medium text-slate-200">
                      {identity
                        ? `${identity.product_sku_snapshot} / ${identity.product_name_snapshot}`
                        : line.stocktake_line_id}
                    </p>
                    {identity ? (
                      <p className="mt-1 text-xs text-slate-500">
                        Batch {identity.batch_code_snapshot} / Expiry{" "}
                        {identity.expiry_date_snapshot}
                      </p>
                    ) : null}
                  </td>
                  <td>
                    {identity
                      ? STOCKTAKE_BUCKET_LABELS[identity.bucket_code]
                      : "-"}
                  </td>
                  <td>{line.review_decision_code}</td>
                  <td>{formatNumber(line.final_physical_qty)}</td>
                  <td>{formatNumber(line.expected_qty_at_count)}</td>
                  <td>{formatNumber(line.variance_qty)}</td>
                  <td>
                    {line.reason_code
                      ? STOCKTAKE_VARIANCE_REASON_LABELS[
                          line.reason_code
                        ]
                      : "-"}
                  </td>
                  <td>{formatNumber(line.line_version_no)}</td>
                  <td>
                    {formatNumber(line.count_cutoff_ledger_seq)}
                  </td>
                  <td>{line.review_note ?? "-"}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}

export default function ApprovalPanel({
  details,
  reviewLines,
  approval = null,
  approvalLines = [],
}: {
  details: StocktakeDetails;
  reviewLines: StocktakeReviewLine[];
  approval?: StocktakeApproval | null;
  approvalLines?: StocktakeApprovalLine[];
}) {
  if (details.status_code === "REVIEW") {
    return (
      <ReviewApprovalForm
        details={details}
        reviewLines={reviewLines}
      />
    );
  }

  return (
    <ApprovalAudit
      details={details}
      reviewLines={reviewLines}
      approval={approval}
      approvalLines={approvalLines}
    />
  );
}
