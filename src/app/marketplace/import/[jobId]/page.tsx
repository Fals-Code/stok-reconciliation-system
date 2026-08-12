import { randomUUID } from "node:crypto";
import Link from "next/link";
import { notFound } from "next/navigation";
import { commitMarketplaceCsvImportAction } from "../actions";
import { AppShell } from "@/app/app-shell/app-shell";
import { requireAdminSession } from "@/lib/auth";
import { getMarketplaceCsvImportEventResults, getMarketplaceCsvImportJob, getMarketplaceCsvImportRows } from "@/lib/csv-import/server";
import { safeMarketplaceCsvCommitErrorCode } from "@/lib/csv-import/safe-errors";

export const dynamic = "force-dynamic";

const statusLabel: Record<string, string> = { UPLOADED: "Diunggah", VALIDATING: "Memvalidasi", READY: "Siap dikonfirmasi", VALIDATION_FAILED: "Validasi gagal", COMMITTING: "Sedang diposting", COMPLETED: "Selesai", COMMIT_FAILED: "Posting gagal", CANCELLED: "Dibatalkan" };
const commitErrorMessage: Record<string, string> = {
  CSV_IMPORT_COMMIT_FAILED: "Posting belum berhasil. Periksa kembali preview atau coba lagi.",
  CSV_IMPORT_COMMIT_CONFIRMATION_REQUIRED: "Konfirmasi eksplisit diperlukan sebelum posting.",
  CSV_IMPORT_COMMIT_KEY_INVALID: "Permintaan posting tidak valid. Muat ulang halaman lalu coba lagi.",
  CSV_IMPORT_COMMIT_STATE_INVALID: "Job belum berada pada status yang dapat diposting.",
  CSV_IMPORT_COMMIT_IN_PROGRESS: "Posting job masih diproses.",
  CSV_IMPORT_COMMIT_FAILED_REPLAY: "Posting sebelumnya gagal dan belum dapat diulang dengan permintaan yang sama.",
  CSV_IMPORT_ALREADY_COMPLETED: "Job ini sudah selesai diposting.",
  CSV_IMPORT_BLOCKING_ROWS: "Masih ada row yang memerlukan perbaikan.",
  CSV_IMPORT_NO_ROWS: "Job tidak memiliki row yang dapat diproses.",
  CSV_IMPORT_JOB_NOT_FOUND: "Job import tidak ditemukan.",
  CSV_EXTERNAL_EVENT_CONFLICT: "External event memiliki payload yang berbeda.",
  CSV_EXTERNAL_EVENT_ALREADY_EXISTS: "External event sudah ada pada sistem.",
  IDEMPOTENCY_KEY_REUSED: "Permintaan sebelumnya memakai key yang sama dengan payload berbeda.",
};
function formatDate(value: string | null) { return value ? new Intl.DateTimeFormat("id-ID", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "-"; }
function previewText(value: Record<string, unknown> | null) {
  if (!value) return "-";
  const components = Array.isArray(value.components) ? value.components : [];
  return components.map((item) => { const row = item as Record<string, unknown>; return `${row.productSku ?? row.productId ?? "produk"} × ${row.quantity ?? "?"}`; }).join(", ") || String(value.listingType ?? "mapping tersedia");
}

export default async function CsvImportDetailPage({ params, searchParams }: { params: Promise<{ jobId: string }>; searchParams: Promise<{ status?: string; commit?: string; commitError?: string; rowStatus?: string; cursor?: string }> }) {
  const [{ jobId }, query, session] = await Promise.all([
    params,
    searchParams,
    requireAdminSession(),
  ]);
  let job: Awaited<ReturnType<typeof getMarketplaceCsvImportJob>>;

  try {
    job = await getMarketplaceCsvImportJob(jobId);
  } catch {
    return (
      <AppShell profile={session.profile}>
        <div className="min-h-screen bg-slate-950 px-5 py-10 text-slate-100">
        <section className="mx-auto max-w-3xl rounded-3xl border border-rose-400/20 bg-rose-400/[0.06] p-7">
          <h1 className="text-2xl font-semibold">Detail import belum dapat dimuat</h1>
          <p className="mt-3 text-sm leading-6 text-rose-100/80">
            Tidak ada event atau stok yang diubah. Muat ulang halaman untuk mencoba lagi.
          </p>
          <Link className="nav-link mt-6 inline-flex" href="/marketplace/import">
            Kembali ke Import CSV
          </Link>
        </section>
        </div>
      </AppShell>
    );
  }

  if (!job) notFound();
  let rows: Awaited<ReturnType<typeof getMarketplaceCsvImportRows>>;
  let events: Awaited<ReturnType<typeof getMarketplaceCsvImportEventResults>>;

  try {
    rows = await getMarketplaceCsvImportRows(jobId, 50, query.cursor ? Number(query.cursor) : null, query.rowStatus ?? null);
    events = job.status_code === "COMPLETED" ? await getMarketplaceCsvImportEventResults(jobId, 100) : { rows: [], nextCursor: null, hasMore: false };
  } catch {
    return (
      <AppShell profile={session.profile}>
        <div className="min-h-screen bg-slate-950 px-5 py-10 text-slate-100">
        <section className="mx-auto max-w-3xl rounded-3xl border border-rose-400/20 bg-rose-400/[0.06] p-7">
          <h1 className="text-2xl font-semibold">Preview import belum dapat dimuat</h1>
          <p className="mt-3 text-sm leading-6 text-rose-100/80">
            Job tetap tersimpan dan belum diposting ulang. Muat ulang halaman untuk mencoba lagi.
          </p>
          <Link className="nav-link mt-6 inline-flex" href="/marketplace/import">
            Kembali ke Import CSV
          </Link>
        </section>
        </div>
      </AppShell>
    );
  }

  const commitKey = `csv-ui:${jobId}:${randomUUID()}`;
  const canCommit = job.status_code === "READY" || job.status_code === "COMMIT_FAILED";
  const commitErrorCode = query.commitError ? safeMarketplaceCsvCommitErrorCode(query.commitError) : null;
  return (
    <AppShell profile={session.profile}>
      <div className="min-h-screen bg-slate-950 text-slate-100"><div className="mx-auto w-full max-w-[1500px] px-5 py-8 lg:px-8">
      <Link className="nav-link inline-flex" href="/marketplace/import">← Kembali ke Import CSV</Link>
      <header className="mt-6 flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between"><div><p className="section-kicker">CSV Import / Detail Job</p><h1 className="mt-3 text-3xl font-semibold">{job.original_file_name}</h1><p className="mt-2 font-mono text-xs text-slate-500">{job.id} · {job.template_version}</p></div><span className="status-pill status-success">{statusLabel[job.status_code] ?? job.status_code}</span></header>
      {query.commit ? <div className="mt-6 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 p-4 text-sm text-emerald-100">Permintaan commit: {query.commit}</div> : null}
      {commitErrorCode ? <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/10 p-4 text-sm text-rose-100">Commit belum selesai: {commitErrorMessage[commitErrorCode] ?? commitErrorMessage.CSV_IMPORT_COMMIT_FAILED}</div> : null}
      <section className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4"><div className="metric-card"><p className="metric-label">Rows</p><p className="metric-value">{job.row_count}</p><p className="metric-detail">{job.valid_row_count} valid · {job.invalid_row_count} invalid</p></div><div className="metric-card"><p className="metric-label">Duplicate / conflict</p><p className="metric-value">{job.duplicate_row_count} / {job.conflict_row_count}</p><p className="metric-detail">Tidak ada partial acceptance</p></div><div className="metric-card"><p className="metric-label">Expansion</p><p className="metric-value">{job.expanded_line_count}</p><p className="metric-detail">Canonical line preview</p></div><div className="metric-card"><p className="metric-label">File</p><p className="metric-value text-lg">{Math.round(job.file_size_bytes / 1024)} KB</p><p className="metric-detail">{job.detected_mime}</p></div></section>
      <section className="panel-card mt-6"><div className="flex flex-wrap items-end justify-between gap-3"><div><p className="section-kicker">Preview canonical</p><h2 className="section-title">Rows dan error per baris</h2></div><a className="nav-link" href={`/marketplace/import/${job.id}/errors`}>Unduh error report</a></div><form method="get" className="mt-5 flex flex-wrap items-end gap-3"><label className="field-label">Status row<select name="rowStatus" defaultValue={query.rowStatus ?? ""}><option value="">Semua</option><option value="VALID">Valid</option><option value="INVALID">Invalid</option><option value="DUPLICATE">Duplicate</option><option value="CONFLICT">Conflict</option></select></label><button className="primary-button" type="submit">Filter row</button></form><div className="mt-5 overflow-x-auto rounded-2xl border border-white/10"><table className="min-w-[1200px] w-full text-left text-sm"><thead className="bg-white/[0.04] text-xs uppercase tracking-wide text-slate-500"><tr><th className="px-4 py-3">Row</th><th className="px-4 py-3">Event / order</th><th className="px-4 py-3">Mapping</th><th className="px-4 py-3">Status</th><th className="px-4 py-3">Errors</th></tr></thead><tbody className="divide-y divide-white/5">{rows.rows.map((row) => <tr key={row.id} className="align-top"><td className="px-4 py-4 font-mono text-xs">{row.row_number}</td><td className="px-4 py-4"><p className="text-slate-200">{row.external_event_ref ?? "-"}</p><p className="mt-1 text-xs text-slate-500">{String(row.normalized_row.external_order_ref ?? "-")}</p></td><td className="max-w-md px-4 py-4 text-xs text-slate-300">{previewText(row.expansion_preview)}</td><td className="px-4 py-4"><span className="status-pill status-neutral">{row.validation_status_code}</span></td><td className="max-w-lg px-4 py-4 text-xs text-amber-100">{row.validation_errors?.length ? <ul className="space-y-1">{row.validation_errors.map((item, index) => <li key={`${item.code}-${index}`}><span className="font-mono">{item.code}</span>: {item.message}<span className="block text-slate-500">{item.remediation}</span></li>)}</ul> : "Tidak ada error"}</td></tr>)}{rows.rows.length === 0 ? <tr><td colSpan={5} className="px-4 py-8 text-center text-slate-500">Tidak ada row pada filter ini.</td></tr> : null}</tbody></table></div><div className="mt-5 flex gap-2">{rows.nextCursor ? <Link className="primary-button" href={`/marketplace/import/${job.id}?${new URLSearchParams({ ...(query.rowStatus ? { rowStatus: query.rowStatus } : {}), cursor: String(rows.nextCursor) })}`}>Row berikutnya →</Link> : <span className="text-xs text-slate-500">Akhir daftar row</span>}</div></section>
      {canCommit ? <section className="panel-card mt-6 border-amber-400/20"><p className="section-kicker">Step 2</p><h2 className="section-title">Konfirmasi posting atomic</h2><p className="mt-3 text-sm leading-6 text-slate-400">Semua grouped event akan diproses dalam satu transaksi. Jika satu event gagal, seluruh batch rollback. Reservasi tetap stock-neutral; tidak ada direct write ke ledger.</p><form action={commitMarketplaceCsvImportAction} className="mt-5"><input type="hidden" name="jobId" value={job.id} /><input type="hidden" name="commitKey" value={commitKey} /><label className="flex items-start gap-3 text-sm text-slate-200"><input name="confirmation" type="checkbox" required /> Saya sudah memeriksa preview dan memahami bahwa commit akan membuat reservasi marketplace canonical.</label><button className="primary-button mt-5" type="submit">Konfirmasi dan proses semua event</button></form></section> : null}
      {job.status_code === "COMPLETED" ? <section className="panel-card mt-6"><p className="section-kicker">Commit result</p><h2 className="section-title">Referensi hasil canonical</h2><div className="mt-5 space-y-3">{events.rows.map((event) => <div key={event.id} className="rounded-xl border border-white/10 p-4 text-sm"><p className="font-mono text-emerald-300">{event.external_event_ref} · {event.status_code}</p><p className="mt-2 text-slate-300">Event {event.canonical_event_id} · Order {event.marketplace_order_id} · Normalisasi {event.normalization_event_id}</p></div>)}</div></section> : null}
      <p className="mt-6 text-xs text-slate-500">Uploaded: {formatDate(job.uploaded_at)} · Validated: {formatDate(job.validated_at)} · Committed: {formatDate(job.committed_at)}</p>
      </div></div>
    </AppShell>
  );
}
