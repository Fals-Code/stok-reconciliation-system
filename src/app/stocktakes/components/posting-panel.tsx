import Link from "next/link";

import { postStocktakeAdjustmentAction } from "@/app/stocktakes/actions";
import {
  STOCKTAKE_BUCKET_LABELS,
  STOCKTAKE_VARIANCE_REASON_LABELS,
} from "@/lib/stocktakes/constants";
import {
  buildStocktakeAdjustmentPreview,
  evaluateStocktakeApprovalSnapshot,
  evaluateStocktakePostingSnapshot,
  stocktakePostingIdempotencyKey,
  type StocktakeSnapshotIntegrity,
  type StocktakeSnapshotIntegrityIssue,
} from "@/lib/stocktakes/posting";
import type {
  StocktakeApproval,
  StocktakeApprovalLine,
  StocktakeCountAttempt,
  StocktakeDetails,
  StocktakePosting,
  StocktakePostingLine,
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

function metadataString(
  metadata: Record<string, unknown>,
  key: string,
) {
  const value = metadata[key];
  return typeof value === "string" ? value : null;
}

function adjustmentLabel(value: number) {
  if (value > 0) {
    return `Tambah ${formatNumber(value)}`;
  }

  if (value < 0) {
    return `Kurangi ${formatNumber(Math.abs(value))}`;
  }

  return "Tidak ada perubahan";
}

const SNAPSHOT_ISSUE_LABELS: Record<
  StocktakeSnapshotIntegrityIssue,
  string
> = {
  EMPTY_SNAPSHOT: "Header snapshot tidak memiliki line yang valid.",
  LINE_COUNT_MISMATCH:
    "Jumlah line yang dibaca tidak sama dengan header snapshot.",
  NONZERO_LINE_COUNT_MISMATCH:
    "Jumlah line nonzero tidak sama dengan header snapshot.",
  NET_ADJUSTMENT_MISMATCH:
    "Total net adjustment tidak sama dengan header snapshot.",
  ABSOLUTE_ADJUSTMENT_MISMATCH:
    "Total absolute adjustment tidak sama dengan header snapshot.",
  SNAPSHOT_IDENTITY_MISMATCH:
    "Ada line yang tidak terikat ke snapshot atau stocktake aktif.",
  DUPLICATE_LINE_IDENTITY:
    "Ada identitas line duplikat pada hasil read snapshot.",
};

function SnapshotContractError({
  title,
  description,
  integrity,
}: {
  title: string;
  description: string;
  integrity: StocktakeSnapshotIntegrity;
}) {
  return (
    <section className="panel-card mt-8 border-rose-400/20">
      <p className="section-kicker text-rose-300">
        Snapshot contract error
      </p>
      <h2 className="section-title">{title}</h2>
      <p className="mt-3 max-w-4xl text-sm leading-6 text-slate-400">
        {description}
      </p>

      <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <div className="metric-card">
          <p className="metric-label">Line header / read</p>
          <p className="metric-value">
            {formatNumber(integrity.expectedLineCount)} /{" "}
            {formatNumber(integrity.actualLineCount)}
          </p>
        </div>
        <div className="metric-card">
          <p className="metric-label">Nonzero header / read</p>
          <p className="metric-value">
            {formatNumber(integrity.expectedNonzeroLineCount)} /{" "}
            {formatNumber(integrity.actualNonzeroLineCount)}
          </p>
        </div>
        <div className="metric-card">
          <p className="metric-label">Net header / read</p>
          <p className="metric-value">
            {formatNumber(integrity.expectedNetAdjustmentQty)} /{" "}
            {formatNumber(integrity.actualNetAdjustmentQty)}
          </p>
        </div>
        <div className="metric-card">
          <p className="metric-label">Absolute read</p>
          <p className="metric-value">
            {formatNumber(integrity.actualTotalAbsoluteAdjustmentQty)}
          </p>
        </div>
      </div>

      <ul className="mt-5 space-y-2 text-sm text-rose-100">
        {integrity.issues.map((issue) => (
          <li
            key={issue}
            className="rounded-xl border border-rose-400/20 bg-rose-400/[0.055] px-4 py-3"
          >
            {SNAPSHOT_ISSUE_LABELS[issue]}
          </li>
        ))}
      </ul>

      <p className="mt-5 text-sm leading-6 text-slate-400">
        Muat ulang halaman. Jika masalah tetap muncul, periksa view audit.
        Jangan menjalankan posting pengganti atau mengubah saldo secara manual.
      </p>
    </section>
  );
}

function PostingPreview({
  details,
  reviewLines,
  approval,
  approvalLines,
}: {
  details: StocktakeDetails;
  reviewLines: StocktakeReviewLine[];
  approval: StocktakeApproval;
  approvalLines: StocktakeApprovalLine[];
}) {
  const snapshotIntegrity = evaluateStocktakeApprovalSnapshot(
    approval,
    approvalLines,
  );

  if (!snapshotIntegrity.isValid) {
    return (
      <SnapshotContractError
        title="Preview adjustment diblokir."
        description="Approval header dan line snapshot tidak konsisten. Form posting permanen tidak dirender sampai read contract kembali lengkap."
        integrity={snapshotIntegrity}
      />
    );
  }

  const preview = buildStocktakeAdjustmentPreview(approvalLines);
  const identityByLine = new Map(
    reviewLines.map((line) => [line.stocktake_line_id, line]),
  );
  const idempotencyKey = stocktakePostingIdempotencyKey(
    details.stocktake_id,
    approval.approval_version_no,
  );

  return (
    <section className="mt-8">
      <div className="panel-card border-amber-400/20">
        <p className="section-kicker text-amber-200">
          Atomic adjustment preview
        </p>
        <h2 className="section-title">
          Preview immutable sebelum ledger berubah.
        </h2>
        <p className="mt-3 max-w-4xl text-sm leading-6 text-slate-400">
          Preview ini dihitung dari approval snapshot version{" "}
          {formatNumber(approval.approval_version_no)}. Browser
          tidak mengirim adjustment quantity sebagai otoritas.
          Server akan memvalidasi kembali approval, basis line,
          projection, saldo negatif, dan reservasi sebelum posting.
        </p>

        <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <div className="metric-card">
            <p className="metric-label">Line positif</p>
            <p className="metric-value">
              {formatNumber(preview.positiveLineCount)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Line negatif</p>
            <p className="metric-value">
              {formatNumber(preview.negativeLineCount)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Line netral</p>
            <p className="metric-value">
              {formatNumber(preview.zeroLineCount)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Net adjustment</p>
            <p className="metric-value">
              {formatNumber(preview.netAdjustmentQty)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Units ditambah</p>
            <p className="metric-value">
              {formatNumber(preview.unitsAdded)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Units dikurangi</p>
            <p className="metric-value">
              {formatNumber(preview.unitsRemoved)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Absolute adjustment</p>
            <p className="metric-value">
              {formatNumber(
                preview.totalAbsoluteAdjustmentQty,
              )}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Approval hash</p>
            <p className="mt-3 break-all font-mono text-[11px] text-emerald-200">
              {approval.approval_hash}
            </p>
          </div>
        </div>

        <div className="mt-5 rounded-xl border border-white/10 p-4">
          <p className="text-xs uppercase tracking-[0.12em] text-slate-500">
            Reason distribution
          </p>
          {preview.reasonDistribution.length ? (
            <div className="mt-3 grid gap-3 md:grid-cols-2">
              {preview.reasonDistribution.map((reason) => (
                <div
                  key={reason.reasonCode}
                  className="rounded-xl border border-white/10 bg-slate-950/45 p-3"
                >
                  <p className="font-medium text-slate-200">
                    {
                      STOCKTAKE_VARIANCE_REASON_LABELS[
                        reason.reasonCode
                      ]
                    }
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    {formatNumber(reason.lineCount)} line /{" "}
                    {formatNumber(reason.totalAbsoluteQty)} unit
                  </p>
                </div>
              ))}
            </div>
          ) : (
            <p className="mt-3 text-sm text-slate-400">
              Tidak ada variance nonzero.
            </p>
          )}
        </div>
      </div>

      <div className="panel-card mt-5 overflow-x-auto">
        <table className="min-w-[1240px]">
          <thead>
            <tr>
              <th>Line</th>
              <th>Identity</th>
              <th>Bucket</th>
              <th>Physical</th>
              <th>Expected</th>
              <th>Variance</th>
              <th>Reason</th>
              <th>Proposed ledger effect</th>
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
                      ? STOCKTAKE_BUCKET_LABELS[
                          identity.bucket_code
                        ]
                      : "-"}
                  </td>
                  <td>
                    {formatNumber(line.final_physical_qty)}
                  </td>
                  <td>
                    {formatNumber(line.expected_qty_at_count)}
                  </td>
                  <td>{formatNumber(line.variance_qty)}</td>
                  <td>
                    {line.reason_code
                      ? STOCKTAKE_VARIANCE_REASON_LABELS[
                          line.reason_code
                        ]
                      : "-"}
                  </td>
                  <td>
                    <span
                      className={
                        line.variance_qty === 0
                          ? "text-slate-500"
                          : line.variance_qty > 0
                            ? "text-emerald-200"
                            : "text-rose-200"
                      }
                    >
                      {identity
                        ? `${adjustmentLabel(line.variance_qty)} pada ${STOCKTAKE_BUCKET_LABELS[identity.bucket_code]}`
                        : adjustmentLabel(line.variance_qty)}
                    </span>
                    {line.variance_qty === 0 ? (
                      <p className="mt-1 text-xs text-slate-600">
                        Tidak membuat ledger entry.
                      </p>
                    ) : null}
                  </td>
                  <td>{line.review_note ?? "-"}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <form
        action={postStocktakeAdjustmentAction}
        className="mt-5 rounded-2xl border border-rose-400/25 bg-rose-400/[0.055] p-5"
      >
        <input
          type="hidden"
          name="stocktakeId"
          value={details.stocktake_id}
        />
        <input
          type="hidden"
          name="approvalVersion"
          value={approval.approval_version_no}
        />

        <p className="text-lg font-semibold text-rose-100">
          Posting adjustment bersifat permanen.
        </p>
        <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-300">
          Server akan membuat satu transaksi
          STOCKTAKE_ADJUSTMENT, menambahkan ledger entry hanya
          untuk line nonzero, memperbarui projection secara
          atomik, dan menjalankan reconciliation POST_STOCKTAKE.
          Riwayat ledger lama tidak diedit.
        </p>

        <label className="mt-5 block">
          <span className="field-label">Catatan posting</span>
          <textarea
            className="mt-2 min-h-24 w-full rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-rose-400/50"
            name="note"
            maxLength={2000}
            placeholder="Opsional. Disimpan pada transaksi dan posting audit."
          />
        </label>

        <label className="mt-4 flex items-start gap-3 rounded-xl border border-rose-400/25 bg-slate-950/45 p-4">
          <input
            className="mt-1"
            type="checkbox"
            name="confirmation"
          />
          <span className="text-sm leading-6 text-slate-300">
            Saya memahami posting ini tidak mengedit ledger lama,
            tidak dapat diedit langsung setelah berhasil, dan akan
            memicu reconciliation otomatis.
          </span>
        </label>

        <div className="mt-4 rounded-xl border border-white/10 p-3">
          <p className="text-xs uppercase tracking-[0.12em] text-slate-500">
            Deterministic idempotency key
          </p>
          <p className="mt-2 break-all font-mono text-xs text-slate-300">
            {idempotencyKey}
          </p>
        </div>

        <button
          className="mt-4 rounded-xl border border-rose-300/35 bg-rose-400/15 px-4 py-2.5 text-sm font-semibold text-rose-100 transition hover:bg-rose-400/20"
          type="submit"
        >
          Posting adjustment ke ledger
        </button>
      </form>
    </section>
  );
}

function PostingInProgress() {
  return (
    <section className="panel-card mt-8 border-amber-400/20">
      <p className="section-kicker text-amber-200">
        Posting in progress
      </p>
      <h2 className="section-title">
        Server sedang memproses transaksi atomik.
      </h2>
      <p className="mt-3 text-sm leading-6 text-slate-400">
        Jangan mencoba membuat adjustment baru. Muat ulang halaman
        untuk membaca hasil final dari database.
      </p>
    </section>
  );
}

function PostedAudit({
  details,
  reviewLines,
  posting,
  postingLines,
  attempts,
}: {
  details: StocktakeDetails;
  reviewLines: StocktakeReviewLine[];
  posting: StocktakePosting | null;
  postingLines: StocktakePostingLine[];
  attempts: StocktakeCountAttempt[];
}) {
  if (!posting) {
    return (
      <section className="panel-card mt-8 border-rose-400/20">
        <p className="section-kicker text-rose-300">
          Posting contract error
        </p>
        <h2 className="section-title">
          Posting audit tidak ditemukan.
        </h2>
        <p className="mt-3 text-sm leading-6 text-slate-400">
          Status sesi sudah {details.status_code}, tetapi view
          posting tidak mengembalikan record. Jangan membuat
          transaksi pengganti secara manual.
        </p>
      </section>
    );
  }

  const snapshotIntegrity = evaluateStocktakePostingSnapshot(
    posting,
    postingLines,
  );

  if (!snapshotIntegrity.isValid) {
    return (
      <SnapshotContractError
        title="Audit posting tidak lengkap."
        description="Posting header dan line audit tidak konsisten. Hasil tidak boleh ditampilkan sebagai audit sukses sampai seluruh line dapat dibaca kembali."
        integrity={snapshotIntegrity}
      />
    );
  }

  const identityByLine = new Map(
    reviewLines.map((line) => [line.stocktake_line_id, line]),
  );
  const integrityStatus =
    metadataString(
      posting.metadata,
      "reconciliationIntegrityStatus",
    ) ?? "UNKNOWN";

  return (
    <section className="mt-8">
      <div className="panel-card border-emerald-400/20">
        <p className="section-kicker">Posted audit result</p>
        <h2 className="section-title">
          Adjustment berhasil diposting.
        </h2>
        <p className="mt-3 text-sm leading-6 text-slate-400">
          Data berikut dibaca kembali dari immutable posting views.
          Refresh halaman tidak bergantung pada state sementara
          Server Action.
        </p>

        <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <div className="metric-card">
            <p className="metric-label">Line</p>
            <p className="metric-value">
              {formatNumber(posting.line_count)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Nonzero line</p>
            <p className="metric-value">
              {formatNumber(posting.nonzero_line_count)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Net adjustment</p>
            <p className="metric-value">
              {formatNumber(posting.net_adjustment_qty)}
            </p>
          </div>
          <div className="metric-card">
            <p className="metric-label">Absolute adjustment</p>
            <p className="metric-value">
              {formatNumber(
                posting.total_absolute_adjustment_qty,
              )}
            </p>
          </div>
        </div>

        <dl className="mt-5 grid gap-3 text-sm lg:grid-cols-2">
          <div className="rounded-xl border border-white/10 p-4">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Posting ID
            </dt>
            <dd className="mt-2 break-all font-mono text-slate-200">
              {posting.posting_id}
            </dd>
          </div>
          <div className="rounded-xl border border-white/10 p-4">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Posted at
            </dt>
            <dd className="mt-2 text-slate-200">
              {formatDateTime(posting.posted_at)}
            </dd>
          </div>
          <div className="rounded-xl border border-white/10 p-4">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Transaction ID
            </dt>
            <dd className="mt-2 break-all font-mono text-slate-200">
              {posting.transaction_id}
            </dd>
          </div>
          <div className="rounded-xl border border-white/10 p-4">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Reconciliation
            </dt>
            <dd className="mt-2">
              <Link
                className="font-mono text-emerald-200 underline decoration-emerald-400/40 underline-offset-4"
                href={`/reconciliation?runId=${encodeURIComponent(posting.reconciliation_run_id)}#runs`}
              >
                {posting.reconciliation_run_id}
              </Link>
            </dd>
            <p className="mt-2 text-xs text-slate-500">
              Integrity: {integrityStatus}
            </p>
          </div>
          <div className="rounded-xl border border-white/10 p-4">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Ledger sequence
            </dt>
            <dd className="mt-2 text-slate-200">
              {formatNumber(
                posting.posting_ledger_seq_before,
              )}{" "}
              {"->"}{" "}
              {formatNumber(
                posting.posting_ledger_seq_after,
              )}
            </dd>
          </div>
          <div className="rounded-xl border border-white/10 p-4">
            <dt className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Approval version
            </dt>
            <dd className="mt-2 text-slate-200">
              {formatNumber(posting.approval_version_no)}
            </dd>
          </div>
        </dl>

        {posting.note ? (
          <div className="mt-5 rounded-xl border border-white/10 p-4">
            <p className="text-xs uppercase tracking-[0.12em] text-slate-500">
              Catatan posting
            </p>
            <p className="mt-2 text-sm leading-6 text-slate-300">
              {posting.note}
            </p>
          </div>
        ) : null}
      </div>

      <div className="panel-card mt-5 overflow-x-auto">
        <table className="min-w-[1320px]">
          <thead>
            <tr>
              <th>Line</th>
              <th>Identity</th>
              <th>Bucket</th>
              <th>Adjustment</th>
              <th>Ledger before</th>
              <th>Ledger after</th>
              <th>Reason</th>
              <th>Ledger entry</th>
            </tr>
          </thead>
          <tbody>
            {postingLines.map((line) => {
              const identity = identityByLine.get(
                line.stocktake_line_id,
              );

              return (
                <tr key={line.posting_line_id}>
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
                    {STOCKTAKE_BUCKET_LABELS[line.bucket_code]}
                  </td>
                  <td>{formatNumber(line.adjustment_qty)}</td>
                  <td>
                    {formatNumber(
                      line.current_ledger_qty_before,
                    )}
                  </td>
                  <td>
                    {formatNumber(
                      line.current_ledger_qty_after,
                    )}
                  </td>
                  <td>
                    {line.reason_code
                      ? STOCKTAKE_VARIANCE_REASON_LABELS[
                          line.reason_code
                        ]
                      : "Stock-neutral"}
                  </td>
                  <td>
                    {line.ledger_entry_id ? (
                      <span className="break-all font-mono text-xs text-emerald-200">
                        {line.ledger_entry_id}
                      </span>
                    ) : (
                      <span className="text-slate-500">
                        Tidak ada ledger entry
                      </span>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <details className="panel-card mt-5">
        <summary className="cursor-pointer font-semibold text-slate-200">
          Riwayat seluruh count attempt ({formatNumber(attempts.length)})
        </summary>
        <div className="mt-4 overflow-x-auto">
          <table className="min-w-[1100px]">
            <thead>
              <tr>
                <th>Line</th>
                <th>Attempt</th>
                <th>Physical</th>
                <th>Expected</th>
                <th>Variance</th>
                <th>Cutoff</th>
                <th>Method</th>
                <th>Counted at</th>
                <th>Note</th>
              </tr>
            </thead>
            <tbody>
              {attempts.map((attempt) => {
                const identity = identityByLine.get(
                  attempt.stocktake_line_id,
                );

                return (
                  <tr key={attempt.count_attempt_id}>
                    <td>
                      {identity
                        ? `${identity.line_no} / ${identity.product_sku_snapshot} / ${identity.batch_code_snapshot}`
                        : attempt.stocktake_line_id}
                    </td>
                    <td>{formatNumber(attempt.attempt_no)}</td>
                    <td>{formatNumber(attempt.physical_qty)}</td>
                    <td>
                      {formatNumber(
                        attempt.expected_qty_at_count,
                      )}
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
                );
              })}
            </tbody>
          </table>
        </div>
      </details>
    </section>
  );
}

export default function PostingPanel({
  details,
  reviewLines,
  approval,
  approvalLines,
  posting = null,
  postingLines = [],
  attempts = [],
}: {
  details: StocktakeDetails;
  reviewLines: StocktakeReviewLine[];
  approval: StocktakeApproval | null;
  approvalLines: StocktakeApprovalLine[];
  posting?: StocktakePosting | null;
  postingLines?: StocktakePostingLine[];
  attempts?: StocktakeCountAttempt[];
}) {
  if (details.status_code === "APPROVED") {
    if (!approval) {
      return (
        <section className="panel-card mt-8 border-rose-400/20">
          <p className="section-kicker text-rose-300">
            Approval contract error
          </p>
          <h2 className="section-title">
            Preview tidak dapat dibangun.
          </h2>
          <p className="mt-3 text-sm text-slate-400">
            Immutable approval snapshot tidak ditemukan.
          </p>
        </section>
      );
    }

    return (
      <PostingPreview
        details={details}
        reviewLines={reviewLines}
        approval={approval}
        approvalLines={approvalLines}
      />
    );
  }

  if (details.status_code === "POSTING") {
    return <PostingInProgress />;
  }

  return (
    <PostedAudit
      details={details}
      reviewLines={reviewLines}
      posting={posting}
      postingLines={postingLines}
      attempts={attempts}
    />
  );
}