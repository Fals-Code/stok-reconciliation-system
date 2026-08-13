import Link from "next/link";

import {
  Alert,
  EmptyState,
  StatusBadge,
} from "@/components/ui";
import type {
  LedgerExplorerRow,
  ProductMasterRow,
} from "@/lib/supabase-rest";

const numberFormatter =
  new Intl.NumberFormat("id-ID");

const dateFormatter =
  new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    dateStyle: "medium",
    timeStyle: "short",
  });

function quantity(value: number) {
  return numberFormatter.format(
    Number(value),
  );
}

function signedQuantity(value: number) {
  return `${
    value > 0 ? "+" : ""
  }${quantity(value)} unit`;
}

function formatDate(value: string) {
  const date = new Date(value);

  return Number.isNaN(date.getTime())
    ? "-"
    : dateFormatter.format(date);
}

function transactionLabel(code: string) {
  if (code === "INITIAL_BALANCE") {
    return "Saldo Awal";
  }

  if (code === "RECEIPT") {
    return "Barang Masuk";
  }

  if (
    code === "MARKETPLACE_OUTBOUND" ||
    code === "OUTBOUND_MARKETPLACE"
  ) {
    return "Barang Keluar Marketplace";
  }

  if (
    code === "MANUAL_OUTBOUND" ||
    code === "OUTBOUND_MANUAL"
  ) {
    return "Barang Keluar Manual";
  }

  if (code.startsWith("RETURN")) {
    return "Retur";
  }

  if (code.startsWith("DISPOSAL")) {
    return "Barang Rusak / Kedaluwarsa";
  }

  if (code === "STOCKTAKE_ADJUSTMENT") {
    return "Penyesuaian Hasil Hitung";
  }

  if (code === "REVERSAL") {
    return "Pembatalan Transaksi";
  }

  return "Perubahan Stok";
}

function transactionHref(
  row: LedgerExplorerRow,
  productId: string,
) {
  const context = new URLSearchParams({
    productId,
  });

  return `/ledger/${
    row.transaction_id
  }?${context.toString()}`;
}

export function ProductSummary({
  historyHref,
  product,
  recentRows,
}: {
  historyHref: string;
  product: ProductMasterRow;
  recentRows: LedgerExplorerRow[] | null;
}) {
  return (
    <div className="grid gap-6">
      <section>
        <div className="flex flex-wrap items-center gap-3">
          <StatusBadge
            tone={
              product.is_active
                ? "selected"
                : "neutral"
            }
          >
            {product.is_active
              ? "Aktif"
              : "Tidak Aktif"}
          </StatusBadge>

          <span className="ui-code text-sm text-ui-text-muted">
            {product.sku}
          </span>
        </div>

        <dl className="mt-5 grid gap-4 border-y border-ui-border py-5 sm:grid-cols-3">
          <div>
            <dt className="text-sm text-ui-text-muted">
              Layak Dijual
            </dt>
            <dd className="ui-number mt-1 text-2xl font-semibold text-ui-text">
              {quantity(
                product.sellable_qty,
              )}
            </dd>
          </div>

          <div>
            <dt className="text-sm text-ui-text-muted">
              Sudah Dipesan
            </dt>
            <dd className="ui-number mt-1 text-2xl font-semibold text-ui-text">
              {quantity(
                product.reserved_qty,
              )}
            </dd>
          </div>

          <div>
            <dt className="text-sm font-semibold text-ui-text">
              Tersedia
            </dt>
            <dd className="ui-number mt-1 text-3xl font-semibold text-ui-primary">
              {quantity(
                product.available_qty,
              )}
            </dd>
          </div>
        </dl>

        <p className="mt-4 max-w-3xl text-sm leading-6 text-ui-text-muted">
          Tersedia{" "}
          {quantity(
            product.available_qty,
          )}{" "}
          unit karena{" "}
          {quantity(
            product.sellable_qty,
          )}{" "}
          unit Layak Dijual dikurangi{" "}
          {quantity(
            product.reserved_qty,
          )}{" "}
          unit Sudah Dipesan. Barang yang
          dipesan belum keluar secara fisik.
        </p>

        {product.description ? (
          <p className="mt-3 max-w-3xl text-sm leading-6 text-ui-text-muted">
            {product.description}
          </p>
        ) : null}
      </section>

      <section
        aria-labelledby="recent-stock-changes"
        className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5"
      >
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2
              className="text-lg font-semibold text-ui-text"
              id="recent-stock-changes"
            >
              Perubahan Terbaru
            </h2>
            <p className="mt-1 text-sm text-ui-text-muted">
              Lima perubahan stok terbaru
              untuk produk ini.
            </p>
          </div>

          <Link
            className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
            href={historyHref}
          >
            Lihat semua riwayat
          </Link>
        </div>

        {recentRows === null ? (
          <Alert
            className="mt-4"
            title="Riwayat terbaru belum dapat dimuat"
            tone="warning"
          >
            Posisi stok tetap berasal dari
            data produk. Muat ulang halaman
            untuk mencoba membaca riwayat.
          </Alert>
        ) : recentRows.length === 0 ? (
          <EmptyState
            className="mt-4"
            description="Belum ada perubahan stok pada ledger untuk produk ini."
            title="Belum ada riwayat stok"
          />
        ) : (
          <div className="mt-4 divide-y divide-ui-border">
            {recentRows.map((row) => (
              <article
                className="py-4 first:pt-0 last:pb-0"
                key={row.ledger_entry_id}
              >
                <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <p className="text-sm font-semibold text-ui-text">
                      {transactionLabel(
                        row.transaction_type_code,
                      )}
                    </p>

                    <p className="mt-1 text-xs text-ui-text-muted">
                      Kode Batch{" "}
                      {row.batch_code_snapshot}
                      {" · "}
                      {formatDate(
                        row.occurred_at,
                      )}
                    </p>
                  </div>

                  <p
                    className={
                      row.quantity_delta >= 0
                        ? "ui-number text-sm font-semibold text-ui-primary"
                        : "ui-number text-sm font-semibold text-ui-danger"
                    }
                  >
                    {signedQuantity(
                      row.quantity_delta,
                    )}
                  </p>
                </div>

                <Link
                  className="mt-2 inline-flex text-sm font-semibold text-ui-primary hover:underline"
                  href={transactionHref(
                    row,
                    product.product_id,
                  )}
                >
                  Lihat Detail
                </Link>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
