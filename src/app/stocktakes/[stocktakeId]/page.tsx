import Link from "next/link";
import { notFound } from "next/navigation";

import {
  prepareStocktakeAction,
  startStocktakeAction,
} from "@/app/stocktakes/actions";
import {
  STOCKTAKE_BUCKET_LABELS,
  STOCKTAKE_SCOPE_LABELS,
  STOCKTAKE_STATUS_META,
  STOCKTAKE_TYPE_LABELS,
  STOCKTAKE_VISIBILITY_LABELS,
  type StocktakePillTone,
} from "@/lib/stocktakes/constants";
import { getStocktakeDetails } from "@/lib/stocktakes/queries";
import type {
  StocktakeDetails,
  StocktakeScopeDefinition,
} from "@/lib/stocktakes/types";

export const dynamic = "force-dynamic";

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number) {
  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null, includeTime = true) {
  if (!value) return "Belum ada";

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
    ...(includeTime
      ? { hour: "2-digit", minute: "2-digit", hour12: false }
      : {}),
  }).format(date);
}

function Pill({
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

function scopeEntitySummary(scope: StocktakeScopeDefinition) {
  if (scope.mode === "PRODUCTS") {
    return `${scope.productIds?.length ?? 0} produk dipilih`;
  }

  if (scope.mode === "BATCHES") {
    return `${scope.batchIds?.length ?? 0} batch dipilih`;
  }

  return "Seluruh inventory aktif";
}

function DraftAction({ details }: { details: StocktakeDetails }) {
  return (
    <section className="mt-6 rounded-2xl border border-amber-400/20 bg-amber-400/[0.055] p-5">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="font-semibold text-amber-100">
            Validasi konfigurasi sebelum penghitungan.
          </p>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
            Prepare memastikan produk atau batch masih berada dalam organisasi,
            scope menghasilkan line, dan mode tetap CONTINUOUS. Tahap ini tidak
            membuat snapshot, count line, ledger entry, atau perubahan saldo.
          </p>
          <p className="mt-3 text-xs text-slate-500">
            Tolerance tetap {formatNumber(details.tolerance_policy_snapshot.units)}
            {" unit / "}
            {formatNumber(details.tolerance_policy_snapshot.percent)}%.
          </p>
        </div>

        <form action={prepareStocktakeAction}>
          <input type="hidden" name="stocktakeId" value={details.stocktake_id} />
          <button className="primary-button" type="submit">
            Validasi dan siapkan sesi
          </button>
        </form>
      </div>
    </section>
  );
}

function ReadyAction({ details }: { details: StocktakeDetails }) {
  return (
    <section className="mt-6 rounded-2xl border border-emerald-400/20 bg-emerald-400/[0.055] p-5">
      <p className="font-semibold text-emerald-100">
        Scope valid dan sesi siap dimulai.
      </p>
      <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
        Start mengambil batas ledger terbaru secara atomik, membuat line
        penghitungan dan snapshot immutable, lalu memindahkan sesi ke COUNTING.
        Tidak ada quantity yang dikoreksi pada tahap ini.
      </p>

      <form action={startStocktakeAction} className="mt-5">
        <input type="hidden" name="stocktakeId" value={details.stocktake_id} />

        <label className="flex max-w-3xl items-start gap-3 rounded-xl border border-white/10 bg-slate-950/40 p-4">
          <input
            className="mt-1"
            type="checkbox"
            name="confirmStart"
            required
          />
          <span>
            <span className="text-sm font-semibold text-white">
              Saya memahami bahwa snapshot dan count line akan dibuat.
            </span>
            <span className="mt-1 block text-xs leading-5 text-slate-500">
              Snapshot bersumber dari ledger dan tidak diedit dari browser.
            </span>
          </span>
        </label>

        <button className="primary-button mt-4" type="submit">
          Mulai penghitungan
        </button>
      </form>
    </section>
  );
}

function CountingNotice() {
  return (
    <section className="mt-6 rounded-2xl border border-sky-400/20 bg-sky-400/[0.055] p-5">
      <p className="font-semibold text-sky-100">
        Snapshot sudah dibuat dan sesi berada pada COUNTING.
      </p>
      <p className="mt-2 text-sm leading-6 text-slate-400">
        Count entry dan recount akan ditambahkan pada slice berikutnya. Halaman
        ini tetap read-only agar line tidak diubah melalui jalur yang belum
        tervalidasi.
      </p>
    </section>
  );
}

export default async function StocktakeDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ stocktakeId: string }>;
  searchParams: Promise<{ success?: string; error?: string }>;
}) {
  const { stocktakeId } = await params;
  const feedback = await searchParams;
  const data = await getStocktakeDetails(stocktakeId);

  if (!data) {
    notFound();
  }

  const { details, summary } = data;
  const status = STOCKTAKE_STATUS_META[details.status_code];
  const scope = details.scope_definition;

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <header className="border-b border-white/10 bg-slate-950/90">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-5 px-5 py-4 lg:px-8">
          <div>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-emerald-300">
              {details.stocktake_no}
            </p>
            <p className="mt-1 text-sm text-slate-400">Stocktake session</p>
          </div>

          <Link className="nav-link border border-white/10" href="/stocktakes">
            Kembali ke daftar
          </Link>
        </div>
      </header>

      <div className="mx-auto max-w-6xl px-5 py-8 lg:px-8">
        <section>
          <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="section-kicker">Detail sesi</p>
              <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
                {details.title}
              </h1>
              <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
                Browser hanya menjalankan command yang valid untuk status saat
                ini. Status akhir, snapshot, dan line tetap ditentukan server.
              </p>
            </div>

            <Pill label={status.label} tone={status.tone} />
          </div>

          {feedback.success ? (
            <div className="mt-6 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-100">
              {feedback.success}
            </div>
          ) : null}

          {feedback.error ? (
            <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-100">
              {feedback.error}
            </div>
          ) : null}

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              [
                "Status",
                status.label,
                `Version ${formatNumber(details.version_no)}`,
              ],
              [
                "Progress",
                `${formatNumber(summary?.counted_line_count ?? 0)} / ${formatNumber(
                  summary?.line_count ?? 0,
                )}`,
                `${formatNumber(summary?.variance_line_count ?? 0)} variance line`,
              ],
              [
                "Rencana",
                formatDate(details.planned_at),
                details.timezone_snapshot,
              ],
              [
                "Snapshot ledger",
                details.snapshot_ledger_seq === null
                  ? "Belum dibuat"
                  : formatNumber(details.snapshot_ledger_seq),
                "Source of truth: ledger",
              ],
            ].map(([label, value, description]) => (
              <article key={label} className="metric-card">
                <p className="text-sm text-slate-400">{label}</p>
                <p className="mt-3 text-xl font-semibold text-white">{value}</p>
                <p className="mt-2 text-xs text-slate-500">{description}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="mt-8 grid gap-6 lg:grid-cols-2">
          <article className="panel-card">
            <p className="section-kicker">Configuration</p>
            <h2 className="section-title">Aturan sesi.</h2>

            <dl className="mt-6 space-y-4 text-sm">
              {[
                [
                  "Tipe",
                  STOCKTAKE_TYPE_LABELS[details.stocktake_type_code],
                ],
                ["Mode", details.mode_code],
                [
                  "Visibility",
                  STOCKTAKE_VISIBILITY_LABELS[details.visibility_code],
                ],
                ["Rule version", details.rule_version],
                [
                  "Tolerance",
                  `${formatNumber(details.tolerance_policy_snapshot.units)} unit / ${formatNumber(
                    details.tolerance_policy_snapshot.percent,
                  )}%`,
                ],
                ["Mulai", formatDate(details.started_at)],
                ["Dibuat", formatDate(details.created_at)],
                ["Diperbarui", formatDate(details.updated_at)],
              ].map(([label, value]) => (
                <div
                  key={label}
                  className="flex items-start justify-between gap-6 border-b border-white/10 pb-4"
                >
                  <dt className="text-slate-500">{label}</dt>
                  <dd className="text-right font-medium text-slate-200">
                    {value}
                  </dd>
                </div>
              ))}
            </dl>
          </article>

          <article className="panel-card">
            <p className="section-kicker">Scope</p>
            <h2 className="section-title">Entity yang direncanakan.</h2>

            <div className="mt-6 rounded-xl border border-white/10 bg-slate-950/45 p-4">
              <p className="text-sm font-semibold text-white">
                {STOCKTAKE_SCOPE_LABELS[scope.mode]}
              </p>
              <p className="mt-2 text-xs text-slate-500">
                {scopeEntitySummary(scope)}
              </p>
            </div>

            <div className="mt-4 flex flex-wrap gap-2">
              {scope.bucketCodes.map((bucket) => (
                <Pill
                  key={bucket}
                  label={STOCKTAKE_BUCKET_LABELS[bucket]}
                  tone="neutral"
                />
              ))}
            </div>

            <dl className="mt-6 space-y-3 text-sm">
              {[
                ["Saldo sistem nol", scope.includeZeroSystemBalance],
                ["Produk tidak aktif bersaldo", scope.includeInactiveWithBalance],
                ["Batch blocked", scope.includeBlockedBatches],
                ["Batch expired", scope.includeExpiredBatches],
              ].map(([label, enabled]) => (
                <div
                  key={String(label)}
                  className="flex items-center justify-between gap-4"
                >
                  <dt className="text-slate-500">{label}</dt>
                  <dd className="font-medium text-slate-200">
                    {enabled ? "Disertakan" : "Tidak disertakan"}
                  </dd>
                </div>
              ))}
            </dl>

            {details.note ? (
              <div className="mt-6 rounded-xl border border-white/10 p-4">
                <p className="text-xs uppercase tracking-[0.12em] text-slate-500">
                  Catatan
                </p>
                <p className="mt-2 text-sm leading-6 text-slate-300">
                  {details.note}
                </p>
              </div>
            ) : null}
          </article>
        </section>

        {details.status_code === "DRAFT" ? (
          <DraftAction details={details} />
        ) : null}

        {details.status_code === "READY" ? (
          <ReadyAction details={details} />
        ) : null}

        {details.status_code === "COUNTING" ? <CountingNotice /> : null}
      </div>
    </main>
  );
}