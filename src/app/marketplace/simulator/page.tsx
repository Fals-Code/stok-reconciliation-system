import Link from "next/link";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  Alert,
  Button,
  Field,
  Input,
  Select,
  StatusBadge,
  Textarea,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  getMarketplaceListingSimulatorData,
} from "@/lib/supabase-rest";

import {
  advanceMarketplaceOrderAction,
  reserveMarketplaceOrderAction,
} from "./actions";

export const dynamic =
  "force-dynamic";

const numberFormatter =
  new Intl.NumberFormat("id-ID");

function formatNumber(
  value: number,
) {
  return numberFormatter.format(
    Number(value),
  );
}

function toJakartaDateTimeLocal(
  value: Date,
) {
  const parts =
    new Intl.DateTimeFormat(
      "en-CA",
      {
        timeZone: "Asia/Jakarta",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      },
    ).formatToParts(value);

  const values =
    Object.fromEntries(
      parts.map((part) => [
        part.type,
        part.value,
      ]),
    );

  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

function channelLabel(
  code: string,
) {
  if (
    code === "TIKTOK_SHOP"
  ) {
    return "TikTok Shop";
  }

  if (code === "SHOPEE") {
    return "Shopee";
  }

  return code;
}

export default async function MarketplaceSimulatorPage({
  searchParams,
}: {
  searchParams: Promise<{
    success?: string;
    error?: string;
  }>;
}) {
  const [session, feedback] =
    await Promise.all([
      requireAdminSession(),
      searchParams,
    ]);

  let simulator:
    Awaited<
      ReturnType<
        typeof getMarketplaceListingSimulatorData
      >
    >;

  try {
    simulator =
      await getMarketplaceListingSimulatorData(
        session.profile
          .organization_id,
      );
  } catch {
    return (
      <AppShell
        profile={session.profile}
      >
        <div className="mx-auto w-full max-w-[1000px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader
            description="Alat Admin untuk menguji kontrak pesanan marketplace."
            eyebrow="Pengaturan / Marketplace"
            title="Simulator Pesanan"
          />

          <Alert
            className="mt-6"
            title="Data simulator belum dapat dimuat"
            tone="danger"
          >
            Tidak ada perintah pesanan atau perubahan stok yang dijalankan.
          </Alert>

          <Link
            className="mt-5 inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
            href="/settings"
          >
            ← Kembali ke Pengaturan
          </Link>
        </div>
      </AppShell>
    );
  }

  const {
    listingCatalog,
    normalizations,
    components,
  } = simulator;

  const activeListings =
    listingCatalog.filter(
      (listing) =>
        listing.status_code ===
          "ACTIVE" &&
        listing
          .mapping_readiness_code ===
          "PUBLISHED",
    );

  const shipCandidates =
    components.filter(
      (component) =>
        Number(
          component
            .open_reserved_quantity,
        ) > 0,
    );

  const now =
    toJakartaDateTimeLocal(
      new Date(),
    );

  return (
    <AppShell
      profile={session.profile}
    >
      <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          action={
            <div className="flex flex-wrap justify-end gap-2">
              <Link
                className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text hover:border-ui-border-strong hover:bg-ui-surface-subtle"
                href="/marketplace/listings"
              >
                Mapping Produk
              </Link>

              <Link
                className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text hover:border-ui-border-strong hover:bg-ui-surface-subtle"
                href="/marketplace/import"
              >
                Import Pesanan
              </Link>
            </div>
          }
          description="Listing marketplace dinormalisasi sebelum reservasi dan shipment. Simulator ini hanya alat Admin/demo dan tetap memakai normalized event contract yang sama."
          eyebrow="Pengaturan / Marketplace"
          title="Simulator Pesanan"
        />

        <div className="mt-4">
          <Link
            className="inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
            href="/settings"
          >
            ← Kembali ke Pengaturan
          </Link>
        </div>

        <Alert
          className="mt-6"
          title="Dampak stok mengikuti lifecycle marketplace"
          tone="info"
        >
          Reservasi tidak mengubah stok fisik. Shopee mengurangi stok saat SHIPPED dan TikTok Shop saat IN_TRANSIT melalui FEFO otomatis.
        </Alert>

        {feedback.success ? (
          <Alert
            className="mt-4"
            title="Simulator selesai"
            tone="success"
          >
            {feedback.success}
          </Alert>
        ) : null}

        {feedback.error ? (
          <Alert
            className="mt-4"
            title="Simulator belum berhasil"
            tone="danger"
          >
            {feedback.error}
          </Alert>
        ) : null}

        <dl className="mt-6 grid gap-3 sm:grid-cols-3">
          <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4">
            <dt className="text-xs font-medium text-ui-text-muted">
              Mapping aktif
            </dt>
            <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
              {formatNumber(
                activeListings.length,
              )}
            </dd>
          </div>

          <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4">
            <dt className="text-xs font-medium text-ui-text-muted">
              Reservasi terbuka
            </dt>
            <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
              {formatNumber(
                shipCandidates.length,
              )}
            </dd>
          </div>

          <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4">
            <dt className="text-xs font-medium text-ui-text-muted">
              Snapshot normalisasi
            </dt>
            <dd className="ui-number mt-1 text-xl font-semibold text-ui-text">
              {formatNumber(
                normalizations.length,
              )}
            </dd>
          </div>
        </dl>

        <section
          className="mt-8"
          id="simulator"
        >
          <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
            Simulasi event
          </p>

          <h2 className="mt-1 text-lg font-semibold text-ui-text">
            Uji alur normalized marketplace event
          </h2>

          <p className="mt-2 max-w-3xl text-sm leading-6 text-ui-text-muted">
            Gunakan referensi event unik. Replay event yang sama tidak boleh menghasilkan domain effect kedua.
          </p>

          <div className="mt-5 grid gap-5 xl:grid-cols-2">
            <form
              action={
                reserveMarketplaceOrderAction
              }
              className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 sm:p-6"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
                    Langkah 1
                  </p>

                  <h3 className="mt-1 text-lg font-semibold text-ui-text">
                    Reserve listing marketplace
                  </h3>
                </div>

                <StatusBadge tone="warning">
                  Stock-neutral
                </StatusBadge>
              </div>

              <p className="mt-2 text-sm leading-6 text-ui-text-muted">
                Mapping aktif diubah menjadi komponen produk sebelum reservasi dibuat.
              </p>

              <div className="mt-5 grid gap-4 sm:grid-cols-2">
                <Field
                  className="sm:col-span-2"
                  id="marketplace-listing-selection"
                  label="Listing marketplace"
                >
                  {(controlProps) => (
                    <Select
                      {...controlProps}
                      defaultValue=""
                      disabled={
                        activeListings.length ===
                        0
                      }
                      name="marketplaceListingSelection"
                      required
                    >
                      <option
                        disabled
                        value=""
                      >
                        {activeListings.length ===
                        0
                          ? "Belum ada mapping aktif"
                          : "Pilih listing"}
                      </option>

                      {activeListings.map(
                        (listing) => (
                          <option
                            key={
                              listing.listing_id
                            }
                            value={JSON.stringify(
                              {
                                channelCode:
                                  listing.channel_code,
                                externalListingCode:
                                  listing.external_listing_code,
                                listingName:
                                  listing.display_name,
                                listingType:
                                  listing.listing_type_code,
                              },
                            )}
                          >
                            {channelLabel(
                              listing.channel_code,
                            )}{" "}
                            ·{" "}
                            {
                              listing.external_listing_code
                            }{" "}
                            ·{" "}
                            {
                              listing.display_name
                            }{" "}
                            ·{" "}
                            {
                              listing.listing_type_code
                            }{" "}
                            v
                            {
                              listing.current_version
                            }
                          </option>
                        ),
                      )}
                    </Select>
                  )}
                </Field>

                <Field
                  id="reserve-occurred-at"
                  label="Waktu event"
                >
                  {(controlProps) => (
                    <Input
                      {...controlProps}
                      defaultValue={now}
                      name="occurredAt"
                      required
                      type="datetime-local"
                    />
                  )}
                </Field>

                <Field
                  id="reserve-order-ref"
                  label="Referensi pesanan"
                >
                  {(controlProps) => (
                    <Input
                      {...controlProps}
                      name="orderRef"
                      placeholder="ORD-DEMO-001"
                      required
                    />
                  )}
                </Field>

                <Field
                  description="Menjadi bagian identitas idempotensi."
                  id="reserve-event-ref"
                  label="Referensi event"
                >
                  {(controlProps) => (
                    <Input
                      {...controlProps}
                      name="eventRef"
                      placeholder="EVT-RESERVE-001"
                      required
                    />
                  )}
                </Field>

                <Field
                  id="reserve-source-line"
                  label="Referensi baris"
                >
                  {(controlProps) => (
                    <Input
                      {...controlProps}
                      name="sourceLineRef"
                      placeholder="LINE-1"
                      required
                    />
                  )}
                </Field>

                <Field
                  id="reserve-listing-quantity"
                  label="Jumlah listing"
                >
                  {(controlProps) => (
                    <Input
                      {...controlProps}
                      min={1}
                      name="listingQuantity"
                      required
                      step={1}
                      type="number"
                    />
                  )}
                </Field>

                <Field
                  className="sm:col-span-2"
                  id="reserve-note"
                  label="Catatan"
                >
                  {(controlProps) => (
                    <Textarea
                      {...controlProps}
                      name="note"
                      placeholder="Opsional"
                      rows={3}
                    />
                  )}
                </Field>
              </div>

              <Button
                className="mt-5"
                disabled={
                  activeListings.length ===
                  0
                }
                type="submit"
              >
                Simulasikan reservasi
              </Button>
            </form>

            <form
              action={
                advanceMarketplaceOrderAction
              }
              className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 sm:p-6"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
                    Langkah 2
                  </p>

                  <h3 className="mt-1 text-lg font-semibold text-ui-text">
                    Ship komponen hasil ekspansi
                  </h3>
                </div>

                <StatusBadge tone="danger">
                  Mengubah stok fisik
                </StatusBadge>
              </div>

              <p className="mt-2 text-sm leading-6 text-ui-text-muted">
                Shipment memakai canonical component dan batch FEFO dipilih otomatis.
              </p>

              <div className="mt-5 grid gap-4 sm:grid-cols-2">
                <Field
                  className="sm:col-span-2"
                  id="marketplace-component-selection"
                  label="Komponen pesanan"
                >
                  {(controlProps) => (
                    <Select
                      {...controlProps}
                      defaultValue=""
                      disabled={
                        shipCandidates.length ===
                        0
                      }
                      name="marketplaceSelection"
                      required
                    >
                      <option
                        disabled
                        value=""
                      >
                        {shipCandidates.length ===
                        0
                          ? "Belum ada reservasi terbuka"
                          : "Pilih komponen"}
                      </option>

                      {shipCandidates.map(
                        (component) => (
                          <option
                            key={
                              component.source_component_id
                            }
                            value={JSON.stringify(
                              {
                                channelCode:
                                  component.channel_code,
                                orderRef:
                                  component.external_order_ref,
                                orderSourceLineRef:
                                  component.source_line_ref,
                                componentNo:
                                  component.component_no,
                              },
                            )}
                          >
                            {
                              component.external_order_ref
                            }{" "}
                            ·{" "}
                            {
                              component.external_listing_code_snapshot
                            }{" "}
                            · C
                            {
                              component.component_no
                            }{" "}
                            ·{" "}
                            {
                              component.product_sku_snapshot
                            }{" "}
                            · terbuka{" "}
                            {formatNumber(
                              component.open_reserved_quantity,
                            )}
                          </option>
                        ),
                      )}
                    </Select>
                  )}
                </Field>

                <Field
                  id="ship-occurred-at"
                  label="Waktu event"
                >
                  {(controlProps) => (
                    <Input
                      {...controlProps}
                      defaultValue={now}
                      name="occurredAt"
                      required
                      type="datetime-local"
                    />
                  )}
                </Field>

                <Field
                  id="ship-event-ref"
                  label="Referensi event"
                >
                  {(controlProps) => (
                    <Input
                      {...controlProps}
                      name="eventRef"
                      placeholder="EVT-SHIP-001"
                      required
                    />
                  )}
                </Field>

                <Field
                  id="ship-quantity"
                  label="Jumlah dikirim"
                >
                  {(controlProps) => (
                    <Input
                      {...controlProps}
                      min={1}
                      name="quantity"
                      required
                      step={1}
                      type="number"
                    />
                  )}
                </Field>

                <Field
                  className="sm:col-span-2"
                  id="ship-note"
                  label="Catatan"
                >
                  {(controlProps) => (
                    <Textarea
                      {...controlProps}
                      name="note"
                      placeholder="Opsional"
                      rows={3}
                    />
                  )}
                </Field>
              </div>

              <Button
                className="mt-5"
                disabled={
                  shipCandidates.length ===
                  0
                }
                type="submit"
                variant="danger"
              >
                Simulasikan shipment
              </Button>
            </form>
          </div>
        </section>

        <section className="mt-8">
          <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
            Audit hasil
          </p>

          <h2 className="mt-1 text-lg font-semibold text-ui-text">
            Snapshot komponen pesanan
          </h2>

          <p className="mt-2 text-sm leading-6 text-ui-text-muted">
            Pesanan lama tetap menyimpan mapping version yang dipakai saat normalisasi.
          </p>

          {components.length === 0 ? (
            <div className="mt-4 rounded-[var(--ui-radius-lg)] border border-dashed border-ui-border px-5 py-8 text-center">
              <p className="font-semibold text-ui-text">
                Belum ada snapshot komponen
              </p>
              <p className="mt-1 text-sm text-ui-text-muted">
                Jalankan reservasi untuk melihat hasil ekspansi listing.
              </p>
            </div>
          ) : (
            <div className="mt-4 overflow-x-auto rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface">
              <table className="w-full min-w-[900px] text-left text-sm">
                <thead className="border-b border-ui-border bg-ui-surface-subtle text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
                  <tr>
                    <th className="px-4 py-3">
                      Pesanan
                    </th>
                    <th className="px-4 py-3">
                      Listing
                    </th>
                    <th className="px-4 py-3">
                      Mapping
                    </th>
                    <th className="px-4 py-3">
                      Produk
                    </th>
                    <th className="px-4 py-3 text-right">
                      Terbuka
                    </th>
                    <th className="px-4 py-3 text-right">
                      Terkirim
                    </th>
                  </tr>
                </thead>

                <tbody className="divide-y divide-ui-border">
                  {components.map(
                    (component) => (
                      <tr
                        key={
                          component.source_component_id
                        }
                      >
                        <td className="ui-code px-4 py-4 text-xs font-semibold text-ui-text">
                          {
                            component.external_order_ref
                          }
                        </td>

                        <td className="px-4 py-4">
                          <p className="ui-code text-xs text-ui-text">
                            {
                              component.external_listing_code_snapshot
                            }
                          </p>

                          <p className="mt-1 text-xs text-ui-text-muted">
                            {
                              component.listing_name_snapshot
                            }
                          </p>
                        </td>

                        <td className="px-4 py-4">
                          <StatusBadge tone="neutral">
                            {`${component.listing_type_code_snapshot} v${component.mapping_version}`}
                          </StatusBadge>
                        </td>

                        <td className="px-4 py-4">
                          <p className="ui-code text-xs font-semibold text-ui-text">
                            {
                              component.product_sku_snapshot
                            }
                          </p>

                          <p className="mt-1 text-xs text-ui-text-muted">
                            {
                              component.product_name_snapshot
                            }
                          </p>
                        </td>

                        <td className="ui-number px-4 py-4 text-right text-ui-text">
                          {formatNumber(
                            component.open_reserved_quantity,
                          )}
                        </td>

                        <td className="ui-number px-4 py-4 text-right text-ui-text">
                          {formatNumber(
                            component.shipped_quantity,
                          )}
                        </td>
                      </tr>
                    ),
                  )}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <details className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
          <summary className="cursor-pointer text-sm font-semibold text-ui-text">
            Detail normalisasi teknis
          </summary>

          <div className="mt-4 space-y-3">
            {normalizations.length ===
            0 ? (
              <p className="text-sm text-ui-text-muted">
                Belum ada normalisasi.
              </p>
            ) : (
              normalizations.map(
                (row) => (
                  <div
                    className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 text-xs leading-5 text-ui-text-muted"
                    key={
                      row.source_component_id
                    }
                  >
                    <p className="ui-code font-semibold text-ui-text">
                      {
                        row.external_order_ref_snapshot
                      }{" "}
                      /{" "}
                      {
                        row.external_listing_code_snapshot
                      }
                    </p>

                    <p className="mt-1">
                      {
                        row.listing_type_code_snapshot
                      }{" "}
                      v
                      {
                        row.mapping_version
                      }{" "}
                      · komponen{" "}
                      {
                        row.component_no
                      }{" "}
                      ·{" "}
                      {
                        row.product_sku_snapshot
                      }{" "}
                      ·{" "}
                      {
                        row.expanded_quantity
                      }{" "}
                      unit
                    </p>
                  </div>
                ),
              )
            )}
          </div>
        </details>
      </div>
    </AppShell>
  );
}