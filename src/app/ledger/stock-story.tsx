import Link from "next/link";

import { getLedgerStockStoryPage, type LedgerExplorerFilters } from "@/lib/supabase-rest";

const numberFormatter = new Intl.NumberFormat("id-ID");

function date(value: string) {
  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    dateStyle: "medium",
    timeStyle: "short",
    hour12: false,
  }).format(new Date(value));
}

function sourceLabel(value: string, reference: string) {
  return `${value} · ${reference}`;
}

export async function LedgerStockStory({
  productId,
  batchId,
  productLabel,
  batchLabel,
}: {
  productId: string;
  batchId?: string;
  productLabel: string;
  batchLabel?: string;
}) {
  const filters: LedgerExplorerFilters = { productId, batchId, pageSize: 10 };
  let result;

  try {
    result = await getLedgerStockStoryPage(filters);
  } catch {
    return (
      <section className="panel-card mt-6" data-testid="stock-story-error">
        <p className="section-kicker">Stock story</p>
        <h2 className="section-title">Jejak stok tidak dapat dibaca.</h2>
        <p className="mt-3 text-sm text-rose-200">Periksa sesi Admin atau koneksi database. Histori tidak diganti dengan saldo projection.</p>
      </section>
    );
  }

  const explorerQuery = new URLSearchParams({ productId });
  if (batchId) explorerQuery.set("batchId", batchId);

  return (
    <section className="panel-card mt-6" data-testid="stock-story">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="section-kicker">Stock story read-only</p>
          <h2 className="section-title">Jejak movement fisik</h2>
          <p className="mt-2 text-sm text-slate-400">{productLabel}{batchLabel ? ` · ${batchLabel}` : ""}. Reservasi tidak ditampilkan sebagai movement fisik.</p>
        </div>
        <Link className="nav-link" href={`/ledger?${explorerQuery.toString()}`}>Lihat semua di Ledger Explorer</Link>
      </div>

      {result.rows.length === 0 ? (
        <p className="mt-5 text-sm text-slate-400">Belum ada movement ledger dalam scope ini.</p>
      ) : (
        <div className="mt-5 overflow-x-auto">
          <table className="min-w-[980px] w-full text-left text-sm">
            <thead className="text-xs uppercase tracking-wide text-slate-500">
              <tr><th className="px-3 py-3">Occurred</th><th className="px-3 py-3">Transaction</th><th className="px-3 py-3">Batch / bucket</th><th className="px-3 py-3">Delta</th><th className="px-3 py-3">Reason / channel</th><th className="px-3 py-3">Source / actor</th><th className="px-3 py-3">Recorded</th></tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {result.rows.map((row) => (
                <tr key={row.ledger_entry_id} className="align-top">
                  <td className="whitespace-nowrap px-3 py-3 text-xs text-slate-300">{date(row.occurred_at)}</td>
                  <td className="px-3 py-3"><Link className="font-mono text-xs text-emerald-300 underline" href={`/ledger/${row.transaction_id}?${explorerQuery.toString()}`}>{row.transaction_no}</Link><p className="mt-1 text-xs text-slate-500">{row.transaction_type_code}</p></td>
                  <td className="px-3 py-3 text-xs text-slate-300">{row.batch_code_snapshot} · {row.bucket_code}</td>
                  <td className={`px-3 py-3 font-mono font-semibold ${row.quantity_delta >= 0 ? "text-emerald-300" : "text-rose-300"}`}>{row.quantity_delta > 0 ? "+" : ""}{numberFormatter.format(row.quantity_delta)}</td>
                  <td className="px-3 py-3 text-xs text-slate-300">{row.reason_code_snapshot} · {row.channel_code_snapshot}</td>
                  <td className="px-3 py-3 text-xs text-slate-400">{sourceLabel(row.source_type_code, row.source_ref_snapshot)}<br />{row.process_name ?? row.actor_user_id ?? "Proses tepercaya"}</td>
                  <td className="whitespace-nowrap px-3 py-3 text-xs text-slate-500">{date(row.recorded_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <p className="mt-4 text-xs text-slate-500">Menampilkan maksimal {result.pageSize} movement pertama; pagination server-side tersedia di Ledger Explorer.</p>
    </section>
  );
}
