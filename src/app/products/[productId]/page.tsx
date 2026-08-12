import { randomUUID } from "node:crypto";
import Link from "next/link";
import {
  notFound,
} from "next/navigation";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  archiveProductAction,
  reactivateProductAction,
  updateProductAction,
} from "@/app/products/actions";
import {
  ProductBatches,
} from "@/app/products/[productId]/product-batches";
import {
  ProductHistory,
} from "@/app/products/[productId]/product-history";
import {
  ProductSummary,
} from "@/app/products/[productId]/product-summary";
import {
  Alert,
  Input,
  Textarea,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  safeInternalRoute,
} from "@/lib/safe-internal-route";
import {
  getLedgerStockStoryPage,
  getProductBatchMasterData,
  getProductMasterData,
} from "@/lib/supabase-rest";

export const dynamic =
  "force-dynamic";

type SearchParams =
  Record<
    string,
    string | string[] | undefined
  >;

type ProductTab =
  | "summary"
  | "batches"
  | "history";

function first(
  value: SearchParams[string],
) {
  return Array.isArray(value)
    ? value[0]
    : value;
}

function tabFrom(
  value?: string,
): ProductTab {
  if (value === "batches") {
    return "batches";
  }

  if (value === "history") {
    return "history";
  }

  return "summary";
}

function tabHref({
  productId,
  returnTo,
  tab,
}: {
  productId: string;
  returnTo: string;
  tab: ProductTab;
}) {
  const query =
    new URLSearchParams();

  if (tab !== "summary") {
    query.set("tab", tab);
  }

  if (returnTo !== "/products") {
    query.set(
      "returnTo",
      returnTo,
    );
  }

  const encoded =
    query.toString();

  return `/products/${encodeURIComponent(
    productId,
  )}${encoded ? `?${encoded}` : ""}`;
}

export default async function ProductDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{
    productId: string;
  }>;
  searchParams:
    Promise<SearchParams>;
}) {
  const [
    { productId },
    query,
    session,
  ] = await Promise.all([
    params,
    searchParams,
    requireAdminSession(),
  ]);

  let master;

  try {
    master =
      await getProductMasterData(
        session.profile
          .organization_id,
      );
  } catch {
    return (
      <AppShell
        profile={
          session.profile
        }
      >
        <div className="mx-auto w-full max-w-[1120px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader
            description="Data produk belum dapat dimuat. Kondisi gagal tidak mengubah stok."
            title="Detail Produk"
          />

          <Alert
            className="mt-6"
            title="Produk belum dapat dimuat"
            tone="warning"
          >
            Muat ulang halaman sebelum
            melakukan perubahan pada
            master produk.
          </Alert>
        </div>
      </AppShell>
    );
  }

  const product =
    master.products.find(
      (row) =>
        row.product_id ===
        productId,
    );

  if (!product) {
    notFound();
  }

  const returnTo = safeInternalRoute(
    first(query.returnTo),
    "/products",
    { allowedPathnames: ["/products"] },
  );

  const tab =
    tabFrom(
      first(query.tab),
    );

  const success =
    first(query.success);

  const error =
    first(query.error);

  const summaryHref =
    tabHref({
      productId,
      returnTo,
      tab: "summary",
    });

  const batchesHref =
    tabHref({
      productId,
      returnTo,
      tab: "batches",
    });

  const historyHref =
    tabHref({
      productId,
      returnTo,
      tab: "history",
    });

  let recentRows = null;

  if (tab === "summary") {
    try {
      const recent =
        await getLedgerStockStoryPage({
          productId,
          pageSize: 10,
        });

      recentRows =
        recent.rows.slice(0, 5);
    } catch {
      recentRows = null;
    }
  }

  let batchData = null;

  if (tab === "batches") {
    try {
      batchData =
        await getProductBatchMasterData(
          session.profile
            .organization_id,
        );
    } catch {
      batchData = null;
    }
  }

  const audits =
    master.audits.filter(
      (audit) =>
        audit.product_id ===
        product.product_id,
    );

  const lockedSize =
    product.has_authoritative_history &&
    product.size_ml !== null;

  return (
    <AppShell
      profile={session.profile}
    >
      <div className="mx-auto w-full max-w-[1120px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          action={
            <Link
              className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
              href={returnTo}
            >
              Kembali ke Stok
            </Link>
          }
          description={`${product.sku} · ${
            product.is_active
              ? "Aktif"
              : "Tidak Aktif"
          }`}
          eyebrow="Stok"
          title={product.name}
        />

        {success ? (
          <Alert
            className="mt-6"
            title="Perubahan tersimpan"
            tone="success"
          >
            {success}
          </Alert>
        ) : null}

        {error ? (
          <Alert
            className="mt-6"
            title="Perubahan belum tersimpan"
            tone="warning"
          >
            {error}
          </Alert>
        ) : null}

        <nav
          aria-label="Detail Produk"
          className="mt-6 flex max-w-full gap-1 overflow-x-auto border-b border-ui-border"
        >
          {[
            [
              "summary",
              "Ringkasan",
              summaryHref,
            ],
            [
              "batches",
              "Batch",
              batchesHref,
            ],
            [
              "history",
              "Riwayat",
              historyHref,
            ],
          ].map(
            ([
              value,
              label,
              href,
            ]) => (
              <Link
                aria-current={
                  tab === value
                    ? "page"
                    : undefined
                }
                className={
                  tab === value
                    ? "shrink-0 border-b-2 border-ui-primary px-4 py-3 text-sm font-semibold text-ui-primary"
                    : "shrink-0 border-b-2 border-transparent px-4 py-3 text-sm font-semibold text-ui-text-muted hover:text-ui-text"
                }
                href={href}
                key={value}
              >
                {label}
              </Link>
            ),
          )}
        </nav>

        <section className="mt-6">
          {tab === "summary" ? (
            <ProductSummary
              historyHref={
                historyHref
              }
              product={product}
              recentRows={
                recentRows
              }
            />
          ) : null}

          {tab === "batches" ? (
            batchData ? (
              <ProductBatches
                batchQuery={first(
                  query.batchQ,
                )}
                batchStatus={first(
                  query.batchStatus,
                )}
                batches={batchData.batches.filter(
                  (batch) =>
                    batch.product_id ===
                    product.product_id,
                )}
                product={product}
                returnTo={returnTo}
              />
            ) : (
              <Alert
                title="Batch belum dapat dimuat"
                tone="warning"
              >
                Data Produk tetap
                tersedia, tetapi daftar
                Batch belum dapat dibaca.
              </Alert>
            )
          ) : null}

          {tab === "history" ? (
            <ProductHistory
              params={query}
              productId={
                product.product_id
              }
              productSku={
                product.sku
              }
              returnTo={returnTo}
            />
          ) : null}
        </section>

        {tab === "summary" ? (
          <div className="mt-8 grid gap-4">
            <details className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5">
              <summary className="cursor-pointer text-sm font-semibold text-ui-text">
                Pengaturan Produk
              </summary>

              <p className="mt-3 text-sm leading-6 text-ui-text-muted">
                Mengubah master Produk
                tidak mengedit ledger atau
                snapshot transaksi lama.
              </p>

              {lockedSize ? (
                <Alert
                  className="mt-4"
                  title="Ukuran produk sudah dikunci"
                  tone="warning"
                >
                  Produk sudah memiliki histori authoritative.
                  Ukuran dan SKU tidak dapat diubah manual.
                  Nama dan deskripsi masih dapat diperbarui.
                </Alert>
              ) : null}

              <form
                action={
                  updateProductAction
                }
                className="mt-4 grid gap-4 sm:grid-cols-2"
              >
                <input
                  name="intentId"
                  type="hidden"
                  value={randomUUID()}
                />
                <input
                  name="productId"
                  type="hidden"
                  value={
                    product.product_id
                  }
                />
                <input
                  name="rowVersion"
                  type="hidden"
                  value={
                    product.row_version
                  }
                />

                <label className="grid gap-2 text-sm font-semibold text-ui-text">
                  SKU
                  <Input disabled readOnly value={product.sku} />
                  <span className="text-xs font-normal text-ui-text-muted">
                    Dibuat otomatis dari nama dan ukuran; tidak dapat diedit manual.
                  </span>
                </label>

                <label className="grid gap-2 text-sm font-semibold text-ui-text">
                  Nama Produk
                  <Input
                    defaultValue={
                      product.name
                    }
                    name="name"
                    required
                  />
                </label>
                <label className="grid gap-2 text-sm font-semibold text-ui-text">
                  Ukuran
                  {lockedSize ? (
                    <>
                      <input name="size" type="hidden" value={product.size_ml ?? ""} />
                      <Input disabled readOnly value={`${product.size_ml} ml`} />
                    </>
                  ) : (
                    <Input defaultValue={product.size_ml ?? ""} inputMode="decimal" name="size" placeholder="Contoh: 30 ml atau 1,5 L" required />
                  )}
                </label>


                <label className="grid gap-2 text-sm font-semibold text-ui-text sm:col-span-2">
                  Deskripsi
                  <Textarea
                    defaultValue={
                      product.description ??
                      ""
                    }
                    name="description"
                  />
                </label>

                <label className="grid gap-2 text-sm font-semibold text-ui-text sm:col-span-2">
                  Catatan audit
                  <Textarea name="note" />
                </label>

                <div className="sm:col-span-2">
                  <button
                    className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary"
                    type="submit"
                  >
                    Simpan Produk
                  </button>
                </div>
              </form>

              <form
                action={
                  product.is_active
                    ? archiveProductAction
                    : reactivateProductAction
                }
                className="mt-6 grid gap-3 border-t border-ui-border pt-5"
              >
                <input
                  name="intentId"
                  type="hidden"
                  value={randomUUID()}
                />
                <input
                  name="productId"
                  type="hidden"
                  value={
                    product.product_id
                  }
                />
                <input
                  name="rowVersion"
                  type="hidden"
                  value={
                    product.row_version
                  }
                />

                <label className="grid gap-2 text-sm font-semibold text-ui-text">
                  Alasan{" "}
                  {product.is_active
                    ? "menonaktifkan"
                    : "mengaktifkan kembali"}
                  <Textarea
                    name="reason"
                    required
                  />
                </label>

                <label className="flex items-start gap-2 text-sm text-ui-text">
                  <input
                    className="mt-1"
                    name="confirmation"
                    required
                    type="checkbox"
                  />
                  Saya memahami perubahan
                  status tidak menghapus
                  histori Produk.
                </label>

                <div>
                  <button
                    className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-text"
                    type="submit"
                  >
                    {product.is_active
                      ? "Nonaktifkan Produk"
                      : "Aktifkan Kembali Produk"}
                  </button>
                </div>
              </form>
            </details>

            <details className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5">
              <summary className="cursor-pointer text-sm font-semibold text-ui-text">
                Jejak Perubahan Master
              </summary>

              {audits.length ? (
                <div className="mt-4 grid gap-3">
                  {audits.map(
                    (audit) => (
                      <article
                        className="rounded-[var(--ui-radius-md)] bg-ui-surface-subtle p-3 text-sm"
                        key={
                          audit.audit_id
                        }
                      >
                        <p className="font-semibold text-ui-text">
                          {
                            audit.action_code
                          }
                        </p>

                        <p className="mt-1 text-ui-text-muted">
                          {audit.reason ??
                            audit.note ??
                            "Tanpa catatan"}
                        </p>

                        <p className="mt-1 text-xs text-ui-text-muted">
                          {audit.actor_display_name ??
                            audit.process_name ??
                            "Proses tepercaya"}
                          {" · "}
                          {
                            audit.occurred_at
                          }
                        </p>
                      </article>
                    ),
                  )}
                </div>
              ) : (
                <p className="mt-3 text-sm text-ui-text-muted">
                  Belum ada perubahan
                  master yang tercatat.
                </p>
              )}
            </details>
          </div>
        ) : null}
      </div>
    </AppShell>
  );
}
