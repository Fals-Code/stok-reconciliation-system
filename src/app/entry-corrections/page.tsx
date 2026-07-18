import { randomUUID } from "node:crypto";
import Link from "next/link";

import PageSectionNav from "@/app/app-shell/page-section-nav";
import { reverseStockTransactionAction } from "@/app/entry-corrections/actions";
import {
  getEntryCorrectionData,
  previewStockTransactionReversal,
  type StockLedgerEntry,
  type StockReversalApplication,
  type StockReversalPreview,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

const SUPPORTED_SOURCE_TYPES = ["RECEIPT", "MANUAL_OUTBOUND"] as const;
const WORKLIST_TYPES = [...SUPPORTED_SOURCE_TYPES, "REVERSAL"] as const;

type WorklistType = (typeof WORKLIST_TYPES)[number];
type FilterType = "ALL" | WorklistType;

type SearchParams = {
  q?: string;
  type?: string;
  transactionId?: string;
  success?: string;
  error?: string;
  originalId?: string;
  reversalId?: string;
};

type FilterState = {
  q: string;
  type: FilterType;
  transactionId: string | null;
};

type TransactionGroup = {
  transactionId: string;
  transactionNo: string;
  transactionTypeCode: string;
  reasonCode: string;
  channelCode: string;
  sourceTypeCode: string;
  sourceRef: string;
  occurredAt: string;
  recordedAt: string;
  note: string | null;
  latestLedgerSeq: number;
  totalAbsoluteQuantity: number;
  lines: StockLedgerEntry[];
};

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number | null | undefined) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return "â€”";
  }

  return numberFormatter.format(Number(value));
}

function formatSigned(value: number) {
  const normalized = Number(value);
  return `${normalized > 0 ? "+" : ""}${formatNumber(normalized)}`;
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

function labelFromCode(value: string) {
  return value
    .toLowerCase()
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function normalizeType(value: string | undefined): FilterType {
  const normalized = value?.trim().toUpperCase() ?? "ALL";
  return WORKLIST_TYPES.includes(normalized as WorklistType)
    ? (normalized as WorklistType)
    : "ALL";
}

function buildTransactionGroups(entries: StockLedgerEntry[]) {
  const groups = new Map<string, TransactionGroup>();

  for (const entry of entries) {
    const current = groups.get(entry.transaction_id);

    if (current) {
      current.lines.push(entry);
      current.totalAbsoluteQuantity += Math.abs(entry.quantity_delta);
      current.latestLedgerSeq = Math.max(
        current.latestLedgerSeq,
        entry.ledger_seq,
      );
      continue;
    }

    groups.set(entry.transaction_id, {
      transactionId: entry.transaction_id,
      transactionNo: entry.transaction_no,
      transactionTypeCode: entry.transaction_type_code,
      reasonCode: entry.reason_code_snapshot,
      channelCode: entry.channel_code_snapshot,
      sourceTypeCode: entry.source_type_code,
      sourceRef: entry.source_ref_snapshot,
      occurredAt: entry.occurred_at,
      recordedAt: entry.recorded_at,
      note: entry.note,
      latestLedgerSeq: entry.ledger_seq,
      totalAbsoluteQuantity: Math.abs(entry.quantity_delta),
      lines: [entry],
    });
  }

  return [...groups.values()]
    .map((group) => ({
      ...group,
      lines: [...group.lines].sort(
        (left, right) => left.ledger_seq - right.ledger_seq,
      ),
    }))
    .sort((left, right) => right.latestLedgerSeq - left.latestLedgerSeq);
}

function entryCorrectionHref(
  state: FilterState,
  updates: Partial<FilterState>,
  hash?: "worklist" | "detail",
) {
  const merged = { ...state, ...updates };
  const params = new URLSearchParams();

  if (merged.q) params.set("q", merged.q);
  if (merged.type !== "ALL") params.set("type", merged.type);
  if (merged.transactionId) {
    params.set("transactionId", merged.transactionId);
  }

  const query = params.toString();
  return `/entry-corrections${query ? `?${query}` : ""}${
    hash ? `#${hash}` : ""
  }`;
}

function applicationForTransaction(
  applications: StockReversalApplication[],
  transactionId: string,
) {
  return (
    applications.find(
      (application) =>
        application.original_transaction_id === transactionId ||
        application.reversal_transaction_id === transactionId,
    ) ?? null
  );
}

function uniqueReversedTransactionCount(
  applications: StockReversalApplication[],
) {
  return new Set(
    applications.map((application) => application.original_transaction_id),
  ).size;
}

function Pill({
  label,
  tone = "neutral",
}: {
  label: string;
  tone?: "success" | "warning" | "danger" | "info" | "neutral";
}) {
  const tones = {
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

function transactionTone(
  group: TransactionGroup,
  application: StockReversalApplication | null,
) {
  if (group.transactionTypeCode === "REVERSAL") return "info" as const;
  if (application) return "success" as const;
  return "warning" as const;
}

function transactionStatusLabel(
  group: TransactionGroup,
  application: StockReversalApplication | null,
) {
  if (group.transactionTypeCode === "REVERSAL") return "Transaksi pembalik";
  if (application) return "Sudah dibalik";
  return "Siap ditinjau";
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-amber-300">
          Koreksi Entri tidak tersedia
        </p>
        <h1 className="mt-3 text-3xl font-semibold">
          Data transaksi gagal dimuat.
        </h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <Link className="nav-link mt-6 inline-flex" href="/">
          Kembali ke dashboard
        </Link>
      </section>
    </main>
  );
}

function LedgerLines({ lines }: { lines: StockLedgerEntry[] }) {
  return (
    <div className="overflow-x-auto rounded-2xl border border-white/10 bg-slate-950/35">
      <table>
        <thead>
          <tr>
            <th>Ledger</th>
            <th>Produk</th>
            <th>Batch</th>
            <th>Bucket</th>
            <th className="text-right">Delta asal</th>
            <th>Waktu</th>
          </tr>
        </thead>
        <tbody>
          {lines.map((line) => (
            <tr key={line.ledger_entry_id}>
              <td className="font-mono text-xs text-slate-500">
                #{formatNumber(line.ledger_seq)}
              </td>
              <td>
                <p className="font-medium text-white">
                  {line.product_sku_snapshot}
                </p>
                <p className="mt-1 font-mono text-[0.65rem] text-slate-600">
                  {line.product_id}
                </p>
              </td>
              <td>
                <p className="text-slate-200">{line.batch_code_snapshot}</p>
                <p className="mt-1 text-xs text-slate-500">
                  Exp {line.expiry_date_snapshot}
                </p>
              </td>
              <td>{labelFromCode(line.bucket_code)}</td>
              <td
                className={[
                  "text-right font-mono font-semibold",
                  line.quantity_delta >= 0
                    ? "text-emerald-300"
                    : "text-rose-300",
                ].join(" ")}
              >
                {formatSigned(line.quantity_delta)}
              </td>
              <td className="text-xs text-slate-500">
                {formatDate(line.occurred_at)} WIB
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ReversalLinkage({
  application,
  state,
}: {
  application: StockReversalApplication;
  state: FilterState;
}) {
  return (
    <section className="mt-6 rounded-2xl border border-sky-400/20 bg-sky-400/[0.055] p-5">
      <p className="section-kicker text-sky-300">Hubungan reversal</p>
      <h3 className="mt-2 text-lg font-semibold text-white">
        Transaksi asal dan pembalik tetap terlihat.
      </h3>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <Link
          className="rounded-xl border border-white/10 bg-slate-950/35 p-4 transition hover:border-sky-400/30"
          href={entryCorrectionHref(
            state,
            { transactionId: application.original_transaction_id },
            "detail",
          )}
        >
          <p className="text-xs text-slate-500">Transaksi asal</p>
          <p className="mt-1 font-semibold text-white">
            {application.original_transaction_no}
          </p>
        </Link>
        <Link
          className="rounded-xl border border-white/10 bg-slate-950/35 p-4 transition hover:border-sky-400/30"
          href={entryCorrectionHref(
            state,
            { transactionId: application.reversal_transaction_id },
            "detail",
          )}
        >
          <p className="text-xs text-slate-500">Transaksi pembalik</p>
          <p className="mt-1 font-semibold text-white">
            {application.reversal_transaction_no}
          </p>
        </Link>
      </div>
      <p className="mt-4 text-xs leading-5 text-slate-500">
        Mapping ledger tersimpan per entry. Kuantitas yang diaplikasikan pada
        baris ini: {formatNumber(application.quantity_applied)} unit.
      </p>
    </section>
  );
}

function ImpactPreview({
  preview,
  returnTo,
  idempotencyKey,
}: {
  preview: StockReversalPreview;
  returnTo: string;
  idempotencyKey: string;
}) {
  return (
    <section className="mt-7">
      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="section-kicker">Preview dampak authoritative</p>
          <h3 className="mt-2 text-xl font-semibold text-white">
            Saldo sebelum dan sesudah koreksi.
          </h3>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
            Preview dihitung database dan tidak mengubah stok. Commit akan
            menghitung ulang seluruh invariant sebelum ledger pembalik dibuat.
          </p>
        </div>
        <Pill
          label={preview.eligible ? "Dapat dikoreksi" : "Diblokir"}
          tone={preview.eligible ? "success" : "danger"}
        />
      </div>

      {preview.blockers.length ? (
        <div className="mt-5 space-y-3">
          {preview.blockers.map((blocker) => (
            <article
              className="rounded-2xl border border-rose-400/20 bg-rose-400/[0.06] p-4"
              key={blocker.code}
            >
              <p className="font-medium text-rose-100">{blocker.message}</p>
              <p className="mt-2 font-mono text-xs text-rose-300/70">
                {blocker.code}
              </p>
            </article>
          ))}
        </div>
      ) : null}

      <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10 bg-slate-950/35">
        <table>
          <thead>
            <tr>
              <th>Produk / batch</th>
              <th>Bucket</th>
              <th className="text-right">Asal</th>
              <th className="text-right">Reversal</th>
              <th className="text-right">Batch saat ini</th>
              <th className="text-right">Batch setelah</th>
              <th className="text-right">Sellable produk</th>
              <th className="text-right">Reserved</th>
            </tr>
          </thead>
          <tbody>
            {preview.lines.map((line) => (
              <tr key={line.originalEntryId}>
                <td>
                  <p className="font-medium text-white">{line.productSku}</p>
                  <p className="mt-1 text-xs text-slate-500">
                    {line.batchCode} Â· exp {line.expiryDate}
                  </p>
                </td>
                <td>{labelFromCode(line.bucketCode)}</td>
                <td className="text-right font-mono text-slate-300">
                  {formatSigned(line.originalDelta)}
                </td>
                <td
                  className={[
                    "text-right font-mono font-semibold",
                    line.reversalDelta >= 0
                      ? "text-emerald-300"
                      : "text-rose-300",
                  ].join(" ")}
                >
                  {formatSigned(line.reversalDelta)}
                </td>
                <td className="text-right">
                  {formatNumber(line.currentBatchBucketQty)}
                </td>
                <td className="text-right font-semibold text-white">
                  {formatNumber(line.resultingBatchBucketQty)}
                </td>
                <td className="text-right">
                  {formatNumber(line.currentProductSellableQty)}
                  <span className="mx-1 text-slate-600">â†’</span>
                  <span className="font-semibold text-white">
                    {formatNumber(line.resultingProductSellableQty)}
                  </span>
                </td>
                <td className="text-right">
                  {formatNumber(line.currentProductReservedQty)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <details className="mt-4 rounded-2xl border border-white/10 bg-white/[0.02]">
        <summary className="cursor-pointer px-5 py-4 text-sm font-medium text-slate-300 transition hover:text-white">
          Detail teknis preview
        </summary>
        <dl className="grid gap-3 border-t border-white/10 p-5 sm:grid-cols-2">
          <div className="rounded-xl border border-white/10 bg-slate-950/35 p-4">
            <dt className="text-xs text-slate-500">Basis hash</dt>
            <dd className="mt-2 break-all font-mono text-xs text-slate-300">
              {preview.basisHash}
            </dd>
          </div>
          <div className="rounded-xl border border-white/10 bg-slate-950/35 p-4">
            <dt className="text-xs text-slate-500">Jumlah entry</dt>
            <dd className="mt-2 text-sm text-slate-200">
              {formatNumber(preview.lineCount)} entry Â·{" "}
              {formatNumber(preview.totalAbsoluteQuantity)} unit absolut
            </dd>
          </div>
        </dl>
      </details>

      {preview.eligible ? (
        <form
          action={reverseStockTransactionAction}
          className="mt-6 rounded-3xl border border-amber-400/25 bg-amber-400/[0.055] p-5 lg:p-6"
        >
          <input
            name="originalTransactionId"
            type="hidden"
            value={preview.originalTransaction.transactionId}
          />
          <input
            name="previewBasisHash"
            type="hidden"
            value={preview.basisHash}
          />
          <input
            name="idempotencyKey"
            type="hidden"
            value={idempotencyKey}
          />
          <input name="returnTo" type="hidden" value={returnTo} />

          <p className="section-kicker text-amber-300">Konfirmasi final</p>
          <h3 className="mt-2 text-xl font-semibold text-white">
            Balik seluruh transaksi secara atomik.
          </h3>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            Transaksi dan ledger asal tidak diedit atau dihapus. Sistem membuat
            transaksi REVERSAL baru dengan delta yang tepat berlawanan. Proses
            ini adalah Koreksi Entri, bukan Penyesuaian Opname.
          </p>

          <label className="field-label mt-5">
            Alasan koreksi
            <textarea
              maxLength={2000}
              minLength={1}
              name="note"
              placeholder="Jelaskan kesalahan input dan alasan transaksi harus dibalik."
              required
              rows={5}
            />
          </label>

          <label className="mt-4 flex items-start gap-3 rounded-xl border border-white/10 bg-slate-950/45 p-4">
            <input
              className="mt-1"
              name="confirmation"
              required
              type="checkbox"
            />
            <span>
              <span className="text-sm font-semibold text-white">
                Saya sudah meninjau dampak dan mengonfirmasi reversal penuh.
              </span>
              <span className="mt-1 block text-xs leading-5 text-slate-500">
                Database tetap akan menolak preview kedaluwarsa, saldo negatif,
                reserved conflict, atau transaksi yang sudah dibalik.
              </span>
            </span>
          </label>

          <button
            className="mt-5 rounded-xl bg-amber-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-amber-200"
            type="submit"
          >
            Posting Koreksi Entri
          </button>
        </form>
      ) : (
        <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/[0.055] p-5 text-sm leading-6 text-rose-100">
          Commit tidak tersedia karena database menemukan blocker. Tidak ada
          stok atau ledger yang berubah dari preview ini.
        </div>
      )}
    </section>
  );
}

export default async function EntryCorrectionsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const state: FilterState = {
    q: params.q?.trim() ?? "",
    type: normalizeType(params.type),
    transactionId: params.transactionId?.trim() || null,
  };

  let data;

  try {
    data = await getEntryCorrectionData();
  } catch (error) {
    return (
      <ConfigurationError
        message={error instanceof Error ? error.message : "Konfigurasi tidak valid."}
      />
    );
  }

  const groups = buildTransactionGroups(data.ledger);
  const reversedOriginalIds = new Set(
    data.applications.map(
      (application) => application.original_transaction_id,
    ),
  );
  const normalizedQuery = state.q.toLowerCase();

  const filteredGroups = groups.filter((group) => {
    if (
      state.type !== "ALL" &&
      group.transactionTypeCode !== state.type
    ) {
      return false;
    }

    if (!normalizedQuery) return true;

    return [
      group.transactionNo,
      group.sourceRef,
      group.sourceTypeCode,
      group.reasonCode,
      group.channelCode,
      ...group.lines.flatMap((line) => [
        line.product_sku_snapshot,
        line.batch_code_snapshot,
      ]),
    ]
      .join(" ")
      .toLowerCase()
      .includes(normalizedQuery);
  });

  const selectedGroup = state.transactionId
    ? groups.find((group) => group.transactionId === state.transactionId) ??
      null
    : null;
  const selectedApplication = selectedGroup
    ? applicationForTransaction(
        data.applications,
        selectedGroup.transactionId,
      )
    : null;

  let preview: StockReversalPreview | null = null;
  let previewError: string | null = null;

  if (
    selectedGroup &&
    SUPPORTED_SOURCE_TYPES.includes(
      selectedGroup.transactionTypeCode as (typeof SUPPORTED_SOURCE_TYPES)[number],
    )
  ) {
    try {
      preview = await previewStockTransactionReversal(
        selectedGroup.transactionId,
      );
    } catch (error) {
      previewError =
        error instanceof Error
          ? error.message
          : "Preview reversal gagal dimuat.";
    }
  }

  const candidateCount = groups.filter(
    (group) =>
      SUPPORTED_SOURCE_TYPES.includes(
        group.transactionTypeCode as (typeof SUPPORTED_SOURCE_TYPES)[number],
      ) && !reversedOriginalIds.has(group.transactionId),
  ).length;
  const reversalCount = groups.filter(
    (group) => group.transactionTypeCode === "REVERSAL",
  ).length;
  const returnTo = selectedGroup
    ? entryCorrectionHref(
        state,
        { transactionId: selectedGroup.transactionId },
        "detail",
      )
    : entryCorrectionHref(state, {}, "worklist");

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <PageSectionNav
        items={[
          { href: "#overview", label: "Ringkasan" },
          { href: "#worklist", label: "Transaksi" },
          { href: "#detail", label: "Detail & preview" },
        ]}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section className="scroll-mt-24" id="overview">
          <div className="flex flex-col gap-6 xl:flex-row xl:items-end xl:justify-between">
            <div>
              <p className="section-kicker">Kontrol stok Â· Koreksi Entri</p>
              <h1 className="mt-3 max-w-4xl text-3xl font-semibold tracking-tight sm:text-4xl">
                Balik kesalahan input tanpa menghapus jejak transaksi.
              </h1>
              <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
                Tinjau transaksi penerimaan atau outbound manual, periksa dampak
                saldo yang dihitung database, lalu buat REVERSAL baru dengan
                konfirmasi eksplisit.
              </p>
            </div>
            <div className="rounded-2xl border border-amber-400/20 bg-amber-400/[0.055] px-4 py-3 text-sm text-amber-100">
              Full-document reversal Â· bukan edit saldo
            </div>
          </div>

          {params.success ? (
            <div className="mt-6 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-100">
              <p>{params.success}</p>
              {params.originalId && params.reversalId ? (
                <div className="mt-3 flex flex-wrap gap-3">
                  <Link
                    className="rounded-lg border border-emerald-300/25 px-3 py-2 font-medium transition hover:bg-emerald-300/10"
                    href={entryCorrectionHref(
                      state,
                      { transactionId: params.originalId },
                      "detail",
                    )}
                  >
                    Buka transaksi asal
                  </Link>
                  <Link
                    className="rounded-lg border border-emerald-300/25 px-3 py-2 font-medium transition hover:bg-emerald-300/10"
                    href={entryCorrectionHref(
                      state,
                      { transactionId: params.reversalId },
                      "detail",
                    )}
                  >
                    Buka transaksi pembalik
                  </Link>
                </div>
              ) : null}
            </div>
          ) : null}

          {params.error ? (
            <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-100">
              {params.error}
            </div>
          ) : null}

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              ["Transaksi terbaca", groups.length, "Dikelompokkan per stock transaction"],
              ["Siap ditinjau", candidateCount, "Receipt atau manual outbound"],
              [
                "Sudah dibalik",
                uniqueReversedTransactionCount(data.applications),
                "Transaksi asal dengan reversal mapping",
              ],
              ["Transaksi reversal", reversalCount, "Jejak pembalik yang tetap terlihat"],
            ].map(([label, value, description]) => (
              <article className="metric-card" key={label}>
                <p className="text-sm text-slate-400">{label}</p>
                <p className="mt-3 text-3xl font-semibold text-white">
                  {formatNumber(Number(value))}
                </p>
                <p className="mt-2 text-xs text-slate-500">{description}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="mt-10 scroll-mt-24" id="worklist">
          <div className="mb-5">
            <p className="section-kicker">Transaction worklist</p>
            <h2 className="section-title">
              Temukan dokumen yang perlu dikoreksi.
            </h2>
          </div>

          <form
            className="mb-5 grid gap-4 rounded-2xl border border-white/10 bg-white/[0.025] p-5 md:grid-cols-[minmax(0,1fr)_16rem_auto]"
            method="get"
          >
            <label className="field-label">
              Cari transaksi
              <input
                defaultValue={state.q}
                name="q"
                placeholder="Nomor transaksi, referensi, SKU, atau batch"
              />
            </label>

            <label className="field-label">
              Jenis transaksi
              <select defaultValue={state.type} name="type">
                <option value="ALL">Semua jenis</option>
                <option value="RECEIPT">Penerimaan</option>
                <option value="MANUAL_OUTBOUND">Outbound manual</option>
                <option value="REVERSAL">Reversal</option>
              </select>
            </label>

            <div className="flex items-end gap-3">
              <button className="primary-button" type="submit">
                Terapkan
              </button>
              <Link
                className="nav-link border border-white/10"
                href="/entry-corrections#worklist"
              >
                Reset
              </Link>
            </div>
          </form>

          {filteredGroups.length === 0 ? (
            <div className="rounded-3xl border border-dashed border-white/15 bg-white/[0.02] px-6 py-14 text-center">
              <h3 className="text-xl font-semibold text-white">
                Tidak ada transaksi yang cocok.
              </h3>
              <p className="mx-auto mt-3 max-w-xl text-sm leading-6 text-slate-400">
                Ubah filter atau cari menggunakan nomor transaksi, referensi
                sumber, SKU, maupun kode batch.
              </p>
            </div>
          ) : (
            <div className="overflow-x-auto rounded-2xl border border-white/10 bg-white/[0.025]">
              <table>
                <thead>
                  <tr>
                    <th>Transaksi</th>
                    <th>Status koreksi</th>
                    <th>Sumber</th>
                    <th>Reason / channel</th>
                    <th className="text-right">Entry</th>
                    <th className="text-right">Qty absolut</th>
                    <th>Waktu</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {filteredGroups.map((group) => {
                    const application = applicationForTransaction(
                      data.applications,
                      group.transactionId,
                    );

                    return (
                      <tr key={group.transactionId}>
                        <td>
                          <p className="font-semibold text-white">
                            {group.transactionNo}
                          </p>
                          <p className="mt-1 text-xs text-slate-500">
                            {labelFromCode(group.transactionTypeCode)}
                          </p>
                        </td>
                        <td>
                          <Pill
                            label={transactionStatusLabel(group, application)}
                            tone={transactionTone(group, application)}
                          />
                        </td>
                        <td>
                          <p className="text-slate-200">{group.sourceRef}</p>
                          <p className="mt-1 text-xs text-slate-500">
                            {labelFromCode(group.sourceTypeCode)}
                          </p>
                        </td>
                        <td>
                          <p>{labelFromCode(group.reasonCode)}</p>
                          <p className="mt-1 text-xs text-slate-500">
                            {labelFromCode(group.channelCode)}
                          </p>
                        </td>
                        <td className="text-right">
                          {formatNumber(group.lines.length)}
                        </td>
                        <td className="text-right">
                          {formatNumber(group.totalAbsoluteQuantity)}
                        </td>
                        <td className="text-xs text-slate-500">
                          {formatDate(group.occurredAt)} WIB
                        </td>
                        <td>
                          <Link
                            className="rounded-xl border border-white/10 bg-white/[0.035] px-3 py-2 text-sm font-medium text-slate-200 transition hover:border-emerald-400/25 hover:bg-emerald-400/[0.08]"
                            href={entryCorrectionHref(
                              state,
                              { transactionId: group.transactionId },
                              "detail",
                            )}
                          >
                            Tinjau
                          </Link>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <section className="mt-10 scroll-mt-24" id="detail">
          {!selectedGroup ? (
            <div className="rounded-3xl border border-dashed border-white/15 bg-white/[0.02] px-6 py-14 text-center">
              <p className="font-mono text-xs uppercase tracking-[0.18em] text-emerald-300">
                Detail transaksi
              </p>
              <h2 className="mt-3 text-2xl font-semibold text-white">
                Pilih transaksi untuk melihat dampaknya.
              </h2>
              <p className="mx-auto mt-3 max-w-xl text-sm leading-6 text-slate-400">
                Preview authoritative hanya dihitung untuk transaksi yang
                dipilih. Membuka detail tidak mengubah ledger maupun saldo.
              </p>
            </div>
          ) : (
            <article className="rounded-3xl border border-white/10 bg-white/[0.025] p-5 lg:p-6">
              <div className="flex flex-col gap-4 border-b border-white/10 pb-5 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <p className="section-kicker">Detail transaksi</p>
                  <h2 className="mt-2 text-2xl font-semibold text-white">
                    {selectedGroup.transactionNo}
                  </h2>
                  <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
                    {selectedGroup.note ||
                      "Tidak ada catatan pada transaksi asal."}
                  </p>
                </div>
                <Link
                  className="shrink-0 rounded-xl border border-white/10 px-3 py-2 text-sm text-slate-300 transition hover:bg-white/[0.05]"
                  href={entryCorrectionHref(
                    state,
                    { transactionId: null },
                    "worklist",
                  )}
                >
                  Tutup detail
                </Link>
              </div>

              <div className="mt-5 flex flex-wrap gap-2">
                <Pill
                  label={labelFromCode(selectedGroup.transactionTypeCode)}
                  tone={
                    selectedGroup.transactionTypeCode === "REVERSAL"
                      ? "info"
                      : "neutral"
                  }
                />
                <Pill label={labelFromCode(selectedGroup.reasonCode)} />
                <Pill label={labelFromCode(selectedGroup.channelCode)} />
                <Pill
                  label={transactionStatusLabel(
                    selectedGroup,
                    selectedApplication,
                  )}
                  tone={transactionTone(
                    selectedGroup,
                    selectedApplication,
                  )}
                />
              </div>

              <dl className="mt-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                {[
                  ["Referensi sumber", selectedGroup.sourceRef],
                  ["Tipe sumber", labelFromCode(selectedGroup.sourceTypeCode)],
                  ["Terjadi", `${formatDate(selectedGroup.occurredAt)} WIB`],
                  ["Dicatat", `${formatDate(selectedGroup.recordedAt)} WIB`],
                ].map(([label, value]) => (
                  <div
                    className="rounded-xl border border-white/10 bg-slate-950/35 p-4"
                    key={label}
                  >
                    <dt className="text-xs text-slate-500">{label}</dt>
                    <dd className="mt-2 break-words text-sm font-medium text-slate-200">
                      {value}
                    </dd>
                  </div>
                ))}
              </dl>

              <div className="mt-7">
                <div className="mb-4">
                  <p className="section-kicker">Ledger asal</p>
                  <h3 className="mt-1 text-xl font-semibold text-white">
                    Seluruh baris dalam transaksi.
                  </h3>
                </div>
                <LedgerLines lines={selectedGroup.lines} />
              </div>

              {selectedApplication ? (
                <ReversalLinkage
                  application={selectedApplication}
                  state={state}
                />
              ) : null}

              {previewError ? (
                <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/[0.055] p-5 text-sm leading-6 text-rose-100">
                  Preview gagal dimuat: {previewError}
                </div>
              ) : null}

              {preview ? (
                <ImpactPreview
                  idempotencyKey={`entry-correction:${selectedGroup.transactionId}:${randomUUID()}`}
                  preview={preview}
                  returnTo={returnTo}
                />
              ) : null}

              {selectedGroup.transactionTypeCode === "REVERSAL" ? (
                <div className="mt-6 rounded-2xl border border-sky-400/20 bg-sky-400/[0.055] p-5 text-sm leading-6 text-sky-100">
                  Ini adalah transaksi pembalik yang bersifat immutable. Sistem
                  tidak menyediakan reversal-of-reversal melalui workflow
                  generik.
                </div>
              ) : null}
            </article>
          )}
        </section>
      </div>
    </main>
  );
}