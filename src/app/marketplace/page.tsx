import Link from "next/link";
import PageSectionNav from "@/app/app-shell/page-section-nav";

import { CurrentDateTimeInput } from "@/app/marketplace/current-date-time-input";
import {
  advanceMarketplaceOrderAction,
  reserveMarketplaceOrderAction,
} from "@/app/actions";
import {
  getDashboardData,
  getMarketplaceData,
  getMarketplaceListingSimulatorData,
  type MarketplaceListingCatalogRow,
  type MarketplaceListingComponentLifecycle,
  type MarketplaceOrder,
  type MarketplaceReservation,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

const numberFormatter = new Intl.NumberFormat("id-ID");

function formatNumber(value: number) {
  return numberFormatter.format(Number(value));
}

function formatDate(value: string | null, includeTime = false) {
  if (!value) return "â€”";

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

  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );
  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

type PillTone = "success" | "warning" | "danger" | "neutral" | "info";

function Pill({ label, tone }: { label: string; tone: PillTone }) {
  const tones = {
    success: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
    warning: "border-amber-400/20 bg-amber-400/10 text-amber-200",
    danger: "border-rose-400/20 bg-rose-400/10 text-rose-200",
    neutral: "border-white/10 bg-white/[0.04] text-slate-300",
    info: "border-sky-400/20 bg-sky-400/10 text-sky-200",
  };

  return (
    <span
      className={`inline-flex rounded-full border px-2.5 py-1 text-xs ${tones[tone]}`}
    >
      {label}
    </span>
  );
}

function orderTone(order: MarketplaceOrder): PillTone {
  if (order.status_code === "SHIPPED") return "success";
  if (order.status_code === "CANCELLED") return "danger";
  if (order.status_code === "CLOSED_MIXED") return "warning";
  return "neutral";
}

function reservationTone(reservation: MarketplaceReservation): PillTone {
  if (reservation.status_code === "CONSUMED") return "success";
  if (reservation.status_code === "RELEASED") return "danger";
  if (reservation.status_code.startsWith("PARTIALLY")) return "warning";
  return "neutral";
}

function listingTone(listing: MarketplaceListingCatalogRow): PillTone {
  if (
    listing.status_code === "ACTIVE" &&
    listing.mapping_readiness_code === "PUBLISHED"
  ) {
    return "success";
  }

  if (listing.mapping_readiness_code === "DRAFT_ONLY") return "warning";
  if (listing.status_code === "ARCHIVED") return "danger";
  return "neutral";
}

function componentLabel(component: MarketplaceListingComponentLifecycle) {
  return (
    `${component.channel_code} Â· ${component.external_order_ref} Â· ` +
    `${component.external_listing_code_snapshot} v${component.mapping_version} Â· ` +
    `C${component.component_no} ${component.product_sku_snapshot} Â· ` +
    `open ${formatNumber(component.open_reserved_quantity)}`
  );
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-amber-300">
          Marketplace simulator tidak tersedia
        </p>
        <h1 className="mt-3 text-3xl font-semibold">
          Data marketplace gagal dimuat.
        </h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <Link className="nav-link mt-6 inline-flex" href="/">
          Kembali ke dashboard
        </Link>
      </section>
    </main>
  );
}

export default async function MarketplacePage({
  searchParams,
}: {
  searchParams: Promise<{ success?: string; error?: string }>;
}) {
  const feedback = await searchParams;
  let dashboard;
  let marketplace;
  let listingSimulator;

  try {
    [dashboard, marketplace, listingSimulator] = await Promise.all([
      getDashboardData(),
      getMarketplaceData(),
      getMarketplaceListingSimulatorData(),
    ]);
  } catch (error) {
    return (
      <ConfigurationError
        message={
          error instanceof Error ? error.message : "Konfigurasi tidak valid."
        }
      />
    );
  }

  const { ledger } = dashboard;
  const { orders, reservations, events, allocations } = marketplace;
  const { listingCatalog, normalizations, components } = listingSimulator;
  const activeListings = listingCatalog.filter(
    (listing) =>
      listing.status_code === "ACTIVE" &&
      listing.mapping_readiness_code === "PUBLISHED",
  );
  const shipCandidates = components.filter(
    (component) => Number(component.open_reserved_quantity) > 0,
  );
  const openOrders = orders.filter(
    (order) => Number(order.open_qty) > 0,
  ).length;
  const openQuantity = orders.reduce(
    (sum, order) => sum + Number(order.open_qty),
    0,
  );
  const shippedQuantity = orders.reduce(
    (sum, order) => sum + Number(order.shipped_qty),
    0,
  );
  const latestPhysicalAt = ledger.reduce(
    (latest, entry) =>
      Math.max(latest, new Date(entry.occurred_at).getTime()),
    0,
  );
  const latestMarketplaceAt = events.reduce(
    (latest, event) =>
      Math.max(latest, new Date(event.occurred_at).getTime()),
    0,
  );
  const latestRecordedAt = Math.max(
    latestPhysicalAt,
    latestMarketplaceAt,
  );
  const minimumEventAt =
    latestRecordedAt > 0
      ? toDateTimeLocal(new Date(latestRecordedAt + 60_000))
      : undefined;
  const eventById = new Map(
    events.map((event) => [event.event_id, event]),
  );

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <PageSectionNav
        items={[
          { href: "#simulator", label: "Simulator" },
          { href: "#normalizations", label: "Ekspansi" },
          { href: "#orders", label: "Orders" },
          { href: "#events", label: "Events" },
          { href: "#allocations", label: "FEFO" },
        ]}
      />

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section>
          <p className="section-kicker">Marketplace operations</p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
            Listing marketplace dinormalisasi sebelum reservasi dan shipment.
          </h1>
          <p className="mt-3 max-w-4xl text-sm leading-6 text-slate-400 sm:text-base">
            Simulator menerima kode listing Shopee atau TikTok Shop, memilih versi
            mapping berdasarkan waktu event, lalu memecah bundle menjadi produk satuan.
            Reservasi tetap stock-neutral. Stok fisik hanya berkurang saat Shopee
            SHIPPED atau TikTok Shop IN_TRANSIT melalui FEFO otomatis.
          </p>
          <div className="mt-5 flex flex-wrap gap-3">
            <Link
              className="primary-button inline-flex"
              href="/marketplace/cancellations"
            >
              Kelola pembatalan parsial
            </Link>
            <a className="nav-link inline-flex" href="#normalizations">
              Lihat hasil ekspansi
            </a>
          </div>

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              [
                "Listing siap",
                activeListings.length,
                "Mapping aktif dan efektif",
              ],
              ["Open orders", openOrders, "Masih memiliki reservasi aktif"],
              ["Open reserved", openQuantity, "Belum dibatalkan atau dikirim"],
              ["Shipped", shippedQuantity, "Sudah keluar fisik melalui FEFO"],
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

        <section id="simulator" className="mt-10 scroll-mt-24">
          <div className="mb-5 flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="section-kicker">Normalized event simulator</p>
              <h2 className="section-title">
                Terapkan lifecycle dari identitas listing eksternal.
              </h2>
            </div>
            <Pill label="Listing contract V1" tone="success" />
          </div>

          {feedback.success ? (
            <div className="mb-5 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-5 py-4 text-sm text-emerald-200">
              {feedback.success}
            </div>
          ) : null}
          {feedback.error ? (
            <div className="mb-5 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-5 py-4 text-sm text-rose-200">
              {feedback.error}
            </div>
          ) : null}

          <div className="grid gap-5 xl:grid-cols-2">
            <form action={reserveMarketplaceOrderAction} className="panel-card">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="section-kicker">Step 1</p>
                  <h3 className="mt-1 text-xl font-semibold">
                    Reserve listing marketplace
                  </h3>
                </div>
                <Pill label="Stock-neutral" tone="warning" />
              </div>
              <p className="mt-3 text-sm leading-6 text-slate-400">
                Quantity listing akan dikalikan dengan recipe version yang efektif.
                Bundle tidak pernah menjadi produk stok.
              </p>

              <div className="form-grid mt-6">
                <label className="field-label sm:col-span-2">
                  Listing marketplace
                  <select
                    name="marketplaceListingSelection"
                    defaultValue=""
                    required
                    disabled={activeListings.length === 0}
                  >
                    <option value="" disabled>
                      {activeListings.length === 0
                        ? "Belum ada listing aktif"
                        : "Pilih listing eksternal"}
                    </option>
                    {activeListings.map((listing) => (
                      <option
                        key={listing.listing_id}
                        value={JSON.stringify({
                          channelCode: listing.channel_code,
                          externalListingCode: listing.external_listing_code,
                          listingName: listing.display_name,
                          listingType: listing.listing_type_code,
                        })}
                      >
                        {listing.channel_code} Â· {listing.external_listing_code} Â·{" "}
                        {listing.display_name} Â· {listing.listing_type_code} Â· v
                        {listing.current_version ?? "â€”"}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field-label">
                  Waktu event
                  <CurrentDateTimeInput minimumEventAt={minimumEventAt} />
                </label>
                <label className="field-label">
                  Order reference
                  <input
                    name="orderRef"
                    required
                    placeholder="SHP-ORDER-1001"
                  />
                </label>
                <label className="field-label">
                  Event reference
                  <input
                    name="eventRef"
                    required
                    placeholder="SHP-EVT-RESERVE-1001"
                  />
                </label>
                <label className="field-label">
                  Source line reference
                  <input name="sourceLineRef" required placeholder="ITEM-1" />
                </label>
                <label className="field-label">
                  Quantity listing
                  <input
                    name="listingQuantity"
                    type="number"
                    min="1"
                    step="1"
                    required
                    placeholder="2"
                  />
                </label>
                <label className="field-label">
                  Catatan
                  <input name="note" placeholder="Opsional" />
                </label>
              </div>

              <button
                className="primary-button mt-6"
                type="submit"
                disabled={activeListings.length === 0}
              >
                Normalisasi dan reserve
              </button>
            </form>

            <form action={advanceMarketplaceOrderAction} className="panel-card">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="section-kicker">Step 2</p>
                  <h3 className="mt-1 text-xl font-semibold">
                    Ship komponen hasil ekspansi
                  </h3>
                </div>
                <Pill label="FEFO otomatis" tone="success" />
              </div>
              <p className="mt-3 text-sm leading-6 text-slate-400">
                Shopee mengurangi stok saat SHIPPED. TikTok Shop mengurangi stok
                saat IN_TRANSIT. Pembatalan dilakukan melalui workflow pembatalan,
                bukan event RELEASE generik.
              </p>

              <div className="form-grid mt-6">
                <label className="field-label sm:col-span-2">
                  Komponen reservasi aktif
                  <select
                    name="marketplaceSelection"
                    defaultValue=""
                    required
                    disabled={shipCandidates.length === 0}
                  >
                    <option value="" disabled>
                      {shipCandidates.length === 0
                        ? "Tidak ada komponen reservasi aktif"
                        : "Pilih komponen produk"}
                    </option>
                    {shipCandidates.map((component) => (
                      <option
                        key={component.source_component_id}
                        value={JSON.stringify({
                          channelCode: component.channel_code,
                          orderRef: component.external_order_ref,
                          orderSourceLineRef: component.source_line_ref,
                          componentNo: component.component_no,
                        })}
                      >
                        {componentLabel(component)}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field-label">
                  Waktu event
                  <CurrentDateTimeInput minimumEventAt={minimumEventAt} />
                </label>
                <label className="field-label">
                  Event reference
                  <input
                    name="eventRef"
                    required
                    placeholder="SHP-EVT-SHIP-1001"
                  />
                </label>
                <label className="field-label">
                  Quantity produk satuan
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
                  Catatan
                  <input name="note" placeholder="Opsional" />
                </label>
              </div>

              <button
                className="primary-button mt-6"
                type="submit"
                disabled={shipCandidates.length === 0}
              >
                Apply SHIP
              </button>
            </form>
          </div>

          <section className="mt-6 rounded-3xl border border-white/10 bg-white/[0.025] p-5">
            <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <p className="section-kicker">Listing readiness</p>
                <h3 className="mt-1 text-lg font-semibold">
                  Status mapping yang tersedia untuk simulator
                </h3>
              </div>
              <span className="text-sm text-slate-400">
                {listingCatalog.length} listing terdaftar
              </span>
            </div>
            <div className="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              {listingCatalog.length === 0 ? (
                <p className="text-sm text-slate-500">
                  Belum ada listing marketplace terdaftar.
                </p>
              ) : (
                listingCatalog.map((listing) => (
                  <article
                    key={listing.listing_id}
                    className="rounded-2xl border border-white/10 bg-slate-950/40 p-4"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="font-mono text-xs text-slate-400">
                          {listing.channel_code} Â· {listing.external_listing_code}
                        </p>
                        <p className="mt-2 font-medium text-white">
                          {listing.display_name}
                        </p>
                      </div>
                      <Pill
                        label={listing.mapping_readiness_code}
                        tone={listingTone(listing)}
                      />
                    </div>
                    <p className="mt-3 text-xs text-slate-500">
                      {listing.listing_type_code} Â· current version{" "}
                      {listing.current_version ?? "â€”"} Â· draft{" "}
                      {listing.draft_version_count}
                    </p>
                  </article>
                ))
              )}
            </div>
          </section>
        </section>

        <section id="normalizations" className="mt-10 scroll-mt-24">
          <div>
            <p className="section-kicker">Immutable expansion snapshot</p>
            <h2 className="section-title">
              Listing sumber dan produk satuan hasil normalisasi.
            </h2>
          </div>
          <p className="mt-3 max-w-4xl text-sm leading-6 text-slate-400">
            Setiap baris menyimpan kode listing, recipe version, component number,
            product snapshot, dan quantity hasil perkalian yang dipakai order.
          </p>

          <div className="mt-5 overflow-hidden rounded-2xl border border-white/10 bg-white/[0.025]">
            <div className="overflow-x-auto">
              <table>
                <thead>
                  <tr>
                    <th>Order / source</th>
                    <th>Listing</th>
                    <th>Mapping</th>
                    <th>Component</th>
                    <th>Produk</th>
                    <th>Per listing</th>
                    <th>Listing qty</th>
                    <th>Expanded</th>
                    <th>Reservasi</th>
                  </tr>
                </thead>
                <tbody>
                  {normalizations.length === 0 ? (
                    <tr>
                      <td colSpan={9}>Belum ada listing yang dinormalisasi.</td>
                    </tr>
                  ) : (
                    normalizations.map((row) => (
                      <tr key={row.source_component_id}>
                        <td>
                          <p className="font-mono text-xs text-white">
                            {row.external_order_ref_snapshot}
                          </p>
                          <p className="mt-1 text-xs text-slate-500">
                            {row.source_line_ref}
                          </p>
                        </td>
                        <td>
                          <p className="font-mono text-xs text-white">
                            {row.external_listing_code_snapshot}
                          </p>
                          <p className="mt-1 text-xs text-slate-500">
                            {row.listing_name_snapshot}
                          </p>
                        </td>
                        <td>
                          <Pill
                            label={`${row.listing_type_code_snapshot} v${row.mapping_version}`}
                            tone={
                              row.listing_type_code_snapshot === "BUNDLE"
                                ? "info"
                                : "neutral"
                            }
                          />
                        </td>
                        <td>#{row.component_no}</td>
                        <td>
                          <p>{row.product_sku_snapshot}</p>
                          <p className="mt-1 text-xs text-slate-500">
                            {row.product_name_snapshot}
                          </p>
                        </td>
                        <td>{formatNumber(row.unit_quantity_per_listing)}</td>
                        <td>{formatNumber(row.listing_quantity)}</td>
                        <td className="font-semibold text-white">
                          {formatNumber(row.expanded_quantity)}
                        </td>
                        <td>
                          <Pill
                            label={`${row.reservation_status_code} Â· open ${formatNumber(
                              Number(row.reserved_qty) -
                                Number(row.consumed_qty) -
                                Number(row.released_qty),
                            )}`}
                            tone="warning"
                          />
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <section id="orders" className="mt-10 scroll-mt-24">
          <div>
            <p className="section-kicker">Canonical state</p>
            <h2 className="section-title">Order dan reservasi marketplace.</h2>
          </div>

          <div className="mt-5 overflow-hidden rounded-2xl border border-white/10 bg-white/[0.025]">
            <div className="overflow-x-auto">
              <table>
                <thead>
                  <tr>
                    <th>Order</th>
                    <th>Channel</th>
                    <th>Reserved</th>
                    <th>Open</th>
                    <th>Shipped</th>
                    <th>Released</th>
                    <th>Status</th>
                    <th>Reserved at</th>
                  </tr>
                </thead>
                <tbody>
                  {orders.length === 0 ? (
                    <tr>
                      <td colSpan={8}>Belum ada order marketplace.</td>
                    </tr>
                  ) : (
                    orders.map((order) => (
                      <tr key={order.order_id}>
                        <td className="font-mono text-xs text-white">
                          {order.external_order_ref}
                        </td>
                        <td>{order.channel_code}</td>
                        <td>{formatNumber(order.reserved_qty)}</td>
                        <td className="font-semibold text-white">
                          {formatNumber(order.open_qty)}
                        </td>
                        <td>{formatNumber(order.shipped_qty)}</td>
                        <td>{formatNumber(order.released_qty)}</td>
                        <td>
                          <Pill
                            label={order.status_code}
                            tone={orderTone(order)}
                          />
                        </td>
                        <td className="whitespace-nowrap">
                          {formatDate(order.reserved_at, true)}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>

          <div className="mt-5 overflow-hidden rounded-2xl border border-white/10 bg-white/[0.025]">
            <div className="overflow-x-auto">
              <table>
                <thead>
                  <tr>
                    <th>Item</th>
                    <th>Order</th>
                    <th>SKU</th>
                    <th>Reserved</th>
                    <th>Consumed</th>
                    <th>Released</th>
                    <th>Open</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {reservations.length === 0 ? (
                    <tr>
                      <td colSpan={8}>Belum ada reservasi marketplace.</td>
                    </tr>
                  ) : (
                    reservations.map((reservation) => (
                      <tr key={reservation.reservation_id}>
                        <td className="font-mono text-xs text-white">
                          {reservation.external_item_ref}
                        </td>
                        <td>{reservation.external_order_ref}</td>
                        <td>{reservation.product_sku_snapshot}</td>
                        <td>{formatNumber(reservation.reserved_qty)}</td>
                        <td>{formatNumber(reservation.consumed_qty)}</td>
                        <td>{formatNumber(reservation.released_qty)}</td>
                        <td className="font-semibold text-white">
                          {formatNumber(reservation.open_qty)}
                        </td>
                        <td>
                          <Pill
                            label={reservation.status_code}
                            tone={reservationTone(reservation)}
                          />
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <section id="events" className="mt-10 scroll-mt-24">
          <div>
            <p className="section-kicker">Append-only events</p>
            <h2 className="section-title">Riwayat event marketplace.</h2>
          </div>

          <div className="mt-5 overflow-hidden rounded-2xl border border-white/10 bg-white/[0.025]">
            <div className="overflow-x-auto">
              <table>
                <thead>
                  <tr>
                    <th>Event ref</th>
                    <th>Channel</th>
                    <th>Type</th>
                    <th>Occurred</th>
                    <th>Transaction</th>
                    <th>Note</th>
                  </tr>
                </thead>
                <tbody>
                  {events.length === 0 ? (
                    <tr>
                      <td colSpan={6}>Belum ada event marketplace.</td>
                    </tr>
                  ) : (
                    events.map((event) => (
                      <tr key={event.event_id}>
                        <td className="font-mono text-xs text-white">
                          {event.external_event_ref}
                        </td>
                        <td>{event.channel_code}</td>
                        <td>
                          <Pill
                            label={event.event_type_code}
                            tone={
                              event.event_type_code === "SHIP"
                                ? "success"
                                : event.event_type_code === "RELEASE"
                                  ? "danger"
                                  : "warning"
                            }
                          />
                        </td>
                        <td className="whitespace-nowrap">
                          {formatDate(event.occurred_at, true)}
                        </td>
                        <td className="font-mono text-xs text-slate-400">
                          {event.transaction_id ?? "non-physical"}
                        </td>
                        <td>{event.note ?? "â€”"}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <section id="allocations" className="mt-10 scroll-mt-24 pb-12">
          <div>
            <p className="section-kicker">Shipment audit</p>
            <h2 className="section-title">Alokasi batch FEFO.</h2>
          </div>

          <div className="mt-5 overflow-hidden rounded-2xl border border-white/10 bg-white/[0.025]">
            <div className="overflow-x-auto">
              <table>
                <thead>
                  <tr>
                    <th>Event</th>
                    <th>Allocation</th>
                    <th>SKU</th>
                    <th>Batch</th>
                    <th>Expiry</th>
                    <th>Quantity</th>
                    <th>Source line</th>
                  </tr>
                </thead>
                <tbody>
                  {allocations.length === 0 ? (
                    <tr>
                      <td colSpan={7}>Belum ada shipment marketplace.</td>
                    </tr>
                  ) : (
                    allocations.map((allocation) => (
                      <tr key={allocation.allocation_id}>
                        <td className="font-mono text-xs text-white">
                          {eventById.get(allocation.event_id)
                            ?.external_event_ref ?? allocation.event_id}
                        </td>
                        <td>#{allocation.allocation_no}</td>
                        <td>{allocation.product_sku_snapshot}</td>
                        <td className="font-mono text-xs">
                          {allocation.batch_code_snapshot}
                        </td>
                        <td>{formatDate(allocation.expiry_date_snapshot)}</td>
                        <td className="font-semibold text-white">
                          {formatNumber(allocation.quantity_allocated)}
                        </td>
                        <td>{allocation.source_line_ref}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}