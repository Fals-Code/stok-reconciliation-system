import Link from "next/link";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import { EmptyState, Select, StatusBadge } from "@/components/ui";
import { requireAdminSession } from "@/lib/auth";
import { getStocktakeList } from "@/lib/stocktakes/queries";
import type {
  StocktakeListItem,
  StocktakeStatus,
  StocktakeType,
} from "@/lib/stocktakes/types";

export const dynamic = "force-dynamic";

const statusLabels: Record<StocktakeStatus, string> = {
  DRAFT: "Belum Dimulai",
  READY: "Siap Dihitung",
  COUNTING: "Sedang Dihitung",
  REVIEW: "Perlu Diperiksa",
  APPROVED: "Siap Disimpan",
  POSTING: "Menyimpan Perubahan",
  POSTED: "Selesai",
  CANCELLED: "Dibatalkan",
  EXCEPTION: "Bermasalah",
};

const typeLabels: Record<StocktakeType, string> = {
  FULL: "Seluruh Stok",
  CYCLE: "Sebagian Stok",
  AD_HOC: "Hitung Khusus",
};

function statusTone(status: StocktakeStatus) {
  if (status === "POSTED") return "selected" as const;
  if (status === "EXCEPTION" || status === "CANCELLED") return "danger" as const;
  if (
    status === "COUNTING" ||
    status === "REVIEW" ||
    status === "APPROVED" ||
    status === "POSTING"
  ) {
    return "warning" as const;
  }
  return "neutral" as const;
}

function nextAction(stocktake: StocktakeListItem) {
  const labels: Record<StocktakeStatus, string> = {
    DRAFT: "Siapkan",
    READY: "Mulai Menghitung",
    COUNTING: "Lanjutkan Menghitung",
    REVIEW: "Periksa Hasil",
    APPROVED: "Simpan Perubahan",
    POSTING: "Lihat Status",
    POSTED: "Lihat Hasil",
    CANCELLED: "Lihat Riwayat",
    EXCEPTION: "Periksa Masalah",
  };

  return labels[stocktake.status_code];
}

function first(
  params: Record<string, string | string[] | undefined>,
  key: string,
) {
  const value = params[key];
  return (Array.isArray(value) ? value[0] : value)?.trim() ?? "";
}

function progress(stocktake: StocktakeListItem) {
  if (stocktake.line_count <= 0) return 0;

  return Math.min(
    100,
    Math.round(
      (stocktake.counted_line_count / stocktake.line_count) * 100,
    ),
  );
}

function StocktakeCard({ stocktake }: { stocktake: StocktakeListItem }) {
  const countingProgress = progress(stocktake);
  const showProgress = stocktake.status_code === "COUNTING";

  return (
    <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-5 py-4">
      <div className="grid gap-4 sm:grid-cols-[minmax(0,1.25fr)_minmax(220px,0.8fr)_auto] sm:items-center">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="truncate text-base font-semibold text-ui-text">
              {stocktake.title}
            </h3>
            <StatusBadge tone={statusTone(stocktake.status_code)}>
              {statusLabels[stocktake.status_code]}
            </StatusBadge>
          </div>

          <p className="mt-1 text-sm text-ui-text-muted">
            {typeLabels[stocktake.stocktake_type_code]}
            {" \u00B7 "}
            {stocktake.visibility_code === "BLIND"
              ? "Tanpa lihat catatan"
              : "Dengan catatan"}
          </p>

        </div>

        {showProgress ? (
          <div className="min-w-0">
            <div className="mb-1.5 flex items-center justify-between gap-3 text-xs text-ui-text-muted">
              <span>
                {stocktake.counted_line_count} dari {stocktake.line_count} lokasi
              </span>
              <span className="font-semibold text-ui-text">
                {countingProgress}%
              </span>
            </div>
            <div
              aria-label={`Kemajuan hitung ${countingProgress}%`}
              className="h-1.5 overflow-hidden rounded-full bg-ui-border"
              role="progressbar"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={countingProgress}
            >
              <div
                className="h-full rounded-full bg-ui-primary"
                style={{ width: `${countingProgress}%` }}
              />
            </div>
          </div>
        ) : (
          <div />
        )}

        <Link
          className="inline-flex min-h-[var(--ui-control-height)] shrink-0 items-center font-semibold text-ui-primary hover:underline"
          href={`/stocktakes/${encodeURIComponent(stocktake.stocktake_id)}`}
        >
          {nextAction(stocktake)}
        </Link>
      </div>
    </article>
  );
}

export default async function StocktakesPage({
  searchParams,
}: {
  searchParams: Promise<
    Record<string, string | string[] | undefined>
  >;
}) {
  const [session, params] = await Promise.all([
    requireAdminSession(),
    searchParams,
  ]);

  let stocktakes: StocktakeListItem[];

  try {
    stocktakes = await getStocktakeList();
  } catch {
    return (
      <AppShell profile={session.profile}>
        <div className="mx-auto w-full max-w-[1120px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader
            description="Daftar Hitung Stok belum dapat dimuat. Kondisi gagal tidak mengubah stok."
            title="Hitung Stok"
          />
          <div className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-warning bg-ui-warning-subtle p-4 text-sm text-ui-warning">
            Daftar belum tersedia. Muat ulang halaman sebelum memulai atau
            melanjutkan pekerjaan.
          </div>
        </div>
      </AppShell>
    );
  }

  const status = first(params, "status");
  const type = first(params, "type");

  const filtered = stocktakes.filter(
    (item) =>
      (!status || item.status_code === status) &&
      (!type || item.stocktake_type_code === type),
  );

  const activeStocktakes = filtered.filter(
    (item) =>
      item.status_code !== "POSTED" &&
      item.status_code !== "CANCELLED",
  );
  const historyStocktakes = filtered.filter(
    (item) =>
      item.status_code === "POSTED" ||
      item.status_code === "CANCELLED",
  );

  const activeAll = stocktakes.filter(
    (item) =>
      item.status_code !== "POSTED" &&
      item.status_code !== "CANCELLED",
  );
  const reviewCount = activeAll.filter(
    (item) => item.status_code === "REVIEW",
  ).length;
  const readyToPostCount = activeAll.filter(
    (item) => item.status_code === "APPROVED",
  ).length;

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1120px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <div className="mb-3">
          <Link
            className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
            href="/products"
          >
            {"\u2190"} Kembali ke Stok
          </Link>
        </div>

        <PageHeader
          action={
            <Link
              className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary"
              href="/stocktakes/new"
            >
              Mulai Hitung Stok
            </Link>
          }
          description="Bandingkan jumlah fisik dengan catatan sistem. Stok baru berubah setelah hasil diperiksa, disetujui, lalu disimpan."
          eyebrow="Stok"
          title="Hitung Stok"
        />

        <section
          aria-label="Ringkasan pekerjaan Hitung Stok"
          className="mt-6 grid gap-3 sm:grid-cols-3"
        >
          <div className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 py-2.5">
            <p className="text-sm text-ui-text-muted">Pekerjaan aktif</p>
            <p className="ui-number mt-0.5 text-lg font-semibold text-ui-text">
              {activeAll.length}
            </p>
          </div>
          <div className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 py-2.5">
            <p className="text-sm text-ui-text-muted">Perlu diperiksa</p>
            <p className="ui-number mt-0.5 text-lg font-semibold text-ui-text">
              {reviewCount}
            </p>
          </div>
          <div className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 py-2.5">
            <p className="text-sm text-ui-text-muted">Siap disimpan</p>
            <p className="ui-number mt-0.5 text-lg font-semibold text-ui-text">
              {readyToPostCount}
            </p>
          </div>
        </section>

        <form
          className="mt-5 grid gap-3 border-b border-ui-border pb-4 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto] sm:items-end"
          method="get"
        >
          <label className="grid min-w-0 gap-2 text-sm font-semibold text-ui-text">
            Status
            <Select defaultValue={status} name="status">
              <option value="">Semua status</option>
              {Object.entries(statusLabels).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </Select>
          </label>

          <label className="grid min-w-0 gap-2 text-sm font-semibold text-ui-text">
            Jenis hitung
            <Select defaultValue={type} name="type">
              <option value="">Semua jenis</option>
              {Object.entries(typeLabels).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </Select>
          </label>

          <div className="flex min-h-[var(--ui-control-height)] items-center gap-2">
            <button
              className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm font-semibold text-ui-text hover:bg-ui-surface-subtle"
              type="submit"
            >
              Terapkan Filter
            </button>
            {(status || type) ? (
              <Link
                className="inline-flex min-h-[var(--ui-control-height)] items-center px-1 text-sm font-semibold text-ui-text-muted hover:text-ui-text"
                href="/stocktakes"
              >
                Reset
              </Link>
            ) : null}
          </div>
        </form>

        {activeStocktakes.length ? (
          <section className="mt-6">
            <div>
              <h2 className="text-lg font-semibold text-ui-text">
                Perlu dilanjutkan
              </h2>
              <p className="mt-1 text-sm text-ui-text-muted">
                Buka pekerjaan lalu lanjutkan dari tahap terakhir.
              </p>
            </div>

            <div className="mt-3 grid gap-3">
              {activeStocktakes.map((stocktake) => (
                <StocktakeCard
                  key={stocktake.stocktake_id}
                  stocktake={stocktake}
                />
              ))}
            </div>
          </section>
        ) : (
          <EmptyState
            className="mt-6"
            description="Tidak ada Hitung Stok yang perlu dilanjutkan."
            title="Pekerjaan aktif kosong"
          />
        )}

        {historyStocktakes.length ? (
          <section className="mt-8 border-t border-ui-border pt-7">
            <div className="flex items-end justify-between gap-3">
              <h2 className="text-lg font-semibold text-ui-text">
                Riwayat Hitung Stok
              </h2>
              <span className="text-sm font-medium text-ui-text-muted">
                {historyStocktakes.length} riwayat
              </span>
            </div>

            <div className="mt-3 grid gap-3">
              {historyStocktakes.map((stocktake) => (
                <StocktakeCard
                  key={stocktake.stocktake_id}
                  stocktake={stocktake}
                />
              ))}
            </div>
          </section>
        ) : null}
      </div>
    </AppShell>
  );
}