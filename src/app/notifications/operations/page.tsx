import { randomUUID } from "node:crypto";

import Link from "next/link";

import PageSectionNav from "@/app/app-shell/page-section-nav";
import {
  retryNotificationOutboxEventAction,
  runNotificationEvaluationAction,
} from "@/app/notifications/operations/actions";
import {
  getNotificationOperationsSummary,
  getNotificationOutboxActionableList,
  type NotificationEvaluationFamilyCode,
  type NotificationOperationsSummary,
  type NotificationOutboxActionableItem,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = {
  status?: string;
  success?: string;
  error?: string;
};

type PillTone =
  | "success"
  | "warning"
  | "danger"
  | "info"
  | "neutral";

const statusOptions = [
  ["ALL", "Semua actionable"],
  ["FAILED_FINAL", "Failed final"],
  ["FAILED_RETRYABLE", "Failed retryable"],
  ["PROCESSING", "Processing"],
  ["PENDING", "Pending"],
] as const;

const evaluationFamilies = [
  {
    code: "EXPIRY",
    title: "Expiry",
    description:
      "Evaluasi batch mendekati atau melewati masa kedaluwarsa.",
  },
  {
    code: "RETURN_INSPECTION",
    title: "Return inspection",
    description:
      "Evaluasi retur yang menunggu inspeksi dan tindak lanjut.",
  },
  {
    code: "RECONCILIATION",
    title: "Reconciliation",
    description:
      "Evaluasi hasil rekonsiliasi dan issue integritas stok.",
  },
  {
    code: "STOCKTAKE",
    title: "Stocktake",
    description:
      "Evaluasi lifecycle dan hasil proses stok opname.",
  },
] as const satisfies readonly {
  code: NotificationEvaluationFamilyCode;
  title: string;
  description: string;
}[];

function normalizeStatus(value: string | undefined) {
  const normalized = value?.trim().toUpperCase() || "ALL";

  return statusOptions.some(([code]) => code === normalized)
    ? normalized
    : "ALL";
}

function formatDate(value: string | null) {
  if (!value) return "Belum tersedia";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(date);
}

function labelFromCode(value: string) {
  return value
    .toLowerCase()
    .split("_")
    .map(
      (part) =>
        part.charAt(0).toUpperCase() + part.slice(1),
    )
    .join(" ");
}

function formatJson(value: unknown) {
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function statusTone(status: string): PillTone {
  if (status === "FAILED_FINAL") return "danger";
  if (status === "FAILED_RETRYABLE") return "warning";
  if (status === "PROCESSING") return "info";
  if (status === "PENDING") return "neutral";
  return "success";
}

function Pill({
  label,
  tone,
}: {
  label: string;
  tone: PillTone;
}) {
  const tones: Record<PillTone, string> = {
    success:
      "border-emerald-400/25 bg-emerald-400/10 text-emerald-200",
    warning:
      "border-amber-400/25 bg-amber-400/10 text-amber-100",
    danger:
      "border-rose-400/25 bg-rose-400/10 text-rose-100",
    info:
      "border-sky-400/25 bg-sky-400/10 text-sky-100",
    neutral:
      "border-white/10 bg-white/[0.035] text-slate-300",
  };

  return (
    <span
      className={`inline-flex rounded-full border px-2.5 py-1 text-xs font-medium ${tones[tone]}`}
    >
      {label}
    </span>
  );
}

function MetricCard({
  label,
  value,
  description,
  tone = "neutral",
}: {
  label: string;
  value: number;
  description: string;
  tone?: PillTone;
}) {
  return (
    <article className="metric-card">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-slate-400">{label}</p>
        <Pill
          label={tone === "danger" ? "Perlu tindakan" : "Live"}
          tone={tone}
        />
      </div>
      <p className="mt-3 text-3xl font-semibold text-white">
        {value.toLocaleString("id-ID")}
      </p>
      <p className="mt-2 text-xs leading-5 text-slate-500">
        {description}
      </p>
    </article>
  );
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-5 py-10 text-slate-100 lg:px-8">
      <div className="mx-auto max-w-4xl rounded-3xl border border-rose-400/20 bg-rose-400/[0.06] p-7">
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-rose-300">
          Notification operations
        </p>
        <h1 className="mt-3 text-2xl font-semibold">
          Halaman operasi belum dapat dimuat.
        </h1>
        <p className="mt-3 break-words text-sm leading-6 text-rose-100/80">
          {message}
        </p>
        <Link
          className="mt-6 inline-flex rounded-xl border border-white/10 px-4 py-2 text-sm text-slate-200 hover:bg-white/[0.05]"
          href="/notifications"
        >
          Kembali ke Notification Center
        </Link>
      </div>
    </main>
  );
}

function SummarySection({
  summary,
}: {
  summary: NotificationOperationsSummary;
}) {
  return (
    <section className="scroll-mt-24" id="overview">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-emerald-300">
            Notification operations
          </p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
            Kendali evaluator dan outbox, tanpa akses tabel mentah.
          </h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
            Jalankan evaluator manual dengan alasan tercatat, pantau
            kesehatan antrean, dan retry hanya event gagal yang memang
            dapat ditindaklanjuti.
          </p>
        </div>
        <div className="flex flex-col items-start gap-2 lg:items-end">
          <Link
            className="rounded-xl border border-white/10 px-4 py-2 text-sm text-slate-300 transition hover:bg-white/[0.05] hover:text-white"
            href="/notifications"
          >
            Buka Notification Center
          </Link>
          <p className="text-xs text-slate-500">
            Snapshot {formatDate(summary.generatedAt)} WIB
          </p>
        </div>
      </div>

      <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          description="Event menunggu worker mengambil antrean."
          label="Pending outbox"
          tone={
            summary.outbox.pendingCount > 0
              ? "warning"
              : "success"
          }
          value={summary.outbox.pendingCount}
        />
        <MetricCard
          description="Event gagal yang dapat atau harus di-retry."
          label="Failed outbox"
          tone={
            summary.outbox.failedRetryableCount +
              summary.outbox.failedFinalCount >
            0
              ? "danger"
              : "success"
          }
          value={
            summary.outbox.failedRetryableCount +
            summary.outbox.failedFinalCount
          }
        />
        <MetricCard
          description={`Lock processing lebih lama dari ${summary.staleLockTimeoutSeconds} detik.`}
          label="Stale processing"
          tone={
            summary.outbox.staleProcessingCount > 0
              ? "danger"
              : "success"
          }
          value={summary.outbox.staleProcessingCount}
        />
        <MetricCard
          description="Notifikasi aktif yang belum dibaca akun ini."
          label="Unread notifications"
          tone={
            summary.notifications.unreadCount > 0
              ? "warning"
              : "success"
          }
          value={summary.notifications.unreadCount}
        />
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-3">
        <article className="rounded-3xl border border-white/10 bg-white/[0.025] p-5">
          <p className="section-kicker">Rule runs</p>
          <dl className="mt-4 grid grid-cols-2 gap-4 text-sm">
            <div>
              <dt className="text-slate-500">Sedang berjalan</dt>
              <dd className="mt-1 text-xl font-semibold text-white">
                {summary.ruleRuns.startedCount}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">Sukses 24 jam</dt>
              <dd className="mt-1 text-xl font-semibold text-emerald-200">
                {summary.ruleRuns.succeededLast24Hours}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">Parsial gagal</dt>
              <dd className="mt-1 text-xl font-semibold text-amber-100">
                {summary.ruleRuns.partiallyFailedLast24Hours}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">Gagal 24 jam</dt>
              <dd className="mt-1 text-xl font-semibold text-rose-100">
                {summary.ruleRuns.failedLast24Hours}
              </dd>
            </div>
          </dl>
        </article>

        <article className="rounded-3xl border border-white/10 bg-white/[0.025] p-5">
          <p className="section-kicker">Lifecycle</p>
          <dl className="mt-4 grid grid-cols-2 gap-4 text-sm">
            <div>
              <dt className="text-slate-500">Open</dt>
              <dd className="mt-1 text-xl font-semibold text-white">
                {summary.notifications.openCount}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">Acknowledged</dt>
              <dd className="mt-1 text-xl font-semibold text-sky-100">
                {summary.notifications.acknowledgedCount}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">Critical aktif</dt>
              <dd className="mt-1 text-xl font-semibold text-rose-100">
                {summary.notifications.criticalActiveCount}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">High aktif</dt>
              <dd className="mt-1 text-xl font-semibold text-amber-100">
                {summary.notifications.highActiveCount}
              </dd>
            </div>
          </dl>
        </article>

        <article className="rounded-3xl border border-white/10 bg-white/[0.025] p-5">
          <p className="section-kicker">Admin commands</p>
          <dl className="mt-4 grid grid-cols-2 gap-4 text-sm">
            <div>
              <dt className="text-slate-500">Retry 24 jam</dt>
              <dd className="mt-1 text-xl font-semibold text-white">
                {summary.adminOperations.retryRequestsLast24Hours}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">Evaluasi 24 jam</dt>
              <dd className="mt-1 text-xl font-semibold text-white">
                {
                  summary.adminOperations
                    .evaluationRequestsLast24Hours
                }
              </dd>
            </div>
          </dl>
          <p className="mt-5 text-xs leading-5 text-slate-500">
            Permintaan terakhir:{" "}
            {formatDate(
              summary.adminOperations.latestRequestedAt,
            )}{" "}
            WIB
          </p>
        </article>
      </div>
    </section>
  );
}

function EvaluationSection({ returnTo }: { returnTo: string }) {
  return (
    <section className="mt-12 scroll-mt-24" id="evaluations">
      <div className="mb-5">
        <p className="section-kicker">Manual evaluators</p>
        <h2 className="section-title">
          Jalankan ulang evaluasi dengan alasan audit.
        </h2>
        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-500">
          Perintah hanya membuat event outbox. Evaluator tetap diproses
          melalui dispatcher yang sama dengan event normal.
        </p>
      </div>

      <div className="grid gap-5 lg:grid-cols-2">
        {evaluationFamilies.map((family) => (
          <article
            className="rounded-3xl border border-white/10 bg-white/[0.025] p-5"
            key={family.code}
          >
            <div className="flex items-start justify-between gap-4">
              <div>
                <h3 className="text-lg font-semibold text-white">
                  {family.title}
                </h3>
                <p className="mt-2 text-sm leading-6 text-slate-500">
                  {family.description}
                </p>
              </div>
              <Pill
                label={labelFromCode(family.code)}
                tone="info"
              />
            </div>

            <form
              action={runNotificationEvaluationAction}
              className="mt-5 space-y-4"
            >
              <input
                name="evaluationFamilyCode"
                type="hidden"
                value={family.code}
              />
              <input
                name="idempotencyKey"
                type="hidden"
                value={randomUUID()}
              />
              <input
                name="returnTo"
                type="hidden"
                value={`${returnTo}#evaluations`}
              />

              <label className="field-label">
                Alasan evaluasi
                <textarea
                  className="min-h-28"
                  maxLength={2000}
                  name="reason"
                  placeholder={`Contoh: verifikasi manual ${family.title.toLowerCase()} setelah koreksi data sumber.`}
                  required
                />
              </label>

              <button className="primary-button w-full" type="submit">
                Jalankan evaluasi {family.title}
              </button>
            </form>
          </article>
        ))}
      </div>
    </section>
  );
}

function OutboxCard({
  event,
  returnTo,
}: {
  event: NotificationOutboxActionableItem;
  returnTo: string;
}) {
  return (
    <article className="rounded-3xl border border-white/10 bg-white/[0.025] p-5">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <Pill
              label={labelFromCode(event.status_code)}
              tone={statusTone(event.status_code)}
            />
            {event.is_stale_processing ? (
              <Pill label="Stale lock" tone="danger" />
            ) : null}
            {event.can_retry ? (
              <Pill label="Retry tersedia" tone="warning" />
            ) : null}
          </div>

          <h3 className="mt-4 break-words text-lg font-semibold text-white">
            {labelFromCode(event.event_type_code)}
          </h3>
          <p className="mt-2 break-all font-mono text-xs text-slate-500">
            {event.outbox_event_id}
          </p>
          <p className="mt-3 break-words text-sm text-slate-400">
            Source:{" "}
            <span className="font-mono text-xs text-slate-300">
              {event.source_event_key}
            </span>
          </p>
        </div>

        <dl className="grid shrink-0 grid-cols-2 gap-x-6 gap-y-3 text-xs">
          <div>
            <dt className="text-slate-500">Attempt total</dt>
            <dd className="mt-1 text-slate-200">
              {event.attempt_count}
            </dd>
          </div>
          <div>
            <dt className="text-slate-500">Attempt siklus</dt>
            <dd className="mt-1 text-slate-200">
              {event.retry_cycle_attempt_count}
            </dd>
          </div>
          <div>
            <dt className="text-slate-500">Available</dt>
            <dd className="mt-1 text-slate-200">
              {formatDate(event.available_at)} WIB
            </dd>
          </div>
          <div>
            <dt className="text-slate-500">Occurred</dt>
            <dd className="mt-1 text-slate-200">
              {formatDate(event.occurred_at)} WIB
            </dd>
          </div>
        </dl>
      </div>

      {event.last_error_code ? (
        <div className="mt-5 rounded-2xl border border-rose-400/15 bg-rose-400/[0.045] p-4">
          <p className="font-mono text-xs font-medium text-rose-200">
            {event.last_error_code}
          </p>
          <details className="mt-3">
            <summary className="cursor-pointer text-xs text-slate-400 hover:text-slate-200">
              Lihat detail error
            </summary>
            <pre className="mt-3 max-h-72 overflow-auto whitespace-pre-wrap break-words rounded-xl bg-slate-950/70 p-3 text-xs leading-5 text-slate-400">
              {formatJson(event.last_error_detail)}
            </pre>
          </details>
        </div>
      ) : null}

      {event.is_stale_processing ? (
        <p className="mt-5 rounded-2xl border border-amber-400/20 bg-amber-400/[0.055] px-4 py-3 text-sm leading-6 text-amber-100">
          Lock worker melewati batas lima menit. Event ini tidak dapat
          di-retry manual sampai mekanisme recovery mengubah statusnya.
        </p>
      ) : null}

      {event.can_retry ? (
        <form
          action={retryNotificationOutboxEventAction}
          className="mt-5 grid gap-4 lg:grid-cols-[1fr_auto] lg:items-end"
        >
          <input
            name="outboxEventId"
            type="hidden"
            value={event.outbox_event_id}
          />
          <input
            name="idempotencyKey"
            type="hidden"
            value={randomUUID()}
          />
          <input
            name="returnTo"
            type="hidden"
            value={`${returnTo}#outbox`}
          />

          <label className="field-label">
            Alasan retry
            <textarea
              className="min-h-24"
              maxLength={2000}
              name="reason"
              placeholder="Jelaskan diagnosis, koreksi yang sudah dilakukan, dan alasan event aman diproses ulang."
              required
            />
          </label>

          <button
            className="primary-button min-h-11 px-6"
            type="submit"
          >
            Retry event
          </button>
        </form>
      ) : null}
    </article>
  );
}

function OutboxSection({
  events,
  status,
  returnTo,
}: {
  events: NotificationOutboxActionableItem[];
  status: string;
  returnTo: string;
}) {
  return (
    <section className="mt-12 scroll-mt-24" id="outbox">
      <div className="mb-5 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="section-kicker">Actionable outbox</p>
          <h2 className="section-title">
            Antrean yang membutuhkan pengamatan atau tindakan.
          </h2>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-500">
            Payload sumber tidak ditampilkan. Halaman hanya membuka
            metadata operasional dan detail error yang diperlukan untuk
            diagnosis.
          </p>
        </div>

        <form
          action="/notifications/operations"
          className="flex min-w-64 gap-2"
          method="get"
        >
          <label className="field-label flex-1">
            Status
            <select defaultValue={status} name="status">
              {statusOptions.map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <button
            className="mt-6 rounded-xl border border-white/10 px-4 text-sm text-slate-200 transition hover:bg-white/[0.05]"
            type="submit"
          >
            Filter
          </button>
        </form>
      </div>

      {events.length ? (
        <div className="space-y-4">
          {events.map((event) => (
            <OutboxCard
              event={event}
              key={event.outbox_event_id}
              returnTo={returnTo}
            />
          ))}
        </div>
      ) : (
        <div className="rounded-3xl border border-dashed border-white/10 p-8 text-center">
          <p className="text-base font-medium text-slate-300">
            Tidak ada actionable outbox untuk filter ini.
          </p>
          <p className="mt-2 text-sm text-slate-500">
            Untuk sekali ini, tidak adanya pekerjaan memang kabar baik.
          </p>
        </div>
      )}
    </section>
  );
}

export default async function NotificationOperationsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const status = normalizeStatus(params.status);
  const feedbackError =
    params.error?.trim().slice(0, 500) || null;
  const feedbackSuccess = feedbackError
    ? null
    : params.success?.trim().slice(0, 500) || null;

  let summary: NotificationOperationsSummary;
  let events: NotificationOutboxActionableItem[];

  try {
    [summary, events] = await Promise.all([
      getNotificationOperationsSummary(),
      getNotificationOutboxActionableList(
        status === "ALL" ? null : status,
        50,
      ),
    ]);
  } catch (error) {
    return (
      <ConfigurationError
        message={
          error instanceof Error
            ? error.message
            : "Konfigurasi Notification Operations tidak valid."
        }
      />
    );
  }

  const returnParams = new URLSearchParams();

  if (status !== "ALL") {
    returnParams.set("status", status);
  }

  const returnQuery = returnParams.toString();
  const returnTo = `/notifications/operations${
    returnQuery ? `?${returnQuery}` : ""
  }`;

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <PageSectionNav
        items={[
          { href: "#overview", label: "Ringkasan" },
          { href: "#evaluations", label: "Evaluasi manual" },
          { href: "#outbox", label: "Outbox" },
        ]}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <SummarySection summary={summary} />

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

        <EvaluationSection returnTo={returnTo} />
        <OutboxSection
          events={events}
          returnTo={returnTo}
          status={status}
        />
      </div>
    </main>
  );
}
