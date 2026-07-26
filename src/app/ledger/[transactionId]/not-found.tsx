import Link from "next/link";

export default function LedgerTransactionNotFound() {
  return (
    <main className="mx-auto max-w-3xl px-5 py-16 text-slate-100">
      <section className="rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="section-kicker">Ledger / Not found</p>
        <h1 className="mt-3 text-3xl font-semibold">Transaction tidak ditemukan.</h1>
        <p className="mt-4 text-sm leading-6 text-slate-300">ID tidak valid atau transaction berada di organisasi lain. Tidak ada fallback ke transaction lain.</p>
        <Link className="nav-link mt-6 inline-flex" href="/ledger">Kembali ke Ledger Explorer</Link>
      </section>
    </main>
  );
}
