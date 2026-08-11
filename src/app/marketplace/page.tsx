import { LiveQueryControls } from "@/components/ui/live-query-controls";
import Link from "next/link";

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
  type MarketplaceOrder,
} from "@/lib/supabase-rest";

export const dynamic =
  "force-dynamic";

type SearchParams = Record<
  string,
  string | string[] | undefined
>;

const numberFormatter =
  new Intl.NumberFormat("id-ID");

function first(
  value: SearchParams[string],
) {
  return Array.isArray(value)
    ? value[0]
    : value;
}

function quantity(
  value: number,
) {
  return numberFormatter.format(
    Number(value),
  );
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
      day: "2-digit",
      month: "short",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    },
  ).format(date);
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
): {
  key:
    | "OPEN"
    | "SHIPPED"
    | "CANCELLED"
    | "CLOSED";
  label: string;
  tone:
    | "neutral"
    | "selected"
    | "warning"
    | "danger";
} {
  if (
    order.status_code ===
    "CANCELLED"
  ) {
    return {
      key: "CANCELLED",
      label: "Dibatalkan",
      tone: "danger",
    };
  }

  if (
    Number(order.open_qty) > 0
  ) {
    return {
      key: "OPEN",
      label: "Dalam proses",
      tone: "warning",
    };
  }

  if (
    order.status_code ===
      "SHIPPED" ||
    Number(
      order.shipped_qty,
    ) > 0
  ) {
    return {
      key: "SHIPPED",
      label:
        order.status_code ===
        "CLOSED_MIXED"
          ? "Selesai sebagian"
          : "Terkirim",
      tone:
        order.status_code ===
        "CLOSED_MIXED"
          ? "warning"
          : "selected",
    };
  }

  return {
    key: "CLOSED",
    label: "Selesai",
    tone: "neutral",
  };
}

export default async function MarketplacePage({
  searchParams,
}: {
  searchParams:
    Promise<SearchParams>;
}) {
  const [session, query] =
    await Promise.all([
      requireAdminSession(),
      searchParams,
    ]);

  let marketplace:
    Awaited<
      ReturnType<
        typeof getMarketplaceData
      >
    > | null = null;

  let loadFailed = false;

  try {
    marketplace =
      await getMarketplaceData(
        session.profile
          .organization_id,
      );
  } catch {
    loadFailed = true;
  }

  const orders =
    marketplace?.orders ?? [];

  const q =
    first(query.q)
      ?.trim()
      .toLowerCase() ?? "";

  const channel =
    first(query.channel) ??
    "ALL";

  const status =
    first(query.status) ??
    "ALL";

  const filteredOrders =
    orders.filter(
      (order) => {
        const presentation =
          orderStatus(order);

        if (
          channel !== "ALL" &&
          order.channel_code !==
            channel
        ) {
          return false;
        }

        if (
          status !== "ALL" &&
          presentation.key !==
            status
        ) {
          return false;
        }

        if (
          q &&
          ![
            order.external_order_ref,
            order.channel_code,
            presentation.label,
          ]
            .join(" ")
            .toLowerCase()
            .includes(q)
        ) {
          return false;
        }

        return true;
      },
    );

  const openOrders =
    orders.filter(
      (order) =>
        Number(
          order.open_qty,
        ) > 0,
    );

  const openQuantity =
    orders.reduce(
      (sum, order) =>
        sum +
        Number(
          order.open_qty,
        ),
      0,
    );

  const shippedQuantity =
    orders.reduce(
      (sum, order) =>
        sum +
        Number(
          order.shipped_qty,
        ),
      0,
    );

  return (
    <AppShell
      profile={session.profile}
    >
      <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          description="Pantau pesanan marketplace dan buka detail saat ada pekerjaan yang perlu ditindaklanjuti."
          eyebrow="Pesanan"
          title="Pesanan"
        />

        <OrderWorkspaceTabs active="orders" />

        {loadFailed ? (
          <Alert
            className="mt-6"
            title="Pesanan belum dapat dimuat"
            tone="danger"
          >
            Coba muat ulang halaman.
            Tidak ada perubahan stok yang
            dilakukan.
          </Alert>
        ) : (
          <>
            <section
              aria-label="Ringkasan pesanan"
              className="mt-4 grid gap-3 sm:grid-cols-3"
            >
              <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border border-l-2 border-l-ui-warning bg-ui-surface px-4 py-3">
                <p className="text-sm font-medium text-ui-text-muted">
                  Perlu diproses
                </p>
                <p className="ui-number text-xl font-semibold tracking-tight text-ui-text">
                  {quantity(openOrders.length)}
                </p>
              </div>

              <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-4 py-3">
                <p className="text-sm font-medium text-ui-text-muted">
                  Belum dikirim
                </p>
                <p className="ui-number text-xl font-semibold tracking-tight text-ui-text">
                  {quantity(openQuantity)}
                </p>
              </div>

              <div className="flex items-center justify-between gap-4 rounded-[var(--ui-radius-lg)] border border-ui-border border-l-2 border-l-ui-primary bg-ui-surface px-4 py-3">
                <p className="text-sm font-medium text-ui-text-muted">
                  Sudah dikirim
                </p>
                <p className="ui-number text-xl font-semibold tracking-tight text-ui-primary">
                  {quantity(shippedQuantity)}
                </p>
              </div>
            </section>

            <section aria-labelledby="orders-heading" className="mt-5">
              <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center">
                <div className="min-w-0">
                  <h2
                    className="text-lg font-semibold text-ui-text"
                    id="orders-heading"
                  >
                    Daftar pesanan
                  </h2>

                </div>

                <div className="w-full lg:w-auto lg:min-w-[42rem]">
                  <LiveQueryControls
                    bare
                    compact
                    hideIdleStatus
                    hideInactiveClear
                    fields={[
                      {
                        kind: "search",
                        name: "q",
                        ariaLabel: "Cari pesanan",
                        placeholder: "Cari nomor pesanan",
                      },
                      {
                        kind: "select",
                        name: "channel",
                        ariaLabel: "Filter kanal pesanan",
                        options: [
                          { value: "", label: "Semua kanal" },
                          { value: "SHOPEE", label: "Shopee" },
                          { value: "TIKTOK_SHOP", label: "TikTok Shop" },
                        ],
                      },
                      {
                        kind: "select",
                        name: "status",
                        ariaLabel: "Filter status pesanan",
                        options: [
                          { value: "", label: "Semua status" },
                          { value: "OPEN", label: "Dalam proses" },
                          { value: "SHIPPED", label: "Terkirim" },
                          { value: "CANCELLED", label: "Dibatalkan" },
                          { value: "CLOSED", label: "Selesai" },
                        ],
                      },
                    ]}
                  />
                </div>
              </div>

              {filteredOrders.length === 0 ? (
                <EmptyState
                  className="mt-3 py-5"
                  description={
                    orders.length === 0
                      ? "Pesanan akan muncul setelah data marketplace diterima."
                      : "Tidak ada pesanan yang cocok dengan pencarian atau filter ini."
                  }
                  title={
                    orders.length === 0
                      ? "Belum ada pesanan"
                      : "Tidak ada hasil"
                  }
                />
              ) : (
                <div className="mt-4 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface">
                  <div className="hidden grid-cols-[minmax(0,1fr)_auto] items-center gap-6 border-b border-ui-border bg-ui-surface-subtle px-5 py-2.5 md:grid">
                    <p className="text-xs font-semibold text-ui-text-muted">
                      Pesanan
                    </p>
                    <p className="pr-7 text-xs font-semibold text-ui-text-muted">
                      Status
                    </p>
                  </div>

                  <div className="divide-y divide-ui-border">
                    {filteredOrders.map((order) => {
                      const presentation = orderStatus(order);

                      return (
                        <Link
                          className="group grid gap-3 px-5 py-4 hover:bg-ui-surface-subtle md:grid-cols-[minmax(0,1fr)_auto] md:items-center md:gap-6"
                          href={`/marketplace/${encodeURIComponent(order.order_id)}`}
                          key={order.order_id}
                        >
                          <div className="min-w-0">
                            <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                              <p className="ui-code truncate text-sm font-semibold text-ui-text">
                                {order.external_order_ref}
                              </p>
                              <span className="text-xs font-semibold text-ui-text-muted">
                                {channelLabel(order.channel_code)}
                              </span>
                            </div>

                            <p className="mt-1.5 text-[0.8125rem] font-medium text-ui-text-muted">
                              {quantity(order.open_qty)} unit terbuka
                              {"\u00B7"} {quantity(order.shipped_qty)} unit dikirim
                            </p>

                            <p className="mt-1 text-xs text-ui-text-muted">
                              Diperbarui {formatDate(order.updated_at)}
                            </p>
                          </div>

                          <div className="flex items-center justify-between gap-3 md:justify-end">
                            <StatusBadge tone={presentation.tone}>
                              {presentation.label}
                            </StatusBadge>

                            <span
                              aria-hidden="true"
                              className="text-base text-ui-text-muted transition-transform group-hover:translate-x-0.5 motion-reduce:transition-none"
                            >
                              {"\u2192"}
                            </span>
                          </div>
                        </Link>
                      );
                    })}
                  </div>
                </div>
              )}            </section>
          </>
        )}
      </div>
    </AppShell>
  );
}