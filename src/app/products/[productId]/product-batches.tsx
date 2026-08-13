import { LiveQueryControls } from "@/components/ui/live-query-controls";
import { randomUUID } from "node:crypto";
import Link from "next/link";

import {
  createProductBatchAction,
} from "@/app/products/actions";
import {
  EmptyState,
  Input,
  StatusBadge,
  Textarea,
} from "@/components/ui";
import type {
  ProductBatchMasterRow,
  ProductMasterRow,
} from "@/lib/supabase-rest";

type BatchStatusFilter =
  | "ALL"
  | "ACTIVE"
  | "BLOCKED"
  | "EXPIRED"
  | "ARCHIVED";

const numberFormatter =
  new Intl.NumberFormat("id-ID");

function quantity(value: number) {
  return numberFormatter.format(
    Number(value),
  );
}

function normalizeStatus(
  value?: string,
): BatchStatusFilter {
  if (
    value === "ACTIVE" ||
    value === "BLOCKED" ||
    value === "EXPIRED" ||
    value === "ARCHIVED"
  ) {
    return value;
  }

  return "ALL";
}

function statusLabel(
  status: ProductBatchMasterRow[
    "lifecycle_status_code"
  ],
) {
  if (status === "ACTIVE") {
    return "Aktif";
  }

  if (status === "BLOCKED") {
    return "Ditahan";
  }

  if (status === "EXPIRED") {
    return "Kedaluwarsa";
  }

  return "Tidak Aktif";
}

function statusTone(
  status: ProductBatchMasterRow[
    "lifecycle_status_code"
  ],
) {
  return status === "BLOCKED" ||
    status === "EXPIRED"
    ? "warning" as const
    : "neutral" as const;
}

function kindLabel(
  kind: ProductBatchMasterRow[
    "batch_kind_code"
  ],
) {
  if (kind === "RETURN") {
    return "Batch Retur";
  }

  if (
    kind === "UNIDENTIFIED_RETURN"
  ) {
    return "Retur Belum Teridentifikasi";
  }

  return "Batch Standar";
}

function batchSignal(
  batch: ProductBatchMasterRow,
) {
  if (
    batch.lifecycle_status_code ===
    "BLOCKED"
  ) {
    return batch.block_reason
      ? `Ditahan: ${batch.block_reason}`
      : "Batch sedang ditahan.";
  }

  if (batch.is_effectively_expired) {
    return "Batch sudah kedaluwarsa.";
  }

  if (
    batch.effective_expiry_state ===
    "EXPIRES_TODAY"
  ) {
    return "Batch kedaluwarsa hari ini.";
  }

  return null;
}

function currentTabHref({
  batchQuery,
  batchStatus,
  productId,
  returnTo,
}: {
  batchQuery: string;
  batchStatus: BatchStatusFilter;
  productId: string;
  returnTo: string;
}) {
  const query =
    new URLSearchParams();

  query.set("tab", "batches");

  if (returnTo) {
    query.set(
      "returnTo",
      returnTo,
    );
  }

  if (batchQuery) {
    query.set(
      "batchQ",
      batchQuery,
    );
  }

  if (batchStatus !== "ALL") {
    query.set(
      "batchStatus",
      batchStatus,
    );
  }

  return `/products/${encodeURIComponent(
    productId,
  )}?${query.toString()}`;
}

export function ProductBatches({
  batchQuery: rawBatchQuery,
  batchStatus: rawBatchStatus,
  batches,
  product,
  returnTo,
}: {
  batchQuery?: string;
  batchStatus?: string;
  batches: ProductBatchMasterRow[];
  product: ProductMasterRow;
  returnTo: string;
}) {
  const batchQuery =
    rawBatchQuery?.trim() ?? "";

  const batchStatus =
    normalizeStatus(
      rawBatchStatus,
    );

  const filtered =
    batches.filter((batch) => {
      const queryMatch =
        !batchQuery ||
        batch.batch_code
          .toLowerCase()
          .includes(
            batchQuery.toLowerCase(),
          );

      const statusMatch =
        batchStatus === "ALL" ||
        batch.lifecycle_status_code ===
          batchStatus;

      return (
        queryMatch &&
        statusMatch
      );
    });

  const tabHref =
    currentTabHref({
      batchQuery,
      batchStatus,
      productId:
        product.product_id,
      returnTo,
    });

  return (
    <div className="grid gap-6">
      <section className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5">
        <h2 className="text-lg font-semibold text-ui-text">
          Batch
        </h2>

        <p className="mt-1 text-sm leading-6 text-ui-text-muted">
          Status batch, tanggal
          kedaluwarsa, dan kondisi stok
          berasal langsung dari master
          batch. Ditahan dan Kedaluwarsa
          tidak sama dengan kondisi stok
          Rusak.
        </p>

        <LiveQueryControls
          className="mt-4 shadow-none"
          contextKeys={["tab", "returnTo"]}
          fields={[
            {
              kind: "search",
              name: "batchQ",
              label: "Cari Kode Batch",
              ariaLabel: "Cari kode batch",
              placeholder: "Contoh: SER-2612-B",
            },
            {
              kind: "select",
              name: "batchStatus",
              label: "Status",
              ariaLabel: "Filter status batch",
              options: [
                { value: "", label: "Semua status" },
                { value: "ACTIVE", label: "Aktif" },
                { value: "BLOCKED", label: "Ditahan" },
                { value: "EXPIRED", label: "Kedaluwarsa" },
                { value: "ARCHIVED", label: "Tidak Aktif" },
              ],
            },
          ]}
        />
      </section>

      {product.is_active ? (
        <details className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5">
          <summary className="cursor-pointer text-sm font-semibold text-ui-text">
            Buat Batch Baru
          </summary>
          <div className="mt-3 space-y-2 text-sm leading-6 text-ui-text-muted">
            <p>
              Gunakan ini jika kode batch belum terdaftar. Membuat batch hanya
              mendaftarkan identitas batch dan tidak menambah jumlah stok.
            </p>
            <p>
              Untuk mencatat barang yang benar-benar diterima gudang, gunakan{" "}
              <Link
                className="font-semibold text-ui-primary hover:underline"
                href="/receipts/new"
              >
                Barang Masuk
              </Link>
              .
            </p>
          </div>
          <form
            action={
              createProductBatchAction
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

            <label className="grid gap-2 text-sm font-semibold text-ui-text">
              Kode Batch
              <Input
                name="batchCode"
                required
              />
            </label>

            <label className="grid gap-2 text-sm font-semibold text-ui-text">
              Tanggal Kedaluwarsa
              <Input
                name="expiryDate"
                required
                type="date"
              />
            </label>

            <label className="grid gap-2 text-sm font-semibold text-ui-text">
              Tanggal Produksi
              <Input
                name="manufacturedDate"
                type="date"
              />
            </label>

            <label className="grid gap-2 text-sm font-semibold text-ui-text">
              Pertama Diterima
              <Input
                name="receivedFirstAt"
                type="datetime-local"
              />
            </label>

            <label className="grid gap-2 text-sm font-semibold text-ui-text sm:col-span-2">
              Catatan
              <Textarea name="note" />
            </label>

            <div className="sm:col-span-2">
              <button
                className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary"
                type="submit"
              >
                Buat Batch
              </button>
            </div>
          </form>
        </details>
      ) : (
        <p className="rounded-[var(--ui-radius-md)] border border-ui-warning bg-ui-warning-subtle p-4 text-sm text-ui-warning">
          Produk tidak aktif tidak dapat
          menerima Batch baru.
        </p>
      )}

      {filtered.length === 0 ? (
        <EmptyState
          description={
            batchQuery ||
            batchStatus !== "ALL"
              ? "Ubah pencarian atau status Batch."
              : "Belum ada Batch untuk produk ini."
          }
          title={
            batchQuery ||
            batchStatus !== "ALL"
              ? "Tidak ada Batch yang cocok"
              : "Belum ada Batch"
          }
        />
      ) : (
        <div className="grid gap-3">
          {filtered.map(
            (batch) => {
              const signal =
                batchSignal(batch);

              const batchReturnTo =
                tabHref;

              return (
                <article
                  className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4"
                  key={
                    batch.batch_id
                  }
                >
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <Link
                          className="font-semibold text-ui-text hover:text-ui-primary hover:underline"
                          href={`/products/${encodeURIComponent(
                            product.product_id,
                          )}/batches/${encodeURIComponent(
                            batch.batch_id,
                          )}?returnTo=${encodeURIComponent(
                            batchReturnTo,
                          )}`}
                        >
                          {
                            batch.batch_code
                          }
                        </Link>

                        <StatusBadge
                          tone={statusTone(
                            batch.lifecycle_status_code,
                          )}
                        >
                          {statusLabel(
                            batch.lifecycle_status_code,
                          )}
                        </StatusBadge>
                      </div>

                      <p className="mt-1 text-xs text-ui-text-muted">
                        {kindLabel(
                          batch.batch_kind_code,
                        )}
                        {" · "}
                        Kedaluwarsa{" "}
                        {
                          batch.expiry_date
                        }
                      </p>
                    </div>

                    <p className="text-sm text-ui-text-muted">
                      FEFO otomatis:{" "}
                      <span className="font-semibold text-ui-text">
                        {batch.is_fefo_eligible
                          ? "Dapat digunakan"
                          : "Tidak digunakan"}
                      </span>
                    </p>
                  </div>

                  {signal ? (
                    <p className="mt-3 rounded-[var(--ui-radius-md)] bg-ui-warning-subtle px-3 py-2 text-sm text-ui-warning">
                      {signal}
                    </p>
                  ) : null}

                  <dl className="mt-4 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
                    <div>
                      <dt className="text-ui-text-muted">
                        Layak Dijual
                      </dt>
                      <dd className="ui-number mt-1 font-semibold text-ui-text">
                        {quantity(
                          batch.sellable_qty,
                        )}
                      </dd>
                    </div>

                    <div>
                      <dt className="text-ui-text-muted">
                        Ditahan
                      </dt>
                      <dd className="ui-number mt-1 font-semibold text-ui-text">
                        {quantity(
                          batch.quarantine_qty,
                        )}
                      </dd>
                    </div>

                    <div>
                      <dt className="text-ui-text-muted">
                        Rusak
                      </dt>
                      <dd className="ui-number mt-1 font-semibold text-ui-text">
                        {quantity(
                          batch.damaged_qty,
                        )}
                      </dd>
                    </div>

                    <div>
                      <dt className="text-ui-text-muted">
                        Sudah Dipesan
                      </dt>
                      <dd className="ui-number mt-1 font-semibold text-ui-text">
                        {quantity(
                          batch.reserved_qty,
                        )}
                      </dd>
                    </div>
                  </dl>
                </article>
              );
            },
          )}
        </div>
      )}
    </div>
  );
}
