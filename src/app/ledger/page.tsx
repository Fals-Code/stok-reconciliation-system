import Link from "next/link";

import {
  getLedgerExplorerPage,
  type LedgerExplorerFilters,
  type LedgerExplorerPage as LedgerPageResult,
  type LedgerExplorerRow,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParamValue = string | string[] | undefined;
type LedgerSearchParams = Record<string, SearchParamValue>;

const numberFormatter = new Intl.NumberFormat("id-ID");

function firstParam(value: SearchParamValue) {
  return Array.isArray(value) ? value[0] : value;
}

function textParam(params: LedgerSearchParams, name: string) {
  return firstParam(params[name])?.trim() ?? "";
}

function formatNumber(value: number) {
  return numberFormatter.format(value);
}

function formatDate(value: string | null) {
  if (!value) return "-";

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

function signedQuantity(value: number) {
  return `${value > 0 ? "+" : ""}${formatNumber(value)}`;
}

function filtersFromParams(params: LedgerSearchParams): LedgerExplorerFilters {
  const direction = textParam(params, "direction");
  const quantityDirection = textParam(params, "quantityDirection");

  return {
    occurredFrom: textParam(params, "occurredFrom") || undefined,
    occurredTo: textParam(params, "occurredTo") || undefined,
    recordedFrom: textParam(params, "recordedFrom") || undefined,
    recordedTo: textParam(params, "recordedTo") || undefined,
    productSku: textParam(params, "productSku") || undefined,
    batchCode: textParam(params, "batchCode") || undefined,
    transactionType: textParam(params, "transactionType") || undefined,
    reason: textParam(params, "reason") || undefined,
    channel: textParam(params, "channel") || undefined,
    sourceType: textParam(params, "sourceType") || undefined,
    sourceRef: textParam(params, "sourceRef") || undefined,
    actorProcess: textParam(params, "actorProcess") || undefined,
    bucket: textParam(params, "bucket") || undefined,
    quantityDirection:
      quantityDirection === "IN" || quantityDirection === "OUT"
        ? quantityDirection
        : undefined,
    reversalState: textParam(params, "reversalState") as LedgerExplorerFilters["reversalState"] || undefined,
    cursor: textParam(params, "cursor") || undefined,
    direction: direction === "previous" ? "previous" : "next",
    pageSize: 20,
  };
}

function queryForState(
  params: LedgerSearchParams,
  cursor: string | null,
  direction: "next" | "previous",
) {
  const next = new URLSearchParams();
  const names = [
    "occurredFrom",
    "occurredTo",
    "recordedFrom",
    "recordedTo",
    "productSku",
    "batchCode",
    "transactionType",
    "reason",
    "channel",
    "sourceType",
    "sourceRef",
    "actorProcess",
    "bucket",
    "quantityDirection",
    "reversalState",
  ];

  for (const name of names) {
    const value = textParam(params, name);
    if (value) next.set(name, value);
  }

  if (cursor) {
    next.set("cursor", cursor);
    next.set("direction", direction);
  }

  const query = next.toString();
  return query ? `/ledger?${query}` : "/ledger";
}

function DetailLink({
  row,
  params,
}: {
  row: LedgerExplorerRow;
  params: LedgerSearchParams;
}) {
  const detailQuery = new URLSearchParams();
  const sourceQuery = new URLSearchParams(queryForState(params, null, "next").split("?")[1] ?? "");
  sourceQuery.forEach((value, key) => detailQuery.set(key, value));
  const query = detailQuery.toString();

  return (
    <Link
      className="font-mono text-xs text-emerald-300 underline decoration-emerald-300/30 underline-offset-4 hover:text-emerald-200"
      href={`/ledger/${row.transaction_id}${query ? `?${query}` : ""}`}
    >
      {row.transaction_no}
    </Link>
  );
}

function FilterForm({ params }: { params: LedgerSearchParams }) {
  const fields = [
    ["occurredFrom", "Occurred dari", "datetime-local"],
    ["occurredTo", "Occurred sampai", "datetime-local"],
    ["recordedFrom", "Recorded dari", "datetime-local"],
    ["recordedTo", "Recorded sampai", "datetime-local"],
    ["productSku", "SKU produk", "text"],
    ["batchCode", "Kode batch", "text"],
    ["transactionType", "Tipe transaksi", "text"],
    ["reason", "Reason", "text"],
    ["channel", "Channel", "text"],
    ["sourceType", "Source type", "text"],
    ["sourceRef", "Source reference", "text"],
    ["actorProcess", "Actor / process", "text"],
  ] as const;

  return (
    <form method="get" className="panel-card" data-testid="ledger-filter-form">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="section-kicker">Filter read-only</p>
          <h2 className="section-title">Cari alasan di balik movement.</h2>
        </div>
        <Link className="nav-link" href="/ledger">Reset filter</Link>
      </div>

      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {fields.map(([name, label, type]) => (
          <label key={name} className="field-label">
            {label}
            <input
              name={name}
              type={type}
              defaultValue={textParam(params, name)}
              placeholder={type === "text" ? `Filter ${label.toLowerCase()}` : undefined}
            />
          </label>
        ))}

        <label className="field-label">
          Bucket
          <select name="bucket" defaultValue={textParam(params, "bucket")}>
            <option value="">Semua bucket</option>
            <option value="SELLABLE">SELLABLE</option>
            <option value="QUARANTINE">QUARANTINE</option>
            <option value="DAMAGED">DAMAGED</option>
          </select>
        </label>
        <label className="field-label">
          Arah quantity
          <select name="quantityDirection" defaultValue={textParam(params, "quantityDirection")}>
            <option value="">Semua arah</option>
            <option value="IN">IN (+)</option>
            <option value="OUT">OUT (-)</option>
          </select>
        </label>
        <label className="field-label">
          Reversal state
          <select name="reversalState" defaultValue={textParam(params, "reversalState")}>
            <option value="">Semua state</option>
            <option value="NOT_REVERSED">NOT_REVERSED</option>
            <option value="PARTIALLY_REVERSED">PARTIALLY_REVERSED</option>
            <option value="FULLY_REVERSED">FULLY_REVERSED</option>
            <option value="REVERSAL">REVERSAL</option>
          </select>
        </label>
      </div>

      <div className="mt-5 flex flex-wrap items-center gap-3">
        <button className="primary-button" type="submit">Terapkan filter</button>
        <span className="text-xs text-slate-500">Filter disimpan di URL dan tetap setelah refresh.</span>
      </div>
    </form>
  );
}

function LedgerTable({ rows, params }: { rows: LedgerExplorerRow[]; params: LedgerSearchParams }) {
  return (
    <div className="overflow-x-auto rounded-2xl border border-white/10" data-testid="ledger-table">
      <table className="min-w-[1200px] w-full text-left text-sm">
        <thead className="bg-white/[0.04] text-xs uppercase tracking-wide text-slate-500">
          <tr>
            <th className="px-4 py-3">Transaction</th>
            <th className="px-4 py-3">Occurred</th>
            <th className="px-4 py-3">Recorded</th>
            <th className="px-4 py-3">Produk / batch</th>
            <th className="px-4 py-3">Bucket</th>
            <th className="px-4 py-3">Quantity</th>
            <th className="px-4 py-3">Reason / channel</th>
            <th className="px-4 py-3">Source</th>
            <th className="px-4 py-3">Actor / process</th>
            <th className="px-4 py-3">Reversal</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-white/5">
          {rows.map((row) => (
            <tr key={row.ledger_entry_id} className="align-top hover:bg-white/[0.025]">
              <td className="px-4 py-4">
                <DetailLink row={row} params={params} />
                <p className="mt-1 text-xs text-slate-500">{labelFromCode(row.transaction_type_code)} · line {row.line_no}</p>
              </td>
              <td className="whitespace-nowrap px-4 py-4 text-slate-300">{formatDate(row.occurred_at)}</td>
              <td className="whitespace-nowrap px-4 py-4 text-slate-400">{formatDate(row.recorded_at)}</td>
              <td className="px-4 py-4">
                <p className="font-mono text-xs text-slate-200">{row.product_sku_snapshot}</p>
                <p className="mt-1 text-xs text-slate-500">{row.batch_code_snapshot}</p>
              </td>
              <td className="px-4 py-4 text-xs text-slate-300">{row.bucket_code}</td>
              <td className={`whitespace-nowrap px-4 py-4 font-mono font-semibold ${row.quantity_delta >= 0 ? "text-emerald-300" : "text-rose-300"}`}>
                <span aria-label={row.quantity_delta >= 0 ? "quantity masuk" : "quantity keluar"}>{signedQuantity(row.quantity_delta)}</span>
                <span className="ml-2 text-[0.65rem] text-slate-500">{row.quantity_direction}</span>
              </td>
              <td className="px-4 py-4 text-xs">
                <p className="text-slate-300">{row.reason_code_snapshot}</p>
                <p className="mt-1 text-slate-500">{row.channel_code_snapshot}</p>
              </td>
              <td className="max-w-48 px-4 py-4 text-xs">
                <p className="text-slate-300">{row.source_type_code}</p>
                <p className="mt-1 break-all text-slate-500">{row.source_ref_snapshot}</p>
              </td>
              <td className="max-w-48 px-4 py-4 text-xs text-slate-400">
                {row.process_name ?? row.actor_user_id ?? "-"}
              </td>
              <td className="px-4 py-4 text-xs text-slate-400">{row.reversal_state}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Pagination({ result, params }: { result: LedgerPageResult; params: LedgerSearchParams }) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-t border-white/10 pt-5" data-testid="ledger-pagination">
      <p className="text-xs text-slate-500">Menampilkan maksimal {result.pageSize} baris per halaman.</p>
      <div className="flex gap-2">
        {result.hasPreviousPage && result.previousCursor ? (
          <Link className="nav-link" href={queryForState(params, result.previousCursor, "previous")}>← Lebih baru</Link>
        ) : <span className="rounded-xl border border-white/5 px-3 py-2 text-sm text-slate-700">← Lebih baru</span>}
        {result.hasNextPage && result.nextCursor ? (
          <Link className="primary-button" href={queryForState(params, result.nextCursor, "next")}>Lebih lama →</Link>
        ) : <span className="rounded-xl border border-white/5 px-3 py-2 text-sm text-slate-700">Lebih lama →</span>}
      </div>
    </div>
  );
}

function ReadError({ message }: { message: string }) {
  return <section className="rounded-2xl border border-rose-400/20 bg-rose-400/[0.06] p-6 text-sm text-rose-100" data-testid="ledger-error"><strong>Ledger tidak dapat dibaca.</strong><p className="mt-2 text-rose-200/80">{message}</p></section>;
}

export default async function LedgerPage({ searchParams }: { searchParams: Promise<LedgerSearchParams> }) {
  const params = await searchParams;
  const filters = filtersFromParams(params);
  let result: LedgerPageResult;
  let errorMessage: string | null = null;

  try {
    result = await getLedgerExplorerPage(filters);
  } catch (error) {
    result = { rows: [], pageSize: 20, nextCursor: null, previousCursor: null, hasNextPage: false, hasPreviousPage: false };
    errorMessage = error instanceof Error ? error.message : "Kesalahan database tidak diketahui.";
  }

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto w-full max-w-[1500px] px-5 py-8 lg:px-8">
        <header className="mb-7 flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="section-kicker">Auditability / Ledger</p>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">Ledger Explorer</h1>
            <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">Explorer read-only untuk menjawab mengapa saldo produk atau batch berubah. Ledger tetap append-only dan reservasi tidak dihitung sebagai movement fisik.</p>
          </div>
          <span className="rounded-full border border-emerald-400/20 bg-emerald-400/10 px-3 py-2 text-xs text-emerald-200">Read-only · organization-scoped</span>
        </header>

        <FilterForm params={params} />
        <section className="panel-card mt-6" aria-labelledby="ledger-result-title">
          <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
            <div><p className="section-kicker">Movement history</p><h2 id="ledger-result-title" className="section-title">Perubahan stok yang dapat ditelusuri</h2></div>
            <p className="text-xs text-slate-500">Urutan ledger_seq terbaru ke terlama.</p>
          </div>
          {errorMessage ? <ReadError message={errorMessage} /> : result.rows.length === 0 ? <div className="rounded-2xl border border-white/10 bg-white/[0.02] p-8 text-center text-sm text-slate-400" data-testid="ledger-empty">Tidak ada movement untuk filter ini.</div> : <LedgerTable rows={result.rows} params={params} />}
          {!errorMessage && result.rows.length > 0 ? <div className="mt-5"><Pagination result={result} params={params} /></div> : null}
        </section>
      </div>
    </main>
  );
}
