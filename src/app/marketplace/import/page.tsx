import Link from "next/link";
import { stageMarketplaceCsvAction } from "./actions";
import { getMarketplaceCsvImportJobs } from "@/lib/csv-import/server";

export const dynamic = "force-dynamic";

const statusLabel: Record<string, string> = {
  UPLOADED: "Diunggah",
  VALIDATING: "Memvalidasi",
  READY: "Siap dikonfirmasi",
  VALIDATION_FAILED: "Validasi gagal",
  COMMITTING: "Sedang diposting",
  COMPLETED: "Selesai",
  COMMIT_FAILED: "Posting gagal",
  CANCELLED: "Dibatalkan",
};

export default async function CsvImportPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const query = await searchParams;
  const data = await getMarketplaceCsvImportJobs();
  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto w-full max-w-[1400px] px-5 py-8 lg:px-8">
        <header className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="section-kicker">Marketplace / Import CSV</p>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">Import reservasi marketplace</h1>
            <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">CSV v1 hanya menjadi adapter ORDER/RESERVE. Preview tidak mengubah stok; posting selalu membutuhkan konfirmasi eksplisit dan memakai boundary canonical yang sama dengan simulator.</p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Link className="nav-link" href="/marketplace/import/template">Unduh template CSV v1</Link>
            <span className="status-pill status-success">Read-only sampai konfirmasi</span>
          </div>
        </header>

        {query.error ? <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/10 p-4 text-sm text-rose-100" role="alert">Import belum dibuat: {query.error}</div> : null}

        <section className="panel-card mt-8" aria-labelledby="upload-title">
          <p className="section-kicker">Step 1</p>
          <h2 id="upload-title" className="section-title">Unggah dan validasi</h2>
          <form action={stageMarketplaceCsvAction} encType="multipart/form-data" className="mt-5 flex flex-col gap-4 sm:flex-row sm:items-end">
            <label className="field-label flex-1">File CSV v1<input name="file" type="file" accept=".csv,text/csv" required /></label>
            <button className="primary-button" type="submit">Unggah untuk preview</button>
          </form>
          <p className="mt-3 text-xs text-slate-500">Batas 10 MB. File privat, path dibuat server, dan organization diambil dari profil Admin aktif.</p>
        </section>

        <section className="panel-card mt-8" aria-labelledby="jobs-title">
          <div className="flex flex-wrap items-end justify-between gap-3"><div><p className="section-kicker">Riwayat import</p><h2 id="jobs-title" className="section-title">Job CSV organisasi ini</h2></div><p className="text-xs text-slate-500">Urutan terbaru terlebih dahulu.</p></div>
          <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10">
            <table className="min-w-[920px] w-full text-left text-sm"><thead className="bg-white/[0.04] text-xs uppercase tracking-wide text-slate-500"><tr><th className="px-4 py-3">File</th><th className="px-4 py-3">Status</th><th className="px-4 py-3">Rows</th><th className="px-4 py-3">Valid / invalid</th><th className="px-4 py-3">Dibuat</th><th className="px-4 py-3" /></tr></thead><tbody className="divide-y divide-white/5">
              {data.rows.map((job) => <tr key={job.id}><td className="px-4 py-4"><p className="font-medium text-white">{job.original_file_name}</p><p className="mt-1 font-mono text-xs text-slate-500">{job.template_version}</p></td><td className="px-4 py-4"><span className="status-pill status-neutral">{statusLabel[job.status_code] ?? job.status_code}</span></td><td className="px-4 py-4 text-slate-300">{job.row_count}</td><td className="px-4 py-4 text-slate-300">{job.valid_row_count} / {job.invalid_row_count}</td><td className="px-4 py-4 text-xs text-slate-400">{new Date(job.created_at).toLocaleString("id-ID")}</td><td className="px-4 py-4"><Link className="text-emerald-300 underline underline-offset-4" href={`/marketplace/import/${job.id}`}>Buka detail</Link></td></tr>)}
              {data.rows.length === 0 ? <tr><td colSpan={6} className="px-4 py-8 text-center text-slate-500">Belum ada import.</td></tr> : null}
            </tbody></table>
          </div>
        </section>
      </div>
    </main>
  );
}
