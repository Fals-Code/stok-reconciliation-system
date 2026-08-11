import { LiveQueryControls } from "@/components/ui/live-query-controls";
import Link from "next/link";

import {
  Alert,
  EmptyState,
  StatusBadge,
} from "@/components/ui";
import {
  getLedgerStockStoryPage,
  type LedgerExplorerFilters,
  type LedgerExplorerRow,
} from "@/lib/supabase-rest";

type SearchParams =
  Record<
    string,
    string | string[] | undefined
  >;

const numberFormatter =
  new Intl.NumberFormat("id-ID");

const dateFormatter =
  new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    dateStyle: "medium",
    timeStyle: "short",
  });

function first(
  value: SearchParams[string],
) {
  return Array.isArray(value)
    ? value[0]
    : value;
}

function text(
  params: SearchParams,
  name: string,
) {
  return (
    first(params[name])?.trim() ??
    ""
  );
}

function validCursor(
  value: string,
) {
  return (
    /^\d+$/.test(value) &&
    BigInt(value) > BigInt(0)
  );
}

function pageContext(
  params: SearchParams,
) {
  const rawPage =
    text(params, "page");

  const parsed =
    /^[1-9]\d*$/.test(rawPage)
      ? Number(rawPage)
      : 1;

  const page =
    Number.isSafeInteger(parsed)
      ? parsed
      : 1;

  const cursor =
    text(params, "cursor");

  if (
    page === 1 ||
    !validCursor(cursor)
  ) {
    return {
      cursor: undefined,
      direction:
        "next" as const,
      page: 1,
    };
  }

  return {
    cursor,
    direction:
      text(
        params,
        "direction",
      ) === "previous"
        ? "previous" as const
        : "next" as const,
    page,
  };
}

function transactionLabel(
  code: string,
) {
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

  if (
    code ===
    "STOCKTAKE_ADJUSTMENT"
  ) {
    return "Penyesuaian Hasil Hitung";
  }

  if (code === "REVERSAL") {
    return "Pembatalan Transaksi";
  }

  return "Perubahan Stok";
}

function reversalLabel(
  state: LedgerExplorerRow[
    "reversal_state"
  ],
) {
  if (state === "REVERSAL") {
    return "Transaksi pembatalan";
  }

  if (
    state === "FULLY_REVERSED"
  ) {
    return "Sudah dibatalkan";
  }

  if (
    state ===
    "PARTIALLY_REVERSED"
  ) {
    return "Sebagian dibatalkan";
  }

  return "Belum dibatalkan";
}

function formatDate(value: string) {
  const date = new Date(value);

  return Number.isNaN(
    date.getTime(),
  )
    ? "-"
    : dateFormatter.format(date);
}

function signed(value: number) {
  return `${
    value > 0 ? "+" : ""
  }${numberFormatter.format(
    value,
  )} unit`;
}

function filters(
  params: SearchParams,
  productId: string,
): LedgerExplorerFilters {
  const context =
    pageContext(params);

  return {
    productId,
    batchCode:
      text(
        params,
        "batchCode",
      ) || undefined,
    transactionType:
      text(
        params,
        "transactionType",
      ) || undefined,
    sourceRef:
      text(
        params,
        "sourceRef",
      ) || undefined,
    occurredFrom:
      text(
        params,
        "occurredFrom",
      ) || undefined,
    occurredTo:
      text(
        params,
        "occurredTo",
      ) || undefined,
    cursor:
      context.cursor,
    direction:
      context.direction,
    pageSize: 20,
  };
}

function historyHref({
  cursor,
  direction,
  page,
  params,
  productId,
  returnTo,
}: {
  cursor?: string | null;
  direction?:
    | "next"
    | "previous";
  page?: number;
  params: SearchParams;
  productId: string;
  returnTo: string;
}) {
  const query =
    new URLSearchParams();

  query.set("tab", "history");

  if (returnTo) {
    query.set(
      "returnTo",
      returnTo,
    );
  }

  for (
    const name of [
      "occurredFrom",
      "occurredTo",
      "batchCode",
      "transactionType",
      "sourceRef",
    ] as const
  ) {
    const value =
      text(params, name);

    if (value) {
      query.set(name, value);
    }
  }

  if (
    cursor &&
    page &&
    page > 1
  ) {
    query.set(
      "cursor",
      cursor,
    );

    query.set(
      "direction",
      direction ?? "next",
    );

    query.set(
      "page",
      String(page),
    );
  }

  return `/products/${encodeURIComponent(
    productId,
  )}?${query.toString()}`;
}

export async function ProductHistory({
  params,
  productId,
  productSku,
  returnTo,
}: {
  params: SearchParams;
  productId: string;
  productSku: string;
  returnTo: string;
}) {
  const context =
    pageContext(params);

  let result;

  try {
    result =
      await getLedgerStockStoryPage(
        filters(
          params,
          productId,
        ),
      );
  } catch {
    return (
      <Alert
        title="Riwayat stok belum dapat dimuat"
        tone="warning"
      >
        Kegagalan membaca riwayat tidak
        mengubah stok. Muat ulang atau
        ubah filter.
      </Alert>
    );
  }

  const previousHref =
    result.hasPreviousPage &&
    result.previousCursor
      ? historyHref({
          cursor:
            result.previousCursor,
          direction:
            "previous",
          page: Math.max(
            1,
            context.page - 1,
          ),
          params,
          productId,
          returnTo,
        })
      : null;

  const nextHref =
    result.hasNextPage &&
    result.nextCursor
      ? historyHref({
          cursor:
            result.nextCursor,
          direction: "next",
          page:
            context.page + 1,
          params,
          productId,
          returnTo,
        })
      : null;

  return (
    <div className="grid gap-5">
      <section className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <h2 className="text-lg font-semibold text-ui-text">
              Riwayat Produk
            </h2>

            <p className="mt-1 text-sm text-ui-text-muted">
              Ledger tetap menjadi bukti
              immutable. Produk sudah
              dikunci ke konteks ini.
            </p>
          </div>

          <Link
            className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
            href={`/ledger?productId=${encodeURIComponent(
              productId,
            )}&productSku=${encodeURIComponent(
              productSku,
            )}`}
          >
            Buka Filter Lengkap
          </Link>
        </div>

        <LiveQueryControls
          className="mt-4 shadow-none"
          contextKeys={["tab", "returnTo"]}
          fields={[
            {
              kind: "datetime-local",
              name: "occurredFrom",
              label: "Dari waktu",
              ariaLabel: "Riwayat dari waktu",
            },
            {
              kind: "datetime-local",
              name: "occurredTo",
              label: "Sampai waktu",
              ariaLabel: "Riwayat sampai waktu",
            },
            {
              kind: "search",
              name: "batchCode",
              label: "Kode Batch",
              ariaLabel: "Cari kode batch pada riwayat",
              placeholder: "Cari batch",
            },
            {
              kind: "select",
              name: "transactionType",
              label: "Jenis Perubahan",
              ariaLabel: "Filter jenis perubahan riwayat",
              options: [
                { value: "", label: "Semua perubahan" },
                { value: "INITIAL_BALANCE", label: "Saldo Awal" },
                { value: "RECEIPT", label: "Barang Masuk" },
                { value: "MARKETPLACE_OUTBOUND", label: "Barang Keluar Marketplace" },
                { value: "MANUAL_OUTBOUND", label: "Barang Keluar Manual" },
                { value: "RETURN_SELLABLE_INBOUND", label: "Retur Layak Dijual" },
                { value: "DISPOSAL", label: "Barang Rusak / Kedaluwarsa" },
                { value: "STOCKTAKE_ADJUSTMENT", label: "Penyesuaian Hasil Hitung" },
                { value: "REVERSAL", label: "Pembatalan Transaksi" },
              ],
            },
            {
              kind: "search",
              name: "sourceRef",
              label: "Referensi",
              ariaLabel: "Cari referensi riwayat",
              placeholder: "Cari referensi",
            },
          ]}
        />
      </section>

      {result.rows.length === 0 ? (
        <EmptyState
          description="Tidak ada perubahan stok yang cocok dengan filter pada produk ini."
          title="Tidak ada riwayat yang cocok"
        />
      ) : (
        <div className="grid gap-3">
          {result.rows.map(
            (row) => (
              <article
                className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4"
                key={
                  row.ledger_entry_id
                }
              >
                <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <p className="font-semibold text-ui-text">
                      {transactionLabel(
                        row.transaction_type_code,
                      )}
                    </p>

                    <p className="mt-1 text-xs text-ui-text-muted">
                      Kode Batch{" "}
                      {
                        row.batch_code_snapshot
                      }
                      {" · "}
                      {formatDate(
                        row.occurred_at,
                      )}
                    </p>
                  </div>

                  <p
                    className={
                      row.quantity_delta >=
                      0
                        ? "ui-number font-semibold text-ui-primary"
                        : "ui-number font-semibold text-ui-danger"
                    }
                  >
                    {signed(
                      row.quantity_delta,
                    )}
                  </p>
                </div>

                <div className="mt-3 flex flex-wrap items-center gap-2">
                  <StatusBadge
                    tone={
                      row.reversal_state ===
                      "NOT_REVERSED"
                        ? "neutral"
                        : "warning"
                    }
                  >
                    {reversalLabel(
                      row.reversal_state,
                    )}
                  </StatusBadge>

                  <span className="text-xs text-ui-text-muted">
                    Referensi{" "}
                    {
                      row.source_ref_snapshot
                    }
                  </span>
                </div>

                <Link
                  className="mt-3 inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
                  href={`/ledger/${encodeURIComponent(
                    row.transaction_id,
                  )}?productId=${encodeURIComponent(
                    productId,
                  )}`}
                >
                  Lihat Detail Transaksi
                </Link>
              </article>
            ),
          )}
        </div>
      )}

      <nav
        aria-label="Halaman riwayat produk"
        className="flex items-center justify-between gap-3"
      >
        {previousHref ? (
          <Link
            className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
            href={previousHref}
          >
            Halaman sebelumnya
          </Link>
        ) : (
          <span
            aria-disabled="true"
            className="text-sm text-ui-text-muted"
          >
            Halaman sebelumnya
          </span>
        )}

        <span className="ui-number text-sm text-ui-text-muted">
          Halaman {context.page}
        </span>

        {nextHref ? (
          <Link
            className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
            href={nextHref}
          >
            Halaman berikutnya
          </Link>
        ) : (
          <span
            aria-disabled="true"
            className="text-sm text-ui-text-muted"
          >
            Halaman berikutnya
          </span>
        )}
      </nav>
    </div>
  );
}
