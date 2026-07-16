import Link from "next/link";
import type { ReactNode } from "react";

import PageSectionNav from "@/app/app-shell/page-section-nav";
import {
  acknowledgeNotificationAction,
  revokeNotificationAcknowledgmentAction,
  setNotificationReadStateAction,
} from "@/app/notifications/actions";
import {
  getNotificationDetail,
  getNotificationEventHistory,
  getNotificationList,
  type NotificationDetail,
  type NotificationEventHistoryItem,
  type NotificationListItem,
  type NotificationListFilters,
  type NotificationReadStateCode,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 50;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type SearchParams = {
  lifecycle?: string;
  severity?: string;
  category?: string;
  readState?: string;
  archived?: string;
  before?: string;
  beforeId?: string;
  notificationId?: string;
  success?: string;
  error?: string;
};

type FilterState = {
  lifecycle: string;
  severity: string;
  category: string;
  readState: string;
  includeArchived: boolean;
  before: string | null;
  beforeId: string | null;
  notificationId: string | null;
};

type PillTone = "success" | "warning" | "danger" | "info" | "neutral";

const lifecycleOptions = [
  ["ALL", "Semua lifecycle"],
  ["OPEN", "Open"],
  ["ACKNOWLEDGED", "Acknowledged"],
  ["RESOLVED", "Resolved"],
] as const;

const severityOptions = [
  ["ALL", "Semua severity"],
  ["CRITICAL", "Critical"],
  ["HIGH", "High"],
  ["WARNING", "Warning"],
  ["INFO", "Info"],
] as const;

const categoryOptions = [
  ["ALL", "Semua kategori"],
  ["EXPIRY", "Kedaluwarsa"],
  ["RETURN", "Retur"],
  ["RECONCILIATION", "Rekonsiliasi"],
  ["STOCKTAKE", "Stok opname"],
] as const;

const readStateOptions = [
  ["ALL", "Semua status baca"],
  ["UNREAD", "Belum dibaca"],
  ["READ", "Sudah dibaca"],
  ["ARCHIVED_FOR_USER", "Diarsipkan"],
] as const;

function normalizeOption(
  value: string | undefined,
  allowed: readonly string[],
  fallback = "ALL",
) {
  const normalized = value?.trim().toUpperCase() || fallback;
  return allowed.includes(normalized) ? normalized : fallback;
}

function normalizeSearchParams(params: SearchParams): FilterState {
  const before = params.before?.trim() || null;
  const beforeId =
    params.beforeId && UUID_PATTERN.test(params.beforeId.trim())
      ? params.beforeId.trim()
      : null;
  const notificationId =
    params.notificationId && UUID_PATTERN.test(params.notificationId.trim())
      ? params.notificationId.trim()
      : null;

  return {
    lifecycle: normalizeOption(
      params.lifecycle,
      lifecycleOptions.map(([value]) => value),
    ),
    severity: normalizeOption(
      params.severity,
      severityOptions.map(([value]) => value),
    ),
    category: normalizeOption(
      params.category,
      categoryOptions.map(([value]) => value),
    ),
    readState: normalizeOption(
      params.readState,
      readStateOptions.map(([value]) => value),
    ),
    includeArchived: params.archived === "1",
    before:
      before && !Number.isNaN(new Date(before).getTime()) ? before : null,
    beforeId,
    notificationId,
  };
}

function notificationHref(
  state: FilterState,
  updates: Partial<FilterState>,
  hash?: "notifications" | "detail",
) {
  const merged = { ...state, ...updates };
  const params = new URLSearchParams();

  if (merged.lifecycle !== "ALL") {
    params.set("lifecycle", merged.lifecycle);
  }
  if (merged.severity !== "ALL") {
    params.set("severity", merged.severity);
  }
  if (merged.category !== "ALL") {
    params.set("category", merged.category);
  }
  if (merged.readState !== "ALL") {
    params.set("readState", merged.readState);
  }
  if (merged.includeArchived) {
    params.set("archived", "1");
  }
  if (merged.before && merged.beforeId) {
    params.set("before", merged.before);
    params.set("beforeId", merged.beforeId);
  }
  if (merged.notificationId) {
    params.set("notificationId", merged.notificationId);
  }

  const query = params.toString();
  return `/notifications${query ? `?${query}` : ""}${hash ? `#${hash}` : ""}`;
}

function formatDate(value: string | null) {
  if (!value) return "Belum tersedia";

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;

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

function formatJson(value: unknown) {
  if (value === null || value === undefined) return "Tidak ada";

  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function severityTone(severity: string): PillTone {
  if (severity === "CRITICAL") return "danger";
  if (severity === "HIGH" || severity === "WARNING") return "warning";
  if (severity === "INFO") return "info";
  return "neutral";
}

function lifecycleTone(lifecycle: string): PillTone {
  if (lifecycle === "RESOLVED") return "success";
  if (lifecycle === "ACKNOWLEDGED") return "info";
  if (lifecycle === "OPEN") return "warning";
  return "neutral";
}

function readTone(readState: string): PillTone {
  if (readState === "UNREAD") return "danger";
  if (readState === "READ") return "success";
  return "neutral";
}

function labelFromCode(value: string) {
  return value
    .toLowerCase()
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function Pill({ label, tone }: { label: string; tone: PillTone }) {
  const tones: Record<PillTone, string> = {
    success: "border-emerald-400/25 bg-emerald-400/10 text-emerald-200",
    warning: "border-amber-400/25 bg-amber-400/10 text-amber-100",
    danger: "border-rose-400/25 bg-rose-400/10 text-rose-100",
    info: "border-sky-400/25 bg-sky-400/10 text-sky-100",
    neutral: "border-white/10 bg-white/[0.04] text-slate-300",
  };

  return (
    <span
      className={`inline-flex rounded-full border px-2.5 py-1 text-xs font-medium ${tones[tone]}`}
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
          Notification Center tidak tersedia
        </p>
        <h1 className="mt-3 text-3xl font-semibold">
          Data notifikasi gagal dimuat.
        </h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <Link className="nav-link mt-6 inline-flex" href="/">
          Kembali ke dashboard
        </Link>
      </section>
    </main>
  );
}

function EmptyState() {
  return (
    <div className="rounded-3xl border border-dashed border-white/15 bg-white/[0.02] px-6 py-14 text-center">
      <p className="font-mono text-xs uppercase tracking-[0.18em] text-emerald-300">
        Tidak ada alert
      </p>
      <h2 className="mt-3 text-2xl font-semibold text-white">
        Filter ini tidak menghasilkan notifikasi.
      </h2>
      <p className="mx-auto mt-3 max-w-xl text-sm leading-6 text-slate-400">
        Kondisi operasional mungkin memang aman, atau filternya terlalu rajin
        menyaring. Keduanya lebih baik daripada daftar alert palsu.
      </p>
    </div>
  );
}

function NotificationCard({
  notification,
  state,
  selected,
}: {
  notification: NotificationListItem;
  state: FilterState;
  selected: boolean;
}) {
  return (
    <article
      className={[
        "rounded-2xl border p-5 transition",
        selected
          ? "border-emerald-400/35 bg-emerald-400/[0.07]"
          : notification.read_state_code === "UNREAD"
            ? "border-white/15 bg-white/[0.045] hover:border-white/25"
            : "border-white/10 bg-white/[0.025] hover:border-white/20",
      ].join(" ")}
    >
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap gap-2">
            <Pill
              label={labelFromCode(notification.severity_code)}
              tone={severityTone(notification.severity_code)}
            />
            <Pill
              label={labelFromCode(notification.lifecycle_status_code)}
              tone={lifecycleTone(notification.lifecycle_status_code)}
            />
            <Pill
              label={labelFromCode(notification.read_state_code)}
              tone={readTone(notification.read_state_code)}
            />
          </div>

          <h3 className="mt-4 text-lg font-semibold text-white">
            {notification.title}
          </h3>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
            {notification.message}
          </p>
        </div>

        <div className="shrink-0 text-left text-xs text-slate-500 sm:text-right">
          <p>{formatDate(notification.last_seen_at)} WIB</p>
          <p className="mt-1 font-mono">
            {notification.category_code} · {notification.stage_code}
          </p>
        </div>
      </div>

      <div className="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-white/10 pt-4">
        <div className="text-xs text-slate-500">
          Episode {notification.episode_no} · muncul{" "}
          {notification.occurrence_count} kali
        </div>
        <Link
          className="rounded-xl border border-white/10 bg-white/[0.035] px-3 py-2 text-sm font-medium text-slate-200 transition hover:border-emerald-400/25 hover:bg-emerald-400/[0.08]"
          href={notificationHref(
            state,
            {
              notificationId: notification.notification_id,
            },
            "detail",
          )}
        >
          Lihat detail
        </Link>
      </div>
    </article>
  );
}

function DetailField({
  label,
  value,
}: {
  label: string;
  value: ReactNode;
}) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.025] p-4">
      <dt className="font-mono text-[0.65rem] uppercase tracking-[0.14em] text-slate-600">
        {label}
      </dt>
      <dd className="mt-2 break-words text-sm leading-6 text-slate-300">
        {value}
      </dd>
    </div>
  );
}

const READ_STATE_ACTIONS = [
  {
    code: "UNREAD",
    label: "Tandai belum dibaca",
    description: "Kembalikan alert ke antrean unread akun ini.",
  },
  {
    code: "READ",
    label: "Tandai sudah dibaca",
    description: "Simpan versi notification yang sudah dilihat.",
  },
  {
    code: "ARCHIVED_FOR_USER",
    label: "Arsipkan",
    description: "Sembunyikan alert dari daftar utama akun ini.",
  },
] as const satisfies readonly {
  code: NotificationReadStateCode;
  label: string;
  description: string;
}[];

function ActionContextFields({
  notificationId,
  returnTo,
}: {
  notificationId: string;
  returnTo: string;
}) {
  return (
    <>
      <input name="notificationId" type="hidden" value={notificationId} />
      <input name="returnTo" type="hidden" value={returnTo} />
    </>
  );
}

function NotificationActions({
  detail,
  returnTo,
}: {
  detail: NotificationDetail;
  returnTo: string;
}) {
  const readActions = READ_STATE_ACTIONS.filter(
    (action) => action.code !== detail.read_state_code,
  );

  return (
    <section className="mt-6 grid gap-5 xl:grid-cols-2">
      <div className="rounded-2xl border border-white/10 bg-white/[0.02] p-5">
        <p className="section-kicker">Status pribadi</p>
        <h3 className="mt-1 text-lg font-semibold text-white">
          Atur status baca akun ini.
        </h3>
        <p className="mt-2 text-sm leading-6 text-slate-500">
          Perubahan ini tidak mengubah lifecycle organisasi atau status untuk
          Admin lain.
        </p>

        <div className="mt-5 space-y-3">
          {readActions.map((action) => (
            <form
              action={setNotificationReadStateAction}
              className="flex flex-col gap-3 rounded-xl border border-white/10 bg-slate-950/45 p-4 sm:flex-row sm:items-center sm:justify-between"
              key={action.code}
            >
              <ActionContextFields
                notificationId={detail.notification_id}
                returnTo={returnTo}
              />
              <input
                name="readStateCode"
                type="hidden"
                value={action.code}
              />
              <div>
                <p className="text-sm font-medium text-slate-200">
                  {action.label}
                </p>
                <p className="mt-1 text-xs leading-5 text-slate-500">
                  {action.description}
                </p>
              </div>
              <button
                className={[
                  "shrink-0 rounded-xl border px-3 py-2 text-sm font-medium transition",
                  action.code === "ARCHIVED_FOR_USER"
                    ? "border-amber-400/20 bg-amber-400/[0.07] text-amber-100 hover:bg-amber-400/10"
                    : "border-white/10 bg-white/[0.035] text-slate-200 hover:border-emerald-400/25 hover:bg-emerald-400/[0.08]",
                ].join(" ")}
                type="submit"
              >
                {action.label}
              </button>
            </form>
          ))}
        </div>
      </div>

      <div className="rounded-2xl border border-white/10 bg-white/[0.02] p-5">
        <p className="section-kicker">Lifecycle organisasi</p>
        <h3 className="mt-1 text-lg font-semibold text-white">
          Catat tanggung jawab atas alert.
        </h3>
        <p className="mt-2 text-sm leading-6 text-slate-500">
          Acknowledge dan pembatalannya ditulis ke audit trail dan berlaku
          untuk organisasi, bukan hanya akun ini.
        </p>

        {detail.lifecycle_status_code === "OPEN" ? (
          <form action={acknowledgeNotificationAction} className="mt-5">
            <ActionContextFields
              notificationId={detail.notification_id}
              returnTo={returnTo}
            />
            <label className="field-label">
              Catatan acknowledgment
              <textarea
                maxLength={2000}
                name="note"
                placeholder="Opsional: siapa yang menindaklanjuti dan langkah awalnya."
                rows={4}
              />
            </label>
            <button className="primary-button mt-4" type="submit">
              Acknowledge notification
            </button>
          </form>
        ) : null}

        {detail.lifecycle_status_code === "ACKNOWLEDGED" ? (
          <form
            action={revokeNotificationAcknowledgmentAction}
            className="mt-5"
          >
            <ActionContextFields
              notificationId={detail.notification_id}
              returnTo={returnTo}
            />
            <label className="field-label">
              Alasan pembatalan
              <textarea
                maxLength={2000}
                name="note"
                placeholder="Opsional: jelaskan mengapa alert perlu kembali open."
                rows={4}
              />
            </label>
            <button
              className="mt-4 rounded-xl border border-amber-400/25 bg-amber-400/[0.07] px-4 py-2.5 text-sm font-semibold text-amber-100 transition hover:bg-amber-400/12"
              type="submit"
            >
              Batalkan acknowledgment
            </button>
          </form>
        ) : null}

        {detail.lifecycle_status_code === "RESOLVED" ? (
          <div className="mt-5 rounded-xl border border-emerald-400/20 bg-emerald-400/[0.055] p-4 text-sm leading-6 text-emerald-100">
            Notification sudah resolved. Lifecycle ditutup oleh evaluator dan
            tidak dapat di-acknowledge ulang.
          </div>
        ) : null}
      </div>
    </section>
  );
}

function NotificationDetailPanel({
  detail,
  history,
  state,
}: {
  detail: NotificationDetail;
  history: NotificationEventHistoryItem[];
  state: FilterState;
}) {
  return (
    <section
      className="scroll-mt-24 rounded-3xl border border-white/10 bg-white/[0.025] p-5 lg:p-6"
      id="detail"
    >
      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="section-kicker">Detail notifikasi</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">
            {detail.title}
          </h2>
          <p className="mt-3 text-sm leading-6 text-slate-400">
            {detail.message}
          </p>
        </div>
        <Link
          className="shrink-0 rounded-xl border border-white/10 px-3 py-2 text-sm text-slate-300 transition hover:bg-white/[0.05]"
          href={notificationHref(
            state,
            { notificationId: null },
            "notifications",
          )}
        >
          Tutup detail
        </Link>
      </div>

      <div className="mt-5 flex flex-wrap gap-2">
        <Pill
          label={labelFromCode(detail.severity_code)}
          tone={severityTone(detail.severity_code)}
        />
        <Pill
          label={labelFromCode(detail.lifecycle_status_code)}
          tone={lifecycleTone(detail.lifecycle_status_code)}
        />
        <Pill
          label={labelFromCode(detail.read_state_code)}
          tone={readTone(detail.read_state_code)}
        />
        <Pill label={labelFromCode(detail.category_code)} tone="neutral" />
      </div>

      <NotificationActions
        detail={detail}
        returnTo={notificationHref(state, {}, "detail")}
      />

      <dl className="mt-6 grid gap-3 sm:grid-cols-2">
        <DetailField label="Rule" value={detail.rule_code} />
        <DetailField label="Stage" value={detail.stage_code} />
        <DetailField label="Entity" value={`${detail.entity_type_code} · ${detail.entity_id}`} />
        <DetailField label="Episode" value={detail.episode_no} />
        <DetailField label="Mulai kondisi" value={`${formatDate(detail.condition_started_at)} WIB`} />
        <DetailField label="Batas waktu" value={`${formatDate(detail.due_at)} WIB`} />
        <DetailField label="Pertama terlihat" value={`${formatDate(detail.first_seen_at)} WIB`} />
        <DetailField label="Terakhir terlihat" value={`${formatDate(detail.last_seen_at)} WIB`} />
        <DetailField
          label="Acknowledgment"
          value={
            detail.acknowledged_at
              ? `${detail.acknowledged_by_display_name ?? "Admin"} · ${formatDate(detail.acknowledged_at)} WIB`
              : "Belum diakui"
          }
        />
        <DetailField
          label="Resolusi"
          value={
            detail.resolved_at
              ? `${detail.resolution_code ?? "RESOLVED"} · ${formatDate(detail.resolved_at)} WIB`
              : "Belum terselesaikan"
          }
        />
      </dl>

      {detail.action_route ? (
        <div className="mt-5 rounded-2xl border border-emerald-400/20 bg-emerald-400/[0.055] p-4">
          <p className="text-sm text-emerald-100">
            Buka sumber operasional untuk menindaklanjuti kondisi ini.
          </p>
          <Link
            className="mt-3 inline-flex rounded-xl bg-emerald-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-emerald-200"
            href={detail.action_route}
          >
            Buka tindak lanjut
          </Link>
        </div>
      ) : null}

      <div className="mt-7 grid gap-5 xl:grid-cols-2">
        <section>
          <h3 className="text-lg font-semibold text-white">Source snapshot</h3>
          <pre className="mt-3 max-h-96 overflow-auto rounded-2xl border border-white/10 bg-slate-950/80 p-4 text-xs leading-6 text-slate-300">
            {formatJson(detail.source_snapshot)}
          </pre>
        </section>
        <section>
          <h3 className="text-lg font-semibold text-white">Config snapshot</h3>
          <pre className="mt-3 max-h-96 overflow-auto rounded-2xl border border-white/10 bg-slate-950/80 p-4 text-xs leading-6 text-slate-300">
            {formatJson(detail.config_snapshot)}
          </pre>
        </section>
      </div>

      <section className="mt-8">
        <div className="flex items-end justify-between gap-4">
          <div>
            <p className="section-kicker">Audit trail</p>
            <h3 className="mt-1 text-xl font-semibold text-white">
              Riwayat lifecycle
            </h3>
          </div>
          <span className="rounded-full border border-white/10 px-3 py-1 text-xs text-slate-500">
            {history.length} event
          </span>
        </div>

        {history.length ? (
          <div className="mt-4 space-y-3">
            {history.map((event) => (
              <article
                className="rounded-2xl border border-white/10 bg-white/[0.02] p-4"
                key={event.event_id}
              >
                <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <p className="font-medium text-slate-200">
                      {labelFromCode(event.event_type_code)}
                    </p>
                    <p className="mt-1 text-xs text-slate-500">
                      {event.actor_display_name ??
                        event.process_name ??
                        labelFromCode(event.actor_type_code)}
                    </p>
                  </div>
                  <p className="text-xs text-slate-500">
                    {formatDate(event.occurred_at)} WIB
                  </p>
                </div>
                {event.note ? (
                  <p className="mt-3 text-sm leading-6 text-slate-400">
                    {event.note}
                  </p>
                ) : null}
                <div className="mt-3 flex flex-wrap gap-2 text-xs text-slate-500">
                  {event.from_lifecycle_status_code ||
                  event.to_lifecycle_status_code ? (
                    <span>
                      {event.from_lifecycle_status_code ?? "—"} →{" "}
                      {event.to_lifecycle_status_code ?? "—"}
                    </span>
                  ) : null}
                  {event.from_stage_code || event.to_stage_code ? (
                    <span>
                      · {event.from_stage_code ?? "—"} →{" "}
                      {event.to_stage_code ?? "—"}
                    </span>
                  ) : null}
                </div>
              </article>
            ))}
          </div>
        ) : (
          <p className="mt-4 rounded-2xl border border-dashed border-white/10 p-5 text-sm text-slate-500">
            Belum ada event lifecycle yang dapat ditampilkan.
          </p>
        )}
      </section>
    </section>
  );
}

export default async function NotificationsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const state = normalizeSearchParams(params);
  const feedbackError = params.error?.trim().slice(0, 500) || null;
  const feedbackSuccess = feedbackError
    ? null
    : params.success?.trim().slice(0, 500) || null;

  const filters: NotificationListFilters = {
    lifecycleStatusCode:
      state.lifecycle === "ALL" ? null : state.lifecycle,
    severityCode: state.severity === "ALL" ? null : state.severity,
    categoryCode: state.category === "ALL" ? null : state.category,
    readStateCode: state.readState === "ALL" ? null : state.readState,
    includeArchived: state.includeArchived,
    limit: PAGE_SIZE,
    beforeLastSeenAt:
      state.before && state.beforeId ? state.before : null,
    beforeId: state.before && state.beforeId ? state.beforeId : null,
  };

  let notifications: NotificationListItem[];
  let detail: NotificationDetail | null = null;
  let history: NotificationEventHistoryItem[] = [];

  try {
    notifications = await getNotificationList(filters);

    if (state.notificationId) {
      [detail, history] = await Promise.all([
        getNotificationDetail(state.notificationId),
        getNotificationEventHistory(state.notificationId),
      ]);
    }
  } catch (error) {
    return (
      <ConfigurationError
        message={
          error instanceof Error
            ? error.message
            : "Konfigurasi Notification Center tidak valid."
        }
      />
    );
  }

  const openCount = notifications.filter(
    (notification) => notification.lifecycle_status_code === "OPEN",
  ).length;
  const criticalCount = notifications.filter(
    (notification) => notification.severity_code === "CRITICAL",
  ).length;
  const unreadCount = notifications.filter(
    (notification) => notification.read_state_code === "UNREAD",
  ).length;
  const lastNotification = notifications.at(-1) ?? null;
  const nextCursor =
    notifications.length === PAGE_SIZE ? lastNotification : null;

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <PageSectionNav
        items={[
          { href: "#overview", label: "Ringkasan" },
          { href: "#filters", label: "Filter" },
          { href: "#notifications", label: "Daftar" },
          ...(detail ? [{ href: "#detail" as const, label: "Detail" }] : []),
        ]}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section className="scroll-mt-24" id="overview">
          <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="font-mono text-xs uppercase tracking-[0.2em] text-emerald-300">
                Notification Center
              </p>
              <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
                Alert operasional yang punya sumber dan histori.
              </h1>
              <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
                Pantau risiko kedaluwarsa, inspeksi retur, rekonsiliasi, dan
                stok opname tanpa mencampurkan status baca pribadi dengan
                lifecycle organisasi.
              </p>
            </div>
            <div className="rounded-2xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm text-slate-400">
              Menampilkan {notifications.length} notifikasi
            </div>
          </div>

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              ["Ditampilkan", notifications.length, "Sesuai filter aktif"],
              ["Open", openCount, "Belum diakui atau diselesaikan"],
              ["Critical", criticalCount, "Prioritas tertinggi"],
              ["Unread", unreadCount, "Belum dibaca oleh akun ini"],
            ].map(([label, value, description]) => (
              <article className="metric-card" key={label}>
                <p className="text-sm text-slate-400">{label}</p>
                <p className="mt-3 text-3xl font-semibold text-white">
                  {Number(value).toLocaleString("id-ID")}
                </p>
                <p className="mt-2 text-xs text-slate-500">{description}</p>
              </article>
            ))}
          </div>
        </section>

        {feedbackSuccess ? (
          <div className="mt-6 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-100">
            {feedbackSuccess}
          </div>
        ) : null}

        {feedbackError ? (
          <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-100">
            {feedbackError}
          </div>
        ) : null}

        <section className="mt-10 scroll-mt-24" id="filters">
          <div className="mb-5">
            <p className="section-kicker">Filter server-side</p>
            <h2 className="section-title">
              Kurangi kebisingan tanpa menghapus bukti.
            </h2>
          </div>

          <form
            action="/notifications"
            className="grid gap-4 rounded-3xl border border-white/10 bg-white/[0.025] p-5 sm:grid-cols-2 xl:grid-cols-5"
            method="get"
          >
            <label className="field-label">
              Lifecycle
              <select defaultValue={state.lifecycle} name="lifecycle">
                {lifecycleOptions.map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>

            <label className="field-label">
              Severity
              <select defaultValue={state.severity} name="severity">
                {severityOptions.map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>

            <label className="field-label">
              Kategori
              <select defaultValue={state.category} name="category">
                {categoryOptions.map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>

            <label className="field-label">
              Status baca
              <select defaultValue={state.readState} name="readState">
                {readStateOptions.map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>

            <div className="flex flex-col justify-end gap-3">
              <label className="flex items-center gap-2 text-sm text-slate-400">
                <input
                  defaultChecked={state.includeArchived}
                  name="archived"
                  type="checkbox"
                  value="1"
                />
                Sertakan arsip pribadi
              </label>
              <div className="flex gap-2">
                <button className="primary-button flex-1" type="submit">
                  Terapkan
                </button>
                <Link
                  className="flex items-center justify-center rounded-xl border border-white/10 px-3 text-sm text-slate-300 transition hover:bg-white/[0.05]"
                  href="/notifications"
                >
                  Reset
                </Link>
              </div>
            </div>
          </form>
        </section>

        <section className="mt-10 scroll-mt-24" id="notifications">
          <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="section-kicker">Alert stream</p>
              <h2 className="section-title">Notifikasi terbaru.</h2>
            </div>
            {state.before && state.beforeId ? (
              <Link
                className="text-sm text-emerald-300 hover:text-emerald-200"
                href={notificationHref(
                  state,
                  { before: null, beforeId: null },
                  "notifications",
                )}
              >
                Kembali ke halaman terbaru
              </Link>
            ) : null}
          </div>

          {notifications.length ? (
            <div className="space-y-4">
              {notifications.map((notification) => (
                <NotificationCard
                  key={notification.notification_id}
                  notification={notification}
                  selected={
                    detail?.notification_id === notification.notification_id
                  }
                  state={state}
                />
              ))}
            </div>
          ) : (
            <EmptyState />
          )}

          {nextCursor ? (
            <div className="mt-6 flex justify-center">
              <Link
                className="rounded-xl border border-white/10 bg-white/[0.035] px-5 py-3 text-sm font-medium text-slate-200 transition hover:border-emerald-400/25 hover:bg-emerald-400/[0.08]"
                href={notificationHref(
                  state,
                  {
                    before: nextCursor.last_seen_at,
                    beforeId: nextCursor.notification_id,
                    notificationId: null,
                  },
                  "notifications",
                )}
              >
                Muat notifikasi lebih lama
              </Link>
            </div>
          ) : null}
        </section>

        {detail ? (
          <div className="mt-10">
            <NotificationDetailPanel
              detail={detail}
              history={history}
              state={state}
            />
          </div>
        ) : state.notificationId ? (
          <section className="mt-10 rounded-3xl border border-amber-400/20 bg-amber-400/[0.055] p-6 text-amber-100">
            Notifikasi yang dipilih tidak ditemukan dalam organisasi aktif.
          </section>
        ) : null}
      </div>
    </main>
  );
}
