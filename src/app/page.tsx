const foundations = [
  {
    title: "Stock ledger",
    description: "Setiap perubahan jumlah barang harus memiliki jejak transaksi.",
  },
  {
    title: "Batch dan FEFO",
    description: "Batch dengan kedaluwarsa terdekat dialokasikan lebih dahulu.",
  },
  {
    title: "Rekonsiliasi",
    description: "Selisih stok dijelaskan sampai ke pergerakan pembentuknya.",
  },
];

const roadmap = [
  "Fondasi Next.js dan TypeScript",
  "Skema database, migration, dan RLS",
  "Produk, batch, penerimaan, dan stock ledger",
  "Marketplace simulator, retur, opname, dan rekonsiliasi",
];

export default function Home() {
  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <section className="mx-auto flex min-h-screen w-full max-w-6xl flex-col justify-center px-6 py-16 sm:px-10 lg:px-12">
        <div className="mb-10 inline-flex w-fit items-center gap-2 rounded-full border border-emerald-400/20 bg-emerald-400/10 px-3 py-1 text-sm text-emerald-300">
          <span
            className="h-2 w-2 rounded-full bg-emerald-400"
            aria-hidden="true"
          />
          Fondasi aplikasi siap
        </div>

        <div className="grid gap-12 lg:grid-cols-[1.35fr_0.65fr] lg:items-end">
          <div>
            <p className="mb-4 font-mono text-sm uppercase tracking-[0.22em] text-slate-400">
              Stok reconciliation system
            </p>
            <h1 className="max-w-4xl text-4xl font-semibold tracking-tight text-white sm:text-6xl">
              Tidak ada angka stok yang berubah tanpa jejak.
            </h1>
            <p className="mt-6 max-w-2xl text-base leading-7 text-slate-300 sm:text-lg">
              Sistem pencatatan dan rekonsiliasi stok untuk menelusuri barang
              masuk, reservasi, pengeluaran, pembatalan, retur, dan koreksi
              stok sampai ke sumber transaksinya.
            </p>
          </div>

          <aside className="rounded-2xl border border-white/10 bg-white/[0.04] p-6">
            <p className="text-sm font-medium text-slate-400">Stack fase awal</p>
            <dl className="mt-5 space-y-4 text-sm">
              <div className="flex justify-between gap-4">
                <dt className="text-slate-400">Frontend</dt>
                <dd className="font-medium text-white">Next.js + TypeScript</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-slate-400">Database</dt>
                <dd className="font-medium text-white">Supabase Postgres</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-slate-400">Model akses</dt>
                <dd className="font-medium text-white">Admin</dd>
              </div>
            </dl>
          </aside>
        </div>

        <div className="mt-16 grid gap-4 md:grid-cols-3">
          {foundations.map((item) => (
            <article
              key={item.title}
              className="rounded-2xl border border-white/10 bg-white/[0.03] p-6"
            >
              <h2 className="text-lg font-semibold text-white">{item.title}</h2>
              <p className="mt-3 text-sm leading-6 text-slate-400">
                {item.description}
              </p>
            </article>
          ))}
        </div>

        <section className="mt-12 rounded-2xl border border-white/10 bg-slate-900/70 p-6 sm:p-8">
          <div className="flex flex-col gap-6 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <p className="text-sm font-medium text-emerald-300">
                Roadmap implementasi
              </p>
              <h2 className="mt-2 text-2xl font-semibold text-white">
                Bangun logika stok sebelum mempercantik dashboard.
              </h2>
            </div>
            <span className="w-fit rounded-full bg-white/10 px-3 py-1 font-mono text-xs text-slate-300">
              v0.1.0
            </span>
          </div>

          <ol className="mt-8 grid gap-4 md:grid-cols-2">
            {roadmap.map((item, index) => (
              <li
                key={item}
                className="flex gap-4 rounded-xl bg-white/[0.03] p-4"
              >
                <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-emerald-400/15 font-mono text-xs text-emerald-300">
                  {index + 1}
                </span>
                <span className="pt-1 text-sm text-slate-300">{item}</span>
              </li>
            ))}
          </ol>
        </section>
      </section>
    </main>
  );
}
