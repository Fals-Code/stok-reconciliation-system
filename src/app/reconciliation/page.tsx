import { randomUUID } from "node:crypto";

import Link from "next/link";

import { runReconciliationAction } from "@/app/actions";
import {
  getReconciliationData,
  getReconciliationRunData,
  type ReconciliationIssue,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

const numberFormatter = new Intl.NumberFormat("id-ID");

const reconciliationChecks = [
  {
    code: "LEDGER_BATCH_PROJECTION",
    label: "Saldo ledger dan batch",
    category: "Stok dan batch",
    description:
      "Memastikan saldo per batch sama dengan pergerakan fisik yang tercatat di ledger.",
  },
  {
    code: "BATCH_PRODUCT_PROJECTION",
    label: "Saldo batch dan produk",
    category: "Stok dan batch",
    description:
      "Memastikan jumlah seluruh batch membentuk saldo produk yang sama.",
  },
  {
    code: "RESERVATION_CONSISTENCY",
    label: "Reservasi pesanan",
    category: "Pesanan marketplace",
    description:
      "Memastikan reservasi aktif sesuai dengan quantity order yang belum dilepas atau dikirim.",
  },
  {
    code: "MARKETPLACE_ALLOCATION_CONSISTENCY",
    label: "Alokasi shipment FEFO",
    category: "Pesanan marketplace",
    description:
      "Memastikan barang keluar marketplace memiliki alokasi batch FEFO yang lengkap.",
  },
  {
    code: "RETURN_RECEIPT_QUARANTINE",
    label: "Penerimaan retur",
    category: "Retur",
    description:
      "Memastikan barang retur yang diterima masuk ke quarantine dengan quantity yang tepat.",
  },
  {
    code: "RETURN_INSPECTION_TRANSFER",
    label: "Hasil inspeksi retur",
    category: "Retur",
    description:
      "Memastikan perpindahan quarantine ke sellable atau damaged tetap net-zero.",
  },
  {
    code: "DUPLICATE_SOURCE_EFFECT",
    label: "Transaksi sumber ganda",
    category: "Data ganda",
    description:
      "Mendeteksi satu command atau event yang menghasilkan lebih dari satu dampak domain.",
  },
  {
    code: "IMPOSSIBLE_PROJECTION_STATE",
    label: "Kondisi saldo tidak mungkin",
    category: "Integritas data",
    description:
      "Mendeteksi saldo negatif atau kombinasi projection yang melanggar invariant stok.",
  },
] as const;

type PillTone = "success" | "warning" | "danger" | "neutral";

type FilterState = {
  q: string;
  status: string;
  severity: string;
  checkCode: string;
  runId: string | null;
  issueId: string | null;
};

function formatNumber(value: number) {
  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null, includeTime = true) {
  if (!value) return "Belum ada";

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
    ...(includeTime
      ? { hour: "2-digit", minute: "2-digit", hour12: false }
      : {}),
  }).format(date);
}

function formatJson(value: unknown) {
  if (value === null || value === undefined) return "Tidak ada";

  if (typeof value === "string") {
    return value;
  }

  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function compactValue(value: unknown, maxLength = 72) {
  if (value === null || value === undefined) return "Tidak ada";

  if (typeof value === "number") {
    return formatNumber(value);
  }

  if (typeof value === "string") {
    return value.length > maxLength
      ? `${value.slice(0, maxLength - 3)}...`
      : value;
  }

  const text = formatJson(value).replace(/\s+/g, " ");
  return text.length > maxLength
    ? `${text.slice(0, maxLength - 3)}...`
    : text;
}

function summaryText(summary: Record<string, unknown>, key: string) {
  const value = summary[key];
  return typeof value === "string" ? value : null;
}

function summaryNumber(summary: Record<string, unknown>, key: string) {
  const value = summary[key];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function severityTone(severity: ReconciliationIssue["severity_code"]): PillTone {
  if (severity === "CRITICAL") return "danger";
  if (severity === "HIGH" || severity === "MEDIUM") return "warning";
  return "neutral";
}

function severityLabel(severity: ReconciliationIssue["severity_code"]) {
  const labels: Record<string, string> = {
    CRITICAL: "Kritis",
    HIGH: "Tinggi",
    MEDIUM: "Sedang",
    LOW: "Rendah",
    INFO: "Informasi",
  };

  return labels[severity] ?? severity;
}

function runTone(status: string): PillTone {
  if (status === "SUCCEEDED") return "success";
  if (status === "FAILED" || status === "ERROR") return "danger";
  if (status === "RUNNING" || status === "PENDING") return "warning";
  return "neutral";
}

function runLabel(status: string) {
  const labels: Record<string, string> = {
    SUCCEEDED: "Selesai",
    FAILED: "Gagal",
    ERROR: "Error",
    RUNNING: "Sedang berjalan",
    PENDING: "Menunggu",
  };

  return labels[status] ?? status;
}

function issueTone(status: string): PillTone {
  return status === "RESOLVED" ? "success" : "warning";
}

function issueStatusLabel(status: string) {
  return status === "RESOLVED" ? "Selesai" : "Perlu diperiksa";
}

function integrityTone(value: string | null): PillTone {
  if (value === "CLEAN") return "success";
  if (value === "ISSUES_FOUND") return "danger";
  return "neutral";
}

function integrityLabel(value: string | null) {
  if (value === "CLEAN") return "Aman";
  if (value === "ISSUES_FOUND") return "Perlu diperiksa";
  return "Belum diperiksa";
}

function checkDefinition(checkCode: string) {
  return (
    reconciliationChecks.find((check) => check.code === checkCode) ?? {
      code: checkCode,
      label: checkCode,
      category: "Pemeriksaan lain",
      description: "Detail pemeriksaan tersedia pada bagian teknis.",
    }
  );
}

function numericDifference(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  if (value && typeof value === "object" && !Array.isArray(value)) {
    const numericValues = Object.values(value).filter(
      (candidate): candidate is number =>
        typeof candidate === "number" && Number.isFinite(candidate),
    );

    if (numericValues.length === 1) {
      return numericValues[0];
    }
  }

  return null;
}

function differencePresentation(value: unknown) {
  const numeric = numericDifference(value);

  if (numeric === 0) {
    return {
      label: "Sesuai",
      detail: "Tidak ada selisih",
      tone: "success" as const,
    };
  }

  if (numeric !== null && numeric < 0) {
    return {
      label: `Kurang ${formatNumber(Math.abs(numeric))}`,
      detail: compactValue(value),
      tone: "danger" as const,
    };
  }

  if (numeric !== null && numeric > 0) {
    return {
      label: `Lebih ${formatNumber(numeric)}`,
      detail: compactValue(value),
      tone: "warning" as const,
    };
  }

  return {
    label: "Ada selisih",
    detail: compactValue(value),
    tone: "warning" as const,
  };
}

function recordString(record: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }

  return null;
}

function issueEntityLabel(issue: ReconciliationIssue) {
  const entity =
    issue.entity_key && typeof issue.entity_key === "object"
      ? (issue.entity_key as Record<string, unknown>)
      : {};

  const primary =
    recordString(entity, [
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
    ]) ??
    issue.source_ref ??
    issue.entity_type_code;

  const secondary =
    recordString(entity, ["batchCode", "batch_code", "lineRef", "line_ref"]) ??
    issue.batch_id ??
    issue.product_id;

  return {
    primary,
    secondary:
      secondary && secondary !== primary ? secondary : issue.entity_type_code,
  };
}

function issueSearchText(issue: ReconciliationIssue) {
  const definition = checkDefinition(issue.check_code);

  return [
    issue.check_code,
    definition.label,
    definition.category,
    issue.entity_type_code,
    issue.source_type_code,
    issue.source_ref,
    issue.product_id,
    issue.batch_id,
    formatJson(issue.entity_key),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function Pill({ label, tone }: { label: string; tone: PillTone }) {
  const tones = {
    success: "border-emerald-400/25 bg-emerald-400/10 text-emerald-200",
    warning: "border-amber-400/25 bg-amber-400/10 text-amber-100",
    danger: "border-rose-400/25 bg-rose-400/10 text-rose-100",
    neutral: "border-white/10 bg-white/[0.04] text-slate-300",
  };

  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-medium ${tones[tone]}`}
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
          Rekonsiliasi tidak tersedia
        </p>
        <h1 className="mt-3 text-3xl font-semibold">
          Data rekonsiliasi gagal dimuat.
        </h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <Link className="nav-link mt-6 inline-flex" href="/">
          Kembali ke dashboard
        </Link>
      </section>
    </main>
  );
}

function reconciliationHref(
  state: FilterState,
  updates: Partial<FilterState>,
  hash: "issues" | "runs",
) {
  const merged = { ...state, ...updates };
  const params = new URLSearchParams();

  if (merged.q) params.set("q", merged.q);
  if (merged.status !== "ALL") params.set("status", merged.status);
  if (merged.severity !== "ALL") params.set("severity", merged.severity);
  if (merged.checkCode !== "ALL") {
    params.set("checkCode", merged.checkCode);
  }
  if (merged.runId) params.set("runId", merged.runId);
  if (merged.issueId) params.set("issueId", merged.issueId);

  const query = params.toString();
  return `/reconciliation${query ? `?${query}` : ""}#${hash}`;
}

export default async function ReconciliationPage({
  searchParams,
}: {
  searchParams: Promise<{
    q?: string;
    status?: string;
    severity?: string;
    checkCode?: string;
    runId?: string;
    issueId?: string;
    success?: string;
    error?: string;
  }>;
}) {
  const params = await searchParams;
  let data;
  let requestedRunData:
    | Awaited<ReturnType<typeof getReconciliationRunData>>
    | null = null;

  try {
    [data, requestedRunData] = await Promise.all([
      getReconciliationData(),
      params.runId
        ? getReconciliationRunData(params.runId)
        : Promise.resolve(null),
    ]);
  } catch (error) {
    return (
      <ConfigurationError
        message={error instanceof Error ? error.message : "Konfigurasi tidak valid."}
      />
    );
  }

  const { runs, checks, issues, evidence } = data;

  const allowedStatuses = new Set(["ALL", "OPEN", "RESOLVED"]);
  const allowedSeverities = new Set([
    "ALL",
    "INFO",
    "LOW",
    "MEDIUM",
    "HIGH",
    "CRITICAL",
  ]);

  const query = params.q?.trim() ?? "";
  const normalizedQuery = query.toLowerCase();
  const statusFilter = allowedStatuses.has(params.status ?? "")
    ? String(params.status)
    : "ALL";
  const severityFilter = allowedSeverities.has(params.severity ?? "")
    ? String(params.severity)
    : "ALL";

  const availableCheckCodes = Array.from(
    new Set(issues.map((issue) => issue.check_code)),
  ).sort();

  const checkCodeFilter =
    params.checkCode && availableCheckCodes.includes(params.checkCode)
      ? params.checkCode
      : "ALL";

  const filteredIssues = issues.filter((issue) => {
    if (statusFilter !== "ALL" && issue.status_code !== statusFilter) {
      return false;
    }

    if (severityFilter !== "ALL" && issue.severity_code !== severityFilter) {
      return false;
    }

    if (checkCodeFilter !== "ALL" && issue.check_code !== checkCodeFilter) {
      return false;
    }

    if (normalizedQuery && !issueSearchText(issue).includes(normalizedQuery)) {
      return false;
    }

    return true;
  });

  const requestedRunMissing =
    Boolean(params.runId) && !requestedRunData?.run;
  const selectedRun = params.runId
    ? requestedRunData?.run ?? null
    : runs[0] ?? null;
  const selectedChecks = params.runId
    ? requestedRunData?.checks ?? []
    : selectedRun
      ? checks
          .filter((check) => check.run_id === selectedRun.run_id)
          .sort((left, right) =>
            left.check_code.localeCompare(right.check_code),
          )
      : [];
  const visibleRuns =
    selectedRun &&
    !runs.some((run) => run.run_id === selectedRun.run_id)
      ? [selectedRun, ...runs]
      : runs;

  const selectedIssue =
    issues.find((issue) => issue.issue_id === params.issueId) ??
    filteredIssues[0] ??
    null;
  const selectedEvidence = selectedIssue
    ? evidence
        .filter((item) => item.issue_id === selectedIssue.issue_id)
        .sort((left, right) => {
          const timeDifference =
            new Date(right.created_at).getTime() -
            new Date(left.created_at).getTime();

          if (timeDifference !== 0) return timeDifference;
          return left.evidence_no - right.evidence_no;
        })
    : [];

  const latestRun = runs[0] ?? null;
  const latestIntegrityStatus = latestRun
    ? summaryText(latestRun.summary, "integrityStatus")
    : null;

  const openIssues = issues.filter((issue) => issue.status_code === "OPEN");
  const openCritical = openIssues.filter(
    (issue) => issue.severity_code === "CRITICAL",
  ).length;
  const openHigh = openIssues.filter(
    (issue) => issue.severity_code === "HIGH",
  ).length;
  const affectedProducts = new Set(
    openIssues
      .map((issue) => issue.product_id)
      .filter((productId): productId is string => Boolean(productId)),
  ).size;
  const oldestOpenIssue = openIssues.reduce<ReconciliationIssue | null>(
    (oldest, issue) => {
      if (!oldest) return issue;
      return new Date(issue.first_seen_at) < new Date(oldest.first_seen_at)
        ? issue
        : oldest;
    },
    null,
  );

  const filterState: FilterState = {
    q: query,
    status: statusFilter,
    severity: severityFilter,
    checkCode: checkCodeFilter,
    runId: selectedRun?.run_id ?? null,
    issueId: selectedIssue?.issue_id ?? null,
  };

  const activeFilters = [
    query ? `Pencarian: ${query}` : null,
    statusFilter !== "ALL"
      ? `Status: ${statusFilter === "OPEN" ? "Perlu diperiksa" : "Selesai"}`
      : null,
    severityFilter !== "ALL"
      ? `Tingkat: ${severityLabel(
          severityFilter as ReconciliationIssue["severity_code"],
        )}`
      : null,
    checkCodeFilter !== "ALL"
      ? `Jenis: ${checkDefinition(checkCodeFilter).label}`
      : null,
  ].filter((filter): filter is string => Boolean(filter));

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <header className="sticky top-0 z-20 border-b border-white/10 bg-slate-950/90 backdrop-blur">
        <div className="mx-auto flex max-w-[1500px] items-center justify-between gap-5 px-5 py-4 lg:px-8">
          <div>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-emerald-300">
              GlowLab Inventory
            </p>
            <p className="mt-1 text-sm text-slate-400">
              Kontrol konsistensi stok
            </p>
          </div>

          <nav className="hidden items-center gap-2 text-sm md:flex">
            <a className="nav-link" href="#overview">
              Ringkasan
            </a>
            <a className="nav-link" href="#issues">
              Masalah
            </a>
            <a className="nav-link" href="#runs">
              Riwayat
            </a>
          </nav>

          <div className="flex items-center gap-2">
            <Link className="nav-link border border-white/10" href="/stocktakes">
              Stocktakes
            </Link>
            <Link className="nav-link border border-white/10" href="/marketplace">
              Marketplace
            </Link>
            <Link className="nav-link border border-white/10" href="/returns">
              Retur
            </Link>
            <Link className="nav-link border border-white/10" href="/">
              Dashboard
            </Link>
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section id="overview" className="scroll-mt-24">
          <div className="flex flex-col gap-6 xl:flex-row xl:items-end xl:justify-between">
            <div>
              <p className="section-kicker">Rekonsiliasi stok</p>
              <h1 className="mt-3 max-w-4xl text-3xl font-semibold tracking-tight sm:text-4xl">
                Pastikan catatan stok tetap konsisten.
              </h1>
              <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
                Sistem membandingkan ledger, saldo batch, reservasi, shipment,
                dan retur. Pemeriksaan hanya membaca data dan menyimpan hasil.
                Quantity stok tidak diubah.
              </p>
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <Pill label="Tidak mengubah stok" tone="success" />
              <Pill label="8 pemeriksaan aktif" tone="neutral" />
            </div>
          </div>

          {params.success ? (
            <div className="mt-6 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-100">
              {params.success}
            </div>
          ) : null}

          {params.error ? (
            <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-100">
              {params.error}
            </div>
          ) : null}

          <div className="mt-7 overflow-hidden rounded-2xl border border-white/10 bg-white/[0.025]">
            <div className="grid sm:grid-cols-2 xl:grid-cols-4">
              <article className="border-b border-white/10 p-5 sm:border-r xl:border-b-0">
                <p className="text-sm text-slate-400">Kondisi catatan stok</p>
                <div className="mt-3">
                  <Pill
                    label={integrityLabel(latestIntegrityStatus)}
                    tone={integrityTone(latestIntegrityStatus)}
                  />
                </div>
                <p className="mt-3 text-xs text-slate-500">
                  Status run: {latestRun ? runLabel(latestRun.status_code) : "Belum ada"}
                </p>
              </article>

              <article className="border-b border-white/10 p-5 xl:border-b-0 xl:border-r">
                <p className="text-sm text-slate-400">Pemeriksaan terakhir</p>
                <p className="mt-3 text-2xl font-semibold text-white">
                  {latestRun?.run_no ?? "Belum pernah"}
                </p>
                <p className="mt-2 text-xs text-slate-500">
                  {latestRun
                    ? formatDate(latestRun.completed_at ?? latestRun.started_at)
                    : "Jalankan pemeriksaan pertama"}
                </p>
              </article>

              <article className="border-b border-white/10 p-5 sm:border-r xl:border-b-0">
                <p className="text-sm text-slate-400">Masalah terbuka</p>
                <p className="mt-3 text-3xl font-semibold text-white">
                  {formatNumber(openIssues.length)}
                </p>
                <p className="mt-2 text-xs text-slate-500">
                  Kritis {openCritical} / Tinggi {openHigh}
                </p>
              </article>

              <article className="p-5">
                <p className="text-sm text-slate-400">Produk terdampak</p>
                <p className="mt-3 text-3xl font-semibold text-white">
                  {formatNumber(affectedProducts)}
                </p>
                <p className="mt-2 text-xs text-slate-500">
                  Terlama:{" "}
                  {oldestOpenIssue
                    ? formatDate(oldestOpenIssue.first_seen_at)
                    : "Tidak ada masalah terbuka"}
                </p>
              </article>
            </div>
          </div>
        </section>

        <section id="manual-run" className="mt-6 scroll-mt-24">
          <form
            action={runReconciliationAction}
            className="rounded-2xl border border-emerald-400/20 bg-emerald-400/[0.055] p-5 sm:p-6"
          >
            <input
              type="hidden"
              name="idempotencyKey"
              value={`reconciliation:admin-ui:${randomUUID()}`}
            />

            <div className="flex flex-col gap-5 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <p className="text-lg font-semibold text-white">
                  Periksa konsistensi seluruh organisasi
                </p>
                <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-300">
                  Jalankan semua pemeriksaan untuk mencari perbedaan antara
                  nilai yang seharusnya dan nilai yang tercatat saat ini.
                </p>
              </div>

              <button className="primary-button shrink-0" type="submit">
                Periksa konsistensi stok
              </button>
            </div>

            <details className="mt-5 border-t border-emerald-400/15 pt-5">
              <summary className="cursor-pointer text-sm font-semibold text-emerald-200">
                Atur pemeriksaan lanjutan
              </summary>
              <p className="mt-2 text-sm text-slate-400">
                Semua pemeriksaan dipilih secara default. Nonaktifkan hanya
                ketika sedang menyelidiki kelompok masalah tertentu.
              </p>

              <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                {reconciliationChecks.map((check) => (
                  <label
                    key={check.code}
                    className="flex cursor-pointer items-start gap-3 rounded-xl border border-white/10 bg-slate-950/45 p-4 text-sm transition hover:border-emerald-400/30"
                  >
                    <input
                      className="mt-1 h-4 w-4"
                      type="checkbox"
                      name="checkCodes"
                      value={check.code}
                      defaultChecked
                    />
                    <span>
                      <span className="block font-medium text-slate-100">
                        {check.label}
                      </span>
                      <span className="mt-1 block text-xs leading-5 text-slate-500">
                        {check.description}
                      </span>
                      <span className="mt-2 block break-all font-mono text-[10px] text-slate-600">
                        {check.code}
                      </span>
                    </span>
                  </label>
                ))}
              </div>
            </details>
          </form>
        </section>

        <section id="issues" className="mt-10 scroll-mt-24">
          <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="section-kicker">Masalah yang ditemukan</p>
              <h2 className="section-title">
                Lihat selisih dan telusuri sumbernya.
              </h2>
            </div>
            <p className="text-sm text-slate-500">
              {formatNumber(filteredIssues.length)} dari {formatNumber(issues.length)} temuan
            </p>
          </div>

          <form className="panel-card mb-4">
            <div className="grid gap-4 lg:grid-cols-[1.5fr_0.8fr_0.8fr_1fr_auto]">
              <label className="field-label">
                Cari
                <input
                  name="q"
                  defaultValue={query}
                  placeholder="SKU, batch, order, retur, atau sumber..."
                />
              </label>

              <label className="field-label">
                Status temuan
                <select name="status" defaultValue={statusFilter}>
                  <option value="ALL">Semua status</option>
                  <option value="OPEN">Perlu diperiksa</option>
                  <option value="RESOLVED">Selesai</option>
                </select>
              </label>

              <label className="field-label">
                Tingkat masalah
                <select name="severity" defaultValue={severityFilter}>
                  <option value="ALL">Semua tingkat</option>
                  <option value="CRITICAL">Kritis</option>
                  <option value="HIGH">Tinggi</option>
                  <option value="MEDIUM">Sedang</option>
                  <option value="LOW">Rendah</option>
                  <option value="INFO">Informasi</option>
                </select>
              </label>

              <label className="field-label">
                Jenis pemeriksaan
                <select name="checkCode" defaultValue={checkCodeFilter}>
                  <option value="ALL">Semua jenis</option>
                  {availableCheckCodes.map((checkCode) => (
                    <option key={checkCode} value={checkCode}>
                      {checkDefinition(checkCode).label}
                    </option>
                  ))}
                </select>
              </label>

              <div className="flex items-end">
                <button className="primary-button w-full" type="submit">
                  Terapkan filter
                </button>
              </div>
            </div>

            {activeFilters.length > 0 ? (
              <div className="mt-4 flex flex-wrap items-center gap-2 border-t border-white/10 pt-4">
                {activeFilters.map((filter) => (
                  <span
                    key={filter}
                    className="rounded-full border border-white/10 bg-white/[0.04] px-3 py-1.5 text-xs text-slate-300"
                  >
                    {filter}
                  </span>
                ))}
                <Link
                  href="/reconciliation#issues"
                  className="text-xs font-semibold text-emerald-300 hover:text-emerald-200"
                >
                  Hapus semua filter
                </Link>
              </div>
            ) : null}
          </form>

          {filteredIssues.length === 0 ? (
            <div className="rounded-2xl border border-emerald-400/20 bg-emerald-400/[0.045] p-8 text-center">
              <p className="text-lg font-semibold text-white">
                Tidak ada masalah pada tampilan ini.
              </p>
              <p className="mx-auto mt-2 max-w-2xl text-sm leading-6 text-slate-400">
                Bila pemeriksaan terakhir berstatus Aman, ledger, projection,
                reservasi, shipment, dan retur konsisten pada boundary tersebut.
              </p>
            </div>
          ) : (
            <>
              <div className="hidden overflow-hidden rounded-2xl border border-white/10 bg-white/[0.02] md:block">
                <div className="max-h-[560px] overflow-auto">
                  <table className="min-w-[1120px] text-left text-sm">
                    <thead className="sticky top-0 z-10 border-b border-white/10 bg-slate-950/95 backdrop-blur">
                      <tr>
                        <th className="px-4 py-3">Sumber</th>
                        <th className="px-4 py-3">Kelompok</th>
                        <th className="px-4 py-3 text-right">Seharusnya</th>
                        <th className="px-4 py-3 text-right">Tercatat</th>
                        <th className="px-4 py-3">Selisih</th>
                        <th className="px-4 py-3">Tingkat</th>
                        <th className="px-4 py-3">Status</th>
                        <th className="px-4 py-3">Terakhir</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-white/10">
                      {filteredIssues.map((issue) => {
                        const definition = checkDefinition(issue.check_code);
                        const entity = issueEntityLabel(issue);
                        const difference = differencePresentation(
                          issue.difference_value,
                        );

                        return (
                          <tr
                            key={issue.issue_id}
                            className={
                              selectedIssue?.issue_id === issue.issue_id
                                ? "bg-emerald-400/[0.07]"
                                : ""
                            }
                          >
                            <td className="px-4 py-4">
                              <Link
                                href={reconciliationHref(
                                  filterState,
                                  { issueId: issue.issue_id },
                                  "issues",
                                )}
                                className="font-medium text-white hover:text-emerald-300"
                              >
                                {entity.primary}
                              </Link>
                              <p className="mt-1 max-w-[260px] truncate text-xs text-slate-500">
                                {entity.secondary}
                              </p>
                            </td>
                            <td className="px-4 py-4">
                              <p className="text-slate-200">{definition.category}</p>
                              <p className="mt-1 text-xs text-slate-500">
                                {definition.label}
                              </p>
                            </td>
                            <td className="px-4 py-4 text-right font-mono text-xs text-slate-300">
                              {compactValue(issue.expected_value, 34)}
                            </td>
                            <td className="px-4 py-4 text-right font-mono text-xs text-slate-300">
                              {compactValue(issue.actual_value, 34)}
                            </td>
                            <td className="px-4 py-4">
                              <Pill
                                label={difference.label}
                                tone={difference.tone}
                              />
                            </td>
                            <td className="px-4 py-4">
                              <Pill
                                label={severityLabel(issue.severity_code)}
                                tone={severityTone(issue.severity_code)}
                              />
                            </td>
                            <td className="px-4 py-4">
                              <Pill
                                label={issueStatusLabel(issue.status_code)}
                                tone={issueTone(issue.status_code)}
                              />
                            </td>
                            <td className="px-4 py-4 text-xs text-slate-400">
                              {formatDate(issue.last_seen_at)}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </div>

              <div className="space-y-3 md:hidden">
                {filteredIssues.map((issue) => {
                  const definition = checkDefinition(issue.check_code);
                  const entity = issueEntityLabel(issue);
                  const difference = differencePresentation(
                    issue.difference_value,
                  );

                  return (
                    <Link
                      key={issue.issue_id}
                      href={reconciliationHref(
                        filterState,
                        { issueId: issue.issue_id },
                        "issues",
                      )}
                      className={`block rounded-2xl border p-4 ${
                        selectedIssue?.issue_id === issue.issue_id
                          ? "border-emerald-400/30 bg-emerald-400/[0.07]"
                          : "border-white/10 bg-white/[0.025]"
                      }`}
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="font-medium text-white">{entity.primary}</p>
                          <p className="mt-1 text-xs text-slate-500">
                            {definition.category} / {definition.label}
                          </p>
                        </div>
                        <Pill
                          label={severityLabel(issue.severity_code)}
                          tone={severityTone(issue.severity_code)}
                        />
                      </div>

                      <div className="mt-4 grid grid-cols-3 gap-2 text-center">
                        <div className="rounded-xl border border-white/10 p-3">
                          <p className="text-[10px] uppercase tracking-wide text-slate-500">
                            Seharusnya
                          </p>
                          <p className="mt-2 font-mono text-xs text-slate-200">
                            {compactValue(issue.expected_value, 24)}
                          </p>
                        </div>
                        <div className="rounded-xl border border-white/10 p-3">
                          <p className="text-[10px] uppercase tracking-wide text-slate-500">
                            Selisih
                          </p>
                          <p className="mt-2 text-xs text-slate-200">
                            {difference.label}
                          </p>
                        </div>
                        <div className="rounded-xl border border-white/10 p-3">
                          <p className="text-[10px] uppercase tracking-wide text-slate-500">
                            Tercatat
                          </p>
                          <p className="mt-2 font-mono text-xs text-slate-200">
                            {compactValue(issue.actual_value, 24)}
                          </p>
                        </div>
                      </div>
                    </Link>
                  );
                })}
              </div>
            </>
          )}

          {selectedIssue ? (
            <article className="mt-5 overflow-hidden rounded-2xl border border-white/10 bg-white/[0.025]">
              <div className="border-b border-white/10 p-5 sm:p-6">
                <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                  <div>
                    <p className="section-kicker">Detail masalah</p>
                    <h3 className="mt-2 text-2xl font-semibold text-white">
                      {issueEntityLabel(selectedIssue).primary}
                    </h3>
                    <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
                      {checkDefinition(selectedIssue.check_code).description}
                    </p>
                  </div>

                  <div className="flex flex-wrap gap-2">
                    <Pill
                      label={severityLabel(selectedIssue.severity_code)}
                      tone={severityTone(selectedIssue.severity_code)}
                    />
                    <Pill
                      label={issueStatusLabel(selectedIssue.status_code)}
                      tone={issueTone(selectedIssue.status_code)}
                    />
                  </div>
                </div>
              </div>

              <div className="p-5 sm:p-6">
                <div className="grid gap-3 lg:grid-cols-[1fr_0.72fr_1fr]">
                  <div className="min-w-0 rounded-2xl border border-sky-400/20 bg-sky-400/[0.055] p-5">
                    <p className="text-xs font-semibold uppercase tracking-[0.16em] text-sky-300">
                      Nilai yang seharusnya
                    </p>
                    <pre className="mt-4 overflow-x-auto whitespace-pre-wrap break-words font-mono text-sm leading-6 text-slate-100">
                      {formatJson(selectedIssue.expected_value)}
                    </pre>
                  </div>

                  <div className="min-w-0 rounded-2xl border border-amber-400/20 bg-amber-400/[0.055] p-5 text-center">
                    <p className="text-xs font-semibold uppercase tracking-[0.16em] text-amber-300">
                      Selisih
                    </p>
                    <p className="mt-4 text-2xl font-semibold text-white">
                      {
                        differencePresentation(selectedIssue.difference_value)
                          .label
                      }
                    </p>
                    <pre className="mt-3 overflow-x-auto whitespace-pre-wrap break-words font-mono text-xs leading-6 text-slate-300">
                      {formatJson(selectedIssue.difference_value)}
                    </pre>
                  </div>

                  <div className="min-w-0 rounded-2xl border border-violet-400/20 bg-violet-400/[0.055] p-5">
                    <p className="text-xs font-semibold uppercase tracking-[0.16em] text-violet-300">
                      Nilai yang tercatat
                    </p>
                    <pre className="mt-4 overflow-x-auto whitespace-pre-wrap break-words font-mono text-sm leading-6 text-slate-100">
                      {formatJson(selectedIssue.actual_value)}
                    </pre>
                  </div>
                </div>

                <div className="mt-5 grid gap-4 lg:grid-cols-3">
                  <div className="rounded-xl border border-white/10 p-4">
                    <p className="text-xs text-slate-500">Kelompok masalah</p>
                    <p className="mt-2 text-sm font-medium text-white">
                      {checkDefinition(selectedIssue.check_code).category}
                    </p>
                    <p className="mt-1 text-xs text-slate-400">
                      {checkDefinition(selectedIssue.check_code).label}
                    </p>
                  </div>
                  <div className="rounded-xl border border-white/10 p-4">
                    <p className="text-xs text-slate-500">Sumber data</p>
                    <p className="mt-2 break-all text-sm text-white">
                      {selectedIssue.source_type_code ?? "Tidak ada tipe sumber"}
                    </p>
                    <p className="mt-1 break-all text-xs text-slate-400">
                      {selectedIssue.source_ref ?? "Tidak ada referensi sumber"}
                    </p>
                  </div>
                  <div className="rounded-xl border border-white/10 p-4">
                    <p className="text-xs text-slate-500">Riwayat kemunculan</p>
                    <p className="mt-2 text-sm text-white">
                      Muncul {formatNumber(selectedIssue.recurrence_count)} kali
                    </p>
                    <p className="mt-1 text-xs text-slate-400">
                      {formatDate(selectedIssue.first_seen_at)} sampai{" "}
                      {formatDate(selectedIssue.last_seen_at)}
                    </p>
                  </div>
                </div>

                {selectedIssue.status_code === "RESOLVED" ? (
                  <div className="mt-5 rounded-2xl border border-emerald-400/20 bg-emerald-400/[0.055] p-5">
                    <p className="font-medium text-emerald-100">
                      {selectedIssue.resolution_code ?? "Masalah selesai"}
                    </p>
                    <p className="mt-2 text-sm text-slate-300">
                      {selectedIssue.resolution_note ?? "Tidak ada catatan penyelesaian."}
                    </p>
                    <p className="mt-2 text-xs text-slate-500">
                      {formatDate(selectedIssue.resolved_at)}
                    </p>
                  </div>
                ) : null}

                <div className="mt-7">
                  <div className="flex items-end justify-between gap-4">
                    <div>
                      <p className="section-kicker">Bukti pemeriksaan</p>
                      <h4 className="mt-1 text-lg font-semibold text-white">
                        {formatNumber(selectedEvidence.length)} snapshot
                      </h4>
                    </div>
                  </div>

                  <div className="mt-4 space-y-3">
                    {selectedEvidence.length === 0 ? (
                      <div className="rounded-xl border border-white/10 p-4 text-sm text-slate-400">
                        Belum ada evidence tersimpan untuk masalah ini.
                      </div>
                    ) : (
                      selectedEvidence.map((item) => (
                        <article
                          key={item.evidence_id}
                          className="rounded-2xl border border-white/10 bg-slate-950/55 p-4"
                        >
                          <div className="flex flex-wrap items-start justify-between gap-3">
                            <div>
                              <p className="text-sm font-medium text-white">
                                Snapshot #{item.evidence_no}
                              </p>
                              <p className="mt-1 text-xs text-slate-500">
                                {formatDate(item.created_at)}
                              </p>
                            </div>
                            <Pill label={item.evidence_type_code} tone="neutral" />
                          </div>

                          <div className="mt-4 grid gap-3 lg:grid-cols-2">
                            <div className="min-w-0 rounded-xl border border-white/10 p-3">
                              <p className="text-xs uppercase tracking-wide text-slate-500">
                                Detail
                              </p>
                              <pre className="mt-2 whitespace-pre-wrap break-words font-mono text-xs leading-6 text-slate-300">
                                {formatJson(item.detail)}
                              </pre>
                            </div>
                            <div className="min-w-0 rounded-xl border border-white/10 p-3">
                              <p className="text-xs uppercase tracking-wide text-slate-500">
                                Selisih
                              </p>
                              <pre className="mt-2 whitespace-pre-wrap break-words font-mono text-xs leading-6 text-slate-300">
                                {formatJson(item.difference_value)}
                              </pre>
                            </div>
                          </div>
                        </article>
                      ))
                    )}
                  </div>
                </div>

                <details className="mt-6 rounded-2xl border border-white/10 bg-slate-950/55 p-4">
                  <summary className="cursor-pointer text-sm font-semibold text-slate-200">
                    Lihat detail teknis dan audit
                  </summary>
                  <div className="mt-4 grid gap-4 lg:grid-cols-2">
                    <div>
                      <p className="text-xs uppercase tracking-wide text-slate-500">
                        Check code
                      </p>
                      <p className="mt-2 break-all font-mono text-xs text-slate-300">
                        {selectedIssue.check_code}
                      </p>
                    </div>
                    <div>
                      <p className="text-xs uppercase tracking-wide text-slate-500">
                        Rule version
                      </p>
                      <p className="mt-2 break-all font-mono text-xs text-slate-300">
                        {selectedIssue.rule_version}
                      </p>
                    </div>
                    <div>
                      <p className="text-xs uppercase tracking-wide text-slate-500">
                        Fingerprint
                      </p>
                      <p className="mt-2 break-all font-mono text-xs text-slate-300">
                        {selectedIssue.fingerprint}
                      </p>
                    </div>
                    <div>
                      <p className="text-xs uppercase tracking-wide text-slate-500">
                        Entity type
                      </p>
                      <p className="mt-2 break-all font-mono text-xs text-slate-300">
                        {selectedIssue.entity_type_code}
                      </p>
                    </div>
                    <div className="lg:col-span-2">
                      <p className="text-xs uppercase tracking-wide text-slate-500">
                        Entity key
                      </p>
                      <pre className="mt-2 overflow-x-auto whitespace-pre-wrap break-words font-mono text-xs leading-6 text-slate-300">
                        {formatJson(selectedIssue.entity_key)}
                      </pre>
                    </div>
                  </div>
                </details>
              </div>
            </article>
          ) : null}
        </section>

        <section id="runs" className="mt-10 scroll-mt-24">
          <div className="mb-5">
            <p className="section-kicker">Riwayat pemeriksaan</p>
            <h2 className="section-title">
              Lihat kapan pemeriksaan dijalankan dan apa hasilnya.
            </h2>
          </div>

          {requestedRunMissing ? (
            <div className="mb-5 rounded-2xl border border-rose-400/25 bg-rose-400/[0.055] p-5">
              <p className="font-semibold text-rose-100">
                Reconciliation run tidak ditemukan.
              </p>
              <p className="mt-2 text-sm leading-6 text-slate-400">
                Run ID{" "}
                <span className="break-all font-mono text-slate-300">
                  {params.runId}
                </span>{" "}
                tidak tersedia untuk organisasi Admin ini. Sistem tidak memilih
                run terbaru sebagai pengganti.
              </p>
            </div>
          ) : null}

          <div className="grid gap-5 xl:grid-cols-[1.15fr_0.85fr]">
            <div className="overflow-hidden rounded-2xl border border-white/10 bg-white/[0.02]">
              {visibleRuns.length === 0 ? (
                <div className="p-8 text-center text-sm text-slate-400">
                  Belum ada riwayat pemeriksaan.
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="min-w-[900px] text-left text-sm">
                    <thead className="border-b border-white/10 bg-white/[0.025]">
                      <tr>
                        <th className="px-5 py-4">Pemeriksaan</th>
                        <th className="px-5 py-4">Status</th>
                        <th className="px-5 py-4">Boundary ledger</th>
                        <th className="px-5 py-4 text-right">Check</th>
                        <th className="px-5 py-4 text-right">Masalah</th>
                        <th className="px-5 py-4">Selesai</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-white/10">
                      {visibleRuns.map((run) => {
                        const issueCount =
                          summaryNumber(run.summary, "issueCount") ?? 0;
                        const checkCount =
                          summaryNumber(run.summary, "checkCount") ??
                          run.check_codes.length;

                        return (
                          <tr
                            key={run.run_id}
                            className={
                              selectedRun?.run_id === run.run_id
                                ? "bg-emerald-400/[0.07]"
                                : ""
                            }
                          >
                            <td className="px-5 py-4">
                              <Link
                                className="font-medium text-white hover:text-emerald-300"
                                href={reconciliationHref(
                                  filterState,
                                  { runId: run.run_id },
                                  "runs",
                                )}
                              >
                                {run.run_no}
                              </Link>
                              <p className="mt-1 text-xs text-slate-500">
                                {run.run_type_code} / {run.trigger_code}
                              </p>
                            </td>
                            <td className="px-5 py-4">
                              <Pill
                                label={runLabel(run.status_code)}
                                tone={runTone(run.status_code)}
                              />
                            </td>
                            <td className="px-5 py-4 font-mono text-xs text-slate-300">
                              {run.ledger_seq_from} - {run.ledger_seq_to}
                            </td>
                            <td className="px-5 py-4 text-right text-slate-300">
                              {formatNumber(checkCount)}
                            </td>
                            <td className="px-5 py-4 text-right text-slate-300">
                              {formatNumber(issueCount)}
                            </td>
                            <td className="px-5 py-4 text-xs text-slate-400">
                              {formatDate(run.completed_at)}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>

            <div className="panel-card">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="section-kicker">Hasil yang dipilih</p>
                  <h3 className="mt-2 text-xl font-semibold text-white">
                    {requestedRunMissing
                      ? "Run tidak ditemukan"
                      : selectedRun?.run_no ?? "Belum ada pemeriksaan"}
                  </h3>
                </div>
                {selectedRun ? (
                  <Pill
                    label={runLabel(selectedRun.status_code)}
                    tone={runTone(selectedRun.status_code)}
                  />
                ) : null}
              </div>

              {selectedRun ? (
                <>
                  <dl className="mt-5 grid gap-3 text-sm sm:grid-cols-2">
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Rule set</dt>
                      <dd className="mt-1 font-mono text-xs text-slate-200">
                        {selectedRun.rule_set_version}
                      </dd>
                    </div>
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Boundary ledger</dt>
                      <dd className="mt-1 font-mono text-xs text-slate-200">
                        {selectedRun.ledger_seq_from} -{" "}
                        {selectedRun.ledger_seq_to}
                      </dd>
                    </div>
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Mulai</dt>
                      <dd className="mt-1 text-slate-200">
                        {formatDate(selectedRun.started_at)}
                      </dd>
                    </div>
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Selesai</dt>
                      <dd className="mt-1 text-slate-200">
                        {formatDate(selectedRun.completed_at)}
                      </dd>
                    </div>
                  </dl>

                  <div className="mt-5 space-y-3">
                    {selectedChecks.length === 0 ? (
                      <p className="text-sm text-slate-400">
                        Belum ada hasil check untuk pemeriksaan ini.
                      </p>
                    ) : (
                      selectedChecks.map((check) => {
                        const definition = checkDefinition(check.check_code);

                        return (
                          <article
                            key={check.run_check_id}
                            className="rounded-2xl border border-white/10 bg-white/[0.025] p-4"
                          >
                            <div className="flex flex-wrap items-start justify-between gap-3">
                              <div>
                                <p className="font-medium text-white">
                                  {definition.label}
                                </p>
                                <p className="mt-1 text-xs text-slate-500">
                                  {definition.category} / diperiksa{" "}
                                  {formatNumber(check.checked_count)} / masalah{" "}
                                  {formatNumber(check.issue_count)}
                                </p>
                                <p className="mt-2 break-all font-mono text-[10px] text-slate-600">
                                  {check.check_code}
                                </p>
                              </div>
                              <Pill
                                label={runLabel(check.status_code)}
                                tone={runTone(check.status_code)}
                              />
                            </div>

                            {check.error_code ? (
                              <p className="mt-3 rounded-xl border border-rose-400/20 bg-rose-400/10 p-3 font-mono text-xs text-rose-100">
                                {check.error_code}
                              </p>
                            ) : null}
                          </article>
                        );
                      })
                    )}
                  </div>
                </>
              ) : (
                <p className="mt-5 text-sm text-slate-400">
                  {requestedRunMissing
                    ? "Tidak ada hasil check yang ditampilkan untuk run yang tidak ditemukan."
                    : "Jalankan pemeriksaan pertama untuk melihat hasil per kelompok."}
                </p>
              )}
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
