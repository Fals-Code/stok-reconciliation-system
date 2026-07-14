import {
  completeStocktakeCountingAction,
  requestStocktakeRecountAction,
  submitStocktakeCountAction,
} from "@/app/stocktakes/actions";
import {
  STOCKTAKE_BUCKET_LABELS,
  STOCKTAKE_COUNT_STATUS_META,
  type StocktakePillTone,
} from "@/lib/stocktakes/constants";
import type {
  StocktakeCountingLine,
  StocktakeDetails,
  StocktakeListItem,
  StocktakeNonBlindLine,
} from "@/lib/stocktakes/types";

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number | null) {
  return value === null ? "Belum ada" : numberFormatter.format(Number(value));
}

function formatDate(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
  }).format(date);
}

function isNonBlindLine(
  line: StocktakeCountingLine,
): line is StocktakeNonBlindLine {
  return "system_qty_at_snapshot" in line;
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

function CountForm({
  stocktakeId,
  line,
}: {
  stocktakeId: string;
  line: StocktakeCountingLine;
}) {
  const isRecount = line.count_status_code === "RECOUNT_REQUESTED";

  return (
    <form
      action={submitStocktakeCountAction}
      className="mt-5 rounded-2xl border border-white/10 bg-slate-950/45 p-4"
    >
      <input type="hidden" name="stocktakeId" value={stocktakeId} />
      <input
        type="hidden"
        name="stocktakeLineId"
        value={line.stocktake_line_id}
      />
      <input
        type="hidden"
        name="attemptNo"
        value={line.count_attempt_no}
      />

      <div className="grid gap-4 lg:grid-cols-[minmax(0,14rem)_1fr]">
        <label>
          <span className="field-label">Quantity fisik</span>
          <input
            className="mt-2 w-full rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-emerald-400/50"
            type="number"
            name="physicalQty"
            min="0"
            step="1"
            inputMode="numeric"
            required
          />
        </label>

        <label>
          <span className="field-label">Catatan count</span>
          <textarea
            className="mt-2 min-h-20 w-full rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-emerald-400/50"
            name="note"
            maxLength={2000}
            placeholder="Opsional, misalnya kondisi kemasan atau lokasi fisik."
          />
        </label>
      </div>

      <label className="mt-4 flex items-start gap-3 rounded-xl border border-white/10 p-3">
        <input className="mt-1" type="checkbox" name="zeroConfirmed" />
        <span>
          <span className="text-sm font-medium text-slate-200">
            Konfirmasi quantity fisik benar-benar nol
          </span>
          <span className="mt-1 block text-xs leading-5 text-slate-500">
            Wajib dicentang hanya ketika quantity yang dimasukkan adalah 0.
            Kolom kosong tidak pernah dianggap nol.
          </span>
        </span>
      </label>

      <button className="primary-button mt-4" type="submit">
        {isRecount ? "Simpan hasil hitung ulang" : "Simpan hasil hitung"}
      </button>
    </form>
  );
}

function RecountForm({
  stocktakeId,
  line,
}: {
  stocktakeId: string;
  line: StocktakeCountingLine;
}) {
  return (
    <details className="mt-4 rounded-xl border border-white/10 bg-slate-950/35 p-4">
      <summary className="cursor-pointer text-sm font-semibold text-amber-100">
        Minta hitung ulang
      </summary>

      <form action={requestStocktakeRecountAction} className="mt-4">
        <input type="hidden" name="stocktakeId" value={stocktakeId} />
        <input
          type="hidden"
          name="stocktakeLineId"
          value={line.stocktake_line_id}
        />
        <input
          type="hidden"
          name="attemptNo"
          value={line.count_attempt_no}
        />

        <label>
          <span className="field-label">Alasan recount</span>
          <textarea
            className="mt-2 min-h-24 w-full rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-amber-400/50"
            name="reason"
            maxLength={2000}
            required
            placeholder="Jelaskan mengapa count perlu diverifikasi ulang."
          />
        </label>

        <button
          className="mt-4 rounded-xl border border-amber-400/30 bg-amber-400/10 px-4 py-2.5 text-sm font-semibold text-amber-100 transition hover:bg-amber-400/15"
          type="submit"
        >
          Tandai perlu hitung ulang
        </button>
      </form>
    </details>
  );
}

export default function CountingPanel({
  details,
  summary,
  lines,
}: {
  details: StocktakeDetails;
  summary: StocktakeListItem | null;
  lines: StocktakeCountingLine[];
}) {
  const countedLineCount = lines.filter(
    (line) => line.count_status_code === "COUNTED",
  ).length;
  const lineCount = lines.length;
  const canComplete = lineCount > 0 && countedLineCount === lineCount;
  const isBlind = details.visibility_code === "BLIND";

  return (
    <section className="mt-8">
      <div className="panel-card">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="section-kicker">Counting</p>
            <h2 className="section-title">
              {isBlind ? "Blind physical count." : "Non-blind physical count."}
            </h2>
            <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
              Setiap submit membuat count attempt append-only. Recount tidak
              menimpa attempt sebelumnya, dan tidak satu pun tindakan counting
              mengubah ledger atau saldo projection.
            </p>
          </div>

          <div className="rounded-2xl border border-white/10 bg-slate-950/45 px-5 py-4">
            <p className="text-xs uppercase tracking-[0.14em] text-slate-500">
              Progress
            </p>
            <p className="mt-2 text-2xl font-semibold text-white">
              {formatNumber(countedLineCount)} / {formatNumber(lineCount)}
            </p>
          </div>
        </div>

        {isBlind ? (
          <div className="mt-5 rounded-xl border border-sky-400/20 bg-sky-400/[0.06] p-4 text-sm leading-6 text-sky-100">
            Expected quantity, variance, snapshot quantity, dan attempt history
            tidak diambil dari database selama sesi BLIND masih berada pada
            COUNTING.
          </div>
        ) : null}
      </div>

      <div className="mt-5 space-y-4">
        {lines.map((line) => {
          const status = STOCKTAKE_COUNT_STATUS_META[line.count_status_code];
          const nonBlind = isNonBlindLine(line);
          const showSavedPhysical =
            line.final_physical_qty !== null &&
            (line.count_status_code === "COUNTED" || nonBlind);

          return (
            <article key={line.stocktake_line_id} className="panel-card">
              <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-mono text-xs text-slate-500">
                      Line {formatNumber(line.line_no)}
                    </span>
                    <StatusPill label={status.label} tone={status.tone} />
                    <StatusPill
                      label={STOCKTAKE_BUCKET_LABELS[line.bucket_code]}
                      tone="neutral"
                    />
                  </div>

                  <h3 className="mt-3 text-lg font-semibold text-white">
                    {line.product_sku_snapshot} / {line.product_name_snapshot}
                  </h3>
                  <p className="mt-2 text-sm text-slate-400">
                    Batch {line.batch_code_snapshot} / Expiry{" "}
                    {formatDate(line.expiry_date_snapshot)}
                  </p>
                </div>

                <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-3">
                  <div className="rounded-xl border border-white/10 bg-slate-950/40 p-3">
                    <p className="text-xs text-slate-500">Attempt</p>
                    <p className="mt-1 font-semibold text-white">
                      {formatNumber(line.count_attempt_no)}
                    </p>
                  </div>

                  {showSavedPhysical ? (
                    <div className="rounded-xl border border-white/10 bg-slate-950/40 p-3">
                      <p className="text-xs text-slate-500">Fisik tersimpan</p>
                      <p className="mt-1 font-semibold text-white">
                        {formatNumber(line.final_physical_qty)}
                      </p>
                    </div>
                  ) : null}

                  {nonBlind ? (
                    <div className="rounded-xl border border-white/10 bg-slate-950/40 p-3">
                      <p className="text-xs text-slate-500">Snapshot awal</p>
                      <p className="mt-1 font-semibold text-white">
                        {formatNumber(line.system_qty_at_snapshot)}
                      </p>
                    </div>
                  ) : null}
                </div>
              </div>

              {nonBlind && line.count_status_code === "COUNTED" ? (
                <div className="mt-4 grid gap-3 sm:grid-cols-3">
                  <div className="rounded-xl border border-white/10 p-3">
                    <p className="text-xs text-slate-500">Expected at count</p>
                    <p className="mt-1 font-semibold text-white">
                      {formatNumber(line.expected_qty_at_count)}
                    </p>
                  </div>
                  <div className="rounded-xl border border-white/10 p-3">
                    <p className="text-xs text-slate-500">Variance</p>
                    <p className="mt-1 font-semibold text-white">
                      {formatNumber(line.variance_qty)}
                    </p>
                  </div>
                  <div className="rounded-xl border border-white/10 p-3">
                    <p className="text-xs text-slate-500">Ledger cutoff</p>
                    <p className="mt-1 font-semibold text-white">
                      {formatNumber(line.count_cutoff_ledger_seq)}
                    </p>
                  </div>
                </div>
              ) : null}

              {line.count_status_code === "PENDING" ||
              line.count_status_code === "RECOUNT_REQUESTED" ? (
                <CountForm stocktakeId={details.stocktake_id} line={line} />
              ) : null}

              {line.count_status_code === "COUNTED" ? (
                <RecountForm stocktakeId={details.stocktake_id} line={line} />
              ) : null}
            </article>
          );
        })}

        {lines.length === 0 ? (
          <div className="panel-card text-sm text-slate-400">
            Tidak ada count line yang dapat dibaca untuk sesi ini.
          </div>
        ) : null}
      </div>

      <section className="mt-6 rounded-2xl border border-emerald-400/20 bg-emerald-400/[0.055] p-5">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="font-semibold text-emerald-100">
              Selesaikan counting setelah seluruh line tersimpan.
            </p>
            <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
              Server tetap memeriksa seluruh line. Tombol browser hanya membantu
              mencegah submit terlalu dini, bukan menggantikan validasi domain.
            </p>
            <p className="mt-2 text-xs text-slate-500">
              Ringkasan server: {formatNumber(summary?.counted_line_count ?? 0)}
              {" / "}
              {formatNumber(summary?.line_count ?? 0)} line.
            </p>
          </div>

          <form action={completeStocktakeCountingAction}>
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
            <button
              className="primary-button disabled:cursor-not-allowed disabled:opacity-40"
              type="submit"
              disabled={!canComplete}
            >
              Selesaikan counting
            </button>
          </form>
        </div>
      </section>
    </section>
  );
}
