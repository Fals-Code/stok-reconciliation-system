import { randomUUID } from "node:crypto";
import Link from "next/link";

import {
  createProductAction,
} from "@/app/products/actions";
import {
  Input,
  Textarea,
} from "@/components/ui";

import {
  Alert,
} from "@/components/ui/alert";
import {
  EmptyState,
} from "@/components/ui/empty-state";
import {
  StockWorkspaceControls,
  type ProductStatusFilter,
} from "@/app/products/stock-workspace-controls";
import {
  getProductMasterData,
  type ProductMasterRow,
} from "@/lib/supabase-rest";
import {
  getStocktakeList,
} from "@/lib/stocktakes/queries";
import type {
  StocktakeListItem,
  StocktakeStatus,
} from "@/lib/stocktakes/types";

const formatter = new Intl.NumberFormat("id-ID");

const NON_TERMINAL_STOCKTAKE_STATUSES = new Set<StocktakeStatus>([
  "DRAFT",
  "READY",
  "COUNTING",
  "REVIEW",
  "APPROVED",
  "POSTING",
  "EXCEPTION",
]);

const STOCKTAKE_STATUS_LABELS: Record<StocktakeStatus, string> = {
  DRAFT: "Belum Dimulai",
  READY: "Siap Dihitung",
  COUNTING: "Sedang Dihitung",
  REVIEW: "Perlu Diperiksa",
  APPROVED: "Siap Disimpan",
  POSTING: "Menyimpan Perubahan",
  POSTED: "Selesai",
  CANCELLED: "Dibatalkan",
  EXCEPTION: "Bermasalah",
};

function quantity(value: number) {
  return formatter.format(value);
}

function statusFrom(value?: string): ProductStatusFilter {
  const normalized = value?.toUpperCase();

  if (normalized === "ACTIVE" || normalized === "ARCHIVED") {
    return normalized;
  }

  return "ALL";
}

function matchesFilters(
  product: ProductMasterRow,
  query: string,
  status: ProductStatusFilter,
) {
  const matchesQuery =
    !query ||
    `${product.name} ${product.sku}`
      .toLowerCase()
      .includes(query.toLowerCase());
  const matchesStatus =
    status === "ALL" ||
    (status === "ACTIVE" ? product.is_active : !product.is_active);

  return matchesQuery && matchesStatus;
}

function retryPath(query: string, status: ProductStatusFilter) {
  const parameters = new URLSearchParams();

  if (query) {
    parameters.set("q", query);
  }

  if (status !== "ALL") {
    parameters.set("status", status);
  }

  const search = parameters.toString();

  return search ? `/products?${search}` : "/products";
}

function StockSummary({
  available,
  reserved,
  active,
}: {
  available: number;
  reserved: number;
  active: number;
}) {
  const items = [
    {
      label: "Tersedia",
      value: available,
      helper: "Unit yang dapat digunakan sekarang",
      accent: "bg-ui-primary",
      prominent: true,
    },
    {
      label: "Sudah Dipesan",
      value: reserved,
      helper: "Dialokasikan untuk pesanan",
      accent: "bg-ui-warning",
      prominent: false,
    },
    {
      label: "Produk Aktif",
      value: active,
      helper: "Produk yang sedang digunakan",
      accent: "bg-ui-text-muted",
      prominent: false,
    },
  ];

  return (
    <dl className="grid gap-3 sm:grid-cols-3">
      {items.map((item) => (
        <div
          className="relative overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-3.5"
          key={item.label}
        >
          <span
            aria-hidden="true"
            className={`absolute inset-y-2 left-0 w-0.5 rounded-full opacity-70 ${item.accent}`}
          />
          <dt className="text-xs font-medium text-ui-text-muted">
            {item.label}
          </dt>
          <dd
            className={
              item.prominent
                ? "ui-number mt-1 text-2xl font-semibold tracking-tight text-ui-primary"
                : "ui-number mt-1 text-2xl font-semibold tracking-tight text-ui-text"
            }
          >
            {quantity(item.value)}
          </dd>
          <dd className="mt-1 text-xs text-ui-text-muted">
            {item.helper}
          </dd>
        </div>
      ))}
    </dl>
  );
}
export function WorkspaceActions() {
  return (
    <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center sm:justify-end">
      <details className="group relative">
        <summary className="inline-flex min-h-[var(--ui-control-height)] cursor-pointer list-none items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary shadow-[var(--ui-shadow-sm)] hover:bg-ui-primary-hover [&::-webkit-details-marker]:hidden">
          Catat Perubahan
          <span
            aria-hidden="true"
            className="ml-1.5 text-[10px] text-ui-text-on-primary opacity-80 transition-transform group-open:rotate-180 motion-reduce:transition-none"
          >
            {"\u25BE"}
          </span>
        </summary>

        <div className="mt-2 grid w-full gap-1 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-2 shadow-[var(--ui-shadow-md)] sm:absolute sm:left-0 sm:z-20 sm:w-72">
          <Link
            className="rounded-[var(--ui-radius-sm)] px-3 py-3 text-sm font-semibold text-ui-text hover:bg-ui-surface-subtle"
            href="/receipts/new"
          >
            Barang Masuk
            <span className="mt-1 block text-xs font-normal leading-5 text-ui-text-muted">
              Catat barang yang benar-benar diterima gudang.
            </span>
          </Link>

          <Link
            className="rounded-[var(--ui-radius-sm)] px-3 py-3 text-sm font-semibold text-ui-text hover:bg-ui-surface-subtle"
            href="/manual-outbounds"
          >
            Barang Keluar
            <span className="mt-1 block text-xs font-normal leading-5 text-ui-text-muted">
              Catat penjualan langsung, bonus, promo, atau sampel.
            </span>
          </Link>

          <Link
            className="rounded-[var(--ui-radius-sm)] px-3 py-3 text-sm font-semibold text-ui-text hover:bg-ui-surface-subtle"
            href="/stock-disposals"
          >
            Barang Rusak / Kedaluwarsa
            <span className="mt-1 block text-xs font-normal leading-5 text-ui-text-muted">
              Catat pemusnahan berdasarkan Kode Batch.
            </span>
          </Link>
        </div>
      </details>

      <details className="group relative" id="product-form">
        <summary className="inline-flex min-h-[var(--ui-control-height)] cursor-pointer list-none items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text hover:border-ui-border-strong hover:bg-ui-surface-subtle [&::-webkit-details-marker]:hidden">
          Tambah Produk
        </summary>
        <div className="mt-2 w-full rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 shadow-[var(--ui-shadow-md)] sm:absolute sm:right-0 sm:z-20 sm:w-[30rem]">
          <h2 className="text-base font-semibold text-ui-text">Tambah Produk</h2>
          <p className="mt-1 text-sm leading-6 text-ui-text-muted">Membuat master produk tidak menambah atau mengurangi stok.</p>
          <form action={createProductAction} className="mt-4 grid gap-4">
            <input name="intentId" type="hidden" value={randomUUID()} />
            <label className="grid gap-2 text-sm font-semibold text-ui-text">Nama Produk<Input autoComplete="off" name="name" required /></label>
            <label className="grid gap-2 text-sm font-semibold text-ui-text">Ukuran (contoh: 1.5 L, 30 ml)<Input autoComplete="off" name="size" required /></label>
            <label className="grid gap-2 text-sm font-semibold text-ui-text">Deskripsi<Textarea name="description" rows={2} /></label>
            <label className="grid gap-2 text-sm font-semibold text-ui-text">Catatan audit<Textarea name="note" placeholder="Opsional. Contoh: produk baru dari katalog maklon." rows={2} /></label>
            <div className="flex justify-end"><button className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover" type="submit">Tambah Produk</button></div>
          </form>
        </div>
      </details>
<Link
        className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text hover:border-ui-border-strong hover:bg-ui-surface-subtle"
        href="/stocktakes/new"
      >
        Hitung Stok
      </Link>
    </div>
  );
}

function stocktakeProgress(stocktake: StocktakeListItem) {
  if (stocktake.status_code !== "COUNTING") {
    return null;
  }

  return `${quantity(stocktake.counted_line_count)} dari ${quantity(
    stocktake.line_count,
  )} produk sudah dihitung`;
}

function stocktakeActionLabel(status: StocktakeStatus) {
  const labels: Record<StocktakeStatus, string> = {
    DRAFT: "Siapkan Penghitungan",
    READY: "Mulai Menghitung",
    COUNTING: "Lanjutkan Menghitung",
    REVIEW: "Periksa Hasil",
    APPROVED: "Periksa Sebelum Simpan",
    POSTING: "Lihat Status",
    POSTED: "Lihat Hasil",
    CANCELLED: "Lihat Riwayat",
    EXCEPTION: "Periksa Masalah",
  };

  return labels[status];
}

function ContinueStocktake({
  stocktake,
}: {
  stocktake: StocktakeListItem;
}) {
  const progress = stocktakeProgress(stocktake);
  const progressPercent =
    stocktake.line_count > 0
      ? Math.min(
          100,
          Math.round(
            (stocktake.counted_line_count / stocktake.line_count) * 100,
          ),
        )
      : 0;

  return (
    <section
      aria-labelledby="stocktake-continuation-title"
      className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-4 sm:px-5"
    >
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <p className="text-xs font-semibold uppercase tracking-wide text-ui-primary">
              Hitung Stok
            </p>
            <span aria-hidden="true" className="text-ui-text-muted">
              {"\u00B7"}
            </span>
            <p className="text-sm font-medium text-ui-text-muted">
              {STOCKTAKE_STATUS_LABELS[stocktake.status_code]}
            </p>
          </div>

          <h2
            className="mt-1 text-base font-semibold text-ui-text"
            id="stocktake-continuation-title"
          >
            {stocktake.title}
          </h2>

          {progress ? (
            <div className="mt-2 max-w-xl">
              <p className="text-sm text-ui-text-muted">
                {progress}
              </p>
              <div
                aria-hidden="true"
                className="mt-2 h-1 overflow-hidden rounded-full bg-ui-surface-subtle"
              >
                <div
                  className="h-full rounded-full bg-ui-primary transition-[width] motion-reduce:transition-none"
                  style={{ width: `${progressPercent}%` }}
                />
              </div>
            </div>
          ) : null}
        </div>

        <Link
          className="inline-flex min-h-[var(--ui-control-height)] shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-primary hover:bg-ui-primary-subtle"
          href={`/stocktakes/${encodeURIComponent(stocktake.stocktake_id)}`}
        >
          {stocktakeActionLabel(stocktake.status_code)}
        </Link>
      </div>
    </section>
  );
}
function ProductCards({
  products,
  returnTo,
}: {
  products: ProductMasterRow[];
  returnTo: string;
}) {
  return (
    <div className="grid gap-3 md:hidden">
      {products.map((product) => (
        <article
          className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4"
          key={product.product_id}
        >
          <div className="min-w-0">
            <h2 className="truncate text-sm font-semibold text-ui-text">
              <Link
                className="hover:text-ui-primary hover:underline"
                href={`/products/${encodeURIComponent(product.product_id)}?returnTo=${encodeURIComponent(returnTo)}`}
              >
                {product.name}
              </Link>
            </h2>
            <p className="ui-code mt-1 text-xs text-ui-text-muted">
              {product.sku}
            </p>
          </div>

          <div className="mt-4 grid grid-cols-2 gap-x-4 gap-y-3">
            <div>
              <p className="text-xs text-ui-text-muted">Tersedia</p>
              <p className="ui-number mt-1 text-2xl font-semibold text-ui-primary">
                {quantity(product.available_qty)}
              </p>
            </div>
            <div>
              <p className="text-xs text-ui-text-muted">Layak Dijual</p>
              <p className="ui-number mt-1 text-sm font-medium text-ui-text">
                {quantity(product.sellable_qty)}
              </p>
            </div>
            <div>
              <p className="text-xs text-ui-text-muted">Sudah Dipesan</p>
              <p className="ui-number mt-1 text-sm font-medium text-ui-text">
                {quantity(product.reserved_qty)}
              </p>
            </div>
            <div>
              <p className="text-xs text-ui-text-muted">Batch</p>
              <p className="ui-number mt-1 text-sm font-medium text-ui-text">
                {quantity(product.batch_count)}
              </p>
            </div>
          </div>
        </article>
      ))}
    </div>
  );
}

function ProductTable({
  products,
  returnTo,
}: {
  products: ProductMasterRow[];
  returnTo: string;
}) {
  return (
    <div className="hidden md:block">
      <div className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-6 border-b border-ui-border bg-ui-surface-subtle px-5 py-2.5">
        <p className="text-xs font-semibold text-ui-text-muted">
          Produk
        </p>
        <p className="pr-7 text-xs font-semibold text-ui-text-muted">
          Tersedia
        </p>
      </div>

      {products.map((product) => (
        <Link
          className="group grid grid-cols-[minmax(0,1fr)_auto] items-center gap-6 border-b border-ui-border px-5 py-3.5 last:border-b-0 hover:bg-ui-surface-subtle"
          href={`/products/${encodeURIComponent(product.product_id)}?returnTo=${encodeURIComponent(returnTo)}`}
          key={product.product_id}
        >
          <div className="min-w-0">
            <h3 className="truncate text-sm font-semibold text-ui-text">
              {product.name}
            </h3>

            <p className="ui-code mt-1 text-xs text-ui-text-muted">
              {product.sku}
              {"\u00B7"} {product.is_active ? "Aktif" : "Tidak Aktif"}
            </p>

            <p className="mt-1.5 text-[0.8125rem] font-medium text-ui-text-muted">
              {quantity(product.sellable_qty)} layak dijual
              {"\u00B7"} {quantity(product.reserved_qty)} dipesan
              {"\u00B7"} {quantity(product.batch_count)} batch
            </p>
          </div>

          <div className="flex items-center gap-2.5">
            <div className="text-right">
              <p className="ui-number text-2xl font-semibold tracking-tight text-ui-primary">
                {quantity(product.available_qty)}
              </p>
              <p className="mt-0.5 text-xs font-medium text-ui-text-muted">
                tersedia
              </p>
            </div>

            <span
              aria-hidden="true"
              className="text-base text-ui-text-muted transition-transform group-hover:translate-x-0.5 motion-reduce:transition-none"
            >
              {"\u2192"}
            </span>
          </div>
        </Link>
      ))}
    </div>
  );
}
export function StockWorkspaceLoading() {
  return (
    <section aria-live="polite" className="mt-6">
      <p className="text-sm text-ui-text-muted">Memuat posisi stok</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-3">
        {["tersedia", "dipesan", "aktif"].map((item) => (
          <div
            className="h-28 animate-pulse rounded-[var(--ui-radius-lg)] bg-ui-surface-subtle motion-reduce:animate-none"
            key={item}
          />
        ))}
      </div>
      <div className="mt-6 h-64 animate-pulse rounded-[var(--ui-radius-lg)] bg-ui-surface-subtle motion-reduce:animate-none" />
    </section>
  );
}

export async function StockWorkspace({
  query: rawQuery,
  status: rawStatus,
}: {
  query?: string;
  status?: string;
}) {
  const query = rawQuery?.trim() ?? "";
  const status = statusFrom(rawStatus);
  const retryHref = retryPath(query, status);

  const [productResult, stocktakeResult] = await Promise.allSettled([
    getProductMasterData(),
    getStocktakeList(),
  ]);

  if (productResult.status === "rejected") {
    return (
      <Alert className="mt-6" title="Stok belum dapat dimuat" tone="danger">
        <p>Coba muat ulang. Kegagalan tidak mengubah stok.</p>
        <Link
          className="mt-3 inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-danger px-4 text-sm font-semibold text-ui-danger hover:bg-ui-danger-subtle"
          href={retryHref}
        >
          Muat Ulang
        </Link>
      </Alert>
    );
  }

  const { products: allProducts } = productResult.value;
  const products = allProducts.filter((product) =>
    matchesFilters(product, query, status),
  );

  const available = allProducts.reduce(
    (total, product) => total + product.available_qty,
    0,
  );
  const reserved = allProducts.reduce(
    (total, product) => total + product.reserved_qty,
    0,
  );
  const active = allProducts.filter((product) => product.is_active).length;
  const hasFilters = Boolean(query) || status !== "ALL";

  const continuation =
    stocktakeResult.status === "fulfilled"
      ? stocktakeResult.value.find((stocktake) =>
          NON_TERMINAL_STOCKTAKE_STATUSES.has(stocktake.status_code),
        ) ?? null
      : null;

  return (
    <section className="mt-6">
      <section aria-label="Ringkasan stok">
        <StockSummary
          active={active}
          available={available}
          reserved={reserved}
        />
      </section>

      {stocktakeResult.status === "rejected" ? (
        <Alert
          className="mt-6"
          title="Pekerjaan Hitung Stok belum dapat diperiksa"
          tone="warning"
        >
          Posisi stok tetap dapat digunakan. Buka Hitung Stok untuk memeriksa pekerjaan yang sedang berjalan.
        </Alert>
      ) : null}

      {continuation ? (
        <ContinueStocktake stocktake={continuation} />
      ) : null}

      <section className="mt-7" aria-labelledby="products-heading">
        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-start">
          <div className="min-w-0">
            <h2
              className="text-lg font-semibold text-ui-text"
              id="products-heading"
            >
              Produk
            </h2>
            <p className="mt-1 text-sm text-ui-text-muted">
              Cari produk dan periksa jumlah yang tersedia.
            </p>
          </div>

          <div className="w-full lg:w-auto lg:min-w-[34rem]">
            <StockWorkspaceControls
              key={`${query}:${status}`}
            />
          </div>
        </div>
        <div className="mt-3 overflow-hidden rounded-t-[var(--ui-radius-lg)] border border-b-0 border-ui-border bg-ui-surface">
          {products.length > 0 ? (
            <>
              <ProductCards products={products} returnTo={retryHref} />
              <ProductTable products={products} returnTo={retryHref} />
            </>
          ) : (
            <EmptyState
              action={
                hasFilters ? (
                  <Link
                    className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-text hover:border-ui-border-strong"
                    href="/products"
                  >
                    Hapus Filter
                  </Link>
                ) : undefined
              }
              description={
                hasFilters
                  ? "Ubah kata pencarian atau filter."
                  : "Belum ada produk yang tercatat."
              }
              title={
                hasFilters
                  ? "Tidak ada produk yang cocok"
                  : "Belum ada produk"
              }
            />
          )}
        </div>

        <div className="flex flex-col gap-2 rounded-b-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-2.5 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-xs font-medium text-ui-text-muted">
            Lihat juga
          </p>

          <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
            <Link
              className="inline-flex min-h-8 items-center gap-1.5 text-sm font-semibold text-ui-primary hover:underline"
              href="/stock-issues"
            >
              Masalah Stok
              <span aria-hidden="true">{"\u2192"}</span>
            </Link>

            <Link
              className="inline-flex min-h-8 items-center gap-1.5 text-sm font-semibold text-ui-primary hover:underline"
              href="/ledger"
            >
              Riwayat Stok
              <span aria-hidden="true">{"\u2192"}</span>
            </Link>
          </div>
        </div>
      </section>
    </section>
  );
}
