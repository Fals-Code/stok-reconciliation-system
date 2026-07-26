export default function TodayControlCenterLoading() {
  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto w-full max-w-[1500px] animate-pulse px-5 py-8 lg:px-8">
        <div className="h-3 w-40 rounded bg-white/[0.08]" />
        <div className="mt-4 h-10 w-96 max-w-full rounded bg-white/[0.08]" />
        <div className="mt-3 h-5 w-full max-w-2xl rounded bg-white/[0.05]" />
        <div className="mt-8 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {[0, 1, 2, 3].map((item) => (
            <div key={item} className="h-28 rounded-2xl border border-white/[0.06] bg-white/[0.025]" />
          ))}
        </div>
        <div className="mt-8 h-80 rounded-2xl border border-white/[0.06] bg-white/[0.025]" />
      </div>
    </main>
  );
}
