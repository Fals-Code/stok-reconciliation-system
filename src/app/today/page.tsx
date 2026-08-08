import Link from "next/link";

import { getBreadcrumbItems } from "@/app/app-shell/navigation";
import { PageHeader } from "@/app/app-shell/page-header";
import { requireAdminSession } from "@/lib/auth";
import {
  decodeTodayControlCenterCursor,
  getTodayControlCenterWorkItems,
  TODAY_CONTROL_CENTER_SEVERITIES,
  TODAY_CONTROL_CENTER_WORK_TYPES,
  type TodayControlCenterSeverity,
  type TodayControlCenterWorkItem,
  type TodayControlCenterWorkType,
} from "@/lib/supabase-rest";
import {
  Alert,
  Button,
  EmptyState,
  Field,
  Select,
  StatusBadge,
} from "@/components/ui";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 20;
const MAX_CURSOR_STACK = 20;

const severityOptions: ReadonlyArray<["ALL" | TodayControlCenterSeverity, string]> = [
  ["ALL", "Semua severity"],
  ["CRITICAL", "Kritis"],
  ["HIGH", "Segera"],
  ["WARNING", "Perhatian"],
  ["INFO", "Rutin"],
];

const workTypeLabels: Record<TodayControlCenterWorkType, string> = {
  RECONCILIATION_ISSUE: "Masalah rekonsiliasi",
  RECONCILIATION_RUN_FAILED: "Run rekonsiliasi gagal",
  TIKTOK_CLAIM_DEADLINE: "Tenggat klaim TikTok",
  RETURN_INSPECTION_PENDING: "Inspeksi retur menunggu",
  BATCH_EXPIRY: "Risiko kedaluwarsa batch",
  STOCKTAKE_RECOUNT_REQUIRED: "Hitung ulang stok opname",
  STOCKTAKE_POST_FAILED: "Posting stok opname gagal",
  NOTIFICATION_OUTBOX_FAILURE: "Outbox notifikasi gagal",
  NOTIFICATION_RULE_RUN_FAILURE: "Evaluasi notifikasi gagal",
};

const severityToBadgeTone: Record<TodayControlCenterSeverity, "neutral" | "warning" | "danger"> = {
  CRITICAL: "danger",
  HIGH: "warning",
  WARNING: "warning",
  INFO: "neutral",
};

const severityMeta: Record<TodayControlCenterSeverity, { label: string }> = {
  CRITICAL: { label: "Kritis" },
  HIGH: { label: "Segera" },
  WARNING: { label: "Perhatian" },
  INFO: { label: "Rutin" },
};

type SearchValue = string | string[] | undefined;
type TodaySearchParams = {
  severity?: SearchValue;
  workType?: SearchValue;
  cursor?: SearchValue;
};

type TodayFilterState = {
  severity: "ALL" | TodayControlCenterSeverity;
  workType: "ALL" | TodayControlCenterWorkType;
  cursorStack: string[];
  invalidState: boolean;
};

function firstParam(value: SearchValue) {
  return Array.isArray(value) ? value[0] : value;
}

function normalizeOption<T extends string>(
  value: string | undefined,
  allowed: readonly T[],
): T | null {
  const normalized = value?.trim().toUpperCase() ?? "";
  return allowed.includes(normalized as T) ? (normalized as T) : null;
}

function parseCursorStack(value: string | undefined) {
  const raw = value?.trim() ?? "";
  if (!raw) return { cursorStack: [] as string[], invalid: false };

  const cursorStack = raw.split(".");
  if (cursorStack.length > MAX_CURSOR_STACK) {
    return { cursorStack: [] as string[], invalid: true };
  }

  try {
    cursorStack.forEach((cursor) => decodeTodayControlCenterCursor(cursor));
    return { cursorStack, invalid: false };
  } catch {
    return { cursorStack: [] as string[], invalid: true };
  }
}

function filtersFromParams(params: TodaySearchParams): TodayFilterState {
  const rawSeverity = firstParam(params.severity);
  const rawWorkType = firstParam(params.workType);
  const severity = normalizeOption(rawSeverity, TODAY_CONTROL_CENTER_SEVERITIES);
  const workType = normalizeOption(rawWorkType, TODAY_CONTROL_CENTER_WORK_TYPES);
  const cursor = parseCursorStack(firstParam(params.cursor));

  return {
    severity: severity ?? "ALL",
    workType: workType ?? "ALL",
    cursorStack: cursor.cursorStack,
    invalidState:
      cursor.invalid ||
      Boolean(rawSeverity?.trim() && !severity) ||
      Boolean(rawWorkType?.trim() && !workType),
  };
}

function todayHref(state: TodayFilterState, updates: Partial<TodayFilterState> = {}) {
  const merged = { ...state, ...updates };
  const params = new URLSearchParams();

  if (merged.severity !== "ALL") params.set("severity", merged.severity);
  if (merged.workType !== "ALL") params.set("workType", merged.workType);
  if (merged.cursorStack.length > 0) params.set("cursor", merged.cursorStack.join("."));

  const query = params.toString();
  return `/today${query ? `?${query}` : ""}`;
}

function formatDate(value: string | null) {
  if (!value) return "Belum ada tenggat";

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Waktu tidak tersedia";

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function isSafeInternalRoute(routePath: string | null) {
  if (!routePath) {
    return false;
  }

  try {
    let candidate = routePath;

    for (let depth = 0; depth < 3; depth += 1) {
      if (
        !candidate.startsWith("/") ||
        candidate.startsWith("//") ||
        candidate.startsWith("/\\")
      ) {
        return false;
      }

      const decoded = decodeURIComponent(candidate);
      if (decoded === candidate) {
        return true;
      }

      candidate = decoded;
    }

    return false;
  } catch {
    return false;
  }
}

function WorkItemCard({ item }: { item: TodayControlCenterWorkItem }) {
  const actionAvailable = isSafeInternalRoute(item.route_path);
  const badgeTone = severityToBadgeTone[item.severity_code];

  return (
    <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5 hover:bg-ui-surface-subtle transition-colors" data-testid="today-work-item">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge tone={badgeTone}>{severityMeta[item.severity_code].label}</StatusBadge>
            <span className="text-xs text-ui-text-muted">{workTypeLabels[item.work_type_code]}</span>
          </div>
          <h2 className="mt-3 text-lg font-semibold text-ui-text">{item.title}</h2>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-ui-text-muted">{item.summary}</p>
        </div>
        {actionAvailable ? (
          <Link
            href={item.route_path as string}
            className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-transparent bg-transparent px-4 text-sm font-semibold text-ui-text-muted hover:bg-ui-surface-subtle hover:text-ui-text transition-colors motion-reduce:transition-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ui-focus shrink-0"
            data-testid="today-work-item-link"
          >
            Buka tindakan
          </Link>
        ) : (
          <span className="shrink-0 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle px-3 py-2 text-sm text-ui-text-muted" data-testid="today-work-item-blocked">
            Detail tindakan belum tersedia
          </span>
        )}
      </div>
      <dl className="mt-4 grid gap-3 text-xs text-ui-text-muted sm:grid-cols-2 xl:grid-cols-4">
        <div><dt className="font-mono uppercase tracking-wide text-ui-text-muted">Terjadi</dt><dd className="mt-1 text-ui-text">{formatDate(item.occurred_at)}</dd></div>
        <div><dt className="font-mono uppercase tracking-wide text-ui-text-muted">Tenggat</dt><dd className="mt-1 text-ui-text">{formatDate(item.due_at)}</dd></div>
        <div><dt className="font-mono uppercase tracking-wide text-ui-text-muted">Sumber</dt><dd className="mt-1 break-all text-ui-text">{item.source_reference ?? "Referensi tidak tersedia"}</dd></div>
        <div><dt className="font-mono uppercase tracking-wide text-ui-text-muted">Status episode</dt><dd className="mt-1 text-ui-text">{item.resolution_status === "ACKNOWLEDGED" ? "Sudah diakui" : "Aktif"}</dd></div>
      </dl>
    </article>
  );
}

function WorkItemCardMobile({ item }: { item: TodayControlCenterWorkItem }) {
  const actionAvailable = isSafeInternalRoute(item.route_path);
  const badgeTone = severityToBadgeTone[item.severity_code];

  return (
    <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4" data-testid="today-work-item-mobile">
      <div className="flex flex-wrap items-start gap-2">
        <StatusBadge tone={badgeTone}>{severityMeta[item.severity_code].label}</StatusBadge>
        <span className="text-xs text-ui-text-muted">{workTypeLabels[item.work_type_code]}</span>
      </div>
      <h2 className="mt-3 text-base font-semibold text-ui-text">{item.title}</h2>
      <p className="mt-2 text-sm leading-6 text-ui-text-muted">{item.summary}</p>
      <dl className="mt-3 grid gap-2 text-xs text-ui-text-muted sm:grid-cols-2">
        <div><dt className="font-mono uppercase tracking-wide text-ui-text-muted">Terjadi</dt><dd className="mt-0.5 text-ui-text">{formatDate(item.occurred_at)}</dd></div>
        <div><dt className="font-mono uppercase tracking-wide text-ui-text-muted">Tenggat</dt><dd className="mt-0.5 text-ui-text">{formatDate(item.due_at)}</dd></div>
        <div><dt className="font-mono uppercase tracking-wide text-ui-text-muted">Sumber</dt><dd className="mt-0.5 break-all text-ui-text">{item.source_reference ?? "Referensi tidak tersedia"}</dd></div>
        <div><dt className="font-mono uppercase tracking-wide text-ui-text-muted">Status episode</dt><dd className="mt-0.5 text-ui-text">{item.resolution_status === "ACKNOWLEDGED" ? "Sudah diakui" : "Aktif"}</dd></div>
      </dl>
      {actionAvailable ? (
        <Link
          href={item.route_path as string}
          className="mt-3 inline-flex w-full min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary text-ui-text-on-primary text-sm font-semibold hover:bg-ui-primary-hover transition-colors"
          data-testid="today-work-item-link-mobile"
        >
          Buka tindakan
        </Link>
      ) : (
        <span className="mt-3 inline-flex w-full min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle text-sm text-ui-text-muted" data-testid="today-work-item-blocked-mobile">
          Detail tindakan belum tersedia
        </span>
      )}
    </article>
  );
}

function SeveritySummaryCard({ severity, count }: { severity: TodayControlCenterSeverity; count: number }) {
  const badgeTone = severityToBadgeTone[severity];

  return (
    <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4" data-testid="today-severity-summary-card">
      <StatusBadge tone={badgeTone}>{severityMeta[severity].label}</StatusBadge>
      <p className="mt-3 text-2xl font-semibold text-ui-text">{count}</p>
      <p className="mt-1 text-xs text-ui-text-muted">item pada halaman ini</p>
    </article>
  );
}

export default async function TodayControlCenterPage({
  searchParams,
}: {
  searchParams: Promise<TodaySearchParams>;
}) {
  await requireAdminSession();
  const state = filtersFromParams(await searchParams);
  const activeCursor = state.cursorStack.at(-1);
  let data: Awaited<ReturnType<typeof getTodayControlCenterWorkItems>> | null = null;
  let loadFailed = false;

  try {
    data = await getTodayControlCenterWorkItems({
      severityCode: state.severity === "ALL" ? undefined : state.severity,
      workTypeCode: state.workType === "ALL" ? undefined : state.workType,
      cursor: activeCursor,
      pageSize: PAGE_SIZE,
    });
  } catch {
    loadFailed = true;
  }

  const rows = data?.rows ?? [];
  const severityCounts = TODAY_CONTROL_CENTER_SEVERITIES.map((severity) => ({
    severity,
    count: rows.filter((item) => item.severity_code === severity).length,
  }));
  const nextStack = data?.nextCursor ? [...state.cursorStack, data.nextCursor] : state.cursorStack;

  const severityDefaultValue = state.severity === "ALL" ? "" : state.severity;
  const workTypeDefaultValue = state.workType === "ALL" ? "" : state.workType;

  return (
    <main className="min-h-screen bg-ui-canvas text-ui-text">
      <div className="mx-auto w-full max-w-[1500px] px-5 py-8 lg:px-8">
        <PageHeader
          breadcrumb={getBreadcrumbItems("/today")}
          description="Antrean kerja read-only dari sinyal operasional aktif. Membuka atau menyaring daftar ini tidak mengubah stok maupun status bisnis."
          status={
            <StatusBadge tone="neutral">Read-only</StatusBadge>
          }
          title="Pusat Kendali Hari Ini"
        />

        {state.invalidState ? (
          <Alert tone="warning" className="mt-6" title="Filter atau tautan halaman tidak valid.">
            Menampilkan antrean dari awal dengan filter aman.
          </Alert>
        ) : null}
        {loadFailed ? (
          <Alert tone="danger" className="mt-6" title="Antrean belum dapat dimuat.">
            Coba muat ulang; tidak ada perubahan data yang dilakukan.
          </Alert>
        ) : null}

        <section className="mt-8" aria-labelledby="severity-summary-title">
          <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
            <div>
              <p className="text-xs font-mono uppercase tracking-[0.1em] text-ui-text-muted">Ringkasan halaman</p>
              <h2 id="severity-summary-title" className="mt-1 text-2xl font-semibold text-ui-text">Prioritas pada halaman ini</h2>
            </div>
            <p className="text-xs text-ui-text-muted">Urutan: Kritis, Segera, Perhatian, Rutin.</p>
          </div>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4" data-testid="today-severity-summary">
            {severityCounts.map(({ severity, count }) => (
              <SeveritySummaryCard key={severity} severity={severity} count={count} />
            ))}
          </div>
        </section>

        <section className="mt-8 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5" aria-labelledby="today-filters-title">
          <div>
            <p className="text-xs font-mono uppercase tracking-[0.1em] text-ui-text-muted">Filter</p>
            <h2 id="today-filters-title" className="mt-1 text-lg font-semibold text-ui-text">Saring tindakan</h2>
          </div>
          <form method="get" className="mt-4 grid gap-3 sm:grid-cols-[1fr_1fr_auto]" data-testid="today-filter-form">
            <Field id="today-severity-filter" label="Severity">
              {({ id, ...fieldProps }) => (
                <Select {...fieldProps} id={id} name="severity" defaultValue={severityDefaultValue}>
                  {severityOptions.map(([value, label]) => (
                    <option key={value} value={value === "ALL" ? "" : value}>{label}</option>
                  ))}
                </Select>
              )}
            </Field>
            <Field id="today-worktype-filter" label="Jenis pekerjaan">
              {({ id, ...fieldProps }) => (
                <Select {...fieldProps} id={id} name="workType" defaultValue={workTypeDefaultValue}>
                  <option value="">Semua jenis pekerjaan</option>
                  {TODAY_CONTROL_CENTER_WORK_TYPES.map((workType) => (
                    <option key={workType} value={workType}>{workTypeLabels[workType]}</option>
                  ))}
                </Select>
              )}
            </Field>
            <div className="flex items-end gap-2">
              <Button type="submit" className="min-w-[120px]">Terapkan</Button>
              <Link
                href="/today"
                className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text transition-colors hover:border-ui-border-strong hover:bg-ui-surface-subtle"
              >
                Reset
              </Link>
            </div>
          </form>
        </section>

        <section className="mt-8" aria-labelledby="today-list-title">
          <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
            <div>
              <p className="text-xs font-mono uppercase tracking-[0.1em] text-ui-text-muted">Tindakan hari ini</p>
              <h2 id="today-list-title" className="mt-1 text-2xl font-semibold text-ui-text">Sinyal aktif yang perlu diperiksa</h2>
            </div>
            <p className="text-xs text-ui-text-muted">Sumber yang sudah selesai tidak tampil lagi setelah refresh.</p>
          </div>
          {loadFailed ? null : rows.length === 0 ? (
            <EmptyState
              className="mt-5"
              title="Tidak ada tindakan aktif untuk filter ini"
              description="Episode yang sudah selesai atau ditutup tidak ditampilkan."
              data-testid="today-empty-state"
            />
          ) : (
            <>
              <div className="mt-5 space-y-3 hidden sm:block" data-testid="today-work-list-desktop">
                {rows.map((item) => (
                  <WorkItemCard key={item.work_item_id} item={item} />
                ))}
              </div>
              <div className="mt-5 space-y-3 sm:hidden" data-testid="today-work-list-mobile">
                {rows.map((item) => (
                  <WorkItemCardMobile key={item.work_item_id} item={item} />
                ))}
              </div>
            </>
          )}

          {!loadFailed && (
            <nav className="mt-6 flex flex-wrap items-center justify-between gap-3" aria-label="Pagination tindakan hari ini">
              {state.cursorStack.length > 0 ? (
                <Link
                  href={todayHref(state, { cursorStack: state.cursorStack.slice(0, -1) })}
                  className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text transition-colors hover:border-ui-border-strong hover:bg-ui-surface-subtle"
                  data-testid="today-previous-page"
                >
                  Sebelumnya
                </Link>
              ) : (
                <span className="text-sm text-ui-text-muted">Halaman pertama</span>
              )}
              {data?.hasNextPage && data.nextCursor ? (
                <Link
                  href={todayHref(state, { cursorStack: nextStack })}
                  className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary text-ui-text-on-primary px-4 text-sm font-semibold hover:bg-ui-primary-hover transition-colors"
                  data-testid="today-next-page"
                >
                  Berikutnya
                </Link>
              ) : (
                <span className="text-sm text-ui-text-muted">Tidak ada halaman berikutnya</span>
              )}
            </nav>
          )}
        </section>
      </div>
    </main>
  );
}
