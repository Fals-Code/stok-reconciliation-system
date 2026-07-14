import Link from "next/link";

import {
  STOCKTAKE_STATUSES,
  STOCKTAKE_STATUS_META,
  STOCKTAKE_TYPES,
  STOCKTAKE_TYPE_LABELS,
  STOCKTAKE_VISIBILITIES,
  STOCKTAKE_VISIBILITY_LABELS,
  isActiveStocktake,
  stocktakeProgress,
  type StocktakePillTone,
} from "@/lib/stocktakes/constants";
import { getStocktakeList } from "@/lib/stocktakes/queries";
import type {
  StocktakeStatus,
  StocktakeType,
  StocktakeVisibility,
} from "@/lib/stocktakes/types";

export const dynamic = "force-dynamic";

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number | null) {
  if (value === null) {
    return "Tersembunyi";
  }

  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null, includeTime = true) {
  if (!value) return "Belum ditentukan";

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

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-amber-300">
          Stocktake tidak tersedia
        </p>
        <h1 className="mt-3 text-3xl font-semibold">
          Daftar stok opname gagal dimuat.
        </h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <Link className="nav-link mt-6 inline-flex" href="/">
          Kembali ke dashboard
        </Link>
      </section>
    </main>
  );
}

function normalizeFilter<T extends string>(
  value: string | undefined,
  allowed: readonly T[],
): "ALL" | T {
  return value && allowed.includes(value as T) ? (value as T) : "ALL";
}

export default async function StocktakesPage({
  searchParams,
}: {
  searchParams: Promise<{
    status?: string;
    type?: string;
    visibility?: string;
  }>;
}) {
  const params = await searchParams;
  let stocktakes;

  try {
    stocktakes = await getStocktakeList();
  } catch (error) {
    return (
      <ConfigurationError
        message={error instanceof Error ? error.message : "Konfigurasi tidak valid."}
      />
    );
  }

  const statusFilter = normalizeFilter<StocktakeStatus>(
    params.status,
    STOCKTAKE_STATUSES,
  );
  const typeFilter = normalizeFilter<StocktakeType>(
    params.type,
    STOCKTAKE_TYPES,
  );
  const visibilityFilter = normalizeFilter<StocktakeVisibility>(
    params.visibility,
    STOCKTAKE_VISIBILITIES,
  );

  const filteredStocktakes = stocktakes.filter((stocktake) => {
    if (
      statusFilter !== "ALL" &&
      stocktake.status_code !== statusFilter
    ) {
      return false;
    }

    if (
      typeFilter !== "ALL" &&
      stocktake.stocktake_type_code !== typeFilter
    ) {
      return false;
    }

    if (
      visibilityFilter !== "ALL" &&
      stocktake.visibility_code !== visibilityFilter
    ) {
      return false;
    }

    return true;
  });

  const activeCount = stocktakes.filter((stocktake) =>
    isActiveStocktake(stocktake.status_code),
  ).length;
  const countingCount = stocktakes.filter(
    (stocktake) => stocktake.status_code === "COUNTING",
  ).length;
  const reviewCount = stocktakes.filter(
    (stocktake) =>
      stocktake.status_code === "REVIEW" ||
      stocktake.status_code === "APPROVED",
  ).length;
  const postedCount = stocktakes.filter(
    (stocktake) => stocktake.status_code === "POSTED",
  ).length;

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <header className="sticky top-0 z-20 border-b border-white/10 bg-slate-950/90 backdrop-blur">
        <div className="mx-auto flex max-w-[1500px] items-center justify-between gap-5 px-5 py-4 lg:px-8">
          <div>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-emerald-300">
              GlowLab Stocktakes
            </p>
            <p className="mt-1 text-sm text-slate-400">
              Ledger-first physical counting
            </p>
          </div>

          <nav className="hidden items-center gap-2 text-sm md:flex">
            <a className="nav-link" href="#overview">
              Ringkasan
            </a>
            <a className="nav-link" href="#sessions">
              Sesi
            </a>
          </nav>

          <div className="flex items-center gap-2">
            <Link className="nav-link border border-white/10" href="/marketplace">
              Marketplace
            </Link>
            <Link className="nav-link border border-white/10" href="/returns">
              Returns
            </Link>
            <Link
              className="nav-link border border-white/10"
              href="/reconciliation"
            >
              Reconciliation
            </Link>
            <Link className="nav-link border border-white/10" href="/">
              Dashboard
            </Link>
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section id="overview" className="scroll-mt-24">
          <div className="flex flex-col gap-6 xl:flex-row xl:items-end xl:justify-between">
            <div>
              <p className="section-kicker">Stok opname</p>
              <h1 className="mt-3 max-w-4xl text-3xl font-semibold tracking-tight sm:text-4xl">
                Bandingkan fisik dengan ledger tanpa mengedit saldo langsung.
              </h1>
              <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
                Halaman ini membaca sesi stocktake yang sudah tersimpan. Create,
                counting, review, approval, dan posting akan ditambahkan sebagai
                slice terpisah agar lifecycle tetap dapat diuji.
              </p>
            </div>

            <div className="rounded-2xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm text-slate-400">
              Mode fase 1: CONTINUOUS
            </div>
          </div>

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              ["Sesi aktif", activeCount, "Belum posted atau cancelled"],
              ["Sedang dihitung", countingCount, "Count atau recount berjalan"],
              ["Review dan approval", reviewCount, "Menunggu keputusan Admin"],
              ["Sudah diposting", postedCount, "Adjustment dan audit tersedia"],
            ].map(([label, value, description]) => (
              <article key={label} className="metric-card">
                <p className="text-sm text-slate-400">{label}</p>
                <p className="mt-3 text-3xl font-semibold text-white">
                  {formatNumber(Number(value))}
                </p>
                <p className="mt-2 text-xs text-slate-500">{description}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="sessions" className="mt-10 scroll-mt-24">
          <div className="mb-5 flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
            <div>
              <p className="section-kicker">Daftar sesi</p>
              <h2 className="section-title">
                Pantau progres dan status stocktake.
              </h2>
            </div>

            <Link className="primary-button" href="/stocktakes/new">
              Buat sesi stocktake
            </Link>
          </div>

          <form
            className="mb-5 grid gap-4 rounded-2xl border border-white/10 bg-white/[0.025] p-5 sm:grid-cols-2 xl:grid-cols-4"
            method="get"
          >
            <label className="field-label">
              Status
              <select name="status" defaultValue={statusFilter}>
                <option value="ALL">Semua status</option>
                {STOCKTAKE_STATUSES.map((status) => (
                  <option key={status} value={status}>
                    {STOCKTAKE_STATUS_META[status].label}
                  </option>
                ))}
              </select>
            </label>

            <label className="field-label">
              Tipe
              <select name="type" defaultValue={typeFilter}>
                <option value="ALL">Semua tipe</option>
                {STOCKTAKE_TYPES.map((type) => (
                  <option key={type} value={type}>
                    {STOCKTAKE_TYPE_LABELS[type]}
                  </option>
                ))}
              </select>
            </label>

            <label className="field-label">
              Visibility
              <select name="visibility" defaultValue={visibilityFilter}>
                <option value="ALL">Semua visibility</option>
                {STOCKTAKE_VISIBILITIES.map((visibility) => (
                  <option key={visibility} value={visibility}>
                    {STOCKTAKE_VISIBILITY_LABELS[visibility]}
                  </option>
                ))}
              </select>
            </label>

            <div className="flex items-end gap-3">
              <button className="primary-button flex-1" type="submit">
                Terapkan
              </button>
              <Link className="nav-link border border-white/10" href="/stocktakes">
                Reset
              </Link>
            </div>
          </form>

          {filteredStocktakes.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-white/10 bg-white/[0.02] px-6 py-12 text-center">
              <p className="text-lg font-semibold text-white">
                Tidak ada sesi stocktake.
              </p>
              <p className="mt-2 text-sm text-slate-400">
                Belum ada data atau tidak ada sesi yang cocok dengan filter.
              </p>
            </div>
          ) : (
            <div className="overflow-x-auto rounded-2xl border border-white/10 bg-white/[0.025]">
              <table>
                <thead>
                  <tr>
                    <th>Sesi</th>
                    <th>Status</th>
                    <th>Tipe</th>
                    <th>Visibility</th>
                    <th>Progress</th>
                    <th>Variance</th>
                    <th>Rencana</th>
                    <th>Aktivitas terakhir</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredStocktakes.map((stocktake) => {
                    const status = STOCKTAKE_STATUS_META[stocktake.status_code];
                    const progress = stocktakeProgress(stocktake);

                    return (
                      <tr key={stocktake.stocktake_id}>
                        <td>
                          <Link
                            className="block rounded-lg outline-offset-4"
                            href={`/stocktakes/${stocktake.stocktake_id}`}
                          >
                            <p className="font-semibold text-white">
                              {stocktake.stocktake_no}
                            </p>
                            <p className="mt-1 max-w-72 text-xs text-slate-500">
                              {stocktake.title}
                            </p>
                          </Link>
                        </td>
                        <td>
                          <Pill label={status.label} tone={status.tone} />
                        </td>
                        <td>
                          {STOCKTAKE_TYPE_LABELS[stocktake.stocktake_type_code]}
                        </td>
                        <td>
                          {STOCKTAKE_VISIBILITY_LABELS[stocktake.visibility_code]}
                        </td>
                        <td>
                          <div className="min-w-36">
                            <div className="flex items-center justify-between gap-3 text-xs">
                              <span>
                                {formatNumber(stocktake.counted_line_count)} /{" "}
                                {formatNumber(stocktake.line_count)}
                              </span>
                              <span className="text-slate-500">{progress}%</span>
                            </div>
                            <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-white/10">
                              <div
                                className="h-full rounded-full bg-emerald-400"
                                style={{ width: `${progress}%` }}
                              />
                            </div>
                          </div>
                        </td>
                        <td>{formatNumber(stocktake.variance_line_count)}</td>
                        <td>{formatDate(stocktake.planned_at)}</td>
                        <td>{formatDate(stocktake.updated_at)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </section>
      </div>
    </main>
  );
}