import { LiveQueryControls } from "@/components/ui/live-query-controls";
import {
  randomUUID,
} from "node:crypto";
import Link from "next/link";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  runReconciliationAction,
} from "@/app/actions";
import {
  Alert,
  EmptyState,
  StatusBadge,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  getReconciliationData,
  getReconciliationRunData,
  type ReconciliationCheck,
  type ReconciliationIssue,
  type ReconciliationRun,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = Record<
  string,
  string | string[] | undefined
>;

const checks = [
  {
    code: "LEDGER_BATCH_PROJECTION",
    label: "Saldo ledger dan batch",
  },
  {
    code: "BATCH_PRODUCT_PROJECTION",
    label: "Saldo batch dan produk",
  },
  {
    code: "RESERVATION_CONSISTENCY",
    label: "Reservasi pesanan",
  },
  {
    code: "MARKETPLACE_ALLOCATION_CONSISTENCY",
    label: "Alokasi pengiriman",
  },
  {
    code: "RETURN_RECEIPT_CONSISTENCY",
    label: "Penerimaan retur",
  },
  {
    code: "RETURN_INSPECTION_CONSISTENCY",
    label: "Dampak stok retur",
  },
  {
    code: "DUPLICATE_SOURCE_EFFECT",
    label: "Dampak transaksi ganda",
  },
  {
    code: "IMPOSSIBLE_PROJECTION_STATE",
    label: "Kondisi saldo tidak mungkin",
  },
] as const;

const dateFormatter =
  new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    dateStyle: "medium",
    timeStyle: "short",
  });

function first(
  value: SearchParams[string],
) {
  return Array.isArray(value)
    ? value[0]
    : value;
}

function formatDate(
  value: string | null,
) {
  if (!value) {
    return "Belum pernah";
  }

  const date =
    new Date(value);

  return Number.isNaN(
    date.getTime(),
  )
    ? value
    : dateFormatter.format(
        date,
      );
}

function checkLabel(
  code: string,
) {
  return (
    checks.find(
      (item) =>
        item.code === code,
    )?.label ??
    "Pemeriksaan lainnya"
  );
}

function severityLabel(
  severity:
    ReconciliationIssue[
      "severity_code"
    ],
) {
  if (
    severity === "CRITICAL"
  ) {
    return "Kritis";
  }

  if (
    severity === "HIGH"
  ) {
    return "Mendesak";
  }

  if (
    severity === "MEDIUM"
  ) {
    return "Perlu Diperiksa";
  }

  if (
    severity === "LOW"
  ) {
    return "Perlu Diperiksa";
  }

  return "Informasi";
}

function severityTone(
  severity:
    ReconciliationIssue[
      "severity_code"
    ],
) {
  if (
    severity === "CRITICAL"
  ) {
    return "danger" as const;
  }

  if (
    severity === "HIGH" ||
    severity === "MEDIUM"
  ) {
    return "warning" as const;
  }

  return "neutral" as const;
}

function runLabel(
  status: string,
) {
  if (status === "SUCCEEDED") {
    return "Selesai";
  }

  if (status === "FAILED" || status === "ERROR") {
    return "Gagal";
  }

  if (status === "RUNNING" || status === "PENDING") {
    return "Sedang berjalan";
  }

  return status;
}

function runTone(
  status: string,
) {
  if (status === "SUCCEEDED") {
    return "selected" as const;
  }

  if (status === "FAILED" || status === "ERROR") {
    return "danger" as const;
  }

  if (status === "RUNNING" || status === "PENDING") {
    return "warning" as const;
  }

  return "neutral" as const;
}

function summaryNumber(
  summary: Record<string, unknown>,
  key: string,
) {
  const value = summary[key];

  return typeof value === "number" && Number.isFinite(value)
    ? value
    : null;
}

function recordString(
  value: Record<
    string,
    unknown
  >,
  keys: string[],
) {
  for (
    const key of keys
  ) {
    const candidate =
      value[key];

    if (
      typeof candidate ===
        "string" &&
      candidate.trim()
    ) {
      return candidate.trim();
    }
  }

  return null;
}

function entityLabel(
  issue:
    ReconciliationIssue,
) {
  const entity =
    issue.entity_key &&
    typeof issue.entity_key ===
      "object"
      ? issue.entity_key
      : {};

  const primary =
    recordString(
      entity,
      [
        "productSku",
        "product_sku",
        "sku",
        "batchCode",
        "batch_code",
        "orderRef",
        "order_ref",
        "returnRef",
        "return_ref",
        "sourceRef",
        "source_ref",
      ],
    ) ??
    issue.source_ref ??
    "Data stok";

  const secondary =
    recordString(
      entity,
      [
        "batchCode",
        "batch_code",
        "lineRef",
        "line_ref",
      ],
    );

  return {
    primary,
    secondary,
  };
}

function compactValue(
  value: unknown,
) {
  if (
    value === null ||
    value === undefined
  ) {
    return "Tidak tersedia";
  }

  if (
    typeof value ===
      "string" ||
    typeof value ===
      "number"
  ) {
    return String(value);
  }

  try {
    const text =
      JSON.stringify(value);

    return text.length > 120
      ? `${text.slice(0, 117)}...`
      : text;
  } catch {
    return "Detail tersedia";
  }
}

function filtersHref({
  checkCode,
  q,
  severity,
  status,
}: {
  checkCode: string;
  q: string;
  severity: string;
  status: string;
}) {
  const query =
    new URLSearchParams();

  if (q) {
    query.set("q", q);
  }

  if (
    severity !== "ALL"
  ) {
    query.set(
      "severity",
      severity,
    );
  }

  if (
    status !== "OPEN"
  ) {
    query.set(
      "status",
      status,
    );
  }

  if (checkCode !== "ALL") {
    query.set("checkCode", checkCode);
  }

  const encoded =
    query.toString();

  return `/stock-issues${
    encoded
      ? `?${encoded}`
      : ""
  }`;
}

export default async function StockIssuesPage({
  searchParams,
}: {
  searchParams:
    Promise<SearchParams>;
}) {
  const [session, query] =
    await Promise.all([
      requireAdminSession(),
      searchParams,
    ]);

  const q =
    first(query.q)
      ?.trim()
      .toLowerCase() ?? "";

  const status =
    first(query.status) ===
    "RESOLVED"
      ? "RESOLVED"
      : first(query.status) ===
          "ALL"
        ? "ALL"
        : "OPEN";

  const severity =
    first(
      query.severity,
    ) ?? "ALL";

  const requestedCheckCode =
    first(query.checkCode) ?? "ALL";
  const checkCode =
    requestedCheckCode === "ALL" ||
    checks.some(
      (check) =>
        check.code === requestedCheckCode,
    )
      ? requestedCheckCode
      : "ALL";

  const requestedRunId =
    first(query.runId) ?? null;

  const selectedIssueId =
    first(
      query.issueId,
    ) ?? null;

  const success =
    first(query.success);
  const error =
    first(query.error);

  let data = null;
  let requestedRunData:
    | Awaited<
        ReturnType<
          typeof getReconciliationRunData
        >
      >
    | null = null;

  try {
    [data, requestedRunData] =
      await Promise.all([
        getReconciliationData(
          session.profile
            .organization_id,
        ),
        requestedRunId
          ? getReconciliationRunData(
              requestedRunId,
              session.profile
                .organization_id,
            )
          : Promise.resolve(null),
      ]);
  } catch {
    data = null;
  }

  if (!data) {
    return (
      <AppShell
        profile={session.profile}
      >
        <div className="mx-auto w-full max-w-[1180px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader
            description="Periksa ketidaksesuaian pada catatan stok dan telusuri penyebabnya."
            eyebrow="Stok"
            title="Masalah Stok"
          />

          <Alert
            className="mt-6"
            title="Masalah stok belum dapat dimuat"
            tone="warning"
          >
            Muat ulang halaman. Kondisi gagal ini tidak mengubah stok.
          </Alert>
        </div>
      </AppShell>
    );
  }

  const latestRun =
    data.runs[0] ?? null;

  const openIssues =
    data.issues.filter(
      (issue) =>
        issue.status_code ===
        "OPEN",
    );

  const criticalCount =
    openIssues.filter(
      (issue) =>
        issue.severity_code ===
        "CRITICAL",
    ).length;

  const filtered =
    data.issues.filter(
      (issue) => {
        if (
          status !== "ALL" &&
          issue.status_code !==
            status
        ) {
          return false;
        }

        if (
          severity !== "ALL" &&
          issue.severity_code !==
            severity
        ) {
          return false;
        }

        if (
          checkCode !== "ALL" &&
          issue.check_code !== checkCode
        ) {
          return false;
        }

        if (!q) {
          return true;
        }

        const entity =
          entityLabel(issue);

        return [
          entity.primary,
          entity.secondary,
          issue.source_ref,
          issue.check_code,
          checkLabel(
            issue.check_code,
          ),
        ]
          .filter(Boolean)
          .join(" ")
          .toLowerCase()
          .includes(q);
      },
    );

  const selectedIssue =
    selectedIssueId
      ? data.issues.find(
          (issue) =>
            issue.issue_id ===
            selectedIssueId,
        ) ?? null
      : null;
  const selectedIssueMissing =
    Boolean(selectedIssueId) &&
    !selectedIssue;
  const selectedRun =
    requestedRunId
      ? requestedRunData?.run ?? null
      : latestRun;
  const selectedChecks:
    ReconciliationCheck[] =
    requestedRunId
      ? requestedRunData?.checks ?? []
      : selectedRun
        ? data.checks.filter(
            (check) =>
              check.run_id ===
              selectedRun.run_id,
          )
        : [];
  const selectedRunMissing =
    Boolean(requestedRunId) &&
    !selectedRun;
  const visibleRuns:
    ReconciliationRun[] =
    selectedRun &&
    !data.runs.some(
      (run) =>
        run.run_id === selectedRun.run_id,
    )
      ? [selectedRun, ...data.runs]
      : data.runs;

  const evidence =
    selectedIssue
      ? data.evidence.filter(
          (row) =>
            row.issue_id ===
            selectedIssue.issue_id,
        )
      : [];

  const baseHref =
    filtersHref({
      checkCode,
      q,
      severity,
      status,
    });

  return (
    <AppShell
      profile={session.profile}
    >
      <div className="mx-auto w-full max-w-[1180px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          action={
            <form
              action={
                runReconciliationAction
              }
            >
              <input
                name="idempotencyKey"
                type="hidden"
                value={
                  randomUUID()
                }
              />

              {checks.map(
                (check) => (
                  <input
                    key={
                      check.code
                    }
                    name="checkCodes"
                    type="hidden"
                    value={
                      check.code
                    }
                  />
                ),
              )}

              <button
                className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
                type="submit"
              >
                Periksa Stok Sekarang
              </button>
            </form>
          }
          description="Periksa ketidaksesuaian pada catatan stok dan telusuri penyebabnya."
          eyebrow="Stok"
          title="Masalah Stok"
        />

        {success ? (
          <Alert
            className="mt-6"
            title="Pemeriksaan selesai"
            tone="success"
          >
            {success}
          </Alert>
        ) : null}

        {error ? (
          <Alert
            className="mt-6"
            title="Pemeriksaan belum selesai"
            tone="warning"
          >
            {error}
          </Alert>
        ) : null}

        <section
          aria-labelledby="manual-run-heading"
          className="mt-7 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5"
          id="manual-run"
        >
          <div>
            <h2
              className="text-lg font-semibold text-ui-text"
              id="manual-run-heading"
            >
              Jalankan pemeriksaan stok
            </h2>
            <p className="mt-1 text-sm text-ui-text-muted">
              Pemeriksaan hanya membandingkan catatan dan menyimpan hasil audit. Saldo stok tidak diubah.
            </p>
          </div>

          <form
            action={runReconciliationAction}
            className="mt-4"
          >
            <input
              name="idempotencyKey"
              type="hidden"
              value={randomUUID()}
            />

            <details className="rounded-[var(--ui-radius-md)] border border-ui-border p-4">
              <summary className="cursor-pointer text-sm font-semibold text-ui-text">
                Pilih pemeriksaan yang akan dijalankan
              </summary>
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                {checks.map((check) => (
                  <label
                    className="flex gap-3 text-sm text-ui-text"
                    key={check.code}
                  >
                    <input
                      className="mt-0.5 h-4 w-4"
                      defaultChecked
                      name="checkCodes"
                      type="checkbox"
                      value={check.code}
                    />
                    <span>{check.label}</span>
                  </label>
                ))}
              </div>
            </details>

            <button
              className="mt-4 inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
              type="submit"
            >
              Jalankan pemeriksaan terpilih
            </button>
          </form>
        </section>

        <section
          aria-label="Kondisi masalah stok"
          className="mt-7 border-y border-ui-border py-5"
        >
          <dl className="grid gap-5 sm:grid-cols-4">
            <div>
              <dt className="text-sm text-ui-text-muted">
                Perlu diperiksa
              </dt>
              <dd className="ui-number mt-1 text-2xl font-semibold text-ui-text">
                {openIssues.length}
              </dd>
            </div>

            <div>
              <dt className="text-sm text-ui-text-muted">
                Kritis
              </dt>
              <dd className="ui-number mt-1 text-2xl font-semibold text-ui-danger">
                {criticalCount}
              </dd>
            </div>

            <div>
              <dt className="text-sm text-ui-text-muted">
                Pemeriksaan terakhir
              </dt>
              <dd className="mt-1 text-sm font-semibold text-ui-text">
                {latestRun?.run_no ?? "Belum pernah"}
              </dd>
              <p className="mt-1 text-xs text-ui-text-muted">
                {latestRun
                  ? `${runLabel(latestRun.status_code)} · ${formatDate(latestRun.completed_at ?? latestRun.started_at)}`
                  : "Jalankan pemeriksaan pertama"}
              </p>
            </div>

            <div>
              <dt className="text-sm text-ui-text-muted">
                Pemeriksaan aktif
              </dt>
              <dd className="ui-number mt-1 text-2xl font-semibold text-ui-text">
                {latestRun?.check_codes.length ?? 0}
              </dd>
            </div>
          </dl>
        </section>

        <section
          aria-labelledby="stock-issues-heading"
          className="mt-8"
        >
          <div>
            <h2
              className="text-lg font-semibold text-ui-text"
              id="stock-issues-heading"
            >
              Masalah yang ditemukan
            </h2>
            <p className="mt-1 text-sm text-ui-text-muted">
              Pemeriksaan ini membandingkan catatan sistem. Hitung fisik tetap dilakukan lewat Hitung Stok.
            </p>
          </div>

          <LiveQueryControls
            className="mt-5 shadow-none"
            resetKeys={["cursor", "direction", "page", "issueId", "runId"]}
            fields={[
              {
                kind: "search",
                name: "q",
                ariaLabel: "Cari masalah stok",
                placeholder: "Cari produk, batch, order, atau referensi",
              },
              {
                kind: "select",
                name: "status",
                ariaLabel: "Filter status masalah stok",
                options: [
                  { value: "OPEN", label: "Perlu diperiksa" },
                  { value: "RESOLVED", label: "Selesai" },
                  { value: "ALL", label: "Semua" },
                ],
              },
              {
                kind: "select",
                name: "severity",
                ariaLabel: "Filter prioritas masalah stok",
                options: [
                  { value: "", label: "Semua prioritas" },
                  { value: "CRITICAL", label: "Kritis" },
                  { value: "HIGH", label: "Mendesak" },
                  { value: "MEDIUM", label: "Perlu Diperiksa" },
                  { value: "LOW", label: "Rendah" },
                  { value: "INFO", label: "Informasi" },
                ],
              },
              {
                kind: "select",
                name: "checkCode",
                ariaLabel: "Filter jenis pemeriksaan stok",
                options: [
                  { value: "", label: "Semua pemeriksaan" },
                  ...checks.map((check) => ({
                    value: check.code,
                    label: check.label,
                  })),
                ],
              },
            ]}
          />

          {selectedIssueMissing ? (
            <Alert
              className="mt-5"
              title="Masalah stok tidak ditemukan"
              tone="warning"
            >
              Tautan ini tidak merujuk ke masalah stok pada organisasi Anda. Tidak ada kesimpulan aman yang dibuat.
            </Alert>
          ) : null}

          {filtered.length ===
          0 ? (
            <EmptyState
              className="mt-5"
              description={
                openIssues.length === 0 &&
                status === "OPEN"
                  ? "Pemeriksaan terakhir tidak menemukan masalah stok aktif."
                  : "Tidak ada masalah stok yang cocok dengan filter ini."
              }
              title={
                openIssues.length === 0 &&
                status === "OPEN"
                  ? "Catatan stok konsisten"
                  : "Tidak ada hasil"
              }
            />
          ) : (
            <div className="mt-5 overflow-hidden border-y border-ui-border">
              <div className="hidden grid-cols-[minmax(0,1.2fr)_minmax(0,1.4fr)_11rem_8rem] gap-4 border-b border-ui-border bg-ui-surface-subtle px-4 py-3 text-xs font-semibold uppercase tracking-wide text-ui-text-muted md:grid">
                <span>Data terkait</span>
                <span>Masalah</span>
                <span>Prioritas</span>
                <span aria-hidden="true" />
              </div>

              <div className="divide-y divide-ui-border">
                {filtered.map(
                  (issue) => {
                    const entity =
                      entityLabel(
                        issue,
                      );

                    const issueHref =
                      `${baseHref}${
                        baseHref.includes(
                          "?",
                        )
                          ? "&"
                          : "?"
                      }issueId=${encodeURIComponent(
                        issue.issue_id,
                      )}`;

                    return (
                      <article
                        className="grid gap-3 px-4 py-4 md:grid-cols-[minmax(0,1.2fr)_minmax(0,1.4fr)_11rem_8rem] md:items-center md:gap-4"
                        key={
                          issue.issue_id
                        }
                      >
                        <div>
                          <p className="text-sm font-semibold text-ui-text">
                            {
                              entity.primary
                            }
                          </p>
                          <p className="mt-1 text-xs text-ui-text-muted">
                            {entity.secondary ??
                              issue.entity_type_code}
                          </p>
                        </div>

                        <div>
                          <p className="text-sm font-medium text-ui-text">
                            {checkLabel(
                              issue.check_code,
                            )}
                          </p>
                          <p className="mt-1 text-xs text-ui-text-muted">
                            {issue.status_code === "RESOLVED"
                              ? "Selesai"
                              : "Perlu diperiksa"} · terlihat terakhir {formatDate(
                              issue.last_seen_at,
                            )}
                          </p>
                        </div>

                        <StatusBadge
                          tone={severityTone(
                            issue.severity_code,
                          )}
                        >
                          {severityLabel(
                            issue.severity_code,
                          )}
                        </StatusBadge>

                        <Link
                          className="text-sm font-semibold text-ui-primary hover:underline"
                          href={
                            issueHref
                          }
                        >
                          Buka masalah
                        </Link>
                      </article>
                    );
                  },
                )}
              </div>
            </div>
          )}
        </section>

        {selectedIssue ? (
          <section
            aria-labelledby="issue-detail-heading"
            className="mt-8 border-t border-ui-border pt-7"
          >
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-ui-primary">
                  Detail masalah
                </p>
                <h2
                  className="mt-1 text-xl font-semibold text-ui-text"
                  id="issue-detail-heading"
                >
                  {checkLabel(
                    selectedIssue.check_code,
                  )}
                </h2>
              </div>

              <div className="flex items-center gap-4">
                <StatusBadge
                  tone={
                    selectedIssue.status_code === "RESOLVED"
                      ? "selected"
                      : "warning"
                  }
                >
                  {selectedIssue.status_code === "RESOLVED"
                    ? "Selesai"
                    : "Perlu diperiksa"}
                </StatusBadge>
                <Link
                  className="text-sm font-semibold text-ui-primary hover:underline"
                  href={baseHref}
                >
                  Tutup detail
                </Link>
              </div>
            </div>

            <div className="mt-5 grid gap-5 border-y border-ui-border py-5 sm:grid-cols-3">
              <div>
                <p className="text-sm text-ui-text-muted">
                  Yang seharusnya
                </p>
                <p className="mt-1 break-words text-sm font-semibold text-ui-text">
                  {compactValue(
                    selectedIssue.expected_value,
                  )}
                </p>
              </div>

              <div>
                <p className="text-sm text-ui-text-muted">
                  Yang tercatat
                </p>
                <p className="mt-1 break-words text-sm font-semibold text-ui-text">
                  {compactValue(
                    selectedIssue.actual_value,
                  )}
                </p>
              </div>

              <div>
                <p className="text-sm text-ui-text-muted">
                  Selisih / masalah
                </p>
                <p className="mt-1 break-words text-sm font-semibold text-ui-danger">
                  {compactValue(
                    selectedIssue.difference_value,
                  )}
                </p>
              </div>
            </div>

            {evidence.length >
            0 ? (
              <div className="mt-6">
                <h3 className="text-base font-semibold text-ui-text">
                  Bukti terkait
                </h3>

                <div className="mt-3 divide-y divide-ui-border">
                  {evidence.map(
                    (
                      row,
                      index,
                    ) => (
                      <div
                        className="py-3"
                        key={
                          row.evidence_id
                        }
                      >
                        <p className="text-sm font-semibold text-ui-text">
                          Bukti {index + 1}
                        </p>
                        <p className="mt-1 text-xs leading-5 text-ui-text-muted">
                          Seharusnya: {compactValue(
                            row.expected_value,
                          )} · Tercatat: {compactValue(
                            row.actual_value,
                          )}
                        </p>
                        <p className="mt-1 text-xs leading-5 text-ui-text-muted">
                          {compactValue(row.detail)} · {formatDate(row.created_at)}
                        </p>
                      </div>
                    ),
                  )}
                </div>
              </div>
            ) : null}

            <div className="mt-6 flex flex-wrap gap-3">
              {selectedIssue.product_id ? (
                <Link
                  className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-primary hover:bg-ui-primary-subtle"
                  href={`/products/${encodeURIComponent(
                    selectedIssue.product_id,
                  )}?tab=history`}
                >
                  Lihat Riwayat Produk
                </Link>
              ) : null}

              <Link
                className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-primary hover:bg-ui-primary-subtle"
                href="/ledger"
              >
                Lihat Riwayat Stok
              </Link>
            </div>

            <details className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4">
              <summary className="cursor-pointer text-sm font-semibold text-ui-text">
                Detail teknis
              </summary>

              <dl className="mt-4 grid gap-3 text-xs text-ui-text-muted sm:grid-cols-2">
                <div>
                  <dt>Pemeriksaan</dt>
                  <dd className="ui-code mt-1 break-all text-ui-text">
                    {selectedIssue.check_code}
                  </dd>
                </div>

                <div>
                  <dt>Referensi sumber</dt>
                  <dd className="ui-code mt-1 break-all text-ui-text">
                    {selectedIssue.source_ref ??
                      "-"}
                  </dd>
                </div>

                <div>
                  <dt>Terlihat pertama</dt>
                  <dd className="mt-1 text-ui-text">
                    {formatDate(
                      selectedIssue.first_seen_at,
                    )}
                  </dd>
                </div>

                <div>
                  <dt>Terulang</dt>
                  <dd className="mt-1 text-ui-text">
                    {selectedIssue.recurrence_count} kali
                  </dd>
                </div>

                <div>
                  <dt>Terlihat terakhir</dt>
                  <dd className="mt-1 text-ui-text">
                    {formatDate(selectedIssue.last_seen_at)}
                  </dd>
                </div>

                {selectedIssue.status_code === "RESOLVED" ? (
                  <div>
                    <dt>Penyelesaian</dt>
                    <dd className="mt-1 text-ui-text">
                      {selectedIssue.resolution_code ?? "Selesai"}
                      {selectedIssue.resolution_note
                        ? ` · ${selectedIssue.resolution_note}`
                        : ""}
                    </dd>
                  </div>
                ) : null}
              </dl>
            </details>
          </section>
        ) : null}

        <section
          aria-labelledby="reconciliation-runs-heading"
          className="mt-10 border-t border-ui-border pt-7"
        >
          <div>
            <h2
              className="text-lg font-semibold text-ui-text"
              id="reconciliation-runs-heading"
            >
              Riwayat pemeriksaan
            </h2>
            <p className="mt-1 text-sm text-ui-text-muted">
              Setiap run mencatat waktu, boundary ledger, dan hasil check tanpa mengubah stok.
            </p>
          </div>

          {selectedRunMissing ? (
            <Alert
              className="mt-5"
              title="Riwayat pemeriksaan tidak ditemukan"
              tone="warning"
            >
              Tautan ini tidak merujuk ke run pada organisasi Anda. Tidak ada kesimpulan aman yang dibuat.
            </Alert>
          ) : null}

          {visibleRuns.length === 0 ? (
            <EmptyState
              className="mt-5"
              description="Jalankan pemeriksaan untuk membuat catatan audit pertama."
              title="Belum ada riwayat pemeriksaan"
            />
          ) : (
            <div className="mt-5 divide-y divide-ui-border border-y border-ui-border">
              {visibleRuns.slice(0, 10).map((run) => {
                const runHref = `${baseHref}${
                  baseHref.includes("?") ? "&" : "?"
                }runId=${encodeURIComponent(run.run_id)}`;
                const issueCount =
                  summaryNumber(run.summary, "issueCount") ?? 0;

                return (
                  <article
                    className="grid gap-3 px-4 py-4 md:grid-cols-[minmax(0,1fr)_11rem_11rem_7rem] md:items-center md:gap-4"
                    key={run.run_id}
                  >
                    <div>
                      <Link
                        className="text-sm font-semibold text-ui-primary hover:underline"
                        href={runHref}
                      >
                        {run.run_no}
                      </Link>
                      <p className="mt-1 text-xs text-ui-text-muted">
                        {formatDate(run.completed_at ?? run.started_at)} · ledger {run.ledger_seq_from}–{run.ledger_seq_to}
                      </p>
                    </div>
                    <StatusBadge tone={runTone(run.status_code)}>
                      {runLabel(run.status_code)}
                    </StatusBadge>
                    <p className="text-sm text-ui-text-muted">
                      {run.check_codes.length} check · {issueCount} masalah
                    </p>
                    <Link
                      className="text-sm font-semibold text-ui-primary hover:underline"
                      href={runHref}
                    >
                      Lihat hasil
                    </Link>
                  </article>
                );
              })}
            </div>
          )}

          {selectedRun ? (
            <div className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-ui-primary">
                    Hasil pemeriksaan
                  </p>
                  <h3 className="mt-1 text-lg font-semibold text-ui-text">
                    {selectedRun.run_no}
                  </h3>
                </div>
                <StatusBadge tone={runTone(selectedRun.status_code)}>
                  {runLabel(selectedRun.status_code)}
                </StatusBadge>
              </div>

              <dl className="mt-5 grid gap-4 border-y border-ui-border py-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
                <div>
                  <dt className="text-ui-text-muted">Boundary ledger</dt>
                  <dd className="ui-code mt-1 text-ui-text">
                    {selectedRun.ledger_seq_from}–{selectedRun.ledger_seq_to}
                  </dd>
                </div>
                <div>
                  <dt className="text-ui-text-muted">Mulai</dt>
                  <dd className="mt-1 text-ui-text">
                    {formatDate(selectedRun.started_at)}
                  </dd>
                </div>
                <div>
                  <dt className="text-ui-text-muted">Selesai</dt>
                  <dd className="mt-1 text-ui-text">
                    {formatDate(selectedRun.completed_at)}
                  </dd>
                </div>
                <div>
                  <dt className="text-ui-text-muted">Versi aturan</dt>
                  <dd className="ui-code mt-1 break-all text-ui-text">
                    {selectedRun.rule_set_version}
                  </dd>
                </div>
              </dl>

              {selectedRun.error_code ? (
                <Alert
                  className="mt-5"
                  title="Pemeriksaan melaporkan kegagalan"
                  tone="warning"
                >
                  Kode audit: {selectedRun.error_code}
                </Alert>
              ) : null}

              <div className="mt-5">
                <h4 className="text-sm font-semibold text-ui-text">
                  Hasil per pemeriksaan
                </h4>
                {selectedChecks.length === 0 ? (
                  <p className="mt-2 text-sm text-ui-text-muted">
                    Belum ada hasil check yang tersedia untuk run ini.
                  </p>
                ) : (
                  <div className="mt-3 divide-y divide-ui-border border-y border-ui-border">
                    {selectedChecks.map((check) => (
                      <div
                        className="grid gap-2 px-3 py-3 sm:grid-cols-[minmax(0,1fr)_8rem_8rem] sm:items-center"
                        key={check.run_check_id}
                      >
                        <div>
                          <p className="text-sm font-medium text-ui-text">
                            {checkLabel(check.check_code)}
                          </p>
                          {check.error_code ? (
                            <p className="mt-1 text-xs text-ui-danger">
                              {check.error_code}
                            </p>
                          ) : null}
                        </div>
                        <p className="text-sm text-ui-text-muted">
                          {check.checked_count} data diperiksa
                        </p>
                        <p className="text-sm text-ui-text-muted">
                          {check.issue_count} masalah
                        </p>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          ) : null}
        </section>
      </div>
    </AppShell>
  );
}