import Link from "next/link";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  Alert,
  EmptyState,
  StatusBadge,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  isSafeInternalRoute,
} from "@/lib/safe-internal-route";
import {
  getDashboardData,
  getTodayControlCenterWorkItems,
  type BatchInventory,
  type StockLedgerEntry,
  type TodayControlCenterSeverity,
  type TodayControlCenterWorkItem,
  type TodayControlCenterWorkType,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

const numberFormatter = new Intl.NumberFormat("id-ID");

const nonOperationalWorkTypes = new Set<TodayControlCenterWorkType>([
  "RECONCILIATION_RUN_FAILED",
  "NOTIFICATION_OUTBOX_FAILURE",
  "NOTIFICATION_RULE_RUN_FAILURE",
]);

type OperationalWorkType = Exclude<
  TodayControlCenterWorkType,
  "RECONCILIATION_RUN_FAILED" | "NOTIFICATION_OUTBOX_FAILURE" | "NOTIFICATION_RULE_RUN_FAILURE"
>;

const severityLabel: Record<TodayControlCenterSeverity, string> = {
  CRITICAL: "Kritis",
  HIGH: "Mendesak",
  WARNING: "Perlu Diperiksa",
  INFO: "Informasi",
};

const severityTone: Record<
  TodayControlCenterSeverity,
  "danger" | "warning" | "neutral"
> = {
  CRITICAL: "danger",
  HIGH: "warning",
  WARNING: "warning",
  INFO: "neutral",
};

const workTypeLabel: Record<OperationalWorkType, string> = {
  RECONCILIATION_ISSUE: "Masalah stok",
  TIKTOK_CLAIM_DEADLINE: "Klaim TikTok",
  RETURN_INSPECTION_PENDING: "Retur",
  BATCH_EXPIRY: "Batch",
  STOCKTAKE_RECOUNT_REQUIRED: "Hitung stok",
  STOCKTAKE_POST_FAILED: "Hitung stok",
};

const workAction: Record<
  OperationalWorkType,
  { href: string; label: string }
> = {
  RECONCILIATION_ISSUE: {
    href: "/stock-issues",
    label: "Periksa Selisih",
  },
  TIKTOK_CLAIM_DEADLINE: {
    href: "/returns",
    label: "Buka Klaim",
  },
  RETURN_INSPECTION_PENDING: {
    href: "/returns",
    label: "Buka Retur",
  },
  BATCH_EXPIRY: {
    href: "/products",
    label: "Lihat Batch",
  },
  STOCKTAKE_RECOUNT_REQUIRED: {
    href: "/stocktakes",
    label: "Lanjutkan Hitung",
  },
  STOCKTAKE_POST_FAILED: {
    href: "/stocktakes",
    label: "Periksa Hasil",
  },
};

const activityLabel: Record<string, string> = {
  INITIAL_BALANCE: "Stok Awal",
  RECEIPT: "Barang Masuk",
  MARKETPLACE_OUTBOUND: "Barang Keluar",
  OUTBOUND_MARKETPLACE: "Barang Keluar",
  MANUAL_OUTBOUND: "Barang Keluar",
  RETURN_SELLABLE_INBOUND: "Retur Layak Dijual",
  STOCKTAKE_ADJUSTMENT: "Penyesuaian Hasil Hitung",
  DISPOSAL: "Barang Rusak / Kedaluwarsa",
  REVERSAL: "Koreksi",
};

function quantity(value: number) {
  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null, includeYear = false) {
  if (!value) return null;

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    ...(includeYear ? { year: "numeric" } : {}),
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function formatExpiryDate(value: string) {
  const date = new Date(`${value}T00:00:00+07:00`);

  if (Number.isNaN(date.getTime())) return value;

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
  }).format(date);
}

function expiryDays(batch: BatchInventory) {
  const expiry = new Date(`${batch.expiry_date}T00:00:00+07:00`);
  return Math.ceil((expiry.getTime() - Date.now()) / 86_400_000);
}

function getTodayWorkItemReactKey(item: TodayControlCenterWorkItem) {
  return item.notification_id
    ? `${item.work_item_id}:${item.notification_id}`
    : `${item.work_item_id}:${item.source_entity_id}`;
}

function isOperationalWorkItem(
  item: TodayControlCenterWorkItem,
): item is TodayControlCenterWorkItem & {
  work_type_code: OperationalWorkType;
} {
  return !nonOperationalWorkTypes.has(item.work_type_code);
}

function getWorkHref(
  item: TodayControlCenterWorkItem & {
    work_type_code: OperationalWorkType;
  },
) {
  return isSafeInternalRoute(item.route_path)
    ? item.route_path!
    : workAction[item.work_type_code].href;
}

function getDueLabel(item: TodayControlCenterWorkItem) {
  if (item.work_type_code === "TIKTOK_CLAIM_DEADLINE") {
    return "Batas klaim";
  }

  if (item.work_type_code === "BATCH_EXPIRY") {
    return "Kedaluwarsa";
  }

  return "Perlu ditindaklanjuti";
}

function PrioritySummary({
  rows,
}: {
  rows: Array<TodayControlCenterWorkItem & { work_type_code: OperationalWorkType }>;
}) {
  const urgent = rows.filter(
    (item) => item.severity_code === "CRITICAL" || item.severity_code === "HIGH",
  ).length;
  const review = rows.filter((item) => item.severity_code === "WARNING").length;
  const info = rows.filter((item) => item.severity_code === "INFO").length;

  const items = [
    { label: "Mendesak", value: urgent, accent: "bg-ui-danger" },
    { label: "Perlu Diperiksa", value: review, accent: "bg-ui-warning" },
    { label: "Informasi", value: info, accent: "bg-ui-primary" },
  ];

  return (
    <dl className="grid gap-3 sm:grid-cols-3">
      {items.map((item) => (
        <div
          className="relative overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-3"
          key={item.label}
        >
          <span
            aria-hidden="true"
            className={`absolute inset-y-2 left-0 w-0.5 rounded-full opacity-70 ${item.accent}`}
          />
          <dt className="text-xs font-medium text-ui-text-muted">
            {item.label}
          </dt>
          <dd className="ui-number mt-1 text-[1.4rem] font-semibold tracking-tight text-ui-text">
            {quantity(item.value)}
          </dd>
        </div>
      ))}
    </dl>
  );
}
function WorkItem({
  item,
}: {
  item: TodayControlCenterWorkItem & {
    work_type_code: OperationalWorkType;
  };
}) {
  const fallbackAction = workAction[item.work_type_code];
  const due = formatDate(item.due_at, true);
  const accentClass =
    item.severity_code === "CRITICAL"
      ? "bg-ui-danger"
      : item.severity_code === "HIGH" || item.severity_code === "WARNING"
        ? "bg-ui-warning"
        : "bg-ui-primary";

  return (
    <article className="relative border-b border-ui-border px-4 py-3.5 last:border-b-0 sm:px-5">
      <span
        aria-hidden="true"
        className={`absolute left-0 top-1/2 h-8 w-0.5 -translate-y-1/2 rounded-full opacity-80 ${accentClass}`}
      />

      <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-start sm:gap-x-6">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge tone={severityTone[item.severity_code]}>
              {severityLabel[item.severity_code]}
            </StatusBadge>
            <span className="text-xs font-medium text-ui-text-muted">
              {workTypeLabel[item.work_type_code]}
            </span>
          </div>

          <h3 className="mt-2 text-[0.9375rem] font-semibold leading-5 text-ui-text">
            {item.title}
          </h3>

          <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
            {item.summary}
          </p>

          {due ? (
            <p className="mt-2 text-xs font-medium text-ui-text-muted">
              {getDueLabel(item)}: {due} WIB
            </p>
          ) : null}
        </div>

        <Link
          className="inline-flex min-h-9 shrink-0 items-center gap-1.5 self-start px-1 text-sm font-semibold text-ui-primary hover:underline"
          href={getWorkHref(item)}
        >
          {fallbackAction.label}
          <span aria-hidden="true">{"\u2192"}</span>
        </Link>
      </div>
    </article>
  );
}
function StockSnapshot({
  available,
  reserved,
  updatedAt,
}: {
  available: number;
  reserved: number;
  updatedAt: string | null;
}) {
  const updatedLabel = formatDate(updatedAt);

  return (
    <section aria-labelledby="stock-snapshot-heading">
      <div className="flex items-start justify-between gap-6">
        <div>
          <h2 className="text-sm font-medium text-ui-text-muted" id="stock-snapshot-heading">
            Stok tersedia
          </h2>
          <p className="ui-number mt-1 text-2xl font-semibold tracking-tight text-ui-primary">
            {quantity(available)}
            <span className="ml-1.5 text-sm font-medium text-ui-text-muted">unit</span>
          </p>
        </div>

        <div className="text-right">
          <p className="text-sm text-ui-text-muted">Sudah dipesan</p>
          <p className="ui-number mt-1 text-lg font-semibold text-ui-text">
            {quantity(reserved)}
          </p>
        </div>
      </div>

      {updatedLabel ? (
        <p className="mt-3 text-xs text-ui-text-muted">
          Diperbarui {updatedLabel} WIB
        </p>
      ) : null}
    </section>
  );
}
function BatchRiskList({
  rows,
}: {
  rows: Array<{ batch: BatchInventory; days: number }>;
}) {
  return (
    <section aria-labelledby="batch-risk-heading" className="border-t border-ui-border pt-5">
      <div className="flex items-baseline justify-between gap-4">
        <div>
          <h2 className="text-base font-semibold text-ui-text" id="batch-risk-heading">
            Batch perlu diperhatikan
          </h2>
          <p className="mt-1 text-sm text-ui-text-muted">
            Batch dengan tindakan aktif.
          </p>
        </div>

        <span className="ui-number text-sm font-semibold text-ui-text">
          {quantity(rows.length)}
        </span>
      </div>

      {rows.length === 0 ? (
        <p className="mt-4 text-sm text-ui-text-muted">
          Tidak ada batch yang perlu diperhatikan.
        </p>
      ) : (
        <div className="mt-3 divide-y divide-ui-border">
          {rows.slice(0, 4).map(({ batch, days }) => (
            <Link
              className="flex items-start justify-between gap-4 py-3 first:pt-0 last:pb-0 hover:text-ui-primary"
              href={`/products/${batch.product_id}/batches/${batch.batch_id}`}
              key={batch.batch_id}
            >
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold text-ui-text">
                  {batch.product_name}
                </p>
                <p className="mt-1 text-xs text-ui-text-muted">
                  Batch {batch.batch_code}
                </p>
              </div>

              <div className="shrink-0 text-right">
                <p className={days < 0 ? "text-xs font-semibold text-ui-danger" : "text-xs font-semibold text-ui-warning"}>
                  {days < 0 ? "Kedaluwarsa" : `${days} hari lagi`}
                </p>
                <p className="mt-1 text-xs text-ui-text-muted">
                  {formatExpiryDate(batch.expiry_date)}
                </p>
              </div>
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}
function RecentActivity({
  rows,
}: {
  rows: StockLedgerEntry[];
}) {
  return (
    <section aria-labelledby="recent-activity-heading">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-base font-semibold text-ui-text" id="recent-activity-heading">
            Pergerakan terbaru
          </h2>
          <p className="mt-1 text-sm text-ui-text-muted">
            Perubahan stok fisik yang terakhir tercatat.
          </p>
        </div>

        <Link
          className="inline-flex min-h-9 items-center gap-1.5 text-sm font-semibold text-ui-primary hover:underline"
          href="/ledger"
        >
          Lihat semua riwayat
          <span aria-hidden="true">{"\u2192"}</span>
        </Link>
      </div>

      {rows.length === 0 ? (
        <p className="mt-4 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-4 text-sm text-ui-text-muted">
          Belum ada pergerakan stok.
        </p>
      ) : (
        <div className="mt-4 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface">
          {rows.slice(0, 6).map((entry) => {
            const label = activityLabel[entry.transaction_type_code] ?? "Pergerakan Stok";
            const occurredAt = formatDate(entry.occurred_at);
            const quantityLabel = `${entry.quantity_delta > 0 ? "+" : ""}${quantity(entry.quantity_delta)}`;

            return (
              <article
                className="grid gap-1 border-b border-ui-border px-4 py-3 last:border-b-0 sm:grid-cols-[9rem_minmax(0,1fr)_auto] sm:items-center sm:gap-4 sm:px-5"
                key={entry.ledger_entry_id}
              >
                <p className="text-sm font-semibold text-ui-text">
                  {label}
                </p>

                <p className="min-w-0 truncate text-xs text-ui-text-muted">
                  {entry.product_sku_snapshot} {"\u00B7"} Batch {entry.batch_code_snapshot}
                </p>

                <div className="flex items-baseline justify-between gap-4 sm:block sm:text-right">
                  <p className={entry.quantity_delta > 0 ? "ui-number text-sm font-semibold text-ui-primary" : "ui-number text-sm font-semibold text-ui-text"}>
                    {quantityLabel}
                  </p>
                  {occurredAt ? (
                    <p className="mt-0.5 whitespace-nowrap text-xs text-ui-text-muted">
                      {occurredAt} WIB
                    </p>
                  ) : null}
                </div>
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}
export default async function HomePage() {
  const session = await requireAdminSession();

  const [dashboardResult, workResult] = await Promise.allSettled([
    getDashboardData(),
    getTodayControlCenterWorkItems({ pageSize: 10 }),
  ]);

  const dashboard =
    dashboardResult.status === "fulfilled"
      ? dashboardResult.value
      : null;
  const work =
    workResult.status === "fulfilled"
      ? workResult.value
      : null;

  const products = dashboard?.products ?? [];
  const allWorkRows = work?.rows ?? [];
  const operationalRows = allWorkRows.filter(isOperationalWorkItem);

  const activeBatchIds = new Set(
    operationalRows
      .filter((item) => item.work_type_code === "BATCH_EXPIRY")
      .map((item) => item.source_entity_id),
  );

  const riskBatches = (dashboard?.batches ?? [])
    .filter((batch) => activeBatchIds.has(batch.batch_id))
    .map((batch) => ({ batch, days: expiryDays(batch) }))
    .sort((left, right) => left.days - right.days);

  const reserved = products.reduce(
    (sum, product) => sum + Number(product.reserved_qty),
    0,
  );
  const available = products.reduce(
    (sum, product) => sum + Number(product.available_qty),
    0,
  );
  const stockUpdatedAt = products.reduce<string | null>((latest, product) => {
    if (!product.stock_updated_at) return latest;
    return !latest || product.stock_updated_at > latest
      ? product.stock_updated_at
      : latest;
  }, null);

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          description="Yang perlu Anda kerjakan dan perhatikan sekarang."
          title="Hari Ini"
        />

        <div className="mt-6">
          {workResult.status === "rejected" ? (
            <Alert title="Pekerjaan belum dapat dimuat" tone="danger">
              Coba muat ulang halaman. Data yang tidak berhasil dimuat tidak dianggap aman.
            </Alert>
          ) : (
            <PrioritySummary rows={operationalRows} />
          )}
        </div>

        <div className="mt-8 grid gap-8 lg:grid-cols-[minmax(0,1fr)_320px] lg:items-start">
          <section aria-labelledby="worklist-heading">
            <div className="flex items-baseline justify-between gap-4">
              <div>
                <h2 className="text-lg font-semibold text-ui-text" id="worklist-heading">
                  Perlu tindakan
                </h2>
                <p className="mt-1 text-sm text-ui-text-muted">
                  Kerjakan dari prioritas tertinggi.
                </p>
              </div>

              {workResult.status === "fulfilled" ? (
                <span className="ui-number text-sm font-semibold text-ui-text">
                  {quantity(operationalRows.length)} perlu ditangani
                </span>
              ) : null}
            </div>

            <div className="mt-4 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface">
              {workResult.status === "rejected" ? (
                <p className="py-5 text-sm text-ui-text-muted">
                  Daftar pekerjaan belum tersedia.
                </p>
              ) : operationalRows.length > 0 ? (
                operationalRows.map((item) => (
                  <WorkItem
                    item={item}
                    key={getTodayWorkItemReactKey(item)}
                  />
                ))
              ) : (
                <EmptyState
                  className="border-y-0"
                  description="Tidak ada pekerjaan yang membutuhkan tindakan sekarang."
                  title="Tidak ada pekerjaan tertunda"
                />
              )}
            </div>
          </section>

          <aside className="content-start">
            <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
              <p className="mb-5 text-xs font-semibold uppercase tracking-[0.08em] text-ui-text-muted">
                Ringkasan Hari Ini
              </p>

              {dashboardResult.status === "rejected" ? (
                <Alert title="Ringkasan stok belum dapat dimuat" tone="danger">
                  Coba muat ulang halaman. Data yang gagal dimuat tidak dianggap nol.
                </Alert>
              ) : (
                <StockSnapshot
                  available={available}
                  reserved={reserved}
                  updatedAt={stockUpdatedAt}
                />
              )}

              <div className="mt-5">
                {dashboardResult.status === "fulfilled" && workResult.status === "fulfilled" ? (
                  <BatchRiskList rows={riskBatches} />
                ) : (
                  <Alert title="Batch belum dapat diperiksa" tone="danger">
                    Muat ulang halaman untuk melihat batch yang membutuhkan tindakan.
                  </Alert>
                )}
              </div>
            </div>
          </aside>
        </div>

        <div className="mt-10 pt-1">
          {dashboardResult.status === "rejected" ? (
            <Alert title="Pergerakan terbaru belum dapat dimuat" tone="danger">
              Coba muat ulang halaman.
            </Alert>
          ) : (
            <RecentActivity rows={dashboard?.ledger ?? []} />
          )}
        </div>
      </div>
    </AppShell>
  );
}
