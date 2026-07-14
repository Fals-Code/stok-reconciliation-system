import { randomUUID } from "node:crypto";

import Link from "next/link";
import { redirect } from "next/navigation";

import { createStocktakeAction } from "@/app/stocktakes/actions";
import {
  STOCKTAKE_BUCKETS,
  STOCKTAKE_BUCKET_LABELS,
  STOCKTAKE_SCOPE_LABELS,
  STOCKTAKE_SCOPE_MODES,
  STOCKTAKE_TYPE_LABELS,
  STOCKTAKE_TYPES,
  STOCKTAKE_VISIBILITIES,
  STOCKTAKE_VISIBILITY_LABELS,
} from "@/lib/stocktakes/constants";
import { getStocktakeCreateOptions } from "@/lib/stocktakes/queries";

export const dynamic = "force-dynamic";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number) {
  return numberFormatter.format(Number(value));
}

function formatDate(value: string) {
  const date = new Date(`${value}T00:00:00+07:00`);

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
  }).format(date);
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-amber-300">
          Form stocktake tidak tersedia
        </p>
        <h1 className="mt-3 text-3xl font-semibold">
          Pilihan produk dan batch gagal dimuat.
        </h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <Link className="nav-link mt-6 inline-flex" href="/stocktakes">
          Kembali ke daftar stocktake
        </Link>
      </section>
    </main>
  );
}

export default async function NewStocktakePage({
  searchParams,
}: {
  searchParams: Promise<{
    idempotencyKey?: string;
    error?: string;
  }>;
}) {
  const params = await searchParams;

  if (
    !params.idempotencyKey ||
    !UUID_PATTERN.test(params.idempotencyKey)
  ) {
    const canonical = new URLSearchParams({
      idempotencyKey: randomUUID(),
    });

    redirect(`/stocktakes/new?${canonical.toString()}`);
  }

  let options;

  try {
    options = await getStocktakeCreateOptions();
  } catch (error) {
    return (
      <ConfigurationError
        message={error instanceof Error ? error.message : "Konfigurasi tidak valid."}
      />
    );
  }

  const { products, batches } = options;

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <header className="border-b border-white/10 bg-slate-950/90">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-5 px-5 py-4 lg:px-8">
          <div>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-emerald-300">
              Create Stocktake
            </p>
            <p className="mt-1 text-sm text-slate-400">
              Session configuration
            </p>
          </div>

          <Link className="nav-link border border-white/10" href="/stocktakes">
            Kembali ke daftar
          </Link>
        </div>
      </header>

      <div className="mx-auto max-w-6xl px-5 py-8 lg:px-8">
        <section>
          <p className="section-kicker">Sesi baru</p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
            Tentukan apa yang akan dihitung.
          </h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
            Pembuatan sesi hanya menyimpan konfigurasi Draft. Belum ada snapshot,
            count line, ledger entry, atau perubahan saldo.
          </p>
        </section>

        {params.error ? (
          <div className="mt-6 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-100">
            <p>{params.error}</p>
            <Link
              className="mt-3 inline-flex text-xs font-semibold text-rose-200 underline underline-offset-4"
              href="/stocktakes/new"
            >
              Mulai form baru dengan referensi baru
            </Link>
          </div>
        ) : null}

        <form action={createStocktakeAction} className="mt-8 space-y-6">
          <input
            type="hidden"
            name="idempotencyKey"
            value={params.idempotencyKey}
          />

          <section className="panel-card">
            <div>
              <p className="section-kicker">Identitas sesi</p>
              <h2 className="section-title">Informasi utama stocktake.</h2>
            </div>

            <div className="form-grid mt-6">
              <label className="field-label sm:col-span-2">
                Judul
                <input
                  name="title"
                  required
                  maxLength={200}
                  placeholder="Cycle count batch serum Juli 2026"
                />
              </label>

              <label className="field-label">
                Tipe
                <select name="stocktakeTypeCode" defaultValue="CYCLE" required>
                  {STOCKTAKE_TYPES.map((type) => (
                    <option key={type} value={type}>
                      {STOCKTAKE_TYPE_LABELS[type]}
                    </option>
                  ))}
                </select>
              </label>

              <label className="field-label">
                Visibility
                <select name="visibilityCode" defaultValue="BLIND" required>
                  {STOCKTAKE_VISIBILITIES.map((visibility) => (
                    <option key={visibility} value={visibility}>
                      {STOCKTAKE_VISIBILITY_LABELS[visibility]}
                    </option>
                  ))}
                </select>
              </label>

              <label className="field-label">
                Mode
                <input value="CONTINUOUS" readOnly aria-readonly="true" />
              </label>

              <label className="field-label">
                Rencana penghitungan
                <input name="plannedAt" type="datetime-local" />
              </label>

              <label className="field-label sm:col-span-2">
                Catatan
                <textarea
                  name="note"
                  rows={3}
                  maxLength={2000}
                  placeholder="Tujuan, area hitung, atau instruksi operasional."
                />
              </label>
            </div>
          </section>

          <section className="panel-card">
            <div>
              <p className="section-kicker">Scope</p>
              <h2 className="section-title">Pilih basis entity dan bucket.</h2>
              <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
                Pilihan produk hanya digunakan untuk mode Produk terpilih.
                Pilihan batch hanya digunakan untuk mode Batch terpilih.
              </p>
            </div>

            <div className="form-grid mt-6">
              <label className="field-label sm:col-span-2">
                Mode scope
                <select name="scopeMode" defaultValue="ALL_ACTIVE_INVENTORY">
                  {STOCKTAKE_SCOPE_MODES.map((mode) => (
                    <option key={mode} value={mode}>
                      {STOCKTAKE_SCOPE_LABELS[mode]}
                    </option>
                  ))}
                </select>
              </label>
            </div>

            <div className="mt-6">
              <p className="text-sm font-semibold text-slate-300">Buckets</p>
              <div className="mt-3 grid gap-3 sm:grid-cols-3">
                {STOCKTAKE_BUCKETS.map((bucket) => (
                  <label
                    key={bucket}
                    className="flex items-center gap-3 rounded-xl border border-white/10 bg-slate-950/45 p-4 text-sm text-slate-300"
                  >
                    <input
                      type="checkbox"
                      name="bucketCodes"
                      value={bucket}
                      defaultChecked
                    />
                    {STOCKTAKE_BUCKET_LABELS[bucket]}
                  </label>
                ))}
              </div>
            </div>

            <details className="mt-6 rounded-xl border border-white/10 bg-slate-950/35 p-4">
              <summary className="cursor-pointer text-sm font-semibold text-white">
                Pilih produk ({formatNumber(products.length)})
              </summary>
              <p className="mt-2 text-xs leading-5 text-slate-500">
                Digunakan hanya saat mode scope Produk terpilih.
              </p>

              <div className="mt-4 max-h-80 space-y-2 overflow-y-auto pr-2">
                {products.length === 0 ? (
                  <p className="text-sm text-slate-500">
                    Tidak ada produk yang dapat dipilih.
                  </p>
                ) : (
                  products.map((product) => (
                    <label
                      key={product.product_id}
                      className="flex items-start gap-3 rounded-xl border border-white/10 p-3 text-sm"
                    >
                      <input
                        className="mt-1"
                        type="checkbox"
                        name="productIds"
                        value={product.product_id}
                      />
                      <span>
                        <span className="font-semibold text-white">
                          {product.sku} Â· {product.name}
                        </span>
                        <span className="mt-1 block text-xs text-slate-500">
                          Sellable {formatNumber(product.sellable_qty)} Â·
                          Quarantine {formatNumber(product.quarantine_qty)} Â·
                          Damaged {formatNumber(product.damaged_qty)}
                          {!product.is_active ? " Â· Tidak aktif" : ""}
                        </span>
                      </span>
                    </label>
                  ))
                )}
              </div>
            </details>

            <details className="mt-4 rounded-xl border border-white/10 bg-slate-950/35 p-4">
              <summary className="cursor-pointer text-sm font-semibold text-white">
                Pilih batch ({formatNumber(batches.length)})
              </summary>
              <p className="mt-2 text-xs leading-5 text-slate-500">
                Digunakan hanya saat mode scope Batch terpilih.
              </p>

              <div className="mt-4 max-h-96 space-y-2 overflow-y-auto pr-2">
                {batches.length === 0 ? (
                  <p className="text-sm text-slate-500">
                    Tidak ada batch yang dapat dipilih.
                  </p>
                ) : (
                  batches.map((batch) => (
                    <label
                      key={batch.batch_id}
                      className="flex items-start gap-3 rounded-xl border border-white/10 p-3 text-sm"
                    >
                      <input
                        className="mt-1"
                        type="checkbox"
                        name="batchIds"
                        value={batch.batch_id}
                      />
                      <span>
                        <span className="font-semibold text-white">
                          {batch.sku} Â· {batch.product_name} Â· {batch.batch_code}
                        </span>
                        <span className="mt-1 block text-xs text-slate-500">
                          Exp {formatDate(batch.expiry_date)} Â· {batch.status_code}
                          {" Â· "}Sellable {formatNumber(batch.sellable_qty)}
                          {" Â· "}Quarantine {formatNumber(batch.quarantine_qty)}
                          {" Â· "}Damaged {formatNumber(batch.damaged_qty)}
                        </span>
                      </span>
                    </label>
                  ))
                )}
              </div>
            </details>
          </section>

          <section className="panel-card">
            <div>
              <p className="section-kicker">Inclusion rules</p>
              <h2 className="section-title">Atur entity khusus yang ikut dihitung.</h2>
            </div>

            <div className="mt-6 grid gap-3 sm:grid-cols-2">
              {[
                [
                  "includeZeroSystemBalance",
                  "Sertakan saldo sistem nol",
                  "Membuat line untuk entity yang ledger-nya bernilai nol.",
                ],
                [
                  "includeInactiveWithBalance",
                  "Sertakan produk tidak aktif bersaldo",
                  "Produk nonaktif hanya masuk bila masih memiliki saldo.",
                ],
                [
                  "includeBlockedBatches",
                  "Sertakan batch blocked",
                  "Batch blocked dapat masuk ke scope untuk verifikasi fisik.",
                ],
                [
                  "includeExpiredBatches",
                  "Sertakan batch expired",
                  "Batch kedaluwarsa tetap dapat dihitung sebagai fakta fisik.",
                ],
              ].map(([name, label, description]) => (
                <label
                  key={name}
                  className="flex items-start gap-3 rounded-xl border border-white/10 bg-slate-950/35 p-4"
                >
                  <input className="mt-1" type="checkbox" name={name} />
                  <span>
                    <span className="text-sm font-semibold text-white">
                      {label}
                    </span>
                    <span className="mt-1 block text-xs leading-5 text-slate-500">
                      {description}
                    </span>
                  </span>
                </label>
              ))}
            </div>
          </section>

          <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
            <Link
              className="nav-link border border-white/10 text-center"
              href="/stocktakes"
            >
              Batal
            </Link>
            <button className="primary-button" type="submit">
              Buat sesi Draft
            </button>
          </div>
        </form>
      </div>
    </main>
  );
}