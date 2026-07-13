import Link from "next/link";

import { CurrentDateTimeInput } from "@/app/marketplace/current-date-time-input";
import {
  advanceMarketplaceOrderAction,
  reserveMarketplaceOrderAction,
} from "@/app/actions";
import {
  getDashboardData,
  getMarketplaceData,
  type MarketplaceOrder,
  type MarketplaceReservation,
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

function ConfigurationError({ message }: { message: string }) {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-slate-100">
      <section className="mx-auto max-w-3xl rounded-3xl border border-amber-400/20 bg-amber-400/[0.06] p-8">
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-amber-300">
          Marketplace simulator tidak tersedia
        </p>
        <h1 className="mt-3 text-3xl font-semibold">Data marketplace gagal dimuat.</h1>
        <p className="mt-4 leading-7 text-slate-300">{message}</p>
        <Link className="nav-link mt-6 inline-flex" href="/">Kembali ke dashboard</Link>
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

  try {
    [dashboard, marketplace] = await Promise.all([
      getDashboardData(),
      getMarketplaceData(),
    ]);
  } catch (error) {
    return (
      <ConfigurationError
        message={error instanceof Error ? error.message : "Konfigurasi tidak valid."}
      />
    );
  }

  const { products, ledger } = dashboard;
  const { orders, reservations, events, allocations } = marketplace;
  const openReservations = reservations.filter((reservation) => Number(reservation.open_qty) > 0);
  const openOrders = orders.filter((order) => Number(order.open_qty) > 0).length;
  const openQuantity = orders.reduce((sum, order) => sum + Number(order.open_qty), 0);
  const shippedQuantity = orders.reduce((sum, order) => sum + Number(order.shipped_qty), 0);
  const releasedQuantity = orders.reduce((sum, order) => sum + Number(order.released_qty), 0);
  const latestPhysicalAt = ledger.reduce(
    (latest, entry) => Math.max(latest, new Date(entry.occurred_at).getTime()),
    0,
  );
  const latestMarketplaceAt = events.reduce(
    (latest, event) => Math.max(latest, new Date(event.occurred_at).getTime()),
    0,
  );
  const latestRecordedAt = Math.max(
    latestPhysicalAt,
    latestMarketplaceAt,
  );
  const minimumEventAt = latestRecordedAt > 0
    ? toDateTimeLocal(new Date(latestRecordedAt + 60_000))
    : undefined;

  const eventById = new Map(events.map((event) => [event.event_id, event]));

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <header className="sticky top-0 z-20 border-b border-white/10 bg-slate-950/90 backdrop-blur">
        <div className="mx-auto flex max-w-[1500px] items-center justify-between gap-5 px-5 py-4 lg:px-8">
          <div>
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-emerald-300">
              GlowLab Marketplace
            </p>
            <p className="mt-1 text-sm text-slate-400">Reservation lifecycle simulator</p>
          </div>
          <nav className="hidden items-center gap-2 text-sm md:flex">
            <a className="nav-link" href="#simulator">Simulator</a>
            <a className="nav-link" href="#orders">Orders</a>
            <a className="nav-link" href="#events">Events</a>
            <a className="nav-link" href="#allocations">FEFO</a>
          </nav>
          <Link className="nav-link border border-white/10" href="/">Dashboard</Link>
        </div>
      </header>

      <div className="mx-auto max-w-[1500px] px-5 py-8 lg:px-8">
        <section>
          <p className="section-kicker">Marketplace operations</p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
            Reservasi dahulu, stok fisik bergerak saat shipment.
          </h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400 sm:text-base">
            Simulator ini menerapkan event Shopee dan TikTok Shop melalui RPC atomik.
            RESERVE dan RELEASE hanya mengubah reserved stock, sedangkan SHIP membuat
            transaksi outbound serta alokasi batch FEFO yang dapat diaudit.
          </p>

          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {[
              ["Open orders", openOrders, "Masih memiliki reservasi aktif"],
              ["Open reserved", openQuantity, "Belum dilepas atau dikirim"],
              ["Shipped", shippedQuantity, "Sudah keluar fisik"],
              ["Released", releasedQuantity, "Kembali menjadi available"],
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
          <div className="mb-5 flex items-end justify-between gap-4">
            <div>
              <p className="section-kicker">Event simulator</p>
              <h2 className="section-title">Terapkan lifecycle order marketplace.</h2>
            </div>
            <Pill label="Atomic RPC" tone="success" />
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
                  <h3 className="mt-1 text-xl font-semibold">Reserve order baru</h3>
                </div>
                <Pill label="RESERVED +" tone="warning" />
              </div>

              <div className="form-grid mt-6">
                <label className="field-label">
                  Channel
                  <select name="channelCode" defaultValue="SHOPEE" required>
                    <option value="SHOPEE">Shopee</option>
                    <option value="TIKTOK_SHOP">TikTok Shop</option>
                  </select>
                </label>
                <label className="field-label">
                  Waktu event
                  <CurrentDateTimeInput minimumEventAt={minimumEventAt} />
                </label>
                <label className="field-label">
                  Order reference
                  <input name="orderRef" required placeholder="SHP-ORDER-1001" />
                </label>
                <label className="field-label">
                  Event reference
                  <input name="eventRef" required placeholder="SHP-EVT-RESERVE-1001" />
                </label>
                <label className="field-label">
                  Produk
                  <select name="productId" defaultValue="" required>
                    <option value="" disabled>Pilih produk</option>
                    {products.map((product) => (
                      <option key={product.product_id} value={product.product_id}>
                        {product.sku} · available {product.available_qty}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field-label">
                  Item reference
                  <input name="sourceLineRef" required placeholder="ITEM-1" />
                </label>
                <label className="field-label">
                  Quantity
                  <input name="quantity" type="number" min="1" step="1" required placeholder="3" />
                </label>
                <label className="field-label">
                  Catatan
                  <input name="note" placeholder="Opsional" />
                </label>
              </div>

              <button className="primary-button mt-6" type="submit">Apply RESERVE</button>
            </form>

            <form action={advanceMarketplaceOrderAction} className="panel-card">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="section-kicker">Step 2</p>
                  <h3 className="mt-1 text-xl font-semibold">Release atau ship reservasi</h3>
                </div>
                <Pill label="FEFO on SHIP" tone="success" />
              </div>

              <div className="form-grid mt-6">
                <label className="field-label">
                  Event type
                  <select name="eventType" defaultValue="SHIP" required>
                    <option value="SHIP">SHIP · keluarkan fisik</option>
                    <option value="RELEASE">RELEASE · batalkan reservasi</option>
                  </select>
                </label>
                <label className="field-label">
                  Waktu event
                  <CurrentDateTimeInput minimumEventAt={minimumEventAt} />
                </label>
                <label className="field-label sm:col-span-2">
                  Reservasi aktif
                  <select name="marketplaceSelection" defaultValue="" required disabled={openReservations.length === 0}>
                    <option value="" disabled>
                      {openReservations.length === 0 ? "Tidak ada reservasi aktif" : "Pilih reservasi"}
                    </option>
                    {openReservations.map((reservation) => (
                      <option
                        key={reservation.reservation_id}
                        value={JSON.stringify({
                          channelCode: reservation.channel_code,
                          orderRef: reservation.external_order_ref,
                          productId: reservation.product_id,
                          sourceLineRef: reservation.external_item_ref,
                        })}
                      >
                        {reservation.channel_code} · {reservation.external_order_ref} · {reservation.product_sku_snapshot} · open {reservation.open_qty}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field-label">
                  Event reference
                  <input name="eventRef" required placeholder="SHP-EVT-SHIP-1001" />
                </label>
                <label className="field-label">
                  Quantity
                  <input name="quantity" type="number" min="1" step="1" required placeholder="3" />
                </label>
                <label className="field-label sm:col-span-2">
                  Catatan
                  <input name="note" placeholder="Opsional" />
                </label>
              </div>

              <button
                className="primary-button mt-6"
                type="submit"
                disabled={openReservations.length === 0}
              >
                Apply lifecycle event
              </button>
            </form>
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
                    <tr><td colSpan={8}>Belum ada order marketplace.</td></tr>
                  ) : orders.map((order) => (
                    <tr key={order.order_id}>
                      <td className="font-mono text-xs text-white">{order.external_order_ref}</td>
                      <td>{order.channel_code}</td>
                      <td>{formatNumber(order.reserved_qty)}</td>
                      <td className="font-semibold text-white">{formatNumber(order.open_qty)}</td>
                      <td>{formatNumber(order.shipped_qty)}</td>
                      <td>{formatNumber(order.released_qty)}</td>
                      <td><Pill label={order.status_code} tone={orderTone(order)} /></td>
                      <td className="whitespace-nowrap">{formatDate(order.reserved_at, true)}</td>
                    </tr>
                  ))}
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
                    <tr><td colSpan={8}>Belum ada reservasi marketplace.</td></tr>
                  ) : reservations.map((reservation) => (
                    <tr key={reservation.reservation_id}>
                      <td className="font-mono text-xs text-white">{reservation.external_item_ref}</td>
                      <td>{reservation.external_order_ref}</td>
                      <td>{reservation.product_sku_snapshot}</td>
                      <td>{formatNumber(reservation.reserved_qty)}</td>
                      <td>{formatNumber(reservation.consumed_qty)}</td>
                      <td>{formatNumber(reservation.released_qty)}</td>
                      <td className="font-semibold text-white">{formatNumber(reservation.open_qty)}</td>
                      <td><Pill label={reservation.status_code} tone={reservationTone(reservation)} /></td>
                    </tr>
                  ))}
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
                    <tr><td colSpan={6}>Belum ada event marketplace.</td></tr>
                  ) : events.map((event) => (
                    <tr key={event.event_id}>
                      <td className="font-mono text-xs text-white">{event.external_event_ref}</td>
                      <td>{event.channel_code}</td>
                      <td>
                        <Pill
                          label={event.event_type_code}
                          tone={event.event_type_code === "SHIP" ? "success" : event.event_type_code === "RELEASE" ? "danger" : "warning"}
                        />
                      </td>
                      <td className="whitespace-nowrap">{formatDate(event.occurred_at, true)}</td>
                      <td className="font-mono text-xs text-slate-400">{event.transaction_id ?? "non-physical"}</td>
                      <td>{event.note ?? "—"}</td>
                    </tr>
                  ))}
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
                    <tr><td colSpan={7}>Belum ada shipment marketplace.</td></tr>
                  ) : allocations.map((allocation) => (
                    <tr key={allocation.allocation_id}>
                      <td className="font-mono text-xs text-white">
                        {eventById.get(allocation.event_id)?.external_event_ref ?? allocation.event_id}
                      </td>
                      <td>#{allocation.allocation_no}</td>
                      <td>{allocation.product_sku_snapshot}</td>
                      <td className="font-mono text-xs">{allocation.batch_code_snapshot}</td>
                      <td>{formatDate(allocation.expiry_date_snapshot)}</td>
                      <td className="font-semibold text-white">{formatNumber(allocation.quantity_allocated)}</td>
                      <td>{allocation.source_line_ref}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
