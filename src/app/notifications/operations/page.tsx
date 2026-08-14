import { randomUUID } from "node:crypto";

import Link from "next/link";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import PageSectionNav from "@/app/app-shell/page-section-nav";
import NotificationStatePanel from "@/app/notifications/operations/notification-state-panel";
import {
  retryNotificationOutboxEventAction,
  runNotificationEvaluationAction,
} from "@/app/notifications/operations/actions";
import {
  Alert,
  Button,
  EmptyState,
  Field,
  Select,
  StatusBadge,
  Textarea,
} from "@/components/ui";
import { requireAdminSession } from "@/lib/auth";
import {
  getNotificationOperationsSummary,
  getNotificationOutboxActionableList,
  getSchedulerOperationsSummary,
  type NotificationEvaluationFamilyCode,
  type NotificationOperationsSummary,
  type NotificationOutboxActionableItem,
  type SchedulerJobHealthCode,
  type SchedulerOperationsSummary,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = {
  status?: string;
  success?: string;
  error?: string;
};

type BadgeTone =
  | "neutral"
  | "selected"
  | "warning"
  | "danger";

const statusOptions = [
  ["ALL", "Semua yang perlu dipantau"],
  ["FAILED_FINAL", "Gagal dan perlu diperiksa"],
  ["FAILED_RETRYABLE", "Gagal dan bisa dicoba lagi"],
  ["PROCESSING", "Sedang diproses"],
  ["PENDING", "Menunggu diproses"],
] as const;

const evaluationFamilies = [
  {
    code: "EXPIRY",
    title: "Kedaluwarsa",
    description:
      "Periksa ulang batch yang mendekati atau melewati masa kedaluwarsa.",
  },
  {
    code: "RETURN_INSPECTION",
    title: "Inspeksi Retur",
    description:
      "Periksa ulang retur yang masih menunggu inspeksi dan tindak lanjut.",
  },
  {
    code: "RECONCILIATION",
    title: "Rekonsiliasi",
    description:
      "Periksa ulang hasil rekonsiliasi dan temuan integritas stok.",
  },
  {
    code: "STOCKTAKE",
    title: "Stok Opname",
    description:
      "Periksa ulang status dan hasil proses stok opname.",
  },
] as const satisfies readonly {
  code: NotificationEvaluationFamilyCode;
  title: string;
  description: string;
}[];

function normalizeStatus(value: string | undefined) {
  const normalized =
    value?.trim().toUpperCase() || "ALL";

  return statusOptions.some(
    ([code]) => code === normalized,
  )
    ? normalized
    : "ALL";
}

function formatDate(value: string | null) {
  if (!value) {
    return "Waktu belum tersedia";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "Waktu belum tersedia";
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
        part.charAt(0).toUpperCase() +
        part.slice(1),
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

function statusLabel(status: string) {
  const labels: Record<string, string> = {
    FAILED_FINAL: "Gagal — perlu diperiksa",
    FAILED_RETRYABLE:
      "Gagal — bisa dicoba lagi",
    PROCESSING: "Sedang diproses",
    PENDING: "Menunggu diproses",
  };

  return (
    labels[status] ??
    labelFromCode(status)
  );
}

function statusTone(
  status: string,
): BadgeTone {
  if (status === "FAILED_FINAL") {
    return "danger";
  }

  if (status === "FAILED_RETRYABLE") {
    return "warning";
  }

  if (status === "PROCESSING") {
    return "selected";
  }

  return "neutral";
}

const schedulerJobLabels: Record<
  SchedulerOperationsSummary["jobs"][number]["jobCode"],
  string
> = {
  NOTIFICATION_OUTBOX: "Pemrosesan Notifikasi",
  CLAIM_DEADLINE: "Pengingat Klaim",
  EXPIRY_DAILY: "Pemeriksaan Kedaluwarsa",
  RECONCILIATION_DAILY: "Rekonsiliasi Harian",
};

function schedulerHealthLabel(value: SchedulerJobHealthCode) {
  const labels: Record<SchedulerJobHealthCode, string> = {
    HEALTHY: "Sehat",
    FAILED: "Gagal",
    STALE: "Terlambat",
    NEVER_RUN: "Belum Pernah Berjalan",
  };

  return labels[value];
}

function schedulerHealthTone(value: SchedulerJobHealthCode): BadgeTone {
  if (value === "FAILED") return "danger";
  if (value === "STALE") return "warning";
  if (value === "HEALTHY") return "selected";
  return "neutral";
}

function ScheduledOperationsSection({
  summary,
}: {
  summary: SchedulerOperationsSummary;
}) {
  return (
    <section
      className="mt-10 scroll-mt-24"
      id="scheduled-operations"
    >
      <div>
        <h2 className="text-lg font-semibold text-ui-text">
          Operasi Sistem Terjadwal
        </h2>

        <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
          Pantau pemeriksaan otomatis. Proses ini hanya
          membaca kondisi operasional dan membuat catatan
          pemeriksaan atau notifikasi; tidak mengubah stok.
        </p>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        {summary.jobs.map((job) => (
          <article
            className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5"
            key={job.jobCode}
          >
            <div className="flex items-start justify-between gap-4">
              <div>
                <h3 className="text-base font-semibold text-ui-text">
                  {schedulerJobLabels[job.jobCode]}
                </h3>

                <p className="mt-1 text-sm text-ui-text-muted">
                  Terakhir selesai: {formatDate(job.lastCompletedAt)} WIB
                </p>
              </div>

              <StatusBadge tone={schedulerHealthTone(job.healthCode)}>
                {schedulerHealthLabel(job.healthCode)}
              </StatusBadge>
            </div>

            {job.lastFailureSummary ? (
              <Alert
                className="mt-4"
                title="Perlu pemeriksaan"
                tone="danger"
              >
                {job.lastFailureSummary}
              </Alert>
            ) : null}
          </article>
        ))}
      </div>
    </section>
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
  tone?: BadgeTone;
}) {
  const stateLabel =
    tone === "danger"
      ? "Perlu tindakan"
      : tone === "warning"
        ? "Perlu dilihat"
        : tone === "selected"
          ? "Aman"
          : "Informasi";

  return (
    <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
      <div className="flex items-start justify-between gap-3">
        <p className="text-sm font-medium text-ui-text-muted">
          {label}
        </p>

        <StatusBadge tone={tone}>
          {stateLabel}
        </StatusBadge>
      </div>

      <p className="mt-3 text-3xl font-semibold tracking-tight text-ui-text">
        {value.toLocaleString("id-ID")}
      </p>

      <p className="mt-2 text-xs leading-5 text-ui-text-muted">
        {description}
      </p>
    </article>
  );
}

function ConfigurationError({
  message,
}: {
  message: string;
}) {
  return (
    <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
      <Link
        className="mb-6 inline-flex min-h-10 items-center text-sm font-semibold text-ui-primary hover:underline"
        href="/settings"
      >
        ← Kembali ke Pengaturan
      </Link>

      <PageHeader
        description="Halaman diagnostik tidak menampilkan keadaan sistem sebagai aman ketika data operasional gagal dibaca."
        eyebrow="Pengaturan"
        title="Status & Diagnostik Sistem"
      />

      <Alert
        className="mt-6"
        title="Diagnostik belum dapat dimuat"
        tone="danger"
      >
        <p>
          Data operasional tidak berhasil dibaca.
          Muat ulang halaman setelah memastikan layanan
          lokal dan koneksi database tersedia.
        </p>

        <details className="mt-3">
          <summary className="cursor-pointer font-semibold">
            Lihat detail teknis
          </summary>

          <p className="mt-2 break-words text-xs">
            {message}
          </p>
        </details>
      </Alert>
    </div>
  );
}

function SummarySection({
  summary,
}: {
  summary: NotificationOperationsSummary;
}) {
  return (
    <section
      className="scroll-mt-24"
      id="overview"
    >
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="text-lg font-semibold text-ui-text">
            Ringkasan kondisi saat ini
          </h2>

          <p className="mt-1 text-sm leading-6 text-ui-text-muted">
            Fokuskan perhatian pada proses yang gagal,
            tertahan, atau masih menunggu tindakan.
          </p>
        </div>

        <p className="text-xs text-ui-text-muted">
          Snapshot {formatDate(summary.generatedAt)} WIB
        </p>
      </div>

      <div className="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          description="Pengiriman notifikasi yang masih menunggu worker."
          label="Menunggu dikirim"
          tone={
            summary.outbox.pendingCount > 0
              ? "warning"
              : "selected"
          }
          value={summary.outbox.pendingCount}
        />

        <MetricCard
          description="Pengiriman yang gagal dan membutuhkan pemeriksaan atau percobaan ulang."
          label="Gagal dikirim"
          tone={
            summary.outbox.failedRetryableCount +
              summary.outbox.failedFinalCount >
            0
              ? "danger"
              : "selected"
          }
          value={
            summary.outbox.failedRetryableCount +
            summary.outbox.failedFinalCount
          }
        />

        <MetricCard
          description={`Proses terkunci lebih lama dari ${summary.staleLockTimeoutSeconds} detik.`}
          label="Proses macet"
          tone={
            summary.outbox.staleProcessingCount > 0
              ? "danger"
              : "selected"
          }
          value={
            summary.outbox.staleProcessingCount
          }
        />

        <MetricCard
          description="Notifikasi aktif yang belum dibaca oleh akun Admin ini."
          label="Belum dibaca"
          tone={
            summary.notifications.unreadCount > 0
              ? "warning"
              : "selected"
          }
          value={
            summary.notifications.unreadCount
          }
        />
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-3">
        <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
          <h3 className="text-sm font-semibold text-ui-text">
            Pemeriksaan otomatis
          </h3>

          <dl className="mt-4 grid grid-cols-2 gap-4 text-sm">
            <div>
              <dt className="text-ui-text-muted">
                Sedang berjalan
              </dt>
              <dd className="mt-1 text-xl font-semibold text-ui-text">
                {summary.ruleRuns.startedCount}
              </dd>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Sukses 24 jam
              </dt>
              <dd className="mt-1 text-xl font-semibold text-ui-text">
                {
                  summary.ruleRuns
                    .succeededLast24Hours
                }
              </dd>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Sebagian gagal
              </dt>
              <dd className="mt-1 text-xl font-semibold text-ui-warning">
                {
                  summary.ruleRuns
                    .partiallyFailedLast24Hours
                }
              </dd>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Gagal 24 jam
              </dt>
              <dd className="mt-1 text-xl font-semibold text-ui-danger">
                {
                  summary.ruleRuns
                    .failedLast24Hours
                }
              </dd>
            </div>
          </dl>
        </article>

        <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
          <h3 className="text-sm font-semibold text-ui-text">
            Penanganan notifikasi
          </h3>

          <dl className="mt-4 grid grid-cols-2 gap-4 text-sm">
            <div>
              <dt className="text-ui-text-muted">
                Belum ditangani
              </dt>
              <dd className="mt-1 text-xl font-semibold text-ui-text">
                {summary.notifications.openCount}
              </dd>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Sedang ditangani
              </dt>
              <dd className="mt-1 text-xl font-semibold text-ui-primary">
                {
                  summary.notifications
                    .acknowledgedCount
                }
              </dd>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Kritis aktif
              </dt>
              <dd className="mt-1 text-xl font-semibold text-ui-danger">
                {
                  summary.notifications
                    .criticalActiveCount
                }
              </dd>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Mendesak aktif
              </dt>
              <dd className="mt-1 text-xl font-semibold text-ui-warning">
                {
                  summary.notifications
                    .highActiveCount
                }
              </dd>
            </div>
          </dl>
        </article>

        <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
          <h3 className="text-sm font-semibold text-ui-text">
            Tindakan Admin
          </h3>

          <dl className="mt-4 grid grid-cols-2 gap-4 text-sm">
            <div>
              <dt className="text-ui-text-muted">
                Percobaan ulang 24 jam
              </dt>
              <dd className="mt-1 text-xl font-semibold text-ui-text">
                {
                  summary.adminOperations
                    .retryRequestsLast24Hours
                }
              </dd>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Pemeriksaan 24 jam
              </dt>
              <dd className="mt-1 text-xl font-semibold text-ui-text">
                {
                  summary.adminOperations
                    .evaluationRequestsLast24Hours
                }
              </dd>
            </div>
          </dl>

          <p className="mt-5 text-xs leading-5 text-ui-text-muted">
            Permintaan terakhir{" "}
            {formatDate(
              summary.adminOperations
                .latestRequestedAt,
            )}{" "}
            WIB
          </p>
        </article>
      </div>
    </section>
  );
}

function EvaluationSection({
  returnTo,
}: {
  returnTo: string;
}) {
  return (
    <section
      className="mt-10 scroll-mt-24"
      id="evaluations"
    >
      <div>
        <h2 className="text-lg font-semibold text-ui-text">
          Pemeriksaan sistem
        </h2>

        <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
          Jalankan pemeriksaan ulang hanya ketika
          diperlukan. Alasan wajib diisi dan permintaan
          dicatat untuk audit. Proses tetap menggunakan
          jalur evaluator dan outbox yang sama dengan
          kejadian normal.
        </p>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        {evaluationFamilies.map((family) => {
          const fieldId =
            `evaluation-reason-${family.code.toLowerCase()}`;

          return (
            <article
              className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5"
              key={family.code}
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <h3 className="text-base font-semibold text-ui-text">
                    {family.title}
                  </h3>

                  <p className="mt-1 text-sm leading-6 text-ui-text-muted">
                    {family.description}
                  </p>
                </div>

                <StatusBadge tone="neutral">
                  Manual
                </StatusBadge>
              </div>

              <form
                action={
                  runNotificationEvaluationAction
                }
                className="mt-5 grid gap-4"
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

                <Field
                  description="Wajib diisi dan disimpan sebagai alasan tindakan Admin."
                  id={fieldId}
                  label="Alasan pemeriksaan"
                >
                  {(controlProps) => (
                    <Textarea
                      {...controlProps}
                      maxLength={2000}
                      name="reason"
                      placeholder={`Contoh: periksa ulang ${family.title.toLowerCase()} setelah koreksi data sumber.`}
                      required
                    />
                  )}
                </Field>

                <Button
                  className="w-full"
                  type="submit"
                >
                  Jalankan pemeriksaan {family.title}
                </Button>
              </form>
            </article>
          );
        })}
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
    <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge
              tone={statusTone(
                event.status_code,
              )}
            >
              {statusLabel(event.status_code)}
            </StatusBadge>

            {event.is_stale_processing ? (
              <StatusBadge tone="danger">
                Proses macet
              </StatusBadge>
            ) : null}

            {event.can_retry ? (
              <StatusBadge tone="warning">
                Bisa dicoba lagi
              </StatusBadge>
            ) : null}
          </div>

          <h3 className="mt-3 text-base font-semibold text-ui-text">
            Pengiriman notifikasi
          </h3>

          <p className="mt-1 text-sm text-ui-text-muted">
            {labelFromCode(
              event.event_type_code,
            )}
          </p>

          <p className="mt-2 break-all text-xs text-ui-text-muted">
            ID pengiriman:{" "}
            {event.outbox_event_id}
          </p>
        </div>

        <dl className="grid shrink-0 grid-cols-2 gap-x-6 gap-y-3 text-xs">
          <div>
            <dt className="text-ui-text-muted">
              Total percobaan
            </dt>
            <dd className="mt-1 font-semibold text-ui-text">
              {event.attempt_count}
            </dd>
          </div>

          <div>
            <dt className="text-ui-text-muted">
              Percobaan siklus ini
            </dt>
            <dd className="mt-1 font-semibold text-ui-text">
              {
                event.retry_cycle_attempt_count
              }
            </dd>
          </div>

          <div>
            <dt className="text-ui-text-muted">
              Siap diproses
            </dt>
            <dd className="mt-1 text-ui-text">
              {formatDate(event.available_at)} WIB
            </dd>
          </div>

          <div>
            <dt className="text-ui-text-muted">
              Terjadi
            </dt>
            <dd className="mt-1 text-ui-text">
              {formatDate(event.occurred_at)} WIB
            </dd>
          </div>
        </dl>
      </div>

      <details className="mt-4 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle px-4 py-3">
        <summary className="cursor-pointer text-sm font-semibold text-ui-text">
          Detail teknis
        </summary>

        <dl className="mt-3 grid gap-3 text-xs sm:grid-cols-2">
          <div>
            <dt className="text-ui-text-muted">
              Source event
            </dt>
            <dd className="mt-1 break-all text-ui-text">
              {event.source_event_key}
            </dd>
          </div>

          <div>
            <dt className="text-ui-text-muted">
              Correlation ID
            </dt>
            <dd className="mt-1 break-all text-ui-text">
              {event.correlation_id}
            </dd>
          </div>

          <div>
            <dt className="text-ui-text-muted">
              Entity
            </dt>
            <dd className="mt-1 break-all text-ui-text">
              {event.entity_type_code}:{" "}
              {event.entity_id}
            </dd>
          </div>

          <div>
            <dt className="text-ui-text-muted">
              Retry budget mulai
            </dt>
            <dd className="mt-1 text-ui-text">
              {
                event.retry_budget_started_at_attempt
              }
            </dd>
          </div>
        </dl>
      </details>

      {event.last_error_code ? (
        <Alert
          className="mt-4"
          title="Pengiriman terakhir gagal"
          tone="danger"
        >
          <p className="break-words text-xs">
            Kode: {event.last_error_code}
          </p>

          <details className="mt-3">
            <summary className="cursor-pointer font-semibold">
              Lihat detail error
            </summary>

            <pre className="mt-3 max-h-72 overflow-auto whitespace-pre-wrap break-words rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-3 text-xs leading-5 text-ui-text-muted">
              {formatJson(
                event.last_error_detail,
              )}
            </pre>
          </details>
        </Alert>
      ) : null}

      {event.is_stale_processing ? (
        <Alert
          className="mt-4"
          title="Proses terlihat macet"
          tone="warning"
        >
          Lock worker sudah melewati batas aman.
          Pengiriman ini belum boleh dicoba ulang secara
          manual sampai mekanisme recovery mengubah
          statusnya.
        </Alert>
      ) : null}

      {event.can_retry ? (
        <form
          action={
            retryNotificationOutboxEventAction
          }
          className="mt-5 grid gap-4 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end"
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

          <Field
            description="Jelaskan diagnosis dan alasan pengiriman aman untuk dicoba lagi."
            id={`retry-reason-${event.outbox_event_id}`}
            label="Alasan percobaan ulang"
          >
            {(controlProps) => (
              <Textarea
                {...controlProps}
                className="min-h-24"
                maxLength={2000}
                name="reason"
                placeholder="Contoh: penyebab kegagalan sudah diperbaiki dan event aman diproses ulang."
                required
              />
            )}
          </Field>

          <Button type="submit">
            Coba kirim lagi
          </Button>
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
    <section
      className="mt-10 scroll-mt-24"
      id="outbox"
    >
      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <h2 className="text-lg font-semibold text-ui-text">
            Pengiriman notifikasi
          </h2>

          <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
            Daftar ini hanya menampilkan pengiriman
            yang masih perlu diamati atau ditindaklanjuti.
            Payload sumber tetap tersembunyi; detail
            diagnostik dibuka seperlunya.
          </p>
        </div>

        <form
          action="/notifications/operations"
          className="grid min-w-64 gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end"
          method="get"
        >
          <Field
            id="outbox-status-filter"
            label="Status pengiriman"
          >
            {(controlProps) => (
              <Select
                {...controlProps}
                defaultValue={status}
                name="status"
              >
                {statusOptions.map(
                  ([value, label]) => (
                    <option
                      key={value}
                      value={value}
                    >
                      {label}
                    </option>
                  ),
                )}
              </Select>
            )}
          </Field>

          <Button
            type="submit"
            variant="secondary"
          >
            Terapkan filter
          </Button>
        </form>
      </div>

      {events.length > 0 ? (
        <div className="mt-4 grid gap-4">
          {events.map((event) => (
            <OutboxCard
              event={event}
              key={event.outbox_event_id}
              returnTo={returnTo}
            />
          ))}
        </div>
      ) : (
        <EmptyState
          className="mt-4"
          description="Tidak ada pengiriman yang membutuhkan pengamatan atau tindakan untuk filter ini."
          title="Tidak ada pekerjaan diagnostik"
        />
      )}
    </section>
  );
}

export default async function NotificationOperationsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [params, session] =
    await Promise.all([
      searchParams,
      requireAdminSession(),
    ]);

  const status =
    normalizeStatus(params.status);

  const feedbackError =
    params.error?.trim().slice(0, 500) ||
    null;

  const feedbackSuccess = feedbackError
    ? null
    : params.success
        ?.trim()
        .slice(0, 500) || null;

  let summary: NotificationOperationsSummary;
  let events: NotificationOutboxActionableItem[];
  let scheduler: SchedulerOperationsSummary;

  try {
    [summary, events, scheduler] = await Promise.all([
      getNotificationOperationsSummary(),
      getNotificationOutboxActionableList(
        status === "ALL"
          ? null
          : status,
        50,
      ),
      getSchedulerOperationsSummary(),
    ]);
  } catch (error) {
    return (
      <AppShell profile={session.profile}>
        <ConfigurationError
          message={
            error instanceof Error
              ? error.message
              : "Konfigurasi diagnostik notifikasi tidak valid."
          }
        />
      </AppShell>
    );
  }

  const returnParams =
    new URLSearchParams();

  if (status !== "ALL") {
    returnParams.set(
      "status",
      status,
    );
  }

  const returnQuery =
    returnParams.toString();

  const returnTo =
    `/notifications/operations${
      returnQuery
        ? `?${returnQuery}`
        : ""
    }`;

  return (
    <AppShell profile={session.profile}>
      <PageSectionNav
        items={[
          {
            href: "#overview",
            label: "Ringkasan",
          },
          {
            href: "#scheduled-operations",
            label: "Operasi Terjadwal",
          },
          {
            href: "#notification-state",
            label: "Status notifikasi",
          },
          {
            href: "#evaluations",
            label: "Pemeriksaan sistem",
          },
          {
            href: "#outbox",
            label: "Pengiriman notifikasi",
          },
        ]}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <Link
          className="mb-6 inline-flex min-h-10 items-center text-sm font-semibold text-ui-primary hover:underline"
          href="/settings"
        >
          ← Kembali ke Pengaturan
        </Link>

        <PageHeader
          action={
            <Link
              className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text transition-colors hover:border-ui-border-strong hover:bg-ui-surface-subtle"
              href="/"
            >
              Buka Beranda
            </Link>
          }
          description="Pantau status notifikasi, pemeriksaan sistem, dan pengiriman yang membutuhkan tindakan Admin. Detail teknis tetap tersedia untuk audit tanpa memenuhi tampilan utama."
          eyebrow="Pengaturan"
          title="Status & Diagnostik Sistem"
        />

        <div className="mt-6">
          <SummarySection summary={summary} />
        </div>

        {feedbackSuccess ? (
          <Alert
            className="mt-6"
            tone="success"
          >
            {feedbackSuccess}
          </Alert>
        ) : null}

        {feedbackError ? (
          <Alert
            className="mt-6"
            tone="danger"
          >
            {feedbackError}
          </Alert>
        ) : null}

        <ScheduledOperationsSection summary={scheduler} />

        <NotificationStatePanel />

        <EvaluationSection
          returnTo={returnTo}
        />

        <OutboxSection
          events={events}
          returnTo={returnTo}
          status={status}
        />
      </div>
    </AppShell>
  );
}
