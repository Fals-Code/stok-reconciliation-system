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
  archiveProductBatchAction,
  blockProductBatchAction,
  reactivateProductBatchAction,
  unblockProductBatchAction,
  updateProductBatchAction,
} from "@/app/products/actions";
import {
  Alert,
  Input,
  StatusBadge,
  Textarea,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  getProductBatchMasterData,
  type ProductBatchMasterRow,
} from "@/lib/supabase-rest";

export const dynamic =
  "force-dynamic";

type SearchParams =
  Record<
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

function quantity(value: number) {
  return new Intl.NumberFormat(
    "id-ID",
  ).format(Number(value));
}

function safeReturnTo(
  value: string | undefined,
  productId: string,
) {
  const candidate =
    value?.trim() ?? "";

  const expectedPrefix =
    `/products/${productId}`;

  if (
    candidate.startsWith(
      expectedPrefix,
    ) &&
    !candidate.startsWith("//") &&
    !candidate.includes("\n") &&
    !candidate.includes("\r")
  ) {
    return candidate;
  }

  return `${expectedPrefix}?tab=batches`;
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
      ? `Batch ditahan: ${batch.block_reason}`
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

function HiddenIdentity({
  batch,
  productId,
}: {
  batch: ProductBatchMasterRow;
  productId: string;
}) {
  return (
    <>
      <input
        name="intentId"
        type="hidden"
        value={randomUUID()}
      />
      <input
        name="productId"
        type="hidden"
        value={productId}
      />
      <input
        name="batchId"
        type="hidden"
        value={batch.batch_id}
      />
      <input
        name="rowVersion"
        type="hidden"
        value={batch.row_version}
      />
    </>
  );
}

export default async function BatchDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{
    productId: string;
    batchId: string;
  }>;
  searchParams:
    Promise<SearchParams>;
}) {
  const [
    {
      productId,
      batchId,
    },
    query,
    session,
  ] = await Promise.all([
    params,
    searchParams,
    requireAdminSession(),
  ]);

  let data;

  try {
    data =
      await getProductBatchMasterData(
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
        <div className="mx-auto w-full max-w-[960px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader
            description="Data Batch belum dapat dimuat. Kondisi gagal tidak mengubah stok."
            title="Detail Batch"
          />

          <Alert
            className="mt-6"
            title="Batch belum dapat dimuat"
            tone="warning"
          >
            Muat ulang sebelum melakukan
            perubahan pada master Batch.
          </Alert>
        </div>
      </AppShell>
    );
  }

  const batch =
    data.batches.find(
      (row) =>
        row.product_id ===
          productId &&
        row.batch_id ===
          batchId,
    );

  if (!batch) {
    notFound();
  }

  const returnTo =
    safeReturnTo(
      first(query.returnTo),
      productId,
    );

  const audits =
    data.audits.filter(
      (audit) =>
        audit.batch_id ===
        batch.batch_id,
    );

  const standard =
    batch.batch_kind_code ===
    "STANDARD";

  const archived =
    batch.lifecycle_status_code ===
    "ARCHIVED";

  const expired =
    batch.is_effectively_expired;

  const signal =
    batchSignal(batch);

  const success =
    first(query.success);

  const error =
    first(query.error);

  return (
    <AppShell
      profile={session.profile}
    >
      <div className="mx-auto w-full max-w-[960px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          action={
            <Link
              className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
              href={returnTo}
            >
              Kembali ke Produk
            </Link>
          }
          description={`${batch.product_sku} · ${batch.product_name}`}
          eyebrow="Detail Batch"
          title={batch.batch_code}
        />

        {success ? (
          <Alert
            className="mt-6"
            title="Perubahan Batch tersimpan"
            tone="success"
          >
            {success}
          </Alert>
        ) : null}

        {error ? (
          <Alert
            className="mt-6"
            title="Perubahan Batch belum tersimpan"
            tone="warning"
          >
            {error}
          </Alert>
        ) : null}

        <section className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <p className="text-sm font-semibold text-ui-text">
                {kindLabel(
                  batch.batch_kind_code,
                )}
              </p>

              <p className="mt-1 text-sm text-ui-text-muted">
                Kedaluwarsa{" "}
                {batch.expiry_date}
              </p>
            </div>

            <StatusBadge
              tone={
                batch.lifecycle_status_code ===
                  "BLOCKED" ||
                batch.lifecycle_status_code ===
                  "EXPIRED"
                  ? "warning"
                  : "neutral"
              }
            >
              {statusLabel(
                batch.lifecycle_status_code,
              )}
            </StatusBadge>
          </div>

          {signal ? (
            <p className="mt-4 rounded-[var(--ui-radius-md)] bg-ui-warning-subtle px-3 py-2 text-sm text-ui-warning">
              {signal}
            </p>
          ) : null}

          <dl className="mt-5 grid grid-cols-2 gap-4 text-sm sm:grid-cols-3">
            <div>
              <dt className="text-ui-text-muted">
                Layak Dijual
              </dt>
              <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                {quantity(
                  batch.sellable_qty,
                )}
              </dd>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Ditahan
              </dt>
              <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                {quantity(
                  batch.quarantine_qty,
                )}
              </dd>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Rusak
              </dt>
              <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
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
              <p className="mt-1 text-xs text-ui-text-muted">
                Reservasi berlaku pada
                tingkat Produk.
              </p>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Pemakaian FEFO
              </dt>
              <dd className="mt-1 font-semibold text-ui-text">
                {batch.is_fefo_eligible
                  ? "Dapat digunakan otomatis"
                  : "Tidak digunakan"}
              </dd>
            </div>

            <div>
              <dt className="text-ui-text-muted">
                Histori stok
              </dt>
              <dd className="mt-1 font-semibold text-ui-text">
                {batch.has_authoritative_history
                  ? "Sudah ada"
                  : "Belum ada"}
              </dd>
            </div>
          </dl>

          <p className="mt-5 text-sm leading-6 text-ui-text-muted">
            Operator tidak memilih Batch
            untuk Barang Keluar. Sistem
            tetap menentukan FEFO secara
            otomatis saat transaksi
            outbound diperiksa dan
            disimpan.
          </p>

          <Link
            className="mt-4 inline-flex min-h-[var(--ui-control-height)] items-center font-semibold text-ui-primary hover:underline"
            href={`/ledger?productId=${encodeURIComponent(
              batch.product_id,
            )}&batchId=${encodeURIComponent(
              batch.batch_id,
            )}&batchCode=${encodeURIComponent(
              batch.batch_code,
            )}`}
          >
            Lihat Riwayat Batch
          </Link>
        </section>

        {!standard ? (
          <Alert
            className="mt-6"
            title="Batch dikelola oleh alur retur"
            tone="warning"
          >
            Jenis{" "}
            {batch.batch_kind_code} dibuat
            oleh domain retur dan tidak
            diedit melalui pengaturan Batch
            STANDARD.
          </Alert>
        ) : (
          <details className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5">
            <summary className="cursor-pointer text-sm font-semibold text-ui-text">
              Pengaturan Batch
            </summary>

            {!archived ? (
              <form
                action={
                  updateProductBatchAction
                }
                className="mt-4 grid gap-4 sm:grid-cols-2"
              >
                <HiddenIdentity
                  batch={batch}
                  productId={
                    productId
                  }
                />

                <label className="grid gap-2 text-sm font-semibold text-ui-text">
                  Kode Batch
                  <Input
                    defaultValue={
                      batch.batch_code
                    }
                    name="batchCode"
                    required
                  />
                </label>

                <label className="grid gap-2 text-sm font-semibold text-ui-text">
                  Kedaluwarsa
                  <Input
                    defaultValue={
                      batch.expiry_date
                    }
                    name="expiryDate"
                    required
                    type="date"
                  />
                </label>

                <label className="grid gap-2 text-sm font-semibold text-ui-text">
                  Tanggal Produksi
                  <Input
                    defaultValue={
                      batch.manufactured_date ??
                      ""
                    }
                    name="manufacturedDate"
                    type="date"
                  />
                </label>

                <label className="grid gap-2 text-sm font-semibold text-ui-text">
                  Pertama Diterima
                  <Input
                    defaultValue={
                      batch.received_first_at?.slice(
                        0,
                        16,
                      ) ?? ""
                    }
                    name="receivedFirstAt"
                    type="datetime-local"
                  />
                </label>

                {batch.has_authoritative_history ? (
                  <label className="grid gap-2 text-sm font-semibold text-ui-text sm:col-span-2">
                    Alasan koreksi
                    <Textarea
                      name="reason"
                      placeholder="Wajib jika tanggal kedaluwarsa dikoreksi setelah Batch memiliki histori."
                    />
                  </label>
                ) : null}

                <label className="grid gap-2 text-sm font-semibold text-ui-text sm:col-span-2">
                  Catatan
                  <Textarea name="note" />
                </label>

                <div className="sm:col-span-2">
                  <button
                    className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary"
                    type="submit"
                  >
                    Simpan Batch
                  </button>
                </div>
              </form>
            ) : (
              <p className="mt-4 text-sm text-ui-text-muted">
                Batch tidak aktif tidak
                dapat diedit sebelum
                diaktifkan kembali.
              </p>
            )}

            <div className="mt-6 border-t border-ui-border pt-5">
              {batch.lifecycle_status_code ===
              "ACTIVE" ? (
                <div className="grid gap-5 sm:grid-cols-2">
                  <form
                    action={
                      blockProductBatchAction
                    }
                    className="grid gap-3"
                  >
                    <HiddenIdentity
                      batch={batch}
                      productId={
                        productId
                      }
                    />

                    <label className="grid gap-2 text-sm font-semibold text-ui-text">
                      Alasan menahan Batch
                      <Textarea
                        name="reason"
                        required
                      />
                    </label>

                    <button
                      className="min-h-[var(--ui-control-height)] justify-self-start rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-text"
                      type="submit"
                    >
                      Tahan Batch
                    </button>
                  </form>

                  <form
                    action={
                      archiveProductBatchAction
                    }
                    className="grid gap-3"
                  >
                    <HiddenIdentity
                      batch={batch}
                      productId={
                        productId
                      }
                    />

                    <label className="grid gap-2 text-sm font-semibold text-ui-text">
                      Alasan menonaktifkan
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
                      Saya memahami Batch
                      tidak akan digunakan
                      pada transaksi baru.
                    </label>

                    <button
                      className="min-h-[var(--ui-control-height)] justify-self-start rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-text"
                      type="submit"
                    >
                      Nonaktifkan Batch
                    </button>
                  </form>
                </div>
              ) : null}

              {batch.lifecycle_status_code ===
              "BLOCKED" ? (
                <div className="grid gap-5 sm:grid-cols-2">
                  {expired ? (
                    <p className="text-sm text-ui-warning">
                      Batch yang sudah
                      kedaluwarsa tidak dapat
                      diaktifkan kembali.
                    </p>
                  ) : (
                    <form
                      action={
                        unblockProductBatchAction
                      }
                      className="grid gap-3"
                    >
                      <HiddenIdentity
                        batch={batch}
                        productId={
                          productId
                        }
                      />

                      <label className="grid gap-2 text-sm font-semibold text-ui-text">
                        Alasan melepas
                        tahanan
                        <Textarea
                          name="reason"
                          required
                        />
                      </label>

                      <button
                        className="min-h-[var(--ui-control-height)] justify-self-start rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-text"
                        type="submit"
                      >
                        Aktifkan Batch
                      </button>
                    </form>
                  )}

                  <form
                    action={
                      archiveProductBatchAction
                    }
                    className="grid gap-3"
                  >
                    <HiddenIdentity
                      batch={batch}
                      productId={
                        productId
                      }
                    />

                    <label className="grid gap-2 text-sm font-semibold text-ui-text">
                      Alasan menonaktifkan
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
                      Saya memahami Batch
                      akan menjadi tidak
                      aktif.
                    </label>

                    <button
                      className="min-h-[var(--ui-control-height)] justify-self-start rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-text"
                      type="submit"
                    >
                      Nonaktifkan Batch
                    </button>
                  </form>
                </div>
              ) : null}

              {batch.lifecycle_status_code ===
              "ARCHIVED" ? (
                expired ? (
                  <p className="text-sm text-ui-warning">
                    Batch yang sudah
                    kedaluwarsa tidak dapat
                    diaktifkan kembali.
                  </p>
                ) : (
                  <form
                    action={
                      reactivateProductBatchAction
                    }
                    className="grid gap-3"
                  >
                    <HiddenIdentity
                      batch={batch}
                      productId={
                        productId
                      }
                    />

                    <label className="grid gap-2 text-sm font-semibold text-ui-text">
                      Alasan mengaktifkan
                      kembali
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
                      Saya sudah memeriksa
                      identitas dan tanggal
                      Batch.
                    </label>

                    <button
                      className="min-h-[var(--ui-control-height)] justify-self-start rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary"
                      type="submit"
                    >
                      Aktifkan Kembali Batch
                    </button>
                  </form>
                )
              ) : null}
            </div>
          </details>
        )}

        <details className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:p-5">
          <summary className="cursor-pointer text-sm font-semibold text-ui-text">
            Audit Batch
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

                    {audit.before_snapshot &&
                    audit.after_snapshot ? (
                      <p className="mt-1 text-xs text-ui-text-muted">
                        Snapshot sebelum dan
                        sesudah tersimpan
                        untuk audit.
                      </p>
                    ) : null}
                  </article>
                ),
              )}
            </div>
          ) : (
            <p className="mt-3 text-sm text-ui-text-muted">
              Belum ada audit Batch.
            </p>
          )}
        </details>
      </div>
    </AppShell>
  );
}
