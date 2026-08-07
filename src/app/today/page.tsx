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

const severityMeta: Record<TodayControlCenterSeverity, { label: string; tone: string }> = {
  CRITICAL: { label: "Kritis", tone: "border-rose-400/30 bg-rose-400/10 text-rose-200" },
  HIGH: { label: "Segera", tone: "border-amber-400/30 bg-amber-400/10 text-amber-100" },
  WARNING: { label: "Perhatian", tone: "border-sky-400/30 bg-sky-400/10 text-sky-100" },
  INFO: { label: "Rutin", tone: "border-white/15 bg-white/[0.04] text-slate-200" },
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

function SeverityBadge({ severity }: { severity: TodayControlCenterSeverity }) {
  const meta = severityMeta[severity];
  return <span className={`status-pill border ${meta.tone}`}>{meta.label}</span>;
}

function WorkItemCard({ item }: { item: TodayControlCenterWorkItem }) {
  const actionAvailable = isSafeInternalRoute(item.route_path);

  return (
    <article className="rounded-2xl border border-white/10 bg-white/[0.025] p-5" data-testid="today-work-item">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <SeverityBadge severity={item.severity_code} />
            <span className="text-xs text-slate-400">{workTypeLabels[item.work_type_code]}</span>
          </div>
          <h2 className="mt-3 text-lg font-semibold text-white">{item.title}</h2>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-slate-300">{item.summary}</p>
        </div>
        {actionAvailable ? (
          <Link className="nav-link shrink-0" href={item.route_path as string} data-testid="today-work-item-link">
            Buka tindakan
          </Link>
        ) : (
          <span className="shrink-0 rounded-xl border border-white/10 px-3 py-2 text-sm text-slate-500" data-testid="today-work-item-blocked">
            Detail tindakan belum tersedia
          </span>
        )}
      </div>
      <dl className="mt-5 grid gap-3 text-xs text-slate-400 sm:grid-cols-2 xl:grid-cols-4">
        <div><dt className="font-mono uppercase tracking-wide text-slate-600">Terjadi</dt><dd className="mt-1 text-slate-300">{formatDate(item.occurred_at)}</dd></div>
        <div><dt className="font-mono uppercase tracking-wide text-slate-600">Tenggat</dt><dd className="mt-1 text-slate-300">{formatDate(item.due_at)}</dd></div>
        <div><dt className="font-mono uppercase tracking-wide text-slate-600">Sumber</dt><dd className="mt-1 break-all text-slate-300">{item.source_reference ?? "Referensi tidak tersedia"}</dd></div>
        <div><dt className="font-mono uppercase tracking-wide text-slate-600">Status episode</dt><dd className="mt-1 text-slate-300">{item.resolution_status === "ACKNOWLEDGED" ? "Sudah diakui" : "Aktif"}</dd></div>
      </dl>
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

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto w-full max-w-[1500px] px-5 py-8 lg:px-8">
        <PageHeader
          breadcrumb={getBreadcrumbItems("/today")}
          description="Antrean kerja read-only dari sinyal operasional aktif. Membuka atau menyaring daftar ini tidak mengubah stok maupun status bisnis."
          status={
            <span className="status-pill status-neutral">
              Read-only
            </span>
          }
          title="Pusat Kendali Hari Ini"
        />

        {state.invalidState ? <div className="mt-6 rounded-2xl border border-amber-400/20 bg-amber-400/10 p-4 text-sm text-amber-100" role="status">Filter atau tautan halaman tidak valid. Menampilkan antrean dari awal dengan filter aman.</div> : null}
        {loadFailed ? <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/10 p-4 text-sm text-rose-100" role="alert">Antrean belum dapat dimuat. Coba muat ulang; tidak ada perubahan data yang dilakukan.</div> : null}

        <section className="mt-8" aria-labelledby="severity-summary-title">
          <div className="mb-4 flex flex-wrap items-end justify-between gap-3"><div><p className="section-kicker">Ringkasan halaman</p><h2 id="severity-summary-title" className="section-title">Prioritas pada halaman ini</h2></div><p className="text-xs text-slate-500">Urutan: Kritis, Segera, Perhatian, Rutin.</p></div>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4" data-testid="today-severity-summary">
            {severityCounts.map(({ severity, count }) => (
              <article key={severity} className="metric-card">
                <SeverityBadge severity={severity} />
                <p className="mt-3 text-3xl font-semibold text-white">{count}</p>
                <p className="mt-2 text-xs text-slate-500">item pada halaman ini</p>
              </article>
            ))}
          </div>
        </section>

        <section className="panel-card mt-8" aria-labelledby="today-filters-title">
          <div><p className="section-kicker">Filter</p><h2 id="today-filters-title" className="section-title">Saring tindakan</h2></div>
          <form method="get" className="mt-5 grid gap-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto]" data-testid="today-filter-form">
            <label className="field-label">Severity<select name="severity" defaultValue={state.severity}>{severityOptions.map(([value, label]) => <option key={value} value={value === "ALL" ? "" : value}>{label}</option>)}</select></label>
            <label className="field-label">Jenis pekerjaan<select name="workType" defaultValue={state.workType}><option value="">Semua jenis pekerjaan</option>{TODAY_CONTROL_CENTER_WORK_TYPES.map((workType) => <option key={workType} value={workType}>{workTypeLabels[workType]}</option>)}</select></label>
            <div className="flex items-end gap-2"><button className="primary-button" type="submit">Terapkan</button><Link className="nav-link" href="/today">Reset</Link></div>
          </form>
        </section>

        <section className="mt-8" aria-labelledby="today-list-title">
          <div className="flex flex-wrap items-end justify-between gap-3"><div><p className="section-kicker">Tindakan hari ini</p><h2 id="today-list-title" className="section-title">Sinyal aktif yang perlu diperiksa</h2></div><p className="text-xs text-slate-500">Sumber yang sudah selesai tidak tampil lagi setelah refresh.</p></div>
          {loadFailed ? null : rows.length === 0 ? (
            <div className="mt-5 rounded-2xl border border-dashed border-white/15 p-8 text-center text-sm leading-6 text-slate-400" data-testid="today-empty-state">Tidak ada tindakan aktif untuk filter ini. Episode yang sudah selesai atau ditutup tidak ditampilkan.</div>
          ) : (
            <div className="mt-5 space-y-4">{rows.map((item) => <WorkItemCard key={item.work_item_id} item={item} />)}</div>
          )}

          {!loadFailed ? <nav className="mt-6 flex flex-wrap items-center justify-between gap-3" aria-label="Pagination tindakan hari ini">
            {state.cursorStack.length > 0 ? <Link className="nav-link" href={todayHref(state, { cursorStack: state.cursorStack.slice(0, -1) })} data-testid="today-previous-page">Sebelumnya</Link> : <span className="text-sm text-slate-600">Halaman pertama</span>}
            {data?.hasNextPage && data.nextCursor ? <Link className="nav-link" href={todayHref(state, { cursorStack: nextStack })} data-testid="today-next-page">Berikutnya</Link> : <span className="text-sm text-slate-600">Tidak ada halaman berikutnya</span>}
          </nav> : null}
        </section>
      </div>
    </main>
  );
}
