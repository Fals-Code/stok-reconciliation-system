import { randomUUID } from "node:crypto";

import Link from "next/link";

import { runReconciliationAction } from "@/app/actions";
import {
  getReconciliationData,
  type ReconciliationIssue,
  type ReconciliationRun,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

const numberFormatter = new Intl.NumberFormat("id-ID");

const reconciliationChecks = [
  {
    code: "LEDGER_BATCH_PROJECTION",
    label: "Ledger vs batch projection",
  },
  {
    code: "BATCH_PRODUCT_PROJECTION",
    label: "Batch vs product projection",
  },
  {
    code: "RESERVATION_CONSISTENCY",
    label: "Reservation consistency",
  },
  {
    code: "MARKETPLACE_ALLOCATION_CONSISTENCY",
    label: "Marketplace allocation vs outbound",
  },
  {
    code: "RETURN_RECEIPT_QUARANTINE",
    label: "Return receipt vs quarantine",
  },
  {
    code: "RETURN_INSPECTION_TRANSFER",
    label: "Return inspection net-zero",
  },
  {
    code: "DUPLICATE_SOURCE_EFFECT",
    label: "Duplicate source effect",
  },
  {
    code: "IMPOSSIBLE_PROJECTION_STATE",
    label: "Impossible projection state",
  },
] as const;

type PillTone = "success" | "warning" | "danger" | "neutral";

function formatNumber(value: number) {
  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null, includeTime = true) {
  if (!value) return "—";

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
  if (value === null || value === undefined) return "—";

  if (typeof value === "string") {
    return value;
  }

  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
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
  if (severity === "LOW" || severity === "INFO") return "neutral";
  return "neutral";
}

function runTone(status: string): PillTone {
  if (status === "SUCCEEDED") return "success";
  if (status === "FAILED" || status === "ERROR") return "danger";
  if (status === "RUNNING" || status === "PENDING") return "warning";
  return "neutral";
}

function issueTone(status: string): PillTone {
  return status === "RESOLVED" ? "success" : "warning";
}

function integrityTone(value: string | null): PillTone {
  if (value === "CLEAN") return "success";
  if (value === "ISSUES_FOUND") return "danger";
  return "neutral";
}

function Pill({ label, tone }: { label: string; tone: PillTone }) {
  const tones = {
    success: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
    warning: "border-amber-400/20 bg-amber-400/10 text-amber-200",
    danger: "border-rose-400/20 bg-rose-400/10 text-rose-200",
    neutral: "border-white/10 bg-white/[0.04] text-slate-300",
  };

  return (
    <span
      className={`inline-flex rounded-full border px-2.5 py-1 text-xs ${tones[tone]}`}
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

function runHref(
  run: ReconciliationRun,
  filters: {
    status: string;
    severity: string;
    checkCode: string;
    issueId: string | null;
  },
) {
  const params = new URLSearchParams();

  if (filters.status !== "ALL") params.set("status", filters.status);
  if (filters.severity !== "ALL") params.set("severity", filters.severity);
  if (filters.checkCode !== "ALL") params.set("checkCode", filters.checkCode);
  if (filters.issueId) params.set("issueId", filters.issueId);

  params.set("runId", run.run_id);
  return `/reconciliation?${params.toString()}#runs`;
}

function issueHref(
  issueId: string,
  filters: {
    status: string;
    severity: string;
    checkCode: string;
    runId: string | null;
  },
) {
  const params = new URLSearchParams();

  if (filters.status !== "ALL") params.set("status", filters.status);
  if (filters.severity !== "ALL") params.set("severity", filters.severity);
  if (filters.checkCode !== "ALL") params.set("checkCode", filters.checkCode);
  if (filters.runId) params.set("runId", filters.runId);

  params.set("issueId", issueId);
  return `/reconciliation?${params.toString()}#issues`;
}

export default async function ReconciliationPage({
  searchParams,
}: {
  searchParams: Promise<{
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

  try {
    data = await getReconciliationData();
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

    return true;
  });

  const selectedRun =
    runs.find((run) => run.run_id === params.runId) ?? runs[0] ?? null;
  const selectedChecks = selectedRun
    ? checks
        .filter((check) => check.run_id === selectedRun.run_id)
        .sort((left, right) => left.check_code.localeCompare(right.check_code))
    : [];

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

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <header className="sticky top-0 z-20 border-b border-white/10 bg-slate-950/90 backdrop-blur">
        <div className="mx-auto flex max-w-[1500px] items-center justify-between gap-5 px-5 py-4 lg:px-8">
          <div>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-emerald-300">
              GlowLab Reconciliation
            </p>
            <p className="mt-1 text-sm text-slate-400">
              Explain mismatches without mutating stock
            </p>
          </div>

          <nav className="hidden items-center gap-2 text-sm md:flex">
            <a className="nav-link" href="#overview">
              Overview
            </a>
            <a className="nav-link" href="#manual-run">
              Manual run
            </a>
            <a className="nav-link" href="#runs">
              Runs
            </a>
            <a className="nav-link" href="#issues">
              Issues
            </a>
          </nav>

          <div className="flex items-center gap-2">
            <Link className="nav-link border border-white/10" href="/marketplace">
              Marketplace
            </Link>
            <Link className="nav-link border border-white/10" href="/returns">
              Returns
            </Link>
            <Link className="nav-link border border-white/10" href="/">
              Dashboard
            </Link>
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section id="overview" className="scroll-mt-24">
          <p className="section-kicker">Inventory integrity</p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
            Periksa konsistensi, simpan bukti, jangan sentuh ledger lama.
          </h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
            Rekonsiliasi membandingkan ledger, projection, reservasi, alokasi,
            dan retur pada boundary yang eksplisit. Hasilnya tersimpan sebagai
            run, check, issue, dan evidence tanpa mengubah quantity stok.
          </p>

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <article className="metric-card">
              <p className="text-sm text-slate-400">Latest run</p>
              <p className="mt-3 text-2xl font-semibold text-white">
                {latestRun?.run_no ?? "Belum ada"}
              </p>
              <p className="mt-2 text-xs text-slate-500">
                {latestRun
                  ? formatDate(latestRun.completed_at ?? latestRun.started_at)
                  : "Jalankan rekonsiliasi pertama"}
              </p>
            </article>

            <article className="metric-card">
              <p className="text-sm text-slate-400">Integrity status</p>
              <div className="mt-3">
                <Pill
                  label={latestIntegrityStatus ?? "NO DATA"}
                  tone={integrityTone(latestIntegrityStatus)}
                />
              </div>
              <p className="mt-3 text-xs text-slate-500">
                Run status: {latestRun?.status_code ?? "—"}
              </p>
            </article>

            <article className="metric-card">
              <p className="text-sm text-slate-400">Open issues</p>
              <p className="mt-3 text-3xl font-semibold text-white">
                {formatNumber(openIssues.length)}
              </p>
              <p className="mt-2 text-xs text-slate-500">
                Critical {openCritical} · High {openHigh}
              </p>
            </article>

            <article className="metric-card">
              <p className="text-sm text-slate-400">Affected products</p>
              <p className="mt-3 text-3xl font-semibold text-white">
                {formatNumber(affectedProducts)}
              </p>
              <p className="mt-2 text-xs text-slate-500">
                Oldest open:{" "}
                {oldestOpenIssue
                  ? formatDate(oldestOpenIssue.first_seen_at)
                  : "tidak ada"}
              </p>
            </article>
          </div>
        </section>

        <section id="manual-run" className="mt-10 scroll-mt-24">
          <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="section-kicker">Manual reconciliation</p>
              <h2 className="section-title">
                Jalankan check pada seluruh organisasi.
              </h2>
            </div>
            <Pill label="core-integrity-v7" tone="neutral" />
          </div>

          {params.success ? (
            <div className="mb-5 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-200">
              {params.success}
            </div>
          ) : null}

          {params.error ? (
            <div className="mb-5 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-200">
              {params.error}
            </div>
          ) : null}

          <form action={runReconciliationAction} className="panel-card">
            <input
              type="hidden"
              name="idempotencyKey"
              value={`reconciliation:admin-ui:${randomUUID()}`}
            />
            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
              {reconciliationChecks.map((check) => (
                <label
                  key={check.code}
                  className="flex cursor-pointer items-start gap-3 rounded-2xl border border-white/10 bg-white/[0.025] p-4 text-sm transition hover:border-emerald-400/30"
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
                    <span className="mt-1 block break-all font-mono text-[11px] text-slate-500">
                      {check.code}
                    </span>
                  </span>
                </label>
              ))}
            </div>

            <div className="mt-6 flex flex-col gap-3 border-t border-white/10 pt-5 sm:flex-row sm:items-center sm:justify-between">
              <p className="max-w-3xl text-sm leading-6 text-slate-400">
                Scope saat ini selalu seluruh organisasi. Run hanya membaca,
                membandingkan, dan menyimpan hasil. Tidak ada ledger entry atau
                stock projection yang diubah.
              </p>
              <button className="primary-button shrink-0" type="submit">
                Run reconciliation
              </button>
            </div>
          </form>
        </section>

        <section id="runs" className="mt-10 scroll-mt-24">
          <div className="mb-5">
            <p className="section-kicker">Run history</p>
            <h2 className="section-title">Boundary dan hasil setiap eksekusi.</h2>
          </div>

          <div className="grid gap-5 xl:grid-cols-[1.15fr_0.85fr]">
            <div className="panel-card overflow-hidden p-0">
              {runs.length === 0 ? (
                <div className="p-6 text-sm text-slate-400">
                  Belum ada reconciliation run.
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="min-w-[880px] text-left text-sm">
                    <thead className="border-b border-white/10 bg-white/[0.025] text-xs uppercase tracking-wide text-slate-500">
                      <tr>
                        <th className="px-5 py-4">Run</th>
                        <th className="px-5 py-4">Status</th>
                        <th className="px-5 py-4">Type</th>
                        <th className="px-5 py-4">Boundary</th>
                        <th className="px-5 py-4">Checks</th>
                        <th className="px-5 py-4">Issues</th>
                        <th className="px-5 py-4">Completed</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-white/10">
                      {runs.map((run) => {
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
                                ? "bg-emerald-400/[0.06]"
                                : "hover:bg-white/[0.025]"
                            }
                          >
                            <td className="px-5 py-4">
                              <Link
                                className="font-medium text-white hover:text-emerald-300"
                                href={runHref(run, {
                                  status: statusFilter,
                                  severity: severityFilter,
                                  checkCode: checkCodeFilter,
                                  issueId: selectedIssue?.issue_id ?? null,
                                })}
                              >
                                {run.run_no}
                              </Link>
                              <p className="mt-1 font-mono text-[11px] text-slate-500">
                                {run.rule_set_version}
                              </p>
                            </td>
                            <td className="px-5 py-4">
                              <Pill
                                label={run.status_code}
                                tone={runTone(run.status_code)}
                              />
                            </td>
                            <td className="px-5 py-4 text-slate-300">
                              {run.run_type_code}
                              <p className="mt-1 text-xs text-slate-500">
                                {run.trigger_code}
                              </p>
                            </td>
                            <td className="px-5 py-4 font-mono text-xs text-slate-300">
                              {run.ledger_seq_from}-{run.ledger_seq_to}
                            </td>
                            <td className="px-5 py-4 text-slate-300">
                              {formatNumber(checkCount)}
                            </td>
                            <td className="px-5 py-4 text-slate-300">
                              {formatNumber(issueCount)}
                            </td>
                            <td className="px-5 py-4 text-slate-400">
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
                  <p className="section-kicker">Selected run</p>
                  <h3 className="mt-2 text-xl font-semibold">
                    {selectedRun?.run_no ?? "Belum ada run"}
                  </h3>
                </div>
                {selectedRun ? (
                  <Pill
                    label={selectedRun.status_code}
                    tone={runTone(selectedRun.status_code)}
                  />
                ) : null}
              </div>

              {selectedRun ? (
                <>
                  <dl className="mt-5 grid gap-3 text-sm sm:grid-cols-2">
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Rule set</dt>
                      <dd className="mt-1 font-mono text-slate-200">
                        {selectedRun.rule_set_version}
                      </dd>
                    </div>
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Boundary</dt>
                      <dd className="mt-1 font-mono text-slate-200">
                        {selectedRun.ledger_seq_from}-
                        {selectedRun.ledger_seq_to}
                      </dd>
                    </div>
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Started</dt>
                      <dd className="mt-1 text-slate-200">
                        {formatDate(selectedRun.started_at)}
                      </dd>
                    </div>
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Completed</dt>
                      <dd className="mt-1 text-slate-200">
                        {formatDate(selectedRun.completed_at)}
                      </dd>
                    </div>
                  </dl>

                  <div className="mt-5 space-y-3">
                    {selectedChecks.length === 0 ? (
                      <p className="text-sm text-slate-400">
                        Belum ada hasil check untuk run ini.
                      </p>
                    ) : (
                      selectedChecks.map((check) => (
                        <article
                          key={check.run_check_id}
                          className="rounded-2xl border border-white/10 bg-white/[0.025] p-4"
                        >
                          <div className="flex flex-wrap items-start justify-between gap-3">
                            <div>
                              <p className="break-all font-mono text-xs text-slate-300">
                                {check.check_code}
                              </p>
                              <p className="mt-2 text-xs text-slate-500">
                                Rule {check.rule_version} · checked{" "}
                                {formatNumber(check.checked_count)} · issues{" "}
                                {formatNumber(check.issue_count)}
                              </p>
                            </div>
                            <Pill
                              label={check.status_code}
                              tone={runTone(check.status_code)}
                            />
                          </div>
                          {check.error_code ? (
                            <p className="mt-3 rounded-xl border border-rose-400/20 bg-rose-400/10 p-3 font-mono text-xs text-rose-200">
                              {check.error_code}
                            </p>
                          ) : null}
                        </article>
                      ))
                    )}
                  </div>
                </>
              ) : (
                <p className="mt-5 text-sm text-slate-400">
                  Jalankan rekonsiliasi untuk melihat detail check.
                </p>
              )}
            </div>
          </div>
        </section>

        <section id="issues" className="mt-10 scroll-mt-24">
          <div className="mb-5">
            <p className="section-kicker">Issue investigation</p>
            <h2 className="section-title">
              Filter temuan dan buka evidence yang tersimpan.
            </h2>
          </div>

          <form className="panel-card mb-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <label className="field-label">
              Status
              <select name="status" defaultValue={statusFilter}>
                <option value="ALL">Semua status</option>
                <option value="OPEN">Open</option>
                <option value="RESOLVED">Resolved</option>
              </select>
            </label>

            <label className="field-label">
              Severity
              <select name="severity" defaultValue={severityFilter}>
                {["ALL", "INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL"].map(
                  (severity) => (
                    <option key={severity} value={severity}>
                      {severity === "ALL" ? "Semua severity" : severity}
                    </option>
                  ),
                )}
              </select>
            </label>

            <label className="field-label">
              Check
              <select name="checkCode" defaultValue={checkCodeFilter}>
                <option value="ALL">Semua check</option>
                {availableCheckCodes.map((checkCode) => (
                  <option key={checkCode} value={checkCode}>
                    {checkCode}
                  </option>
                ))}
              </select>
            </label>

            <div className="flex items-end gap-3">
              {selectedRun ? (
                <input type="hidden" name="runId" value={selectedRun.run_id} />
              ) : null}
              <button className="primary-button w-full" type="submit">
                Terapkan filter
              </button>
            </div>
          </form>

          <div className="grid gap-5 xl:grid-cols-[0.9fr_1.1fr]">
            <div className="space-y-3">
              {filteredIssues.length === 0 ? (
                <div className="panel-card text-sm text-slate-400">
                  Tidak ada issue yang cocok dengan filter.
                </div>
              ) : (
                filteredIssues.map((issue) => (
                  <Link
                    key={issue.issue_id}
                    href={issueHref(issue.issue_id, {
                      status: statusFilter,
                      severity: severityFilter,
                      checkCode: checkCodeFilter,
                      runId: selectedRun?.run_id ?? null,
                    })}
                    className={`block rounded-2xl border p-4 transition ${
                      selectedIssue?.issue_id === issue.issue_id
                        ? "border-emerald-400/30 bg-emerald-400/[0.07]"
                        : "border-white/10 bg-white/[0.025] hover:border-white/20"
                    }`}
                  >
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <p className="break-all font-mono text-xs text-slate-300">
                          {issue.check_code}
                        </p>
                        <p className="mt-2 text-sm font-medium text-white">
                          {issue.entity_type_code}
                        </p>
                      </div>
                      <div className="flex flex-wrap gap-2">
                        <Pill
                          label={issue.severity_code}
                          tone={severityTone(issue.severity_code)}
                        />
                        <Pill
                          label={issue.status_code}
                          tone={issueTone(issue.status_code)}
                        />
                      </div>
                    </div>

                    <div className="mt-4 grid gap-2 text-xs text-slate-500 sm:grid-cols-2">
                      <p>First: {formatDate(issue.first_seen_at)}</p>
                      <p>Last: {formatDate(issue.last_seen_at)}</p>
                      <p>Recurrence: {formatNumber(issue.recurrence_count)}</p>
                      <p className="truncate">
                        Source: {issue.source_ref ?? "—"}
                      </p>
                    </div>
                  </Link>
                ))
              )}
            </div>

            <div className="panel-card min-w-0">
              {selectedIssue ? (
                <>
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="section-kicker">Selected issue</p>
                      <h3 className="mt-2 break-all text-xl font-semibold">
                        {selectedIssue.check_code}
                      </h3>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      <Pill
                        label={selectedIssue.severity_code}
                        tone={severityTone(selectedIssue.severity_code)}
                      />
                      <Pill
                        label={selectedIssue.status_code}
                        tone={issueTone(selectedIssue.status_code)}
                      />
                    </div>
                  </div>

                  <dl className="mt-5 grid gap-3 text-sm sm:grid-cols-2">
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Entity</dt>
                      <dd className="mt-1 text-slate-200">
                        {selectedIssue.entity_type_code}
                      </dd>
                    </div>
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Rule</dt>
                      <dd className="mt-1 font-mono text-slate-200">
                        {selectedIssue.rule_version}
                      </dd>
                    </div>
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Product</dt>
                      <dd className="mt-1 break-all font-mono text-xs text-slate-200">
                        {selectedIssue.product_id ?? "—"}
                      </dd>
                    </div>
                    <div className="rounded-xl border border-white/10 p-3">
                      <dt className="text-slate-500">Batch</dt>
                      <dd className="mt-1 break-all font-mono text-xs text-slate-200">
                        {selectedIssue.batch_id ?? "—"}
                      </dd>
                    </div>
                    <div className="rounded-xl border border-white/10 p-3 sm:col-span-2">
                      <dt className="text-slate-500">Source</dt>
                      <dd className="mt-1 break-all text-slate-200">
                        {selectedIssue.source_type_code ?? "—"} ·{" "}
                        {selectedIssue.source_ref ?? "—"}
                      </dd>
                    </div>
                  </dl>

                  <div className="mt-5 grid gap-4 xl:grid-cols-3">
                    {[
                      ["Expected", selectedIssue.expected_value],
                      ["Actual", selectedIssue.actual_value],
                      ["Difference", selectedIssue.difference_value],
                    ].map(([label, value]) => (
                      <div
                        key={String(label)}
                        className="min-w-0 rounded-2xl border border-white/10 bg-slate-950/60 p-4"
                      >
                        <p className="text-xs uppercase tracking-wide text-slate-500">
                          {String(label)}
                        </p>
                        <pre className="mt-3 overflow-x-auto whitespace-pre-wrap break-words font-mono text-xs leading-6 text-slate-300">
                          {formatJson(value)}
                        </pre>
                      </div>
                    ))}
                  </div>

                  <div className="mt-5 rounded-2xl border border-white/10 bg-slate-950/60 p-4">
                    <p className="text-xs uppercase tracking-wide text-slate-500">
                      Entity key
                    </p>
                    <pre className="mt-3 overflow-x-auto whitespace-pre-wrap break-words font-mono text-xs leading-6 text-slate-300">
                      {formatJson(selectedIssue.entity_key)}
                    </pre>
                  </div>

                  {selectedIssue.status_code === "RESOLVED" ? (
                    <div className="mt-5 rounded-2xl border border-emerald-400/20 bg-emerald-400/[0.06] p-4 text-sm">
                      <p className="font-medium text-emerald-200">
                        {selectedIssue.resolution_code ?? "RESOLVED"}
                      </p>
                      <p className="mt-2 text-slate-300">
                        {selectedIssue.resolution_note ?? "Tidak ada catatan."}
                      </p>
                      <p className="mt-2 text-xs text-slate-500">
                        {formatDate(selectedIssue.resolved_at)}
                      </p>
                    </div>
                  ) : null}

                  <div className="mt-7">
                    <div className="flex items-end justify-between gap-3">
                      <div>
                        <p className="section-kicker">Evidence timeline</p>
                        <h4 className="mt-1 text-lg font-semibold">
                          {formatNumber(selectedEvidence.length)} snapshot
                        </h4>
                      </div>
                      <p className="text-xs text-slate-500">
                        Fingerprint{" "}
                        <span className="font-mono">
                          {selectedIssue.fingerprint.slice(0, 12)}…
                        </span>
                      </p>
                    </div>

                    <div className="mt-4 space-y-3">
                      {selectedEvidence.length === 0 ? (
                        <p className="text-sm text-slate-400">
                          Evidence belum tersedia untuk issue ini.
                        </p>
                      ) : (
                        selectedEvidence.map((item) => (
                          <article
                            key={item.evidence_id}
                            className="rounded-2xl border border-white/10 bg-white/[0.025] p-4"
                          >
                            <div className="flex flex-wrap items-start justify-between gap-3">
                              <div>
                                <p className="break-all font-mono text-xs text-slate-300">
                                  {item.evidence_type_code}
                                </p>
                                <p className="mt-2 text-xs text-slate-500">
                                  Evidence #{item.evidence_no} ·{" "}
                                  {formatDate(item.created_at)}
                                </p>
                              </div>
                              <Pill label={item.entity_type_code} tone="neutral" />
                            </div>

                            <div className="mt-4 grid gap-3 xl:grid-cols-2">
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
                                  Difference
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
                </>
              ) : (
                <div className="text-sm text-slate-400">
                  Tidak ada issue untuk ditampilkan. Baseline bersih memang
                  kurang dramatis, tetapi jauh lebih sehat.
                </div>
              )}
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}