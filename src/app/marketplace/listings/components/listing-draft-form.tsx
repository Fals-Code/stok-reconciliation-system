"use client";

import {
  useMemo,
  useState,
} from "react";

import {
  createMarketplaceListingDraftAction,
  saveMarketplaceListingDraftAction,
} from "@/app/marketplace/listings/actions";
import type {
  MarketplaceListingChannelCode,
  MarketplaceListingDraftComponent,
  MarketplaceListingTypeCode,
} from "@/app/marketplace/listings/draft";
import {
  Button,
  Field,
  Input,
  Select,
  StatusBadge,
  Textarea,
} from "@/components/ui";
import type {
  ProductInventory,
} from "@/lib/supabase-rest";

type DraftInitialValue = {
  channelCode: MarketplaceListingChannelCode;
  externalListingCode: string;
  displayName: string;
  listingTypeCode: MarketplaceListingTypeCode;
  effectiveFrom: string;
  productId: string;
  components: MarketplaceListingDraftComponent[];
  note: string;
};

type ComponentRow =
  MarketplaceListingDraftComponent & {
    key: string;
  };

function componentRows(
  components: MarketplaceListingDraftComponent[],
): ComponentRow[] {
  return components.map(
    (component, index) => ({
      ...component,
      key: `${component.productId || "empty"}-${index}`,
    }),
  );
}

export default function MarketplaceListingDraftForm({
  mode,
  products,
  intentId,
  initial,
  lockedIdentity = false,
  listingId,
  versionId,
  expectedRowVersion,
}: {
  mode: "create" | "save";
  products: ProductInventory[];
  intentId: string;
  initial: DraftInitialValue;
  lockedIdentity?: boolean;
  listingId?: string;
  versionId?: string;
  expectedRowVersion?: number;
}) {
  const [listingType, setListingType] =
    useState<MarketplaceListingTypeCode>(
      initial.listingTypeCode,
    );

  const [rows, setRows] =
    useState<ComponentRow[]>(() =>
      componentRows(initial.components),
    );

  const serializedComponents =
    useMemo(
      () =>
        JSON.stringify(
          rows.map(
            ({
              productId,
              quantity,
            }) => ({
              productId,
              quantity: Number(quantity),
            }),
          ),
        ),
      [rows],
    );

  const action =
    mode === "create"
      ? createMarketplaceListingDraftAction
      : saveMarketplaceListingDraftAction;

  function addComponent() {
    setRows((current) => [
      ...current,
      {
        key: `new-${Date.now()}-${current.length}`,
        productId:
          products[0]?.product_id ?? "",
        quantity: 1,
      },
    ]);
  }

  function updateComponent(
    key: string,
    patch: Partial<MarketplaceListingDraftComponent>,
  ) {
    setRows((current) =>
      current.map((row) =>
        row.key === key
          ? {
              ...row,
              ...patch,
            }
          : row,
      ),
    );
  }

  function removeComponent(
    key: string,
  ) {
    setRows((current) =>
      current.filter(
        (row) => row.key !== key,
      ),
    );
  }

  return (
    <form
      action={action}
      className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 sm:p-6"
      id="listing-draft-form"
    >
      <input
        name="intentId"
        type="hidden"
        value={intentId}
      />
      <input
        name="components"
        type="hidden"
        value={serializedComponents}
      />

      {listingId ? (
        <input
          name="listingId"
          type="hidden"
          value={listingId}
        />
      ) : null}

      {versionId ? (
        <input
          name="versionId"
          type="hidden"
          value={versionId}
        />
      ) : null}

      {expectedRowVersion ? (
        <input
          name="expectedRowVersion"
          type="hidden"
          value={expectedRowVersion}
        />
      ) : null}

      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
            {mode === "create"
              ? "Draft mapping"
              : "Edit draft"}
          </p>

          <h2 className="mt-1 text-lg font-semibold text-ui-text">
            {mode === "create"
              ? "Buat mapping produk"
              : "Ubah draft mapping"}
          </h2>

          <p className="mt-2 max-w-3xl text-sm leading-6 text-ui-text-muted">
            Tentukan produk yang mewakili listing marketplace.
            Bundle dipecah menjadi produk satuan ketika pesanan
            diproses. Menyimpan draft belum mengubah stok.
          </p>
        </div>

        <StatusBadge tone="neutral">
          Belum mengubah stok
        </StatusBadge>
      </div>

      <div className="mt-6 grid gap-5 sm:grid-cols-2">
        {lockedIdentity ? (
          <>
            <input
              name="channelCode"
              type="hidden"
              value={initial.channelCode}
            />
            <input
              name="externalListingCode"
              type="hidden"
              value={
                initial.externalListingCode
              }
            />
            <input
              name="listingTypeCode"
              type="hidden"
              value={listingType}
            />

            <div className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 sm:col-span-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
                Identitas listing tetap
              </p>
              <p className="mt-2 break-words text-sm font-semibold text-ui-text">
                {initial.channelCode} /{" "}
                {initial.externalListingCode} /{" "}
                {listingType === "BUNDLE"
                  ? "Bundle"
                  : "Produk tunggal"}
              </p>
              <p className="mt-1 text-xs text-ui-text-muted">
                Channel, kode listing, dan jenis mapping
                tidak dapat diganti pada versi yang sama.
              </p>
            </div>
          </>
        ) : (
          <>
            <Field
              id="listing-channel"
              label="Marketplace"
            >
              {(controlProps) => (
                <Select
                  {...controlProps}
                  defaultValue={
                    initial.channelCode
                  }
                  name="channelCode"
                  required
                >
                  <option value="SHOPEE">
                    Shopee
                  </option>
                  <option value="TIKTOK_SHOP">
                    TikTok Shop
                  </option>
                </Select>
              )}
            </Field>

            <Field
              id="listing-type"
              label="Jenis listing"
            >
              {(controlProps) => (
                <Select
                  {...controlProps}
                  name="listingTypeCode"
                  onChange={(event) =>
                    setListingType(
                      event.target
                        .value as MarketplaceListingTypeCode,
                    )
                  }
                  value={listingType}
                >
                  <option value="SINGLE">
                    Produk tunggal
                  </option>
                  <option value="BUNDLE">
                    Bundle
                  </option>
                </Select>
              )}
            </Field>

            <Field
              className="sm:col-span-2"
              description="Gunakan kode listing yang sama dengan data marketplace."
              id="external-listing-code"
              label="Kode listing marketplace"
            >
              {(controlProps) => (
                <Input
                  {...controlProps}
                  defaultValue={
                    initial.externalListingCode
                  }
                  maxLength={200}
                  name="externalListingCode"
                  placeholder="SHP-SERUM-BUNDLE-01"
                  required
                />
              )}
            </Field>
          </>
        )}

        <Field
          className="sm:col-span-2"
          id="listing-display-name"
          label="Nama listing"
        >
          {(controlProps) => (
            <Input
              {...controlProps}
              defaultValue={
                initial.displayName
              }
              maxLength={300}
              name="displayName"
              placeholder="Paket Serum dan Cleanser"
              required
            />
          )}
        </Field>

        <Field
          description="Waktu mulai mapping ini dapat dipakai untuk pesanan baru."
          id="listing-effective-from"
          label="Mulai berlaku"
        >
          {(controlProps) => (
            <Input
              {...controlProps}
              defaultValue={
                initial.effectiveFrom
              }
              name="effectiveFrom"
              required
              type="datetime-local"
            />
          )}
        </Field>

        {listingType === "SINGLE" ? (
          <Field
            id="listing-product"
            label="Produk satuan"
          >
            {(controlProps) => (
              <Select
                {...controlProps}
                defaultValue={
                  initial.productId
                }
                name="productId"
                required
              >
                <option value="">
                  Pilih produk aktif
                </option>

                {products.map(
                  (product) => (
                    <option
                      key={
                        product.product_id
                      }
                      value={
                        product.product_id
                      }
                    >
                      {product.sku} /{" "}
                      {product.name}
                    </option>
                  ),
                )}
              </Select>
            )}
          </Field>
        ) : (
          <section className="sm:col-span-2">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
              <div>
                <h3 className="text-sm font-semibold text-ui-text">
                  Isi bundle
                </h3>
                <p className="mt-1 text-xs leading-5 text-ui-text-muted">
                  Tentukan jumlah produk satuan
                  yang terdapat dalam satu listing
                  bundle.
                </p>
              </div>

              <Button
                onClick={addComponent}
                type="button"
                variant="secondary"
              >
                Tambah komponen
              </Button>
            </div>

            {rows.length === 0 ? (
              <div className="mt-4 rounded-[var(--ui-radius-md)] border border-ui-warning bg-ui-warning-subtle p-4 text-sm text-ui-warning">
                Belum ada komponen. Tambahkan minimal
                satu produk sebelum menyimpan draft
                bundle.
              </div>
            ) : (
              <div className="mt-4 space-y-3">
                {rows.map(
                  (row, index) => (
                    <div
                      className="grid gap-4 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-4 sm:grid-cols-[minmax(0,1fr)_140px_auto] sm:items-end"
                      key={row.key}
                    >
                      <Field
                        id={`bundle-product-${row.key}`}
                        label={`Produk ${index + 1}`}
                      >
                        {(controlProps) => (
                          <Select
                            {...controlProps}
                            onChange={(
                              event,
                            ) =>
                              updateComponent(
                                row.key,
                                {
                                  productId:
                                    event
                                      .target
                                      .value,
                                },
                              )
                            }
                            required
                            value={
                              row.productId
                            }
                          >
                            <option value="">
                              Pilih produk aktif
                            </option>

                            {products.map(
                              (product) => (
                                <option
                                  key={
                                    product.product_id
                                  }
                                  value={
                                    product.product_id
                                  }
                                >
                                  {
                                    product.sku
                                  }{" "}
                                  /{" "}
                                  {
                                    product.name
                                  }
                                </option>
                              ),
                            )}
                          </Select>
                        )}
                      </Field>

                      <Field
                        id={`bundle-quantity-${row.key}`}
                        label="Jumlah"
                      >
                        {(controlProps) => (
                          <Input
                            {...controlProps}
                            min={1}
                            onChange={(
                              event,
                            ) =>
                              updateComponent(
                                row.key,
                                {
                                  quantity:
                                    Number(
                                      event
                                        .target
                                        .value,
                                    ),
                                },
                              )
                            }
                            required
                            step={1}
                            type="number"
                            value={row.quantity}
                          />
                        )}
                      </Field>

                      <Button
                        onClick={() =>
                          removeComponent(
                            row.key,
                          )
                        }
                        type="button"
                        variant="ghost"
                      >
                        Hapus
                      </Button>
                    </div>
                  ),
                )}
              </div>
            )}
          </section>
        )}

        <Field
          className="sm:col-span-2"
          description="Opsional. Catatan ini membantu penelusuran alasan perubahan mapping."
          id="listing-note"
          label="Catatan"
        >
          {(controlProps) => (
            <Textarea
              {...controlProps}
              defaultValue={initial.note}
              maxLength={2000}
              name="note"
              placeholder="Alasan membuat atau mengubah mapping."
              rows={3}
            />
          )}
        </Field>
      </div>

      <div className="mt-6 flex flex-wrap items-center gap-3 border-t border-ui-border pt-5">
        <Button
          disabled={
            listingType === "BUNDLE" &&
            rows.length === 0
          }
          type="submit"
        >
          {mode === "create"
            ? "Simpan draft mapping"
            : "Simpan perubahan"}
        </Button>

        <p className="text-xs leading-5 text-ui-text-muted">
          Draft harus diperiksa melalui preview sebelum
          dapat diaktifkan.
        </p>
      </div>
    </form>
  );
}