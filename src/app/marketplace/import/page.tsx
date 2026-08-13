import Link from "next/link";

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
  Input,
  StatusBadge,
  type StatusBadgeTone,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  getMarketplaceCsvImportJobs,
} from "@/lib/csv-import/server";

import {
  stageMarketplaceCsvAction,
} from "./actions";

export const dynamic = "force-dynamic";

const uploadErrorMessage: Record<string, string> = {
  CSV_IMPORT_UPLOAD_FAILED:
    "File belum dapat diproses. Periksa format file atau coba kembali.",
  DUPLICATE_FILE:
    "File ini sudah pernah diproses pada organisasi ini.",
  INVALID_EXTENSION:
    "File harus berekstensi .csv.",
  FILE_TOO_LARGE:
    "Ukuran file melebihi batas yang diizinkan.",
  IMPORT_FILE_TOO_LARGE:
    "Ukuran file melebihi batas yang diizinkan.",
  INVALID_MIME:
    "Tipe file tidak didukung.",
  IMPORT_INVALID_MIME:
    "Tipe file tidak didukung.",
  INVALID_UTF8:
    "Format teks file tidak valid. Simpan CSV sebagai UTF-8.",
  BINARY_CONTENT:
    "File berisi data yang tidak dapat dibaca sebagai CSV.",
  MALFORMED_CSV:
    "Struktur CSV tidak dapat dibaca.",
  UNKNOWN_HEADER:
    "Kolom CSV tidak sesuai template.",
  DUPLICATE_HEADER:
    "Nama kolom CSV tidak boleh ganda.",
  MISSING_HEADER:
    "Kolom wajib CSV belum lengkap.",
  UNEQUAL_COLUMNS:
    "Jumlah kolom pada salah satu baris tidak sesuai template.",
  UNSUPPORTED_SCHEMA_VERSION:
    "Versi template CSV tidak didukung.",
  UNSUPPORTED_EVENT_TYPE:
    "Jenis data pada CSV tidak didukung.",
  INVALID_SOURCE_STATUS:
    "Status pesanan pada CSV tidak valid.",
  INVALID_TIMESTAMP:
    "Waktu pada CSV tidak valid.",
  RECEIVED_BEFORE_OCCURRED:
    "Urutan waktu pada salah satu data tidak valid.",
  INVALID_QUANTITY:
    "Jumlah barang harus berupa bilangan bulat positif.",
  FIELD_TOO_LONG:
    "Ada data yang melebihi batas panjang.",
  ROW_LIMIT_EXCEEDED:
    "Jumlah baris melebihi batas yang diizinkan.",
  EVENT_LINE_LIMIT_EXCEEDED:
    "Jumlah item dalam satu pesanan melebihi batas.",
  EXPANDED_LINE_LIMIT_EXCEEDED:
    "Hasil pemetaan produk melebihi batas yang diizinkan.",
  DUPLICATE_SOURCE_LINE:
    "Ada baris item yang tercatat lebih dari sekali.",
  EVENT_IDENTITY_CONFLICT:
    "Ada data pesanan dengan identitas yang saling bertentangan.",
  CSV_IMPORT_VALIDATION_FAILED:
    "Validasi CSV gagal. Buka detail import untuk melihat data yang perlu diperbaiki.",
};

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

function formatDate(value: string) {
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
    hour12: false,
  }).format(date);
}

export default async function CsvImportPage({
  searchParams,
}: {
  searchParams: Promise<{
    errorCode?: string;
  }>;
}) {
  const [query, session] = await Promise.all([
    searchParams,
    requireAdminSession(),
  ]);

  let data: Awaited<
    ReturnType<typeof getMarketplaceCsvImportJobs>
  >;

  try {
    data = await getMarketplaceCsvImportJobs();
  } catch {
    return (
      <AppShell profile={session.profile}>
        <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader
            eyebrow="Pesanan"
            title="Import Pesanan"
            description="Unggah file pesanan marketplace dan periksa hasil validasinya sebelum diproses."
          />

          <Alert
            className="mt-6"
            title="Riwayat import belum dapat dimuat"
            tone="danger"
          >
            Tidak ada data atau stok yang diubah. Muat ulang halaman untuk mencoba lagi.
          </Alert>

          <Link
            className="mt-5 inline-flex min-h-10 items-center text-sm font-semibold text-ui-primary hover:underline"
            href="/settings"
          >
            ← Kembali ke Pengaturan
          </Link>
        </div>
      </AppShell>
    );
  }

  const errorMessage = query.errorCode
    ? uploadErrorMessage[query.errorCode] ??
      uploadErrorMessage.CSV_IMPORT_UPLOAD_FAILED
    : null;

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          action={
            <div className="flex flex-wrap items-center justify-end gap-2">
              <Link
                className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text hover:border-ui-border-strong hover:bg-ui-surface-subtle"
                download
                href="/marketplace/import/template"
                prefetch={false}
              >
                Unduh template CSV
              </Link>
            </div>
          }
          description="Unggah file pesanan marketplace, periksa data yang terbaca, lalu proses hanya setelah semuanya sesuai."
          eyebrow="Pesanan"
          title="Import Pesanan"
        />

        <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
          <Link
            className="inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
            href="/settings"
          >
            ← Kembali ke Pengaturan
          </Link>

          <StatusBadge tone="neutral">
            Stok fisik belum berubah sebelum proses final
          </StatusBadge>
        </div>

        {errorMessage ? (
          <Alert
            className="mt-6"
            title="Import belum dibuat"
            tone="danger"
          >
            {errorMessage}
          </Alert>
        ) : null}

        <section
          aria-labelledby="upload-title"
          className="mt-8 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 sm:p-6"
        >
          <div className="max-w-3xl">
            <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
              Langkah 1
            </p>
            <h2
              className="mt-1 text-lg font-semibold text-ui-text"
              id="upload-title"
            >
              Unggah dan periksa file
            </h2>
            <p className="mt-2 text-sm leading-6 text-ui-text-muted">
              Mengunggah file hanya membuat preview. Tidak ada reservasi atau perubahan stok sampai Anda memproses hasil validasi pada langkah berikutnya.
            </p>
          </div>

          <form
            action={stageMarketplaceCsvAction}
            className="mt-5 grid gap-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end"
          >
            <Field
              description="Gunakan template CSV yang disediakan. Ukuran maksimum 10 MB."
              id="marketplace-import-file"
              label="File CSV"
            >
              {(controlProps) => (
                <Input
                  {...controlProps}
                  accept=".csv,text/csv"
                  name="file"
                  required
                  type="file"
                />
              )}
            </Field>

            <Button type="submit">
              Unggah untuk preview
            </Button>
          </form>
        </section>

        <section
          aria-labelledby="jobs-title"
          className="mt-8"
        >
          <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h2
                className="text-lg font-semibold text-ui-text"
                id="jobs-title"
              >
                Riwayat import
              </h2>
              <p className="mt-1 text-sm text-ui-text-muted">
                Import terbaru ditampilkan lebih dahulu.
              </p>
            </div>

            <span className="ui-number text-sm font-semibold text-ui-text">
              {data.rows.length} ditampilkan
            </span>
          </div>

          {data.rows.length === 0 ? (
            <div className="mt-4 rounded-[var(--ui-radius-lg)] border border-dashed border-ui-border px-5 py-8 text-center">
              <p className="font-semibold text-ui-text">
                Belum ada import
              </p>
              <p className="mt-1 text-sm text-ui-text-muted">
                Unggah file pertama untuk mulai memeriksa pesanan marketplace.
              </p>
            </div>
          ) : (
            <div className="mt-4 overflow-x-auto rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface">
              <table className="w-full min-w-[860px] text-left text-sm">
                <thead className="border-b border-ui-border bg-ui-surface-subtle text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
                  <tr>
                    <th className="px-4 py-3">
                      File
                    </th>
                    <th className="px-4 py-3">
                      Status
                    </th>
                    <th className="px-4 py-3 text-right">
                      Baris
                    </th>
                    <th className="px-4 py-3 text-right">
                      Valid / bermasalah
                    </th>
                    <th className="px-4 py-3">
                      Dibuat
                    </th>
                    <th
                      aria-label="Aksi"
                      className="px-4 py-3"
                    />
                  </tr>
                </thead>

                <tbody className="divide-y divide-ui-border">
                  {data.rows.map((job) => (
                    <tr key={job.id}>
                      <td className="px-4 py-4">
                        <p className="font-semibold text-ui-text">
                          {job.original_file_name}
                        </p>
                        <p className="mt-1 text-xs text-ui-text-muted">
                          Template {job.template_version}
                        </p>
                      </td>

                      <td className="px-4 py-4">
                        <StatusBadge
                          tone={statusTone(job.status_code)}
                        >
                          {statusLabel[job.status_code] ??
                            job.status_code}
                        </StatusBadge>
                      </td>

                      <td className="ui-number px-4 py-4 text-right text-ui-text">
                        {job.row_count}
                      </td>

                      <td className="ui-number px-4 py-4 text-right text-ui-text">
                        {job.valid_row_count} /{" "}
                        {job.invalid_row_count}
                      </td>

                      <td className="px-4 py-4 text-xs text-ui-text-muted">
                        {formatDate(job.created_at)} WIB
                      </td>

                      <td className="px-4 py-4 text-right">
                        <Link
                          className="font-semibold text-ui-primary hover:underline"
                          href={`/marketplace/import/${job.id}`}
                        >
                          Buka detail
                        </Link>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      </div>
    </AppShell>
  );
}