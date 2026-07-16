import Link from "next/link";
import PageSectionNav from "@/app/app-shell/page-section-nav";

import {
  confirmReturnReceiptAction,
  createExpectedReturnAction,
  inspectReturnAction,
  markReturnLostAction,
} from "@/app/actions";
import { CurrentDateTimeInput } from "@/app/returns/current-date-time-input";
import {
  ReturnReceiptSourceSelect,
  ReturnSourceSelect,
  type ReturnReceiptSourceOption,
  type ReturnSourceOption,
} from "@/app/returns/return-selects";
import {
  getMarketplaceData,
  getReturnData,
  type ReturnHeader,
  type ReturnItem,
  type ReturnReceiptLine,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number) {
  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null, includeTime = false) {
  if (!value) return "—";

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
    ...(includeTime
      ? { hour: "2-digit", minute: "2-digit", hour12: false }
      : {}),
  }).format(new Date(value));
}

function toDateTimeLocal(value: Date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(value);

  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

type PillTone = "success" | "warning" | "danger" | "neutral";

function Pill({ label, tone }: { label: string; tone: PillTone }) {
  const tones = {
    success: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
    warning: "border-amber-400/20 bg-amber-400/10 text-amber-200",
    danger: "border-rose-400/20 bg-rose-400/10 text-rose-200",
    neutral: "border-white/10 bg-white/[0.04] text-slate-300",
  };

  return (
    <span className={`inline-flex rounded-full border px-2.5 py-1 text-xs ${tones[tone]}`}>
      {label}
    </span>
  );
}

function returnTone(status: string, outcome: string | null): PillTone {
  if (status.startsWith("COMPLETED") && outcome !== "DAMAGED") return "success";
  if (
    status === "LOST" ||
    status === "EXCEPTION" ||
    outcome === "DAMAGED"
  ) {
    return "danger";
  }
  if (
    status.startsWith("PARTIALLY") ||
    status === "RECEIVED_PENDING_INSPECTION" ||
    outcome === "MIXED"
  ) {
    return "warning";
  }
  return "neutral";
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-amber-300">
          Return Admin tidak tersedia
        </p>
        <h1 className="mt-3 text-3xl font-semibold">Data retur gagal dimuat.</h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <Link className="nav-link mt-6 inline-flex" href="/">
          Kembali ke dashboard
        </Link>
      </section>
    </main>
  );
}

function quantityRows(returnHeader: ReturnHeader) {
  return [
    ["Expected", returnHeader.expected_qty],
    ["Pending arrival", returnHeader.pending_arrival_qty],
    ["Pending inspection", returnHeader.pending_inspection_qty],
    ["Sellable", returnHeader.sellable_qty],
    ["Damaged", returnHeader.damaged_qty],
    ["Lost", returnHeader.lost_qty],
  ];
}

function receiptRemaining(
  line: ReturnReceiptLine,
  inspectedByReceiptLine: Map<string, number>,
) {
  return Math.max(
    0,
    Number(line.quantity_received) -
      Number(inspectedByReceiptLine.get(line.receipt_line_id) ?? 0),
  );
}

export default async function ReturnsPage({
  searchParams,
}: {
  searchParams: Promise<{
    status?: string;
    returnId?: string;
    success?: string;
    error?: string;
  }>;
}) {
  const params = await searchParams;
  let returnData;
  let marketplace;

  try {
    [returnData, marketplace] = await Promise.all([
      getReturnData(),
      getMarketplaceData(),
    ]);
  } catch (error) {
    return (
      <ConfigurationError
        message={error instanceof Error ? error.message : "Konfigurasi tidak valid."}
      />
    );
  }

  const {
    returns,
    items,
    events,
    receiptLines,
    inspectionAllocations,
  } = returnData;
  const { reservations, events: marketplaceEvents, allocations } = marketplace;

  const statusFilter = params.status?.trim() || "ALL";
  const filteredReturns =
    statusFilter === "ALL"
      ? returns
      : returns.filter((returnHeader) => returnHeader.status_code === statusFilter);

  const selectedReturn =
    returns.find((returnHeader) => returnHeader.return_id === params.returnId) ??
    filteredReturns[0] ??
    returns[0] ??
    null;

  const selectedItems = selectedReturn
    ? items.filter((item) => item.return_id === selectedReturn.return_id)
    : [];
  const selectedEvents = selectedReturn
    ? events.filter((event) => event.return_id === selectedReturn.return_id)
    : [];
  const selectedReceiptLines = selectedReturn
    ? receiptLines.filter((line) => line.return_id === selectedReturn.return_id)
    : [];
  const selectedInspectionAllocations = selectedReturn
    ? inspectionAllocations.filter(
        (allocation) => allocation.return_id === selectedReturn.return_id,
      )
    : [];

  const expectedByMarketplaceItem = new Map<string, number>();
  for (const item of items) {
    expectedByMarketplaceItem.set(
      item.marketplace_order_item_id,
      Number(expectedByMarketplaceItem.get(item.marketplace_order_item_id) ?? 0) +
        Number(item.expected_qty),
    );
  }

  const returnSources: ReturnSourceOption[] = reservations
    .map((reservation) => {
      const remaining =
        Number(reservation.consumed_qty) -
        Number(expectedByMarketplaceItem.get(reservation.order_item_id) ?? 0);

      return {
        id: reservation.order_item_id,
        label: `${reservation.channel_code} · ${reservation.external_order_ref} · ${reservation.product_sku_snapshot} · dapat diretur ${Math.max(remaining, 0)}`,
        channelCode: reservation.channel_code,
        orderRef: reservation.external_order_ref,
        productId: reservation.product_id,
        sourceLineRef: reservation.external_item_ref,
        remaining,
      };
    })
    .filter((source) => source.remaining > 0)
    .map((source) => ({
      id: source.id,
      label: source.label,
      channelCode: source.channelCode,
      orderRef: source.orderRef,
      productId: source.productId,
      sourceLineRef: source.sourceLineRef,
    }));

  const marketplaceEventById = new Map(
    marketplaceEvents.map((event) => [event.event_id, event]),
  );

  const usedByShipAllocation = new Map<string, number>();
  for (const line of receiptLines) {
    if (!line.marketplace_ship_allocation_id) continue;
    usedByShipAllocation.set(
      line.marketplace_ship_allocation_id,
      Number(
        usedByShipAllocation.get(line.marketplace_ship_allocation_id) ?? 0,
      ) + Number(line.quantity_received),
    );
  }

  const receiptSources: ReturnReceiptSourceOption[] = [];
  if (selectedReturn) {
    for (const item of selectedItems.filter(
      (candidate) => Number(candidate.pending_arrival_qty) > 0,
    )) {
      const matchingAllocations = allocations.filter((allocation) => {
        const event = marketplaceEventById.get(allocation.event_id);
        return (
          event?.order_id === selectedReturn.marketplace_order_id &&
          allocation.product_id === item.product_id &&
          allocation.source_line_ref === item.marketplace_item_ref
        );
      });

      for (const allocation of matchingAllocations) {
        const remaining =
          Number(allocation.quantity_allocated) -
          Number(usedByShipAllocation.get(allocation.allocation_id) ?? 0);

        if (remaining <= 0) continue;

        receiptSources.push({
          id: `${item.return_item_id}:${allocation.allocation_id}`,
          label: `${item.product_sku_snapshot} · ${allocation.batch_code_snapshot} · verified · allocation tersisa ${remaining}`,
          returnItemId: item.return_item_id,
          marketplaceShipAllocationId: allocation.allocation_id,
        });
      }

      receiptSources.push({
        id: `${item.return_item_id}:UNKNOWN`,
        label: `${item.product_sku_snapshot} · batch tidak diketahui · maksimal ${item.pending_arrival_qty}`,
        returnItemId: item.return_item_id,
        marketplaceShipAllocationId: null,
      });
    }
  }

  const inspectedByReceiptLine = new Map<string, number>();
  for (const allocation of inspectionAllocations) {
    inspectedByReceiptLine.set(
      allocation.receipt_line_id,
      Number(inspectedByReceiptLine.get(allocation.receipt_line_id) ?? 0) +
        Number(allocation.quantity_allocated),
    );
  }

  const inspectableReceiptLines = selectedReceiptLines.filter(
    (line) => receiptRemaining(line, inspectedByReceiptLine) > 0,
  );
  const lostCandidates = selectedItems.filter(
    (item) => Number(item.pending_arrival_qty) > 0,
  );

  const pendingArrival = returns.reduce(
    (sum, returnHeader) => sum + Number(returnHeader.pending_arrival_qty),
    0,
  );
  const pendingInspection = returns.reduce(
    (sum, returnHeader) => sum + Number(returnHeader.pending_inspection_qty),
    0,
  );
  const completed = returns.filter(
    (returnHeader) =>
      returnHeader.status_code.startsWith("COMPLETED") ||
      returnHeader.status_code === "LOST" ||
      returnHeader.status_code === "CLOSED",
  ).length;

  const statuses = Array.from(
    new Set(returns.map((returnHeader) => returnHeader.status_code)),
  ).sort();

  const latestRecordedAt = Math.max(
    0,
    ...events.map((event) => new Date(event.occurred_at).getTime()),
    ...marketplaceEvents.map((event) => new Date(event.occurred_at).getTime()),
  );
  const minimumEventAt =
    latestRecordedAt > 0
      ? toDateTimeLocal(new Date(latestRecordedAt + 60_000))
      : undefined;

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <PageSectionNav
        items={[
          { href: "#overview", label: "Ringkasan" },
          { href: "#actions", label: "Actions" },
          { href: "#returns", label: "Returns" },
          { href: "#timeline", label: "Timeline" },
        ]}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section id="overview" className="scroll-mt-24">
          <p className="section-kicker">Return operations</p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
            Retur diterima ke quarantine, lalu diputuskan dengan bukti.
          </h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
            Expected return tidak mengubah stok. Barang fisik masuk ke quarantine,
            lalu inspeksi memindahkannya secara net-zero ke sellable atau damaged.
            Batch yang tidak teridentifikasi tidak dapat menjadi sellable.
          </p>

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              ["Total returns", returns.length, "Seluruh lifecycle tercatat"],
              ["Pending arrival", pendingArrival, "Belum diterima secara fisik"],
              ["Pending inspection", pendingInspection, "Masih berada di quarantine"],
              ["Closed outcomes", completed, "Selesai atau dinyatakan lost"],
            ].map(([label, value, description]) => (
              <article key={label} className="metric-card">
                <p className="text-sm text-slate-400">{label}</p>
                <p className="mt-3 text-3xl font-semibold text-white">
                  {formatNumber(Number(value))}
                </p>
                <p className="mt-2 text-xs text-slate-500">{description}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="actions" className="mt-10 scroll-mt-24">
          <div className="mb-5 flex items-end justify-between gap-4">
            <div>
              <p className="section-kicker">Return commands</p>
              <h2 className="section-title">Jalankan lifecycle melalui RPC atomik.</h2>
            </div>
            <Pill label="Idempotent" tone="success" />
          </div>

          {params.success ? (
            <div className="mb-5 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-200">
              {params.success}
            </div>
          ) : null}
          {params.error ? (
            <div className="mb-5 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-200">
              {params.error}
            </div>
          ) : null}

          <div className="grid gap-5 xl:grid-cols-2">
            <form action={createExpectedReturnAction} className="panel-card">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="section-kicker">Step 1</p>
                  <h3 className="mt-1 text-xl font-semibold">Buat expected return</h3>
                </div>
                <Pill label="Stock neutral" tone="neutral" />
              </div>
              <div className="form-grid mt-6">
                <label className="field-label sm:col-span-2">
                  Shipment source
                  <ReturnSourceSelect options={returnSources} />
                </label>
                <label className="field-label">
                  Return reference
                  <input name="returnRef" required placeholder="RET-SHP-1001" />
                </label>
                <label className="field-label">
                  Waktu expected
                  <CurrentDateTimeInput minimumEventAt={minimumEventAt} />
                </label>
                <label className="field-label">
                  Quantity
                  <input
                    name="quantity"
                    type="number"
                    min="1"
                    step="1"
                    required
                    placeholder="1"
                  />
                </label>
                <label className="field-label">
                  Source status
                  <input name="sourceStatus" placeholder="RETURN_REQUESTED" />
                </label>
                <label className="field-label sm:col-span-2">
                  Catatan
                  <input name="note" placeholder="Opsional" />
                </label>
              </div>
              <button
                className="primary-button mt-6"
                type="submit"
                disabled={returnSources.length === 0}
              >
                Create expected return
              </button>
            </form>

            <form action={confirmReturnReceiptAction} className="panel-card">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="section-kicker">Step 2</p>
                  <h3 className="mt-1 text-xl font-semibold">Terima ke quarantine</h3>
                </div>
                <Pill label="QUARANTINE +" tone="warning" />
              </div>
              <input
                type="hidden"
                name="returnRef"
                value={selectedReturn?.external_return_ref ?? ""}
              />
              <div className="form-grid mt-6">
                <label className="field-label sm:col-span-2">
                  Return item dan batch source
                  <ReturnReceiptSourceSelect options={receiptSources} />
                </label>
                <label className="field-label">
                  Receipt reference
                  <input name="receiptRef" required placeholder="RCV-RET-1001" />
                </label>
                <label className="field-label">
                  Waktu diterima
                  <CurrentDateTimeInput minimumEventAt={minimumEventAt} />
                </label>
                <label className="field-label">
                  Source line reference
                  <input name="sourceLineRef" required placeholder="RCV-LINE-1" />
                </label>
                <label className="field-label">
                  Quantity
                  <input
                    name="quantity"
                    type="number"
                    min="1"
                    step="1"
                    required
                    placeholder="1"
                  />
                </label>
                <label className="field-label sm:col-span-2">
                  Catatan
                  <input name="note" placeholder="Opsional" />
                </label>
              </div>
              <button
                className="primary-button mt-6"
                type="submit"
                disabled={!selectedReturn || receiptSources.length === 0}
              >
                Confirm physical receipt
              </button>
            </form>

            <form action={inspectReturnAction} className="panel-card">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="section-kicker">Step 3</p>
                  <h3 className="mt-1 text-xl font-semibold">Inspeksi quarantine</h3>
                </div>
                <Pill label="Net-zero transfer" tone="success" />
              </div>
              <input
                type="hidden"
                name="returnRef"
                value={selectedReturn?.external_return_ref ?? ""}
              />
              <div className="form-grid mt-6">
                <label className="field-label sm:col-span-2">
                  Receipt line
                  <select
                    name="receiptLineId"
                    defaultValue=""
                    required
                    disabled={inspectableReceiptLines.length === 0}
                  >
                    <option value="" disabled>
                      {inspectableReceiptLines.length === 0
                        ? "Tidak ada quarantine yang menunggu inspeksi"
                        : "Pilih receipt line"}
                    </option>
                    {inspectableReceiptLines.map((line) => (
                      <option key={line.receipt_line_id} value={line.receipt_line_id}>
                        {line.product_sku_snapshot} · {line.batch_code_snapshot} ·{" "}
                        {line.batch_identity_verified ? "verified" : "unidentified"} ·
                        remaining {receiptRemaining(line, inspectedByReceiptLine)}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field-label">
                  Inspection reference
                  <input name="inspectionRef" required placeholder="INSP-RET-1001" />
                </label>
                <label className="field-label">
                  Waktu inspeksi
                  <CurrentDateTimeInput minimumEventAt={minimumEventAt} />
                </label>
                <label className="field-label">
                  Sellable quantity
                  <input
                    name="sellableQuantity"
                    type="number"
                    min="0"
                    step="1"
                    defaultValue="0"
                    required
                  />
                </label>
                <label className="field-label">
                  Damaged quantity
                  <input
                    name="damagedQuantity"
                    type="number"
                    min="0"
                    step="1"
                    defaultValue="0"
                    required
                  />
                </label>
                <label className="field-label">
                  Source line reference
                  <input name="sourceLineRef" required placeholder="INSP-LINE-1" />
                </label>
                <label className="field-label">
                  Catatan
                  <input name="note" placeholder="Opsional" />
                </label>
              </div>
              <button
                className="primary-button mt-6"
                type="submit"
                disabled={!selectedReturn || inspectableReceiptLines.length === 0}
              >
                Post inspection
              </button>
            </form>

            <form action={markReturnLostAction} className="panel-card">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="section-kicker">Alternative close</p>
                  <h3 className="mt-1 text-xl font-semibold">Tandai lost</h3>
                </div>
                <Pill label="No stock effect" tone="danger" />
              </div>
              <input
                type="hidden"
                name="returnRef"
                value={selectedReturn?.external_return_ref ?? ""}
              />
              <div className="form-grid mt-6">
                <label className="field-label sm:col-span-2">
                  Pending return item
                  <select
                    name="returnItemId"
                    defaultValue=""
                    required
                    disabled={lostCandidates.length === 0}
                  >
                    <option value="" disabled>
                      {lostCandidates.length === 0
                        ? "Tidak ada pending arrival"
                        : "Pilih return item"}
                    </option>
                    {lostCandidates.map((item) => (
                      <option key={item.return_item_id} value={item.return_item_id}>
                        {item.product_sku_snapshot} · pending{" "}
                        {item.pending_arrival_qty}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field-label">
                  Event reference
                  <input name="eventRef" required placeholder="LOST-RET-1001" />
                </label>
                <label className="field-label">
                  Waktu dinyatakan lost
                  <CurrentDateTimeInput minimumEventAt={minimumEventAt} />
                </label>
                <label className="field-label">
                  Source line reference
                  <input name="sourceLineRef" required placeholder="LOST-LINE-1" />
                </label>
                <label className="field-label">
                  Quantity
                  <input
                    name="quantity"
                    type="number"
                    min="1"
                    step="1"
                    required
                    placeholder="1"
                  />
                </label>
                <label className="field-label sm:col-span-2">
                  Catatan
                  <input name="note" placeholder="Opsional" />
                </label>
              </div>
              <button
                className="primary-button mt-6"
                type="submit"
                disabled={!selectedReturn || lostCandidates.length === 0}
              >
                Mark as lost
              </button>
            </form>
          </div>
        </section>

        <section id="returns" className="mt-10 scroll-mt-24">
          <div className="mb-5 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="section-kicker">Return registry</p>
              <h2 className="section-title">Pilih retur untuk diproses.</h2>
            </div>
            <div className="flex flex-wrap gap-2 text-xs">
              <Link
                href="/returns?status=ALL#returns"
                className={`rounded-full border px-3 py-1.5 ${
                  statusFilter === "ALL"
                    ? "border-emerald-400/30 bg-emerald-400/10 text-emerald-300"
                    : "border-white/10 text-slate-400"
                }`}
              >
                ALL
              </Link>
              {statuses.map((status) => (
                <Link
                  key={status}
                  href={`/returns?status=${encodeURIComponent(status)}#returns`}
                  className={`rounded-full border px-3 py-1.5 ${
                    statusFilter === status
                      ? "border-emerald-400/30 bg-emerald-400/10 text-emerald-300"
                      : "border-white/10 text-slate-400"
                  }`}
                >
                  {status}
                </Link>
              ))}
            </div>
          </div>

          <div className="grid gap-5 xl:grid-cols-[0.9fr_1.6fr]">
            <div className="panel-card p-0">
              {filteredReturns.length === 0 ? (
                <div className="p-7 text-sm text-slate-400">
                  Belum ada retur untuk filter ini.
                </div>
              ) : (
                <div className="divide-y divide-white/10">
                  {filteredReturns.map((returnHeader) => (
                    <Link
                      key={returnHeader.return_id}
                      href={`/returns?status=${encodeURIComponent(statusFilter)}&returnId=${returnHeader.return_id}#returns`}
                      className={`block p-5 transition hover:bg-white/[0.03] ${
                        selectedReturn?.return_id === returnHeader.return_id
                          ? "bg-emerald-400/[0.05]"
                          : ""
                      }`}
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="font-mono text-sm text-white">
                            {returnHeader.external_return_ref}
                          </p>
                          <p className="mt-1 text-xs text-slate-500">
                            {returnHeader.channel_code} ·{" "}
                            {returnHeader.marketplace_order_ref}
                          </p>
                        </div>
                        <Pill
                          label={returnHeader.status_code}
                          tone={returnTone(
                            returnHeader.status_code,
                            returnHeader.outcome_code,
                          )}
                        />
                      </div>
                      <div className="mt-4 flex gap-4 text-xs text-slate-400">
                        <span>expected {returnHeader.expected_qty}</span>
                        <span>arrival {returnHeader.pending_arrival_qty}</span>
                        <span>inspect {returnHeader.pending_inspection_qty}</span>
                      </div>
                    </Link>
                  ))}
                </div>
              )}
            </div>

            <article className="panel-card">
              {!selectedReturn ? (
                <div className="py-10 text-center text-sm text-slate-400">
                  Buat expected return untuk memulai lifecycle.
                </div>
              ) : (
                <>
                  <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                    <div>
                      <p className="section-kicker">Selected return</p>
                      <h3 className="mt-2 text-2xl font-semibold">
                        {selectedReturn.external_return_ref}
                      </h3>
                      <p className="mt-2 text-sm text-slate-400">
                        {selectedReturn.channel_code} ·{" "}
                        {selectedReturn.marketplace_order_ref} · expected{" "}
                        {formatDate(selectedReturn.expected_at, true)} WIB
                      </p>
                    </div>
                    <Pill
                      label={selectedReturn.status_code}
                      tone={returnTone(
                        selectedReturn.status_code,
                        selectedReturn.outcome_code,
                      )}
                    />
                  </div>

                  <div className="mt-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                    {quantityRows(selectedReturn).map(([label, value]) => (
                      <div
                        key={label}
                        className="rounded-2xl border border-white/10 bg-slate-950/50 p-4"
                      >
                        <p className="text-xs text-slate-500">{label}</p>
                        <p className="mt-2 text-2xl font-semibold text-white">
                          {formatNumber(Number(value))}
                        </p>
                      </div>
                    ))}
                  </div>

                  <div className="mt-7 overflow-x-auto">
                    <table className="min-w-full text-left text-sm">
                      <thead className="text-xs uppercase tracking-wide text-slate-500">
                        <tr>
                          <th className="px-3 py-3">SKU</th>
                          <th className="px-3 py-3">Expected</th>
                          <th className="px-3 py-3">Arrival</th>
                          <th className="px-3 py-3">Inspect</th>
                          <th className="px-3 py-3">Sellable</th>
                          <th className="px-3 py-3">Damaged</th>
                          <th className="px-3 py-3">Lost</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-white/10">
                        {selectedItems.map((item: ReturnItem) => (
                          <tr key={item.return_item_id}>
                            <td className="px-3 py-3 font-mono text-white">
                              {item.product_sku_snapshot}
                            </td>
                            <td className="px-3 py-3">{item.expected_qty}</td>
                            <td className="px-3 py-3">
                              {item.pending_arrival_qty}
                            </td>
                            <td className="px-3 py-3">
                              {item.pending_inspection_qty}
                            </td>
                            <td className="px-3 py-3 text-emerald-300">
                              {item.sellable_qty}
                            </td>
                            <td className="px-3 py-3 text-rose-300">
                              {item.damaged_qty}
                            </td>
                            <td className="px-3 py-3 text-amber-200">
                              {item.lost_qty}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </>
              )}
            </article>
          </div>
        </section>

        <section id="timeline" className="mt-10 scroll-mt-24">
          <div className="mb-5">
            <p className="section-kicker">Audit trail</p>
            <h2 className="section-title">Event, receipt, dan disposition.</h2>
          </div>

          <div className="grid gap-5 xl:grid-cols-3">
            <article className="panel-card">
              <h3 className="text-lg font-semibold">Return events</h3>
              <div className="mt-5 space-y-4">
                {selectedEvents.length === 0 ? (
                  <p className="text-sm text-slate-500">Belum ada event.</p>
                ) : (
                  selectedEvents.map((event) => (
                    <div
                      key={event.event_id}
                      className="rounded-2xl border border-white/10 bg-slate-950/50 p-4"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <p className="font-mono text-sm text-white">
                          {event.event_type_code}
                        </p>
                        <span className="text-xs text-slate-500">
                          {formatDate(event.occurred_at, true)}
                        </span>
                      </div>
                      <p className="mt-2 text-xs text-slate-400">
                        {event.external_event_ref}
                      </p>
                      {event.note ? (
                        <p className="mt-2 text-xs text-slate-500">{event.note}</p>
                      ) : null}
                    </div>
                  ))
                )}
              </div>
            </article>

            <article className="panel-card">
              <h3 className="text-lg font-semibold">Physical receipts</h3>
              <div className="mt-5 space-y-4">
                {selectedReceiptLines.length === 0 ? (
                  <p className="text-sm text-slate-500">Belum ada receipt.</p>
                ) : (
                  selectedReceiptLines.map((line) => (
                    <div
                      key={line.receipt_line_id}
                      className="rounded-2xl border border-white/10 bg-slate-950/50 p-4"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <p className="font-mono text-sm text-white">
                          {line.receipt_ref}
                        </p>
                        <Pill
                          label={
                            line.batch_identity_verified
                              ? "VERIFIED"
                              : "UNIDENTIFIED"
                          }
                          tone={
                            line.batch_identity_verified ? "success" : "danger"
                          }
                        />
                      </div>
                      <p className="mt-2 text-xs text-slate-400">
                        {line.product_sku_snapshot} · {line.batch_code_snapshot}
                      </p>
                      <p className="mt-2 text-xs text-slate-500">
                        received {line.quantity_received} · quarantine remaining{" "}
                        {receiptRemaining(line, inspectedByReceiptLine)}
                      </p>
                    </div>
                  ))
                )}
              </div>
            </article>

            <article className="panel-card">
              <h3 className="text-lg font-semibold">Inspection allocations</h3>
              <div className="mt-5 space-y-4">
                {selectedInspectionAllocations.length === 0 ? (
                  <p className="text-sm text-slate-500">Belum ada disposition.</p>
                ) : (
                  selectedInspectionAllocations.map((allocation) => (
                    <div
                      key={allocation.inspection_allocation_id}
                      className="rounded-2xl border border-white/10 bg-slate-950/50 p-4"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <p className="font-mono text-sm text-white">
                          {allocation.inspection_ref}
                        </p>
                        <Pill
                          label={allocation.destination_bucket_code}
                          tone={
                            allocation.destination_bucket_code === "SELLABLE"
                              ? "success"
                              : "danger"
                          }
                        />
                      </div>
                      <p className="mt-2 text-xs text-slate-400">
                        quantity {allocation.quantity_allocated} · pair{" "}
                        {allocation.pair_no}
                      </p>
                      <p className="mt-2 text-xs text-slate-500">
                        {formatDate(allocation.occurred_at, true)} WIB
                      </p>
                    </div>
                  ))
                )}
              </div>
            </article>
          </div>
        </section>
      </div>
    </main>
  );
}
