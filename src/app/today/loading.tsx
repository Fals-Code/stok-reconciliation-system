export default function TodayControlCenterLoading() {
  return (
    <main className="min-h-screen bg-ui-canvas text-ui-text">
      <div className="mx-auto w-full max-w-[1500px] animate-pulse px-5 py-8 lg:px-8">
        <div className="h-8 w-48 rounded bg-ui-border" />
        <div className="mt-4 h-6 w-96 max-w-full rounded bg-ui-border" />
        <div className="mt-3 h-4 w-full max-w-2xl rounded bg-ui-border" />
        <div className="mt-8 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {[0, 1, 2, 3].map((item) => (
            <div key={item} className="h-24 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface" />
          ))}
        </div>
        <div className="mt-8 h-64 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface" />
      </div>
    </main>
  );
}
