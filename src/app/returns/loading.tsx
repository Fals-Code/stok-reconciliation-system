export default function ReturnsLoading() {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-7xl space-y-5" aria-busy="true" aria-label="Memuat return workflow">
        <div className="h-8 w-64 animate-pulse rounded bg-white/10" />
        <div className="h-32 animate-pulse rounded-3xl bg-white/5" />
        <div className="grid gap-5 lg:grid-cols-2"><div className="h-80 animate-pulse rounded-3xl bg-white/5" /><div className="h-80 animate-pulse rounded-3xl bg-white/5" /></div>
      </section>
    </main>
  );
}
