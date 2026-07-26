import Link from "next/link";
import { notFound } from "next/navigation";

import {
  getLedgerTransactionDetail,
  type LedgerExplorerRow,
  type LedgerReversalLink,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParamValue = string | string[] | undefined;

function formatDate(value: string | null) {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function signedQuantity(value: number) {
  return `${value > 0 ? "+" : ""}${new Intl.NumberFormat("id-ID").format(value)}`;
}

function labelFromCode(value: string) {
  return value.toLowerCase().split("_").map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(" ");
}

function sourceHref(row: LedgerExplorerRow) {
  if (!row.source_id) return null;
  const id = encodeURIComponent(row.source_id);
  switch (row.source_type_code) {
    case "MANUAL_OUTBOUND": return `/manual-outbounds?outboundId=${id}`;
    case "DISPOSAL": return `/stock-disposals?disposalId=${id}`;
    case "STOCKTAKE": return `/stocktakes/${id}`;
    case "OPENING_BALANCE_CUTOVER": return `/opening-balances?cutoverId=${id}`;
    case "RETURN": return `/returns?returnId=${id}`;
    case "REVERSAL": return `/entry-corrections?transactionId=${id}`;
    default: return null;
  }
}

function SourceEvidence({ row }: { row: LedgerExplorerRow }) {
  const href = sourceHref(row);
  return (
    <div className="panel-card mt-6" data-testid="ledger-source-evidence">
      <p className="section-kicker">Source evidence</p>
      <h2 className="section-title">Sumber movement</h2>
      <p className="mt-3 text-sm text-slate-300">{row.source_type_code} · {row.source_ref_snapshot}</p>
      {href ? <Link className="nav-link mt-4 inline-flex" href={href}>Buka sumber exact</Link> : <p className="mt-4 text-sm text-slate-400">Detail sumber belum tersedia sebagai route exact. Tidak ada link spekulatif.</p>}
      <p className="mt-3 text-xs text-slate-500">Reconciliation issue tidak disimpulkan dari product/batch atau source reference; link hanya ditampilkan bila evidence exact tersedia.</p>
    </div>
  );
}

function backHref(searchParams: Record<string, SearchParamValue>) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(searchParams)) {
    const normalized = Array.isArray(value) ? value[0] : value;
    if (normalized?.trim()) query.set(key, normalized);
  }
  const encoded = query.toString();
  return encoded ? `/ledger?${encoded}` : "/ledger";
}

function RelatedReversal({
  link,
  transactionId,
}: {
  link: LedgerReversalLink;
  transactionId: string;
}) {
  const isOriginal = link.original_transaction_id === transactionId;
  const relatedId = isOriginal ? link.reversal_transaction_id : link.original_transaction_id;
  const relatedNo = isOriginal ? link.reversal_transaction_no : link.original_transaction_no;

  return (
    <li className="flex flex-wrap items-center gap-2 text-sm text-slate-300">
      <span>{isOriginal ? "Reversal" : "Original"} · qty {link.quantity_applied}</span>
      <Link className="font-mono text-xs text-emerald-300 underline underline-offset-4" href={`/ledger/${relatedId}`}>
        {relatedNo}
      </Link>
    </li>
  );
}

function EntryRow({ row }: { row: LedgerExplorerRow }) {
  return (
    <tr className="align-top border-t border-white/5">
      <td className="px-4 py-4 font-mono text-xs text-slate-500">{row.line_no}</td>
      <td className="px-4 py-4">
        <p className="font-mono text-xs text-slate-200">{row.product_sku_snapshot}</p>
        <p className="mt-1 text-xs text-slate-500">{row.batch_code_snapshot}</p>
      </td>
      <td className="px-4 py-4 text-xs text-slate-300">{row.bucket_code}</td>
      <td className={`px-4 py-4 font-mono font-semibold ${row.quantity_delta >= 0 ? "text-emerald-300" : "text-rose-300"}`}>
        <span aria-label={row.quantity_delta >= 0 ? "quantity masuk" : "quantity keluar"}>{signedQuantity(row.quantity_delta)}</span>
        <span className="ml-2 text-[0.65rem] text-slate-500">{row.quantity_direction}</span>
      </td>
      <td className="px-4 py-4 text-xs text-slate-400">{row.entry_role_code} · {row.source_line_ref ?? "-"}</td>
      <td className="px-4 py-4 text-xs text-slate-400">{row.reversal_state}</td>
    </tr>
  );
}

function ReadError({ message }: { message: string }) {
  return <main className="mx-auto max-w-4xl px-5 py-10 text-slate-100"><section className="rounded-2xl border border-rose-400/20 bg-rose-400/[0.06] p-6 text-sm text-rose-100" data-testid="ledger-detail-error"><strong>Detail transaction tidak dapat dibaca.</strong><p className="mt-2 text-rose-200/80">{message}</p><Link className="nav-link mt-5 inline-flex" href="/ledger">Kembali ke Ledger Explorer</Link></section></main>;
}

export default async function LedgerTransactionPage({
  params,
  searchParams,
}: {
  params: Promise<{ transactionId: string }>;
  searchParams: Promise<Record<string, SearchParamValue>>;
}) {
  const [{ transactionId }, query] = await Promise.all([params, searchParams]);
  let detail;

  try {
    detail = await getLedgerTransactionDetail(transactionId);
  } catch (error) {
    return <ReadError message={error instanceof Error ? error.message : "Kesalahan database tidak diketahui."} />;
  }

  if (!detail) notFound();

  const firstRow = detail.rows[0];
  const relatedLinks = detail.reversalLinks;

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto w-full max-w-[1200px] px-5 py-8 lg:px-8">
        <Link className="nav-link inline-flex" href={backHref(query)}>← Kembali ke Ledger Explorer</Link>
        <header className="mt-6 flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <p className="section-kicker">Exact transaction detail</p>
            <h1 className="mt-3 font-mono text-2xl font-semibold sm:text-3xl" data-testid="ledger-detail-title">{firstRow.transaction_no}</h1>
            <p className="mt-2 text-sm text-slate-400">{labelFromCode(firstRow.transaction_type_code)} · {firstRow.source_type_code} · read-only</p>
          </div>
          <span className="rounded-full border border-emerald-400/20 bg-emerald-400/10 px-3 py-2 text-xs text-emerald-200">Tidak ada mutation action</span>
        </header>

        <section className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4" data-testid="ledger-detail-metadata">
          {[
            ["Reason", firstRow.reason_code_snapshot],
            ["Channel", firstRow.channel_code_snapshot],
            ["Source", `${firstRow.source_type_code} · ${firstRow.source_ref_snapshot}`],
            ["Actor / process", firstRow.process_name ?? firstRow.actor_user_id ?? "-"],
            ["Occurred at", formatDate(firstRow.occurred_at)],
            ["Recorded at", formatDate(firstRow.recorded_at)],
            ["Correlation", firstRow.correlation_id],
            ["Idempotency", firstRow.idempotency_command_id],
          ].map(([label, value]) => <div key={label} className="panel-card"><p className="text-xs uppercase tracking-wide text-slate-500">{label}</p><p className="mt-2 break-words text-sm text-slate-200">{value}</p></div>)}
        </section>

        <section className="panel-card mt-6" aria-labelledby="ledger-entry-title">
          <div className="flex flex-wrap items-end justify-between gap-3"><div><p className="section-kicker">Ledger entries</p><h2 id="ledger-entry-title" className="section-title">{detail.rows.length} baris dalam transaction ini</h2></div><p className="text-xs text-slate-500">Urutan line_no lalu ledger_seq.</p></div>
          <div className="mt-5 overflow-x-auto rounded-2xl border border-white/10" data-testid="ledger-detail-entries">
            <table className="min-w-[760px] w-full text-left text-sm"><thead className="bg-white/[0.04] text-xs uppercase tracking-wide text-slate-500"><tr><th className="px-4 py-3">Line</th><th className="px-4 py-3">Produk / batch</th><th className="px-4 py-3">Bucket</th><th className="px-4 py-3">Delta</th><th className="px-4 py-3">Role / source line</th><th className="px-4 py-3">Reversal</th></tr></thead><tbody>{detail.rows.map((row) => <EntryRow key={row.ledger_entry_id} row={row} />)}</tbody></table>
          </div>
        </section>

        <section className="panel-card mt-6" aria-labelledby="reversal-title">
          <p className="section-kicker">Original ↔ reversal</p>
          <h2 id="reversal-title" className="section-title">Linkage audit</h2>
          {relatedLinks.length ? <ul className="mt-4 space-y-3">{relatedLinks.map((link) => <RelatedReversal key={link.reversal_application_id} link={link} transactionId={detail.transactionId} />)}</ul> : <p className="mt-4 text-sm text-slate-400" data-testid="ledger-no-reversal">Tidak ada reversal yang tertaut pada transaction ini.</p>}
          <p className="mt-5 text-xs leading-5 text-slate-500">Source reference ditampilkan apa adanya dari ledger. Link entity yang belum tersedia tidak dibuat secara spekulatif.</p>
        </section>

        <SourceEvidence row={firstRow} />
      </div>
    </main>
  );
}
