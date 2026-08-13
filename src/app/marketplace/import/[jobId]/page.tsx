import {
  randomUUID,
} from "node:crypto";

import Link from "next/link";
import {
  notFound,
} from "next/navigation";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  Alert,
  Button,
  Field,
  Select,
  StatusBadge,
  type StatusBadgeTone,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  safeMarketplaceCsvCommitErrorCode,
} from "@/lib/csv-import/safe-errors";
import {
  getMarketplaceCsvImportEventResults,
  getMarketplaceCsvImportJob,
  getMarketplaceCsvImportRows,
} from "@/lib/csv-import/server";

import {
  commitMarketplaceCsvImportAction,
} from "../actions";

export const dynamic = "force-dynamic";

const statusLabel: Record<string, string> = {
  UPLOADED: "File diterima",
  VALIDATING: "Sedang diperiksa",
  READY: "Siap diproses",
  VALIDATION_FAILED: "Perlu diperbaiki",
  COMMITTING: "Sedang diproses",
  COMPLETED: "Selesai",
  COMMIT_FAILED: "Pemrosesan gagal",
  CANCELLED: "Dibatalkan",
};

const rowStatusLabel: Record<string, string> = {
  VALID: "Valid",
  INVALID: "Perlu diperbaiki",
  DUPLICATE: "Duplikat",
  CONFLICT: "Konflik",
};

const commitErrorMessage: Record<string, string> = {
  CSV_IMPORT_COMMIT_FAILED:
    "Pemrosesan belum berhasil. Periksa kembali preview atau coba lagi.",
  CSV_IMPORT_COMMIT_CONFIRMATION_REQUIRED:
    "Konfirmasi diperlukan sebelum data diproses.",
  CSV_IMPORT_COMMIT_KEY_INVALID:
    "Permintaan tidak valid. Muat ulang halaman lalu coba lagi.",
  CSV_IMPORT_COMMIT_STATE_INVALID:
    "Import belum berada pada status yang dapat diproses.",
  CSV_IMPORT_COMMIT_IN_PROGRESS:
    "Import masih sedang diproses.",
  CSV_IMPORT_COMMIT_FAILED_REPLAY:
    "Pemrosesan sebelumnya gagal dan permintaan yang sama belum dapat diulang.",
  CSV_IMPORT_ALREADY_COMPLETED:
    "Import ini sudah selesai diproses.",
  CSV_IMPORT_BLOCKING_ROWS:
    "Masih ada baris yang perlu diperbaiki.",
  CSV_IMPORT_NO_ROWS:
    "Import tidak memiliki baris yang dapat diproses.",
  CSV_IMPORT_JOB_NOT_FOUND:
    "Import tidak ditemukan.",
  CSV_EXTERNAL_EVENT_CONFLICT:
    "Ada pesanan yang sudah tercatat dengan isi berbeda.",
  CSV_EXTERNAL_EVENT_ALREADY_EXISTS:
    "Ada pesanan yang sudah pernah diproses.",
  IDEMPOTENCY_KEY_REUSED:
    "Permintaan sebelumnya menggunakan kunci yang sama untuk isi yang berbeda.",
};

function statusTone(status: string): StatusBadgeTone {
  if (
    status === "VALIDATION_FAILED" ||
    status === "COMMIT_FAILED"
  ) {
    return "danger";
  }

  if (status === "READY") {
    return "warning";
  }

  if (status === "COMPLETED") {
    return "selected";
  }

  return "neutral";
}

function rowStatusTone(status: string): StatusBadgeTone {
  if (
    status === "INVALID" ||
    status === "CONFLICT"
  ) {
    return "danger";
  }

  if (status === "DUPLICATE") {
    return "warning";
  }

  if (status === "VALID") {
    return "selected";
  }

  return "neutral";
}

function formatDate(value: string | null) {
  if (!value) {
    return "Belum tersedia";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "Belum tersedia";
  }

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

function previewText(
  value: Record<string, unknown> | null,
) {
  if (!value) {
    return "Pemetaan belum tersedia";
  }

  const components = Array.isArray(value.components)
    ? value.components
    : [];

  const summary = components
    .map((item) => {
      const row = item as Record<string, unknown>;

      return `${row.productSku ?? row.productId ?? "produk"} × ${
        row.quantity ?? "?"
      }`;
    })
    .join(", ");

  return (
    summary ||
    String(
      value.listingType ??
        "Pemetaan produk tersedia",
    )
  );
}

function ErrorState({
  profile,
  title,
  description,
}: {
  profile: Parameters<typeof AppShell>[0]["profile"];
  title: string;
  description: string;
}) {
  return (
    <AppShell profile={profile}>
      <div className="mx-auto w-full max-w-[1000px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          description="Periksa import pesanan tanpa mengubah stok ketika data tidak dapat dimuat."
          eyebrow="Pesanan / Import CSV"
          title={title}
        />

        <Alert
          className="mt-6"
          title={title}
          tone="danger"
        >
          {description}
        </Alert>

        <Link
          className="mt-5 inline-flex min-h-10 items-center text-sm font-semibold text-ui-primary hover:underline"
          href="/marketplace/import"
        >
          ← Kembali ke Import CSV
        </Link>
      </div>
    </AppShell>
  );
}

export default async function CsvImportDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{
    jobId: string;
  }>;
  searchParams: Promise<{
    status?: string;
    commit?: string;
    commitError?: string;
    rowStatus?: string;
    cursor?: string;
  }>;
}) {
  const [{ jobId }, query, session] =
    await Promise.all([
      params,
      searchParams,
      requireAdminSession(),
    ]);

  let job: Awaited<
    ReturnType<typeof getMarketplaceCsvImportJob>
  >;

  try {
    job = await getMarketplaceCsvImportJob(jobId);
  } catch {
    return (
      <ErrorState
        description="Tidak ada pesanan atau stok yang diubah. Muat ulang halaman untuk mencoba lagi."
        profile={session.profile}
        title="Detail import belum dapat dimuat"
      />
    );
  }

  if (!job) {
    notFound();
  }

  let rows: Awaited<
    ReturnType<typeof getMarketplaceCsvImportRows>
  >;
  let events: Awaited<
    ReturnType<typeof getMarketplaceCsvImportEventResults>
  >;

  try {
    rows = await getMarketplaceCsvImportRows(
      jobId,
      50,
      query.cursor
        ? Number(query.cursor)
        : null,
      query.rowStatus ?? null,
    );

    events =
      job.status_code === "COMPLETED"
        ? await getMarketplaceCsvImportEventResults(
            jobId,
            100,
          )
        : {
            rows: [],
            nextCursor: null,
            hasMore: false,
          };
  } catch {
    return (
      <ErrorState
        description="Import tetap tersimpan dan tidak diproses ulang. Muat ulang halaman untuk mencoba lagi."
        profile={session.profile}
        title="Preview import belum dapat dimuat"
      />
    );
  }

  const commitKey =
    `csv-ui:${jobId}:${randomUUID()}`;

  const canCommit =
    job.status_code === "READY" ||
    job.status_code === "COMMIT_FAILED";

  const commitErrorCode = query.commitError
    ? safeMarketplaceCsvCommitErrorCode(
        query.commitError,
      )
    : null;

  const nextParams = new URLSearchParams({
    ...(query.rowStatus
      ? {
          rowStatus: query.rowStatus,
        }
      : {}),
    ...(rows.nextCursor
      ? {
          cursor: String(rows.nextCursor),
        }
      : {}),
  });

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1300px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <Link
          className="mb-5 inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
          href="/marketplace/import"
        >
          ← Kembali ke Import CSV
        </Link>

        <PageHeader
          action={
            <StatusBadge
              tone={statusTone(job.status_code)}
            >
              {statusLabel[job.status_code] ??
                job.status_code}
            </StatusBadge>
          }
          description="Periksa setiap baris dan hasil pemetaan produknya sebelum memproses pesanan."
          eyebrow="Pesanan / Import CSV"
          title={job.original_file_name}
        />

        <p className="mt-3 text-xs text-ui-text-muted">
          Template {job.template_version}
        </p>

        {query.commit ? (
          <Alert
            className="mt-6"
            title="Status pemrosesan"
            tone="success"
          >
            {query.commit}
          </Alert>
        ) : null}

        {commitErrorCode ? (
          <Alert
            className="mt-6"
            title="Pemrosesan belum selesai"
            tone="danger"
          >
            {commitErrorMessage[commitErrorCode] ??
              commitErrorMessage.CSV_IMPORT_COMMIT_FAILED}
          </Alert>
        ) : null}

        <dl className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {[
            {
              label: "Jumlah baris",
              value: job.row_count,
              detail: `${job.valid_row_count} valid · ${job.invalid_row_count} bermasalah`,
            },
            {
              label: "Duplikat / konflik",
              value: `${job.duplicate_row_count} / ${job.conflict_row_count}`,
              detail:
                "Baris bermasalah tidak diproses sebagian.",
            },
            {
              label: "Item setelah pemetaan",
              value: job.expanded_line_count,
              detail:
                "Jumlah produk satuan hasil pemetaan.",
            },
            {
              label: "Ukuran file",
              value: `${Math.round(
                job.file_size_bytes / 1024,
              )} KB`,
              detail: job.detected_mime,
            },
          ].map((item) => (
            <div
              className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4"
              key={item.label}
            >
              <dt className="text-xs font-medium text-ui-text-muted">
                {item.label}
              </dt>
              <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                {item.value}
              </dd>
              <p className="mt-1 text-xs leading-5 text-ui-text-muted">
                {item.detail}
              </p>
            </div>
          ))}
        </dl>

        <section
          aria-labelledby="preview-title"
          className="mt-8 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface"
        >
          <div className="flex flex-col gap-4 border-b border-ui-border p-5 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
                Preview
              </p>
              <h2
                className="mt-1 text-lg font-semibold text-ui-text"
                id="preview-title"
              >
                Baris dan masalah per data
              </h2>
              <p className="mt-1 text-sm text-ui-text-muted">
                Pemetaan produk ditampilkan sebelum pesanan diproses.
              </p>
            </div>

            <a
              className="inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
              href={`/marketplace/import/${job.id}/errors`}
            >
              Unduh laporan masalah
            </a>
          </div>

          <form
            className="grid gap-3 border-b border-ui-border p-5 sm:grid-cols-[minmax(0,260px)_auto] sm:items-end"
            method="get"
          >
            <Field
              id="row-status"
              label="Status baris"
            >
              {(controlProps) => (
                <Select
                  {...controlProps}
                  defaultValue={query.rowStatus ?? ""}
                  name="rowStatus"
                >
                  <option value="">
                    Semua
                  </option>
                  <option value="VALID">
                    Valid
                  </option>
                  <option value="INVALID">
                    Perlu diperbaiki
                  </option>
                  <option value="DUPLICATE">
                    Duplikat
                  </option>
                  <option value="CONFLICT">
                    Konflik
                  </option>
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

          <div className="overflow-x-auto">
            <table className="w-full min-w-[1050px] text-left text-sm">
              <thead className="border-b border-ui-border bg-ui-surface-subtle text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
                <tr>
                  <th className="px-4 py-3">
                    Baris
                  </th>
                  <th className="px-4 py-3">
                    Pesanan
                  </th>
                  <th className="px-4 py-3">
                    Pemetaan produk
                  </th>
                  <th className="px-4 py-3">
                    Status
                  </th>
                  <th className="px-4 py-3">
                    Masalah / perbaikan
                  </th>
                </tr>
              </thead>

              <tbody className="divide-y divide-ui-border">
                {rows.rows.map((row) => (
                  <tr
                    className="align-top"
                    key={row.id}
                  >
                    <td className="ui-number px-4 py-4 text-xs text-ui-text">
                      {row.row_number}
                    </td>

                    <td className="px-4 py-4">
                      <p className="font-medium text-ui-text">
                        {row.external_event_ref ?? "-"}
                      </p>
                      <p className="mt-1 text-xs text-ui-text-muted">
                        {String(
                          row.normalized_row
                            .external_order_ref ?? "-",
                        )}
                      </p>
                    </td>

                    <td className="max-w-md px-4 py-4 text-xs leading-5 text-ui-text-muted">
                      {previewText(
                        row.expansion_preview,
                      )}
                    </td>

                    <td className="px-4 py-4">
                      <StatusBadge
                        tone={rowStatusTone(
                          row.validation_status_code,
                        )}
                      >
                        {rowStatusLabel[
                          row.validation_status_code
                        ] ??
                          row.validation_status_code}
                      </StatusBadge>
                    </td>

                    <td className="max-w-lg px-4 py-4 text-xs leading-5 text-ui-text">
                      {row.validation_errors?.length ? (
                        <ul className="space-y-2">
                          {row.validation_errors.map(
                            (item, index) => (
                              <li
                                key={`${item.code}-${index}`}
                              >
                                <span className="font-semibold text-ui-danger">
                                  {item.message}
                                </span>
                                <span className="mt-0.5 block text-ui-text-muted">
                                  {item.remediation}
                                </span>
                              </li>
                            ),
                          )}
                        </ul>
                      ) : (
                        <span className="text-ui-text-muted">
                          Tidak ada masalah
                        </span>
                      )}
                    </td>
                  </tr>
                ))}

                {rows.rows.length === 0 ? (
                  <tr>
                    <td
                      className="px-4 py-8 text-center text-ui-text-muted"
                      colSpan={5}
                    >
                      Tidak ada baris pada filter ini.
                    </td>
                  </tr>
                ) : null}
              </tbody>
            </table>
          </div>

          <div className="border-t border-ui-border p-4">
            {rows.nextCursor ? (
              <Link
                className="inline-flex min-h-9 items-center font-semibold text-ui-primary hover:underline"
                href={`/marketplace/import/${job.id}?${nextParams.toString()}`}
              >
                Lihat baris berikutnya →
              </Link>
            ) : (
              <span className="text-xs text-ui-text-muted">
                Semua baris pada halaman ini sudah ditampilkan.
              </span>
            )}
          </div>
        </section>

        {canCommit ? (
          <section className="mt-8 rounded-[var(--ui-radius-lg)] border border-ui-warning bg-ui-warning-subtle p-5 sm:p-6">
            <p className="text-xs font-semibold uppercase tracking-wide text-ui-warning">
              Langkah 2
            </p>
            <h2 className="mt-1 text-lg font-semibold text-ui-text">
              Periksa sebelum memproses
            </h2>
            <p className="mt-2 max-w-3xl text-sm leading-6 text-ui-text">
              Semua data diproses sebagai satu pekerjaan. Jika satu bagian gagal, tidak ada bagian yang diterapkan. Tahap ini membuat reservasi pesanan marketplace, tetapi tidak mengubah stok fisik.
            </p>

            <form
              action={commitMarketplaceCsvImportAction}
              className="mt-5"
            >
              <input
                name="jobId"
                type="hidden"
                value={job.id}
              />
              <input
                name="commitKey"
                type="hidden"
                value={commitKey}
              />

              <label className="flex max-w-3xl items-start gap-3 text-sm leading-6 text-ui-text">
                <input
                  className="mt-1 size-4 shrink-0 accent-[var(--ui-primary)]"
                  name="confirmation"
                  required
                  type="checkbox"
                />
                <span>
                  Saya sudah memeriksa preview dan siap memproses import ini.
                </span>
              </label>

              <Button
                className="mt-5"
                type="submit"
              >
                Proses semua pesanan
              </Button>
            </form>
          </section>
        ) : null}

        {job.status_code === "COMPLETED" ? (
          <section
            aria-labelledby="result-title"
            className="mt-8 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 sm:p-6"
          >
            <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
              Hasil
            </p>
            <h2
              className="mt-1 text-lg font-semibold text-ui-text"
              id="result-title"
            >
              Hasil pemrosesan
            </h2>
            <p className="mt-1 text-sm text-ui-text-muted">
              Pesanan yang berhasil diproses tercatat melalui kontrak marketplace yang sama dengan sumber lainnya.
            </p>

            {events.rows.length > 0 ? (
              <div className="mt-4 divide-y divide-ui-border rounded-[var(--ui-radius-lg)] border border-ui-border">
                {events.rows.map((event) => (
                  <article
                    className="px-4 py-4"
                    key={event.id}
                  >
                    <div className="flex flex-wrap items-center justify-between gap-3">
                      <p className="font-semibold text-ui-text">
                        {event.external_event_ref}
                      </p>
                      <StatusBadge tone="selected">
                        {event.status_code}
                      </StatusBadge>
                    </div>

                    <details className="mt-3">
                      <summary className="cursor-pointer text-xs font-semibold text-ui-text-muted hover:text-ui-text">
                        Detail teknis
                      </summary>
                      <dl className="mt-3 grid gap-2 text-xs text-ui-text-muted">
                        <div>
                          <dt className="font-semibold text-ui-text">
                            Event
                          </dt>
                          <dd className="break-all">
                            {event.canonical_event_id}
                          </dd>
                        </div>
                        <div>
                          <dt className="font-semibold text-ui-text">
                            Pesanan
                          </dt>
                          <dd className="break-all">
                            {event.marketplace_order_id}
                          </dd>
                        </div>
                        <div>
                          <dt className="font-semibold text-ui-text">
                            Normalisasi
                          </dt>
                          <dd className="break-all">
                            {event.normalization_event_id}
                          </dd>
                        </div>
                      </dl>
                    </details>
                  </article>
                ))}
              </div>
            ) : (
              <p className="mt-4 text-sm text-ui-text-muted">
                Tidak ada referensi hasil yang perlu ditampilkan.
              </p>
            )}
          </section>
        ) : null}

        <dl className="mt-6 grid gap-2 border-t border-ui-border pt-4 text-xs text-ui-text-muted sm:grid-cols-3">
          <div>
            <dt className="font-semibold text-ui-text">
              File diterima
            </dt>
            <dd className="mt-1">
              {formatDate(job.uploaded_at)} WIB
            </dd>
          </div>
          <div>
            <dt className="font-semibold text-ui-text">
              Validasi selesai
            </dt>
            <dd className="mt-1">
              {formatDate(job.validated_at)} WIB
            </dd>
          </div>
          <div>
            <dt className="font-semibold text-ui-text">
              Pemrosesan selesai
            </dt>
            <dd className="mt-1">
              {formatDate(job.committed_at)} WIB
            </dd>
          </div>
        </dl>
      </div>
    </AppShell>
  );
}