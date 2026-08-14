import Link from "next/link";

import {
  Alert,
  EmptyState,
  StatusBadge,
} from "@/components/ui";
import type {
  LedgerExplorerRow,
  ProductMasterRow,
  ProductStockExplanation,
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


function explanationHref(summaryHref: string) {
  const [pathname, query = ""] = summaryHref.split("?");
  const params = new URLSearchParams(query);
  params.set("explainStock", "1");
  return `${pathname}?${params.toString()}`;
}

function movementLabel(code: string) {
  if (code === "UNCLASSIFIED_LEDGER_ENTRY") return "Catatan stok belum terklasifikasi";
  return transactionLabel(code);
}

function movementContextLabel(group: ProductStockExplanation["groupedMovements"][number]) {
  if (group.transactionTypeCode === "UNCLASSIFIED_LEDGER_ENTRY") return "Detail transaksi belum tersedia; jumlah stok fisik tetap dihitung.";
  const channel = group.channelCode === "SHOPEE" ? "Shopee" : group.channelCode === "TIKTOK_SHOP" ? "TikTok Shop" : group.channelCode === "MANUAL" ? "Catatan manual" : group.channelCode === "SYSTEM" ? "Sistem" : "Catatan stok";
  return channel;
}

function groupHref(productId: string, group: ProductStockExplanation["groupedMovements"][number]) {
  const query = new URLSearchParams({ productId, transactionType: group.transactionTypeCode });
  if (group.reasonCode) query.set("reason", group.reasonCode);
  if (group.channelCode) query.set("channel", group.channelCode);
  if (group.sourceTypeCode) query.set("sourceType", group.sourceTypeCode);
  return `/ledger?${query.toString()}`;
}
export function ProductSummary({
  explainStock,
  historyHref,
  product,
  recentRows,
  stockExplanation,
  summaryHref,
}: {
  explainStock: boolean;
  historyHref: string;
  product: ProductMasterRow;
  recentRows: LedgerExplorerRow[] | null;
  stockExplanation: ProductStockExplanation | null;
  summaryHref: string;
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
        aria-labelledby="stock-explanation"
        className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5"
      >
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h2 className="text-lg font-semibold text-ui-text" id="stock-explanation">Jelaskan Stok</h2>
            <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
              Bukti dihitung sampai perubahan terakhir, lalu dibandingkan dengan posisi sistem. Membuka rincian tidak mengubah stok.
            </p>
          </div>
          {!explainStock ? (
            <Link className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline" href={explanationHref(summaryHref)}>
              Jelaskan Stok
            </Link>
          ) : null}
        </div>

        {explainStock && stockExplanation === null ? (
          <Alert className="mt-4" title="Penjelasan stok belum dapat dimuat" tone="warning">
            Kegagalan membaca bukti tidak mengubah stok. Muat ulang untuk mencoba kembali.
          </Alert>
        ) : null}

        {stockExplanation ? (
          <div className="mt-4 grid gap-4">
            <p className="text-sm text-ui-text-muted">Sudah Dipesan tidak dihitung sebagai pergerakan fisik.</p>
            <dl className="grid gap-3 sm:grid-cols-3">
              {[
                ["Layak Dijual", stockExplanation.ledger.sellableQty, stockExplanation.projection.sellableQty, stockExplanation.comparison.sellableMatches],
                ["Karantina", stockExplanation.ledger.quarantineQty, stockExplanation.projection.quarantineQty, stockExplanation.comparison.quarantineMatches],
                ["Rusak", stockExplanation.ledger.damagedQty, stockExplanation.projection.damagedQty, stockExplanation.comparison.damagedMatches],
              ].map(([label, ledger, projection, matches]) => (
                <div className="rounded-[var(--ui-radius-md)] bg-ui-surface-subtle p-3" key={String(label)}>
                  <dt className="text-sm font-semibold text-ui-text">{label}</dt>
                  <dd className="mt-1 text-sm text-ui-text-muted">Catatan Stok {quantity(Number(ledger))} · Posisi Sistem {quantity(Number(projection))}</dd>
                  <p className={matches ? "mt-1 text-xs text-ui-text-muted" : "mt-1 text-xs font-semibold text-ui-danger"}>{matches ? "Sama" : "Selisih — perlu ditelusuri"}</p>
                </div>
              ))}
            </dl>
            <p className="text-sm text-ui-text-muted">Total Stok Fisik: Catatan Stok {quantity(stockExplanation.ledger.onHandQty)} · Posisi Sistem {quantity(stockExplanation.projection.onHandQty)}. Tersedia {quantity(stockExplanation.projection.availableQty)} = Layak Dijual {quantity(stockExplanation.projection.sellableQty)} − Sudah Dipesan {quantity(stockExplanation.projection.reservedQty)}.</p>
            {stockExplanation.groupedMovements.length === 0 ? (
              <EmptyState description="Ledger belum memiliki pergerakan fisik untuk produk ini. Posisi nol adalah keadaan normal; posisi fisik selain nol ditandai sebagai selisih di atas." title="Belum ada bukti pergerakan" />
            ) : (
              <div className="divide-y divide-ui-border">
                {stockExplanation.groupedMovements.map((group) => (
                  <article className="flex flex-col gap-2 py-3 sm:flex-row sm:items-start sm:justify-between" key={`${group.transactionTypeCode}:${group.reasonCode}:${group.channelCode}:${group.sourceTypeCode}`}>
                    <div><p className="text-sm font-semibold text-ui-text">{movementLabel(group.transactionTypeCode)}</p><p className="mt-1 text-xs text-ui-text-muted">{movementContextLabel(group)}</p></div>
                    <div className="text-sm text-ui-text-muted sm:text-right"><p>Layak {signedQuantity(group.sellableDelta)} · Karantina {signedQuantity(group.quarantineDelta)} · Rusak {signedQuantity(group.damagedDelta)}</p><p className="font-semibold text-ui-text">Total fisik {signedQuantity(group.onHandDelta)}</p><Link className="mt-1 inline-flex font-semibold text-ui-primary hover:underline" href={groupHref(product.product_id, group)}>Lihat rinciannya</Link></div>
                  </article>
                ))}
              </div>
            )}
            <Link className="inline-flex text-sm font-semibold text-ui-primary hover:underline" href={historyHref}>Buka Riwayat Produk</Link>
          </div>
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
