"use client";

import { useMemo, useState } from "react";

import {
  createMarketplaceListingDraftAction,
  saveMarketplaceListingDraftAction,
} from "@/app/marketplace/listings/actions";
import type {
  MarketplaceListingChannelCode,
  MarketplaceListingDraftComponent,
  MarketplaceListingTypeCode,
} from "@/app/marketplace/listings/draft";
import type { ProductInventory } from "@/lib/supabase-rest";

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

type ComponentRow = MarketplaceListingDraftComponent & {
  key: string;
};

function componentRows(
  components: MarketplaceListingDraftComponent[],
): ComponentRow[] {
  return components.map((component, index) => ({
    ...component,
    key: `${component.productId || "empty"}-${index}`,
  }));
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
    useState<MarketplaceListingTypeCode>(initial.listingTypeCode);
  const [rows, setRows] = useState<ComponentRow[]>(() =>
    componentRows(initial.components),
  );

  const serializedComponents = useMemo(
    () =>
      JSON.stringify(
        rows.map(({ productId, quantity }) => ({
          productId,
          quantity: Number(quantity),
        })),
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
        productId: products[0]?.product_id ?? "",
        quantity: 1,
      },
    ]);
  }

  function updateComponent(
    key: string,
    patch: Partial<MarketplaceListingDraftComponent>,
  ) {
    setRows((current) =>
      current.map((row) => (row.key === key ? { ...row, ...patch } : row)),
    );
  }

  function removeComponent(key: string) {
    setRows((current) => current.filter((row) => row.key !== key));
  }

  return (
    <form action={action} className="panel-card" id="listing-draft-form">
      <input name="intentId" type="hidden" value={intentId} />
      <input
        name="components"
        type="hidden"
        value={serializedComponents}
      />

      {listingId ? (
        <input name="listingId" type="hidden" value={listingId} />
      ) : null}
      {versionId ? (
        <input name="versionId" type="hidden" value={versionId} />
      ) : null}
      {expectedRowVersion ? (
        <input
          name="expectedRowVersion"
          type="hidden"
          value={expectedRowVersion}
        />
      ) : null}

      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="section-kicker">
            {mode === "create" ? "Draft mapping" : "Edit draft"}
          </p>
          <h2 className="mt-2 text-xl font-semibold">
            {mode === "create"
              ? "Buat listing atau versi mapping baru"
              : "Ubah draft sebelum aktivasi"}
          </h2>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
            Draft tidak membuat reservasi, batch, transaksi, ledger, atau
            perubahan saldo. Dampak fisik baru mungkin terjadi setelah event
            order memakai mapping aktif.
          </p>
        </div>
        <span className="status-pill status-info">Stock-neutral</span>
      </div>

      <div className="form-grid mt-6">
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
              value={initial.externalListingCode}
            />
            <input
              name="listingTypeCode"
              type="hidden"
              value={listingType}
            />
            <div className="rounded-2xl border border-white/10 bg-white/[0.025] p-4 sm:col-span-2">
              <p className="text-xs uppercase tracking-[0.16em] text-slate-500">
                Identitas listing tetap
              </p>
              <p className="mt-2 font-mono text-sm text-white">
                {initial.channelCode} / {initial.externalListingCode} /{" "}
                {listingType}
              </p>
            </div>
          </>
        ) : (
          <>
            <label className="field-label">
              Channel
              <select
                defaultValue={initial.channelCode}
                name="channelCode"
                required
              >
                <option value="SHOPEE">Shopee</option>
                <option value="TIKTOK_SHOP">TikTok Shop</option>
              </select>
            </label>

            <label className="field-label">
              Jenis listing
              <select
                name="listingTypeCode"
                onChange={(event) =>
                  setListingType(
                    event.target.value as MarketplaceListingTypeCode,
                  )
                }
                value={listingType}
              >
                <option value="SINGLE">Produk tunggal</option>
                <option value="BUNDLE">Bundle</option>
              </select>
            </label>

            <label className="field-label sm:col-span-2">
              Kode listing marketplace
              <input
                defaultValue={initial.externalListingCode}
                maxLength={200}
                name="externalListingCode"
                placeholder="SHP-SERUM-BUNDLE-01"
                required
              />
            </label>
          </>
        )}

        <label className="field-label sm:col-span-2">
          Nama listing
          <input
            defaultValue={initial.displayName}
            maxLength={300}
            name="displayName"
            placeholder="Paket Serum dan Cleanser"
            required
          />
        </label>

        <label className="field-label">
          Mulai berlaku
          <input
            defaultValue={initial.effectiveFrom}
            name="effectiveFrom"
            required
            type="datetime-local"
          />
        </label>

        {listingType === "SINGLE" ? (
          <label className="field-label">
            Produk satuan
            <select
              defaultValue={initial.productId}
              name="productId"
              required
            >
              <option value="">Pilih produk aktif</option>
              {products.map((product) => (
                <option key={product.product_id} value={product.product_id}>
                  {product.sku} / {product.name}
                </option>
              ))}
            </select>
          </label>
        ) : (
          <div className="sm:col-span-2">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="field-label">Komponen resep bundle</p>
                <p className="mt-1 text-xs leading-5 text-slate-500">
                  Quantity adalah jumlah produk satuan untuk satu listing
                  bundle.
                </p>
              </div>
              <button
                className="nav-link"
                onClick={addComponent}
                type="button"
              >
                Tambah komponen
              </button>
            </div>

            <div className="mt-3 space-y-3">
              {rows.length === 0 ? (
                <div className="rounded-2xl border border-amber-400/20 bg-amber-400/[0.055] p-4 text-sm text-amber-100">
                  Belum ada komponen. Tambahkan minimal satu produk sebelum
                  menyimpan draft bundle.
                </div>
              ) : (
                rows.map((row, index) => (
                  <div
                    className="grid gap-3 rounded-2xl border border-white/10 bg-white/[0.025] p-4 sm:grid-cols-[1fr_140px_auto]"
                    key={row.key}
                  >
                    <label className="field-label">
                      Produk komponen {index + 1}
                      <select
                        onChange={(event) =>
                          updateComponent(row.key, {
                            productId: event.target.value,
                          })
                        }
                        required
                        value={row.productId}
                      >
                        <option value="">Pilih produk aktif</option>
                        {products.map((product) => (
                          <option
                            key={product.product_id}
                            value={product.product_id}
                          >
                            {product.sku} / {product.name}
                          </option>
                        ))}
                      </select>
                    </label>

                    <label className="field-label">
                      Quantity
                      <input
                        min={1}
                        onChange={(event) =>
                          updateComponent(row.key, {
                            quantity: Number(event.target.value),
                          })
                        }
                        required
                        step={1}
                        type="number"
                        value={row.quantity}
                      />
                    </label>

                    <button
                      className="nav-link self-end"
                      onClick={() => removeComponent(row.key)}
                      type="button"
                    >
                      Hapus
                    </button>
                  </div>
                ))
              )}
            </div>
          </div>
        )}

        <label className="field-label sm:col-span-2">
          Catatan audit
          <textarea
            defaultValue={initial.note}
            maxLength={2000}
            name="note"
            placeholder="Alasan membuat atau mengubah versi mapping."
            rows={3}
          />
        </label>
      </div>

      <div className="mt-6 flex flex-wrap items-center gap-3">
        <button
          className="primary-button"
          disabled={listingType === "BUNDLE" && rows.length === 0}
          type="submit"
        >
          {mode === "create" ? "Simpan draft mapping" : "Simpan perubahan"}
        </button>
        <p className="text-xs leading-5 text-slate-500">
          Aktivasi dilakukan melalui preview authoritative terpisah.
        </p>
      </div>
    </form>
  );
}