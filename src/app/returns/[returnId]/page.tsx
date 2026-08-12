import { randomUUID } from "node:crypto";
import Link from "next/link";
import { notFound } from "next/navigation";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  OrderWorkspaceTabs,
} from "@/app/marketplace/order-workspace-tabs";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  Alert,
  StatusBadge,
} from "@/components/ui";
import {
  cancelTikTokReturnClaimAction,
  confirmLateReturnArrivalAction,
  confirmReturnReceiptAction,
  createTikTokReturnClaimAction,
  inspectReturnAction,
  markReturnLostAction,
  resolveTikTokReturnClaimAction,
  submitTikTokReturnClaimAction,
} from "@/app/returns/actions";
import {
  ReturnMutationReviewForm,
} from "@/app/returns/return-mutation-review-form";
import {
  ReturnClaimReviewForm,
} from "@/app/returns/return-claim-review-form";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  getMarketplaceShipAllocationContext,
  getReturnClaimData,
  getReturnData,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

function qty(value: number) {
  return new Intl.NumberFormat("id-ID").format(Number(value));
}

function channelLabel(code: string) {
  if (code === "TIKTOK_SHOP") return "TikTok Shop";
  if (code === "SHOPEE") return "Shopee";
  return code;
}

function returnStatus(status: string) {
  switch (status) {
    case "EXPECTED":
      return { label: "Menunggu datang", tone: "warning" as const };
    case "PARTIALLY_RECEIVED":
      return { label: "Datang sebagian", tone: "warning" as const };
    case "RECEIVED_PENDING_INSPECTION":
      return { label: "Menunggu diperiksa", tone: "warning" as const };
    case "PARTIALLY_INSPECTED":
      return { label: "Diperiksa sebagian", tone: "warning" as const };
    case "COMPLETED_SELLABLE":
      return { label: "Selesai - layak jual", tone: "selected" as const };
    case "COMPLETED_DAMAGED":
      return { label: "Selesai - rusak", tone: "neutral" as const };
    case "COMPLETED_MIXED":
      return { label: "Selesai - campuran", tone: "selected" as const };
    case "LOST":
      return { label: "Hilang", tone: "danger" as const };
    default:
      return { label: status, tone: "neutral" as const };
  }
}

function returnGuidance(status: string) {
  switch (status) {
    case "EXPECTED":
      return "Tunggu barang tiba. Jika sudah tiba, catat kedatangan. Jika sudah dipastikan hilang, tandai sebagai hilang.";
    case "PARTIALLY_RECEIVED":
      return "Sebagian barang sudah tiba. Catat sisa kedatangan atau tandai bagian yang dipastikan hilang.";
    case "RECEIVED_PENDING_INSPECTION":
      return "Barang sudah tiba dan perlu diperiksa kondisinya.";
    case "PARTIALLY_INSPECTED":
      return "Sebagian barang sudah diperiksa. Lanjutkan pemeriksaan barang yang tersisa.";
    case "LOST":
      return "Barang tercatat hilang. Tinjau klaim marketplace dan catat kedatangan terlambat jika barang kemudian ditemukan.";
    default:
      return "Tinjau kondisi retur dan lakukan tindakan yang tersedia.";
  }
}

function claimStatusLabel(status: string) {
  const labels: Record<string, string> = {
    NOT_STARTED: "Belum dikirim",
    DUE_SOON: "Segera jatuh tempo",
    SUBMITTED: "Sudah dikirim",
    RESOLVED: "Selesai",
    EXPIRED: "Lewat batas",
    EXCEPTION: "Perlu ditangani",
    CANCELLED: "Dibatalkan",
  };

  return labels[status] ?? status;
}

function claimEventLabel(code: string) {
  const labels: Record<string, string> = {
    CREATED: "Dibuat",
    SUBMITTED: "Dikirim",
    RESOLVED: "Diselesaikan",
    CANCELLED: "Dibatalkan",
    EXPIRED: "Lewat batas",
    EXCEPTION: "Perlu ditangani",
  };

  return labels[code] ?? code;
}

function auditDateTime(value: string) {
  return new Intl.DateTimeFormat("id-ID", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Jakarta",
  }).format(new Date(value));
}

function claimTone(status: string) {
  if (["EXPIRED", "EXCEPTION"].includes(status)) {
    return "danger" as const;
  }

  if (status === "DUE_SOON") {
    return "warning" as const;
  }

  if (["SUBMITTED", "RESOLVED"].includes(status)) {
    return "selected" as const;
  }

  return "neutral" as const;
}

function localDateTimeValue() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date());

  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );

  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

export default async function ReturnDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ returnId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [session, route, query] = await Promise.all([
    requireAdminSession(),
    params,
    searchParams,
  ]);

  const queryClaimId = Array.isArray(query.claimId)
    ? query.claimId[0]
    : query.claimId;

  const [data, claimData] = await Promise.all([
    getReturnData(
      session.profile.organization_id,
      route.returnId,
    ),
    getReturnClaimData({
      organizationId: session.profile.organization_id,
      returnId: route.returnId,
      claimId: queryClaimId,
      pageSize: 100,
    }),
  ]);

  const item = data.returns.find(
    (row) => row.return_id === route.returnId,
  );

  if (!item) {
    notFound();
  }

  const items = data.items.filter(
    (row) => row.return_id === item.return_id,
  );

  const shipmentAllocationContext =
    await getMarketplaceShipAllocationContext(
      session.profile.organization_id,
      items.map((row) => row.marketplace_order_item_id),
    );

  const allocationOptionsFor = (orderItemId: string) =>
    shipmentAllocationContext.filter(
      (allocation) =>
        allocation.order_item_id === orderItemId &&
        allocation.remaining_quantity > 0,
    );

  const receiptLines = data.receiptLines.filter(
    (row) => row.return_id === item.return_id,
  );

  const inspectionAllocations =
    data.inspectionAllocations.filter(
      (row) => row.return_id === item.return_id,
    );

  const inspectedByReceipt = new Map<string, number>();

  for (const allocation of inspectionAllocations) {
    inspectedByReceipt.set(
      allocation.receipt_line_id,
      (inspectedByReceipt.get(allocation.receipt_line_id) ?? 0) +
        Number(allocation.quantity_allocated),
    );
  }

  const pendingForReceipt = (receiptLineId: string, received: number) =>
    Math.max(
      0,
      Number(received) -
        (inspectedByReceipt.get(receiptLineId) ?? 0),
    );

  const pendingReceiptLines = receiptLines.filter(
    (line) =>
      pendingForReceipt(
        line.receipt_line_id,
        line.quantity_received,
      ) > 0,
  );

  const claims = claimData.claims.filter(
    (claim) => claim.return_id === item.return_id,
  );

  const selectedClaim =
    queryClaimId
      ? claimData.selectedClaim
      : claims[0] ?? null;

  const selectedClaimItems = selectedClaim
    ? claimData.claimItems.filter(
        (claimItem) => claimItem.claim_id === selectedClaim.id,
      )
    : [];

  const selectedClaimEvents = selectedClaim
    ? claimData.claimEvents.filter(
        (event) => event.claim_id === selectedClaim.id,
      )
    : [];

  const selectedLateArrivalLinks = selectedClaim
    ? claimData.lateArrivalClaimLinks.filter(
        (link) => link.claim_id === selectedClaim.id,
      )
    : [];

  const lateArrivalById = new Map(
    claimData.lateArrivals.map((lateArrival) => [
      lateArrival.late_arrival_id,
      lateArrival,
    ]),
  );

  const committedByItem = new Map<string, number>();

  for (const claimItem of claimData.activeClaimItems) {
    committedByItem.set(
      claimItem.return_item_id,
      (committedByItem.get(claimItem.return_item_id) ?? 0) +
        Number(claimItem.quantity),
    );
  }

  const eligibleClaimItems =
    item.channel_code === "TIKTOK_SHOP"
      ? items
          .map((row) => {
            const netLost =
              Number(row.net_lost_qty ?? row.lost_qty) -
              (committedByItem.get(row.return_item_id) ?? 0);

            return {
              ...row,
              remainingClaimable: Math.max(0, netLost),
            };
          })
          .filter((row) => row.remainingClaimable > 0)
      : [];

  const lateArrivalItems = items
    .map((row) => ({
      ...row,
      remainingLost: Math.max(
        0,
        Number(row.lost_qty) -
          Number(row.late_arrival_qty ?? 0),
      ),
    }))
    .filter((row) => row.remainingLost > 0);

  const success = Array.isArray(query.success)
    ? query.success[0]
    : query.success;
  const error = Array.isArray(query.error)
    ? query.error[0]
    : query.error;

  const returnPresentation = returnStatus(item.status_code);
  const guidance = returnGuidance(item.status_code);

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          eyebrow="Retur & Klaim"
          title={item.external_return_ref}
          description={`${channelLabel(item.channel_code)} \u00B7 ${item.marketplace_order_ref}`}
        />

        <OrderWorkspaceTabs active="returns" />

        <div className="mt-4 flex flex-wrap items-center gap-3">
          <StatusBadge tone={returnPresentation.tone}>
            {returnPresentation.label}
          </StatusBadge>
          <p className="text-sm text-ui-text-muted">
            {guidance}
          </p>
        </div>

        <div className="mt-4 flex items-center gap-3">
          <Link
            href="/returns"
            className="text-sm font-semibold text-ui-primary hover:underline"
          >
            Kembali ke Retur & Klaim
          </Link>
        </div>

        {success ? (
          <Alert
            className="mt-5"
            tone="success"
            title="Berhasil"
          >
            {success}
          </Alert>
        ) : null}

        {error ? (
          <Alert
            className="mt-5"
            tone="danger"
            title="Belum berhasil"
          >
            {error}
          </Alert>
        ) : null}

        <section
          className="mt-5 grid gap-3 sm:grid-cols-3"
          aria-label="Ringkasan proses retur"
        >
          <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-3">
            <p className="text-sm font-medium text-ui-text-muted">
              Diharapkan
            </p>
            <p className="ui-number text-xl font-semibold text-ui-text">
              {qty(item.expected_qty)}
            </p>
          </div>
          <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border border-l-2 border-l-ui-primary bg-ui-surface px-4 py-3">
            <p className="text-sm font-medium text-ui-text-muted">
              Sudah datang
            </p>
            <p className="ui-number text-xl font-semibold text-ui-text">
              {qty(item.received_qty)}
            </p>
          </div>
          <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border border-l-2 border-l-ui-warning bg-ui-surface px-4 py-3">
            <p className="text-sm font-medium text-ui-text-muted">
              Menunggu datang
            </p>
            <p className="ui-number text-xl font-semibold text-ui-text">
              {qty(item.pending_arrival_qty)}
            </p>
          </div>
        </section>

        {item.status_code === "LOST" && Number(item.lost_qty) > 0 ? (
          <p className="mt-2 text-sm font-medium text-ui-text-muted">
            {qty(item.lost_qty)} unit dinyatakan hilang.
          </p>
        ) : null}

        <section className="mt-7">
          <div>
            <h2 className="text-lg font-semibold text-ui-text">
              Kondisi fisik
            </h2>
            <p className="mt-1 text-sm text-ui-text-muted">
              Hasil pemeriksaan barang yang sudah datang.
            </p>
          </div>

          {Number(item.received_qty) === 0 ? (
            <div className="mt-3 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle px-4 py-3">
              <p className="text-sm font-medium text-ui-text">
                {item.status_code === "LOST" ? "Tidak diperiksa" : "Belum diperiksa"}
              </p>
              <p className="mt-1 text-sm text-ui-text-muted">
                {item.status_code === "LOST"
                  ? "Barang dinyatakan hilang sebelum diterima, sehingga tidak ada pemeriksaan fisik."
                  : "Menunggu barang tiba sebelum pemeriksaan fisik dapat dilakukan."}
              </p>
            </div>
          ) : (
            <>
              <dl className="mt-4 grid gap-3 sm:grid-cols-3">
                <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-3">
                  <dt className="text-sm text-ui-text-muted">
                    Layak jual
                  </dt>
                  <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                    {qty(item.sellable_qty)}
                  </dd>
                </div>
                <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-3">
                  <dt className="text-sm text-ui-text-muted">
                    Rusak
                  </dt>
                  <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                    {qty(item.damaged_qty)}
                  </dd>
                </div>
                <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-3">
                  <dt className="text-sm text-ui-text-muted">
                    Hilang
                  </dt>
                  <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
                    {qty(item.lost_qty)}
                  </dd>
                </div>
              </dl>

              <p className="mt-3 text-sm leading-6 text-ui-text-muted">
                Layak jual menambah stok melalui batch retur baru. Rusak dan hilang hanya dicatat sebagai kondisi fisik dan tidak membuat perubahan stok kedua.
              </p>
            </>
          )}
        </section>

        <section className="mt-7 border-t border-ui-border pt-6">
          <h2 className="text-lg font-semibold text-ui-text">
            Barang retur
          </h2>

          <div className="mt-4 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface">
            <div className="hidden grid-cols-[minmax(0,1fr)_6rem_6rem_6rem_6rem] gap-3 border-b border-ui-border bg-ui-surface-subtle px-4 py-2 text-xs font-medium text-ui-text-muted md:grid">
              <span>Barang</span>
              <span className="text-right">Diharapkan</span>
              <span className="text-right">Diterima</span>
              <span className="text-right">Diperiksa</span>
              <span className="text-right">Hilang</span>
            </div>
            <div className="divide-y divide-ui-border">
            {items.map((row) => (
              <article
                className="grid gap-3 px-4 py-4 md:grid-cols-[minmax(0,1fr)_6rem_6rem_6rem_6rem]"
                key={row.return_item_id}
              >
                <div>
                  <p className="text-sm font-semibold text-ui-text">
                    {row.product_sku_snapshot}
                  </p>
                  <p className="ui-code mt-1 text-xs text-ui-text-muted">
                    {row.marketplace_item_ref}
                  </p>
                </div>
                <p className="ui-number text-right text-sm">
                  {qty(row.expected_qty)}
                </p>
                <p className="ui-number text-right text-sm">
                  {qty(row.received_qty)}
                </p>
                <p className="ui-number text-right text-sm">
                  {qty(row.sellable_qty + row.damaged_qty)}
                </p>
                <p className="ui-number text-right text-sm">
                  {qty(row.lost_qty)}
                </p>
              </article>
            ))}
            </div>
          </div>
        </section>

        <div id="return-actions" className="mt-8 border-t border-ui-border pt-7">
          <div>
            <h2 className="text-lg font-semibold text-ui-text">
              Tindakan berikutnya
            </h2>

          </div>

          {item.pending_arrival_qty > 0 ? (
            <section className="mt-5 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
              <h2 className="text-lg font-semibold text-ui-text">
                Catat Kedatangan
              </h2>
              <p className="mt-1 text-sm text-ui-text-muted">
                Kedatangan fisik dicatat tanpa menambah stok.
              </p>
              <p className="mt-3 text-sm font-medium text-ui-text-muted">
                1 Isi {"\u2192"} 2 Periksa {"\u2192"} 3 Simpan
              </p>

              <ReturnMutationReviewForm
                action={confirmReturnReceiptAction}
                className="mt-4 space-y-4"
                kind="receipt"
                submitLabel="Simpan Kedatangan"
              >
                <input type="hidden" name="returnId" value={item.return_id} />
                <input type="hidden" name="returnRef" value={item.external_return_ref} />

                <div className="grid gap-4 sm:grid-cols-2">
                  <label className="text-sm font-medium">
                    Referensi kedatangan
                    <input
                      name="receiptRef"
                      required
                      className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                    />
                  </label>
                  <label className="text-sm font-medium">
                    Waktu
                    <input
                      name="occurredAt"
                      type="datetime-local"
                      defaultValue={localDateTimeValue()}
                      required
                      className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                    />
                  </label>
                </div>

                <div className="space-y-3">
                  {items
                    .filter((row) => row.pending_arrival_qty > 0)
                    .flatMap((row) => {
                      const allocations = allocationOptionsFor(
                        row.marketplace_order_item_id,
                      );
                      const options =
                        allocations.length > 0
                          ? allocations.map((allocation) => ({
                              allocation,
                              lineKey:
                                `${row.return_item_id}:` +
                                allocation.allocation_id,
                            }))
                          : [
                              {
                                allocation: null,
                                lineKey:
                                  `${row.return_item_id}:UNVERIFIED`,
                              },
                            ];

                      return options.map(({ allocation, lineKey }) => {
                        const maximum = Math.min(
                          row.pending_arrival_qty,
                          allocation?.remaining_quantity ??
                            row.pending_arrival_qty,
                        );

                        return (
                          <label
                            key={lineKey}
                            className="grid gap-3 rounded-[var(--ui-radius-md)] border border-ui-border p-3 lg:grid-cols-[auto_minmax(0,1fr)_8rem]"
                          >
                            <input
                              type="checkbox"
                              name="receiptLineKey"
                              value={lineKey}
                              data-return-item-id={row.return_item_id}
                              data-product-sku={row.product_sku_snapshot}
                              data-pending={row.pending_arrival_qty}
                              data-verified={allocation ? "true" : "false"}
                              data-batch-code={allocation?.batch_code_snapshot ?? ""}
                              data-expiry-date={allocation?.expiry_date_snapshot ?? ""}
                              className="mt-1 h-4 w-4"
                            />
                            <span>
                              <span className="block text-sm font-semibold">
                                {row.product_sku_snapshot}
                              </span>
                              {allocation ? (
                                <>
                                  <span className="mt-1 block text-xs text-ui-text-muted">
                                    Batch asal {allocation.batch_code_snapshot}
                                    {" \u00B7 "}
                                    kedaluwarsa {allocation.expiry_date_snapshot}
                                  </span>
                                  <span className="block text-xs text-ui-text-muted">
                                    Kapasitas kiriman tersisa{" "}
                                    {qty(allocation.remaining_quantity)}
                                  </span>
                                </>
                              ) : (
                                <span className="mt-1 block text-xs text-ui-text-muted">
                                  Batch asal belum dapat diverifikasi. Kedatangan tetap tidak mengubah stok; barang belum dapat ditandai layak jual sampai batch asal terverifikasi.
                                </span>
                              )}
                            </span>
                            <input
                              type="number"
                              min="1"
                              max={maximum}
                              defaultValue={maximum}
                              name={`receiptQuantity_${lineKey}`}
                              className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                            />
                          </label>
                        );
                      });
                    })}
                </div>

              </ReturnMutationReviewForm>

            </section>
          ) : null}

          {pendingReceiptLines.length > 0 ? (
            <section className="mt-5 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
              <h2 className="text-lg font-semibold text-ui-text">
                Periksa Barang
              </h2>
              <p className="mt-1 text-sm text-ui-text-muted">
                Layak jual akan masuk ke batch retur baru. Rusak hanya dicatat sebagai kondisi fisik.
              </p>
              <p className="mt-3 text-sm font-medium text-ui-text-muted">
                1 Isi {"\u2192"} 2 Periksa {"\u2192"} 3 Simpan
              </p>

              <ReturnMutationReviewForm
                action={inspectReturnAction}
                className="mt-4 space-y-4"
                kind="inspection"
                submitLabel="Simpan Pemeriksaan"
              >
                <input type="hidden" name="returnId" value={item.return_id} />
                <input type="hidden" name="returnRef" value={item.external_return_ref} />

                <div className="grid gap-4 sm:grid-cols-2">
                  <label className="text-sm font-medium">
                    Referensi pemeriksaan
                    <input
                      name="inspectionRef"
                      required
                      className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                    />
                  </label>
                  <label className="text-sm font-medium">
                    Waktu
                    <input
                      name="occurredAt"
                      type="datetime-local"
                      defaultValue={localDateTimeValue()}
                      required
                      className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                    />
                  </label>
                </div>

                <div className="space-y-3">
                  {pendingReceiptLines.map((line) => {
                    const pending = pendingForReceipt(
                      line.receipt_line_id,
                      line.quantity_received,
                    );

                    return (
                      <div
                        key={line.receipt_line_id}
                        className="grid gap-3 rounded-[var(--ui-radius-md)] border border-ui-border p-3 sm:grid-cols-[auto_1fr_7rem_7rem]"
                      >
                        <input
                          type="checkbox"
                          name="inspectionReceiptLineId"
                          value={line.receipt_line_id}
                          data-product-sku={line.product_sku_snapshot}
                          data-pending={pending}
                          data-verified={line.batch_identity_verified ? "true" : "false"}
                          className="mt-1 h-4 w-4"
                        />
                        <div>
                          <p className="text-sm font-semibold">
                            {line.product_sku_snapshot}
                          </p>
                          <p className="text-xs text-ui-text-muted">
                            Belum diperiksa {qty(pending)}
                          </p>
                        </div>
                        <label className="text-xs text-ui-text-muted">
                          Layak jual
                          <input
                            type="number"
                            min="0"
                            max={
                              line.batch_identity_verified
                                ? pending
                                : 0
                            }
                            defaultValue="0"
                            disabled={!line.batch_identity_verified}
                            name={`sellableQuantity_${line.receipt_line_id}`}
                            className="mt-1 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-2 text-sm disabled:cursor-not-allowed disabled:opacity-50"
                          />
                        </label>
                        <label className="text-xs text-ui-text-muted">
                          Rusak
                          <input
                            type="number"
                            min="0"
                            max={pending}
                            defaultValue="0"
                            name={`damagedQuantity_${line.receipt_line_id}`}
                            className="mt-1 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-2 text-sm"
                          />
                        </label>
                      </div>
                    );
                  })}
                </div>

              </ReturnMutationReviewForm>

            </section>
          ) : null}

          {item.pending_arrival_qty > 0 ? (
            <details className="mt-5 rounded-[var(--ui-radius-lg)] border border-dashed border-ui-border bg-ui-surface-subtle p-5">
              <summary className="cursor-pointer list-none">
                <span className="text-base font-semibold text-ui-text">
                  Jika barang dinyatakan hilang
                </span>
                <span className="mt-1 block text-sm text-ui-text-muted">
                  Buka hanya jika barang memang sudah dipastikan hilang.
                </span>
                <span className="mt-2 block text-xs font-semibold text-ui-primary">
                  Buka tindakan {"\u203A"}
                </span>
              </summary>
              <p className="mt-4 text-sm text-ui-text-muted">
                Penetapan hilang tidak membuat perubahan stok tambahan.
              </p>
              <p className="mt-3 text-sm font-medium text-ui-text-muted">
                1 Isi {"\u2192"} 2 Periksa {"\u2192"} 3 Simpan
              </p>

              <ReturnMutationReviewForm
                action={markReturnLostAction}
                className="mt-4 space-y-4"
                kind="lost"
                submitLabel="Tandai Hilang"
              >
                <input type="hidden" name="returnId" value={item.return_id} />
                <input type="hidden" name="returnRef" value={item.external_return_ref} />

                <div className="grid gap-4 sm:grid-cols-2">
                  <label className="text-sm font-medium">
                    Referensi kehilangan
                    <input
                      name="lostEventRef"
                      required
                      className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                    />
                  </label>
                  <label className="text-sm font-medium">
                    Waktu
                    <input
                      name="occurredAt"
                      type="datetime-local"
                      defaultValue={localDateTimeValue()}
                      required
                      className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                    />
                  </label>
                </div>

                <div className="space-y-3">
                  {items
                    .filter((row) => row.pending_arrival_qty > 0)
                    .map((row) => (
                      <label
                        key={row.return_item_id}
                        className="grid gap-3 rounded-[var(--ui-radius-md)] border border-ui-border p-3 sm:grid-cols-[auto_1fr_8rem]"
                      >
                        <input
                          type="checkbox"
                          name="lostItemId"
                          value={row.return_item_id}
                          data-product-sku={row.product_sku_snapshot}
                          data-pending={row.pending_arrival_qty}
                          className="mt-1 h-4 w-4"
                        />
                        <span>
                          <span className="block text-sm font-semibold">
                            {row.product_sku_snapshot}
                          </span>
                          <span className="text-xs text-ui-text-muted">
                            Sisa belum tiba {qty(row.pending_arrival_qty)}
                          </span>
                        </span>
                        <input
                          type="number"
                          min="1"
                          max={row.pending_arrival_qty}
                          defaultValue={row.pending_arrival_qty}
                          name={`lostQuantity_${row.return_item_id}`}
                          className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                        />
                      </label>
                    ))}
                </div>

              </ReturnMutationReviewForm>

            </details>
          ) : null}
        </div>

        <section
          className={
            claims.length > 0 ||
            eligibleClaimItems.length > 0 ||
            lateArrivalItems.length > 0
              ? item.pending_arrival_qty > 0 || pendingReceiptLines.length > 0
                ? "mt-8 border-t border-ui-border pt-7"
                : "mt-4"
              : "hidden"
          }
          id="claim-detail"
        >
          <h2 className="text-lg font-semibold text-ui-text">
            Klaim marketplace
          </h2>

          {item.channel_code !== "TIKTOK_SHOP" ? (
            <p className="mt-3 text-sm text-ui-text-muted">
              Klaim marketplace pada alur ini tersedia untuk retur TikTok Shop.
            </p>
          ) : (
            <>
              {claims.length > 1 ? (
                <div className="mt-4 divide-y divide-ui-border border-y border-ui-border">
                  {claims.map((claim) => (
                    <Link
                      key={claim.id}
                      href={`/returns/${encodeURIComponent(item.return_id)}?claimId=${encodeURIComponent(claim.id)}#claim-detail`}
                      className="flex flex-col gap-2 px-4 py-4 hover:bg-ui-surface-subtle sm:flex-row sm:items-center sm:justify-between"
                    >
                      <div>
                        <p className="text-sm font-semibold text-ui-text">
                          {claim.external_claim_ref || "Belum dikirim"}
                        </p>
                        <p className="mt-1 text-xs text-ui-text-muted">
                          Batas klaim{" "}
                          {new Intl.DateTimeFormat("id-ID", {
                            dateStyle: "medium",
                            timeZone: "Asia/Jakarta",
                          }).format(new Date(claim.deadline_at))}
                        </p>
                      </div>
                      <StatusBadge tone={claimTone(claim.status_code)}>
                        {claimStatusLabel(claim.status_code)}
                      </StatusBadge>
                    </Link>
                  ))}
                </div>
              ) : null}

              {selectedClaim ? (
                <div className="mt-5 rounded-[var(--ui-radius-md)] border border-ui-border p-4">
                  <div className="flex flex-wrap items-center gap-3">
                    <StatusBadge tone={claimTone(selectedClaim.status_code)}>
                      {claimStatusLabel(selectedClaim.status_code)}
                    </StatusBadge>
                    <p className="text-sm text-ui-text-muted">
                      Klaim tidak mengubah stok.
                    </p>
                  </div>

                  <div className="mt-4 rounded-[var(--ui-radius-md)] border border-ui-warning bg-ui-warning-subtle px-4 py-3">
                    <p className="text-sm font-semibold text-ui-text">
                      Batas klaim:{" "}
                      {new Intl.DateTimeFormat("id-ID", {
                        dateStyle: "long",
                        timeZone: "Asia/Jakarta",
                      }).format(new Date(selectedClaim.deadline_at))}
                    </p>
                    <p className="mt-1 text-xs text-ui-text-muted">
                      Tenggat dihitung 40 hari sejak retur dibuat.
                    </p>
                  </div>

                  <div className="mt-4 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4">
                    <p className="text-xs font-semibold text-ui-primary">
                      Detail klaim
                    </p>
                    <div className="mt-3 grid gap-3 sm:grid-cols-2">
                      <div>
                        <p className="text-xs text-ui-text-muted">Dampak stok</p>
                        <p className="mt-1 text-sm font-semibold text-ui-text">
                          {selectedClaim.stock_effect_code}
                        </p>
                      </div>
                      <div>
                        <p className="text-xs text-ui-text-muted">Quantity diklaim</p>
                        <p className="mt-1 text-sm font-semibold text-ui-text">
                          {qty(
                            selectedClaimItems.reduce(
                              (total, claimItem) => total + Number(claimItem.quantity),
                              0,
                            ),
                          )} unit
                        </p>
                      </div>
                    </div>

                    {selectedClaimItems.length > 0 ? (
                      <div className="mt-4 divide-y divide-ui-border border-y border-ui-border">
                        {selectedClaimItems.map((claimItem) => (
                          <div className="py-4" key={claimItem.id}>
                            <div className="flex flex-wrap items-start justify-between gap-3">
                              <div>
                                <p className="text-sm font-semibold text-ui-text">
                                  {claimItem.product_sku_snapshot}
                                </p>
                                <p className="mt-1 text-xs text-ui-text-muted">
                                  Source line: {claimItem.source_line_ref_snapshot}
                                </p>
                              </div>
                              <p className="ui-number text-sm font-semibold text-ui-text">
                                {qty(claimItem.quantity)} unit
                              </p>
                            </div>
                            <p className="mt-2 text-xs text-ui-text-muted">
                              Quantity hilang yang memenuhi syarat saat klaim dibuat:{" "}
                              {qty(claimItem.eligible_lost_qty_snapshot)}
                            </p>
                            <details className="mt-3">
                              <summary className="cursor-pointer text-xs font-semibold text-ui-primary">
                                Provenance historis
                              </summary>
                              <pre className="mt-2 max-h-72 overflow-auto whitespace-pre-wrap rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-3 text-[11px] leading-5 text-ui-text-muted">
                                {JSON.stringify(
                                  claimItem.canonical_components_snapshot,
                                  null,
                                  2,
                                )}
                              </pre>
                            </details>
                          </div>
                        ))}
                      </div>
                    ) : null}
                  </div>

                  {selectedClaimEvents.length > 0 ? (
                    <div className="mt-4 rounded-[var(--ui-radius-md)] border border-ui-border p-4">
                      <p className="text-sm font-semibold text-ui-text">
                        Riwayat klaim
                      </p>
                      <p className="mt-1 text-xs text-ui-text-muted">
                        Jejak audit immutable dari pembuatan sampai status terakhir.
                      </p>
                      <div className="mt-3 divide-y divide-ui-border border-y border-ui-border">
                        {selectedClaimEvents.map((event) => (
                          <div className="py-3" key={event.id}>
                            <div className="flex flex-wrap items-center justify-between gap-2">
                              <p className="text-sm font-semibold text-ui-text">
                                {claimEventLabel(event.event_type_code)}
                              </p>
                              <time className="text-xs text-ui-text-muted">
                                {auditDateTime(event.occurred_at)}
                              </time>
                            </div>
                            {event.note ? (
                              <p className="mt-1 text-xs text-ui-text-muted">
                                {event.note}
                              </p>
                            ) : null}
                            <details className="mt-2">
                              <summary className="cursor-pointer text-xs font-semibold text-ui-primary">
                                Detail audit
                              </summary>
                              <pre className="mt-2 max-h-72 overflow-auto whitespace-pre-wrap rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-3 text-[11px] leading-5 text-ui-text-muted">
                                {JSON.stringify(event.snapshot, null, 2)}
                              </pre>
                            </details>
                          </div>
                        ))}
                      </div>
                    </div>
                  ) : null}

                  {selectedLateArrivalLinks.length > 0 ? (
                    <div className="mt-4 rounded-[var(--ui-radius-md)] border border-ui-warning bg-ui-warning-subtle p-4">
                      <p className="text-sm font-semibold text-ui-text">
                        Kedatangan terlambat terkait
                      </p>
                      <p className="mt-1 text-xs text-ui-text-muted">
                        Riwayat klaim tetap dipertahankan; kedatangan terlambat tidak mengubah stok.
                      </p>
                      <div className="mt-3 space-y-3">
                        {selectedLateArrivalLinks.map((link) => {
                          const lateArrival = lateArrivalById.get(
                            link.late_arrival_id,
                          );

                          return (
                            <div
                              className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-3"
                              key={link.late_arrival_claim_link_id}
                            >
                              <div className="flex flex-wrap items-center justify-between gap-2">
                                <p className="text-sm font-semibold text-ui-text">
                                  {lateArrival?.late_arrival_reference ??
                                    link.late_arrival_id}
                                </p>
                                <StatusBadge
                                  tone={link.warning_required ? "warning" : "neutral"}
                                >
                                  {link.warning_required
                                    ? "Perlu diperiksa"
                                    : "Tercatat"}
                                </StatusBadge>
                              </div>
                              <p className="mt-2 text-xs text-ui-text-muted">
                                Receipt: {lateArrival?.receipt_ref ?? "Tidak tersedia"}
                              </p>
                              <p className="mt-1 text-xs text-ui-text-muted">
                                Status klaim saat terdeteksi:{" "}
                                {claimStatusLabel(link.claim_status_snapshot)}
                                {" \u00b7 "}Dampak stok{" "}
                                {lateArrival?.stock_effect_code ?? "NONE"}
                              </p>
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  ) : null}

                  {claimData.notifications.length > 0 ? (
                    <div className="mt-4 rounded-[var(--ui-radius-md)] border border-ui-border p-4">
                      <p className="text-sm font-semibold text-ui-text">
                        Notifikasi terkait
                      </p>
                      <p className="mt-1 text-xs text-ui-text-muted">
                        Riwayat pengingat untuk klaim ini tetap tersedia sebagai bukti. Tindakan klaim dilakukan langsung di halaman retur ini.
                      </p>
                      <div className="mt-3 divide-y divide-ui-border border-y border-ui-border">
                        {claimData.notifications.map((notification) => (
                          <article
                            className="flex items-start justify-between gap-3 py-3 text-sm"
                            key={notification.notification_id}
                          >
                            <span>
                              <span className="block font-semibold text-ui-text">
                                {notification.title}
                              </span>
                              <span className="mt-1 block text-xs text-ui-text-muted">
                                {notification.message}
                              </span>
                            </span>
                            <StatusBadge
                              tone={
                                notification.lifecycle_status_code === "RESOLVED"
                                  ? "selected"
                                  : notification.severity_code === "CRITICAL"
                                    ? "danger"
                                    : notification.severity_code === "HIGH"
                                      ? "warning"
                                      : "neutral"
                              }
                            >
                              {notification.lifecycle_status_code}
                            </StatusBadge>
                          </article>
                        ))}
                      </div>
                    </div>
                  ) : null}

                  {!selectedClaim.external_claim_ref &&
                  ["NOT_STARTED", "DUE_SOON", "EXPIRED"].includes(
                    selectedClaim.status_code,
                  ) ? (
                    <ReturnClaimReviewForm
                      action={submitTikTokReturnClaimAction}
                      className="mt-5 space-y-4"
                      deadlineLabel={new Intl.DateTimeFormat("id-ID", {
                        dateStyle: "long",
                        timeZone: "Asia/Jakarta",
                      }).format(new Date(selectedClaim.deadline_at))}
                      kind="submit"
                      submitLabel="Periksa Klaim"
                    >
                      <input type="hidden" name="returnId" value={item.return_id} />
                      <input type="hidden" name="claimId" value={selectedClaim.id} />
                      <label className="block text-sm font-medium">
                        Referensi klaim TikTok
                        <input
                          name="externalClaimRef"
                          required
                          className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                        />
                      </label>
                      <input
                        type="hidden"
                        name="occurredAt"
                        value={localDateTimeValue()}
                      />
                    </ReturnClaimReviewForm>

                  ) : null}

                  {selectedClaim.external_claim_ref &&
                  ["SUBMITTED", "EXPIRED"].includes(
                    selectedClaim.status_code,
                  ) ? (
                    <ReturnClaimReviewForm
                      action={resolveTikTokReturnClaimAction}
                      className="mt-5 space-y-4"
                      kind="resolve"
                      submitLabel="Periksa Penyelesaian Klaim"
                    >
                      <input type="hidden" name="returnId" value={item.return_id} />
                      <input type="hidden" name="claimId" value={selectedClaim.id} />
                      <input
                        type="hidden"
                        name="occurredAt"
                        value={localDateTimeValue()}
                      />
                      <label className="block text-sm font-medium">
                        Hasil klaim
                        <select
                          name="resolutionCode"
                          required
                          defaultValue=""
                          className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3"
                        >
                          <option value="" disabled>
                            Pilih hasil
                          </option>
                          <option value="APPROVED">Disetujui</option>
                          <option value="PARTIALLY_APPROVED">Disetujui sebagian</option>
                          <option value="REJECTED">Ditolak</option>
                          <option value="NO_ACTION">Tidak ada tindakan</option>
                          <option value="OTHER">Lainnya</option>
                        </select>
                      </label>
                    </ReturnClaimReviewForm>

                  ) : null}

                  {["NOT_STARTED", "DUE_SOON", "EXCEPTION"].includes(
                    selectedClaim.status_code,
                  ) ? (
                    <details className="mt-5 border-t border-ui-border pt-5">
                      <summary className="cursor-pointer list-none">
                        <span className="text-sm font-semibold text-ui-text-muted">
                          Batalkan klaim <span aria-hidden="true">{"\u203A"}</span>
                        </span>
                        <span className="mt-1 block text-xs text-ui-text-muted">
                          Gunakan hanya jika klaim tidak perlu dilanjutkan.
                        </span>
                      </summary>
                      <ReturnClaimReviewForm
                        action={cancelTikTokReturnClaimAction}
                        className="mt-4 space-y-4"
                        kind="cancel"
                        submitLabel="Batalkan Klaim"
                        submitVariant="danger"
                      >
                      <input type="hidden" name="returnId" value={item.return_id} />
                      <input type="hidden" name="claimId" value={selectedClaim.id} />
                      <input
                        type="hidden"
                        name="occurredAt"
                        value={localDateTimeValue()}
                      />
                        <label className="block text-sm font-medium">
                          Alasan pembatalan klaim
                          <textarea
                            name="reason"
                            required
                            rows={3}
                            className="mt-2 w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3 py-2"
                          />
                        </label>
                      </ReturnClaimReviewForm>
                    </details>

                  ) : null}
                </div>
              ) : eligibleClaimItems.length > 0 ? (
                <ReturnClaimReviewForm
                  action={createTikTokReturnClaimAction}
                  className="mt-4 space-y-4 rounded-[var(--ui-radius-md)] border border-ui-border p-4"
                  kind="create"
                  submitLabel="Buat Klaim"
                >
                  <input type="hidden" name="returnId" value={item.return_id} />
                  <input
                    type="hidden"
                    name="idempotencyKey"
                    value={`returns:claim:create:${randomUUID()}`}
                  />
                  <input type="hidden" name="claimTypeCode" value="LOST_RETURN" />
                  <input
                    type="hidden"
                    name="occurredAt"
                    value={localDateTimeValue()}
                  />

                  <div className="space-y-3">
                    {eligibleClaimItems.map((row) => (
                      <label
                        key={row.return_item_id}
                        className="grid gap-3 rounded-[var(--ui-radius-md)] border border-ui-border p-3 sm:grid-cols-[auto_1fr_8rem]"
                      >
                        <input
                          type="checkbox"
                          name="claimItemId"
                          value={row.return_item_id}
                          data-product-sku={row.product_sku_snapshot}
                          data-maximum={row.remainingClaimable}
                          className="mt-1 h-4 w-4"
                        />
                        <span>
                          <span className="block text-sm font-semibold">
                            {row.product_sku_snapshot}
                          </span>
                          <span className="text-xs text-ui-text-muted">
                            Masih dapat diklaim {qty(row.remainingClaimable)}
                          </span>
                        </span>
                        <input
                          type="number"
                          min="1"
                          max={row.remainingClaimable}
                          defaultValue={row.remainingClaimable}
                          name={`quantity_${row.return_item_id}`}
                          className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                        />
                      </label>
                    ))}
                  </div>

                </ReturnClaimReviewForm>

              ) : (
                <p className="mt-3 text-sm text-ui-text-muted">
                  Tidak ada quantity hilang yang masih dapat dibuatkan klaim baru.
                </p>
              )}

              {lateArrivalItems.length > 0 ? (
                <details className="mt-5 rounded-[var(--ui-radius-lg)] border border-dashed border-ui-border bg-ui-surface-subtle p-4">
                  <summary className="cursor-pointer list-none">
                    <span className="text-base font-semibold text-ui-text">
                      Kedatangan Setelah Dinyatakan Hilang
                    </span>
                    <span className="mt-1 block text-sm text-ui-text-muted">
                      Buka jika barang yang sebelumnya dinyatakan hilang kemudian tiba.
                    </span>
                    <span className="mt-2 block text-xs font-semibold text-ui-primary">
                      Buka formulir {"\u203A"}
                    </span>
                  </summary>
                  <ReturnMutationReviewForm
                    action={confirmLateReturnArrivalAction}
                    className="mt-4 space-y-4"
                    kind="late-arrival"
                    submitLabel="Catat Kedatangan Terlambat"
                  >
                    <p className="text-sm text-ui-text-muted">
                      Catat kedatangan terlambat untuk mengoreksi jumlah hilang bersih. Aksi ini tetap tidak mengubah stok.
                    </p>

                  <input type="hidden" name="returnId" value={item.return_id} />
                  <input type="hidden" name="returnRef" value={item.external_return_ref} />
                  <input
                    type="hidden"
                    name="sourceLineRef"
                    value={`LATE-${item.external_return_ref}`}
                  />

                  <div className="grid gap-4 sm:grid-cols-2">
                    <label className="text-sm font-medium">
                      Referensi kedatangan terlambat
                      <input
                        name="lateArrivalReference"
                        required
                        className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                      />
                    </label>
                    <label className="text-sm font-medium">
                      Referensi penerimaan
                      <input
                        name="receiptRef"
                        required
                        className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                      />
                    </label>
                    <label className="text-sm font-medium sm:col-span-2">
                      Waktu
                      <input
                        name="occurredAt"
                        type="datetime-local"
                        defaultValue={localDateTimeValue()}
                        required
                        className="mt-2 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                      />
                    </label>
                  </div>

                  <div className="space-y-3">
                    {lateArrivalItems.flatMap((row) => {
                      const allocations = allocationOptionsFor(
                        row.marketplace_order_item_id,
                      );
                      const options =
                        allocations.length > 0
                          ? allocations.map((allocation) => ({
                              allocation,
                              lineKey:
                                `${row.return_item_id}:` +
                                allocation.allocation_id,
                            }))
                          : [
                              {
                                allocation: null,
                                lineKey:
                                  `${row.return_item_id}:UNVERIFIED`,
                              },
                            ];

                      return options.map(({ allocation, lineKey }) => {
                        const maximum = Math.min(
                          row.remainingLost,
                          allocation?.remaining_quantity ??
                            row.remainingLost,
                        );

                        return (
                          <label
                            key={lineKey}
                            className="grid gap-3 rounded-[var(--ui-radius-md)] border border-ui-border p-3 lg:grid-cols-[auto_minmax(0,1fr)_8rem]"
                          >
                            <input
                              type="checkbox"
                              name="lateReturnLineKey"
                              value={lineKey}
                              data-return-item-id={row.return_item_id}
                              data-product-sku={row.product_sku_snapshot}
                              data-remaining-lost={row.remainingLost}
                              data-verified={allocation ? "true" : "false"}
                              data-batch-code={allocation?.batch_code_snapshot ?? ""}
                              className="mt-1 h-4 w-4"
                            />
                            <span>
                              <span className="block text-sm font-semibold">
                                {row.product_sku_snapshot}
                              </span>
                              <span className="text-xs text-ui-text-muted">
                                Net hilang {qty(row.remainingLost)}
                              </span>
                              {allocation ? (
                                <span className="block text-xs text-ui-text-muted">
                                  Batch asal {allocation.batch_code_snapshot}
                                  {" \u00B7 "}
                                  kedaluwarsa {allocation.expiry_date_snapshot}
                                  {" \u00B7 "}
                                  kapasitas tersisa {qty(allocation.remaining_quantity)}
                                </span>
                              ) : (
                                <span className="block text-xs text-ui-text-muted">
                                  Asal kiriman belum dapat diverifikasi.
                                </span>
                              )}
                            </span>
                            <input
                              type="number"
                              min="1"
                              max={maximum}
                              defaultValue={maximum}
                              name={`lateQuantity_${lineKey}`}
                              className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border px-3"
                            />
                          </label>
                        );
                      });
                    })}
                  </div>

                  <label className="block text-sm font-medium">
                    Catatan
                    <textarea
                      name="note"
                      rows={3}
                      className="mt-2 w-full rounded-[var(--ui-radius-md)] border border-ui-border px-3 py-2"
                    />
                  </label>
                  </ReturnMutationReviewForm>
                </details>

              ) : null}
            </>
          )}
        </section>
      </div>
    </AppShell>
  );
}
