import Link from "next/link";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  ReceiptForm,
} from "@/app/receipts/new/receipt-form";
import {
  Alert,
  EmptyState,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  getProductBatchMasterData,
  getProductMasterData,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = Record<
  string,
  string | string[] | undefined
>;

function first(
  value: SearchParams[string],
) {
  return Array.isArray(value)
    ? value[0]
    : value;
}

export default async function NewReceiptPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [session, query] = await Promise.all([
    requireAdminSession(),
    searchParams,
  ]);

  const success = first(query.success);
  const error = first(query.error);
  const transactionId = first(query.transactionId);

  let masterData = null;

  try {
    const [productData, batchData] = await Promise.all([
      getProductMasterData(session.profile.organization_id),
      getProductBatchMasterData(session.profile.organization_id),
    ]);

    masterData = {
      products: productData.products.filter((p) => p.is_active),
      batches: batchData.batches.filter(
        (b) =>
          b.product_is_active &&
          b.batch_kind_code === "STANDARD" &&
          b.lifecycle_status_code === "ACTIVE" &&
          !b.is_effectively_expired,
      ),
    };
  } catch {
    masterData = null;
  }

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1120px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <Link
          className="mb-4 inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
          href="/products"
        >
          &larr; Kembali ke Stok
        </Link>
        <PageHeader
          description="Catat barang yang benar-benar telah diterima gudang."
          eyebrow="Stok"
          title="Barang Masuk"
        />

        {success ? (
          <Alert
            className="mt-6"
            title="Barang masuk berhasil dicatat"
            tone="success"
          >
            <p>{success}</p>
            <div className="mt-3 flex flex-wrap gap-x-5 gap-y-2">
              {transactionId ? (
                <Link className="inline-flex min-h-8 items-center font-semibold text-ui-primary hover:underline" href={`/ledger/${encodeURIComponent(transactionId)}`}>
                  Lihat Transaksi
                </Link>
              ) : null}
              <Link className="inline-flex min-h-8 items-center font-semibold text-ui-primary hover:underline" href="/receipts/new">
                Catat Barang Masuk Lagi
              </Link>
              <Link className="inline-flex min-h-8 items-center font-semibold text-ui-primary hover:underline" href="/products">
                Kembali ke Stok
              </Link>
            </div>
          </Alert>
        ) : null}

        {error ? (
          <Alert
            className="mt-6"
            title="Barang masuk belum tersimpan"
            tone="warning"
          >
            {error}
          </Alert>
        ) : null}

        {masterData === null ? (
          <Alert
            className="mt-6"
            title="Data produk dan batch belum dapat dimuat"
            tone="warning"
          >
            Muat ulang halaman sebelum mencatat penerimaan. Tidak ada perubahan stok yang dilakukan.
          </Alert>
        ) : masterData.products.length === 0 ? (
          <EmptyState
            className="mt-6"
            description="Penerimaan membutuhkan minimal satu produk aktif."
            title="Belum ada produk aktif yang dapat menerima barang"
          />
        ) : (
          <ReceiptForm
            batches={masterData.batches}
            products={masterData.products}
          />
        )}
      </div>
    </AppShell>
  );
}
