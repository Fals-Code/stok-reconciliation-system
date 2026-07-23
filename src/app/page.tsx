import Link from "next/link";

import PageSectionNav from "@/app/app-shell/page-section-nav";

import { postReceiptAction } from "@/app/actions";
import {
  type BatchInventory,
  getDashboardData,
  type ProductInventory,
  type StockLedgerEntry,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number) {
  return numberFormatter.format(value);
}

function formatDate(value: string | null, includeTime = false) {
  if (!value) return "—";

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
    ...(includeTime
      ? { hour: "2-digit", minute: "2-digit", hour12: false }
      : {}),
  }).format(new Date(value));
}

function defaultDateTimeLocal() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date());

  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

type PillTone = "success" | "warning" | "danger" | "neutral";

type StatusBadge = {
  label: string;
  tone: PillTone;
};

function inventoryStatus(product: ProductInventory): StatusBadge {
  if (product.available_qty <= 0) return { label: "Habis", tone: "danger" };
  if (product.available_qty <= 10) return { label: "Menipis", tone: "warning" };
  return { label: "Aman", tone: "success" };
}

function expiryStatus(batch: BatchInventory): StatusBadge {
  const today = new Date();
  const expiry = new Date(`${batch.expiry_date}T00:00:00+07:00`);
  const days = Math.ceil((expiry.getTime() - today.getTime()) / 86_400_000);

  if (days < 0) return { label: "Kedaluwarsa", tone: "danger" };
  if (days <= 30) return { label: `${days} hari`, tone: "danger" };
  if (days <= 90) return { label: `${days} hari`, tone: "warning" };
  return { label: `${days} hari`, tone: "neutral" };
}

function quantityTone(entry: StockLedgerEntry) {
  return entry.quantity_delta >= 0 ? "text-emerald-300" : "text-rose-300";
}

function Pill({
  label,
  tone,
}: {
  label: string;
  tone: PillTone;
}) {
  const tones = {
    success: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
    warning: "border-amber-400/20 bg-amber-400/10 text-amber-200",
    danger: "border-rose-400/20 bg-rose-400/10 text-rose-200",
    neutral: "border-white/10 bg-white/[0.04] text-slate-300",
  };

  return (
    <span className={`inline-flex rounded-full border px-2.5 py-1 text-xs ${tones[tone]}`}>
      {label}
    </span>
  );
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-amber-300">
          Konfigurasi diperlukan
        </p>
        <h1 className="mt-3 text-3xl font-semibold">Dashboard belum terhubung ke Supabase.</h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <div className="mt-7 rounded-2xl border border-white/10 bg-slate-950/70 p-5 font-mono text-sm leading-7 text-slate-300">
          <div>npx supabase status -o env</div>
          <div>Copy-Item .env.example .env.local</div>
          <div>Isi SUPABASE_SECRET_KEY di .env.local</div>
          <div>npm run dev</div>
        </div>
      </section>
    </main>
  );
}

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{
    success?: string;
    error?: string;
    batchId?: string;
  }>;
}) {
  const feedback = await searchParams;
  let data;

  try {
    data = await getDashboardData();
  } catch (error) {
    return (
      <ConfigurationError
        message={error instanceof Error ? error.message : "Konfigurasi tidak valid."}
      />
    );
  }

  const { products, batches, receiptBatches, ledger } = data;
  const receiptOptions = receiptBatches.map((batch) => ({
    ...batch,
    sku: batch.product_sku,
  }));
  const selectedBatchId = feedback.batchId?.trim() || null;
  const selectedBatch = selectedBatchId
    ? batches.find((batch) => batch.batch_id === selectedBatchId) ?? null
    : null;
  const sellable = products.reduce((sum, product) => sum + product.sellable_qty, 0);
  const reserved = products.reduce((sum, product) => sum + product.reserved_qty, 0);
  const available = products.reduce((sum, product) => sum + product.available_qty, 0);
  const riskBatches = batches.filter((batch) => {
    const status = expiryStatus(batch);
    return status.tone === "warning" || status.tone === "danger";
  }).length;
  const currentDateTime = defaultDateTimeLocal();

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <PageSectionNav
        items={[
          { href: "#overview", label: "Ringkasan" },
          { href: "#actions", label: "Transaksi" },
          { href: "#inventory", label: "Inventory" },
          { href: "#ledger", label: "Ledger" },
        ]}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section id="overview" className="scroll-mt-24">
          <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="font-mono text-xs uppercase tracking-[0.2em] text-slate-500">
                Dashboard operasional
              </p>
              <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
                Stok yang bisa dijelaskan, bukan sekadar dihitung.
              </h1>
              <p className="mt-3 max-w-2xl text-sm leading-6 text-slate-400 sm:text-base">
                Posisi produk, kondisi batch, penerimaan, outbound FEFO, dan ledger
                berada dalam satu alur yang dapat diaudit.
              </p>
            </div>
            <div className="rounded-2xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm text-slate-400">
              Update terakhir: {formatDate(new Date().toISOString(), true)} WIB
            </div>
          </div>

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              ["Sellable", sellable, "Total fisik layak jual"],
              ["Reserved", reserved, "Belum keluar fisik"],
              ["Available", available, "Dapat dialokasikan"],
              ["Batch berisiko", riskBatches, "≤ 90 hari / expired"],
            ].map(([label, value, description]) => (
              <article key={label} className="metric-card">
                <p className="text-sm text-slate-400">{label}</p>
                <p className="mt-3 text-3xl font-semibold text-white">
                  {formatNumber(Number(value))}
                </p>
                <p className="mt-2 text-xs text-slate-500">{description}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="actions" className="mt-10 scroll-mt-24">
          <div className="mb-5 flex items-end justify-between gap-4">
            <div>
              <p className="section-kicker">Posting transaksi</p>
              <h2 className="section-title">Gerakkan stok melalui jalur resmi.</h2>
            </div>
            <span className="hidden rounded-full border border-white/10 px-3 py-1 text-xs text-slate-500 sm:inline-flex">
              Atomic RPC + idempotency
            </span>
          </div>

          {feedback.success ? (
            <div className="mb-5 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-200">
              {feedback.success}
            </div>
          ) : null}
          {feedback.error ? (
            <div className="mb-5 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-200">
              {feedback.error}
            </div>
          ) : null}

          <div className="grid gap-5 xl:grid-cols-2">
            <form action={postReceiptAction} className="panel-card">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="section-kicker">Inbound</p>
                  <h3 className="mt-1 text-xl font-semibold">Penerimaan maklon</h3>
                </div>
                <Pill label="SELLABLE +" tone="success" />
              </div>
              <div className="form-grid mt-6">
                <label className="field-label">
                  Referensi penerimaan
                  <input name="sourceRef" required placeholder="SJ-MAKLON-2026-001" />
                </label>
                <label className="field-label">
                  Waktu diterima
                  <input name="occurredAt" type="datetime-local" defaultValue={currentDateTime} required />
                </label>
                <label className="field-label sm:col-span-2">
                  Produk dan batch
                  <select name="batchSelection" required defaultValue="">
                    <option value="" disabled>Pilih batch terdaftar</option>
                    {receiptOptions.map((batch) => (
                      <option key={batch.batch_id} value={`${batch.product_id}:${batch.batch_id}`}>
                        {batch.sku} · {batch.batch_code} · exp {batch.expiry_date}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field-label">
                  Quantity
                  <input name="quantity" type="number" min="1" step="1" required placeholder="10" />
                </label>
                <label className="field-label">
                  Catatan
                  <input name="note" placeholder="Opsional" />
                </label>
              </div>
              <button className="primary-button mt-6" type="submit">Post receipt</button>
            </form>

            <article className="panel-card">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="section-kicker">Outbound</p>
                  <h3 className="mt-1 text-xl font-semibold">
                    Barang Keluar dengan preview FEFO
                  </h3>
                </div>
                <Pill label="PREVIEW WAJIB" tone="warning" />
              </div>
              <p className="mt-5 text-sm leading-6 text-slate-400">
                Pengeluaran manual tidak lagi diposting langsung dari
                dashboard. Tinjau alokasi batch, reserved stock, dan saldo
                setelah transaksi sebelum konfirmasi final.
              </p>
              <Link
                className="primary-button mt-6 inline-flex"
                href="/manual-outbounds"
              >
                Buka workflow Barang Keluar
              </Link>
            </article>
          </div>
        </section>

        <section id="inventory" className="mt-10 scroll-mt-24">
          <div>
            <p className="section-kicker">Inventory position</p>
            <h2 className="section-title">Produk dan batch aktif.</h2>
          </div>

          {selectedBatchId ? (
            <div
              className={[
                "mt-5 rounded-2xl border px-5 py-4 text-sm",
                selectedBatch
                  ? "border-emerald-400/25 bg-emerald-400/[0.07] text-emerald-100"
                  : "border-amber-400/25 bg-amber-400/[0.07] text-amber-100",
              ].join(" ")}
              role="status"
            >
              {selectedBatch
                ? `Batch ${selectedBatch.batch_code} dipilih dari Notification Center.`
                : "Batch sumber notifikasi tidak ditemukan dalam organisasi aktif."}
            </div>
          ) : null}

          <div className="mt-5 overflow-hidden rounded-2xl border border-white/10 bg-white/[0.025]">
            <div className="overflow-x-auto">
              <table>
                <thead>
                  <tr>
                    <th>Produk</th>
                    <th>Sellable</th>
                    <th>Reserved</th>
                    <th>Available</th>
                    <th>Quarantine</th>
                    <th>Damaged</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {products.map((product) => {
                    const status = inventoryStatus(product);
                    return (
                      <tr key={product.product_id}>
                        <td>
                          <div className="font-medium text-white">{product.name}</div>
                          <div className="mt-1 font-mono text-xs text-slate-500">{product.sku}</div>
                        </td>
                        <td>{formatNumber(product.sellable_qty)}</td>
                        <td>{formatNumber(product.reserved_qty)}</td>
                        <td className="font-semibold text-white">{formatNumber(product.available_qty)}</td>
                        <td>{formatNumber(product.quarantine_qty)}</td>
                        <td>{formatNumber(product.damaged_qty)}</td>
                        <td><Pill label={status.label} tone={status.tone} /></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>

          <div className="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
            {batches.map((batch) => {
              const status = expiryStatus(batch);
              return (
                <article
                  className={[
                    "batch-card scroll-mt-28",
                    selectedBatchId === batch.batch_id
                      ? "border-emerald-400/45 bg-emerald-400/[0.08] ring-1 ring-emerald-400/20"
                      : "",
                  ].join(" ")}
                  id={`batch-${batch.batch_id}`}
                  key={batch.batch_id}
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="font-mono text-xs text-emerald-300">{batch.batch_code}</p>
                      <h3 className="mt-2 font-medium text-white">{batch.product_name}</h3>
                    </div>
                    <Pill label={status.label} tone={status.tone} />
                  </div>
                  <dl className="mt-5 grid grid-cols-2 gap-4 text-sm">
                    <div>
                      <dt className="text-slate-500">Sellable</dt>
                      <dd className="mt-1 text-xl font-semibold text-white">{formatNumber(batch.sellable_qty)}</dd>
                    </div>
                    <div>
                      <dt className="text-slate-500">Expiry</dt>
                      <dd className="mt-1 text-slate-300">{formatDate(batch.expiry_date)}</dd>
                    </div>
                    <div>
                      <dt className="text-slate-500">First received</dt>
                      <dd className="mt-1 text-slate-300">{formatDate(batch.received_first_at)}</dd>
                    </div>
                    <div>
                      <dt className="text-slate-500">Status</dt>
                      <dd className="mt-1 text-slate-300">{batch.status_code}</dd>
                    </div>
                  </dl>
                </article>
              );
            })}
          </div>
        </section>

        <section id="ledger" className="mt-10 scroll-mt-24 pb-12">
          <div className="flex items-end justify-between gap-5">
            <div>
              <p className="section-kicker">Immutable ledger</p>
              <h2 className="section-title">Jejak transaksi terbaru.</h2>
            </div>
            <span className="font-mono text-xs text-slate-500">Last {ledger.length} entries</span>
          </div>

          <div className="mt-5 overflow-hidden rounded-2xl border border-white/10 bg-white/[0.025]">
            <div className="overflow-x-auto">
              <table>
                <thead>
                  <tr>
                    <th>Seq</th>
                    <th>Waktu</th>
                    <th>Transaksi</th>
                    <th>Produk / batch</th>
                    <th>Reason</th>
                    <th>Bucket</th>
                    <th className="text-right">Delta</th>
                  </tr>
                </thead>
                <tbody>
                  {ledger.map((entry) => (
                    <tr key={entry.ledger_entry_id}>
                      <td className="font-mono text-xs text-slate-500">#{entry.ledger_seq}</td>
                      <td className="whitespace-nowrap">{formatDate(entry.occurred_at, true)}</td>
                      <td>
                        <div className="font-medium text-white">{entry.transaction_no}</div>
                        <div className="mt-1 text-xs text-slate-500">{entry.source_ref_snapshot}</div>
                      </td>
                      <td>
                        <div>{entry.product_sku_snapshot}</div>
                        <div className="mt-1 font-mono text-xs text-slate-500">{entry.batch_code_snapshot}</div>
                      </td>
                      <td>{entry.reason_code_snapshot}</td>
                      <td><Pill label={entry.bucket_code} tone="neutral" /></td>
                      <td className={`text-right font-mono font-semibold ${quantityTone(entry)}`}>
                        {entry.quantity_delta > 0 ? "+" : ""}{formatNumber(entry.quantity_delta)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
