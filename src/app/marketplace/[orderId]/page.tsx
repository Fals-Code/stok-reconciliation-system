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
  OrderWorkspaceTabs,
} from "@/app/marketplace/order-workspace-tabs";
import {
  Alert,
  EmptyState,
  StatusBadge,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  getMarketplaceData,
  previewMarketplaceCancellation,
  type MarketplaceCancellationPreview,
  type MarketplaceOrder,
} from "@/lib/supabase-rest";
import {
  postMarketplaceCancellationAction,
} from "@/app/marketplace/cancellations/actions";
import {
  serializeMarketplaceCancellationDraft,
  type MarketplaceCancellationDraft,
  type MarketplaceCancellationPhaseCode,
} from "@/app/marketplace/cancellations/draft";

export const dynamic =
  "force-dynamic";

const numberFormatter =
  new Intl.NumberFormat("id-ID");

function qty(
  value: number,
) {
  return numberFormatter.format(
    Number(value),
  );
}

function channelLabel(
  code: string,
) {
  if (code === "TIKTOK_SHOP") {
    return "TikTok Shop";
  }

  if (code === "SHOPEE") {
    return "Shopee";
  }

  return code;
}

function orderStatus(
  order: MarketplaceOrder,
) {
  if (
    order.status_code ===
    "CANCELLED"
  ) {
    return {
      label: "Dibatalkan",
      tone: "danger" as const,
    };
  }

  if (
    Number(
      order.open_qty,
    ) > 0
  ) {
    return {
      label: "Dalam proses",
      tone: "warning" as const,
    };
  }

  if (
    order.status_code ===
    "CLOSED_MIXED"
  ) {
    return {
      label: "Selesai sebagian",
      tone: "warning" as const,
    };
  }

  if (
    Number(
      order.shipped_qty,
    ) > 0
  ) {
    return {
      label: "Terkirim",
      tone: "selected" as const,
    };
  }

  return {
    label: "Selesai",
    tone: "neutral" as const,
  };
}

function eventLabel(
  code: string,
) {
  const labels:
    Record<string, string> = {
      RESERVE:
        "Pesanan masuk",
      RESERVED:
        "Pesanan masuk",
      READY_TO_SHIP:
        "Siap dikirim",
      SHIP:
        "Dikirim",
      SHIPPED:
        "Dikirim",
      IN_TRANSIT:
        "Dalam perjalanan",
      RELEASE:
        "Reservasi dilepas",
      CANCEL:
        "Dibatalkan",
      CANCELLED:
        "Dibatalkan",
    };

  return labels[code] ?? code;
}

function formatDate(
  value: string,
) {
  const date =
    new Date(value);

  if (
    Number.isNaN(
      date.getTime(),
    )
  ) {
    return value;
  }

  return new Intl.DateTimeFormat(
    "id-ID",
    {
      timeZone: "Asia/Jakarta",
      dateStyle: "medium",
      timeStyle: "short",
    },
  ).format(date);
}

export default async function MarketplaceOrderDetailPage({
  params,
  searchParams,
}: {
  params:
    Promise<{
      orderId: string;
    }>;
  searchParams:
    Promise<Record<string, string | string[] | undefined>>;
}) {
  const [session, route, query] =
    await Promise.all([
      requireAdminSession(),
      params,
      searchParams,
    ]);

  let marketplace:
    Awaited<
      ReturnType<
        typeof getMarketplaceData
      >
    > | null = null;

  try {
    marketplace =
      await getMarketplaceData(
        session.profile
          .organization_id,
      );
  } catch {
    marketplace = null;
  }

  if (!marketplace) {
    return (
      <AppShell
        profile={session.profile}
      >
        <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader
            description="Detail pesanan belum dapat dimuat."
            eyebrow="Pesanan"
            title="Pesanan"
          />

          <Alert
            className="mt-6"
            title="Pesanan belum dapat dimuat"
            tone="danger"
          >
            Coba muat ulang halaman. Tidak ada perubahan stok yang dilakukan.
          </Alert>
        </div>
      </AppShell>
    );
  }

  const order =
    marketplace.orders.find(
      (candidate) =>
        candidate.order_id ===
        route.orderId,
    );

  if (!order) {
    notFound();
  }

  const reservations =
    marketplace.reservations.filter(
      (row) =>
        row.order_id ===
        order.order_id,
    );

  const candidates =
    marketplace.candidates.filter(
      (row) =>
        row.order_id ===
        order.order_id,
    );

  const events =
    marketplace.events.filter(
      (row) =>
        row.order_id ===
        order.order_id,
    );

  const cancellations =
    marketplace.cancellations.filter(
      (row) =>
        row.order_id ===
        order.order_id,
    );

  const status =
    orderStatus(order);

  const hasCancelable =
    candidates.some(
      (row) =>
        Number(
          row.total_remaining_cancellable_qty,
        ) > 0,
    );

  const selectedCandidateId =
    Array.isArray(query.cancelItem)
      ? query.cancelItem[0]
      : query.cancelItem;

  const selectedPhase =
    (Array.isArray(query.cancelPhase)
      ? query.cancelPhase[0]
      : query.cancelPhase) as
      | MarketplaceCancellationPhaseCode
      | undefined;

  const selectedQuantityRaw =
    Array.isArray(query.cancelQty)
      ? query.cancelQty[0]
      : query.cancelQty;

  const selectedQuantity =
    selectedQuantityRaw &&
    /^[1-9][0-9]*$/.test(selectedQuantityRaw)
      ? Number(selectedQuantityRaw)
      : 1;

  const selectedEventRef =
    (Array.isArray(query.cancelEventRef)
      ? query.cancelEventRef[0]
      : query.cancelEventRef) ?? "";

  const selectedOccurredAt =
    (Array.isArray(query.cancelOccurredAt)
      ? query.cancelOccurredAt[0]
      : query.cancelOccurredAt) ?? "";

  const selectedNote =
    (Array.isArray(query.cancelNote)
      ? query.cancelNote[0]
      : query.cancelNote) ?? "";

  const selectedCandidate =
    selectedCandidateId
      ? candidates.find(
          (row) =>
            row.order_item_id === selectedCandidateId,
        ) ?? null
      : null;

  let cancellationDraft:
    MarketplaceCancellationDraft | null = null;

  let cancellationPreview:
    MarketplaceCancellationPreview | null = null;

  let cancellationPreviewError:
    string | null = null;

  if (
    selectedCandidate &&
    selectedPhase &&
    selectedOccurredAt &&
    selectedEventRef
  ) {
    cancellationDraft = {
      channelCode:
        selectedCandidate.channel_code,
      eventRef: selectedEventRef,
      orderRef:
        selectedCandidate.external_order_ref,
      occurredAt:
        selectedOccurredAt,
      sourceStatus:
        "CANCELLED",
      lines: [
        {
          productId:
            selectedCandidate.product_id,
          orderItemRef:
            selectedCandidate.external_item_ref,
          phaseCode:
            selectedPhase,
          quantity:
            selectedQuantity,
          sourceLineRef:
            "UI-1",
        },
      ],
      note:
        selectedNote.trim() || null,
    };

    try {
      cancellationPreview =
        await previewMarketplaceCancellation({
          ...cancellationDraft,
          occurredAt:
            `${selectedOccurredAt}:00+07:00`,
          metadata: {
            source:
              "marketplace-cancellation-admin-ui",
            version: 1,
          },
        });
    } catch (error) {
      cancellationPreviewError =
        error instanceof Error
          ? error.message
          : "Preview pembatalan tidak dapat dihitung.";
    }
  }

  return (
    <AppShell
      profile={session.profile}
    >
      <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          description={channelLabel(
            order.channel_code,
          )}
          eyebrow="Pesanan"
          title={
            order.external_order_ref
          }
        />

        <OrderWorkspaceTabs active="orders" />

        {(() => {
          const success =
            Array.isArray(query.success)
              ? query.success[0]
              : query.success;
          const error =
            Array.isArray(query.error)
              ? query.error[0]
              : query.error;

          if (success) {
            return (
              <Alert
                className="mt-6"
                title="Pembatalan berhasil"
                tone="success"
              >
                {success}
              </Alert>
            );
          }

          if (error) {
            return (
              <Alert
                className="mt-6"
                title="Pembatalan belum berhasil"
                tone="danger"
              >
                {error}
              </Alert>
            );
          }

          return null;
        })()}

        <div className="mt-5 flex flex-wrap items-center justify-between gap-3">
          <Link
            className="text-sm font-semibold text-ui-primary hover:underline"
            href="/marketplace"
          >
            {"\u2190"} Kembali ke daftar
          </Link>

          <StatusBadge tone={status.tone}>
            {status.label}
          </StatusBadge>
        </div>

        <p className="mt-3 text-xs text-ui-text-muted">
          Status pengiriman diperbarui dari event marketplace yang diterima sistem {"\u00B7"} tidak perlu ditandai manual.
        </p>

        <section
          aria-label="Ringkasan pesanan"
          className="mt-4 grid gap-3 sm:grid-cols-3"
        >
          <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-3">
            <p className="text-sm font-medium text-ui-text-muted">
              Dipesan
            </p>
            <p className="ui-number text-xl font-semibold tracking-tight text-ui-text">
              {qty(
                Number(order.reserved_qty) +
                  Number(order.released_qty),
              )}
            </p>
          </div>

          <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border border-l-2 border-l-ui-primary bg-ui-surface px-4 py-3">
            <p className="text-sm font-medium text-ui-text-muted">
              Sudah dikirim
            </p>
            <p className="ui-number text-xl font-semibold tracking-tight text-ui-primary">
              {qty(order.shipped_qty)}
            </p>
          </div>

          <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border border-l-2 border-l-ui-warning bg-ui-surface px-4 py-3">
            <p className="text-sm font-medium text-ui-text-muted">
              Belum dikirim
            </p>
            <p className="ui-number text-xl font-semibold tracking-tight text-ui-text">
              {qty(order.open_qty)}
            </p>
          </div>
        </section>

        {Number(order.open_qty) > 0 ? (
          <p className="mt-2 text-xs text-ui-text-muted">
            Unit yang belum dikirim masih berupa reservasi dan belum mengurangi stok fisik.
          </p>
        ) : null}

        <section aria-labelledby="order-items-heading" className="mt-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2
              className="text-lg font-semibold text-ui-text"
              id="order-items-heading"
            >
              Barang
            </h2>

            {hasCancelable ? (
              <StatusBadge tone="warning">
                Dapat dibatalkan
              </StatusBadge>
            ) : null}
          </div>

          {reservations.length ===
          0 ? (
            <EmptyState
              className="mt-4"
              description="Detail item belum tersedia untuk pesanan ini."
              title="Belum ada item"
            />
          ) : (
            <div className="mt-4 overflow-hidden border-y border-ui-border">
              <div className="hidden grid-cols-[minmax(0,1fr)_7rem_7rem_7rem_7rem] gap-4 border-b border-ui-border bg-ui-surface-subtle px-4 py-3 text-xs font-semibold uppercase tracking-wide text-ui-text-muted md:grid">
                <span>Item</span>
                <span className="text-right">
                  Dipesan
                </span>
                <span className="text-right">
                  Dikirim
                </span>
                <span className="text-right">
                  Belum dikirim
                </span>
                <span className="text-right">
                  Dibatalkan
                </span>
              </div>

              <div className="divide-y divide-ui-border">
                {reservations.map(
                  (item) => (
                    <article
                      className="grid gap-3 px-4 py-4 md:grid-cols-[minmax(0,1fr)_7rem_7rem_7rem_7rem] md:items-center md:gap-4"
                      key={
                        item.order_item_id
                      }
                    >
                      <div>
                        <p className="text-sm font-semibold text-ui-text">
                          {
                            item.product_sku_snapshot
                          }
                        </p>
                        <p className="ui-code mt-1 text-xs text-ui-text-muted">
                          {
                            item.external_item_ref
                          }
                        </p>
                      </div>

                      <p className="ui-number text-right text-sm text-ui-text">
                        {qty(
                          item.quantity_ordered,
                        )}
                      </p>

                      <p className="ui-number text-right text-sm text-ui-text">
                        {qty(
                          item.consumed_qty,
                        )}
                      </p>

                      <p className="ui-number text-right text-sm font-semibold text-ui-text">
                        {qty(
                          item.open_qty,
                        )}
                      </p>

                      <p className="ui-number text-right text-sm text-ui-text">
                        {qty(
                          Number(
                            item.pre_shipment_cancelled_qty,
                          ) +
                            Number(
                              item.post_shipment_cancelled_qty,
                            ),
                        )}
                      </p>
                    </article>
                  ),
                )}
              </div>
            </div>
          )}
        </section>

        <section
          aria-labelledby="order-journey-heading"
          className="mt-6 border-t border-ui-border pt-5"
        >
          <h2
            className="text-lg font-semibold text-ui-text"
            id="order-journey-heading"
          >
            Riwayat status
          </h2>

          {events.length === 0 ? (
            <p className="mt-3 text-sm text-ui-text-muted">
              Belum ada riwayat event yang tersedia.
            </p>
          ) : (
            <ol className="mt-4 divide-y divide-ui-border">
              {events.map(
                (event) => (
                  <li
                    className="flex flex-col gap-1 py-3 first:pt-0 sm:flex-row sm:items-center sm:justify-between"
                    key={
                      event.event_id
                    }
                  >
                    <div>
                      <p className="text-sm font-semibold text-ui-text">
                        {eventLabel(
                          event.event_type_code,
                        )}
                      </p>
                      {event.note ? (
                        <p className="mt-1 text-xs text-ui-text-muted">
                          {
                            event.note
                          }
                        </p>
                      ) : null}
                    </div>

                    <time className="text-xs text-ui-text-muted">
                      {formatDate(
                        event.occurred_at,
                      )}
                    </time>
                  </li>
                ),
              )}
            </ol>
          )}
        </section>

        {cancellations.length >
        0 ? (
          <section
            aria-labelledby="cancellation-history-heading"
            className="mt-6 border-t border-ui-border pt-5"
          >
            <h2
              className="text-lg font-semibold text-ui-text"
              id="cancellation-history-heading"
            >
              Pembatalan
            </h2>

            <div className="mt-4 divide-y divide-ui-border">
              {cancellations.map(
                (cancellation) => (
                  <div
                    className="flex flex-col gap-1 py-3 first:pt-0 sm:flex-row sm:items-center sm:justify-between"
                    key={
                      cancellation.cancellation_id
                    }
                  >
                    <div>
                      <p className="ui-code text-sm font-semibold text-ui-text">
                        {
                          cancellation.cancellation_no
                        }
                      </p>
                      <p className="mt-1 text-xs text-ui-text-muted">
                        {qty(
                          cancellation.total_quantity,
                        )}{" "}
                        unit {"\u00B7"} sebelum kirim{" "}
                        {qty(
                          cancellation.pre_shipment_quantity,
                        )}{" "}
                        {"\u00B7"} sesudah kirim{" "}
                        {qty(
                          cancellation.post_shipment_quantity,
                        )}
                      </p>
                    </div>

                    <time className="text-xs text-ui-text-muted">
                      {formatDate(
                        cancellation.occurred_at,
                      )}
                    </time>
                  </div>
                ),
              )}
            </div>
          </section>
        ) : null}

        <section
          aria-labelledby="cancel-order-heading"
          className="mt-6 border-t border-ui-border pt-5"
        >
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-ui-primary">
              Tindakan
            </p>
            <h2
              className="mt-1 text-lg font-semibold text-ui-text"
              id="cancel-order-heading"
            >
              Batalkan barang
            </h2>

            {hasCancelable ? (
              <div
                aria-label="Tahapan pembatalan"
                className="mt-2 flex flex-wrap items-center gap-1 text-xs font-medium text-ui-text-muted"
              >
                <span>1 Isi</span>
                <span aria-hidden="true">{"\u2192"}</span>
                <span>2 Periksa</span>
                <span aria-hidden="true">{"\u2192"}</span>
                <span>3 Simpan</span>
              </div>
            ) : null}
          </div>

          {!hasCancelable ? (
            <p className="mt-3 text-sm text-ui-text-muted">
              Tidak ada barang yang masih dapat dibatalkan.
            </p>
          ) : (
            <div className="mt-4">
              <form
                className="grid gap-3 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 sm:grid-cols-2"
                method="get"
              >
                <label className="text-sm font-medium text-ui-text sm:col-span-2">
                  Barang yang dibatalkan
                  <select
                    className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
                    defaultValue={
                      selectedCandidate?.order_item_id ?? ""
                    }
                    name="cancelItem"
                    required
                  >
                    <option value="" disabled>
                      Pilih item
                    </option>
                    {candidates
                      .filter(
                        (row) =>
                          Number(
                            row.total_remaining_cancellable_qty,
                          ) > 0,
                      )
                      .map((row) => (
                        <option
                          key={row.order_item_id}
                          value={row.order_item_id}
                        >
                          {row.product_sku_snapshot} {"\u00B7"} {row.external_item_ref}
                        </option>
                      ))}
                  </select>
                </label>

                <label className="text-sm font-medium text-ui-text">
                  Status barang saat dibatalkan
                  <select
                    className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
                    defaultValue={selectedPhase ?? ""}
                    name="cancelPhase"
                    required
                  >
                    <option value="" disabled>
                      Pilih jenis
                    </option>
                    {selectedCandidate &&
                    Number(
                      selectedCandidate.open_reserved_qty,
                    ) > 0 ? (
                      <option value="PRE_SHIPMENT">
                        Belum dikirim {"\u2014"} batalkan reservasi
                      </option>
                    ) : null}
                    {selectedCandidate &&
                    Number(
                      selectedCandidate.remaining_post_cancellable_qty,
                    ) > 0 ? (
                      <option value="POST_SHIPMENT">
                        Sudah dikirim {"\u2014"} kembalikan stok ke batch asal
                      </option>
                    ) : null}
                  </select>
                </label>

                <label className="text-sm font-medium text-ui-text">
                  Jumlah
                  <input
                    className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
                    defaultValue={selectedQuantity}
                    min="1"
                    name="cancelQty"
                    required
                    step="1"
                    type="number"
                  />
                </label>

                <label className="text-sm font-medium text-ui-text">
                  Referensi dari marketplace
                  <input
                    className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
                    defaultValue={selectedEventRef}
                    name="cancelEventRef"
                    placeholder="CANCEL-1001"
                    required
                  />
                </label>

                <label className="text-sm font-medium text-ui-text">
                  Waktu pembatalan
                  <input
                    className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text"
                    defaultValue={selectedOccurredAt}
                    name="cancelOccurredAt"
                    required
                    type="datetime-local"
                  />
                </label>

                <label className="text-sm font-medium text-ui-text sm:col-span-2">
                  Catatan
                  <textarea
                    className="mt-2 w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 py-2 text-sm text-ui-text"
                    defaultValue={selectedNote}
                    name="cancelNote"
                    rows={3}
                  />
                </label>

                <div className="sm:col-span-2">
                  <button
                    className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
                    type="submit"
                  >
                    Periksa dampak
                  </button>
                </div>
              </form>

              {cancellationPreviewError ? (
                <Alert
                  className="mt-5"
                  title="Dampak pembatalan belum dapat diperiksa"
                  tone="warning"
                >
                  {cancellationPreviewError}
                </Alert>
              ) : null}

              {cancellationPreview &&
              cancellationDraft ? (
                <section className="mt-5 border-t border-ui-border pt-5">
                  <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                    <div>
                      <p className="text-xs font-semibold uppercase tracking-wide text-ui-primary">
                        2. Periksa dampak
                      </p>
                      <h3 className="mt-1 text-lg font-semibold text-ui-text">
                        Yang akan terjadi
                      </h3>
                    </div>

                    <StatusBadge
                      tone={
                        cancellationPreview.eligible
                          ? "selected"
                          : "danger"
                      }
                    >
                      {cancellationPreview.eligible
                        ? "Siap"
                        : "Diblokir"}
                    </StatusBadge>
                  </div>

                  <dl className="mt-4 grid gap-4 border-y border-ui-border py-4 sm:grid-cols-3">
                    <div>
                      <dt className="text-sm text-ui-text-muted">
                        Total dibatalkan
                      </dt>
                      <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                        {qty(
                          cancellationPreview.totalRequestedQuantity,
                        )}
                      </dd>
                    </div>

                    <div>
                      <dt className="text-sm text-ui-text-muted">
                        Belum dikirim
                      </dt>
                      <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                        {qty(
                          cancellationPreview.preShipmentQuantity,
                        )}
                      </dd>
                      <p className="mt-1 text-xs text-ui-text-muted">
                        Reservasi dilepas. Stok fisik tidak berubah.
                      </p>
                    </div>

                    <div>
                      <dt className="text-sm text-ui-text-muted">
                        Sudah dikirim
                      </dt>
                      <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                        {qty(
                          cancellationPreview.postShipmentQuantity,
                        )}
                      </dd>
                      <p className="mt-1 text-xs text-ui-text-muted">
                        Sistem mengembalikan stok ke batch kiriman asal dan mencatat pembalikannya untuk jejak audit.
                      </p>
                    </div>
                  </dl>

                  {cancellationPreview.blockers.length > 0 ? (
                    <div className="mt-4 space-y-2">
                      {cancellationPreview.blockers.map(
                        (blocker, index) => (
                          <Alert
                            key={`${blocker.code}-${index}`}
                            title="Pembatalan tidak dapat dilanjutkan"
                            tone="danger"
                          >
                            {blocker.message}
                          </Alert>
                        ),
                      )}
                    </div>
                  ) : null}

                  {cancellationPreview.eligible ? (
                    <form
                      action={
                        postMarketplaceCancellationAction
                      }
                      className="mt-5"
                    >
                      <input
                        name="orderId"
                        type="hidden"
                        value={order.order_id}
                      />
                      <input
                        name="draft"
                        type="hidden"
                        value={
                          serializeMarketplaceCancellationDraft(
                            cancellationDraft,
                          )
                        }
                      />
                      <input
                        name="previewBasisHash"
                        type="hidden"
                        value={
                          cancellationPreview.basisHash
                        }
                      />
                      <input
                        name="intentId"
                        type="hidden"
                        value={crypto.randomUUID()}
                      />

                      {cancellationPreview.postShipmentQuantity >
                      0 ? (
                        <label className="flex items-start gap-3 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 text-sm leading-6 text-ui-text">
                          <input
                            className="mt-1 h-4 w-4"
                            name="confirmation"
                            required
                            type="checkbox"
                          />
                          Saya sudah memeriksa jumlah dan memahami stok akan dipulihkan ke batch kiriman asal.
                        </label>
                      ) : null}

                      <button
                        className="mt-4 inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
                        type="submit"
                      >
                        Simpan pembatalan
                      </button>
                    </form>
                  ) : null}

                  <details className="mt-4 border-t border-ui-border pt-4">
                    <summary className="cursor-pointer text-sm font-semibold text-ui-text">
                      Detail teknis
                    </summary>
                    <dl className="mt-3 grid gap-3 text-xs text-ui-text-muted sm:grid-cols-2">
                      <div>
                        <dt>Request hash</dt>
                        <dd className="ui-code mt-1 break-all text-ui-text">
                          {cancellationPreview.requestHash}
                        </dd>
                      </div>
                      <div>
                        <dt>Basis hash</dt>
                        <dd className="ui-code mt-1 break-all text-ui-text">
                          {cancellationPreview.basisHash}
                        </dd>
                      </div>
                    </dl>
                  </details>
                </section>
              ) : null}
            </div>
          )}
        </section>
      </div>
    </AppShell>
  );
}
